"""Deterministic intent extraction used when no LLM is configured or the LLM fails.

It is intentionally simple and predictable: keyword tables map free text to mood,
language, genres, activity, era, energy, duration and discovery preference.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from app.services.ai.intent import MusicIntent

LANGUAGES = {
    "telugu": "Telugu",
    "hindi": "Hindi",
    "bollywood": "Hindi",
    "tamil": "Tamil",
    "kollywood": "Tamil",
    "malayalam": "Malayalam",
    "kannada": "Kannada",
    "punjabi": "Punjabi",
    "bengali": "Bengali",
    "marathi": "Marathi",
    "english": "English",
    "spanish": "Spanish",
    "latin": "Spanish",
    "korean": "Korean",
    "k-pop": "Korean",
    "kpop": "Korean",
    "japanese": "Japanese",
    "j-pop": "Japanese",
    "french": "French",
    "arabic": "Arabic",
    "portuguese": "Portuguese",
}

MOOD_WORDS: dict[str, tuple[str, ...]] = {
    "calm": ("calm", "relax", "relaxing", "chill", "peaceful", "soothing", "mellow", "soft"),
    "happy": ("happy", "cheerful", "feel good", "feel-good", "uplifting", "sunny", "joyful"),
    "focused": (
        "focus",
        "focused",
        "coding",
        "study",
        "studying",
        "work",
        "concentrat",
        "deep work",
        "reading",
    ),
    "energetic": ("energetic", "energy", "hype", "party", "dance", "upbeat", "pump"),
    "romantic": ("romantic", "love", "romance", "date night", "valentine"),
    "sleep": ("sleep", "sleeping", "bedtime", "lullaby", "insomnia"),
    "workout": ("workout", "gym", "running", "run", "cardio", "lifting", "training"),
    "travel": ("road trip", "roadtrip", "drive", "driving", "travel", "journey", "commute"),
}

MOOD_ENERGY = {
    "calm": 30,
    "happy": 70,
    "focused": 35,
    "energetic": 85,
    "romantic": 45,
    "sleep": 10,
    "workout": 92,
    "travel": 65,
}

GENRES = (
    "melody",
    "melodies",
    "acoustic",
    "lofi",
    "lo-fi",
    "jazz",
    "classical",
    "carnatic",
    "hindustani",
    "ghazal",
    "folk",
    "rock",
    "indie",
    "pop",
    "hip hop",
    "hip-hop",
    "rap",
    "edm",
    "electronic",
    "house",
    "techno",
    "ambient",
    "r&b",
    "soul",
    "blues",
    "metal",
    "country",
    "reggaeton",
    "devotional",
    "sufi",
    "qawwali",
    "instrumental",
    "piano",
    "orchestral",
    "synthwave",
    "kuthu",
    "mass",
    "remix",
    "unplugged",
    "ballad",
)
_GENRE_ALIASES = {"melodies": "melody", "lo-fi": "lofi", "hip-hop": "hip hop"}

ACTIVITIES = {
    "coding": "coding",
    "programming": "coding",
    "study": "studying",
    "studying": "studying",
    "road trip": "road trip",
    "roadtrip": "road trip",
    "drive": "driving",
    "driving": "driving",
    "workout": "workout",
    "gym": "workout",
    "running": "running",
    "cooking": "cooking",
    "party": "party",
    "sleep": "sleep",
    "reading": "reading",
    "meditation": "meditation",
    "yoga": "yoga",
}

_NUMBER_WORDS = {
    "one": 1,
    "an": 1,
    "a": 1,
    "two": 2,
    "three": 3,
    "four": 4,
    "five": 5,
    "half": 0.5,
}
_DURATION_RE = re.compile(
    r"\b(?P<num>\d+(?:\.\d+)?|one|two|three|four|five|an|a|half)[\s-]*"
    r"(?P<unit>hours?|hrs?|h\b|minutes?|mins?)",
    re.IGNORECASE,
)
_ERA_RE = re.compile(r"\b(?:(?:19|20)?([0-9])0'?s)\b", re.IGNORECASE)
_SIMILAR_RE = re.compile(r"(?:like|similar to|songs by|by)\s+([A-Z][\w.&' -]{1,40})")


@dataclass(slots=True)
class PreferenceHints:
    languages: list[str] = field(default_factory=list)
    genres: list[str] = field(default_factory=list)
    moods: list[str] = field(default_factory=list)
    favorite_artists: list[str] = field(default_factory=list)
    excluded_artists: list[str] = field(default_factory=list)
    discovery: str = "balanced"


def _parse_duration(text: str) -> int | None:
    match = _DURATION_RE.search(text)
    if not match:
        return None
    raw = match.group("num").lower()
    value = float(_NUMBER_WORDS[raw]) if raw in _NUMBER_WORDS else float(raw)
    unit = match.group("unit").lower()
    minutes = value * 60 if unit.startswith("h") else value
    return max(10, min(int(round(minutes)), 300))


def _parse_era(text: str) -> str | None:
    match = _ERA_RE.search(text)
    if not match:
        return None
    digit = int(match.group(1))
    token = match.group(0).lower()
    if token.startswith("19") or (len(token) <= 4 and digit >= 5):
        return f"19{digit}0s"
    return f"20{digit}0s"


def extract_intent(
    text: str,
    hints: PreferenceHints | None = None,
    *,
    mood: str | None = None,
    language: str | None = None,
    genres: list[str] | None = None,
    energy: int | None = None,
    duration_minutes: int | None = None,
    discovery: str | None = None,
) -> MusicIntent:
    """Explicit arguments (from the Playlist Studio form) override what the text implies."""
    hints = hints or PreferenceHints()
    lowered = f" {text.lower()} "

    found_mood = mood
    if not found_mood:
        for candidate, words in MOOD_WORDS.items():
            if any(word in lowered for word in words):
                found_mood = candidate
                break
    if not found_mood and hints.moods:
        found_mood = hints.moods[0]

    found_language = language
    if not found_language:
        for word, name in LANGUAGES.items():
            if re.search(rf"\b{re.escape(word)}\b", lowered):
                found_language = name
                break
    if not found_language and hints.languages:
        found_language = hints.languages[0]

    found_genres = list(genres or [])
    for genre in GENRES:
        if re.search(rf"(?<![\w-]){re.escape(genre)}(?![\w-])", lowered):
            normalized = _GENRE_ALIASES.get(genre, genre)
            if normalized not in found_genres:
                found_genres.append(normalized)
    if not found_genres and hints.genres:
        found_genres = hints.genres[:2]

    activity = next((v for k, v in ACTIVITIES.items() if f" {k}" in lowered), None)
    era = _parse_era(text)

    vocals = "any"
    if any(w in lowered for w in ("minimal vocals", "no vocals", "low vocals", "few vocals")):
        vocals = "minimal"
    if "instrumental" in lowered or "without lyrics" in lowered:
        vocals = "instrumental"

    found_discovery = discovery
    if not found_discovery:
        if any(
            w in lowered
            for w in (
                "less popular",
                "underrated",
                "hidden gem",
                "obscure",
                "lesser known",
                "lesser-known",
                "new to me",
                "discover",
            )
        ):
            found_discovery = "discovery"
        elif any(
            w in lowered
            for w in (
                "popular",
                "hits",
                "top songs",
                "classics",
                "familiar",
                "favorites",
                "favourites",
                "best of",
            )
        ):
            found_discovery = "familiar"
        else:
            found_discovery = hints.discovery

    found_energy = energy
    if found_energy is None:
        found_energy = MOOD_ENERGY.get(found_mood or "", 50)
        if vocals != "any":
            found_energy = min(found_energy, 45)

    duration = duration_minutes or _parse_duration(text) or 60

    references = [m.strip(" .") for m in _SIMILAR_RE.findall(text)]
    if "my favorite" in lowered or "my favourite" in lowered:
        references.extend(hints.favorite_artists[:4])

    queries = build_queries(
        mood=found_mood,
        language=found_language,
        genres=found_genres,
        activity=activity,
        era=era,
        vocals=vocals,
        references=references,
        discovery=found_discovery,
        text=text,
    )

    title_bits = [b for b in (found_language, (found_mood or "").title() or None) if b]
    if activity:
        descriptor = activity.title()
    else:
        descriptor = found_genres[0].title() if found_genres else "Mix"
    title = " ".join([*title_bits, descriptor]).strip() or "Halo Mix"

    explanation_parts = []
    if found_mood:
        explanation_parts.append(f"a {found_mood} mood")
    if found_language:
        explanation_parts.append(f"{found_language} music")
    if found_genres:
        explanation_parts.append(", ".join(found_genres[:3]))
    if era:
        explanation_parts.append(f"from the {era}")
    if vocals != "any":
        explanation_parts.append(f"{vocals} vocals")
    explanation = (
        "I looked for " + "; ".join(explanation_parts) + "."
        if explanation_parts
        else "I searched for music matching your description."
    )

    return MusicIntent(
        mood=found_mood,  # type: ignore[arg-type]
        language=found_language,
        genres=found_genres[:6],
        activity=activity,
        era=era,
        energy=found_energy,
        vocals=vocals,  # type: ignore[arg-type]
        duration_minutes=duration,
        discovery=found_discovery,  # type: ignore[arg-type]
        reference_artists=references[:8],
        exclude_artists=hints.excluded_artists[:20],
        search_queries=queries,
        playlist_title=title[:80],
        explanation=explanation,
    )


_STOPWORDS = {
    "find",
    "create",
    "make",
    "build",
    "a",
    "an",
    "the",
    "me",
    "some",
    "for",
    "playlist",
    "songs",
    "song",
    "music",
    "with",
    "of",
    "from",
    "to",
    "my",
    "please",
    "recommend",
    "and",
    "that",
    "are",
    "but",
    "i",
    "want",
    "give",
    "play",
    "list",
    "tracks",
    "similar",
    "like",
}


def build_queries(
    *,
    mood: str | None,
    language: str | None,
    genres: list[str],
    activity: str | None,
    era: str | None,
    vocals: str,
    references: list[str],
    discovery: str | None,
    text: str,
) -> list[str]:
    lang = f"{language} " if language else ""
    queries: list[str] = []
    for genre in genres[:2]:
        queries.append(f"{lang}{genre} songs {era or ''}".strip())
    if mood:
        mood_term = {"focused": "focus", "sleep": "sleep", "travel": "road trip"}.get(mood, mood)
        queries.append(f"{lang}{mood_term} songs {era or ''}".strip())
    if activity:
        suffix = "instrumental" if vocals != "any" else "songs"
        queries.append(f"{lang}{activity} music {suffix}".strip())
    if vocals == "instrumental" and not activity:
        queries.append(f"{lang}instrumental music".strip())
    for artist in references[:2]:
        queries.append(f"{artist} songs" if discovery != "discovery" else f"artists like {artist}")
    if discovery == "discovery" and (genres or mood):
        queries.append(f"{lang}{(genres or [mood or ''])[0]} underrated songs".strip())
    if not queries:
        words = [w for w in re.findall(r"[\w'&-]+", text.lower()) if w not in _STOPWORDS]
        queries.append(" ".join(words[:8]) or "popular music")
    seen: list[str] = []
    for query in queries:
        cleaned = " ".join(query.split())
        if cleaned and cleaned.lower() not in {s.lower() for s in seen}:
            seen.append(cleaned)
    return seen[:5]
