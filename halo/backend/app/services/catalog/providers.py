"""Provider-independent catalog interfaces for future integrations (Apple Music via MusicKit,
a HALO-owned catalog). Today's sources (Audius, Jamendo) already fit ``CatalogSource``; these
interfaces add what a licensed provider needs: separate search and playback roles, rights and
entitlement checks, and a router that decides *how* a track plays.

Nothing here streams audio. Apple Music audio is never fetched, proxied or cached by Halo: a
MusicKit track would play on the device through Apple's own player, for subscribers only.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal, Protocol

from app.schemas import Track
from app.services.catalog.rights import (
    MusicEntitlementChecker,
    MusicRightsResolver,
)

PlaybackKind = Literal["stream_url", "device_player"]


@dataclass(frozen=True, slots=True)
class PlaybackDescriptor:
    """How the app should play a track."""

    kind: PlaybackKind
    # "stream_url": the URL the app's own player opens. "device_player": a provider id the
    # provider's on-device player resolves (e.g. a MusicKit catalog id); Halo never sees audio.
    reference: str


@dataclass(frozen=True, slots=True)
class PlaybackRefusal:
    reason: str


class MusicSearchProvider(Protocol):
    async def search(self, query: str, *, limit: int, offset: int = 0) -> list[Track]: ...


class MusicMetadataProvider(Protocol):
    async def get_tracks(self, source_ids: list[str]) -> dict[str, Track]: ...


class MusicPlaybackProvider(Protocol):
    def descriptor(self, track: Track) -> PlaybackDescriptor | None: ...


class MusicCatalogProvider(
    MusicSearchProvider, MusicMetadataProvider, MusicPlaybackProvider, Protocol
):
    @property
    def name(self) -> str: ...


class StreamUrlPlayback:
    """Audius and Jamendo: the app streams the source's own URL."""

    def descriptor(self, track: Track) -> PlaybackDescriptor | None:
        return PlaybackDescriptor("stream_url", track.stream_url) if track.stream_url else None


class PlaybackRouter:
    """Rights first, then entitlement, then the provider's playback descriptor."""

    def __init__(
        self,
        rights: MusicRightsResolver,
        entitlements: MusicEntitlementChecker,
        players: dict[str, MusicPlaybackProvider],
    ) -> None:
        self._rights = rights
        self._entitlements = entitlements
        self._players = players

    async def route(
        self, track: Track, user_id: str | None
    ) -> PlaybackDescriptor | PlaybackRefusal:
        decision = self._rights.decide(track)
        if not decision.playable:
            return PlaybackRefusal(decision.reason)
        entitlement = await self._entitlements.check(user_id, track)
        if not entitlement.allowed:
            return PlaybackRefusal(entitlement.reason)
        player = self._players.get(track.source)
        descriptor = player.descriptor(track) if player else None
        return descriptor or PlaybackRefusal("no_player")
