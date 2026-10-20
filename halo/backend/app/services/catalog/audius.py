"""Audius: free, full-length tracks published by the artists themselves.

REST API at https://api.audius.co/v1 (reads need no key; a key raises rate limits). Audio is
streamed by the listener's device straight from ``/v1/tracks/{id}/stream``; Halo never
downloads or stores it. Responses are wrapped as ``{"data": ...}``.
"""

from __future__ import annotations

import logging
from typing import Any, Literal
from urllib.parse import urlencode

import httpx

from app.schemas import Attribution, Track
from app.services.catalog.base import CatalogUnavailableError
from app.services.catalog.ids import make_track_id

logger = logging.getLogger("halo.audius")

APP_NAME = "Halo"


class AudiusSource:
    name: Literal["audius"] = "audius"
    full_tracks = True

    def __init__(
        self,
        *,
        base_url: str = "https://api.audius.co/v1",
        api_key: str | None = None,
        http_client: httpx.AsyncClient | None = None,
        timeout: float = 8.0,
    ) -> None:
        self._base_url = base_url.rstrip("/")
        self._headers = {"User-Agent": "Halo/0.1 (+https://github.com/narendranadh6/asta-cloud)"}
        if api_key:
            self._headers["x-api-key"] = api_key
        self._client = http_client or httpx.AsyncClient(base_url=self._base_url, timeout=timeout)

    async def aclose(self) -> None:
        await self._client.aclose()

    async def _get(self, path: str, params: dict[str, Any]) -> Any:
        try:
            response = await self._client.get(
                path, params={**params, "app_name": APP_NAME}, headers=self._headers
            )
        except httpx.HTTPError as exc:
            raise CatalogUnavailableError("Audius is unreachable") from exc
        if response.status_code == 404:
            return None
        if response.status_code != 200:
            raise CatalogUnavailableError(f"Audius returned {response.status_code}")
        return response.json().get("data")

    def stream_url(self, track_id: str) -> str:
        return f"{self._base_url}/tracks/{track_id}/stream?{urlencode({'app_name': APP_NAME})}"

    def _track(self, raw: dict[str, Any]) -> Track | None:
        if not raw.get("id") or not raw.get("title"):
            return None
        if raw.get("is_streamable") is False or raw.get("is_delete") or raw.get("is_unlisted"):
            return None
        if raw.get("is_stream_gated") or raw.get("stream_conditions"):
            return None  # paid or gated tracks can't be played for free
        user = raw.get("user") or {}
        artwork = raw.get("artwork") or {}
        permalink = raw.get("permalink")
        page = f"https://audius.co{permalink}" if permalink else None
        return Track(
            id=make_track_id("audius", str(raw["id"])),
            source="audius",
            source_id=str(raw["id"]),
            title=str(raw["title"]),
            artist=str(user.get("name") or user.get("handle") or "Unknown artist"),
            artist_id=str(user["id"]) if user.get("id") else None,
            artwork_url=artwork.get("480x480")
            or artwork.get("1000x1000")
            or artwork.get("150x150"),
            duration_seconds=int(raw["duration"]) if raw.get("duration") else None,
            genre=raw.get("genre") or None,
            mood=raw.get("mood") or None,
            release_date=(raw.get("release_date") or "")[:10] or None,
            play_count=raw.get("play_count"),
            stream_url=self.stream_url(str(raw["id"])),
            external_url=page,
            attribution=Attribution(provider="audius", label="Audius", url=page),
        )

    def _tracks(self, rows: Any) -> list[Track]:
        return [t for t in (self._track(r) for r in rows or [] if isinstance(r, dict)) if t]

    async def search(self, query: str, *, limit: int, offset: int = 0) -> list[Track]:
        rows = await self._get(
            "/tracks/search", {"query": query[:100], "limit": limit, "offset": offset}
        )
        return self._tracks(rows)

    async def trending(self, *, limit: int, genre: str | None = None) -> list[Track]:
        params: dict[str, Any] = {"time": "week", "limit": limit}
        if genre:
            params["genre"] = genre
        return self._tracks(await self._get("/tracks/trending", params))

    async def get_tracks(self, source_ids: list[str]) -> dict[str, Track]:
        found: dict[str, Track] = {}
        for source_id in source_ids:
            row = await self._get(f"/tracks/{source_id}", {})
            track = self._track(row) if isinstance(row, dict) else None
            if track:
                found[source_id] = track
        return found
