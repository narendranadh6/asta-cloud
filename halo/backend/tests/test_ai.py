"""AI planning: schema validation, deterministic fallback, verified-results pipeline."""

from __future__ import annotations

import json

import httpx
import pytest
from pydantic import ValidationError

from app.schemas import Attribution, Track
from app.services.ai.heuristic import PreferenceHints, extract_intent
from app.services.ai.intent import MusicIntent
from app.services.ai.providers import (
    IntentPlanner,
    PlannerError,
    PlanOverrides,
    parse_intent_json,
)
from app.services.recommendations.pipeline import (
    Candidate,
    FeedbackSignals,
    diversify,
    filter_candidates,
    score_candidates,
    song_key,
)
from tests.conftest import AppFactory, register

# --- Schema ----------------------------------------------------------------------------


def test_intent_schema_accepts_valid_payload() -> None:
    intent = MusicIntent.model_validate(
        {
            "mood": "focused",
            "language": "Telugu",
            "genres": ["melody", "Melody", "acoustic"],
            "energy": 35,
            "duration_minutes": 60,
            "discovery": "balanced",
            "search_queries": ["telugu melody songs", "telugu acoustic"],
        }
    )
    assert intent.genres == ["melody", "acoustic"]


@pytest.mark.parametrize(
    "bad",
    [
        {"search_queries": []},
        {"search_queries": ["https://www.youtube.com/watch?v=dQw4w9WgXcQ"]},
        {"search_queries": ["youtu.be/dQw4w9WgXcQ"]},
        {"search_queries": ["song watch?v=abc"]},
        {"search_queries": ["ok"], "energy": 150},
        {"search_queries": ["ok"], "mood": "angry"},
        {"search_queries": ["ok"], "duration_minutes": 2},
        {"search_queries": ["ok"], "discovery": "random"},
    ],
)
def test_intent_schema_rejects_invalid_payloads(bad: dict[str, object]) -> None:
    with pytest.raises(ValidationError):
        MusicIntent.model_validate(bad)


def test_parse_intent_json_handles_fenced_output() -> None:
    raw = 'Sure!\n```json\n{"mood": "calm", "search_queries": ["calm piano"]}\n```'
    assert parse_intent_json(raw).mood == "calm"
    with pytest.raises(PlannerError):
        parse_intent_json("no json here")
    with pytest.raises(PlannerError):
        parse_intent_json('{"search_queries": ["http://evil.example"]}')


# --- Heuristic planner -----------------------------------------------------------------


def test_heuristic_telugu_2000s_melodies() -> None:
    intent = extract_intent("Find relaxing Telugu melodies from the 2000s.")
    assert intent.mood == "calm"
    assert intent.language == "Telugu"
    assert "melody" in intent.genres
    assert intent.era == "2000s"
    assert intent.energy <= 40
    assert any("Telugu melody" in q for q in intent.search_queries)


def test_heuristic_coding_minimal_vocals() -> None:
    intent = extract_intent("Create a late-night coding playlist with minimal vocals.")
    assert intent.mood == "focused"
    assert intent.activity == "coding"
    assert intent.vocals == "minimal"
    assert intent.energy <= 45


def test_heuristic_road_trip_duration() -> None:
    intent = extract_intent("Build a playlist for a two-hour road trip.")
    assert intent.duration_minutes == 120
    assert intent.mood == "travel"
    assert intent.activity == "road trip"


def test_heuristic_discovery_uses_favorites() -> None:
    hints = PreferenceHints(favorite_artists=["Aarav Strings"], excluded_artists=["X Band"])
    intent = extract_intent("Recommend songs similar to my favorites but less popular.", hints)
    assert intent.discovery == "discovery"
    assert "Aarav Strings" in intent.reference_artists
    assert intent.exclude_artists == ["X Band"]


def test_heuristic_overrides_win() -> None:
    intent = extract_intent("happy songs", mood="sleep", duration_minutes=30, energy=5)
    assert (intent.mood, intent.duration_minutes, intent.energy) == ("sleep", 30, 5)


# --- LLM planner with fallback ----------------------------------------------------------


class FakeLLM:
    def __init__(self, response: str | Exception) -> None:
        self.response = response
        self.calls: list[tuple[str, str]] = []

    async def complete_json(self, system: str, user: str) -> str:
        self.calls.append((system, user))
        if isinstance(self.response, Exception):
            raise self.response
        return self.response

    async def aclose(self) -> None:
        return None


async def test_llm_plan_is_used_and_overrides_applied() -> None:
    llm = FakeLLM(
        json.dumps(
            {
                "mood": "happy",
                "search_queries": ["sunny pop"],
                "duration_minutes": 45,
                "playlist_title": "Sunny",
            }
        )
    )
    planner = IntentPlanner(llm)
    result = await planner.plan(
        "upbeat", PreferenceHints(excluded_artists=["Nope"]), PlanOverrides(duration_minutes=90)
    )
    assert result.planner == "llm"
    assert result.intent.duration_minutes == 90
    assert result.intent.exclude_artists == ["Nope"]
    assert '"excluded_artists": ["Nope"]' in llm.calls[0][1]


@pytest.mark.parametrize(
    "response",
    [
        httpx.ConnectError("down"),
        PlannerError("bad"),
        '{"search_queries": ["https://x.com"]}',
        "not json",
    ],
)
async def test_llm_failure_falls_back_to_heuristic(response: str | Exception) -> None:
    result = await IntentPlanner(FakeLLM(response)).plan("calm telugu", PreferenceHints())
    assert result.planner == "heuristic"
    assert result.warning
    assert result.intent.language == "Telugu"


# --- Pipeline stages --------------------------------------------------------------------


def make_track(
    source_id: str,
    title: str,
    artist: str,
    *,
    duration: int = 200,
    plays: int = 1000,
    playable: bool = True,
    preview: bool = False,
) -> Track:
    return Track(
        id=f"audius:{source_id}",
        source="audius",
        source_id=source_id,
        title=title,
        artist=artist,
        duration_seconds=duration,
        play_count=plays,
        is_preview=preview,
        stream_url=f"https://stream.test/{source_id}.mp3" if playable else None,
        attribution=Attribution(provider="audius", label="Audius"),
    )


def intent(**kw: object) -> MusicIntent:
    return MusicIntent.model_validate({"search_queries": ["q"], **kw})


def test_filtering_rules() -> None:
    cands = [
        Candidate(make_track("aaaaaaaaaaa", "Good Song", "Artist A"), "q", 0),
        Candidate(make_track("aaaaaaaaaaa", "Good Song", "Artist A"), "q2", 0),
        Candidate(make_track("bbbbbbbbbbb", "Excluded tune", "Bad Band"), "q", 1),
        Candidate(make_track("ccccccccccc", "Short", "C", duration=30), "q", 2),
        Candidate(make_track("ddddddddddd", "Jukebox", "D", duration=3600), "q", 3),
        Candidate(make_track("eeeeeeeeeee", "Gone", "E", playable=False), "q", 4),
        Candidate(make_track("fffffffffff", "Disliked", "F"), "q", 5),
        Candidate(make_track("ggggggggggg", "Skip me", "G"), "q", 6),
    ]
    kept, counts = filter_candidates(
        cands,
        intent(exclude_artists=["bad band"]),
        PreferenceHints(),
        FeedbackSignals(disliked_track_ids={"audius:fffffffffff"}),
        {"audius:ggggggggggg"},
    )
    assert [c.track.id for c in kept] == ["audius:aaaaaaaaaaa"]
    assert counts == {
        "duplicate": 1,
        "excluded_artist": 1,
        "duration": 2,
        "not_playable": 1,
        "disliked": 1,
        "excluded_track": 1,
    }


def test_scoring_respects_discovery_preference() -> None:
    popular = Candidate(make_track("aaaaaaaaaaa", "Hit", "A", plays=50_000_000), "q", 0)
    obscure = Candidate(make_track("bbbbbbbbbbb", "Gem", "B", plays=2_000), "q", 0)
    middle = Candidate(make_track("ccccccccccc", "Mid", "C", plays=200_000), "q", 0)
    score_candidates(
        [popular, obscure, middle],
        intent(discovery="discovery"),
        PreferenceHints(),
        FeedbackSignals(),
    )
    assert obscure.score > popular.score
    score_candidates(
        [popular, obscure, middle],
        intent(discovery="familiar"),
        PreferenceHints(),
        FeedbackSignals(),
    )
    assert popular.score > obscure.score
    assert all(c.reasons for c in (popular, obscure, middle))


def test_previews_score_below_full_songs() -> None:
    full = Candidate(make_track("full0000001", "Song", "A"), "q", 0)
    preview = Candidate(make_track("prev0000001", "Song Two", "B", preview=True), "q", 0)
    score_candidates([full, preview], intent(), PreferenceHints(), FeedbackSignals())
    assert full.score > preview.score


def test_diversity_caps_channels_and_duplicates() -> None:
    cands = [
        Candidate(make_track(f"a{i:010d}", f"Song {i}", "Same Channel"), "q", i) for i in range(6)
    ]
    cands += [
        Candidate(make_track("dup00000001", "Artist - Tune (Official Video)", "X"), "q", 0),
        Candidate(make_track("dup00000002", "Artist - Tune (Lyrical)", "Y"), "q", 1),
    ]
    for c in cands:
        c.score = 1.0 - c.rank * 0.01
    chosen = diversify(cands, intent(discovery="balanced"), target_seconds=10_000)
    channels = [c.track.artist for c in chosen]
    assert channels.count("Same Channel") == 3
    assert sum(1 for c in chosen if c.track.source_id.startswith("dup")) == 1
    assert song_key(cands[-1].track) == song_key(cands[-2].track)


def test_diversity_stops_at_target_duration() -> None:
    cands = [
        Candidate(make_track(f"b{i:010d}", f"T{i}", f"C{i}", duration=300), "q", i)
        for i in range(30)
    ]
    chosen = diversify(cands, intent(), target_seconds=1200)
    assert len(chosen) == 4


# --- Endpoints --------------------------------------------------------------------------


async def test_ai_playlist_returns_only_verified_tracks(app_factory: AppFactory) -> None:
    app, client = await app_factory()
    async with client:
        auth = await register(client)
        response = await client.post(
            "/api/v1/ai/playlist",
            json={
                "description": "relaxing Telugu melodies from the 2000s",
                "mood": "calm",
                "duration_minutes": 30,
            },
            headers=auth,
        )
        assert response.status_code == 200, response.text
        draft = response.json()
        assert draft["planner"] == "heuristic"
        assert draft["tracks"], draft
        assert draft["session_id"] is None  # personalization off → nothing stored
        ids = [t["track"]["id"] for t in draft["tracks"]]
        verified = await app.state.catalog.get_tracks(ids)
        assert set(ids) == set(verified)
        assert all(t["track"]["stream_url"] for t in draft["tracks"])
        assert all(t["reasons"] for t in draft["tracks"])

        saved = await client.post(
            "/api/v1/playlists",
            json={"name": draft["title"], "track_ids": ids, "is_ai_generated": True},
            headers=auth,
        )
        assert saved.status_code == 201
        assert saved.json()["is_ai_generated"] is True


async def test_ai_chat_stores_conversation_only_with_consent(app_factory: AppFactory) -> None:
    _, client = await app_factory()
    async with client:
        auth = await register(client)
        first = await client.post(
            "/api/v1/ai/chat",
            json={"message": "late-night coding with minimal vocals"},
            headers=auth,
        )
        assert first.status_code == 200
        assert first.json()["stored"] is False
        assert first.json()["conversation_id"] is None
        await client.put(
            "/api/v1/preferences",
            json={"personalization_enabled": True, "store_ai_conversations": True},
            headers=auth,
        )
        second = await client.post(
            "/api/v1/ai/chat", json={"message": "a two-hour road trip"}, headers=auth
        )
        body = second.json()
        assert body["stored"] is True and body["conversation_id"]
        assert body["draft"]["session_id"]
        feedback = await client.post(
            "/api/v1/recommendations/feedback",
            json={
                "track_id": body["draft"]["tracks"][0]["track"]["id"],
                "rating": "dislike",
                "session_id": body["draft"]["session_id"],
            },
            headers=auth,
        )
        assert feedback.json()["recorded"] is True
        disliked = body["draft"]["tracks"][0]["track"]["id"]
        third = await client.post(
            "/api/v1/ai/chat", json={"message": "a two-hour road trip"}, headers=auth
        )
        assert disliked not in {t["track"]["id"] for t in third.json()["draft"]["tracks"]}


async def test_ai_with_failing_llm_still_works(app_factory: AppFactory) -> None:
    _, client = await app_factory(planner=IntentPlanner(FakeLLM(httpx.ConnectError("down"))))
    async with client:
        auth = await register(client)
        response = await client.post(
            "/api/v1/ai/chat", json={"message": "happy korean pop"}, headers=auth
        )
    draft = response.json()["draft"]
    assert draft["planner"] == "heuristic"
    assert draft["tracks"]
    assert draft["warnings"][0].startswith("The AI planner was unavailable")
