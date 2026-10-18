"""Provider interface for music metadata search."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal, Protocol

from app.schemas import Track


class YouTubeError(Exception):
    """Base error for metadata provider failures. Messages are user-safe."""


class QuotaExceededError(YouTubeError):
    pass


class ProviderUnavailableError(YouTubeError):
    pass


class ProviderConfigurationError(YouTubeError):
    pass


class VideoUnavailableError(YouTubeError):
    """The video does not exist, is private, or is blocked in the configured region."""


@dataclass(slots=True)
class SearchPage:
    items: list[Track]
    next_page_token: str | None = None
    prev_page_token: str | None = None
    total_results_estimate: int | None = None
    filtered_out: int = 0
    warnings: list[str] = field(default_factory=list)


class MetadataProvider(Protocol):
    name: Literal["youtube", "demo"]

    async def search(
        self, query: str, *, page_token: str | None = None, max_results: int = 20
    ) -> SearchPage: ...

    async def get_videos(self, video_ids: list[str]) -> dict[str, Track]:
        """Return validated metadata for available videos. Unavailable ids are omitted."""
        ...

    async def aclose(self) -> None: ...
