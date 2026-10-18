"""YouTube Data API v3 client.

Quota notes (default 10,000 units/day): search.list costs 100 units, videos.list costs 1.
Every search is followed by one videos.list call so each returned result is verified
(public, processed, not region-blocked) and carries duration/statistics.
"""

from __future__ import annotations

import asyncio
import html
import logging
import re
from datetime import datetime
from typing import Any, Literal

import httpx

from app.schemas import Attribution, Thumbnail, Track
from app.services.youtube.base import (
    ProviderConfigurationError,
    ProviderUnavailableError,
    QuotaExceededError,
    SearchPage,
    YouTubeError,
)
from app.services.youtube.ids import is_valid_video_id, watch_url

logger = logging.getLogger("muse.youtube")

MUSIC_CATEGORY_ID = "10"
_DURATION_RE = re.compile(
    r"^P(?:(?P<d>\d+)D)?(?:T(?:(?P<h>\d+)H)?(?:(?P<m>\d+)M)?(?:(?P<s>\d+)S)?)?$"
)


def parse_iso8601_duration(value: str | None) -> int | None:
    if not value:
        return None
    match = _DURATION_RE.fullmatch(value)
    if not match:
        return None
    parts = {k: int(v) for k, v in match.groupdict().items() if v}
    return (
        parts.get("d", 0) * 86400 + parts.get("h", 0) * 3600 + parts.get("m", 0) * 60
        + parts.get("s", 0)
    )


def _parse_datetime(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def is_available_in_region(item: dict[str, Any], region: str) -> bool:
    status = item.get("status", {})
    if status.get("privacyStatus") != "public":
        return False
    if status.get("uploadStatus") not in (None, "processed"):
        return False
    restriction = item.get("contentDetails", {}).get("regionRestriction") or {}
    allowed = restriction.get("allowed")
    if allowed is not None and region not in allowed:
        return False
    blocked = restriction.get("blocked")
    return not (blocked is not None and region in blocked)


def track_from_video_resource(item: dict[str, Any]) -> Track | None:
    video_id = item.get("id")
    if not isinstance(video_id, str) or not is_valid_video_id(video_id):
        return None
    snippet = item.get("snippet", {})
    details = item.get("contentDetails", {})
    stats = item.get("statistics", {})
    thumbnails = {
        key: Thumbnail(url=t["url"], width=t.get("width"), height=t.get("height"))
        for key, t in (snippet.get("thumbnails") or {}).items()
        if isinstance(t, dict) and str(t.get("url", "")).startswith("https://")
    }
    view_count = stats.get("viewCount")
    url = watch_url(video_id)
    return Track(
        video_id=video_id,
        title=html.unescape(snippet.get("title", "")).strip() or "Untitled",
        channel_title=html.unescape(snippet.get("channelTitle", "")).strip() or "Unknown channel",
        channel_id=snippet.get("channelId"),
        description=(snippet.get("description") or "")[:500] or None,
        thumbnails=thumbnails,
        duration_seconds=parse_iso8601_duration(details.get("duration")),
        published_at=_parse_datetime(snippet.get("publishedAt")),
        view_count=int(view_count) if str(view_count or "").isdigit() else None,
        is_live=snippet.get("liveBroadcastContent") in {"live", "upcoming"},
        watch_url=url,
        attribution=Attribution(provider="youtube", label="YouTube", url=url),
    )


class YouTubeDataAPIClient:
    name: Literal["youtube", "demo"] = "youtube"

    def __init__(
        self,
        api_key: str,
        *,
        base_url: str = "https://www.googleapis.com/youtube/v3",
        region_code: str = "US",
        timeout_seconds: float = 8.0,
        http_client: httpx.AsyncClient | None = None,
        max_retries: int = 2,
    ) -> None:
        if not api_key:
            raise ProviderConfigurationError("YouTube API key is not configured")
        self._api_key = api_key
        self._region = region_code.upper()
        self._max_retries = max_retries
        self._client = http_client or httpx.AsyncClient(
            base_url=base_url, timeout=httpx.Timeout(timeout_seconds)
        )
        self._owns_client = http_client is None

    async def aclose(self) -> None:
        if self._owns_client:
            await self._client.aclose()

    async def _get(self, path: str, params: dict[str, Any]) -> dict[str, Any]:
        params = {**params, "key": self._api_key}
        last_error: Exception | None = None
        for attempt in range(self._max_retries + 1):
            try:
                response = await self._client.get(path, params=params)
            except (httpx.TimeoutException, httpx.TransportError) as exc:
                last_error = exc
                logger.warning("youtube %s transport error (attempt %d)", path, attempt + 1)
            else:
                if response.status_code == 200:
                    data: dict[str, Any] = response.json()
                    return data
                self._raise_for_error(response)  # raises for non-retryable codes
                last_error = ProviderUnavailableError(f"YouTube returned {response.status_code}")
            if attempt < self._max_retries:
                await asyncio.sleep(0.25 * (2**attempt))
        raise ProviderUnavailableError("YouTube is temporarily unavailable") from last_error

    @staticmethod
    def _raise_for_error(response: httpx.Response) -> None:
        if response.status_code >= 500:
            return  # retryable
        reasons: set[str] = set()
        try:
            for err in response.json().get("error", {}).get("errors", []):
                reasons.add(str(err.get("reason", "")))
        except ValueError:
            pass
        if reasons & {"quotaExceeded", "dailyLimitExceeded", "rateLimitExceeded"}:
            raise QuotaExceededError("YouTube search quota is exhausted for now")
        if reasons & {"keyInvalid", "accessNotConfigured", "forbidden"} or response.status_code in (
            401,
            403,
        ):
            raise ProviderConfigurationError("YouTube API access is misconfigured")
        if response.status_code == 400:
            raise YouTubeError("YouTube rejected the request")
        raise YouTubeError(f"YouTube request failed ({response.status_code})")

    async def search(
        self, query: str, *, page_token: str | None = None, max_results: int = 20
    ) -> SearchPage:
        params: dict[str, Any] = {
            "part": "id",
            "type": "video",
            "videoCategoryId": MUSIC_CATEGORY_ID,
            "q": query,
            "maxResults": max(1, min(max_results, 50)),
            "regionCode": self._region,
            "safeSearch": "moderate",
        }
        if page_token:
            params["pageToken"] = page_token
        data = await self._get("/search", params)
        ids = [
            item.get("id", {}).get("videoId")
            for item in data.get("items", [])
            if item.get("id", {}).get("kind") == "youtube#video"
        ]
        ids = [vid for vid in dict.fromkeys(ids) if is_valid_video_id(vid)]
        videos = await self.get_videos(ids)
        items = [videos[vid] for vid in ids if vid in videos]
        return SearchPage(
            items=items,
            next_page_token=data.get("nextPageToken"),
            prev_page_token=data.get("prevPageToken"),
            total_results_estimate=data.get("pageInfo", {}).get("totalResults"),
            filtered_out=len(ids) - len(items),
        )

    async def trending(
        self, *, page_token: str | None = None, max_results: int = 20
    ) -> SearchPage:
        """videos.list chart=mostPopular in the Music category (1 quota unit)."""
        params: dict[str, Any] = {
            "part": "snippet,contentDetails,status,statistics",
            "chart": "mostPopular",
            "videoCategoryId": MUSIC_CATEGORY_ID,
            "regionCode": self._region,
            "maxResults": max(1, min(max_results, 50)),
        }
        if page_token:
            params["pageToken"] = page_token
        data = await self._get("/videos", params)
        items: list[Track] = []
        dropped = 0
        for item in data.get("items", []):
            track = (
                track_from_video_resource(item)
                if is_available_in_region(item, self._region)
                else None
            )
            if track is None:
                dropped += 1
            else:
                items.append(track)
        return SearchPage(
            items=items,
            next_page_token=data.get("nextPageToken"),
            prev_page_token=data.get("prevPageToken"),
            total_results_estimate=data.get("pageInfo", {}).get("totalResults"),
            filtered_out=dropped,
        )

    async def get_videos(self, video_ids: list[str]) -> dict[str, Track]:
        valid = [vid for vid in dict.fromkeys(video_ids) if is_valid_video_id(vid)]
        result: dict[str, Track] = {}
        for start in range(0, len(valid), 50):
            chunk = valid[start : start + 50]
            data = await self._get(
                "/videos",
                {"part": "snippet,contentDetails,status,statistics", "id": ",".join(chunk)},
            )
            for item in data.get("items", []):
                if not is_available_in_region(item, self._region):
                    continue
                track = track_from_video_resource(item)
                if track is not None:
                    result[track.video_id] = track
        return result
