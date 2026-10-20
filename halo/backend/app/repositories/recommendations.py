"""Collaborative-filtering signals and bandit/ranker persistence."""

from __future__ import annotations

import math
import uuid
from dataclasses import dataclass

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import (
    BanditArm,
    ModelArtifact,
    Playlist,
    PlaylistItem,
    RecommendationFeedback,
    RecommendationSession,
    TrackReference,
    UserPreferences,
)
from app.services.recommendations.bandit import ARMS, ArmPosterior, combine, reward
from app.services.recommendations.ranker import RankerModel

MIN_DISTINCT_USERS = 2  # a co-listen pair must come from at least this many listeners

# Halo track id ("<source>:<id>") computed in SQL from the stored reference.
TRACK_ID = TrackReference.provider.concat(":").concat(TrackReference.provider_id)


@dataclass(slots=True)
class CoListened:
    track_id: str
    score: float
    seed_title: str
    listeners: int


def _opted_in_playlists():  # type: ignore[no-untyped-def]
    """Playlists whose owners consented to personalization (only they feed CF)."""
    return (
        select(Playlist.id, Playlist.user_id)
        .join(UserPreferences, UserPreferences.user_id == Playlist.user_id)
        .where(UserPreferences.personalization_enabled.is_(True))
        .subquery()
    )


async def co_listened(
    session: AsyncSession, seed_track_ids: list[str], *, limit: int = 30
) -> list[CoListened]:
    """Item-to-item co-occurrence across opted-in listeners' playlists.

    The playlist co-occurrence idea behind Spotify's track embeddings ("tracks that
    appear together in playlists are similar"), scored with cosine normalisation:
    co(a, b) / sqrt(n(a) * n(b)). Pairs seen by fewer than MIN_DISTINCT_USERS listeners
    are dropped so no single person's playlist can be read back through recommendations.
    """
    seeds = list(dict.fromkeys(seed_track_ids))[:50]
    if not seeds:
        return []
    owners = _opted_in_playlists()
    seed_rows = (
        select(PlaylistItem.playlist_id, TRACK_ID.label("track_id"), TrackReference.title)
        .join(TrackReference, TrackReference.id == PlaylistItem.track_id)
        .join(owners, owners.c.id == PlaylistItem.playlist_id)
        .where(TRACK_ID.in_(seeds))
        .subquery()
    )
    pair_rows = (
        await session.execute(
            select(
                TRACK_ID.label("track_id"),
                func.count().label("co"),
                func.count(func.distinct(owners.c.user_id)).label("users"),
                func.min(seed_rows.c.title).label("seed_title"),
            )
            .select_from(PlaylistItem)
            .join(TrackReference, TrackReference.id == PlaylistItem.track_id)
            .join(owners, owners.c.id == PlaylistItem.playlist_id)
            .join(seed_rows, seed_rows.c.playlist_id == PlaylistItem.playlist_id)
            .where(TRACK_ID.not_in(seeds))
            .group_by(TRACK_ID)
        )
    ).all()
    candidates = [row for row in pair_rows if int(row.users) >= MIN_DISTINCT_USERS]
    if not candidates:
        return []
    ids = [str(row.track_id) for row in candidates]
    popularity = dict(
        (
            await session.execute(
                select(TRACK_ID, func.count())
                .select_from(PlaylistItem)
                .join(TrackReference, TrackReference.id == PlaylistItem.track_id)
                .join(owners, owners.c.id == PlaylistItem.playlist_id)
                .where(TRACK_ID.in_(ids + seeds))
                .group_by(TRACK_ID)
            )
        ).all()
    )
    seed_count = sum(popularity.get(s, 0) for s in seeds) or 1
    scored = [
        CoListened(
            track_id=str(row.track_id),
            score=round(
                int(row.co) / math.sqrt(max(popularity.get(row.track_id, 1), 1) * seed_count), 4
            ),
            seed_title=str(row.seed_title),
            listeners=int(row.users),
        )
        for row in candidates
    ]
    scored.sort(key=lambda c: c.score, reverse=True)
    return scored[:limit]


async def listener_seeds(session: AsyncSession, user_id: uuid.UUID, limit: int = 20) -> list[str]:
    """Recent positive signals: liked/saved feedback plus songs in recent playlists."""
    liked = (
        (
            await session.execute(
                select(RecommendationFeedback.track_id)
                .where(
                    RecommendationFeedback.user_id == user_id,
                    RecommendationFeedback.rating.in_(("like", "save")),
                )
                .order_by(RecommendationFeedback.updated_at.desc())
                .limit(limit)
            )
        )
        .scalars()
        .all()
    )
    in_playlists = (
        (
            await session.execute(
                select(TRACK_ID)
                .join(PlaylistItem, PlaylistItem.track_id == TrackReference.id)
                .join(Playlist, Playlist.id == PlaylistItem.playlist_id)
                .where(Playlist.user_id == user_id)
                .order_by(PlaylistItem.created_at.desc())
                .limit(limit)
            )
        )
        .scalars()
        .all()
    )
    return list(dict.fromkeys([*liked, *in_playlists]))[:limit]


async def arm_posteriors(
    session: AsyncSession, user_id: uuid.UUID | None
) -> dict[str, ArmPosterior]:
    scopes = ["global"] + ([str(user_id)] if user_id else [])
    rows = (
        (await session.execute(select(BanditArm).where(BanditArm.scope.in_(scopes))))
        .scalars()
        .all()
    )
    by_scope: dict[tuple[str, str], tuple[float, float]] = {
        (r.scope, r.arm): (r.successes, r.failures) for r in rows
    }
    return {
        arm: combine(
            by_scope.get((str(user_id), arm)) if user_id else None, by_scope.get(("global", arm))
        )
        for arm in ARMS
    }


async def record_bandit_reward(
    session: AsyncSession,
    user_id: uuid.UUID,
    session_id: uuid.UUID | None,
    track_id: str,
    rating: str,
) -> str | None:
    """Credit feedback to the source that produced the recommendation. Returns the arm."""
    outcome = reward(rating)
    if outcome is None or session_id is None:
        return None
    rec = await session.get(RecommendationSession, session_id)
    if rec is None or rec.user_id != user_id:
        return None
    detail = (rec.result_details or {}).get(track_id)
    arm = detail.get("source") if isinstance(detail, dict) else None
    if arm not in ARMS:
        return None
    for scope in ("global", str(user_id)):
        row = (
            await session.execute(
                select(BanditArm).where(BanditArm.scope == scope, BanditArm.arm == arm)
            )
        ).scalar_one_or_none()
        if row is None:
            row = BanditArm(scope=scope, arm=arm, successes=1.0, failures=1.0)
            session.add(row)
        if outcome:
            row.successes += 1.0
        else:
            row.failures += 1.0
    await session.flush()
    return str(arm)


async def load_ranker(session: AsyncSession) -> RankerModel:
    row = (
        await session.execute(select(ModelArtifact).where(ModelArtifact.name == "ranker"))
    ).scalar_one_or_none()
    if row is None:
        return RankerModel()
    return RankerModel.from_payload(row.payload, row.trained_examples)


async def save_ranker(session: AsyncSession, model: RankerModel) -> None:
    row = (
        await session.execute(select(ModelArtifact).where(ModelArtifact.name == "ranker"))
    ).scalar_one_or_none()
    if row is None:
        row = ModelArtifact(name="ranker", version=0, payload={})
        session.add(row)
    row.version += 1
    row.payload = model.to_payload()
    row.trained_examples = model.trained_examples
    await session.flush()


async def training_examples(
    session: AsyncSession, limit: int = 50_000
) -> list[tuple[dict[str, float], int]]:
    """Joins feedback with the features logged when the item was recommended."""
    rows = (
        await session.execute(
            select(
                RecommendationFeedback.track_id,
                RecommendationFeedback.rating,
                RecommendationSession.result_details,
            )
            .join(
                RecommendationSession, RecommendationSession.id == RecommendationFeedback.session_id
            )
            .limit(limit)
        )
    ).all()
    examples: list[tuple[dict[str, float], int]] = []
    for track_id, rating, details in rows:
        outcome = reward(rating)
        detail = (details or {}).get(track_id)
        if outcome is None or not isinstance(detail, dict):
            continue
        features = detail.get("features")
        if isinstance(features, dict):
            examples.append(
                (
                    {k: float(v) for k, v in features.items() if isinstance(v, int | float)},
                    1 if outcome else 0,
                )
            )
    return examples
