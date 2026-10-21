"""iTunes Search API: 30-second previews of mainstream songs (including Indian music).

Apple allows previews only to promote the song in its store: each preview is labelled as a
preview, attributed to Apple, links to the song's Apple page ("Listen on Apple Music"), and
is streamed, never saved. Halo follows all of that; previews are never presented as full songs.
"""

from __future__ import annotations

import logging
from typing import Any, Literal

import httpx

from app.schemas import AlbumPage, ArtistPage, Attribution, Track
from app.services.catalog.base import CatalogUnavailableError
from app.services.catalog.ids import make_track_id

logger = logging.getLogger("halo.itunes")


def _artwork(url: str | None, size: int = 600) -> str | None:
    # Search results carry 100x100 artwork; the same URL scheme serves larger sizes.
    return url.replace("100x100bb", f"{size}x{size}bb") if url else None


class ITunesPreviewSource:
    """30-second previews only: Halo shows no artist or album pages for them."""

    name: Literal["itunes"] = "itunes"
    full_tracks = False

    def __init__(
        self,
        *,
        country: str = "IN",
        base_url: str = "https://itunes.apple.com",
        http_client: httpx.AsyncClient | None = None,
        timeout: float = 8.0,
    ) -> None:
        self._country = country
        self._client = http_client or httpx.AsyncClient(base_url=base_url, timeout=timeout)

    async def aclose(self) -> None:
        await self._client.aclose()

    async def _get(self, path: str, params: dict[str, Any]) -> list[dict[str, Any]]:
        try:
            response = await self._client.get(path, params={"country": self._country, **params})
        except httpx.HTTPError as exc:
            raise CatalogUnavailableError("Apple's search service is unreachable") from exc
        if response.status_code != 200:
            raise CatalogUnavailableError(f"Apple's search service returned {response.status_code}")
        # The service answers with text/javascript; parse the body as JSON regardless.
        return list(response.json().get("results") or [])

    def _track(self, raw: dict[str, Any]) -> Track | None:
        if raw.get("kind") != "song" or not raw.get("previewUrl") or not raw.get("trackId"):
            return None
        page = raw.get("trackViewUrl")
        millis = raw.get("trackTimeMillis")
        return Track(
            id=make_track_id("itunes", str(raw["trackId"])),
            source="itunes",
            source_id=str(raw["trackId"]),
            title=str(raw.get("trackName") or ""),
            artist=str(raw.get("artistName") or "Unknown artist"),
            artist_id=str(raw["artistId"]) if raw.get("artistId") else None,
            album=raw.get("collectionName") or None,
            artwork_url=_artwork(raw.get("artworkUrl100")),
            artwork_url_large=_artwork(raw.get("artworkUrl100"), 1200),
            duration_seconds=int(millis) // 1000 if millis else None,
            genre=raw.get("primaryGenreName") or None,
            release_date=(raw.get("releaseDate") or "")[:10] or None,
            stream_url=str(raw["previewUrl"]),
            is_preview=True,
            external_url=page,
            attribution=Attribution(
                provider="itunes", label="Preview courtesy of Apple Music", url=page
            ),
        )

    async def search(self, query: str, *, limit: int, offset: int = 0) -> list[Track]:
        # The Search API has no offset; ask for enough rows and slice.
        rows = await self._get(
            "/search",
            {
                "term": query[:100],
                "media": "music",
                "entity": "song",
                "limit": min(offset + limit, 200),
            },
        )
        tracks = [t for t in (self._track(r) for r in rows) if t]
        return tracks[offset : offset + limit]

    async def trending(self, *, limit: int, genre: str | None = None) -> list[Track]:
        return []  # previews promote specific songs; Halo doesn't build charts from them

    async def get_tracks(self, source_ids: list[str]) -> dict[str, Track]:
        if not source_ids:
            return {}
        rows = await self._get("/lookup", {"id": ",".join(source_ids[:100]), "entity": "song"})
        tracks = [t for t in (self._track(r) for r in rows) if t]
        return {t.source_id: t for t in tracks}

    async def get_artist(self, source_id: str) -> ArtistPage | None:
        return None

    async def get_album(self, source_id: str) -> AlbumPage | None:
        return None
