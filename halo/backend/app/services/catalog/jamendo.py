"""Jamendo: free, full-length Creative Commons music.

API v3.0 at https://api.jamendo.com/v3.0 (needs a free client id from devportal.jamendo.com).
The ``audio`` field is a stream URL the listener's device plays directly. Every track carries
a Creative Commons licence, which Halo shows with the artist name as attribution.
"""

from __future__ import annotations

import asyncio
import logging
from typing import Any, Literal

import httpx

from app.schemas import AlbumPage, AlbumSummary, ArtistPage, Attribution, Track, TrackLicense
from app.services.catalog.base import CatalogUnavailableError
from app.services.catalog.features import estimate
from app.services.catalog.ids import make_track_id

logger = logging.getLogger("halo.jamendo")


def _license_name(url: str | None) -> str:
    """'https://creativecommons.org/licenses/by-nc-sa/3.0/' → 'CC BY-NC-SA 3.0'."""
    if not url or "creativecommons.org/licenses/" not in url:
        return "Creative Commons"
    parts = [p for p in url.split("creativecommons.org/licenses/", 1)[1].split("/") if p]
    if not parts:
        return "Creative Commons"
    return " ".join(["CC", parts[0].upper(), *parts[1:2]])


class JamendoSource:
    name: Literal["jamendo"] = "jamendo"
    full_tracks = True

    def __init__(
        self,
        client_id: str,
        *,
        base_url: str = "https://api.jamendo.com/v3.0",
        http_client: httpx.AsyncClient | None = None,
        timeout: float = 8.0,
    ) -> None:
        self._client_id = client_id
        self._client = http_client or httpx.AsyncClient(base_url=base_url, timeout=timeout)

    async def aclose(self) -> None:
        await self._client.aclose()

    async def _query(self, endpoint: str, params: dict[str, Any]) -> list[dict[str, Any]]:
        query = {"client_id": self._client_id, "format": "json", **params}
        try:
            response = await self._client.get(endpoint, params=query)
        except httpx.HTTPError as exc:
            raise CatalogUnavailableError("Jamendo is unreachable") from exc
        if response.status_code != 200:
            raise CatalogUnavailableError(f"Jamendo returned {response.status_code}")
        payload = response.json()
        headers = payload.get("headers") or {}
        if headers.get("status") not in (None, "success"):
            raise CatalogUnavailableError(f"Jamendo error: {headers.get('error_message')}")
        return [r for r in payload.get("results") or [] if isinstance(r, dict)]

    async def _raw_tracks(self, params: dict[str, Any]) -> list[dict[str, Any]]:
        return await self._query(
            "/tracks/",
            {"audioformat": "mp32", "imagesize": 500, "include": "musicinfo", **params},
        )

    async def _tracks_query(self, params: dict[str, Any]) -> list[Track]:
        return [t for t in (self._track(r) for r in await self._raw_tracks(params)) if t]

    def _track(self, raw: dict[str, Any]) -> Track | None:
        if not raw.get("id") or not raw.get("name") or not raw.get("audio"):
            return None
        musicinfo = raw.get("musicinfo") or {}
        tags = musicinfo.get("tags") or {}
        genres = tags.get("genres") or []
        licence_url = raw.get("license_ccurl")
        page = raw.get("shareurl")
        features = estimate(
            title=str(raw["name"]),
            album=raw.get("album_name"),
            genre=str(genres[0]) if genres else None,
            tags=" ".join(str(t) for t in (tags.get("vartags") or []) + genres),
            lang=musicinfo.get("lang") if isinstance(musicinfo.get("lang"), str) else None,
            speed=musicinfo.get("speed") if isinstance(musicinfo.get("speed"), str) else None,
        )
        return Track(
            id=make_track_id("jamendo", str(raw["id"])),
            source="jamendo",
            source_id=str(raw["id"]),
            title=str(raw["name"]),
            artist=str(raw.get("artist_name") or "Unknown artist"),
            artist_id=str(raw["artist_id"]) if raw.get("artist_id") else None,
            album=raw.get("album_name") or None,
            album_id=str(raw["album_id"]) if raw.get("album_id") else None,
            artwork_url=raw.get("album_image") or raw.get("image") or None,
            duration_seconds=int(raw["duration"]) if raw.get("duration") else None,
            genre=str(genres[0]).title() if genres else None,
            release_date=raw.get("releasedate") or None,
            language=features.language,
            energy=features.energy,
            tempo=features.tempo,
            stream_url=str(raw["audio"]),
            license=TrackLicense(name=_license_name(licence_url), url=licence_url),
            external_url=page,
            attribution=Attribution(provider="jamendo", label="Jamendo", url=page),
        )

    async def search(self, query: str, *, limit: int, offset: int = 0) -> list[Track]:
        return await self._tracks_query(
            {"search": query[:100], "limit": limit, "offset": offset, "order": "relevance"}
        )

    async def trending(self, *, limit: int, genre: str | None = None) -> list[Track]:
        params: dict[str, Any] = {"limit": limit, "order": "popularity_week"}
        if genre:
            params["fuzzytags"] = genre.lower()
        return await self._tracks_query(params)

    async def get_tracks(self, source_ids: list[str]) -> dict[str, Track]:
        if not source_ids:
            return {}
        tracks = await self._tracks_query({"id": " ".join(source_ids[:100]), "limit": 100})
        return {t.source_id: t for t in tracks}

    # --- Artists and albums ---------------------------------------------------------------

    def _album(self, raw: dict[str, Any]) -> AlbumSummary | None:
        if not raw.get("id") or not raw.get("name"):
            return None
        return AlbumSummary(
            id=make_track_id("jamendo", str(raw["id"])),
            source="jamendo",
            title=str(raw["name"]),
            artist=str(raw.get("artist_name") or "Unknown artist"),
            artist_id=make_track_id("jamendo", str(raw["artist_id"]))
            if raw.get("artist_id")
            else None,
            artwork_url=raw.get("image") or None,
            release_date=raw.get("releasedate") or None,
            external_url=raw.get("shareurl") or None,
        )

    async def get_artist(self, source_id: str) -> ArtistPage | None:
        artists, top, albums = await asyncio.gather(
            self._query("/artists/", {"id": source_id}),
            self._tracks_query({"artist_id": source_id, "order": "popularity_total", "limit": 20}),
            self._query("/albums/", {"artist_id": source_id, "limit": 20, "imagesize": 500}),
        )
        if not artists:
            return None
        raw = artists[0]
        page = raw.get("shareurl") or None
        return ArtistPage(
            id=make_track_id("jamendo", str(raw.get("id") or source_id)),
            source="jamendo",
            name=str(raw.get("name") or "Unknown artist"),
            artwork_url=raw.get("image") or None,
            external_url=page,
            attribution=Attribution(provider="jamendo", label="Jamendo", url=page),
            top_tracks=top,
            albums=[a for a in (self._album(r) for r in albums) if a],
        )

    async def get_album(self, source_id: str) -> AlbumPage | None:
        albums, rows = await asyncio.gather(
            self._query("/albums/", {"id": source_id, "imagesize": 600}),
            self._raw_tracks({"album_id": source_id, "limit": 100}),
        )
        summary = self._album(albums[0]) if albums else None
        if summary is None:
            return None
        rows.sort(key=lambda r: int(r.get("position") or 0))
        tracks = [t for t in (self._track(r) for r in rows) if t]
        summary.track_count = len(tracks)
        return AlbumPage(
            **summary.model_dump(),
            artwork_url_large=summary.artwork_url,
            attribution=Attribution(provider="jamendo", label="Jamendo", url=summary.external_url),
            tracks=tracks,
        )
