"""Catalog sources (Audius, Jamendo, iTunes previews) and the merged catalog service.

Responses follow each API's documented shape; no network access is used.
"""

from __future__ import annotations

import httpx
import pytest

from app.core.cache import MemoryStore
from app.schemas import Attribution, Track
from app.services.catalog.audius import AudiusSource
from app.services.catalog.base import CatalogUnavailableError, TrackUnavailableError
from app.services.catalog.ids import is_valid_track_id, make_track_id, parse_track_id
from app.services.catalog.itunes import ITunesPreviewSource
from app.services.catalog.jamendo import JamendoSource, _license_name
from app.services.catalog.service import CatalogService, rank, song_key
from app.services.music_sources.musicbrainz import clean_track_title

# --- Track ids ---------------------------------------------------------------------------


@pytest.mark.parametrize("value", ["audius:D7KyD", "jamendo:1532771", "itunes:1440833098"])
def test_valid_track_ids(value: str) -> None:
    assert is_valid_track_id(value)
    source, source_id = parse_track_id(value)
    assert make_track_id(source, source_id) == value


@pytest.mark.parametrize(
    "value",
    [
        "",
        "D7KyD",
        "youtube:dQw4w9WgXcQ",
        "audius:",
        "audius:a b",
        "audius:../../etc",
        "jamendo:1;drop",
        "spotify:abc",
        "audius:" + "x" * 41,
    ],
)
def test_invalid_track_ids(value: str) -> None:
    assert not is_valid_track_id(value)
    with pytest.raises(ValueError):
        parse_track_id(value)


# --- Audius ------------------------------------------------------------------------------

AUDIUS_TRACK = {
    "id": "D7KyD",
    "title": "Monsoon Drive",
    "duration": 214,
    "genre": "Electronic",
    "mood": "Energizing",
    "play_count": 12345,
    "is_streamable": True,
    "permalink": "/artist/monsoon-drive",
    "release_date": "2026-09-30T00:00:00Z",
    "artwork": {"150x150": "https://a/150.jpg", "480x480": "https://a/480.jpg"},
    "user": {"id": "u1", "name": "Madras Monsoon", "handle": "madras"},
}


def audius(calls: list[httpx.Request]) -> AudiusSource:
    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request)
        assert request.url.params["app_name"] == "Halo"
        path = request.url.path
        if path.endswith("/tracks/search") or path.endswith("/tracks/trending"):
            gated = {**AUDIUS_TRACK, "id": "Gated", "is_stream_gated": True}
            return httpx.Response(200, json={"data": [AUDIUS_TRACK, gated]})
        if path.endswith("/tracks/D7KyD"):
            return httpx.Response(200, json={"data": AUDIUS_TRACK})
        return httpx.Response(404, json={"data": None})

    client = httpx.AsyncClient(
        transport=httpx.MockTransport(handler), base_url="https://audius.test/v1"
    )
    return AudiusSource(base_url="https://audius.test/v1", http_client=client)


async def test_audius_search_maps_tracks_and_skips_gated() -> None:
    calls: list[httpx.Request] = []
    source = audius(calls)
    tracks = await source.search("monsoon", limit=5)
    assert [t.id for t in tracks] == ["audius:D7KyD"]
    track = tracks[0]
    assert (track.artist, track.duration_seconds, track.genre) == (
        "Madras Monsoon",
        214,
        "Electronic",
    )
    assert track.artwork_url == "https://a/480.jpg"
    assert track.artwork_url_large == "https://a/480.jpg"  # no 1000px copy: best available
    assert track.release_date == "2026-09-30"
    assert track.stream_url == "https://audius.test/v1/tracks/D7KyD/stream?app_name=Halo"
    assert not track.is_preview and track.attribution.label == "Audius"
    assert track.external_url == "https://audius.co/artist/monsoon-drive"
    assert calls[0].url.params["query"] == "monsoon"
    trending = await source.trending(limit=5, genre="Electronic")
    assert trending[0].id == "audius:D7KyD" and calls[-1].url.params["time"] == "week"
    assert (await source.get_tracks(["D7KyD", "Gone"])).keys() == {"D7KyD"}


async def test_audius_outage_is_a_catalog_error() -> None:
    client = httpx.AsyncClient(
        transport=httpx.MockTransport(lambda r: httpx.Response(503)), base_url="https://a.test"
    )
    with pytest.raises(CatalogUnavailableError):
        await AudiusSource(base_url="https://a.test", http_client=client).search("x", limit=1)


# --- Jamendo -----------------------------------------------------------------------------


def jamendo(calls: list[httpx.Request]) -> JamendoSource:
    row = {
        "id": "1532771",
        "name": "Kaveri Breeze",
        "duration": 245,
        "artist_id": "77",
        "artist_name": "Kaveri Echo",
        "album_name": "Rivers",
        "album_image": "https://j/album.jpg",
        "audio": "https://prod-1.storage.jamendo.com/?trackid=1532771&format=mp32",
        "releasedate": "2026-01-05",
        "shareurl": "https://www.jamendo.com/track/1532771",
        "license_ccurl": "http://creativecommons.org/licenses/by-nc-sa/3.0/",
        "musicinfo": {"tags": {"genres": ["world", "folk"]}},
    }

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request)
        assert request.url.params["client_id"] == "test-client"
        return httpx.Response(
            200,
            json={"headers": {"status": "success"}, "results": [row, {**row, "audio": ""}]},
        )

    client = httpx.AsyncClient(
        transport=httpx.MockTransport(handler), base_url="https://jamendo.test/v3.0"
    )
    return JamendoSource("test-client", http_client=client)


async def test_jamendo_tracks_carry_creative_commons_licence() -> None:
    calls: list[httpx.Request] = []
    tracks = await jamendo(calls).search("kaveri", limit=5)
    assert len(tracks) == 1  # rows without audio are skipped
    track = tracks[0]
    assert track.id == "jamendo:1532771" and track.album == "Rivers"
    assert track.stream_url and track.stream_url.startswith("https://prod-1.storage.jamendo.com/")
    assert track.genre == "World"
    assert track.license and track.license.name == "CC BY-NC-SA 3.0"
    assert calls[0].url.params["search"] == "kaveri"
    await jamendo(calls).trending(limit=5, genre="Folk")
    assert calls[-1].url.params["order"] == "popularity_week"
    assert calls[-1].url.params["fuzzytags"] == "folk"


def test_licence_names() -> None:
    assert _license_name("https://creativecommons.org/licenses/by/4.0/") == "CC BY 4.0"
    assert _license_name(None) == "Creative Commons"


async def test_jamendo_api_error_is_reported() -> None:
    client = httpx.AsyncClient(
        transport=httpx.MockTransport(
            lambda r: httpx.Response(
                200, json={"headers": {"status": "failed", "error_message": "bad client"}}
            )
        ),
        base_url="https://j.test",
    )
    with pytest.raises(CatalogUnavailableError):
        await JamendoSource("x", http_client=client).search("x", limit=1)


# --- iTunes previews ---------------------------------------------------------------------


async def test_itunes_results_are_labelled_previews() -> None:
    calls: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request)
        song = {
            "kind": "song",
            "trackId": 1440833098,
            "trackName": "Samajavaragamana",
            "artistName": "Sid Sriram",
            "collectionName": "Ala Vaikunthapurramuloo",
            "artworkUrl100": "https://is1.mzstatic.com/x/100x100bb.jpg",
            "previewUrl": "https://audio-ssl.itunes.apple.com/x.m4a",
            "trackViewUrl": "https://music.apple.com/in/album/x?i=1440833098",
            "trackTimeMillis": 229000,
            "primaryGenreName": "Telugu",
            "releaseDate": "2019-09-28T12:00:00Z",
        }
        video = {**song, "kind": "music-video", "trackId": 2}
        return httpx.Response(
            200,
            json={"resultCount": 2, "results": [song, video]},
            headers={"content-type": "text/javascript"},
        )

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler), base_url="https://i.test")
    tracks = await ITunesPreviewSource(http_client=client).search("samajavaragamana", limit=5)
    assert [t.id for t in tracks] == ["itunes:1440833098"]
    track = tracks[0]
    assert track.is_preview and track.attribution.label == "Preview courtesy of Apple Music"
    assert track.external_url and track.external_url.startswith("https://music.apple.com/")
    assert track.artwork_url == "https://is1.mzstatic.com/x/600x600bb.jpg"
    assert track.artwork_url_large == "https://is1.mzstatic.com/x/1200x1200bb.jpg"
    assert track.duration_seconds == 229 and track.album == "Ala Vaikunthapurramuloo"
    assert calls[0].url.params["country"] == "IN" and calls[0].url.params["entity"] == "song"


# --- Catalog service ---------------------------------------------------------------------


def make_track(
    source: str,
    sid: str,
    title: str,
    artist: str,
    *,
    preview: bool = False,
    plays: int | None = None,
) -> Track:
    return Track(
        id=f"{source}:{sid}",
        source=source,
        source_id=sid,
        title=title,
        artist=artist,  # type: ignore[arg-type]
        stream_url=f"https://s/{sid}",
        is_preview=preview,
        play_count=plays,
        attribution=Attribution(provider=source, label=source),  # type: ignore[arg-type]
    )


class StaticSource:
    def __init__(
        self, name: str, tracks: list[Track], *, full: bool = True, fail: bool = False
    ) -> None:
        self.name = name
        self.full_tracks = full
        self._tracks = tracks
        self.fail = fail
        self.calls = 0

    async def search(self, query: str, *, limit: int, offset: int = 0) -> list[Track]:
        self.calls += 1
        if self.fail:
            raise CatalogUnavailableError("down")
        return self._tracks[offset : offset + limit]

    async def trending(self, *, limit: int, genre: str | None = None) -> list[Track]:
        return self._tracks[:limit]

    async def get_tracks(self, source_ids: list[str]) -> dict[str, Track]:
        return {t.source_id: t for t in self._tracks if t.source_id in source_ids}

    async def aclose(self) -> None:
        return None


def test_full_songs_outrank_their_previews_and_duplicates_collapse() -> None:
    full = make_track("audius", "a1", "Saanjh (Official Audio)", "Saanjh Project")
    preview = make_track("itunes", "9", "Saanjh", "Saanjh Project", preview=True, plays=10**6)
    other = make_track("jamendo", "5", "Evening Raga", "Raag Riders")
    ranked = rank([preview, other, full], "saanjh", "song")
    assert ranked[0].id == "audius:a1"
    assert "itunes:9" not in {t.id for t in ranked}  # same song as the full track
    assert song_key(full) == song_key(preview)


async def test_catalog_merges_sources_and_survives_one_failing() -> None:
    audius_src = StaticSource("audius", [make_track("audius", "a1", "Kaveri", "Kaveri Echo")])
    itunes_src = StaticSource(
        "itunes", [make_track("itunes", "1", "Kaveri Song", "Echo", preview=True)], full=False
    )
    broken = StaticSource("jamendo", [], fail=True)
    catalog = CatalogService([audius_src, itunes_src, broken], MemoryStore())  # type: ignore[list-item]
    result = await catalog.search("kaveri", max_results=10)
    assert [t.id for t in result.page.items] == ["audius:a1", "itunes:1"]
    assert result.page.sources == ["audius", "itunes"]
    assert result.page.warnings == ["jamendo is unavailable right now"]
    again = await catalog.search("kaveri", max_results=10)
    assert again.cached and audius_src.calls == 1
    trending = await catalog.trending(max_results=5)
    assert [t.id for t in trending.page.items] == ["audius:a1"]  # previews never chart
    assert (await catalog.get_track("audius:a1")).title == "Kaveri"
    with pytest.raises(TrackUnavailableError):
        await catalog.get_track("audius:gone")


async def test_catalog_with_every_source_down_raises() -> None:
    catalog = CatalogService([StaticSource("audius", [], fail=True)], MemoryStore())  # type: ignore[list-item]
    with pytest.raises(CatalogUnavailableError):
        await catalog.search("x")


@pytest.mark.parametrize(
    ("title", "artist", "expected"),
    [
        ("Glory Box (Official Audio)", "Portishead", ("Portishead", "Glory Box")),
        ("Portishead - Glory Box", "Portishead", ("Portishead", "Glory Box")),
        ("Rain - Night Version", "Kaveri Echo", ("Kaveri Echo", "Rain - Night Version")),
    ],
)
def test_clean_track_title(title: str, artist: str, expected: tuple[str, str]) -> None:
    assert clean_track_title(title, artist) == expected
