"""MusicBrainz (canonical metadata) and ListenBrainz (discovery) integrations.

Response shapes follow the MusicBrainz ws/2 JSON format and the ListenBrainz server
source (listenbrainz/webserver/views/*.py).
"""

from __future__ import annotations

import time
from typing import Any

import httpx
import pytest

from app.core.cache import MemoryStore
from app.services.ai.heuristic import PreferenceHints
from app.services.ai.intent import MusicIntent
from app.services.music_sources.discovery import ListenBrainzDiscovery
from app.services.music_sources.listenbrainz import ListenBrainzClient, PopularRecording
from app.services.music_sources.musicbrainz import MusicBrainzClient, parse_youtube_title
from tests.conftest import AppFactory, register

ARTIST = "8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11"
SIMILAR = "5adcb9d9-5ea2-428d-af46-ef626966e106"
RECORDING = "e97f805a-ab48-4c52-855e-07049142113d"
RELEASE = "76df3287-6cda-33eb-8e9a-044b5e15ffdd"


def mb_handler(calls: list[str]) -> Any:
    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request.url.path)
        assert request.url.params["fmt"] == "json"
        assert "Halo/0.1" in request.headers["User-Agent"]
        path = request.url.path
        if path.endswith("/artist"):
            return httpx.Response(
                200, json={"artists": [{"id": ARTIST, "name": "Portishead", "score": 100}]}
            )
        if path.endswith(f"/artist/{ARTIST}"):
            return httpx.Response(
                200,
                json={
                    "id": ARTIST,
                    "name": "Portishead",
                    "sort-name": "Portishead",
                    "type": "Group",
                    "country": "GB",
                    "area": {"name": "United Kingdom"},
                    "life-span": {"begin": "1991"},
                    "genres": [
                        {"name": "electronic", "count": 3},
                        {"name": "trip hop", "count": 9},
                    ],
                },
            )
        if path.endswith("/recording"):
            return httpx.Response(
                200,
                json={
                    "recordings": [
                        {
                            "id": "00000000-0000-0000-0000-000000000001",
                            "score": 100,
                            "length": 600000,
                        },
                        {"id": RECORDING, "score": 98, "length": 262000},
                        {
                            "id": "00000000-0000-0000-0000-000000000002",
                            "score": 40,
                            "length": 262000,
                        },
                    ]
                },
            )
        if path.endswith(f"/recording/{RECORDING}"):
            return httpx.Response(
                200,
                json={
                    "id": RECORDING,
                    "title": "Glory Box",
                    "length": 262000,
                    "first-release-date": "1994-08-22",
                    "isrcs": ["GBF089400250"],
                    "artist-credit": [
                        {
                            "name": "Portishead",
                            "joinphrase": "",
                            "artist": {"id": ARTIST, "name": "Portishead"},
                        }
                    ],
                    "genres": [{"name": "trip hop", "count": 5}],
                    "releases": [
                        {
                            "id": "11111111-1111-1111-1111-111111111111",
                            "title": "Glory Box (single)",
                            "date": "1995-01-09",
                            "status": "Promotion",
                        },
                        {
                            "id": RELEASE,
                            "title": "Dummy",
                            "date": "1994-08-22",
                            "status": "Official",
                            "release-group": {
                                "id": "48140466-cff6-3222-bd55-63c27e43190d",
                                "primary-type": "Album",
                            },
                        },
                    ],
                },
            )
        if path.endswith(f"/release/{RELEASE}"):
            return httpx.Response(
                200,
                json={
                    "id": RELEASE,
                    "title": "Dummy",
                    "date": "1994-08-22",
                    "country": "GB",
                    "status": "Official",
                    "cover-art-archive": {"front": True},
                    "release-group": {
                        "id": "48140466-cff6-3222-bd55-63c27e43190d",
                        "primary-type": "Album",
                    },
                    "label-info": [
                        {"catalog-number": "828 522-2", "label": {"id": "lbl", "name": "Go! Beat"}}
                    ],
                },
            )
        return httpx.Response(404, json={"error": "Not Found"})

    return handler


def make_mb(calls: list[str], interval: float = 0.0) -> MusicBrainzClient:
    http = httpx.AsyncClient(
        transport=httpx.MockTransport(mb_handler(calls)), base_url="https://mb.test/ws/2"
    )
    return MusicBrainzClient(
        MemoryStore(), contact="https://example.test", http_client=http, min_interval=interval
    )


@pytest.mark.parametrize(
    ("title", "channel", "expected"),
    [
        ("Portishead - Glory Box (Official Video)", "Portishead", ("Portishead", "Glory Box")),
        ("Glory Box [Remastered 2014]", "Portishead - Topic", ("Portishead", "Glory Box")),
        ("Arijit Singh – Tum Hi Ho | Aashiqui 2", "T-Series", ("Arijit Singh", "Tum Hi Ho")),
        ("Kesariya (Lyrical) | Brahmastra", "Sony Music India", ("Sony Music India", "Kesariya")),
    ],
)
def test_parse_youtube_title(title: str, channel: str, expected: tuple[str, str]) -> None:
    assert parse_youtube_title(title, channel) == expected


async def test_musicbrainz_canonical_recording() -> None:
    calls: list[str] = []
    mb = make_mb(calls)
    recording = await mb.match_recording("Glory Box", "Portishead", duration_seconds=263)
    assert recording is not None
    assert recording.recording_mbid == RECORDING  # 600 s version skipped: length mismatch
    assert recording.isrcs == ["GBF089400250"] and recording.genres == ["trip hop"]
    assert recording.first_release_date == "1994-08-22"
    album = recording.releases[0]
    assert (album.title, album.release_group_type, album.labels[0].name) == (
        "Dummy",
        "Album",
        "Go! Beat",
    )
    assert album.labels[0].catalog_number == "828 522-2"
    assert album.cover_art_url == f"https://coverartarchive.org/release/{RELEASE}/front-250"
    assert recording.musicbrainz_url.endswith(RECORDING)
    # Cached: the same lookup does not hit MusicBrainz again.
    before = len(calls)
    await mb.match_recording("Glory Box", "Portishead", duration_seconds=263)
    assert len(calls) == before


async def test_musicbrainz_artist_and_low_confidence() -> None:
    mb = make_mb([])
    artist = await mb.find_artist("Portishead")
    assert artist is not None and artist.genres == ["trip hop", "electronic"]
    assert (artist.type, artist.country, artist.begin, artist.match_score) == (
        "Group",
        "GB",
        "1991",
        100,
    )
    assert await mb.find_artist("   ") is None


async def test_musicbrainz_respects_one_request_per_second() -> None:
    calls: list[str] = []
    mb = make_mb(calls, interval=0.2)
    started = time.monotonic()
    await mb.artist(ARTIST)
    await mb.find_artist("Portishead")  # search + (cached) lookup
    await mb._get("/artist", {"query": "other"})
    assert time.monotonic() - started >= 0.4 - 0.05  # 3 network calls, spaced 0.2 s


def lb_handler(calls: list[httpx.Request]) -> Any:
    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request)
        assert "Halo/0.1" in request.headers["User-Agent"]
        path = request.url.path
        if path.endswith("/explore/fresh-releases/"):
            return httpx.Response(
                200,
                json={
                    "payload": {
                        "total_count": 2,
                        "releases": [
                            {
                                "artist_credit_name": "Röyksopp",
                                "artist_mbids": [ARTIST],
                                "release_date": "2026-10-16",
                                "release_group_mbid": "rg1",
                                "release_group_primary_type": "Album",
                                "release_mbid": "r1",
                                "release_name": "Profound Mysteries IV",
                                "release_tags": ["electronic"],
                                "listen_count": 120,
                                "caa_id": 42,
                                "caa_release_mbid": "r1",
                            },
                            {
                                "artist_credit_name": "Nobody",
                                "release_date": "2026-10-15",
                                "release_mbid": "",
                                "release_name": "skip me",
                            },
                        ],
                    }
                },
            )
        if path.endswith("/stats/sitewide/recordings"):
            return httpx.Response(
                200,
                json={
                    "payload": {
                        "recordings": [
                            {
                                "artist_name": "Ellie Goulding",
                                "listen_count": 25,
                                "recording_mbid": RECORDING,
                                "release_name": "Delirium",
                                "track_name": "Love Me Like You Do",
                            }
                        ]
                    }
                },
            )
        if path.endswith(f"/lb-radio/artist/{ARTIST}"):
            params = request.url.params
            assert (params["mode"], params["pop_begin"], params["pop_end"]) in {
                ("easy", "50", "100"),
                ("medium", "20", "100"),
                ("hard", "0", "60"),
            }
            return httpx.Response(
                200,
                json={
                    ARTIST: [
                        {
                            "recording_mbid": "seed-rec",
                            "similar_artist_mbid": ARTIST,
                            "similar_artist_name": "Portishead",
                            "total_listen_count": 9999,
                        }
                    ],
                    SIMILAR: [
                        {
                            "recording_mbid": RECORDING,
                            "similar_artist_mbid": SIMILAR,
                            "similar_artist_name": "Beth Gibbons",
                            "total_listen_count": 500,
                        }
                    ],
                },
            )
        if path.endswith("/metadata/recording/"):
            assert request.url.params["inc"] == "artist"
            return httpx.Response(
                200,
                json={
                    RECORDING: {
                        "recording": {"name": "Tom the Model", "length": 260000},
                        "artist": {"name": "Beth Gibbons"},
                    }
                },
            )
        if path.startswith("/1/popularity/top-recordings-for-artist/"):
            assert request.headers["Authorization"] == "Token lb-token"
            return httpx.Response(
                200,
                json=[
                    {
                        "artist_name": "Portishead",
                        "recording_mbid": RECORDING,
                        "recording_name": "Roads",
                        "release_name": "Dummy",
                        "total_listen_count": 1380798,
                        "total_user_count": 129454,
                        "length": 305000,
                    }
                ],
            )
        return httpx.Response(404)

    return handler


def make_lb(calls: list[httpx.Request], token: str | None = None) -> ListenBrainzClient:
    http = httpx.AsyncClient(
        transport=httpx.MockTransport(lb_handler(calls)), base_url="https://lb.test/1"
    )
    client = ListenBrainzClient(MemoryStore(), token=token, http_client=http)
    return client


async def test_listenbrainz_fresh_releases_and_charts() -> None:
    calls: list[httpx.Request] = []
    lb = make_lb(calls)
    releases = await lb.fresh_releases(days=200, future=False)
    assert [r.release_name for r in releases] == ["Profound Mysteries IV"]
    assert releases[0].cover_art_url == "https://coverartarchive.org/release/r1/42-250.jpg"
    assert releases[0].listen_count == 120 and releases[0].release_type == "Album"
    assert calls[0].url.params["days"] == "90" and calls[0].url.params["future"] == "false"
    top = await lb.top_recordings(range_="month", count=500)
    assert top[0].title == "Love Me Like You Do" and top[0].listen_count == 25
    assert calls[1].url.params["count"] == "100"


async def test_listenbrainz_artist_radio_skips_seed_and_names_tracks() -> None:
    lb = make_lb([])
    recordings = await lb.artist_radio(ARTIST, discovery="discovery")
    assert [(r.artist_name, r.title, r.listen_count) for r in recordings] == [
        ("Beth Gibbons", "Tom the Model", 500)
    ]


async def test_listenbrainz_popularity_needs_token() -> None:
    calls: list[httpx.Request] = []
    assert await make_lb(calls).artist_top_recordings(ARTIST) == []
    assert calls == []  # no request without a token
    top = await make_lb(calls, token="lb-token").artist_top_recordings(ARTIST)
    assert top[0].title == "Roads" and top[0].listener_count == 129454


async def test_discovery_combines_musicbrainz_and_listenbrainz() -> None:
    discovery = ListenBrainzDiscovery(make_mb([]), make_lb([]))
    tracks = await discovery.tracks("Portishead", discovery="discovery")
    assert tracks[0].similar_to == "Portishead" and tracks[0].artist_name == "Beth Gibbons"
    similar = await discovery.similar("Portishead")
    assert [a.name for a in similar] == ["Beth Gibbons"] and similar[0].score == 1.0


class FakeDiscovery:
    def __init__(self, recordings: list[PopularRecording]) -> None:
        self.recordings = recordings

    async def tracks(
        self, seed: str, *, discovery: str = "balanced", limit: int = 6
    ) -> list[PopularRecording]:
        return [r.model_copy(update={"similar_to": seed}) for r in self.recordings[:limit]]

    async def similar(self, artist: str, *, limit: int = 10) -> list[Any]:
        return []


async def test_pipeline_adds_listenbrainz_picks_matched_on_youtube(app_factory: AppFactory) -> None:
    app, client = await app_factory()
    # Songs that exist in the fake YouTube catalog, plus one that doesn't.
    app.state.pipeline._discovery = FakeDiscovery(
        [
            PopularRecording(
                title="Hindi Melody No. 2", artist_name="Saanjh Project", listen_count=900
            ),
            PopularRecording(
                title="Song That Does Not Exist", artist_name="Nobody At All", listen_count=5
            ),
        ]
    )
    async with client:
        auth = await register(client)
        draft = (
            await client.post(
                "/api/v1/ai/playlist",
                headers=auth,
                json={"description": "songs like Aarav Strings", "duration_minutes": 120},
            )
        ).json()
    picks = [t for t in draft["tracks"] if t["source"] == "listenbrainz"]
    assert [p["track"]["channel_title"] for p in picks] == ["Saanjh Project"]
    assert "Popular with fans of Aarav Strings on ListenBrainz" in picks[0]["reasons"]


async def test_metadata_and_discovery_endpoints(app_factory: AppFactory) -> None:
    app, client = await app_factory()
    app.state.musicbrainz = make_mb([])
    app.state.listenbrainz = make_lb([], token="lb-token")
    async with client:
        auth = await register(client)
        video = (
            await client.get("/api/v1/search", params={"q": "telugu", "limit": 1}, headers=auth)
        ).json()["items"][0]["video_id"]
        meta = await client.get("/api/v1/metadata/track", params={"video_id": video}, headers=auth)
        artist = await client.get(
            "/api/v1/metadata/artist", params={"name": "Portishead"}, headers=auth
        )
        fresh = await client.get("/api/v1/discover/fresh-releases", headers=auth)
        top = await client.get(
            "/api/v1/discover/most-listened", params={"range": "week"}, headers=auth
        )
        bad_range = await client.get(
            "/api/v1/discover/most-listened", params={"range": "decade"}, headers=auth
        )
    body = meta.json()
    assert meta.status_code == 200, body
    assert body["source"] == "MusicBrainz" and "parsed_title" in body
    assert artist.json()["artist"]["name"] == "Portishead"
    assert artist.json()["sources"] == ["MusicBrainz", "ListenBrainz"]
    assert artist.json()["popular_recordings"][0]["title"] == "Roads"
    assert fresh.json()[0]["release_name"] == "Profound Mysteries IV"
    assert top.json()[0]["artist_name"] == "Ellie Goulding"
    assert bad_range.status_code == 422


async def test_disabled_and_unavailable_services(app_factory: AppFactory) -> None:
    app, client = await app_factory()  # test settings disable both services
    async with client:
        auth = await register(client)
        disabled = await client.get("/api/v1/discover/fresh-releases", headers=auth)
        app.state.listenbrainz = ListenBrainzClient(
            MemoryStore(),
            http_client=httpx.AsyncClient(
                transport=httpx.MockTransport(lambda r: httpx.Response(503)),
                base_url="https://lb.test/1",
            ),
        )
        down = await client.get("/api/v1/discover/fresh-releases", headers=auth)
    assert disabled.status_code == 503 and disabled.json()["error"]["code"] == "discovery_disabled"
    assert down.status_code == 502 and down.json()["error"]["code"] == "discovery_unavailable"


def test_intent_type_still_constructible() -> None:
    assert MusicIntent(search_queries=["x"]).discovery == "balanced"
    assert PreferenceHints().favorite_artists == []
