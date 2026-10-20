"""In-memory metadata provider for tests only.

It stands in for the YouTube Data API so the suite runs without network or credentials.
It is not importable from the application package and is never shipped.
"""

from __future__ import annotations

import base64
import hashlib
import re
from datetime import UTC, datetime, timedelta
from typing import Literal

from app.schemas import Attribution, Thumbnail, Track
from app.services.youtube.base import SearchPage

FAKE_PREFIX = "tst"

_LANGUAGES = ["Telugu", "Hindi", "Tamil", "English", "Spanish", "Korean"]
_STYLES = [
    ("melody", "calm", 70, ["acoustic", "melody"]),
    ("lofi", "focused", 30, ["lofi", "instrumental", "chill"]),
    ("dance", "energetic", 90, ["dance", "edm", "party"]),
    ("love song", "romantic", 50, ["romantic", "love", "ballad"]),
    ("road trip anthem", "travel", 75, ["rock", "travel", "drive"]),
    ("workout mix track", "workout", 95, ["workout", "hip hop", "gym"]),
    ("lullaby", "sleep", 15, ["sleep", "ambient", "piano"]),
    ("feel good pop", "happy", 80, ["pop", "happy", "upbeat"]),
]
_ARTISTS = {
    "Telugu": ["Aarav Strings", "Keerthi Waves", "Godavari Collective"],
    "Hindi": ["Mehfil Lights", "Saanjh Project", "Raag Riders"],
    "Tamil": ["Kaveri Echo", "Madras Monsoon", "Isai Theory"],
    "English": ["Northern Static", "Velvet Atlas", "The Quiet Hours"],
    "Spanish": ["Luz de Mar", "Los Faroles", "Sol Naciente"],
    "Korean": ["Hanbit Room", "Seoul Lantern", "Dawn Circuit"],
}
_ERAS = ["2000s", "2010s", "2020s"]
_VARIANTS = ["", " (Live Session)", " (Remix)"]


def fake_video_id(seed: str) -> str:
    digest = base64.urlsafe_b64encode(hashlib.sha256(seed.encode()).digest()).decode()
    return (FAKE_PREFIX + digest.replace("=", ""))[:11]



def _build_catalog() -> list[tuple[Track, set[str]]]:
    catalog: list[tuple[Track, set[str]]] = []
    base_date = datetime(2004, 1, 1, tzinfo=UTC)
    index = 0
    for language in _LANGUAGES:
        for style, mood, energy, tags in _STYLES:
            for artist_index, artist in enumerate(_ARTISTS[language]):
                variant = _VARIANTS[(index + artist_index) % len(_VARIANTS)]
                era = _ERAS[(index + artist_index) % len(_ERAS)]
                title = f"{language} {style.title()} No. {artist_index + 1}{variant}"
                video_id = fake_video_id(f"{language}|{style}|{artist}")
                tokens = {
                    language.lower(), mood, era, *tags, *style.split(),
                    *artist.lower().split()
                }
                if "Live" in variant:
                    tokens.update({"live", "performance", "concert"})
                if "Remix" in variant:
                    tokens.update({"remix", "edit"})
                published = base_date + timedelta(days=index * 97 % 7000)
                thumb = f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg"
                catalog.append(
                    (
                        Track(
                            video_id=video_id,
                            title=title,
                            channel_title=artist,
                            channel_id=None,
                            description=f"Test catalog entry ({mood}, energy {energy}).",
                            thumbnails={"high": Thumbnail(url=thumb, width=480, height=360)},
                            duration_seconds=150 + (index * 37) % 210,
                            published_at=published,
                            view_count=(index * 7919) % 5_000_000 + 1_000,
                            is_live=False,
                            watch_url=f"https://www.youtube.com/watch?v={video_id}",
                            attribution=Attribution(
                                provider="youtube",
                                label="YouTube",
                                url=f"https://www.youtube.com/watch?v={video_id}",
                            ),
                        ),
                        tokens,
                    )
                )
                index += 1
    return catalog


_CATALOG = _build_catalog()
_WORD_RE = re.compile(r"[a-z0-9]+")


class FakeMetadataProvider:
    name: Literal["youtube"] = "youtube"

    def __init__(self) -> None:
        self.search_calls = 0
        self.video_calls = 0

    async def aclose(self) -> None:
        return None

    async def search(
        self, query: str, *, page_token: str | None = None, max_results: int = 20
    ) -> SearchPage:
        self.search_calls += 1
        words = set(_WORD_RE.findall(query.lower()))
        scored: list[tuple[int, int, Track]] = []
        for position, (track, tokens) in enumerate(_CATALOG):
            title_words = set(_WORD_RE.findall(track.title.lower()))
            score = len(words & tokens) * 2 + len(words & title_words)
            if score > 0:
                scored.append((score, -position, track))
        scored.sort(key=lambda item: (item[0], item[1]), reverse=True)
        try:
            offset = int(page_token) if page_token else 0
        except ValueError:
            offset = 0
        max_results = max(1, min(max_results, 50))
        page = [track for _, _, track in scored[offset : offset + max_results]]
        next_offset = offset + max_results
        return SearchPage(
            items=page,
            next_page_token=str(next_offset) if next_offset < len(scored) else None,
            prev_page_token=str(max(0, offset - max_results)) if offset > 0 else None,
            total_results_estimate=len(scored),
        )

    async def trending(
        self, *, page_token: str | None = None, max_results: int = 20
    ) -> SearchPage:
        ranked = sorted((t for t, _ in _CATALOG), key=lambda t: t.view_count or 0, reverse=True)
        try:
            offset = int(page_token) if page_token else 0
        except ValueError:
            offset = 0
        max_results = max(1, min(max_results, 50))
        page = ranked[offset : offset + max_results]
        next_offset = offset + max_results
        return SearchPage(
            items=page,
            next_page_token=str(next_offset) if next_offset < len(ranked) else None,
            prev_page_token=str(max(0, offset - max_results)) if offset > 0 else None,
            total_results_estimate=len(ranked),
        )

    async def get_videos(self, video_ids: list[str]) -> dict[str, Track]:
        self.video_calls += 1
        wanted = set(video_ids)
        return {t.video_id: t for t, _ in _CATALOG if t.video_id in wanted}
