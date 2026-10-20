"""In-memory catalog source for tests only.

It stands in for Audius so the suite runs without network access. It lives in the test
package, is never imported by the application, and is never shipped.
"""

from __future__ import annotations

import base64
import hashlib
import re
from typing import Literal

from app.schemas import Attribution, Track

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


def fake_source_id(seed: str) -> str:
    digest = base64.urlsafe_b64encode(hashlib.sha256(seed.encode()).digest()).decode()
    return (FAKE_PREFIX + digest.replace("=", "").replace("-", "x").replace("_", "y"))[:10]


def fake_track_id(seed: str) -> str:
    return f"audius:{fake_source_id(seed)}"


def _build_catalog() -> list[tuple[Track, set[str]]]:
    catalog: list[tuple[Track, set[str]]] = []
    index = 0
    for language in _LANGUAGES:
        for style, mood, _energy, tags in _STYLES:
            for artist_index, artist in enumerate(_ARTISTS[language]):
                variant = _VARIANTS[(index + artist_index) % len(_VARIANTS)]
                era = _ERAS[(index + artist_index) % len(_ERAS)]
                title = f"{language} {style.title()} No. {artist_index + 1}{variant}"
                source_id = fake_source_id(f"{language}|{style}|{artist}")
                tokens = {
                    language.lower(),
                    mood,
                    era,
                    *tags,
                    *style.split(),
                    *artist.lower().split(),
                }
                if "Live" in variant:
                    tokens.update({"live", "performance", "concert"})
                if "Remix" in variant:
                    tokens.update({"remix", "edit"})
                page = f"https://audius.test/{source_id}"
                catalog.append(
                    (
                        Track(
                            id=f"audius:{source_id}",
                            source="audius",
                            source_id=source_id,
                            title=title,
                            artist=artist,
                            artwork_url=f"https://art.test/{source_id}.jpg",
                            duration_seconds=150 + (index * 37) % 210,
                            genre=tags[0].title(),
                            mood=mood.title(),
                            play_count=(index * 7919) % 5_000_000 + 1_000,
                            stream_url=f"https://stream.test/{source_id}.mp3",
                            external_url=page,
                            attribution=Attribution(provider="audius", label="Audius", url=page),
                        ),
                        tokens,
                    )
                )
                index += 1
    return catalog


CATALOG = _build_catalog()
_WORD_RE = re.compile(r"[a-z0-9]+")


class FakeCatalogSource:
    """Behaves like AudiusSource over the fixed test catalog above."""

    name: Literal["audius"] = "audius"
    full_tracks = True

    def __init__(self) -> None:
        self.search_calls = 0
        self.lookup_calls = 0
        self.removed: set[str] = set()

    async def aclose(self) -> None:
        return None

    def _available(self) -> list[tuple[Track, set[str]]]:
        return [(t, tokens) for t, tokens in CATALOG if t.source_id not in self.removed]

    async def search(self, query: str, *, limit: int, offset: int = 0) -> list[Track]:
        self.search_calls += 1
        words = set(_WORD_RE.findall(query.lower()))
        scored: list[tuple[int, int, Track]] = []
        for position, (track, tokens) in enumerate(self._available()):
            title_words = set(_WORD_RE.findall(track.title.lower()))
            score = len(words & tokens) * 2 + len(words & title_words)
            if score > 0:
                scored.append((score, -position, track))
        scored.sort(key=lambda item: (item[0], item[1]), reverse=True)
        return [track for _, _, track in scored[offset : offset + limit]]

    async def trending(self, *, limit: int, genre: str | None = None) -> list[Track]:
        tracks = [t for t, _ in self._available() if not genre or t.genre == genre]
        return sorted(tracks, key=lambda t: t.play_count or 0, reverse=True)[:limit]

    async def get_tracks(self, source_ids: list[str]) -> dict[str, Track]:
        self.lookup_calls += 1
        wanted = set(source_ids)
        return {t.source_id: t for t, _ in self._available() if t.source_id in wanted}
