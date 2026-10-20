"""Multi-stage recommendation pipeline.

request -> intent (LLM or heuristic)
-> candidate generation from several sources:
     search (planner queries), similar_artist (open artist graphs), listenbrainz (popular
     tracks by similar artists from ListenBrainz listening data, matched in the catalog),
     co_listen (playlist co-occurrence across opted-in listeners, passed in by the caller)
-> verified metadata retrieval -> filtering
-> ranking (heuristic relevance + learnable feature weights)
-> exploration budget chosen by Thompson sampling over sources
-> diversity -> duration-fitted playlist -> feedback updates the bandit and ranker data

Every track in the output came back from the catalog (Audius, Jamendo, iTunes previews) in
this request, so no id is ever invented and every track has a stream URL.
"""

from __future__ import annotations

import asyncio
import logging
import math
import random
import re
from dataclasses import dataclass, field

from app.schemas import RecommendedTrack, Track
from app.services.ai.heuristic import PreferenceHints
from app.services.ai.intent import MusicIntent
from app.services.catalog.base import CatalogError
from app.services.catalog.service import CatalogService
from app.services.music_sources.similar_artists import SimilarArtist
from app.services.recommendations.bandit import (
    ArmPosterior,
    choose_arm,
    explore_quota,
)
from app.services.recommendations.ranker import RankerModel

logger = logging.getLogger("halo.recommendations")

MIN_TRACK_SECONDS = 60
MAX_TRACK_SECONDS = 15 * 60
MAX_PLAYLIST_TRACKS = 100
RESULTS_PER_QUERY = 25

_WORD = re.compile(r"[\w']+", re.UNICODE)
_NOISE = re.compile(
    r"\((?:official|lyric|lyrical|full|audio|video|hd|4k|hq|music video)[^)]*\)|"
    r"\[(?:official|lyric|lyrical|full|audio|video|hd|4k|hq)[^\]]*\]|"
    r"\b(?:official|lyrics?|lyrical|full song|full video|audio|video song|hd|4k)\b",
    re.IGNORECASE,
)
_LONG_FORM = ("jukebox", "nonstop", "non-stop", "mashup", "back to back", "hour", "hrs")


def normalize_name(value: str) -> str:
    return " ".join(_WORD.findall(value.lower()))


def song_key(track: Track) -> str:
    """Rough identity for near-duplicate uploads of the same song."""
    title = _NOISE.sub(" ", track.title.lower())
    title = title.split("|")[0].split(" - ")[-1] if " - " in title else title.split("|")[0]
    return " ".join(_WORD.findall(title))[:60]


@dataclass(slots=True)
class FeedbackSignals:
    liked_track_ids: set[str] = field(default_factory=set)
    disliked_track_ids: set[str] = field(default_factory=set)
    liked_artists: set[str] = field(default_factory=set)
    disliked_artists: set[str] = field(default_factory=set)


@dataclass(slots=True)
class Candidate:
    track: Track
    query: str
    rank: int
    score: float = 0.0
    reasons: list[str] = field(default_factory=list)
    source: str = "search"
    source_reason: str | None = None
    cf_score: float = 0.0
    explore: bool = False
    features: dict[str, float] = field(default_factory=dict)


@dataclass(slots=True)
class PipelineResult:
    tracks: list[RecommendedTrack]
    total_duration_seconds: int
    target_duration_seconds: int
    warnings: list[str]
    filtered_counts: dict[str, int]
    details: dict[str, dict[str, object]] = field(default_factory=dict)


def _allows_long_form(intent: MusicIntent) -> bool:
    text = " ".join([*intent.search_queries, intent.activity or ""]).lower()
    return any(word in text for word in ("jukebox", "nonstop", "mix", "mashup"))


def filter_candidates(
    candidates: list[Candidate],
    intent: MusicIntent,
    hints: PreferenceHints,
    feedback: FeedbackSignals,
    exclude_track_ids: set[str],
) -> tuple[list[Candidate], dict[str, int]]:
    excluded_names = {normalize_name(a) for a in [*intent.exclude_artists, *hints.excluded_artists]}
    excluded_names.discard("")
    long_form_ok = _allows_long_form(intent)
    counts = {
        "duplicate": 0,
        "excluded_artist": 0,
        "duration": 0,
        "disliked": 0,
        "excluded_track": 0,
        "not_playable": 0,
    }
    seen_ids: set[str] = set()
    kept: list[Candidate] = []
    for cand in candidates:
        track = cand.track
        if track.id in seen_ids:
            counts["duplicate"] += 1
            continue
        seen_ids.add(track.id)
        if track.id in exclude_track_ids:
            counts["excluded_track"] += 1
            continue
        artist = normalize_name(track.artist)
        title = normalize_name(track.title)
        if any(name and (name in artist or name in title) for name in excluded_names):
            counts["excluded_artist"] += 1
            continue
        if track.id in feedback.disliked_track_ids:
            counts["disliked"] += 1
            continue
        if not track.stream_url:
            counts["not_playable"] += 1
            continue
        duration = track.duration_seconds
        # Previews report the full song's length; only full tracks can be too short.
        if duration is not None and duration < MIN_TRACK_SECONDS and not track.is_preview:
            counts["duration"] += 1
            continue
        title_lower = track.title.lower()
        if not long_form_ok and (
            (duration is not None and duration > MAX_TRACK_SECONDS)
            or any(word in title_lower for word in _LONG_FORM)
        ):
            counts["duration"] += 1
            continue
        kept.append(cand)
    return kept, counts


def _intent_terms(intent: MusicIntent) -> set[str]:
    terms: set[str] = set()
    for value in [intent.language, intent.mood, intent.activity, intent.era, *intent.genres]:
        if value:
            terms.update(_WORD.findall(value.lower()))
    if intent.vocals == "instrumental":
        terms.add("instrumental")
    return terms


def score_candidates(
    candidates: list[Candidate],
    intent: MusicIntent,
    hints: PreferenceHints,
    feedback: FeedbackSignals,
) -> None:
    terms = _intent_terms(intent)
    favorites = {normalize_name(a) for a in [*hints.favorite_artists, *intent.reference_artists]}
    favorites.discard("")
    views = [c.track.play_count for c in candidates if c.track.play_count]
    median_log_views = sorted(math.log10(v + 1) for v in views)[len(views) // 2] if views else 0.0
    for cand in candidates:
        track = cand.track
        reasons: list[str] = []
        score = 1.0 / (1.0 + cand.rank * 0.15)  # provider relevance for its query
        text = f"{track.title} {track.artist} {track.genre or ''} {track.mood or ''}"
        text_words = set(_WORD.findall(text.lower()))
        overlap = terms & text_words
        if overlap:
            score += 0.12 * len(overlap)
            reasons.append("Matches " + ", ".join(sorted(overlap)[:3]))
        artist = normalize_name(track.artist)
        if any(fav and (fav in artist or fav in normalize_name(track.title)) for fav in favorites):
            if intent.discovery == "discovery":
                score -= 0.15
            else:
                score += 0.35
                reasons.append(f"From {track.artist}, an artist you like")
        if track.id in feedback.liked_track_ids:
            score += 0.3 if intent.discovery != "discovery" else -0.2
            reasons.append("You liked this before")
        if artist in feedback.liked_artists:
            score += 0.15
        if artist in feedback.disliked_artists:
            score -= 0.4
        if track.is_preview:
            score -= 0.25  # a 30-second preview is a weaker pick than a full song
        if track.play_count and median_log_views:
            delta = math.log10(track.play_count + 1) - median_log_views
            if intent.discovery == "familiar":
                score += 0.08 * delta
                if delta > 0.5:
                    reasons.append("Widely loved")
            elif intent.discovery == "discovery":
                score -= 0.10 * delta
                if delta < -0.5:
                    reasons.append("A lesser-known pick")
        if intent.vocals != "any" and "instrumental" in text_words:
            score += 0.2
        cand.score = round(score, 4)
        reasons.append(cand.source_reason or f"Found for “{cand.query}”")
        cand.reasons = reasons
        cand.features = {
            "relevance": cand.score,
            "cf_score": cand.cf_score,
            "similar_artist": 1.0 if cand.source == "similar_artist" else 0.0,
            "co_listen": 1.0 if cand.source == "co_listen" else 0.0,
            "listenbrainz": 1.0 if cand.source == "listenbrainz" else 0.0,
            "liked_channel": 1.0 if artist in feedback.liked_artists else 0.0,
        }
        popularity = (
            math.log10(track.play_count + 1) - median_log_views
            if track.play_count and median_log_views
            else 0.0
        )
        direction = {"familiar": 1.0, "discovery": -1.0}.get(intent.discovery, 0.0)
        cand.features["popularity_z"] = round(popularity, 4)
        cand.features["pop_x_discovery"] = round(popularity * direction, 4)


def diversify(
    candidates: list[Candidate], intent: MusicIntent, target_seconds: int
) -> list[Candidate]:
    """Greedy selection with per-artist caps and near-duplicate suppression."""
    per_artist_cap = 2 if intent.discovery == "discovery" else 3
    remaining = sorted(candidates, key=lambda c: c.score, reverse=True)
    chosen: list[Candidate] = []
    artist_counts: dict[str, int] = {}
    song_keys: set[str] = set()
    total = 0
    while remaining and len(chosen) < MAX_PLAYLIST_TRACKS and total < target_seconds:
        best_index = None
        best_value = -math.inf
        for index, cand in enumerate(remaining):
            key = song_key(cand.track)
            if key and key in song_keys:
                continue
            artist = normalize_name(cand.track.artist)
            used = artist_counts.get(artist, 0)
            if used >= per_artist_cap:
                continue
            value = cand.score - 0.2 * used
            if value > best_value:
                best_value, best_index = value, index
        if best_index is None:
            break
        cand = remaining.pop(best_index)
        chosen.append(cand)
        artist = normalize_name(cand.track.artist)
        artist_counts[artist] = artist_counts.get(artist, 0) + 1
        song_keys.add(song_key(cand.track))
        total += cand.track.duration_seconds or 210
    return chosen


def rank_and_explore(
    candidates: list[Candidate],
    intent: MusicIntent,
    target_seconds: int,
    *,
    ranker: RankerModel,
    posteriors: dict[str, ArmPosterior],
    favorites: set[str],
    rng: random.Random,
) -> list[Candidate]:
    """Exploit the ranker for most slots; spend an exploration budget via Thompson sampling."""
    for cand in candidates:
        cand.score = round(ranker.score(cand.features), 4)
    ranked = sorted(candidates, key=lambda c: c.score, reverse=True)
    expected = max(4, target_seconds // 210)
    quota = explore_quota(intent.discovery, expected)
    # Exploration only considers items the ranker alone would not have selected.
    pool = ranked[max(expected - quota, 0) :]
    picks: list[Candidate] = []
    used_artists: set[str] = set()
    for _ in range(quota):
        available = {c.source for c in pool if c not in picks}
        arm = choose_arm(posteriors, available, rng)
        if arm is None:
            break
        options = [
            c
            for c in pool
            if c.source == arm
            and c not in picks
            and normalize_name(c.track.artist) not in used_artists
        ]
        # Prefer artists the listener hasn't marked as favorites: exploration should be new.
        options.sort(key=lambda c: (normalize_name(c.track.artist) in favorites, -c.score))
        if not options:
            pool = [c for c in pool if c.source != arm]
            continue
        choice = options[0]
        choice.explore = True
        choice.reasons = ["Something new for you", *choice.reasons]
        picks.append(choice)
        used_artists.add(normalize_name(choice.track.artist))
    explore_seconds = sum(c.track.duration_seconds or 210 for c in picks)
    exploit = diversify(
        [c for c in ranked if c not in picks], intent, max(target_seconds - explore_seconds, 0)
    )
    # Spread exploration picks through the playlist instead of bunching them.
    merged = list(exploit)
    if picks:
        step = max(len(merged) // (len(picks) + 1), 1)
        for i, pick in enumerate(picks):
            merged.insert(min((i + 1) * step + i, len(merged)), pick)
    return merged


class RecommendationPipeline:
    def __init__(
        self,
        catalog: CatalogService,
        *,
        similar_artists: object | None = None,
        track_discovery: object | None = None,
        track_lookups: int = 4,
        concurrency: int = 3,
    ) -> None:
        self._catalog = catalog
        self._similar = similar_artists
        self._discovery = track_discovery
        self._track_lookups = track_lookups
        self._semaphore = asyncio.Semaphore(concurrency)

    async def _match_in_catalog(self, artist: str, title: str) -> Track | None:
        """Find a playable copy of a known song in the catalog, or None if unsure."""
        _, items, _ = await self._retrieve(f"{artist} {title}", 3)
        artist_words = set(normalize_name(artist).split())
        title_words = set(normalize_name(title).split()) - {"the", "a", "of"}
        for track in items:
            text = set(normalize_name(f"{track.title} {track.artist}").split())
            if artist_words & text and len(title_words & text) >= max(1, len(title_words) // 2):
                return track
        return None

    async def _listenbrainz_candidates(
        self, intent: MusicIntent, hints: PreferenceHints
    ) -> list[Candidate]:
        if self._discovery is None or self._track_lookups <= 0:
            return []
        seeds = list(dict.fromkeys([*intent.reference_artists, *hints.favorite_artists]))
        if not seeds:
            return []
        excluded = {normalize_name(a) for a in [*intent.exclude_artists, *hints.excluded_artists]}
        recordings = await self._discovery.tracks(  # type: ignore[attr-defined]
            seeds[0], discovery=intent.discovery, limit=self._track_lookups * 2
        )
        picks = [r for r in recordings if normalize_name(r.artist_name) not in excluded]
        matched = await asyncio.gather(
            *(self._match_in_catalog(r.artist_name, r.title) for r in picks[: self._track_lookups])
        )
        return [
            Candidate(
                track=track,
                query=f"{rec.artist_name} {rec.title}",
                rank=rank,
                source="listenbrainz",
                source_reason=f"Popular with fans of {rec.similar_to or seeds[0]} on ListenBrainz",
            )
            for rank, (rec, track) in enumerate(zip(picks, matched, strict=False))
            if track is not None
        ]

    async def _similar_queries(
        self, intent: MusicIntent, hints: PreferenceHints
    ) -> list[tuple[str, str]]:
        """(query, reason) pairs for artists similar to the listener's or request's artists."""
        if self._similar is None:
            return []
        excluded = {normalize_name(a) for a in [*intent.exclude_artists, *hints.excluded_artists]}
        seeds = list(dict.fromkeys([*intent.reference_artists, *hints.favorite_artists]))[:2]
        out: list[tuple[str, str]] = []
        for seed in seeds:
            similar: list[SimilarArtist] = await self._similar.similar(seed, limit=8)  # type: ignore[attr-defined]
            for artist in [a for a in similar if normalize_name(a.name) not in excluded][:2]:
                out.append((artist.name, f"Similar to {seed}"))
        return out

    async def _retrieve(
        self, query: str, limit: int = RESULTS_PER_QUERY
    ) -> tuple[str, list[Track], str | None]:
        async with self._semaphore:
            try:
                result = await self._catalog.search(query, max_results=limit)
                return query, result.page.items, None
            except CatalogError as exc:
                logger.warning("retrieval failed for one planner query: %s", type(exc).__name__)
                return query, [], str(exc)

    async def run(
        self,
        intent: MusicIntent,
        hints: PreferenceHints,
        feedback: FeedbackSignals | None = None,
        exclude_track_ids: set[str] | None = None,
        *,
        extra_candidates: list[Candidate] | None = None,
        ranker: RankerModel | None = None,
        posteriors: dict[str, ArmPosterior] | None = None,
        rng: random.Random | None = None,
    ) -> PipelineResult:
        feedback = feedback or FeedbackSignals()
        target = intent.duration_minutes * 60
        similar_queries = await self._similar_queries(intent, hints)
        results = await asyncio.gather(
            *(self._retrieve(q) for q in intent.search_queries[:5]),
            *(self._retrieve(q, 10) for q, _ in similar_queries),
        )
        main_results = results[: len(intent.search_queries[:5])]
        warnings = sorted({err for _, _, err in main_results if err})
        if all(err for _, _, err in main_results) and not extra_candidates:
            raise CatalogError(warnings[0] if warnings else "Music search is unavailable")

        # Interleave queries so the first query does not dominate ties.
        candidates: list[Candidate] = []
        longest = max((len(items) for _, items, _ in main_results), default=0)
        for rank in range(longest):
            for query, items, _ in main_results:
                if rank < len(items):
                    candidates.append(Candidate(track=items[rank], query=query, rank=rank))
        for (query, items, _), (_, reason) in zip(
            results[len(main_results) :], similar_queries, strict=True
        ):
            candidates.extend(
                Candidate(
                    track=t, query=query, rank=r, source="similar_artist", source_reason=reason
                )
                for r, t in enumerate(items)
            )
        candidates.extend(await self._listenbrainz_candidates(intent, hints))
        candidates.extend(extra_candidates or [])

        filtered, counts = filter_candidates(
            candidates, intent, hints, feedback, exclude_track_ids or set()
        )
        score_candidates(filtered, intent, hints, feedback)
        favorites = {
            normalize_name(a) for a in [*hints.favorite_artists, *intent.reference_artists]
        }
        chosen = rank_and_explore(
            filtered,
            intent,
            target,
            ranker=ranker or RankerModel(),
            posteriors=posteriors or {},
            favorites=favorites,
            rng=rng or random.Random(),
        )
        total = sum(c.track.duration_seconds or 0 for c in chosen)
        if not chosen:
            warnings.append("No songs matched. Try a broader description.")
        elif total < target * 0.8:
            warnings.append(
                f"Only found about {total // 60} minutes of matching music "
                f"for a {intent.duration_minutes}-minute target."
            )
        return PipelineResult(
            tracks=[
                RecommendedTrack(
                    track=c.track,
                    score=c.score,
                    reasons=c.reasons,
                    matched_query=c.query,
                    source=c.source,
                    explore=c.explore,
                )
                for c in chosen
            ],
            details={
                c.track.id: {"source": c.source, "explore": c.explore, "features": c.features}
                for c in chosen
            },
            total_duration_seconds=total,
            target_duration_seconds=target,
            warnings=warnings,
            filtered_counts=counts,
        )
