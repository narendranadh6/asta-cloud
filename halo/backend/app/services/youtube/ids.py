"""Validation and canonical URL construction for YouTube identifiers.

Only identifiers that pass these checks are ever turned into URLs. The iOS app performs
the same validation independently (BrowserIntegration/YouTubeIdentifier.swift).
"""

from __future__ import annotations

import re
from urllib.parse import parse_qs, quote, urlparse

VIDEO_ID_RE = re.compile(r"^[A-Za-z0-9_-]{11}$")
# Public playlist ids: PL (user), OL (album), UU (uploads), FL/LL (likes), RD (mix).
PLAYLIST_ID_RE = re.compile(r"^(PL|OL|UU|FL|LL|RD|OLAK5uy_)[A-Za-z0-9_-]{10,64}$")
CHANNEL_ID_RE = re.compile(r"^UC[A-Za-z0-9_-]{22}$")

YOUTUBE_HOSTS = {"youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"}
SHORT_HOSTS = {"youtu.be"}


def is_valid_video_id(value: object) -> bool:
    return isinstance(value, str) and bool(VIDEO_ID_RE.fullmatch(value))


def is_valid_playlist_id(value: object) -> bool:
    return isinstance(value, str) and bool(PLAYLIST_ID_RE.fullmatch(value))


def is_valid_channel_id(value: object) -> bool:
    return isinstance(value, str) and bool(CHANNEL_ID_RE.fullmatch(value))


def watch_url(video_id: str) -> str:
    if not is_valid_video_id(video_id):
        raise ValueError("invalid YouTube video id")
    return f"https://www.youtube.com/watch?v={quote(video_id, safe='')}"


def playlist_url(playlist_id: str) -> str:
    if not is_valid_playlist_id(playlist_id):
        raise ValueError("invalid YouTube playlist id")
    return f"https://www.youtube.com/playlist?list={quote(playlist_id, safe='')}"


def extract_video_id(url: str) -> str | None:
    """Extract a video id from a YouTube URL. Returns None for anything not recognised."""
    try:
        parsed = urlparse(url.strip())
    except ValueError:
        return None
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        return None
    host = parsed.hostname.lower()
    candidate: str | None = None
    if host in SHORT_HOSTS:
        candidate = parsed.path.lstrip("/").split("/")[0]
    elif host in YOUTUBE_HOSTS:
        if parsed.path == "/watch":
            values = parse_qs(parsed.query).get("v")
            candidate = values[0] if values else None
        else:
            parts = [p for p in parsed.path.split("/") if p]
            if len(parts) >= 2 and parts[0] in {"embed", "shorts", "live", "v"}:
                candidate = parts[1]
    return candidate if is_valid_video_id(candidate) else None
