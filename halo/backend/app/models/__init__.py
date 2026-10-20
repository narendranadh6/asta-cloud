"""Relational models. Tracks are stored only as references (source ids + minimal metadata)."""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    Uuid,
    false,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, JSONType, TimestampMixin, UUIDPrimaryKeyMixin


class User(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "users"

    display_name: Mapped[str | None] = mapped_column(String(80))
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    preferences: Mapped[UserPreferences | None] = relationship(
        back_populates="user", cascade="all, delete-orphan", uselist=False
    )
    artist_preferences: Mapped[list[ArtistPreference]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    playlists: Mapped[list[Playlist]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )


class UserPreferences(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "user_preferences"

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False
    )
    personalization_enabled: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    personalization_consent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    store_ai_conversations: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    record_search_history: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    languages: Mapped[list[str]] = mapped_column(JSONType, default=list, nullable=False)
    genres: Mapped[list[str]] = mapped_column(JSONType, default=list, nullable=False)
    moods: Mapped[list[str]] = mapped_column(JSONType, default=list, nullable=False)
    discovery_preference: Mapped[str] = mapped_column(String(16), default="balanced")
    onboarding_completed: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    user: Mapped[User] = relationship(back_populates="preferences")

    __table_args__ = (
        CheckConstraint(
            "discovery_preference IN ('familiar', 'balanced', 'discovery')",
            name="discovery_preference",
        ),
    )


class ArtistPreference(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """An artist the user marked as favorite or excluded (explicit, user-set)."""

    __tablename__ = "artist_preferences"

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    normalized_name: Mapped[str] = mapped_column(String(200), nullable=False)
    stance: Mapped[str] = mapped_column(String(16), nullable=False)  # favorite | excluded

    user: Mapped[User] = relationship(back_populates="artist_preferences")

    __table_args__ = (
        UniqueConstraint("user_id", "normalized_name", name="uq_artist_pref_user_name"),
        CheckConstraint("stance IN ('favorite', 'excluded')", name="stance"),
        Index("ix_artist_preferences_user_stance", "user_id", "stance"),
    )


class TrackReference(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """A pointer to a track at its source (Audius, Jamendo, iTunes). Never holds audio.

    Metadata is refreshed from the source periodically (see app.tasks.refresh_metadata).
    """

    __tablename__ = "track_references"

    provider: Mapped[str] = mapped_column(String(16), nullable=False)  # source
    provider_id: Mapped[str] = mapped_column(String(64), nullable=False)  # id at the source
    title: Mapped[str] = mapped_column(String(300), nullable=False)
    artist: Mapped[str] = mapped_column(String(200), nullable=False)
    album: Mapped[str | None] = mapped_column(String(300))
    artwork_url: Mapped[str | None] = mapped_column(String(500))
    stream_url: Mapped[str | None] = mapped_column(String(1000))
    is_preview: Mapped[bool] = mapped_column(
        Boolean, default=False, server_default=false(), nullable=False
    )
    duration_seconds: Mapped[int | None] = mapped_column(Integer)
    metadata_fetched_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    is_available: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    __table_args__ = (
        UniqueConstraint("provider", "provider_id", name="uq_track_provider_id"),
        Index("ix_track_references_fetched", "metadata_fetched_at"),
    )


class Playlist(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "playlists"

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    mood: Mapped[str | None] = mapped_column(String(32))
    is_ai_generated: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    recommendation_session_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("recommendation_sessions.id", ondelete="SET NULL")
    )

    user: Mapped[User] = relationship(back_populates="playlists")
    items: Mapped[list[PlaylistItem]] = relationship(
        back_populates="playlist",
        cascade="all, delete-orphan",
        order_by="PlaylistItem.position",
    )

    __table_args__ = (Index("ix_playlists_user_updated", "user_id", "updated_at"),)


class PlaylistItem(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "playlist_items"

    playlist_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("playlists.id", ondelete="CASCADE"), nullable=False
    )
    track_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("track_references.id", ondelete="RESTRICT"), nullable=False
    )
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    note: Mapped[str | None] = mapped_column(String(300))

    playlist: Mapped[Playlist] = relationship(back_populates="items")
    track: Mapped[TrackReference] = relationship(lazy="joined")

    __table_args__ = (
        Index("ix_playlist_items_playlist_position", "playlist_id", "position"),
        Index("ix_playlist_items_track", "track_id"),
    )


class SearchHistory(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "search_history"

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    query: Mapped[str] = mapped_column(String(200), nullable=False)
    kind: Mapped[str] = mapped_column(String(16), nullable=False, default="song")
    result_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)

    __table_args__ = (Index("ix_search_history_user_created", "user_id", "created_at"),)


class RecommendationSession(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """One run of the recommendation pipeline. The raw prompt is kept only with consent."""

    __tablename__ = "recommendation_sessions"

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    source: Mapped[str] = mapped_column(String(16), nullable=False)  # chat | studio
    request_text: Mapped[str | None] = mapped_column(Text)
    intent: Mapped[dict[str, object]] = mapped_column(JSONType, default=dict, nullable=False)
    planner: Mapped[str] = mapped_column(String(16), nullable=False)  # llm | heuristic
    result_track_ids: Mapped[list[str]] = mapped_column(JSONType, default=list, nullable=False)
    # Per track: candidate source, ranking features and whether it was an exploration slot.
    # Used to credit feedback to the right bandit arm and as ranker training data.
    result_details: Mapped[dict[str, object]] = mapped_column(
        JSONType, default=dict, nullable=False
    )

    __table_args__ = (Index("ix_recommendation_sessions_user_created", "user_id", "created_at"),)


class RecommendationFeedback(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "recommendation_feedback"

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    session_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("recommendation_sessions.id", ondelete="SET NULL")
    )
    track_id: Mapped[str] = mapped_column(String(80), nullable=False)
    artist: Mapped[str | None] = mapped_column(String(200))
    rating: Mapped[str] = mapped_column(String(16), nullable=False)
    weight: Mapped[float] = mapped_column(Float, default=1.0, nullable=False)

    __table_args__ = (
        CheckConstraint("rating IN ('like', 'dislike', 'skip', 'save')", name="rating"),
        UniqueConstraint("user_id", "track_id", name="uq_feedback_user_track"),
        Index("ix_recommendation_feedback_user_rating", "user_id", "rating"),
    )


class BanditArm(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Beta-Bernoulli statistics for one candidate source ("arm").

    scope is "global" or a user id string. successes/failures start at the prior
    (1, 1) and are updated from recommendation feedback (Thompson sampling).
    """

    __tablename__ = "bandit_arms"

    scope: Mapped[str] = mapped_column(String(40), nullable=False)
    arm: Mapped[str] = mapped_column(String(32), nullable=False)
    successes: Mapped[float] = mapped_column(Float, default=1.0, nullable=False)
    failures: Mapped[float] = mapped_column(Float, default=1.0, nullable=False)

    __table_args__ = (UniqueConstraint("scope", "arm", name="uq_bandit_scope_arm"),)


class ModelArtifact(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Small learned models (e.g. ranker weights) stored as JSON."""

    __tablename__ = "model_artifacts"

    name: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)
    version: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    payload: Mapped[dict[str, object]] = mapped_column(JSONType, default=dict, nullable=False)
    trained_examples: Mapped[int] = mapped_column(Integer, default=0, nullable=False)


class AIConversation(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Stored only when the user opted in (UserPreferences.store_ai_conversations)."""

    __tablename__ = "ai_conversations"

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    title: Mapped[str] = mapped_column(String(120), nullable=False)
    messages: Mapped[list[dict[str, object]]] = mapped_column(
        JSONType, default=list, nullable=False
    )

    __table_args__ = (Index("ix_ai_conversations_user_updated", "user_id", "updated_at"),)


__all__ = [
    "AIConversation",
    "ArtistPreference",
    "BanditArm",
    "ModelArtifact",
    "Base",
    "Playlist",
    "PlaylistItem",
    "RecommendationFeedback",
    "RecommendationSession",
    "SearchHistory",
    "TrackReference",
    "User",
    "UserPreferences",
]
