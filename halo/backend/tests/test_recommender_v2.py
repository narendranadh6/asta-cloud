"""Recommender v2: bandit exploration, learnable ranker, co-listening, open data sources."""

from __future__ import annotations

import random
from collections import Counter
from typing import Any

import httpx
import pytest
from sqlalchemy import select

from app.core.cache import MemoryStore
from app.models import BanditArm
from app.repositories import recommendations as rec_repo
from app.schemas import Attribution, Track
from app.services.ai.heuristic import PreferenceHints
from app.services.ai.intent import MusicIntent
from app.services.music_sources.radio import RadioBrowserClient, RadioUnavailableError
from app.services.music_sources.similar_artists import (
    CachedSimilarArtists,
    DeezerRelatedArtists,
    LastFmSimilarArtists,
    SimilarArtist,
)
from app.services.recommendations.bandit import ArmPosterior, choose_arm, combine, explore_quota
from app.services.recommendations.pipeline import Candidate, rank_and_explore
from app.services.recommendations.ranker import DEFAULT_WEIGHTS, RankerModel, train
from tests.conftest import AppFactory, register

# --- Bandit -----------------------------------------------------------------------------


def test_explore_quota_follows_discovery_preference() -> None:
    assert explore_quota("familiar", 20) == 2
    assert explore_quota("balanced", 20) == 4
    assert explore_quota("discovery", 20) == 7


def test_thompson_sampling_prefers_rewarded_arm() -> None:
    rng = random.Random(1)
    posteriors = {"search": ArmPosterior(2, 20), "co_listen": ArmPosterior(20, 2)}
    picks = Counter(choose_arm(posteriors, {"search", "co_listen"}, rng) for _ in range(500))
    assert picks["co_listen"] > 450
    assert choose_arm(posteriors, set(), rng) is None


def test_combine_weights_user_evidence_over_population() -> None:
    post = combine(user=(1.0, 11.0), global_=(51.0, 1.0))  # crowd counts 0.1x
    assert post.mean < 0.5  # this listener's dislikes outweigh the crowd's likes


# --- Ranker -----------------------------------------------------------------------------


def test_ranker_learns_from_feedback_and_shrinks_to_prior() -> None:
    liked = {"relevance": 1.0, "co_listen": 1.0, "cf_score": 0.6}
    disliked = {"relevance": 1.0, "co_listen": 0.0, "cf_score": 0.0}
    model = train([(liked, 1)] * 40 + [(disliked, 0)] * 40)
    assert model.weights["co_listen"] > DEFAULT_WEIGHTS["co_listen"]
    assert model.probability(liked) > model.probability(disliked)
    assert model.trained_examples == 80
    assert train([]).weights == DEFAULT_WEIGHTS


def test_ranker_payload_rejects_junk() -> None:
    model = RankerModel.from_payload(
        {
            "weights": {"relevance": "x", "cf_score": float("nan"), "co_listen": 2.0, "evil": 9},
            "bias": "y",
        }
    )
    assert model.weights["relevance"] == DEFAULT_WEIGHTS["relevance"]
    assert model.weights["cf_score"] == DEFAULT_WEIGHTS["cf_score"]
    assert model.weights["co_listen"] == 2.0
    assert "evil" not in model.weights and model.bias == 0.0


# --- Exploration slots -------------------------------------------------------------------


def _track(i: int, artist: str, plays: int = 10_000) -> Track:
    sid = f"t{i:010d}"
    return Track(
        id=f"audius:{sid}",
        source="audius",
        source_id=sid,
        title=f"Song {i}",
        artist=artist,
        duration_seconds=200,
        play_count=plays,
        stream_url=f"https://stream.test/{sid}.mp3",
        attribution=Attribution(provider="audius", label="Audius"),
    )


def test_rank_and_explore_reserves_spread_out_exploration_slots() -> None:
    cands = [
        Candidate(_track(i, f"Search Artist {i}"), "q", i, features={"relevance": 2.0 - i * 0.01})
        for i in range(30)
    ]
    cands += [
        Candidate(
            _track(100 + i, f"Colisten Artist {i}"),
            "cf",
            i,
            source="co_listen",
            features={"relevance": 0.5, "co_listen": 1.0},
        )
        for i in range(10)
    ]
    intent = MusicIntent(search_queries=["q"], discovery="discovery")
    chosen = rank_and_explore(
        cands,
        intent,
        20 * 200,
        ranker=RankerModel(),
        posteriors={"co_listen": ArmPosterior(30, 1), "search": ArmPosterior(1, 30)},
        favorites=set(),
        rng=random.Random(3),
    )
    explore = [i for i, c in enumerate(chosen) if c.explore]
    assert len(explore) == explore_quota("discovery", 20)
    assert all(chosen[i].source == "co_listen" for i in explore)
    assert all(chosen[i].reasons[0] == "Something new for you" for i in explore)
    assert explore[0] > 0 and explore != list(range(explore[0], explore[0] + len(explore)))
    assert len({c.track.artist for c in chosen if c.explore}) == len(explore)


# --- Co-listening (collaborative filtering) ---------------------------------------------


async def _listener(
    client: httpx.AsyncClient, track_ids: list[str], opted_in: bool
) -> dict[str, str]:
    auth = await register(client)
    await client.put(
        "/api/v1/preferences", headers=auth, json={"personalization_enabled": opted_in}
    )
    await client.post("/api/v1/playlists", headers=auth, json={"name": "p", "track_ids": track_ids})
    return auth


async def test_co_listening_needs_two_opted_in_listeners(app_factory: AppFactory) -> None:
    app, client = await app_factory()
    async with client:
        auth = await register(client)
        found = await client.get("/api/v1/search", params={"q": "telugu", "limit": 6}, headers=auth)
        a, b, c, d, e, f = [i["id"] for i in found.json()["items"]]
        await _listener(client, [a, b, c], opted_in=True)
        await _listener(client, [a, b, d], opted_in=True)
        await _listener(client, [a, e], opted_in=True)  # a+e seen by one listener only
        await _listener(client, [a, f], opted_in=False)  # not consented: ignored
        await _listener(client, [a, f], opted_in=False)
    async with app.state.session_factory() as session:
        pairs = await rec_repo.co_listened(session, [a])
    ids = [p.track_id for p in pairs]
    assert ids[0] == b  # co-listened by two consenting listeners
    assert e not in ids and f not in ids  # single-listener and non-consenting pairs hidden
    assert c not in ids and d not in ids
    assert pairs[0].listeners == 2 and 0 < pairs[0].score <= 1


async def test_feedback_credits_the_recommending_source(app_factory: AppFactory) -> None:
    app, client = await app_factory()
    async with client:
        auth = await register(client)
        await client.put(
            "/api/v1/preferences", headers=auth, json={"personalization_enabled": True}
        )
        chat = (
            await client.post(
                "/api/v1/ai/chat", headers=auth, json={"message": "calm telugu melodies"}
            )
        ).json()
        track = chat["draft"]["tracks"][0]
        await client.post(
            "/api/v1/recommendations/feedback",
            headers=auth,
            json={
                "track_id": track["track"]["id"],
                "rating": "like",
                "session_id": chat["draft"]["session_id"],
            },
        )
    async with app.state.session_factory() as session:
        arms = (await session.execute(select(BanditArm))).scalars().all()
        examples = await rec_repo.training_examples(session)
    assert {(arm.arm, arm.successes) for arm in arms} == {(track["source"], 2.0)}
    assert len(arms) == 2  # global + this listener
    assert examples and examples[0][1] == 1 and "relevance" in examples[0][0]


async def test_up_next_excludes_seed_and_uses_co_listening(app_factory: AppFactory) -> None:
    _, client = await app_factory()
    async with client:
        auth = await register(client)
        found = (
            await client.get("/api/v1/search", params={"q": "hindi love", "limit": 3}, headers=auth)
        ).json()["items"]
        seed, partner = found[0]["id"], found[2]["id"]
        await _listener(client, [seed, partner], opted_in=True)
        await _listener(client, [seed, partner], opted_in=True)
        response = await client.get(
            "/api/v1/recommendations/next", params={"track_id": seed, "limit": 8}, headers=auth
        )
        bad = await client.get(
            "/api/v1/recommendations/next", params={"track_id": "bad"}, headers=auth
        )
    body = response.json()
    assert response.status_code == 200, body
    ids = [t["track"]["id"] for t in body["tracks"]]
    assert seed not in ids and 0 < len(ids) <= 8
    assert partner in ids
    assert any(t["source"] == "co_listen" for t in body["tracks"])
    assert bad.status_code == 422


# --- Open data sources --------------------------------------------------------------------


def _mock(handler: Any, base: str) -> httpx.AsyncClient:
    return httpx.AsyncClient(transport=httpx.MockTransport(handler), base_url=base)


async def test_lastfm_similar_artists_parsing() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.params["method"] == "artist.getsimilar"
        assert request.url.params["api_key"] == "k"
        return httpx.Response(
            200,
            json={
                "similarartists": {
                    "artist": [
                        {"name": "Shreya Ghoshal", "match": "1"},
                        {"name": "KK", "match": "0.62"},
                        {"name": "", "match": "0.5"},
                        {"name": "Bad", "match": "oops"},
                    ]
                }
            },
        )

    result = await LastFmSimilarArtists(
        "k", http_client=_mock(handler, "https://lfm.test/")
    ).similar("Arijit Singh")
    assert [(a.name, a.score) for a in result] == [
        ("Shreya Ghoshal", 1.0),
        ("KK", 0.62),
        ("Bad", 0.0),
    ]


async def test_deezer_related_and_cached_fallback() -> None:
    calls: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request.url.path)
        if request.url.path == "/search/artist":
            return httpx.Response(200, json={"data": [{"id": 27, "name": "Daft Punk"}]})
        return httpx.Response(200, json={"data": [{"name": "Justice"}, {"name": "Air"}]})

    class Broken:
        name = "broken"

        async def similar(self, artist: str, *, limit: int = 10) -> list[SimilarArtist]:
            raise httpx.ConnectError("down")

        async def aclose(self) -> None:
            return None

    chain = CachedSimilarArtists(
        [Broken(), DeezerRelatedArtists(http_client=_mock(handler, "https://dz.test"))],  # type: ignore[list-item]
        MemoryStore(),
    )
    first = await chain.similar("Daft Punk")
    again = await chain.similar("daft  punk")
    assert [a.name for a in first] == ["Justice", "Air"] and first[0].score > first[1].score
    assert [a.name for a in again] == ["Justice", "Air"]
    assert calls == ["/search/artist", "/artist/27/related"]  # second call served from cache


async def test_pipeline_expands_with_similar_artists(app_factory: AppFactory) -> None:
    class Similar:
        async def similar(self, artist: str, *, limit: int = 10) -> list[SimilarArtist]:
            return [SimilarArtist("Keerthi Waves", 0.9, "test")]

    app, client = await app_factory()
    app.state.pipeline._similar = Similar()
    async with client:
        auth = await register(client)
        draft = (
            await client.post(
                "/api/v1/ai/playlist",
                headers=auth,
                json={"description": "songs like Aarav Strings", "duration_minutes": 60},
            )
        ).json()
    similar = [t for t in draft["tracks"] if t["source"] == "similar_artist"]
    assert similar and all("Similar to Aarav Strings" in t["reasons"] for t in similar)


async def test_radio_browser_filters_and_caches() -> None:
    seen: list[dict[str, str]] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(dict(request.url.params))
        return httpx.Response(
            200,
            json=[
                {
                    "stationuuid": "a",
                    "name": " Radio  One ",
                    "url_resolved": "https://s.test/one",
                    "favicon": "https://s.test/f.png",
                    "tags": "telugu,film, ",
                    "countrycode": "IN",
                    "language": "telugu",
                    "codec": "MP3",
                    "bitrate": 128,
                    "clickcount": 900,
                    "lastcheckok": 1,
                },
                {
                    "stationuuid": "b",
                    "name": "Broken",
                    "url_resolved": "https://s.test/two",
                    "lastcheckok": 0,
                },
                {
                    "stationuuid": "c",
                    "name": "Weird",
                    "url_resolved": "javascript:alert(1)",
                    "lastcheckok": 1,
                },
            ],
        )

    radio = RadioBrowserClient(MemoryStore(), http_client=_mock(handler, "https://rb.test"))
    stations = await radio.search(tag="Telugu", country_code="in", limit=10)
    again = await radio.search(tag="Telugu", country_code="in", limit=10)
    assert [s.name for s in stations] == ["Radio One"] and stations == again
    assert stations[0].tags == ["telugu", "film"] and stations[0].favicon == "https://s.test/f.png"
    assert seen == [
        {
            "hidebroken": "true",
            "order": "clickcount",
            "reverse": "true",
            "limit": "10",
            "tag": "telugu",
            "countrycode": "IN",
        }
    ]


async def test_radio_endpoint_and_outage(app_factory: AppFactory) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.params.get("tag") == "down":
            return httpx.Response(503)
        return httpx.Response(
            200,
            json=[
                {
                    "stationuuid": "a",
                    "name": "Live",
                    "url_resolved": "https://s.test/live",
                    "lastcheckok": 1,
                }
            ],
        )

    app, client = await app_factory()
    app.state.radio = RadioBrowserClient(
        MemoryStore(), http_client=_mock(handler, "https://rb.test")
    )
    async with client:
        auth = await register(client)
        ok = await client.get("/api/v1/radio/stations", params={"tag": "jazz"}, headers=auth)
        down = await client.get("/api/v1/radio/stations", params={"tag": "down"}, headers=auth)
    assert ok.json()[0]["stream_url"] == "https://s.test/live"
    assert down.status_code == 502 and down.json()["error"]["code"] == "radio_unavailable"
    with pytest.raises(RadioUnavailableError):
        await RadioBrowserClient(
            MemoryStore(), http_client=_mock(lambda r: httpx.Response(500), "https://rb.test")
        ).search()


def test_pipeline_signature_accepts_hints() -> None:
    # Guard against accidental API drift used by the routes.
    assert PreferenceHints().excluded_artists == []
