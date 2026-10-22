"""Musical features Halo Drive ranks on: language, energy and tempo, each optional.

Estimated from what the sources already send (Jamendo ``musicinfo``, Audius genre, mood and
tags) plus the script and words of the title. Every estimate is a hint with a source, never a
claim: an unknown stays ``None`` so the ranker can treat it as "no information" instead of a
wrong guess. Language is never inferred from an English-looking title alone, because Telugu
songs often have English titles.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

# Unicode blocks of Indian scripts → ISO 639-1.
_SCRIPTS = {
    "te": re.compile(r"[ఀ-౿]"),
    "ta": re.compile(r"[஀-௿]"),
    "hi": re.compile(r"[ऀ-ॿ]"),
    "kn": re.compile(r"[ಀ-೿]"),
    "ml": re.compile(r"[ഀ-ൿ]"),
}

# Words that name a language or its film industry, in titles, albums, genres or tags.
_LANGUAGE_WORDS = {
    "te": ("telugu", "tollywood"),
    "ta": ("tamil", "kollywood"),
    "hi": ("hindi", "bollywood"),
    "kn": ("kannada", "sandalwood"),
    "ml": ("malayalam", "mollywood"),
}

# Audius moods → energy (0 calm … 1 intense).
_MOOD_ENERGY = {
    "peaceful": 0.15,
    "tender": 0.2,
    "easygoing": 0.3,
    "romantic": 0.35,
    "sentimental": 0.3,
    "yearning": 0.35,
    "melancholy": 0.25,
    "sophisticated": 0.4,
    "sensual": 0.4,
    "cool": 0.45,
    "serious": 0.45,
    "brooding": 0.4,
    "gritty": 0.6,
    "stirring": 0.6,
    "empowering": 0.7,
    "upbeat": 0.75,
    "excited": 0.8,
    "energizing": 0.85,
    "fiery": 0.85,
    "defiant": 0.75,
    "rowdy": 0.85,
    "aggressive": 0.9,
}

# Genre priors when nothing better is known.
_GENRE_ENERGY = {
    "ambient": 0.15,
    "classical": 0.25,
    "lo-fi": 0.25,
    "lofi": 0.25,
    "acoustic": 0.3,
    "folk": 0.35,
    "jazz": 0.35,
    "soundtrack": 0.45,
    "world": 0.5,
    "r&b/soul": 0.5,
    "pop": 0.6,
    "alternative": 0.6,
    "hip-hop/rap": 0.7,
    "hiphop": 0.7,
    "rock": 0.75,
    "reggae": 0.55,
    "electronic": 0.75,
    "house": 0.8,
    "techno": 0.85,
    "drum & bass": 0.9,
    "dubstep": 0.9,
    "trap": 0.8,
    "metal": 0.9,
    "dance": 0.8,
    "devotional": 0.3,
    "funk": 0.7,
}

# Jamendo "speed" → tempo.
_SPEED = {"verylow": 0.1, "low": 0.3, "medium": 0.5, "high": 0.75, "veryhigh": 0.9}


@dataclass(frozen=True, slots=True)
class Features:
    language: str | None = None
    energy: float | None = None
    tempo: float | None = None


def language_hint(*texts: str | None) -> str | None:
    """A language from native script or explicit language words, else None."""
    joined = " ".join(t for t in texts if t)
    for code, pattern in _SCRIPTS.items():
        if pattern.search(joined):
            return code
    lowered = joined.lower()
    for code, words in _LANGUAGE_WORDS.items():
        if any(re.search(rf"\b{word}\b", lowered) for word in words):
            return code
    return None


def estimate(
    *,
    title: str,
    album: str | None = None,
    genre: str | None = None,
    mood: str | None = None,
    tags: str | None = None,
    lang: str | None = None,
    speed: str | None = None,
    bpm: float | None = None,
) -> Features:
    language = (lang or "").strip().lower()[:2] or language_hint(title, album, genre, tags)
    tempo: float | None = None
    if bpm and 40 <= bpm <= 220:
        tempo = round(min(max((bpm - 60) / 120, 0.0), 1.0), 2)
    elif speed:
        tempo = _SPEED.get(speed.lower())
    energy = _MOOD_ENERGY.get((mood or "").lower())
    if energy is None and genre:
        energy = _GENRE_ENERGY.get(genre.lower())
    if energy is not None and tempo is not None:
        energy = round(0.7 * energy + 0.3 * tempo, 2)
    elif energy is None and tempo is not None:
        energy = tempo
    return Features(language=language or None, energy=energy, tempo=tempo)
