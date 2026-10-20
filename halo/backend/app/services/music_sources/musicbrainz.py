"""MusicBrainz: canonical music metadata (artists, recordings, releases, labels, ISRCs).

https://musicbrainz.org/doc/MusicBrainz_API (data is CC0). Rules followed here:
* at most one request per second per server process (shared lock + spacing),
* a descriptive User-Agent with contact details,
* responses cached (metadata changes slowly), so repeat lookups don't hit the service.

Halo uses MusicBrainz to identify what a YouTube upload actually is (the canonical recording,
album, release date, label, ISRC, genres) and to resolve artist MBIDs for ListenBrainz.
"""

from __future__ import annotations

import asyncio
import hashlib
import logging
import re
import time
from typing import Any

import httpx
from pydantic import BaseModel, Field

from app.core.cache import KeyValueStore

logger = logging.getLogger("halo.musicbrainz")

CACHE_TTL_SECONDS = 30 * 24 * 3600
MIN_INTERVAL_SECONDS = 1.05
MATCH_THRESHOLD = 85  # MusicBrainz search score (0-100) needed to trust a match


class MusicBrainzUnavailableError(Exception):
    pass


class ArtistCredit(BaseModel):
    name: str
    mbid: str | None = None
    join_phrase: str = ""


class Label(BaseModel):
    name: str
    mbid: str | None = None
    catalog_number: str | None = None


class ReleaseInfo(BaseModel):
    mbid: str
    title: str
    date: str | None = None
    country: str | None = None
    status: str | None = None
    release_group_mbid: str | None = None
    release_group_type: str | None = None
    labels: list[Label] = Field(default_factory=list)
    cover_art_url: str | None = None


class CanonicalRecording(BaseModel):
    """What a song really is, according to MusicBrainz."""

    recording_mbid: str
    title: str
    artist_credit: list[ArtistCredit]
    length_ms: int | None = None
    first_release_date: str | None = None
    isrcs: list[str] = Field(default_factory=list)
    genres: list[str] = Field(default_factory=list)
    releases: list[ReleaseInfo] = Field(default_factory=list)
    match_score: int = 0
    musicbrainz_url: str
    source: str = "MusicBrainz"

    @property
    def artist_name(self) -> str:
        return "".join(f"{c.name}{c.join_phrase}" for c in self.artist_credit)


class ArtistInfo(BaseModel):
    mbid: str
    name: str
    sort_name: str | None = None
    type: str | None = None
    country: str | None = None
    area: str | None = None
    disambiguation: str | None = None
    begin: str | None = None
    end: str | None = None
    genres: list[str] = Field(default_factory=list)
    match_score: int = 0
    musicbrainz_url: str


_NOISE = re.compile(
    r"\s*[\(\[][^)\]]*(official|video|audio|lyric|lyrical|visuali[sz]er|hd|4k|full song|"
    r"remaster(ed)?|live|from)[^)\]]*[\)\]]",
    re.IGNORECASE,
)
_SEPARATORS = (" - ", " – ", " — ", " | ")


def parse_youtube_title(title: str, channel: str) -> tuple[str, str]:
    """Best-effort (artist, song) from a YouTube title such as "Artist - Song (Official Video)"."""
    cleaned = _NOISE.sub("", title).strip()
    channel_clean = re.sub(
        r"\s*(- topic|vevo|official)\s*$", "", channel, flags=re.IGNORECASE
    ).strip()
    for separator in _SEPARATORS:
        if separator in cleaned:
            left, right = cleaned.split(separator, 1)
            right = right.split(" | ")[0].strip()
            if left.strip() and right:
                return left.strip(), right
    return channel_clean, cleaned


def _lucene(value: str) -> str:
    """Escape a value for a MusicBrainz (Lucene) phrase query."""
    return re.sub(r'([+\-!(){}\[\]^"~*?:\\/]|&&|\|\|)', r"\\\1", value)[:120]


def _credits(raw: list[dict[str, Any]] | None) -> list[ArtistCredit]:
    out: list[ArtistCredit] = []
    for credit in raw or []:
        artist = credit.get("artist") or {}
        out.append(
            ArtistCredit(
                name=str(credit.get("name") or artist.get("name") or ""),
                mbid=artist.get("id"),
                join_phrase=str(credit.get("joinphrase") or ""),
            )
        )
    return [c for c in out if c.name]


def _genres(entity: dict[str, Any]) -> list[str]:
    ranked = sorted(entity.get("genres") or [], key=lambda g: -int(g.get("count") or 0))
    return [str(g["name"]) for g in ranked if g.get("name")][:8]


def _release(raw: dict[str, Any]) -> ReleaseInfo:
    group = raw.get("release-group") or {}
    labels = [
        Label(
            name=str((info.get("label") or {}).get("name")),
            mbid=(info.get("label") or {}).get("id"),
            catalog_number=info.get("catalog-number"),
        )
        for info in raw.get("label-info") or []
        if (info.get("label") or {}).get("name")
    ]
    cover = None
    if (raw.get("cover-art-archive") or {}).get("front"):
        cover = f"https://coverartarchive.org/release/{raw['id']}/front-250"
    return ReleaseInfo(
        mbid=str(raw["id"]),
        title=str(raw.get("title") or ""),
        date=raw.get("date") or None,
        country=raw.get("country") or None,
        status=raw.get("status") or None,
        release_group_mbid=group.get("id"),
        release_group_type=group.get("primary-type"),
        labels=labels,
        cover_art_url=cover,
    )


class MusicBrainzClient:
    _lock = asyncio.Lock()  # shared by every client in the process: 1 request/second total
    _last_request = 0.0

    def __init__(
        self,
        store: KeyValueStore,
        *,
        contact: str,
        base_url: str = "https://musicbrainz.org/ws/2",
        http_client: httpx.AsyncClient | None = None,
        timeout: float = 10.0,
        min_interval: float = MIN_INTERVAL_SECONDS,
    ) -> None:
        self._store = store
        self._min_interval = min_interval
        self._client = http_client or httpx.AsyncClient(
            base_url=base_url,
            timeout=timeout,
            headers={"User-Agent": f"Halo/0.1 ( {contact} )", "Accept": "application/json"},
        )

    async def aclose(self) -> None:
        await self._client.aclose()

    async def _get(self, path: str, params: dict[str, Any]) -> dict[str, Any]:
        params = {**params, "fmt": "json"}
        key = "mb:" + hashlib.sha256(f"{path}|{sorted(params.items())}".encode()).hexdigest()[:40]
        cached = await self._store.get_json(key)
        if cached is not None:
            return dict(cached)
        async with MusicBrainzClient._lock:
            wait = MusicBrainzClient._last_request + self._min_interval - time.monotonic()
            if wait > 0:
                await asyncio.sleep(wait)
            try:
                response = await self._client.get(path, params=params)
            except httpx.HTTPError as exc:
                raise MusicBrainzUnavailableError("MusicBrainz is unreachable") from exc
            finally:
                MusicBrainzClient._last_request = time.monotonic()
        if response.status_code == 404:
            return {}
        if response.status_code != 200:
            raise MusicBrainzUnavailableError(f"MusicBrainz returned {response.status_code}")
        data: dict[str, Any] = response.json()
        await self._store.set_json(key, data, CACHE_TTL_SECONDS)
        return data

    # --- Artists -----------------------------------------------------------------------

    async def find_artist(self, name: str) -> ArtistInfo | None:
        """Best artist match for a name, with genres from a follow-up lookup."""
        cleaned = " ".join(name.split())
        if not cleaned:
            return None
        data = await self._get("/artist", {"query": f'artist:"{_lucene(cleaned)}"', "limit": 3})
        hits = data.get("artists") or []
        if not hits or int(hits[0].get("score") or 0) < MATCH_THRESHOLD:
            return None
        info = await self.artist(str(hits[0]["id"]))
        if info is not None:
            info.match_score = int(hits[0].get("score") or 0)
        return info

    async def artist(self, mbid: str) -> ArtistInfo | None:
        raw = await self._get(f"/artist/{mbid}", {"inc": "genres"})
        if not raw.get("id"):
            return None
        life = raw.get("life-span") or {}
        return ArtistInfo(
            mbid=str(raw["id"]),
            name=str(raw.get("name") or ""),
            sort_name=raw.get("sort-name"),
            type=raw.get("type"),
            country=raw.get("country"),
            area=(raw.get("area") or {}).get("name"),
            disambiguation=raw.get("disambiguation") or None,
            begin=life.get("begin"),
            end=life.get("end"),
            genres=_genres(raw),
            musicbrainz_url=f"https://musicbrainz.org/artist/{raw['id']}",
        )

    # --- Recordings ----------------------------------------------------------------------

    async def match_recording(
        self, title: str, artist: str, duration_seconds: int | None = None
    ) -> CanonicalRecording | None:
        """Identify a song. Returns None unless MusicBrainz is confident."""
        if not title.strip():
            return None
        query = f'recording:"{_lucene(title)}"'
        if artist.strip():
            query += f' AND artist:"{_lucene(artist)}"'
        data = await self._get("/recording", {"query": query, "limit": 5})
        best: dict[str, Any] | None = None
        for hit in data.get("recordings") or []:
            score = int(hit.get("score") or 0)
            if score < MATCH_THRESHOLD:
                continue
            length = hit.get("length")
            if duration_seconds and length and abs(int(length) / 1000 - duration_seconds) > 25:
                continue  # a different version (live, extended mix...)
            best = hit
            break
        if best is None:
            return None
        recording = await self.recording(str(best["id"]))
        if recording is not None:
            recording.match_score = int(best.get("score") or 0)
        return recording

    async def recording(self, mbid: str) -> CanonicalRecording | None:
        raw = await self._get(
            f"/recording/{mbid}", {"inc": "artist-credits+releases+release-groups+isrcs+genres"}
        )
        if not raw.get("id"):
            return None
        releases = [_release(r) for r in raw.get("releases") or [] if r.get("id")]
        official = [r for r in releases if r.status == "Official"] or releases
        official.sort(key=lambda r: r.date or "9999")
        if official:
            # Labels and cover art live on the release; fetch them for the earliest one.
            detail = await self._get(
                f"/release/{official[0].mbid}", {"inc": "labels+release-groups"}
            )
            if detail.get("id"):
                official[0] = _release(detail)
        return CanonicalRecording(
            recording_mbid=str(raw["id"]),
            title=str(raw.get("title") or ""),
            artist_credit=_credits(raw.get("artist-credit")),
            length_ms=raw.get("length"),
            first_release_date=raw.get("first-release-date") or None,
            isrcs=[str(i) for i in raw.get("isrcs") or []][:5],
            genres=_genres(raw),
            releases=official[:5],
            musicbrainz_url=f"https://musicbrainz.org/recording/{raw['id']}",
        )
