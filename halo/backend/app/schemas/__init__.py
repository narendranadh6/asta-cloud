"""Pydantic v2 request/response schemas for the public API."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.services.catalog.ids import TrackSource, is_valid_track_id
from app.services.music_sources.listenbrainz import PopularRecording
from app.services.music_sources.musicbrainz import ArtistInfo, CanonicalRecording

SearchKind = Literal["song", "artist"]
Discovery = Literal["familiar", "balanced", "discovery"]
Rating = Literal["like", "dislike", "skip", "save"]
MOODS = ("calm", "happy", "focused", "energetic", "romantic", "sleep", "workout", "travel")
Mood = Literal["calm", "happy", "focused", "energetic", "romantic", "sleep", "workout", "travel"]


class APIModel(BaseModel):
    model_config = ConfigDict(from_attributes=True, populate_by_name=True)


# --- Tracks ---------------------------------------------------------------------------


class Attribution(APIModel):
    """Where a track comes from. Clients must show it next to the track."""

    provider: TrackSource
    label: str
    url: str | None = None


class TrackLicense(APIModel):
    """Creative Commons licence for Jamendo tracks (attribution is required)."""

    name: str
    url: str | None = None


class Track(APIModel):
    """A playable song. Audio streams directly from the source at ``stream_url``."""

    id: str  # "<source>:<source id>", e.g. "audius:D7KyD"
    source: TrackSource
    source_id: str
    title: str
    artist: str
    artist_id: str | None = None  # id at the source; the artist page is "<source>:<artist_id>"
    album: str | None = None
    album_id: str | None = None  # id at the source, when the source groups tracks in albums
    artwork_url: str | None = None
    # Sharper copy for the full-screen player, when the source has one.
    artwork_url_large: str | None = None
    duration_seconds: int | None = None
    genre: str | None = None
    mood: str | None = None
    release_date: str | None = None
    play_count: int | None = None
    stream_url: str | None = None
    is_preview: bool = False  # 30-second preview (iTunes), not the full song
    license: TrackLicense | None = None
    external_url: str | None = None  # the track's page at the source
    attribution: Attribution


class AlbumSummary(APIModel):
    """An album (or an artist's release collection) with a Halo id "<source>:<id>"."""

    id: str
    source: TrackSource
    title: str
    artist: str
    artist_id: str | None = None  # Halo artist id, "<source>:<id>"
    artwork_url: str | None = None
    release_date: str | None = None
    track_count: int | None = None
    external_url: str | None = None


class AlbumPage(AlbumSummary):
    artwork_url_large: str | None = None
    attribution: Attribution
    tracks: list[Track] = Field(default_factory=list)


class ArtistPage(APIModel):
    """An artist at one source: profile, most-played songs and albums."""

    id: str  # "<source>:<id>"
    source: TrackSource
    name: str
    handle: str | None = None
    artwork_url: str | None = None
    cover_url: str | None = None
    bio: str | None = None
    follower_count: int | None = None
    external_url: str | None = None
    attribution: Attribution
    top_tracks: list[Track] = Field(default_factory=list)
    albums: list[AlbumSummary] = Field(default_factory=list)


class SearchResponse(APIModel):
    query: str
    kind: SearchKind
    items: list[Track]
    next_page_token: str | None = None
    prev_page_token: str | None = None
    total_results_estimate: int | None = None
    sources: list[str] = Field(default_factory=list)
    cached: bool = False


class TrendingResponse(APIModel):
    items: list[Track]
    next_page_token: str | None = None
    prev_page_token: str | None = None
    sources: list[str] = Field(default_factory=list)
    cached: bool = False
    source: str = "Trending on Audius and Jamendo this week"


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
    track_id: str
    title: str
    artist: str
    album: str | None = None
    artwork_url: str | None = None
    duration_seconds: int | None = None
    stream_url: str | None = None
    is_preview: bool = False
    is_available: bool = True
    added_at: datetime


class PlaylistSummary(APIModel):
    id: uuid.UUID
    name: str
    description: str | None = None
    mood: str | None = None
    is_ai_generated: bool
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


def _check_track_ids(values: list[str]) -> list[str]:
    for value in values:
        if not is_valid_track_id(value):
            raise ValueError(f"invalid track id: {value!r}")
    return values


class PlaylistCreate(APIModel):
    name: str = Field(min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=2000)
    mood: Mood | None = None
    is_ai_generated: bool = False
    recommendation_session_id: uuid.UUID | None = None
    track_ids: list[str] = Field(default_factory=list, max_length=200)

    @field_validator("name")
    @classmethod
    def _name(cls, value: str) -> str:
        return _clean_name(value)

    @field_validator("track_ids")
    @classmethod
    def _tracks(cls, values: list[str]) -> list[str]:
        return _check_track_ids(values)


class PlaylistUpdate(APIModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=2000)
    mood: Mood | None = None

    @field_validator("name")
    @classmethod
    def _name(cls, value: str | None) -> str | None:
        return None if value is None else _clean_name(value)


class PlaylistItemCreate(APIModel):
    track_id: str
    position: int | None = Field(default=None, ge=0)
    note: str | None = Field(default=None, max_length=300)

    @field_validator("track_id")
    @classmethod
    def _track(cls, value: str) -> str:
        return _check_track_ids([value])[0]


class PlaylistReorder(APIModel):
    item_ids: list[uuid.UUID] = Field(min_length=1, max_length=500)


# --- Preferences & taste -------------------------------------------------------------


class ArtistPreferenceIn(APIModel):
    name: str = Field(min_length=1, max_length=200)


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
    """Inferred from Halo activity only (saves, playlists, searches, feedback)."""

    personalization_enabled: bool
    basis: str = (
        "Inferred from your activity inside Halo: saved songs, playlists, searches and feedback."
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
    exclude_track_ids: list[str] = Field(default_factory=list, max_length=200)


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
    source: Literal["search", "similar_artist", "co_listen", "listenbrainz"] = "search"
    explore: bool = False


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
    sources: list[str] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)


class AIChatResponse(APIModel):
    conversation_id: uuid.UUID | None
    reply: str
    draft: PlaylistDraft | None = None
    stored: bool


class UpNextResponse(APIModel):
    """Songs to play next after the seed track."""

    seed_track_id: str
    tracks: list[RecommendedTrack]


class TrackMetadataResponse(APIModel):
    """Canonical facts about a song from MusicBrainz (CC0 data)."""

    track_id: str
    parsed_artist: str
    parsed_title: str
    matched: bool
    recording: CanonicalRecording | None = None
    artist: ArtistInfo | None = None
    source: str = "MusicBrainz"


class ArtistProfileResponse(APIModel):
    artist: ArtistInfo | None
    popular_recordings: list[PopularRecording] = Field(default_factory=list)
    sources: list[str] = Field(default_factory=list)


class FeedbackRequest(APIModel):
    track_id: str
    rating: Rating
    session_id: uuid.UUID | None = None
    artist: str | None = Field(default=None, max_length=200)

    @field_validator("track_id")
    @classmethod
    def _track(cls, value: str) -> str:
        return _check_track_ids([value])[0]


class FeedbackResponse(APIModel):
    id: uuid.UUID
    track_id: str
    rating: Rating
    recorded: bool


class SearchHistoryEntry(APIModel):
    id: uuid.UUID
    query: str
    kind: str
    result_count: int
    created_at: datetime


# --- Home feed --------------------------------------------------------------------------

HomeItemKind = Literal["track", "recording", "release", "artist", "query", "mood"]
HomeLayout = Literal["rail", "feature_rail", "artist_rail", "rows", "tiles", "local"]


class HomeItem(APIModel):
    """One card in a Home section. What happens on tap depends on `kind`:
    track → song details (`track`), mood → mood hub (`id`), everything else → search (`query`)."""

    kind: HomeItemKind
    id: str
    title: str
    subtitle: str | None = None
    artwork_url: str | None = None
    query: str | None = None
    badge: str | None = None
    track: Track | None = None


class HomeSection(APIModel):
    id: str
    type: str
    title: str
    eyebrow: str | None = None  # why this section is here
    layout: HomeLayout
    items: list[HomeItem] = Field(default_factory=list)
    source: str | None = None  # data attribution, e.g. "ListenBrainz"
    see_all_query: str | None = None
    score: float


class HomeFeed(APIModel):
    sections: list[HomeSection]
    personalized: bool
    generated_at: datetime
