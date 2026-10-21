"""Version 1 REST endpoints."""

from __future__ import annotations

import uuid
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Path, Query, Request, Response, status

from app.api.deps import (
    CatalogDep,
    CurrentUser,
    PipelineDep,
    PlannerDep,
    RadioDep,
    SessionDep,
    SettingsDep,
)
from app.core.errors import (
    AppError,
    NotFoundError,
    ServiceUnavailableError,
    UpstreamError,
)
from app.core.rate_limit import rate_limit
from app.core.security import create_access_token
from app.models import RecommendationSession
from app.repositories import playlists as playlist_repo
from app.repositories import recommendations as rec_repo
from app.repositories import users as user_repo
from app.schemas import (
    AIChatRequest,
    AIChatResponse,
    AIPlaylistRequest,
    AlbumPage,
    ArtistPage,
    ArtistProfileResponse,
    FeedbackRequest,
    FeedbackResponse,
    HomeFeed,
    PlaylistCreate,
    PlaylistDetail,
    PlaylistDraft,
    PlaylistItemCreate,
    PlaylistPage,
    PlaylistReorder,
    PlaylistUpdate,
    PreferencesBody,
    PreferencesOut,
    RegisterRequest,
    SearchHistoryEntry,
    SearchKind,
    SearchResponse,
    SuggestionsResponse,
    TasteProfile,
    TokenResponse,
    Track,
    TrackMetadataResponse,
    TrendingResponse,
    UpNextResponse,
)
from app.services.ai.intent import MusicIntent
from app.services.ai.providers import PlanOverrides
from app.services.catalog.base import (
    CatalogError,
    CatalogNotConfiguredError,
    CatalogUnavailableError,
    EntityUnavailableError,
    TrackUnavailableError,
)
from app.services.catalog.ids import TRACK_ID_PATTERN, is_valid_track_id
from app.services.feed.builder import HomeFeedBuilder
from app.services.music_sources.listenbrainz import (
    FreshRelease,
    ListenBrainzClient,
    ListenBrainzUnavailableError,
    PopularRecording,
)
from app.services.music_sources.musicbrainz import (
    MusicBrainzClient,
    MusicBrainzUnavailableError,
    clean_track_title,
)
from app.services.music_sources.radio import RadioStation, RadioUnavailableError
from app.services.recommendations.pipeline import Candidate

router = APIRouter(prefix="/api/v1")

SEARCH_LIMIT = Depends(rate_limit("search", "rate_limit_search_per_minute"))
AI_LIMIT = Depends(rate_limit("ai", "rate_limit_ai_per_minute"))
DEFAULT_LIMIT = Depends(rate_limit("default", "rate_limit_default_per_minute"))
AUTH_LIMIT = Depends(rate_limit("auth", "rate_limit_auth_per_minute"))

TrackIdPath = Annotated[str, Path(min_length=3, max_length=60, pattern=TRACK_ID_PATTERN)]
TrackIdQuery = Annotated[str, Query(min_length=3, max_length=60, pattern=TRACK_ID_PATTERN)]


def translate_catalog_error(exc: CatalogError) -> AppError:
    if isinstance(exc, CatalogNotConfiguredError):
        return ServiceUnavailableError(str(exc), code="catalog_not_configured")
    if isinstance(exc, TrackUnavailableError):
        return NotFoundError(str(exc), code="track_unavailable")
    if isinstance(exc, EntityUnavailableError):
        return NotFoundError(str(exc), code=f"{exc.kind}_unavailable")
    if isinstance(exc, CatalogUnavailableError):
        return UpstreamError(
            str(exc) or "Music sources are not responding right now. Please retry in a moment.",
            code="catalog_unavailable",
            headers={"Retry-After": "5"},
        )
    return UpstreamError("Music search failed. Please retry.", code="search_failed")


async def verified_tracks(catalog: CatalogDep, track_ids: list[str]) -> list[Track]:
    """Resolve ids through the catalog. Unknown or unavailable ids are rejected."""
    if not track_ids:
        return []
    try:
        found = await catalog.get_tracks(track_ids)
    except CatalogError as exc:
        raise translate_catalog_error(exc) from exc
    missing = [tid for tid in track_ids if tid not in found]
    if missing:
        raise AppError(
            "Some songs could not be verified as available",
            code="track_unavailable",
            status_code=422,
            details={"track_ids": missing[:20]},
        )
    return [found[tid] for tid in track_ids]


# --- Auth & account -------------------------------------------------------------------


@router.post(
    "/auth/register",
    response_model=TokenResponse,
    status_code=status.HTTP_201_CREATED,
    tags=["auth"],
    dependencies=[AUTH_LIMIT],
    summary="Create an anonymous Halo account and return a bearer token",
)
async def register(
    body: RegisterRequest, session: SessionDep, settings: SettingsDep
) -> TokenResponse:
    user = await user_repo.create_user(session, body.display_name)
    token, expires_at = create_access_token(user.id, settings)
    return TokenResponse(access_token=token, expires_at=expires_at, user_id=user.id)


@router.post(
    "/auth/refresh", response_model=TokenResponse, tags=["auth"], dependencies=[AUTH_LIMIT]
)
async def refresh_token(user: CurrentUser, settings: SettingsDep) -> TokenResponse:
    token, expires_at = create_access_token(user.id, settings)
    return TokenResponse(access_token=token, expires_at=expires_at, user_id=user.id)


@router.get("/me/export", tags=["account"], dependencies=[DEFAULT_LIMIT])
async def export_data(user: CurrentUser, session: SessionDep) -> dict[str, Any]:
    """Machine-readable export of everything Halo stores about the user."""
    prefs = await user_repo.preferences_out(session, user.id)
    summaries, _ = await playlist_repo.list_playlists(session, user.id, limit=1000, offset=0)
    playlists = [
        (await playlist_repo.get_playlist(session, user.id, p.id)).model_dump(mode="json")
        for p in summaries
    ]
    history = await user_repo.list_search_history(session, user.id, limit=1000)
    taste = await user_repo.taste_profile(session, user.id)
    return {
        "user": {
            "id": str(user.id),
            "display_name": user.display_name,
            "created_at": user.created_at.isoformat(),
        },
        "preferences": prefs.model_dump(mode="json"),
        "playlists": playlists,
        "search_history": [
            SearchHistoryEntry.model_validate(h).model_dump(mode="json") for h in history
        ],
        "taste_profile": taste.model_dump(mode="json"),
    }


@router.delete(
    "/me", status_code=status.HTTP_204_NO_CONTENT, tags=["account"], dependencies=[DEFAULT_LIMIT]
)
async def delete_account(user: CurrentUser, session: SessionDep) -> Response:
    """Permanently delete the account and all user-owned data (cascade)."""
    await user_repo.delete_user(session, user.id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# --- Search & tracks ------------------------------------------------------------------


@router.get("/search", response_model=SearchResponse, tags=["search"], dependencies=[SEARCH_LIMIT])
async def search(
    user: CurrentUser,
    session: SessionDep,
    catalog: CatalogDep,
    q: Annotated[str, Query(min_length=1, max_length=150)],
    kind: SearchKind = "song",
    page_token: Annotated[str | None, Query(max_length=200)] = None,
    limit: Annotated[int, Query(ge=1, le=50)] = 20,
) -> SearchResponse:
    query = " ".join(q.split())
    if not query:
        raise AppError("Search query must not be blank", code="validation_error", status_code=422)
    try:
        result = await catalog.search(query, kind=kind, page_token=page_token, max_results=limit)
    except CatalogError as exc:
        raise translate_catalog_error(exc) from exc
    if page_token is None:
        await user_repo.record_search(session, user.id, query, kind, len(result.page.items))
    return SearchResponse(
        query=query,
        kind=kind,
        items=result.page.items,
        next_page_token=result.page.next_page_token,
        prev_page_token=result.page.prev_page_token,
        total_results_estimate=result.page.total_results_estimate,
        sources=result.page.sources,
        cached=result.cached,
    )


_SEED_SUGGESTIONS = [
    "telugu melodies",
    "lofi beats for coding",
    "bollywood romantic hits",
    "tamil kuthu",
    "acoustic covers",
    "k-pop dance",
    "sufi qawwali",
    "carnatic instrumental",
    "road trip rock",
    "piano for sleep",
    "workout hip hop",
    "jazz for focus",
]


@router.get(
    "/search/suggestions",
    response_model=SuggestionsResponse,
    tags=["search"],
    dependencies=[DEFAULT_LIMIT],
    summary="Suggestions from the user's own Halo search history plus curated seeds",
)
async def search_suggestions(
    user: CurrentUser,
    session: SessionDep,
    q: Annotated[str, Query(max_length=100)] = "",
    limit: Annotated[int, Query(ge=1, le=20)] = 8,
) -> SuggestionsResponse:
    prefix = q.strip().lower()
    own = await user_repo.history_suggestions(session, user.id, prefix, limit)
    seeds = [s for s in _SEED_SUGGESTIONS if not prefix or prefix in s]
    merged = list(dict.fromkeys([*own, *seeds]))[:limit]
    return SuggestionsResponse(query=q, suggestions=merged)


@router.get(
    "/home",
    response_model=HomeFeed,
    tags=["discover"],
    dependencies=[DEFAULT_LIMIT],
    summary="Home feed: ordered sections built from open data and your activity in Halo",
)
async def home(request: Request, user: CurrentUser, session: SessionDep) -> HomeFeed:
    context = await user_repo.feed_context(session, user.id)
    builder: HomeFeedBuilder = request.app.state.home_feed
    return await builder.build(context)


@router.get(
    "/discover/trending",
    response_model=TrendingResponse,
    tags=["search"],
    dependencies=[SEARCH_LIMIT],
    summary="Full tracks trending this week on Audius and Jamendo",
)
async def trending(
    user: CurrentUser,
    catalog: CatalogDep,
    genre: Annotated[str | None, Query(max_length=40)] = None,
    limit: Annotated[int, Query(ge=1, le=50)] = 20,
) -> TrendingResponse:
    try:
        result = await catalog.trending(max_results=limit, genre=genre)
    except CatalogError as exc:
        raise translate_catalog_error(exc) from exc
    return TrendingResponse(
        items=result.page.items, sources=result.page.sources, cached=result.cached
    )


@router.get(
    "/tracks/{track_id}",
    response_model=Track,
    tags=["search"],
    dependencies=[SEARCH_LIMIT],
    summary="One track with a fresh stream URL; 404 track_unavailable if it was removed",
)
async def get_track(track_id: TrackIdPath, user: CurrentUser, catalog: CatalogDep) -> Track:
    try:
        return await catalog.get_track(track_id)
    except CatalogError as exc:
        raise translate_catalog_error(exc) from exc


@router.get(
    "/artists/{artist_id}",
    response_model=ArtistPage,
    tags=["search"],
    dependencies=[SEARCH_LIMIT],
    summary="An artist's page: profile, most-played songs and albums (Audius, Jamendo)",
)
async def get_artist(artist_id: TrackIdPath, user: CurrentUser, catalog: CatalogDep) -> ArtistPage:
    try:
        return await catalog.get_artist(artist_id)
    except CatalogError as exc:
        raise translate_catalog_error(exc) from exc


@router.get(
    "/albums/{album_id}",
    response_model=AlbumPage,
    tags=["search"],
    dependencies=[SEARCH_LIMIT],
    summary="An album with its playable tracks in order (Audius, Jamendo)",
)
async def get_album(album_id: TrackIdPath, user: CurrentUser, catalog: CatalogDep) -> AlbumPage:
    try:
        return await catalog.get_album(album_id)
    except CatalogError as exc:
        raise translate_catalog_error(exc) from exc


@router.get(
    "/history/search",
    response_model=list[SearchHistoryEntry],
    tags=["library"],
    dependencies=[DEFAULT_LIMIT],
)
async def get_search_history(
    user: CurrentUser, session: SessionDep, limit: Annotated[int, Query(ge=1, le=200)] = 50
) -> list[SearchHistoryEntry]:
    rows = await user_repo.list_search_history(session, user.id, limit)
    return [SearchHistoryEntry.model_validate(r) for r in rows]


@router.delete(
    "/history/search",
    status_code=status.HTTP_204_NO_CONTENT,
    tags=["library"],
    dependencies=[DEFAULT_LIMIT],
)
async def clear_search_history(user: CurrentUser, session: SessionDep) -> Response:
    await user_repo.clear_search_history(session, user.id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# --- Playlists ------------------------------------------------------------------------

PlaylistIdPath = Annotated[uuid.UUID, Path()]


@router.get(
    "/playlists", response_model=PlaylistPage, tags=["playlists"], dependencies=[DEFAULT_LIMIT]
)
async def list_playlists(
    user: CurrentUser,
    session: SessionDep,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> PlaylistPage:
    items, total = await playlist_repo.list_playlists(session, user.id, limit, offset)
    return PlaylistPage(items=items, total=total, limit=limit, offset=offset)


@router.post(
    "/playlists",
    response_model=PlaylistDetail,
    status_code=status.HTTP_201_CREATED,
    tags=["playlists"],
    dependencies=[DEFAULT_LIMIT],
)
async def create_playlist(
    body: PlaylistCreate, user: CurrentUser, session: SessionDep, catalog: CatalogDep
) -> PlaylistDetail:
    tracks = await verified_tracks(catalog, list(dict.fromkeys(body.track_ids)))
    return await playlist_repo.create_playlist(session, user.id, body, tracks)


@router.get(
    "/playlists/{playlist_id}",
    response_model=PlaylistDetail,
    tags=["playlists"],
    dependencies=[DEFAULT_LIMIT],
)
async def get_playlist(
    playlist_id: PlaylistIdPath, user: CurrentUser, session: SessionDep
) -> PlaylistDetail:
    return await playlist_repo.get_playlist(session, user.id, playlist_id)


@router.patch(
    "/playlists/{playlist_id}",
    response_model=PlaylistDetail,
    tags=["playlists"],
    dependencies=[DEFAULT_LIMIT],
)
async def update_playlist(
    playlist_id: PlaylistIdPath, body: PlaylistUpdate, user: CurrentUser, session: SessionDep
) -> PlaylistDetail:
    if "name" in body.model_fields_set and body.name is None:
        raise AppError("name cannot be null", code="validation_error", status_code=422)
    return await playlist_repo.update_playlist(session, user.id, playlist_id, body)


@router.delete(
    "/playlists/{playlist_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    tags=["playlists"],
    dependencies=[DEFAULT_LIMIT],
)
async def delete_playlist(
    playlist_id: PlaylistIdPath, user: CurrentUser, session: SessionDep
) -> Response:
    await playlist_repo.delete_playlist(session, user.id, playlist_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/playlists/{playlist_id}/items",
    response_model=PlaylistDetail,
    status_code=status.HTTP_201_CREATED,
    tags=["playlists"],
    dependencies=[DEFAULT_LIMIT],
)
async def add_playlist_item(
    playlist_id: PlaylistIdPath,
    body: PlaylistItemCreate,
    user: CurrentUser,
    session: SessionDep,
    catalog: CatalogDep,
) -> PlaylistDetail:
    # Ownership is checked before calling the music sources.
    await playlist_repo.get_playlist(session, user.id, playlist_id)
    [track] = await verified_tracks(catalog, [body.track_id])
    return await playlist_repo.add_item(
        session, user.id, playlist_id, track, body.position, body.note
    )


@router.delete(
    "/playlists/{playlist_id}/items/{item_id}",
    response_model=PlaylistDetail,
    tags=["playlists"],
    dependencies=[DEFAULT_LIMIT],
)
async def remove_playlist_item(
    playlist_id: PlaylistIdPath,
    item_id: Annotated[uuid.UUID, Path()],
    user: CurrentUser,
    session: SessionDep,
) -> PlaylistDetail:
    return await playlist_repo.remove_item(session, user.id, playlist_id, item_id)


@router.put(
    "/playlists/{playlist_id}/items/order",
    response_model=PlaylistDetail,
    tags=["playlists"],
    dependencies=[DEFAULT_LIMIT],
)
async def reorder_playlist_items(
    playlist_id: PlaylistIdPath, body: PlaylistReorder, user: CurrentUser, session: SessionDep
) -> PlaylistDetail:
    return await playlist_repo.reorder_items(session, user.id, playlist_id, body.item_ids)


# --- AI ---------------------------------------------------------------------------------


async def colisten_candidates(
    session: SessionDep, catalog: CatalogDep, seeds: list[str], limit: int = 25
) -> list[Candidate]:
    """Co-listening candidates, re-verified with the catalog before use."""
    pairs = await rec_repo.co_listened(session, seeds, limit=limit)
    if not pairs:
        return []
    try:
        verified = await catalog.get_tracks([p.track_id for p in pairs])
    except CatalogError:
        return []
    return [
        Candidate(
            track=verified[p.track_id],
            query="co-listening",
            rank=rank,
            source="co_listen",
            source_reason=f"Listeners who saved “{p.seed_title}” also saved this",
            cf_score=min(p.score, 1.0),
        )
        for rank, p in enumerate(pairs)
        if p.track_id in verified
    ]


async def _build_draft(
    *,
    text: str,
    source: str,
    overrides: PlanOverrides,
    exclude_track_ids: set[str],
    history: list[dict[str, str]],
    user_id: uuid.UUID,
    session: SessionDep,
    planner: PlannerDep,
    pipeline: PipelineDep,
    catalog: CatalogDep,
) -> PlaylistDraft:
    hints = await user_repo.preference_hints(session, user_id)
    prefs = await user_repo.get_preferences(session, user_id)
    plan = await planner.plan(text, hints, overrides, history)
    feedback = (
        await user_repo.feedback_signals(session, user_id)
        if prefs.personalization_enabled
        else None
    )
    personal = prefs.personalization_enabled
    extra = (
        await colisten_candidates(session, catalog, await rec_repo.listener_seeds(session, user_id))
        if personal
        else []
    )
    try:
        result = await pipeline.run(
            plan.intent,
            hints,
            feedback,
            exclude_track_ids,
            extra_candidates=extra,
            ranker=await rec_repo.load_ranker(session),
            posteriors=await rec_repo.arm_posteriors(session, user_id if personal else None),
        )
    except CatalogError as exc:
        raise translate_catalog_error(exc) from exc

    session_id: uuid.UUID | None = None
    if prefs.personalization_enabled:
        record = RecommendationSession(
            user_id=user_id,
            source=source,
            request_text=text if prefs.store_ai_conversations else None,
            intent=plan.intent.summary_fields(),
            planner=plan.planner,
            result_track_ids=[t.track.id for t in result.tracks],
            result_details=result.details,
        )
        session.add(record)
        await session.flush()
        session_id = record.id

    warnings = list(result.warnings)
    if plan.warning:
        warnings.insert(0, plan.warning)
    return PlaylistDraft(
        session_id=session_id,
        title=plan.intent.playlist_title,
        explanation=plan.intent.explanation,
        intent=plan.intent.summary_fields(),
        planner=plan.planner,
        queries=plan.intent.search_queries,
        tracks=result.tracks,
        total_duration_seconds=result.total_duration_seconds,
        target_duration_seconds=result.target_duration_seconds,
        sources=catalog.source_names,
        warnings=warnings,
    )


@router.post(
    "/ai/playlist",
    response_model=PlaylistDraft,
    tags=["ai"],
    dependencies=[AI_LIMIT],
    summary="Plan and assemble an editable playlist draft from verified search results",
)
async def ai_playlist(
    body: AIPlaylistRequest,
    user: CurrentUser,
    session: SessionDep,
    planner: PlannerDep,
    pipeline: PipelineDep,
    catalog: CatalogDep,
) -> PlaylistDraft:
    exclude = {t for t in body.exclude_track_ids if is_valid_track_id(t)}
    return await _build_draft(
        text=body.description,
        source="studio",
        overrides=PlanOverrides(
            mood=body.mood,
            language=body.language,
            genres=body.genres or None,
            energy=body.energy,
            duration_minutes=body.duration_minutes,
            discovery=body.discovery,
        ),
        exclude_track_ids=exclude,
        history=[],
        user_id=user.id,
        session=session,
        planner=planner,
        pipeline=pipeline,
        catalog=catalog,
    )


@router.post("/ai/chat", response_model=AIChatResponse, tags=["ai"], dependencies=[AI_LIMIT])
async def ai_chat(
    body: AIChatRequest,
    user: CurrentUser,
    session: SessionDep,
    planner: PlannerDep,
    pipeline: PipelineDep,
    catalog: CatalogDep,
) -> AIChatResponse:
    history = [m.model_dump() for m in body.history]
    draft = await _build_draft(
        text=body.message,
        source="chat",
        overrides=PlanOverrides(),
        exclude_track_ids=set(),
        history=history,
        user_id=user.id,
        session=session,
        planner=planner,
        pipeline=pipeline,
        catalog=catalog,
    )
    if draft.tracks:
        minutes = draft.total_duration_seconds // 60
        reply = (
            f"{draft.explanation} Here are {len(draft.tracks)} songs "
            f"(about {minutes} min). Play them now, edit the queue, or save it as a playlist."
        ).strip()
    else:
        reply = "I couldn't find songs for that. Try naming a language, mood, genre or artist."
    prefs = await user_repo.get_preferences(session, user.id)
    conversation_id: uuid.UUID | None = None
    stored = False
    if prefs.personalization_enabled and prefs.store_ai_conversations:
        conversation = await user_repo.append_conversation(
            session, user.id, body.conversation_id, body.message, reply
        )
        conversation_id = conversation.id
        stored = True
    return AIChatResponse(conversation_id=conversation_id, reply=reply, draft=draft, stored=stored)


@router.post(
    "/recommendations/feedback",
    response_model=FeedbackResponse,
    tags=["ai"],
    dependencies=[DEFAULT_LIMIT],
)
async def recommendation_feedback(
    body: FeedbackRequest, user: CurrentUser, session: SessionDep
) -> FeedbackResponse:
    prefs = await user_repo.get_preferences(session, user.id)
    if not prefs.personalization_enabled:
        # Accepted but not stored: personalization is off.
        return FeedbackResponse(
            id=uuid.uuid4(), track_id=body.track_id, rating=body.rating, recorded=False
        )
    row = await user_repo.upsert_feedback(
        session, user.id, body.track_id, body.rating, body.session_id, body.artist
    )
    await rec_repo.record_bandit_reward(
        session, user.id, row.session_id, body.track_id, body.rating
    )
    return FeedbackResponse(id=row.id, track_id=row.track_id, rating=body.rating, recorded=True)


@router.get(
    "/recommendations/next",
    response_model=UpNextResponse,
    tags=["ai"],
    dependencies=[SEARCH_LIMIT],
    summary="Songs to choose next after a song (co-listening, same and similar artists)",
)
async def up_next(
    user: CurrentUser,
    session: SessionDep,
    pipeline: PipelineDep,
    catalog: CatalogDep,
    track_id: TrackIdQuery,
    limit: Annotated[int, Query(ge=1, le=25)] = 10,
) -> UpNextResponse:
    try:
        seed = await catalog.get_track(track_id)
    except CatalogError as exc:
        raise translate_catalog_error(exc) from exc
    prefs = await user_repo.get_preferences(session, user.id)
    hints = await user_repo.preference_hints(session, user.id)
    personal = prefs.personalization_enabled
    intent = MusicIntent(
        search_queries=[seed.artist],
        reference_artists=[seed.artist],
        exclude_artists=hints.excluded_artists[:20],
        duration_minutes=max(10, limit * 4),
        discovery=prefs.discovery_preference,  # type: ignore[arg-type]
        playlist_title="Up next",
    )
    extra = await colisten_candidates(session, catalog, [track_id])
    try:
        result = await pipeline.run(
            intent,
            hints,
            await user_repo.feedback_signals(session, user.id) if personal else None,
            {track_id},
            extra_candidates=extra,
            ranker=await rec_repo.load_ranker(session),
            posteriors=await rec_repo.arm_posteriors(session, user.id if personal else None),
        )
    except CatalogError as exc:
        raise translate_catalog_error(exc) from exc
    return UpNextResponse(seed_track_id=track_id, tracks=result.tracks[:limit])


# --- MusicBrainz / ListenBrainz --------------------------------------------------------


def _musicbrainz(request: Request) -> MusicBrainzClient:
    client: MusicBrainzClient | None = request.app.state.musicbrainz
    if client is None:
        raise ServiceUnavailableError(
            "Music metadata is turned off on this server.", code="metadata_disabled"
        )
    return client


def _listenbrainz(request: Request) -> ListenBrainzClient:
    client: ListenBrainzClient | None = request.app.state.listenbrainz
    if client is None:
        raise ServiceUnavailableError(
            "Music discovery is turned off on this server.", code="discovery_disabled"
        )
    return client


@router.get(
    "/metadata/track",
    response_model=TrackMetadataResponse,
    tags=["metadata"],
    dependencies=[SEARCH_LIMIT],
    summary="Canonical recording, album, release date, label, ISRC and genres (MusicBrainz)",
)
async def track_metadata(
    request: Request,
    user: CurrentUser,
    catalog: CatalogDep,
    track_id: TrackIdQuery,
) -> TrackMetadataResponse:
    musicbrainz = _musicbrainz(request)
    try:
        track = await catalog.get_track(track_id)
    except CatalogError as exc:
        raise translate_catalog_error(exc) from exc
    artist_name, title = clean_track_title(track.title, track.artist)
    try:
        recording = await musicbrainz.match_recording(title, artist_name, track.duration_seconds)
        artist = None
        if recording and recording.artist_credit and recording.artist_credit[0].mbid:
            artist = await musicbrainz.artist(recording.artist_credit[0].mbid)
    except MusicBrainzUnavailableError as exc:
        raise UpstreamError(
            "Music metadata is unavailable right now.",
            code="metadata_unavailable",
            headers={"Retry-After": "30"},
        ) from exc
    return TrackMetadataResponse(
        track_id=track_id,
        parsed_artist=artist_name,
        parsed_title=title,
        matched=recording is not None,
        recording=recording,
        artist=artist,
    )


@router.get(
    "/metadata/artist",
    response_model=ArtistProfileResponse,
    tags=["metadata"],
    dependencies=[SEARCH_LIMIT],
    summary="Artist profile (MusicBrainz) with popular recordings (ListenBrainz)",
)
async def artist_profile(
    request: Request,
    user: CurrentUser,
    name: Annotated[str, Query(min_length=1, max_length=100)],
) -> ArtistProfileResponse:
    musicbrainz = _musicbrainz(request)
    try:
        artist = await musicbrainz.find_artist(name)
    except MusicBrainzUnavailableError as exc:
        raise UpstreamError(
            "Music metadata is unavailable right now.",
            code="metadata_unavailable",
            headers={"Retry-After": "30"},
        ) from exc
    popular: list[PopularRecording] = []
    sources = ["MusicBrainz"] if artist else []
    listenbrainz: ListenBrainzClient | None = request.app.state.listenbrainz
    if artist and listenbrainz is not None:
        try:
            popular = await listenbrainz.artist_top_recordings(artist.mbid)
        except ListenBrainzUnavailableError:
            popular = []
        if popular:
            sources.append("ListenBrainz")
    return ArtistProfileResponse(artist=artist, popular_recordings=popular, sources=sources)


@router.get(
    "/discover/fresh-releases",
    response_model=list[FreshRelease],
    tags=["search"],
    dependencies=[SEARCH_LIMIT],
    summary="New and recent releases with listen counts (ListenBrainz)",
)
async def fresh_releases(
    request: Request,
    user: CurrentUser,
    days: Annotated[int, Query(ge=1, le=90)] = 14,
    upcoming: bool = False,
    limit: Annotated[int, Query(ge=1, le=200)] = 60,
) -> list[FreshRelease]:
    try:
        releases = await _listenbrainz(request).fresh_releases(
            days=days, past=True, future=upcoming
        )
    except ListenBrainzUnavailableError as exc:
        raise UpstreamError(
            "New releases are unavailable right now.",
            code="discovery_unavailable",
            headers={"Retry-After": "30"},
        ) from exc
    releases.sort(key=lambda r: (r.release_date, r.listen_count), reverse=True)
    return releases[:limit]


@router.get(
    "/discover/most-listened",
    response_model=list[PopularRecording],
    tags=["search"],
    dependencies=[SEARCH_LIMIT],
    summary="Most-listened recordings across ListenBrainz for a time range",
)
async def most_listened(
    request: Request,
    user: CurrentUser,
    range_: Annotated[
        str, Query(alias="range", pattern="^(week|month|quarter|year|all_time)$")
    ] = "week",
    limit: Annotated[int, Query(ge=1, le=100)] = 25,
) -> list[PopularRecording]:
    try:
        return await _listenbrainz(request).top_recordings(range_=range_, count=limit)
    except ListenBrainzUnavailableError as exc:
        raise UpstreamError(
            "Listening charts are unavailable right now.",
            code="discovery_unavailable",
            headers={"Retry-After": "30"},
        ) from exc


# --- Live radio -------------------------------------------------------------------------


@router.get(
    "/radio/stations",
    response_model=list[RadioStation],
    tags=["radio"],
    dependencies=[SEARCH_LIMIT],
    summary="Live internet radio stations from the Radio Browser community directory",
)
async def radio_stations(
    user: CurrentUser,
    radio: RadioDep,
    tag: Annotated[str | None, Query(max_length=40)] = None,
    language: Annotated[str | None, Query(max_length=40)] = None,
    country: Annotated[str | None, Query(min_length=2, max_length=2)] = None,
    q: Annotated[str | None, Query(max_length=60)] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 30,
) -> list[RadioStation]:
    try:
        return await radio.search(
            tag=tag, language=language, country_code=country, name=q, limit=limit
        )
    except RadioUnavailableError as exc:
        raise UpstreamError(
            str(exc), code="radio_unavailable", headers={"Retry-After": "30"}
        ) from exc


# --- Preferences ------------------------------------------------------------------------


@router.get(
    "/preferences",
    response_model=PreferencesOut,
    tags=["preferences"],
    dependencies=[DEFAULT_LIMIT],
)
async def get_preferences(user: CurrentUser, session: SessionDep) -> PreferencesOut:
    return await user_repo.preferences_out(session, user.id)


@router.put(
    "/preferences",
    response_model=PreferencesOut,
    tags=["preferences"],
    dependencies=[DEFAULT_LIMIT],
)
async def put_preferences(
    body: PreferencesBody, user: CurrentUser, session: SessionDep
) -> PreferencesOut:
    return await user_repo.replace_preferences(session, user.id, body)


@router.get(
    "/preferences/taste",
    response_model=TasteProfile,
    tags=["preferences"],
    dependencies=[DEFAULT_LIMIT],
)
async def get_taste(user: CurrentUser, session: SessionDep) -> TasteProfile:
    return await user_repo.taste_profile(session, user.id)


@router.delete(
    "/preferences/taste",
    status_code=status.HTTP_204_NO_CONTENT,
    tags=["preferences"],
    dependencies=[DEFAULT_LIMIT],
)
async def reset_taste(user: CurrentUser, session: SessionDep) -> Response:
    await user_repo.reset_taste_memory(session, user.id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
