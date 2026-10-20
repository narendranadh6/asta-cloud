"""User, preference, history, feedback and conversation persistence."""

from __future__ import annotations

import uuid
from collections import Counter
from datetime import UTC, datetime

from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import (
    AIConversation,
    ArtistPreference,
    Playlist,
    PlaylistItem,
    RecommendationFeedback,
    RecommendationSession,
    SearchHistory,
    TrackReference,
    User,
    UserPreferences,
)
from app.schemas import (
    ArtistPreferenceIn,
    PreferencesBody,
    PreferencesOut,
    TasteProfile,
    TasteSignal,
)
from app.services.ai.heuristic import PreferenceHints
from app.services.recommendations.pipeline import FeedbackSignals, normalize_name

SEARCH_HISTORY_LIMIT = 200


async def create_user(session: AsyncSession, display_name: str | None) -> User:
    user = User(display_name=display_name, last_seen_at=datetime.now(UTC))
    session.add(user)
    await session.flush()
    session.add(UserPreferences(user_id=user.id))
    await session.flush()
    return user


async def get_user(session: AsyncSession, user_id: uuid.UUID) -> User | None:
    return await session.get(User, user_id)


async def delete_user(session: AsyncSession, user_id: uuid.UUID) -> None:
    await session.execute(delete(User).where(User.id == user_id))


async def get_preferences(session: AsyncSession, user_id: uuid.UUID) -> UserPreferences:
    prefs = (
        await session.execute(select(UserPreferences).where(UserPreferences.user_id == user_id))
    ).scalar_one_or_none()
    if prefs is None:
        prefs = UserPreferences(user_id=user_id)
        session.add(prefs)
        await session.flush()
    return prefs


async def list_artist_preferences(
    session: AsyncSession, user_id: uuid.UUID
) -> list[ArtistPreference]:
    result = await session.execute(
        select(ArtistPreference)
        .where(ArtistPreference.user_id == user_id)
        .order_by(ArtistPreference.created_at)
    )
    return list(result.scalars())


async def preferences_out(session: AsyncSession, user_id: uuid.UUID) -> PreferencesOut:
    prefs = await get_preferences(session, user_id)
    artists = await list_artist_preferences(session, user_id)

    def _artists(stance: str) -> list[ArtistPreferenceIn]:
        return [
            ArtistPreferenceIn(name=a.name, youtube_channel_id=a.youtube_channel_id)
            for a in artists
            if a.stance == stance
        ]

    return PreferencesOut(
        personalization_enabled=prefs.personalization_enabled,
        store_ai_conversations=prefs.store_ai_conversations,
        record_search_history=prefs.record_search_history,
        languages=list(prefs.languages or []),
        genres=list(prefs.genres or []),
        moods=list(prefs.moods or []),  # type: ignore[arg-type]
        discovery_preference=prefs.discovery_preference,  # type: ignore[arg-type]
        favorite_artists=_artists("favorite"),
        excluded_artists=_artists("excluded"),
        onboarding_completed=prefs.onboarding_completed,
        personalization_consent_at=prefs.personalization_consent_at,
        updated_at=prefs.updated_at,
    )


async def replace_preferences(
    session: AsyncSession, user_id: uuid.UUID, body: PreferencesBody
) -> PreferencesOut:
    prefs = await get_preferences(session, user_id)
    if body.personalization_enabled and not prefs.personalization_enabled:
        prefs.personalization_consent_at = datetime.now(UTC)
    if not body.personalization_enabled:
        prefs.personalization_consent_at = None
    prefs.personalization_enabled = body.personalization_enabled
    # Storing AI conversations requires personalization consent.
    prefs.store_ai_conversations = body.store_ai_conversations and body.personalization_enabled
    prefs.record_search_history = body.record_search_history
    prefs.languages = body.languages
    prefs.genres = body.genres
    prefs.moods = list(body.moods)
    prefs.discovery_preference = body.discovery_preference
    prefs.onboarding_completed = body.onboarding_completed
    prefs.updated_at = datetime.now(UTC)

    await session.execute(delete(ArtistPreference).where(ArtistPreference.user_id == user_id))
    seen: set[str] = set()
    # Exclusions win if the same artist appears in both lists.
    for stance, artists in (("excluded", body.excluded_artists),
                            ("favorite", body.favorite_artists)):
        for artist in artists:
            normalized = normalize_name(artist.name)
            if not normalized or normalized in seen:
                continue
            seen.add(normalized)
            session.add(
                ArtistPreference(
                    user_id=user_id,
                    name=" ".join(artist.name.split()),
                    normalized_name=normalized,
                    youtube_channel_id=artist.youtube_channel_id,
                    stance=stance,
                )
            )
    if not body.store_ai_conversations or not body.personalization_enabled:
        await session.execute(delete(AIConversation).where(AIConversation.user_id == user_id))
    if not body.record_search_history:
        await clear_search_history(session, user_id)
    await session.flush()
    return await preferences_out(session, user_id)


async def reset_taste_memory(session: AsyncSession, user_id: uuid.UUID) -> None:
    """Forget inferred taste signals. Saved playlists and explicit settings are kept."""
    await session.execute(
        delete(RecommendationFeedback).where(RecommendationFeedback.user_id == user_id)
    )
    await session.execute(
        delete(RecommendationSession).where(RecommendationSession.user_id == user_id)
    )
    await clear_search_history(session, user_id)
    await session.execute(delete(AIConversation).where(AIConversation.user_id == user_id))


async def preference_hints(session: AsyncSession, user_id: uuid.UUID) -> PreferenceHints:
    """Hints passed to the planner. Without consent only exclusions are honoured."""
    prefs = await get_preferences(session, user_id)
    artists = await list_artist_preferences(session, user_id)
    excluded = [a.name for a in artists if a.stance == "excluded"]
    if not prefs.personalization_enabled:
        return PreferenceHints(excluded_artists=excluded)
    return PreferenceHints(
        languages=list(prefs.languages or []),
        genres=list(prefs.genres or []),
        moods=list(prefs.moods or []),
        favorite_artists=[a.name for a in artists if a.stance == "favorite"],
        excluded_artists=excluded,
        discovery=prefs.discovery_preference,
    )


# --- Search history ---------------------------------------------------------------------


async def record_search(
    session: AsyncSession, user_id: uuid.UUID, query: str, kind: str, result_count: int
) -> None:
    prefs = await get_preferences(session, user_id)
    if not prefs.record_search_history:
        return
    session.add(
        SearchHistory(user_id=user_id, query=query[:200], kind=kind, result_count=result_count)
    )
    await session.flush()
    # Keep history bounded.
    stale = (
        select(SearchHistory.id)
        .where(SearchHistory.user_id == user_id)
        .order_by(SearchHistory.created_at.desc())
        .offset(SEARCH_HISTORY_LIMIT)
    )
    stale_ids = list((await session.execute(stale)).scalars())
    if stale_ids:
        await session.execute(delete(SearchHistory).where(SearchHistory.id.in_(stale_ids)))


async def list_search_history(
    session: AsyncSession, user_id: uuid.UUID, limit: int = 50
) -> list[SearchHistory]:
    result = await session.execute(
        select(SearchHistory)
        .where(SearchHistory.user_id == user_id)
        .order_by(SearchHistory.created_at.desc())
        .limit(limit)
    )
    return list(result.scalars())


async def clear_search_history(session: AsyncSession, user_id: uuid.UUID) -> None:
    await session.execute(delete(SearchHistory).where(SearchHistory.user_id == user_id))


async def history_suggestions(
    session: AsyncSession, user_id: uuid.UUID, prefix: str, limit: int
) -> list[str]:
    pattern = prefix.lower().replace("%", "").replace("_", "") + "%"
    result = await session.execute(
        select(SearchHistory.query, func.max(SearchHistory.created_at).label("last"))
        .where(SearchHistory.user_id == user_id, func.lower(SearchHistory.query).like(pattern))
        .group_by(SearchHistory.query)
        .order_by(func.max(SearchHistory.created_at).desc())
        .limit(limit)
    )
    return [row[0] for row in result]


# --- Feedback ---------------------------------------------------------------------------


async def upsert_feedback(
    session: AsyncSession,
    user_id: uuid.UUID,
    video_id: str,
    rating: str,
    session_id: uuid.UUID | None,
    channel_title: str | None,
) -> RecommendationFeedback:
    if session_id is not None:
        owned = await session.get(RecommendationSession, session_id)
        if owned is None or owned.user_id != user_id:
            session_id = None
    existing = (
        await session.execute(
            select(RecommendationFeedback).where(
                RecommendationFeedback.user_id == user_id,
                RecommendationFeedback.video_id == video_id,
            )
        )
    ).scalar_one_or_none()
    if existing is None:
        existing = RecommendationFeedback(user_id=user_id, video_id=video_id, rating=rating)
        session.add(existing)
    existing.rating = rating
    existing.session_id = session_id
    existing.channel_title = channel_title
    existing.updated_at = datetime.now(UTC)
    await session.flush()
    return existing


async def feedback_signals(session: AsyncSession, user_id: uuid.UUID) -> FeedbackSignals:
    rows = (
        await session.execute(
            select(RecommendationFeedback).where(RecommendationFeedback.user_id == user_id)
        )
    ).scalars()
    signals = FeedbackSignals()
    for row in rows:
        channel = normalize_name(row.channel_title or "")
        if row.rating in ("like", "save"):
            signals.liked_video_ids.add(row.video_id)
            if channel:
                signals.liked_channels.add(channel)
        elif row.rating == "dislike":
            signals.disliked_video_ids.add(row.video_id)
    return signals


# --- Taste profile ----------------------------------------------------------------------


async def taste_profile(session: AsyncSession, user_id: uuid.UUID) -> TasteProfile:
    prefs = await get_preferences(session, user_id)
    artists = await list_artist_preferences(session, user_id)
    excluded = [a.name for a in artists if a.stance == "excluded"]

    track_rows = (
        await session.execute(
            select(TrackReference.channel_title)
            .join(PlaylistItem, PlaylistItem.track_id == TrackReference.id)
            .join(Playlist, Playlist.id == PlaylistItem.playlist_id)
            .where(Playlist.user_id == user_id)
        )
    ).scalars()
    channel_counts: Counter[str] = Counter(track_rows)
    feedback = list(
        (
            await session.execute(
                select(RecommendationFeedback).where(RecommendationFeedback.user_id == user_id)
            )
        ).scalars()
    )
    for row in feedback:
        if row.channel_title and row.rating in ("like", "save"):
            channel_counts[row.channel_title] += 2
        elif row.channel_title and row.rating == "dislike":
            channel_counts[row.channel_title] -= 2
    for fav in (a.name for a in artists if a.stance == "favorite"):
        channel_counts[fav] += 3

    searches = await list_search_history(session, user_id, limit=SEARCH_HISTORY_LIMIT)
    term_counts: Counter[str] = Counter()
    for entry in searches:
        for word in normalize_name(entry.query).split():
            if len(word) > 2:
                term_counts[word] += 1

    playlist_count = (
        await session.execute(select(func.count(Playlist.id)).where(Playlist.user_id == user_id))
    ).scalar_one()
    excluded_norm = {normalize_name(e) for e in excluded}
    top_artists = [
        TasteSignal(label=name, weight=float(count), evidence="saves, playlists and feedback")
        for name, count in channel_counts.most_common(15)
        if count > 0 and normalize_name(name) not in excluded_norm
    ][:10]
    top_terms = [
        TasteSignal(label=term, weight=float(count), evidence=f"searched {count}×")
        for term, count in term_counts.most_common(10)
    ]
    return TasteProfile(
        personalization_enabled=prefs.personalization_enabled,
        top_artists=top_artists,
        top_terms=top_terms,
        declared_languages=list(prefs.languages or []),
        declared_genres=list(prefs.genres or []),
        excluded_artists=excluded,
        activity_counts={
            "playlists": int(playlist_count),
            "searches": len(searches),
            "feedback": len(feedback),
        },
    )


# --- AI conversations -------------------------------------------------------------------


async def append_conversation(
    session: AsyncSession,
    user_id: uuid.UUID,
    conversation_id: uuid.UUID | None,
    user_message: str,
    assistant_message: str,
) -> AIConversation:
    conversation = None
    if conversation_id is not None:
        conversation = await session.get(AIConversation, conversation_id)
        if conversation is not None and conversation.user_id != user_id:
            conversation = None
    if conversation is None:
        conversation = AIConversation(
            user_id=user_id, title=" ".join(user_message.split())[:120] or "AI DJ", messages=[]
        )
        session.add(conversation)
    now = datetime.now(UTC).isoformat()
    messages: list[dict[str, object]] = [
        *list(conversation.messages or []),
        {"role": "user", "content": user_message, "at": now},
        {"role": "assistant", "content": assistant_message, "at": now},
    ]
    conversation.messages = messages[-100:]
    conversation.updated_at = datetime.now(UTC)
    await session.flush()
    return conversation
