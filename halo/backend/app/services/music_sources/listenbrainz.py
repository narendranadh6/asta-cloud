"""ListenBrainz: open listening data for discovery.

https://listenbrainz.org/ (MetaBrainz). Endpoints used, as defined in the server source
(github.com/metabrainz/listenbrainz-server, listenbrainz/webserver/views):

* ``GET /1/explore/fresh-releases/``: recent and upcoming releases, with listen counts
* ``GET /1/stats/sitewide/recordings``: most-listened recordings across ListenBrainz
* ``GET /1/lb-radio/artist/{mbid}``: similar artists and their popular recordings
* ``GET /1/metadata/recording/``: names for recording MBIDs
* ``GET /1/popularity/top-recordings-for-artist/{mbid}``: needs a user token

A token (``Authorization: Token ...``) is sent when configured; ListenBrainz requires it for
"expensive" endpoints such as popularity.
"""

from __future__ import annotations

import hashlib
import logging
from datetime import date
from typing import Any, Literal

import httpx
from pydantic import BaseModel, Field

from app.core.cache import KeyValueStore

logger = logging.getLogger("halo.listenbrainz")


class ListenBrainzUnavailableError(Exception):
    pass


class FreshRelease(BaseModel):
    release_mbid: str
    release_name: str
    artist_name: str
    artist_mbids: list[str] = Field(default_factory=list)
    release_date: str
    release_group_mbid: str | None = None
    release_type: str | None = None
    tags: list[str] = Field(default_factory=list)
    listen_count: int = 0
    cover_art_url: str | None = None
    source: str = "ListenBrainz"


class PopularRecording(BaseModel):
    recording_mbid: str | None = None
    title: str
    artist_name: str
    release_name: str | None = None
    listen_count: int = 0
    listener_count: int | None = None
    length_ms: int | None = None
    similar_to: str | None = None  # seed artist this came from (artist radio)
    source: str = "ListenBrainz"


RadioMode = Literal["easy", "medium", "hard"]

# Discovery level -> (LB Radio mode, popularity range in percent).
RADIO_SETTINGS: dict[str, tuple[RadioMode, int, int]] = {
    "familiar": ("easy", 50, 100),
    "balanced": ("medium", 20, 100),
    "discovery": ("hard", 0, 60),
}


def _cover(caa_release_mbid: object, caa_id: object) -> str | None:
    if caa_release_mbid and caa_id:
        return f"https://coverartarchive.org/release/{caa_release_mbid}/{caa_id}-250.jpg"
    return None


class ListenBrainzClient:
    def __init__(
        self,
        store: KeyValueStore,
        *,
        token: str | None = None,
        base_url: str = "https://api.listenbrainz.org/1",
        http_client: httpx.AsyncClient | None = None,
        timeout: float = 10.0,
    ) -> None:
        self._store = store
        self.has_token = bool(token)
        headers = {"User-Agent": "Halo/0.1 (+https://github.com/narendranadh6/asta-cloud)"}
        if token:
            headers["Authorization"] = f"Token {token}"
        self._client = http_client or httpx.AsyncClient(
            base_url=base_url, timeout=timeout, headers=headers
        )

    async def aclose(self) -> None:
        await self._client.aclose()

    async def _get(self, path: str, params: dict[str, Any], ttl: int) -> Any:
        key = "lb:" + hashlib.sha256(f"{path}|{sorted(params.items())}".encode()).hexdigest()[:40]
        cached = await self._store.get_json(key)
        if cached is not None:
            return cached
        try:
            response = await self._client.get(path, params=params)
        except httpx.HTTPError as exc:
            raise ListenBrainzUnavailableError("ListenBrainz is unreachable") from exc
        if response.status_code == 204:
            return None
        if response.status_code != 200:
            raise ListenBrainzUnavailableError(f"ListenBrainz returned {response.status_code}")
        data = response.json()
        await self._store.set_json(key, data, ttl)
        return data

    async def fresh_releases(
        self,
        *,
        days: int = 14,
        past: bool = True,
        future: bool = False,
        sort: str = "release_date",
        on: date | None = None,
    ) -> list[FreshRelease]:
        params: dict[str, Any] = {
            "days": max(1, min(days, 90)),
            "sort": sort,
            "past": str(past).lower(),
            "future": str(future).lower(),
        }
        if on:
            params["release_date"] = on.isoformat()
        data = await self._get("/explore/fresh-releases/", params, ttl=3 * 3600)
        out: list[FreshRelease] = []
        for raw in ((data or {}).get("payload") or {}).get("releases") or []:
            if not raw.get("release_mbid") or not raw.get("release_name"):
                continue
            out.append(
                FreshRelease(
                    release_mbid=str(raw["release_mbid"]),
                    release_name=str(raw["release_name"]),
                    artist_name=str(raw.get("artist_credit_name") or ""),
                    artist_mbids=[str(m) for m in raw.get("artist_mbids") or []],
                    release_date=str(raw.get("release_date") or ""),
                    release_group_mbid=raw.get("release_group_mbid"),
                    release_type=raw.get("release_group_primary_type"),
                    tags=[str(t) for t in raw.get("release_tags") or []][:6],
                    listen_count=int(raw.get("listen_count") or 0),
                    cover_art_url=_cover(raw.get("caa_release_mbid"), raw.get("caa_id")),
                )
            )
        return out

    async def top_recordings(
        self, *, range_: str = "week", count: int = 50
    ) -> list[PopularRecording]:
        data = await self._get(
            "/stats/sitewide/recordings",
            {"range": range_, "count": max(1, min(count, 100))},
            ttl=3600,
        )
        return [
            PopularRecording(
                recording_mbid=raw.get("recording_mbid") or None,
                title=str(raw["track_name"]),
                artist_name=str(raw.get("artist_name") or ""),
                release_name=raw.get("release_name") or None,
                listen_count=int(raw.get("listen_count") or 0),
            )
            for raw in ((data or {}).get("payload") or {}).get("recordings") or []
            if raw.get("track_name")
        ]

    async def artist_top_recordings(
        self, artist_mbid: str, *, limit: int = 10
    ) -> list[PopularRecording]:
        if not self.has_token:
            return []
        data = await self._get(
            f"/popularity/top-recordings-for-artist/{artist_mbid}", {}, ttl=24 * 3600
        )
        return [
            PopularRecording(
                recording_mbid=raw.get("recording_mbid"),
                title=str(raw["recording_name"]),
                artist_name=str(raw.get("artist_name") or ""),
                release_name=raw.get("release_name"),
                listen_count=int(raw.get("total_listen_count") or 0),
                listener_count=raw.get("total_user_count"),
                length_ms=raw.get("length"),
            )
            for raw in (data or [])[:limit]
            if raw.get("recording_name")
        ]

    async def artist_radio(
        self,
        seed_artist_mbid: str,
        *,
        discovery: str = "balanced",
        max_similar_artists: int = 8,
        per_artist: int = 2,
    ) -> list[PopularRecording]:
        """Popular recordings by artists similar to the seed (LB Radio), with titles resolved."""
        mode, pop_begin, pop_end = RADIO_SETTINGS.get(discovery, RADIO_SETTINGS["balanced"])
        data = await self._get(
            f"/lb-radio/artist/{seed_artist_mbid}",
            {
                "mode": mode,
                "max_similar_artists": max_similar_artists,
                "max_recordings_per_artist": per_artist,
                "pop_begin": pop_begin,
                "pop_end": pop_end,
            },
            ttl=24 * 3600,
        )
        rows: list[dict[str, Any]] = []
        for artist_mbid, recordings in (data or {}).items():
            if artist_mbid == seed_artist_mbid:
                continue  # the seed itself is already covered by search
            rows.extend(recordings[:per_artist])
        rows.sort(key=lambda r: -int(r.get("total_listen_count") or 0))
        names = await self.recording_names(
            [str(r["recording_mbid"]) for r in rows if r.get("recording_mbid")]
        )
        out: list[PopularRecording] = []
        for row in rows:
            meta = names.get(str(row.get("recording_mbid")))
            if not meta:
                continue
            out.append(
                PopularRecording(
                    recording_mbid=str(row["recording_mbid"]),
                    title=meta[0],
                    artist_name=meta[1] or str(row.get("similar_artist_name") or ""),
                    listen_count=int(row.get("total_listen_count") or 0),
                    length_ms=meta[2],
                )
            )
        return out

    async def recording_names(self, mbids: list[str]) -> dict[str, tuple[str, str, int | None]]:
        """recording_mbid -> (title, artist credit name, length in ms)."""
        if not mbids:
            return {}
        out: dict[str, tuple[str, str, int | None]] = {}
        for start in range(0, len(mbids), 25):
            chunk = mbids[start : start + 25]
            data = await self._get(
                "/metadata/recording/",
                {"recording_mbids": ",".join(chunk), "inc": "artist"},
                ttl=7 * 24 * 3600,
            )
            for mbid, entry in (data or {}).items():
                recording = (entry or {}).get("recording") or {}
                if recording.get("name"):
                    length = recording.get("length")
                    out[mbid] = (
                        str(recording["name"]),
                        str(((entry or {}).get("artist") or {}).get("name") or ""),
                        int(length) if isinstance(length, int | float) else None,
                    )
        return out
