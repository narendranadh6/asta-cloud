"""Jamendo: free, full-length Creative Commons music.

API v3.0 at https://api.jamendo.com/v3.0 (needs a free client id from devportal.jamendo.com).
The ``audio`` field is a stream URL the listener's device plays directly. Every track carries
a Creative Commons licence, which Halo shows with the artist name as attribution.
"""

from __future__ import annotations

import logging
from typing import Any, Literal

import httpx

from app.schemas import Attribution, Track, TrackLicense
from app.services.catalog.base import CatalogUnavailableError
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

    async def _tracks_query(self, params: dict[str, Any]) -> list[Track]:
        query = {
            "client_id": self._client_id,
            "format": "json",
            "audioformat": "mp32",
            "imagesize": 500,
            "include": "musicinfo",
            **params,
        }
        try:
            response = await self._client.get("/tracks/", params=query)
        except httpx.HTTPError as exc:
            raise CatalogUnavailableError("Jamendo is unreachable") from exc
        if response.status_code != 200:
            raise CatalogUnavailableError(f"Jamendo returned {response.status_code}")
        payload = response.json()
        headers = payload.get("headers") or {}
        if headers.get("status") not in (None, "success"):
            raise CatalogUnavailableError(f"Jamendo error: {headers.get('error_message')}")
        return [t for t in (self._track(r) for r in payload.get("results") or []) if t]

    def _track(self, raw: dict[str, Any]) -> Track | None:
        if not raw.get("id") or not raw.get("name") or not raw.get("audio"):
            return None
        genres = ((raw.get("musicinfo") or {}).get("tags") or {}).get("genres") or []
        licence_url = raw.get("license_ccurl")
        page = raw.get("shareurl")
        return Track(
            id=make_track_id("jamendo", str(raw["id"])),
            source="jamendo",
            source_id=str(raw["id"]),
            title=str(raw["name"]),
            artist=str(raw.get("artist_name") or "Unknown artist"),
            artist_id=str(raw["artist_id"]) if raw.get("artist_id") else None,
            album=raw.get("album_name") or None,
            artwork_url=raw.get("album_image") or raw.get("image") or None,
            duration_seconds=int(raw["duration"]) if raw.get("duration") else None,
            genre=str(genres[0]).title() if genres else None,
            release_date=raw.get("releasedate") or None,
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
