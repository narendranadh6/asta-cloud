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

import re
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


@dataclass(frozen=True, slots=True)
class RightsPolicy:
    """What this deployment has actually confirmed. Everything defaults to "not confirmed".

    * ``deployment_use``: "commercial" (the default: a product offered to the public) or
      "non_commercial" (personal or development use, e.g. the local server).
    * ``audius_terms_confirmed``: someone has reviewed Audius's API terms for this commercial use.
    * ``jamendo_commercial_license``: Halo holds a Jamendo commercial licence. A Creative Commons
      licence on a track is not enough for a commercial service on its own: many are
      non-commercial (NC), and Jamendo's API terms govern commercial use separately.
    """

    deployment_use: Literal["commercial", "non_commercial"] = "commercial"
    audius_terms_confirmed: bool = False
    jamendo_commercial_license: bool = False


_CC_URL = re.compile(
    r"^https?://(?:www\.)?creativecommons\.org/licenses/([a-z-]+)/\d", re.IGNORECASE
)
_CC_CODES = {"by", "by-sa", "by-nd", "by-nc", "by-nc-sa", "by-nc-nd"}


def creative_commons_code(url: str | None) -> str | None:
    """ "by-nc-sa" for a recognised Creative Commons licence URL; None for anything else."""
    match = _CC_URL.match(url or "")
    code = match.group(1).lower() if match else None
    return code if code in _CC_CODES else None


class SourcePolicyRightsResolver:
    """Per-source policy. Unknown sources and unknown licences are refused (fail closed)."""

    def __init__(self, policy: RightsPolicy | None = None) -> None:
        self.policy = policy or RightsPolicy()

    def decide(self, track: Track) -> RightsDecision:
        if track.is_preview:
            return RightsDecision(False, "preview_only")
        if not track.stream_url:
            return RightsDecision(False, "no_stream")
        commercial = self.policy.deployment_use == "commercial"
        if track.source == "audius":
            if commercial and not self.policy.audius_terms_confirmed:
                return RightsDecision(False, "commercial_terms_unconfirmed")
            return RightsDecision(True, "ok", basis="audius_api_terms")
        if track.source == "jamendo":
            code = creative_commons_code(track.license.url if track.license else None)
            if code is None:
                return RightsDecision(False, "unknown_licence")
            if commercial and not self.policy.jamendo_commercial_license:
                return RightsDecision(False, "commercial_licence_missing")
            return RightsDecision(True, "ok", basis="creative_commons")
        return RightsDecision(False, "source_not_authorised")


def authorize(track: Track, resolver: MusicRightsResolver) -> Track:
    """Stamps the decision on the track. A refused track keeps its metadata (it can still be
    found, shown and identified) but loses its stream, so no client can play it."""
    decision = resolver.decide(track)
    track.playback_authorized = decision.playable
    track.playback_restriction = None if decision.playable else decision.reason
    if not decision.playable:
        track.stream_url = None
    return track


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
