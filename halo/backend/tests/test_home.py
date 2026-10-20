"""Server-driven Home feed."""

from __future__ import annotations

from typing import Any

import httpx

from app.services.music_sources.similar_artists import SimilarArtist
from tests.conftest import AppFactory, make_settings, register
from tests.test_api import PREFS
from tests.test_brainz import make_lb


class FakeSimilar:
    def __init__(self, fail: bool = False) -> None:
        self.fail = fail
        self.seeds: list[str] = []

    async def similar(self, artist: str, *, limit: int = 10) -> list[SimilarArtist]:
        if self.fail:
            raise httpx.ConnectError("down")
        self.seeds.append(artist)
        return [
            SimilarArtist("Keerthi Waves", 0.9, "ListenBrainz"),
            SimilarArtist("Northern Static", 0.8, "ListenBrainz"),  # excluded by the listener
            SimilarArtist("Madras Monsoon", 0.7, "ListenBrainz"),
        ]

    async def aclose(self) -> None:
        return None


def by_type(feed: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {s["type"]: s for s in feed["sections"]}


async def test_new_listener_gets_generic_feed_in_score_order(app_factory: AppFactory) -> None:
    _, client = await app_factory()
    async with client:
        auth = await register(client)
        response = await client.get("/api/v1/home", headers=auth)
    assert response.status_code == 200, response.text
    feed = response.json()
    sections = by_type(feed)
    assert feed["personalized"] is False
    scores = [s["score"] for s in feed["sections"]]
    assert scores == sorted(scores, reverse=True)
    assert "because_you_like" not in sections and "your_artists" not in sections
    # Device-only sections are placeholders the app fills in.
    assert sections["recently_discovered"]["layout"] == "local"
    assert sections["recently_discovered"]["items"] == []
    languages = sections["languages"]
    assert languages["title"] == "Explore by language"
    assert [i["title"] for i in languages["items"]][:2] == ["Telugu hits", "Hindi hits"]
    assert all(i["kind"] == "query" and i["query"] for i in languages["items"])
    assert {i["id"] for i in sections["soundtracks"]["items"]} == {
        "film:Telugu",
        "film:Hindi",
        "film:Tamil",
        "film:Malayalam",
        "film:Kannada",
    }
    assert [i["id"] for i in sections["moods"]["items"]][0] == "focused"
    trending = sections["trending"]
    assert trending["source"] == "YouTube"
    assert trending["items"] and all(i["track"]["video_id"] == i["id"] for i in trending["items"])
    # ListenBrainz is off in tests, so its sections are simply absent.
    assert "fresh_releases" not in sections and "most_listened" not in sections


async def test_personalized_feed_uses_saves_and_preferences(app_factory: AppFactory) -> None:
    app, client = await app_factory()
    similar = FakeSimilar()
    app.state.home_feed._similar = similar
    async with client:
        auth = await register(client)
        assert (
            await client.put("/api/v1/preferences", json=PREFS, headers=auth)
        ).status_code == 200
        saved = await client.post(
            "/api/v1/recommendations/feedback",
            headers=auth,
            json={
                "video_id": "tstAAAAAAA1",
                "rating": "save",
                "channel_title": "Aarav Strings - Topic",
            },
        )
        assert saved.status_code in (200, 201), saved.text
        feed = (await client.get("/api/v1/home", headers=auth)).json()
    sections = by_type(feed)
    assert feed["personalized"] is True
    assert similar.seeds == ["Aarav Strings"]  # "- Topic" stripped
    because = sections["because_you_like"]
    assert feed["sections"][0]["type"] == "because_you_like"
    assert because["eyebrow"] == "Because you saved Aarav Strings"
    assert [i["title"] for i in because["items"]] == ["Keerthi Waves", "Madras Monsoon"]
    assert because["items"][0]["query"] == "Keerthi Waves"
    assert sections["languages"]["title"] == "In your languages"
    assert [i["title"] for i in sections["languages"]["items"]][:2] == ["Telugu hits", "Hindi hits"]
    assert [i["title"] for i in sections["your_artists"]["items"]] == ["Aarav Strings"]


async def test_weights_reorder_and_remove_sections(app_factory: AppFactory) -> None:
    settings = make_settings(home_section_weights={"trending": 0, "most_listened": 99})
    app, client = await app_factory(settings=settings)
    app.state.home_feed._listenbrainz = make_lb([])
    async with client:
        auth = await register(client)
        feed = (await client.get("/api/v1/home", headers=auth)).json()
    sections = by_type(feed)
    assert "trending" not in sections
    assert feed["sections"][0]["type"] == "most_listened"
    charts = sections["most_listened"]
    assert charts["layout"] == "rows" and charts["items"][0]["badge"] == "#1"
    assert charts["items"][0]["query"] == "Ellie Goulding Love Me Like You Do"
    fresh = sections["fresh_releases"]
    assert fresh["source"] == "ListenBrainz · Cover Art Archive"
    assert fresh["items"][0]["artwork_url"].startswith("https://coverartarchive.org/")


async def test_failing_section_is_dropped_not_fatal(app_factory: AppFactory) -> None:
    app, client = await app_factory()
    app.state.home_feed._similar = FakeSimilar(fail=True)
    async with client:
        auth = await register(client)
        await client.put("/api/v1/preferences", json=PREFS, headers=auth)
        await client.post(
            "/api/v1/recommendations/feedback",
            headers=auth,
            json={"video_id": "tstAAAAAAA1", "rating": "like", "channel_title": "Aarav Strings"},
        )
        response = await client.get("/api/v1/home", headers=auth)
    assert response.status_code == 200
    sections = by_type(response.json())
    assert "because_you_like" not in sections and "moods" in sections


async def test_home_requires_auth(client: httpx.AsyncClient) -> None:
    assert (await client.get("/api/v1/home")).status_code == 401
