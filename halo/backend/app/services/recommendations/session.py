"""Halo Drive: candidates for a listening session the listener steers by voice.

The app sends its session state (vibe targets, language preference, recency, seed, artist
weights, exclusions); this module generates candidates from the catalog, scores each one on
explicit, inspectable features, applies hard constraints and diversity, and returns them with
their per-feature fit so the app can re-rank its pool instantly when the listener says
"more energy". The server keeps no session state.

Weights live in ``RANKING_WEIGHTS`` (versioned) so they can be tuned and A/B-measured
instead of being hidden inside a model.
"""

from __future__ import annotations

import asyncio
import logging
import math
from dataclasses import dataclass, field
from datetime import date

from app.schemas import (
    SessionCandidate,
    SessionCandidatesRequest,
    SessionCandidatesResponse,
    Track,
)
from app.services.catalog.base import CatalogError
from app.services.catalog.ids import is_valid_track_id
from app.services.catalog.service import CatalogService, song_key

logger = logging.getLogger("halo.session")

RANKING_VERSION = "session-v1"
RANKING_WEIGHTS: dict[str, float] = {
    "rank": 0.6,  # how well the catalog search matched the query
    "energy": 1.0,
    "tempo": 0.4,
    "language": 1.2,
    "recency": 0.8,
    "discovery": 0.5,
    "seed": 0.6,
    "artist": 1.0,
}
# Per-artist cap in one response, so a single artist can't take over a drive.
ARTIST_CAP = 2
# Unknown features score neutral rather than good or bad.
UNKNOWN = 0.5

_LANGUAGE_QUERY = {"te": "telugu", "hi": "hindi", "ta": "tamil", "kn": "kannada", "ml": "malayalam"}


@dataclass(slots=True)
class _Candidate:
    track: Track
    rank: float
    source: str
    fit: dict[str, float] = field(default_factory=dict)
    score: float = 0.0


def _key(name: str) -> str:
    return " ".join("".join(c if c.isalnum() else " " for c in name.lower()).split())


def queries_for(request: SessionCandidatesRequest, seed: Track | None) -> list[tuple[str, str]]:
    """(query, source) pairs: the entity first, then the seed, then the session's vibe."""
    queries: list[tuple[str, str]] = []
    if request.entity:
        queries += [(request.entity.name, "entity"), (f"{request.entity.name} songs", "entity")]
    language = _LANGUAGE_QUERY.get(request.language.primary) if request.language else None
    vibe = request.vibe
    words: list[str] = []
    if vibe.energy is not None:
        words += (
            ["energetic", "dance"]
            if vibe.energy >= 0.65
            else ["calm", "melody"]
            if vibe.energy <= 0.35
            else []
        )
    if vibe.valence is not None and vibe.valence >= 0.7:
        words.append("happy")
    era = request.recency
    if era.mode == "decade" and era.value:
        words.append(f"{era.value % 100:02d}s")
    elif era.mode == "classics":
        words.append("old hits")
    elif era.mode == "within_days":
        words.append("new")
    if seed and request.seed_mode != "elsewhere":
        queries.append((seed.artist, "seed"))
        if seed.genre:
            queries.append((" ".join(filter(None, [language, seed.genre])), "seed"))
    for word in words[:2] or [""]:
        text = " ".join(filter(None, [language, word]))
        if text:
            queries.append((text, "intent"))
    if language and not any(q == language for q, _ in queries):
        queries.append((language, "intent"))
    # A second language needs its own candidates. English has no useful search word, so it
    # uses the vibe words (or a broad genre) on their own.
    secondary = request.language.secondary if request.language else None
    if secondary and request.language and request.language.strategy != "only":
        word = (words or ["pop"])[0]
        other = _LANGUAGE_QUERY.get(secondary)
        queries.append((" ".join(filter(None, [other, word])), "intent"))
    seen: set[str] = set()
    unique = []
    for query, source in queries:
        if query.lower() not in seen:
            seen.add(query.lower())
            unique.append((query, source))
    return unique[:7]


class SessionRecommender:
    def __init__(self, catalog: CatalogService, *, today: date | None = None) -> None:
        self._catalog = catalog
        self._today = today

    async def candidates(self, request: SessionCandidatesRequest) -> SessionCandidatesResponse:
        seed: Track | None = None
        if request.seed_track_id and is_valid_track_id(request.seed_track_id):
            try:
                seed = await self._catalog.get_track(request.seed_track_id)
            except CatalogError:
                seed = None
        queries = queries_for(request, seed)
        warnings: list[str] = []
        found = await asyncio.gather(
            *(self._catalog.search(q, max_results=25) for q, _ in queries), return_exceptions=True
        )
        pool: dict[str, _Candidate] = {}
        sources: set[str] = set()
        for (query, source), result in zip(queries, found, strict=True):
            if isinstance(result, BaseException):
                warnings.append(f"'{query}' couldn't be searched right now")
                continue
            sources.update(result.page.sources)
            for position, track in enumerate(result.page.items):
                rank = 1 / (1 + 0.1 * position)
                current = pool.get(track.id)
                if current is None or rank > current.rank:
                    pool[track.id] = _Candidate(track, rank, source)
        if request.recency.mode == "within_days" or (request.vibe.discovery or 0) >= 0.6:
            try:
                fresh = await self._catalog.trending(max_results=25)
                for position, track in enumerate(fresh.page.items):
                    pool.setdefault(
                        track.id, _Candidate(track, 0.6 / (1 + 0.1 * position), "fresh")
                    )
            except CatalogError:
                warnings.append("New releases couldn't be loaded right now")

        excluded_ids = set(request.excluded_track_ids) | ({seed.id} if seed else set())
        excluded_artists = {_key(a) for a in request.excluded_artists if a.strip()}
        weights = {_key(k): v for k, v in request.artist_weights.items()}
        scored: list[_Candidate] = []
        for candidate in pool.values():
            track = candidate.track
            if track.id in excluded_ids or track.is_preview or not track.stream_url:
                continue
            if _key(track.artist) in excluded_artists:
                continue
            if self._violates_language(request, track):
                continue
            candidate.fit = self._fit(request, candidate, seed, weights)
            candidate.score = sum(RANKING_WEIGHTS[k] * v for k, v in candidate.fit.items())
            scored.append(candidate)
        scored.sort(key=lambda c: c.score, reverse=True)
        chosen = self._diversify(scored, request.limit)
        chosen = self._arrange_languages(request, chosen)
        return SessionCandidatesResponse(
            candidates=[
                SessionCandidate(
                    track=c.track,
                    score=round(c.score, 4),
                    fit={k: round(v, 3) for k, v in c.fit.items()},
                    source=c.source,  # type: ignore[arg-type]
                )
                for c in chosen
            ],
            ranking_version=RANKING_VERSION,
            sources=sorted(sources),
            warnings=warnings,
        )

    # --- Scoring ---------------------------------------------------------------------------

    @staticmethod
    def _violates_language(request: SessionCandidatesRequest, track: Track) -> bool:
        """ "Telugu only" drops songs known to be in another language; unknown ones stay."""
        language = request.language
        if not language or language.strategy != "only" or not track.language:
            return False
        return track.language != language.primary

    def _fit(
        self,
        request: SessionCandidatesRequest,
        candidate: _Candidate,
        seed: Track | None,
        weights: dict[str, float],
    ) -> dict[str, float]:
        track, vibe = candidate.track, request.vibe

        def closeness(target: float | None, value: float | None) -> float:
            if target is None:
                return UNKNOWN
            return UNKNOWN if value is None else 1 - abs(target - value)

        popularity = min(math.log10((track.play_count or 0) + 1) / 7, 1)
        discovery = (
            UNKNOWN if vibe.discovery is None else 1 - abs(vibe.discovery - (1 - popularity))
        )
        artist = weights.get(_key(track.artist), 0.0)
        return {
            "rank": candidate.rank,
            "energy": closeness(vibe.energy, track.energy),
            "tempo": closeness(vibe.tempo, track.tempo),
            "language": self._language_fit(request, track),
            "recency": self._recency_fit(request, track),
            "discovery": discovery,
            "seed": self._seed_fit(request, track, seed),
            "artist": max(min(artist, 1.0), -1.0),
        }

    @staticmethod
    def _language_fit(request: SessionCandidatesRequest, track: Track) -> float:
        language = request.language
        if not language:
            return UNKNOWN
        if track.language is None:
            return 0.4
        if track.language == language.primary:
            return 1.0
        if track.language == language.secondary:
            return {"mostly": 0.6, "mixed": 0.9, "alternating": 0.95}.get(language.strategy, 0.2)
        return 0.0

    def _recency_fit(self, request: SessionCandidatesRequest, track: Track) -> float:
        era = request.recency
        if era.mode == "any":
            return UNKNOWN
        released = _parse_date(track.release_date)
        if released is None:
            return 0.4
        today = self._today or date.today()
        if era.mode == "within_days":
            age = (today - released).days
            limit = era.value or 90
            return 1.0 if age <= limit else max(0.0, 1 - (age - limit) / (limit * 4))
        if era.mode == "decade" and era.value:
            if era.value <= released.year < era.value + 10:
                return 1.0
            distance = min(abs(released.year - era.value), abs(released.year - era.value - 9))
            return max(0.0, 1 - distance / 15)
        return 1.0 if today.year - released.year >= 10 else 0.2  # classics

    @staticmethod
    def _seed_fit(request: SessionCandidatesRequest, track: Track, seed: Track | None) -> float:
        if seed is None:
            return UNKNOWN
        same_artist = _key(track.artist) == _key(seed.artist)
        same_genre = bool(track.genre and seed.genre and track.genre.lower() == seed.genre.lower())
        closeness = 0.9 if same_artist else 0.65 if same_genre else 0.3
        if request.seed_mode == "elsewhere":
            return 1 - closeness
        if request.seed_mode == "deeper":
            popularity = min(math.log10((track.play_count or 0) + 1) / 7, 1)
            return closeness * (1 - 0.5 * popularity)
        return closeness

    # --- Assembly --------------------------------------------------------------------------

    @staticmethod
    def _diversify(scored: list[_Candidate], limit: int) -> list[_Candidate]:
        chosen: list[_Candidate] = []
        per_artist: dict[str, int] = {}
        seen_songs: set[str] = set()
        for candidate in scored:
            artist = _key(candidate.track.artist)
            song = song_key(candidate.track)
            if per_artist.get(artist, 0) >= ARTIST_CAP or song in seen_songs:
                continue
            chosen.append(candidate)
            per_artist[artist] = per_artist.get(artist, 0) + 1
            seen_songs.add(song)
            if len(chosen) == limit:
                break
        return chosen

    @staticmethod
    def _arrange_languages(
        request: SessionCandidatesRequest, chosen: list[_Candidate]
    ) -> list[_Candidate]:
        """Interleave two languages for "mostly", "mixed" and "alternating" sessions."""
        language = request.language
        if not language or not language.secondary or language.strategy == "only":
            return chosen
        first = [c for c in chosen if c.track.language != language.secondary]
        second = [c for c in chosen if c.track.language == language.secondary]
        every = {"mostly": 4, "mixed": 1, "alternating": 1}[language.strategy]
        arranged: list[_Candidate] = []
        while first or second:
            arranged.extend(first[:every])
            first = first[every:]
            if second:
                arranged.append(second.pop(0))
        return arranged


def _parse_date(value: str | None) -> date | None:
    if not value:
        return None
    try:
        return date.fromisoformat(value[:10])
    except ValueError:
        try:
            return date(int(value[:4]), 1, 1)
        except ValueError:
            return None
