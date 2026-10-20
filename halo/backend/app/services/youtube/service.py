"""Cached search facade over a MetadataProvider.

Caching stores only metadata (titles, channel names, thumbnail URLs, durations) for at
most the configured TTL, which is clamped to the 30-day limit in the YouTube API
Services Developer Policies. No audiovisual content is ever fetched or stored.
"""

from __future__ import annotations

import hashlib
import logging
from dataclasses import dataclass
from typing import Literal

from app.core.cache import KeyValueStore
from app.schemas import SearchKind, Track
from app.services.youtube.base import (
    MetadataProvider,
    ProviderConfigurationError,
    SearchPage,
    VideoUnavailableError,
)
from app.services.youtube.ids import is_valid_video_id

logger = logging.getLogger("halo.youtube")

_KIND_SUFFIX: dict[str, str] = {
    "song": "",
    "artist": " songs",
    "remix": " remix",
    "live": " live performance",
}


def shape_query(query: str, kind: SearchKind) -> str:
    cleaned = " ".join(query.split())[:150]
    suffix = _KIND_SUFFIX[kind]
    if suffix and suffix.strip() in cleaned.lower():
        return cleaned
    return f"{cleaned}{suffix}"


@dataclass(slots=True)
class CachedSearch:
    page: SearchPage
    cached: bool


class YouTubeSearchService:
    def __init__(
        self,
        provider: MetadataProvider,
        store: KeyValueStore,
        *,
        search_ttl_seconds: int,
        video_ttl_seconds: int,
    ) -> None:
        self.provider = provider
        self._store = store
        self._search_ttl = search_ttl_seconds
        self._video_ttl = video_ttl_seconds

    @property
    def provider_name(self) -> str:
        return self.provider.name

    def _key(self, *parts: str) -> str:
        digest = hashlib.sha256("|".join(parts).encode()).hexdigest()[:32]
        return f"yt:{self.provider.name}:{digest}"

    async def search(
        self,
        query: str,
        *,
        kind: SearchKind = "song",
        page_token: str | None = None,
        max_results: int = 20,
    ) -> CachedSearch:
        shaped = shape_query(query, kind)
        key = self._key("search", shaped.lower(), page_token or "", str(max_results))
        cached = await self._store.get_json(key)
        if cached is not None:
            return CachedSearch(
                page=SearchPage(
                    items=[Track.model_validate(item) for item in cached["items"]],
                    next_page_token=cached.get("next"),
                    prev_page_token=cached.get("prev"),
                    total_results_estimate=cached.get("total"),
                ),
                cached=True,
            )
        page = await self.provider.search(shaped, page_token=page_token, max_results=max_results)
        await self._store.set_json(
            key,
            {
                "items": [t.model_dump(mode="json") for t in page.items],
                "next": page.next_page_token,
                "prev": page.prev_page_token,
                "total": page.total_results_estimate,
            },
            self._search_ttl,
        )
        for track in page.items:
            await self._store.set_json(
                self._key("video", track.video_id), track.model_dump(mode="json"), self._video_ttl
            )
        return CachedSearch(page=page, cached=False)

    async def trending(
        self, *, page_token: str | None = None, max_results: int = 20
    ) -> CachedSearch:
        key = self._key("trending", page_token or "", str(max_results))
        cached = await self._store.get_json(key)
        if cached is not None:
            return CachedSearch(
                page=SearchPage(
                    items=[Track.model_validate(item) for item in cached["items"]],
                    next_page_token=cached.get("next"),
                    prev_page_token=cached.get("prev"),
                    total_results_estimate=cached.get("total"),
                ),
                cached=True,
            )
        page = await self.provider.trending(page_token=page_token, max_results=max_results)
        await self._store.set_json(
            key,
            {
                "items": [t.model_dump(mode="json") for t in page.items],
                "next": page.next_page_token,
                "prev": page.prev_page_token,
                "total": page.total_results_estimate,
            },
            min(self._search_ttl, 60 * 60),  # charts change; refresh hourly at most
        )
        return CachedSearch(page=page, cached=False)

    async def get_videos(self, video_ids: list[str]) -> dict[str, Track]:
        valid = [vid for vid in dict.fromkeys(video_ids) if is_valid_video_id(vid)]
        found: dict[str, Track] = {}
        missing: list[str] = []
        for vid in valid:
            cached = await self._store.get_json(self._key("video", vid))
            if cached is None:
                missing.append(vid)
            else:
                found[vid] = Track.model_validate(cached)
        if missing:
            fetched = await self.provider.get_videos(missing)
            for vid, track in fetched.items():
                found[vid] = track
                await self._store.set_json(
                    self._key("video", vid), track.model_dump(mode="json"), self._video_ttl
                )
        return found

    async def get_video(self, video_id: str) -> Track:
        if not is_valid_video_id(video_id):
            raise VideoUnavailableError("Invalid video id")
        videos = await self.get_videos([video_id])
        if video_id not in videos:
            raise VideoUnavailableError("This video is unavailable, private, or region-blocked")
        return videos[video_id]


class UnconfiguredProvider:
    """Used when no YouTube API key is set: every call fails with a clear setup error."""

    name: Literal["youtube"] = "youtube"
    configured = False

    async def _fail(self) -> SearchPage:
        raise ProviderConfigurationError(
            "Music search isn't set up yet: the server needs HALO_YOUTUBE_API_KEY."
        )

    async def search(
        self, query: str, *, page_token: str | None = None, max_results: int = 20
    ) -> SearchPage:
        return await self._fail()

    async def trending(self, *, page_token: str | None = None, max_results: int = 20) -> SearchPage:
        return await self._fail()

    async def get_videos(self, video_ids: list[str]) -> dict[str, Track]:
        await self._fail()
        return {}

    async def aclose(self) -> None:
        return None


def build_provider(settings: object) -> MetadataProvider:
    from app.core.config import Settings
    from app.services.youtube.client import YouTubeDataAPIClient

    assert isinstance(settings, Settings)
    key = settings.youtube_api_key.get_secret_value() if settings.youtube_api_key else ""
    if not key.strip():
        logger.error("HALO_YOUTUBE_API_KEY is not set: music search will return 503")
        return UnconfiguredProvider()
    return YouTubeDataAPIClient(
        key,
        base_url=settings.youtube_api_base_url,
        region_code=settings.youtube_region_code,
        timeout_seconds=settings.youtube_timeout_seconds,
    )
