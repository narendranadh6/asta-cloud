"""Interface every catalog source implements."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Protocol

from app.schemas import AlbumPage, ArtistPage, Track
from app.services.catalog.ids import TrackSource


class CatalogError(Exception):
    """Base error for catalog failures. Messages are safe to show to listeners."""


class CatalogUnavailableError(CatalogError):
    """Every source that was asked failed or is switched off."""


class CatalogNotConfiguredError(CatalogError):
    """No music source is enabled on the server."""


class TrackUnavailableError(CatalogError):
    """The track doesn't exist, was removed, or can no longer be streamed."""


class EntityUnavailableError(CatalogError):
    """An artist or album doesn't exist at its source (or the source has no such pages)."""

    def __init__(self, message: str, kind: str) -> None:
        super().__init__(message)
        self.kind = kind


@dataclass(slots=True)
class SearchPage:
    items: list[Track]
    next_page_token: str | None = None
    prev_page_token: str | None = None
    total_results_estimate: int | None = None
    sources: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


class CatalogSource(Protocol):
    @property
    def name(self) -> TrackSource: ...

    @property
    def full_tracks(self) -> bool:
        """False for preview-only sources."""
        ...

    async def search(self, query: str, *, limit: int, offset: int = 0) -> list[Track]: ...

    async def trending(self, *, limit: int, genre: str | None = None) -> list[Track]: ...

    async def get_tracks(self, source_ids: list[str]) -> dict[str, Track]:
        """Tracks that still exist and can be streamed, keyed by source id."""
        ...

    async def get_artist(self, source_id: str) -> ArtistPage | None:
        """The artist's page, or None when unknown (or the source has no artist pages)."""
        ...

    async def get_album(self, source_id: str) -> AlbumPage | None:
        """The album with its playable tracks in order, or None when unknown."""
        ...

    async def aclose(self) -> None: ...
