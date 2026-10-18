"""Pydantic v2 request/response schemas for the public API."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.services.youtube.ids import is_valid_playlist_id, is_valid_video_id

SearchKind = Literal["song", "artist", "remix", "live"]
Discovery = Literal["familiar", "balanced", "discovery"]
Rating = Literal["like", "dislike", "skip", "save"]
MOODS = ("calm", "happy", "focused", "energetic", "romantic", "sleep", "workout", "travel")
Mood = Literal["calm", "happy", "focused", "energetic", "romantic", "sleep", "workout", "travel"]


class APIModel(BaseModel):
    model_config = ConfigDict(from_attributes=True, populate_by_name=True)


# --- Tracks ---------------------------------------------------------------------------


class Thumbnail(APIModel):
    url: str
    width: int | None = None
    height: int | None = None


class Attribution(APIModel):
    """Source attribution that clients must display next to provider metadata."""

    provider: Literal["youtube", "demo"]
    label: str
    url: str | None = None


class Track(APIModel):
    video_id: str
    title: str
    channel_title: str
    channel_id: str | None = None
    description: str | None = None
    thumbnails: dict[str, Thumbnail] = Field(default_factory=dict)
    duration_seconds: int | None = None
    published_at: datetime | None = None
    view_count: int | None = None
    is_live: bool = False
    watch_url: str
    attribution: Attribution

    @property
    def best_thumbnail(self) -> str | None:
        for key in ("maxres", "high", "medium", "standard", "default"):
            if key in self.thumbnails:
                return self.thumbnails[key].url
        return None


class SearchResponse(APIModel):
    query: str
    kind: SearchKind
    items: list[Track]
    next_page_token: str | None = None
    prev_page_token: str | None = None
    total_results_estimate: int | None = None
    provider: Literal["youtube", "demo"]
    cached: bool = False


class TrendingResponse(APIModel):
    items: list[Track]
    next_page_token: str | None = None
    prev_page_token: str | None = None
    provider: Literal["youtube", "demo"]
    cached: bool = False
    source: str = "YouTube most popular music chart"


class SuggestionsResponse(APIModel):
    query: str
    suggestions: list[str]


# --- Auth & account -------------------------------------------------------------------


class RegisterRequest(APIModel):
    display_name: str | None = Field(default=None, max_length=80)


class TokenResponse(APIModel):
    access_token: str
    token_type: Literal["bearer"] = "bearer"
    expires_at: datetime
    user_id: uuid.UUID


# --- Playlists ------------------------------------------------------------------------


class PlaylistItemOut(APIModel):
    id: uuid.UUID
    position: int
    note: str | None = None
    video_id: str
    title: str
    channel_title: str
    thumbnail_url: str | None = None
    duration_seconds: int | None = None
    is_available: bool = True
    watch_url: str
    added_at: datetime


class PlaylistSummary(APIModel):
    id: uuid.UUID
    name: str
    description: str | None = None
    mood: str | None = None
    is_ai_generated: bool
    youtube_playlist_id: str | None = None
    youtube_playlist_url: str | None = None
    item_count: int
    total_duration_seconds: int
    artwork_url: str | None = None
    created_at: datetime
    updated_at: datetime


class PlaylistDetail(PlaylistSummary):
    items: list[PlaylistItemOut]


class PlaylistPage(APIModel):
    items: list[PlaylistSummary]
    total: int
    limit: int
    offset: int


def _clean_name(value: str) -> str:
    cleaned = " ".join(value.split())
    if not cleaned:
        raise ValueError("must not be blank")
    return cleaned


def _check_playlist_id(value: str | None) -> str | None:
    if value is None or value == "":
        return None
    if not is_valid_playlist_id(value):
        raise ValueError("not a valid YouTube playlist id")
    return value


class PlaylistCreate(APIModel):
    name: str = Field(min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=2000)
    mood: Mood | None = None
    youtube_playlist_id: str | None = None
    is_ai_generated: bool = False
    recommendation_session_id: uuid.UUID | None = None
    video_ids: list[str] = Field(default_factory=list, max_length=200)

    @field_validator("name")
    @classmethod
    def _name(cls, value: str) -> str:
        return _clean_name(value)

    @field_validator("youtube_playlist_id")
    @classmethod
    def _youtube_playlist(cls, value: str | None) -> str | None:
        return _check_playlist_id(value)

    @field_validator("video_ids")
    @classmethod
    def _videos(cls, values: list[str]) -> list[str]:
        for value in values:
            if not is_valid_video_id(value):
                raise ValueError(f"invalid YouTube video id: {value!r}")
        return values


class PlaylistUpdate(APIModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=2000)
    mood: Mood | None = None
    youtube_playlist_id: str | None = None

    @field_validator("name")
    @classmethod
    def _name(cls, value: str | None) -> str | None:
        return None if value is None else _clean_name(value)

    @field_validator("youtube_playlist_id")
    @classmethod
    def _youtube_playlist(cls, value: str | None) -> str | None:
        return _check_playlist_id(value)


class PlaylistItemCreate(APIModel):
    video_id: str
    position: int | None = Field(default=None, ge=0)
    note: str | None = Field(default=None, max_length=300)

    @field_validator("video_id")
    @classmethod
    def _video(cls, value: str) -> str:
        if not is_valid_video_id(value):
            raise ValueError("invalid YouTube video id")
        return value


class PlaylistReorder(APIModel):
    item_ids: list[uuid.UUID] = Field(min_length=1, max_length=500)


# --- Preferences & taste -------------------------------------------------------------


class ArtistPreferenceIn(APIModel):
    name: str = Field(min_length=1, max_length=200)
    youtube_channel_id: str | None = Field(default=None, max_length=64)


class PreferencesBody(APIModel):
    personalization_enabled: bool = False
    store_ai_conversations: bool = False
    record_search_history: bool = True
    languages: list[str] = Field(default_factory=list, max_length=12)
    genres: list[str] = Field(default_factory=list, max_length=20)
    moods: list[Mood] = Field(default_factory=list, max_length=8)
    discovery_preference: Discovery = "balanced"
    favorite_artists: list[ArtistPreferenceIn] = Field(default_factory=list, max_length=50)
    excluded_artists: list[ArtistPreferenceIn] = Field(default_factory=list, max_length=100)
    onboarding_completed: bool = False

    @field_validator("languages", "genres")
    @classmethod
    def _tags(cls, values: list[str]) -> list[str]:
        seen: list[str] = []
        for value in values:
            cleaned = " ".join(value.split())[:40]
            if cleaned and cleaned.lower() not in {s.lower() for s in seen}:
                seen.append(cleaned)
        return seen


class PreferencesOut(PreferencesBody):
    personalization_consent_at: datetime | None = None
    updated_at: datetime | None = None


class TasteSignal(APIModel):
    label: str
    weight: float
    evidence: str


class TasteProfile(APIModel):
    """Inferred from MUSE activity only (saves, playlists, searches, feedback).

    This is not playback history: MUSE cannot see what was played in Brave.
    """

    personalization_enabled: bool
    basis: str = (
        "Inferred from your activity inside MUSE: saved songs, playlists, searches and "
        "feedback. MUSE cannot see what you play in Brave or on YouTube."
    )
    top_artists: list[TasteSignal]
    top_terms: list[TasteSignal]
    declared_languages: list[str]
    declared_genres: list[str]
    excluded_artists: list[str]
    activity_counts: dict[str, int]


# --- AI ---------------------------------------------------------------------------------


class AIPlaylistRequest(APIModel):
    description: str = Field(min_length=3, max_length=500)
    mood: Mood | None = None
    genres: list[str] = Field(default_factory=list, max_length=5)
    language: str | None = Field(default=None, max_length=40)
    energy: int | None = Field(default=None, ge=0, le=100)
    duration_minutes: int = Field(default=60, ge=10, le=300)
    discovery: Discovery = "balanced"
    exclude_video_ids: list[str] = Field(default_factory=list, max_length=200)


class ChatMessage(APIModel):
    role: Literal["user", "assistant"]
    content: str = Field(min_length=1, max_length=2000)


class AIChatRequest(APIModel):
    message: str = Field(min_length=1, max_length=1000)
    conversation_id: uuid.UUID | None = None
    history: list[ChatMessage] = Field(default_factory=list, max_length=20)


class RecommendedTrack(APIModel):
    track: Track
    score: float
    reasons: list[str]
    matched_query: str


class PlaylistDraft(APIModel):
    session_id: uuid.UUID | None
    title: str
    explanation: str
    intent: dict[str, object]
    planner: Literal["llm", "heuristic"]
    queries: list[str]
    tracks: list[RecommendedTrack]
    total_duration_seconds: int
    target_duration_seconds: int
    provider: Literal["youtube", "demo"]
    warnings: list[str] = Field(default_factory=list)


class AIChatResponse(APIModel):
    conversation_id: uuid.UUID | None
    reply: str
    draft: PlaylistDraft | None = None
    stored: bool


class FeedbackRequest(APIModel):
    video_id: str
    rating: Rating
    session_id: uuid.UUID | None = None
    channel_title: str | None = Field(default=None, max_length=200)

    @field_validator("video_id")
    @classmethod
    def _video(cls, value: str) -> str:
        if not is_valid_video_id(value):
            raise ValueError("invalid YouTube video id")
        return value


class FeedbackResponse(APIModel):
    id: uuid.UUID
    video_id: str
    rating: Rating
    recorded: bool


class SearchHistoryEntry(APIModel):
    id: uuid.UUID
    query: str
    kind: str
    result_count: int
    created_at: datetime
