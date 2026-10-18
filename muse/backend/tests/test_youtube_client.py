"""YouTube client behaviour against a mocked HTTP transport (no network, no real key)."""

from __future__ import annotations

from typing import Any

import httpx
import pytest

from app.core.cache import MemoryStore
from app.services.youtube.base import (
    ProviderConfigurationError,
    ProviderUnavailableError,
    QuotaExceededError,
    VideoUnavailableError,
)
from app.services.youtube.client import YouTubeDataAPIClient, parse_iso8601_duration
from app.services.youtube.service import YouTubeSearchService, shape_query


def video_resource(video_id: str, **overrides: Any) -> dict[str, Any]:
    item: dict[str, Any] = {
        "id": video_id,
        "snippet": {
            "title": "Song &amp; Dance &#39;Live&#39;",
            "channelTitle": "Channel &amp; Co",
            "channelId": "UC" + "a" * 22,
            "publishedAt": "2009-10-25T06:57:33Z",
            "liveBroadcastContent": "none",
            "thumbnails": {
                "high": {"url": f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg",
                         "width": 480, "height": 360},
                "bad": {"url": "http://insecure.example/x.jpg"},
            },
        },
        "contentDetails": {"duration": "PT3M33S"},
        "status": {"privacyStatus": "public", "uploadStatus": "processed", "embeddable": True},
        "statistics": {"viewCount": "12345"},
    }
    for key, value in overrides.items():
        item[key] = {**item[key], **value}
    return item


class FakeYouTube:
    def __init__(self) -> None:
        self.calls: list[tuple[str, dict[str, str]]] = []
        self.search_items: list[str] = ["aaaaaaaaaaa", "bbbbbbbbbbb", "ccccccccccc", "not-valid"]
        self.videos: dict[str, dict[str, Any]] = {
            "aaaaaaaaaaa": video_resource("aaaaaaaaaaa"),
            "bbbbbbbbbbb": video_resource("bbbbbbbbbbb", status={"privacyStatus": "private"}),
            "ccccccccccc": video_resource(
                "ccccccccccc", contentDetails={"regionRestriction": {"blocked": ["US"]}}
            ),
        }
        self.failures: list[httpx.Response | Exception] = []

    def handler(self, request: httpx.Request) -> httpx.Response:
        params = dict(request.url.params)
        self.calls.append((request.url.path, params))
        if self.failures:
            failure = self.failures.pop(0)
            if isinstance(failure, Exception):
                raise failure
            return failure
        assert params["key"] == "test-key"
        if request.url.path.endswith("/search"):
            page = params.get("pageToken")
            ids = self.search_items if page is None else ["ddddddddddd"]
            return httpx.Response(
                200,
                json={
                    "nextPageToken": None if page else "PAGE2",
                    "prevPageToken": "PAGE1" if page else None,
                    "pageInfo": {"totalResults": 1000},
                    "items": [{"id": {"kind": "youtube#video", "videoId": v}} for v in ids],
                },
            )
        ids = params["id"].split(",")
        self.videos.setdefault("ddddddddddd", video_resource("ddddddddddd"))
        return httpx.Response(
            200, json={"items": [self.videos[v] for v in ids if v in self.videos]}
        )


def make_client(fake: FakeYouTube, **kwargs: Any) -> YouTubeDataAPIClient:
    http = httpx.AsyncClient(
        transport=httpx.MockTransport(fake.handler), base_url="https://yt.test/youtube/v3"
    )
    return YouTubeDataAPIClient("test-key", http_client=http, **kwargs)


def error_response(status: int, reason: str) -> httpx.Response:
    return httpx.Response(status, json={"error": {"errors": [{"reason": reason}]}})


@pytest.mark.parametrize(
    ("value", "seconds"),
    [("PT3M33S", 213), ("PT1H2M", 3720), ("PT45S", 45), ("P1DT1S", 86401), ("bad", None),
     (None, None)],
)
def test_parse_duration(value: str | None, seconds: int | None) -> None:
    assert parse_iso8601_duration(value) == seconds


async def test_search_verifies_and_filters_results() -> None:
    fake = FakeYouTube()
    client = make_client(fake)
    page = await client.search("telugu melody")
    assert [t.video_id for t in page.items] == ["aaaaaaaaaaa"]
    assert page.filtered_out == 2  # private + region-blocked; invalid id dropped earlier
    track = page.items[0]
    assert track.title == "Song & Dance 'Live'"
    assert track.channel_title == "Channel & Co"
    assert track.duration_seconds == 213
    assert track.view_count == 12345
    assert set(track.thumbnails) == {"high"}  # non-HTTPS thumbnail rejected
    assert track.attribution.provider == "youtube"
    assert track.watch_url == "https://www.youtube.com/watch?v=aaaaaaaaaaa"
    search_call = fake.calls[0][1]
    assert search_call["videoCategoryId"] == "10"
    assert search_call["type"] == "video"
    assert page.next_page_token == "PAGE2"


async def test_pagination_passes_page_token() -> None:
    fake = FakeYouTube()
    client = make_client(fake)
    page = await client.search("x", page_token="PAGE2")
    assert fake.calls[0][1]["pageToken"] == "PAGE2"
    assert page.prev_page_token == "PAGE1"
    assert page.next_page_token is None
    assert [t.video_id for t in page.items] == ["ddddddddddd"]


async def test_quota_exceeded_is_not_retried() -> None:
    fake = FakeYouTube()
    fake.failures = [error_response(403, "quotaExceeded")]
    client = make_client(fake)
    with pytest.raises(QuotaExceededError):
        await client.search("x")
    assert len(fake.calls) == 1


async def test_invalid_key_is_configuration_error() -> None:
    fake = FakeYouTube()
    fake.failures = [error_response(400, "keyInvalid")]
    with pytest.raises(ProviderConfigurationError):
        await make_client(fake).search("x")


async def test_transient_errors_are_retried_then_succeed() -> None:
    fake = FakeYouTube()
    fake.failures = [httpx.ConnectError("boom"), httpx.Response(503)]
    page = await make_client(fake).search("x")
    assert page.items


async def test_network_interruption_exhausts_retries() -> None:
    fake = FakeYouTube()
    fake.failures = [httpx.ReadTimeout("slow")] * 3
    with pytest.raises(ProviderUnavailableError):
        await make_client(fake, max_retries=2).search("x")
    assert len(fake.calls) == 3


async def test_service_caches_search_and_videos() -> None:
    fake = FakeYouTube()
    service = YouTubeSearchService(
        make_client(fake), MemoryStore(), search_ttl_seconds=60, video_ttl_seconds=60
    )
    first = await service.search("telugu melody")
    second = await service.search("Telugu   Melody")
    assert not first.cached and second.cached
    calls_before = len(fake.calls)
    track = await service.get_video("aaaaaaaaaaa")
    assert track.video_id == "aaaaaaaaaaa"
    assert len(fake.calls) == calls_before  # served from cache
    with pytest.raises(VideoUnavailableError):
        await service.get_video("bbbbbbbbbbb")


def test_shape_query() -> None:
    assert shape_query("  arijit   singh ", "artist") == "arijit singh songs"
    assert shape_query("tum hi ho", "remix") == "tum hi ho remix"
    assert shape_query("tum hi ho remix", "remix") == "tum hi ho remix"
    assert shape_query("coldplay", "live") == "coldplay live performance"


def test_missing_key_rejected() -> None:
    with pytest.raises(ProviderConfigurationError):
        YouTubeDataAPIClient("")
