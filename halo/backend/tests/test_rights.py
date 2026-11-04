"""Rights and entitlement are hard constraints; the router never plays what isn't authorised."""

from __future__ import annotations

from datetime import date

from app.core.cache import MemoryStore
from app.schemas import Attribution, SessionCandidatesRequest, Track, TrackLicense
from app.services.catalog.providers import (
    PlaybackDescriptor,
    PlaybackRefusal,
    PlaybackRouter,
    StreamUrlPlayback,
)
from app.services.catalog.rights import (
    OpenCatalogEntitlements,
    SourcePolicyRightsResolver,
    playable,
)
from app.services.catalog.service import CatalogService
from app.services.recommendations.session import SessionRecommender
from tests.fakes import CATALOG, FakeCatalogSource


def track(source: str = "audius", **fields: object) -> Track:
    base: dict[str, object] = {
        "id": f"{source}:x1",
        "source": source,
        "source_id": "x1",
        "title": "Song",
        "artist": "Artist",
        "stream_url": "https://stream.test/x1.mp3",
        "attribution": Attribution(provider=source, label=source.title()),  # type: ignore[arg-type]
    }
    base.update(fields)
    return Track.model_validate(base)


def test_policy_allows_only_authorised_full_streams() -> None:
    rights = SourcePolicyRightsResolver()
    assert rights.decide(track()).playable
    assert rights.decide(track("audius", is_preview=True)).reason == "preview_only"
    assert rights.decide(track("audius", stream_url=None)).reason == "no_stream"
    assert rights.decide(track("itunes")).reason == "source_not_authorised"
    assert rights.decide(track("jamendo")).reason == "no_licence"
    licensed = track("jamendo", license=TrackLicense(name="CC BY 4.0", url="https://cc.test"))
    assert rights.decide(licensed).basis == "creative_commons"
    assert playable([track(), track("itunes")], rights) == [track()]


async def test_router_checks_rights_then_entitlement_then_player() -> None:
    router = PlaybackRouter(
        SourcePolicyRightsResolver(), OpenCatalogEntitlements(), {"audius": StreamUrlPlayback()}
    )
    assert await router.route(track(), None) == PlaybackDescriptor(
        "stream_url", "https://stream.test/x1.mp3"
    )
    assert await router.route(track(is_preview=True), None) == PlaybackRefusal("preview_only")
    # A source with no authorised basis is refused before anything else is asked.
    assert await router.route(track("itunes"), None) == PlaybackRefusal("source_not_authorised")


async def test_session_candidates_never_include_unauthorised_tracks() -> None:
    class DenyFirstArtist(SourcePolicyRightsResolver):
        def decide(self, t: Track):  # type: ignore[no-untyped-def]
            if t.artist == CATALOG[0][0].artist:
                from app.services.catalog.rights import RightsDecision

                return RightsDecision(False, "takedown")
            return super().decide(t)

    catalog = CatalogService([FakeCatalogSource()], MemoryStore())
    request = SessionCandidatesRequest.model_validate(
        {"language": {"primary": "te"}, "artist_weights": {CATALOG[0][0].artist: 1.0}}
    )
    result = await SessionRecommender(
        catalog, today=date(2026, 6, 1), rights=DenyFirstArtist()
    ).candidates(request)
    assert result.candidates
    # Even with the strongest possible weight, a refused artist never appears.
    assert all(c.track.artist != CATALOG[0][0].artist for c in result.candidates)
