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
    RightsPolicy,
    SourcePolicyRightsResolver,
    creative_commons_code,
    playable,
)
from app.services.catalog.service import CatalogService
from app.services.recommendations.session import SessionRecommender
from tests.fakes import CATALOG, FakeCatalogSource

PERSONAL = RightsPolicy(deployment_use="non_commercial")
CC_BY_NC = TrackLicense(name="CC BY-NC 4.0", url="https://creativecommons.org/licenses/by-nc/4.0/")
CC_BY = TrackLicense(name="CC BY 4.0", url="https://creativecommons.org/licenses/by/4.0/")


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


def test_personal_use_allows_only_authorised_full_streams() -> None:
    rights = SourcePolicyRightsResolver(PERSONAL)
    assert rights.decide(track()).playable
    assert rights.decide(track("audius", is_preview=True)).reason == "preview_only"
    assert rights.decide(track("audius", stream_url=None)).reason == "no_stream"
    assert rights.decide(track("itunes")).reason == "source_not_authorised"
    assert rights.decide(track("jamendo")).reason == "unknown_licence"
    fake_cc = TrackLicense(name="CC BY 4.0", url="https://cc.test")  # looks like CC, isn't
    assert rights.decide(track("jamendo", license=fake_cc)).reason == "unknown_licence"
    assert rights.decide(track("jamendo", license=CC_BY_NC)).basis == "creative_commons"
    assert playable([track(), track("itunes")], rights) == [track()]


def test_commercial_use_fails_closed_until_rights_are_confirmed() -> None:
    default = SourcePolicyRightsResolver()  # commercial, nothing confirmed
    assert default.decide(track()).reason == "commercial_terms_unconfirmed"
    # A Creative Commons licence alone never allows commercial streaming, even CC BY.
    assert default.decide(track("jamendo", license=CC_BY)).reason == "commercial_licence_missing"
    assert default.decide(track("jamendo", license=CC_BY_NC)).reason == "commercial_licence_missing"
    confirmed = SourcePolicyRightsResolver(
        RightsPolicy(audius_terms_confirmed=True, jamendo_commercial_license=True)
    )
    assert confirmed.decide(track()).playable
    assert confirmed.decide(track("jamendo", license=CC_BY_NC)).playable
    assert not confirmed.decide(track("jamendo")).playable  # unknown licence: still refused


def test_creative_commons_codes_are_parsed_strictly() -> None:
    assert creative_commons_code("https://creativecommons.org/licenses/by-nc-sa/3.0/") == "by-nc-sa"
    assert creative_commons_code("http://www.creativecommons.org/licenses/by/2.5/") == "by"
    assert creative_commons_code("https://creativecommons.org/licenses/zz/1.0/") is None
    assert creative_commons_code("https://evil.test/creativecommons.org/licenses/by/4.0/") is None
    assert creative_commons_code(None) is None


async def test_search_finds_refused_tracks_but_never_hands_out_their_stream() -> None:
    commercial = CatalogService(
        [FakeCatalogSource()], MemoryStore(), rights=SourcePolicyRightsResolver()
    )
    found = (await commercial.search("telugu melody")).page.items
    assert found, "search still finds and shows songs"
    assert all(not t.playback_authorized and t.stream_url is None for t in found)
    assert {t.playback_restriction for t in found} == {"commercial_terms_unconfirmed"}
    personal = CatalogService([FakeCatalogSource()], MemoryStore())
    allowed = (await personal.search("telugu melody")).page.items
    assert all(t.playback_authorized and t.stream_url for t in allowed)


async def test_router_checks_rights_then_entitlement_then_player() -> None:
    router = PlaybackRouter(
        SourcePolicyRightsResolver(PERSONAL),
        OpenCatalogEntitlements(),
        {"audius": StreamUrlPlayback()},
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
        catalog, today=date(2026, 6, 1), rights=DenyFirstArtist(PERSONAL)
    ).candidates(request)
    assert result.candidates
    # Even with the strongest possible weight, a refused artist never appears.
    assert all(c.track.artist != CATALOG[0][0].artist for c in result.candidates)
