"""Playback rights and entitlement: a hard gate before any track is recommended or played.

Halo only plays what a source has authorised it to play. Being findable through an API is not
permission to play: every track passes ``MusicRightsResolver.decide`` (does Halo have a basis
to stream this in full?) and, for sources that need it, ``MusicEntitlementChecker`` (may this
listener play it, e.g. an Apple Music subscription). Recommendations drop anything refused;
nothing here can be overridden by ranking, by a language model, or by the client.

What each source's basis is, and what is still unverified (commercial terms, territories), is
documented in docs/architecture/CATALOG_AND_RIGHTS.md.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal, Protocol

from app.schemas import Track

Basis = Literal[
    "audius_api_terms",  # artist uploads, streamed through the Audius API with attribution
    "creative_commons",  # Jamendo track with its own CC licence
    "halo_direct_license",  # HALO-owned catalog with a signed agreement (not built)
    "provider_subscription",  # e.g. Apple Music through MusicKit (not built)
]


@dataclass(frozen=True, slots=True)
class RightsDecision:
    playable: bool
    reason: str
    basis: Basis | None = None
    needs_entitlement: bool = False


class MusicRightsResolver(Protocol):
    def decide(self, track: Track) -> RightsDecision: ...


class SourcePolicyRightsResolver:
    """Today's policy, per source. Unknown sources are refused, not allowed by default."""

    def decide(self, track: Track) -> RightsDecision:
        if track.is_preview:
            return RightsDecision(False, "preview_only")
        if not track.stream_url:
            return RightsDecision(False, "no_stream")
        if track.source == "audius":
            return RightsDecision(True, "ok", basis="audius_api_terms")
        if track.source == "jamendo":
            if track.license is None:
                return RightsDecision(False, "no_licence")
            return RightsDecision(True, "ok", basis="creative_commons")
        return RightsDecision(False, "source_not_authorised")


@dataclass(frozen=True, slots=True)
class Entitlement:
    allowed: bool
    reason: str


class MusicEntitlementChecker(Protocol):
    async def check(self, user_id: str | None, track: Track) -> Entitlement: ...


class OpenCatalogEntitlements:
    """Audius and Jamendo need no subscription; anything that would is refused until a real
    checker (e.g. MusicKit subscription status, reported by the device) is configured."""

    async def check(self, user_id: str | None, track: Track) -> Entitlement:
        if track.source in ("audius", "jamendo"):
            return Entitlement(True, "open_catalog")
        return Entitlement(False, "entitlement_unknown")


def playable(tracks: list[Track], resolver: MusicRightsResolver) -> list[Track]:
    """Only tracks Halo may play in full; order kept."""
    return [t for t in tracks if resolver.decide(t).playable]
