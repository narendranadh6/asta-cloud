"""Multi-stage recommendation pipeline.

request -> intent (LLM or heuristic)
-> candidate generation from several sources:
     search (planner queries), similar_artist (open artist graphs), co_listen (playlist
     co-occurrence across opted-in listeners, passed in by the caller)
-> verified metadata retrieval -> filtering
-> ranking (heuristic relevance + learnable feature weights)
-> exploration budget chosen by Thompson sampling over sources
-> diversity -> duration-fitted playlist -> feedback updates the bandit and ranker data

Every track in the output came back from the metadata provider in this request (search
results are verified through videos.list), so no id is ever invented.
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
from app.services.music_sources.similar_artists import SimilarArtist
from app.services.recommendations.bandit import (
    ArmPosterior,
    choose_arm,
    explore_quota,
)
from app.services.recommendations.ranker import RankerModel
from app.services.youtube.base import YouTubeError
from app.services.youtube.service import YouTubeSearchService

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
    liked_video_ids: set[str] = field(default_factory=set)
    disliked_video_ids: set[str] = field(default_factory=set)
    liked_channels: set[str] = field(default_factory=set)
    disliked_channels: set[str] = field(default_factory=set)


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
    exclude_video_ids: set[str],
) -> tuple[list[Candidate], dict[str, int]]:
    excluded_names = {normalize_name(a) for a in [*intent.exclude_artists, *hints.excluded_artists]}
    excluded_names.discard("")
    long_form_ok = _allows_long_form(intent)
    counts = {
        "duplicate": 0,
        "excluded_artist": 0,
        "duration": 0,
        "live_now": 0,
        "disliked": 0,
        "excluded_video": 0,
    }
    seen_ids: set[str] = set()
    kept: list[Candidate] = []
    for cand in candidates:
        track = cand.track
        if track.video_id in seen_ids:
            counts["duplicate"] += 1
            continue
        seen_ids.add(track.video_id)
        if track.video_id in exclude_video_ids:
            counts["excluded_video"] += 1
            continue
        channel = normalize_name(track.channel_title)
        title = normalize_name(track.title)
        if any(name and (name in channel or name in title) for name in excluded_names):
            counts["excluded_artist"] += 1
            continue
        if track.video_id in feedback.disliked_video_ids:
            counts["disliked"] += 1
            continue
        if track.is_live:
            counts["live_now"] += 1
            continue
        duration = track.duration_seconds
        if duration is not None and duration < MIN_TRACK_SECONDS:
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
    views = [c.track.view_count for c in candidates if c.track.view_count]
    median_log_views = sorted(math.log10(v + 1) for v in views)[len(views) // 2] if views else 0.0
    for cand in candidates:
        track = cand.track
        reasons: list[str] = []
        score = 1.0 / (1.0 + cand.rank * 0.15)  # provider relevance for its query
        text_words = set(_WORD.findall(f"{track.title} {track.channel_title}".lower()))
        overlap = terms & text_words
        if overlap:
            score += 0.12 * len(overlap)
            reasons.append("Matches " + ", ".join(sorted(overlap)[:3]))
        channel = normalize_name(track.channel_title)
        if any(fav and (fav in channel or fav in normalize_name(track.title)) for fav in favorites):
            if intent.discovery == "discovery":
                score -= 0.15
            else:
                score += 0.35
                reasons.append(f"From {track.channel_title}, an artist you like")
        if track.video_id in feedback.liked_video_ids:
            score += 0.3 if intent.discovery != "discovery" else -0.2
            reasons.append("You liked this before")
        if channel in feedback.liked_channels:
            score += 0.15
        if channel in feedback.disliked_channels:
            score -= 0.4
        if track.view_count and median_log_views:
            delta = math.log10(track.view_count + 1) - median_log_views
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
            "liked_channel": 1.0 if channel in feedback.liked_channels else 0.0,
        }
        popularity = (
            math.log10(track.view_count + 1) - median_log_views
            if track.view_count and median_log_views
            else 0.0
        )
        direction = {"familiar": 1.0, "discovery": -1.0}.get(intent.discovery, 0.0)
        cand.features["popularity_z"] = round(popularity, 4)
        cand.features["pop_x_discovery"] = round(popularity * direction, 4)


def diversify(
    candidates: list[Candidate], intent: MusicIntent, target_seconds: int
) -> list[Candidate]:
    """Greedy selection with per-channel caps and near-duplicate suppression."""
    per_channel_cap = 2 if intent.discovery == "discovery" else 3
    remaining = sorted(candidates, key=lambda c: c.score, reverse=True)
    chosen: list[Candidate] = []
    channel_counts: dict[str, int] = {}
    song_keys: set[str] = set()
    total = 0
    while remaining and len(chosen) < MAX_PLAYLIST_TRACKS and total < target_seconds:
        best_index = None
        best_value = -math.inf
        for index, cand in enumerate(remaining):
            key = song_key(cand.track)
            if key and key in song_keys:
                continue
            channel = normalize_name(cand.track.channel_title)
            used = channel_counts.get(channel, 0)
            if used >= per_channel_cap:
                continue
            value = cand.score - 0.2 * used
            if value > best_value:
                best_value, best_index = value, index
        if best_index is None:
            break
        cand = remaining.pop(best_index)
        chosen.append(cand)
        channel = normalize_name(cand.track.channel_title)
        channel_counts[channel] = channel_counts.get(channel, 0) + 1
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
    used_channels: set[str] = set()
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
            and normalize_name(c.track.channel_title) not in used_channels
        ]
        # Prefer artists the listener hasn't marked as favorites: exploration should be new.
        options.sort(key=lambda c: (normalize_name(c.track.channel_title) in favorites, -c.score))
        if not options:
            pool = [c for c in pool if c.source != arm]
            continue
        choice = options[0]
        choice.explore = True
        choice.reasons = ["Something new for you", *choice.reasons]
        picks.append(choice)
        used_channels.add(normalize_name(choice.track.channel_title))
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
        search: YouTubeSearchService,
        *,
        similar_artists: object | None = None,
        concurrency: int = 3,
    ) -> None:
        self._search = search
        self._similar = similar_artists
        self._semaphore = asyncio.Semaphore(concurrency)

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
                out.append((f"{artist.name} songs", f"Similar to {seed}"))
        return out

    async def _retrieve(
        self, query: str, limit: int = RESULTS_PER_QUERY
    ) -> tuple[str, list[Track], str | None]:
        async with self._semaphore:
            try:
                result = await self._search.search(query, max_results=limit)
                return query, result.page.items, None
            except YouTubeError as exc:
                logger.warning("retrieval failed for one planner query: %s", type(exc).__name__)
                return query, [], str(exc)

    async def run(
        self,
        intent: MusicIntent,
        hints: PreferenceHints,
        feedback: FeedbackSignals | None = None,
        exclude_video_ids: set[str] | None = None,
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
            raise YouTubeError(warnings[0] if warnings else "Music search is unavailable")

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
        candidates.extend(extra_candidates or [])

        filtered, counts = filter_candidates(
            candidates, intent, hints, feedback, exclude_video_ids or set()
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
            warnings.append("No verified results matched. Try a broader description.")
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
                c.track.video_id: {"source": c.source, "explore": c.explore, "features": c.features}
                for c in chosen
            },
            total_duration_seconds=total,
            target_duration_seconds=target,
            warnings=warnings,
            filtered_counts=counts,
        )
