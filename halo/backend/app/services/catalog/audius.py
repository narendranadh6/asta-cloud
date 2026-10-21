"""Audius: free, full-length tracks published by the artists themselves.

REST API at https://api.audius.co/v1 (reads need no key; a key raises rate limits). Audio is
streamed by the listener's device straight from ``/v1/tracks/{id}/stream``; Halo never
downloads or stores it. Responses are wrapped as ``{"data": ...}``.
"""

from __future__ import annotations

import asyncio
import logging
from typing import Any, Literal
from urllib.parse import urlencode

import httpx

from app.schemas import AlbumPage, AlbumSummary, ArtistPage, Attribution, Track
from app.services.catalog.base import CatalogError, CatalogUnavailableError
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
            artwork_url_large=artwork.get("1000x1000") or artwork.get("480x480"),
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

    # --- Artists and albums ---------------------------------------------------------------

    @staticmethod
    def _page(permalink: str | None) -> str | None:
        return f"https://audius.co{permalink}" if permalink else None

    def _album(self, raw: Any) -> AlbumSummary | None:
        if not isinstance(raw, dict) or not raw.get("id"):
            return None
        user = raw.get("user") or {}
        artwork = raw.get("artwork") or {}
        return AlbumSummary(
            id=make_track_id("audius", str(raw["id"])),
            source="audius",
            title=str(raw.get("playlist_name") or "Untitled"),
            artist=str(user.get("name") or user.get("handle") or "Unknown artist"),
            artist_id=make_track_id("audius", str(user["id"])) if user.get("id") else None,
            artwork_url=artwork.get("480x480")
            or artwork.get("1000x1000")
            or artwork.get("150x150"),
            release_date=(raw.get("release_date") or raw.get("created_at") or "")[:10] or None,
            track_count=raw.get("track_count"),
            external_url=self._page(raw.get("permalink")),
        )

    async def _optional(self, path: str, params: dict[str, Any]) -> Any:
        """Secondary data (albums) shouldn't sink the whole page."""
        try:
            return await self._get(path, params)
        except CatalogError as exc:
            logger.warning("audius %s failed: %s", path, exc)
            return None

    async def get_artist(self, source_id: str) -> ArtistPage | None:
        user, rows, album_rows = await asyncio.gather(
            self._get(f"/users/{source_id}", {}),
            self._get(f"/users/{source_id}/tracks", {"sort": "plays", "limit": 20}),
            self._optional(f"/users/{source_id}/albums", {"limit": 20}),
        )
        if not isinstance(user, dict) or user.get("is_deactivated"):
            return None
        picture = user.get("profile_picture") or {}
        cover = user.get("cover_photo") or {}
        handle = user.get("handle")
        page = f"https://audius.co/{handle}" if handle else None
        top = sorted(self._tracks(rows), key=lambda t: t.play_count or 0, reverse=True)
        return ArtistPage(
            id=make_track_id("audius", str(user.get("id") or source_id)),
            source="audius",
            name=str(user.get("name") or handle or "Unknown artist"),
            handle=handle,
            artwork_url=picture.get("480x480")
            or picture.get("1000x1000")
            or picture.get("150x150"),
            cover_url=cover.get("2000x") or cover.get("640x"),
            bio=(user.get("bio") or "").strip() or None,
            follower_count=user.get("follower_count"),
            external_url=page,
            attribution=Attribution(provider="audius", label="Audius", url=page),
            top_tracks=top,
            albums=[a for a in (self._album(r) for r in album_rows or []) if a],
        )

    async def get_album(self, source_id: str) -> AlbumPage | None:
        data, rows = await asyncio.gather(
            self._get(f"/playlists/{source_id}", {}),
            self._get(f"/playlists/{source_id}/tracks", {}),
        )
        raw = data[0] if isinstance(data, list) and data else data
        summary = self._album(raw)
        if summary is None or not isinstance(raw, dict):
            return None
        artwork = raw.get("artwork") or {}
        return AlbumPage(
            **summary.model_dump(),
            artwork_url_large=artwork.get("1000x1000") or summary.artwork_url,
            attribution=Attribution(provider="audius", label="Audius", url=summary.external_url),
            tracks=self._tracks(rows),
        )
