"""Halo Drive session candidates: voice session state → ranked, explainable songs."""

from __future__ import annotations

from datetime import date

import httpx

from app.core.cache import MemoryStore
from app.schemas import SessionCandidatesRequest
from app.services.catalog.service import CatalogService
from app.services.recommendations.session import RANKING_VERSION, SessionRecommender, queries_for
from tests.fakes import FakeCatalogSource


def recommender() -> SessionRecommender:
    catalog = CatalogService([FakeCatalogSource()], MemoryStore())
    return SessionRecommender(catalog, today=date(2026, 6, 1))


def request(**fields: object) -> SessionCandidatesRequest:
    return SessionCandidatesRequest.model_validate(fields)


async def test_telugu_only_energetic_session() -> None:
    result = await recommender().candidates(
        request(vibe={"energy": 0.9}, language={"primary": "te", "strategy": "only"})
    )
    tracks = [c.track for c in result.candidates]
    assert tracks, "expected candidates"
    assert all(t.language == "te" for t in tracks)  # "only" drops other known languages
    top = tracks[:3]
    assert all((t.energy or 0) >= 0.75 for t in top)  # the most energetic first
    assert result.ranking_version == RANKING_VERSION
    assert set(result.candidates[0].fit) >= {"energy", "language", "recency", "seed", "artist"}


async def test_calm_targets_and_artist_cap() -> None:
    result = await recommender().candidates(
        request(vibe={"energy": 0.15}, language={"primary": "te"})
    )
    assert (result.candidates[0].track.energy or 1) <= 0.3
    artists = [c.track.artist for c in result.candidates]
    assert max(artists.count(a) for a in set(artists)) <= 2


async def test_exclusions_and_downweights_are_respected() -> None:
    base = await recommender().candidates(request(language={"primary": "te"}))
    first = base.candidates[0].track
    excluded = await recommender().candidates(
        request(
            language={"primary": "te"},
            excluded_artists=[first.artist.upper()],
            excluded_track_ids=[base.candidates[1].track.id],
        )
    )
    ids = {c.track.id for c in excluded.candidates}
    assert all(c.track.artist != first.artist for c in excluded.candidates)
    assert base.candidates[1].track.id not in ids
    down = await recommender().candidates(
        request(language={"primary": "te"}, artist_weights={first.artist: -1.0})
    )
    assert down.candidates[0].track.artist != first.artist


async def test_mostly_telugu_with_some_english_is_interleaved() -> None:
    result = await recommender().candidates(
        request(language={"primary": "te", "secondary": "en", "strategy": "mostly"}, limit=20)
    )
    languages = [c.track.language for c in result.candidates]
    assert "en" in languages and languages.count("te") > languages.count("en")
    assert languages[0] == "te"


async def test_recency_prefers_the_requested_era() -> None:
    result = await recommender().candidates(
        request(language={"primary": "te"}, recency={"mode": "decade", "value": 2000})
    )
    years = [int((c.track.release_date or "0")[:4]) for c in result.candidates[:3]]
    assert all(2000 <= y < 2010 for y in years)


def test_queries_follow_the_session() -> None:
    entity = queries_for(request(entity={"name": "DSP", "kind": "artist"}), None)
    assert entity[0] == ("DSP", "entity")
    vibe = queries_for(request(vibe={"energy": 0.9}, language={"primary": "te"}), None)
    assert ("telugu energetic", "intent") in vibe and ("telugu", "intent") in vibe


async def test_endpoint(client: httpx.AsyncClient, auth: dict[str, str]) -> None:
    response = await client.post(
        "/api/v1/session/candidates",
        json={"vibe": {"energy": 0.9}, "language": {"primary": "te"}, "limit": 10},
        headers=auth,
    )
    assert response.status_code == 200
    body = response.json()
    assert 0 < len(body["candidates"]) <= 10
    assert body["candidates"][0]["track"]["stream_url"]
    bad = await client.post(
        "/api/v1/session/candidates", json={"vibe": {"energy": 3}}, headers=auth
    )
    assert bad.status_code == 422
