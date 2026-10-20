"""Version 1 REST endpoints."""

from __future__ import annotations

import uuid
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Path, Query, Response, status

from app.api.deps import (
    CurrentUser,
    PipelineDep,
    PlannerDep,
    RadioDep,
    SearchServiceDep,
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
    FeedbackRequest,
    FeedbackResponse,
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
    TrendingResponse,
    UpNextResponse,
)
from app.services.ai.intent import MusicIntent
from app.services.ai.providers import PlanOverrides
from app.services.music_sources.radio import RadioStation, RadioUnavailableError
from app.services.recommendations.pipeline import Candidate
from app.services.youtube.base import (
    ProviderConfigurationError,
    ProviderUnavailableError,
    QuotaExceededError,
    VideoUnavailableError,
    YouTubeError,
)
from app.services.youtube.ids import is_valid_video_id

router = APIRouter(prefix="/api/v1")

SEARCH_LIMIT = Depends(rate_limit("search", "rate_limit_search_per_minute"))
AI_LIMIT = Depends(rate_limit("ai", "rate_limit_ai_per_minute"))
DEFAULT_LIMIT = Depends(rate_limit("default", "rate_limit_default_per_minute"))
AUTH_LIMIT = Depends(rate_limit("auth", "rate_limit_auth_per_minute"))

VideoIdPath = Annotated[str, Path(min_length=11, max_length=11, pattern=r"^[A-Za-z0-9_-]{11}$")]


def translate_provider_error(exc: YouTubeError) -> AppError:
    if isinstance(exc, QuotaExceededError):
        return ServiceUnavailableError(
            "Music search has reached its daily limit. Saved music still works; "
            "please try searching again later.",
            code="search_quota_exceeded",
            headers={"Retry-After": "3600"},
        )
    if isinstance(exc, ProviderConfigurationError):
        return ServiceUnavailableError(
            str(exc) or "Music search is not configured correctly on the server.",
            code="search_misconfigured"
        )
    if isinstance(exc, ProviderUnavailableError):
        return UpstreamError(
            "YouTube is not responding right now. Please retry in a moment.",
            code="search_unavailable",
            headers={"Retry-After": "5"},
        )
    if isinstance(exc, VideoUnavailableError):
        return NotFoundError(str(exc), code="video_unavailable")
    return UpstreamError("Music search failed. Please retry.", code="search_failed")


async def verified_tracks(search: SearchServiceDep, video_ids: list[str]) -> list[Track]:
    """Resolve ids through the provider. Unknown or unavailable ids are rejected."""
    if not video_ids:
        return []
    try:
        found = await search.get_videos(video_ids)
    except YouTubeError as exc:
        raise translate_provider_error(exc) from exc
    missing = [vid for vid in video_ids if vid not in found]
    if missing:
        raise AppError(
            "Some songs could not be verified as available",
            code="video_unavailable",
            status_code=422,
            details={"video_ids": missing[:20]},
        )
    return [found[vid] for vid in video_ids]


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
        "user": {"id": str(user.id), "display_name": user.display_name,
                 "created_at": user.created_at.isoformat()},
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


# --- Search & videos ------------------------------------------------------------------


@router.get(
    "/search", response_model=SearchResponse, tags=["search"], dependencies=[SEARCH_LIMIT]
)
async def search(
    user: CurrentUser,
    session: SessionDep,
    search_service: SearchServiceDep,
    q: Annotated[str, Query(min_length=1, max_length=150)],
    kind: SearchKind = "song",
    page_token: Annotated[str | None, Query(max_length=200)] = None,
    limit: Annotated[int, Query(ge=1, le=50)] = 20,
) -> SearchResponse:
    query = " ".join(q.split())
    if not query:
        raise AppError("Search query must not be blank", code="validation_error", status_code=422)
    try:
        result = await search_service.search(
            query, kind=kind, page_token=page_token, max_results=limit
        )
    except YouTubeError as exc:
        raise translate_provider_error(exc) from exc
    if page_token is None:
        await user_repo.record_search(session, user.id, query, kind, len(result.page.items))
    return SearchResponse(
        query=query,
        kind=kind,
        items=result.page.items,
        next_page_token=result.page.next_page_token,
        prev_page_token=result.page.prev_page_token,
        total_results_estimate=result.page.total_results_estimate,
        provider=search_service.provider.name,
        cached=result.cached,
    )


_SEED_SUGGESTIONS = [
    "telugu melodies", "lofi beats for coding", "bollywood romantic hits", "tamil kuthu",
    "acoustic covers", "k-pop dance", "sufi qawwali", "carnatic instrumental",
    "road trip rock", "piano for sleep", "workout hip hop", "jazz for focus",
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
    "/discover/trending",
    response_model=TrendingResponse,
    tags=["search"],
    dependencies=[SEARCH_LIMIT],
    summary="Most popular music videos in the configured region (official YouTube chart)",
)
async def trending(
    user: CurrentUser,
    search_service: SearchServiceDep,
    page_token: Annotated[str | None, Query(max_length=200)] = None,
    limit: Annotated[int, Query(ge=1, le=50)] = 20,
) -> TrendingResponse:
    try:
        result = await search_service.trending(page_token=page_token, max_results=limit)
    except YouTubeError as exc:
        raise translate_provider_error(exc) from exc
    return TrendingResponse(
        items=result.page.items,
        next_page_token=result.page.next_page_token,
        prev_page_token=result.page.prev_page_token,
        provider=search_service.provider.name,
        cached=result.cached,
    )


@router.get(
    "/videos/{video_id}", response_model=Track, tags=["search"], dependencies=[SEARCH_LIMIT]
)
async def get_video(
    video_id: VideoIdPath, user: CurrentUser, search_service: SearchServiceDep
) -> Track:
    try:
        return await search_service.get_video(video_id)
    except YouTubeError as exc:
        raise translate_provider_error(exc) from exc


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
    body: PlaylistCreate, user: CurrentUser, session: SessionDep, search: SearchServiceDep
) -> PlaylistDetail:
    tracks = await verified_tracks(search, list(dict.fromkeys(body.video_ids)))
    return await playlist_repo.create_playlist(
        session, user.id, body, tracks, search.provider.name
    )


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
    search: SearchServiceDep,
) -> PlaylistDetail:
    # Ownership is checked before spending provider quota.
    await playlist_repo.get_playlist(session, user.id, playlist_id)
    [track] = await verified_tracks(search, [body.video_id])
    return await playlist_repo.add_item(
        session, user.id, playlist_id, track, search.provider.name, body.position, body.note
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
    session: SessionDep, search: SearchServiceDep, seeds: list[str], limit: int = 25
) -> list[Candidate]:
    """Co-listening candidates, re-verified with the provider before use."""
    pairs = await rec_repo.co_listened(session, seeds, limit=limit)
    if not pairs:
        return []
    try:
        verified = await search.get_videos([p.video_id for p in pairs])
    except YouTubeError:
        return []
    return [
        Candidate(
            track=verified[p.video_id], query="co-listening", rank=rank, source="co_listen",
            source_reason=f"Listeners who saved “{p.seed_title}” also saved this",
            cf_score=min(p.score, 1.0),
        )
        for rank, p in enumerate(pairs) if p.video_id in verified
    ]



async def _build_draft(
    *,
    text: str,
    source: str,
    overrides: PlanOverrides,
    exclude_video_ids: set[str],
    history: list[dict[str, str]],
    user_id: uuid.UUID,
    session: SessionDep,
    planner: PlannerDep,
    pipeline: PipelineDep,
    search: SearchServiceDep,
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
        await colisten_candidates(session, search, await rec_repo.listener_seeds(session, user_id))
        if personal else []
    )
    try:
        result = await pipeline.run(
            plan.intent, hints, feedback, exclude_video_ids,
            extra_candidates=extra,
            ranker=await rec_repo.load_ranker(session),
            posteriors=await rec_repo.arm_posteriors(session, user_id if personal else None),
        )
    except YouTubeError as exc:
        raise translate_provider_error(exc) from exc

    session_id: uuid.UUID | None = None
    if prefs.personalization_enabled:
        record = RecommendationSession(
            user_id=user_id,
            source=source,
            request_text=text if prefs.store_ai_conversations else None,
            intent=plan.intent.summary_fields(),
            planner=plan.planner,
            result_video_ids=[t.track.video_id for t in result.tracks],
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
        provider=search.provider.name,
        warnings=warnings,
    )


@router.post(
    "/ai/playlist", response_model=PlaylistDraft, tags=["ai"], dependencies=[AI_LIMIT],
    summary="Plan and assemble an editable playlist draft from verified search results",
)
async def ai_playlist(
    body: AIPlaylistRequest,
    user: CurrentUser,
    session: SessionDep,
    planner: PlannerDep,
    pipeline: PipelineDep,
    search: SearchServiceDep,
) -> PlaylistDraft:
    exclude = {v for v in body.exclude_video_ids if is_valid_video_id(v)}
    return await _build_draft(
        text=body.description,
        source="studio",
        overrides=PlanOverrides(
            mood=body.mood, language=body.language, genres=body.genres or None,
            energy=body.energy, duration_minutes=body.duration_minutes,
            discovery=body.discovery,
        ),
        exclude_video_ids=exclude,
        history=[],
        user_id=user.id,
        session=session,
        planner=planner,
        pipeline=pipeline,
        search=search,
    )


@router.post("/ai/chat", response_model=AIChatResponse, tags=["ai"], dependencies=[AI_LIMIT])
async def ai_chat(
    body: AIChatRequest,
    user: CurrentUser,
    session: SessionDep,
    planner: PlannerDep,
    pipeline: PipelineDep,
    search: SearchServiceDep,
) -> AIChatResponse:
    history = [m.model_dump() for m in body.history]
    draft = await _build_draft(
        text=body.message,
        source="chat",
        overrides=PlanOverrides(),
        exclude_video_ids=set(),
        history=history,
        user_id=user.id,
        session=session,
        planner=planner,
        pipeline=pipeline,
        search=search,
    )
    if draft.tracks:
        minutes = draft.total_duration_seconds // 60
        reply = (
            f"{draft.explanation} Here are {len(draft.tracks)} verified tracks "
            f"(about {minutes} min). Edit the queue, then save it as a playlist."
        ).strip()
    else:
        reply = (
            "I couldn't find verified matches for that. Try naming a language, mood, "
            "genre or artist."
        )
    prefs = await user_repo.get_preferences(session, user.id)
    conversation_id: uuid.UUID | None = None
    stored = False
    if prefs.personalization_enabled and prefs.store_ai_conversations:
        conversation = await user_repo.append_conversation(
            session, user.id, body.conversation_id, body.message, reply
        )
        conversation_id = conversation.id
        stored = True
    return AIChatResponse(
        conversation_id=conversation_id, reply=reply, draft=draft, stored=stored
    )


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
            id=uuid.uuid4(), video_id=body.video_id, rating=body.rating, recorded=False
        )
    row = await user_repo.upsert_feedback(
        session, user.id, body.video_id, body.rating, body.session_id, body.channel_title
    )
    await rec_repo.record_bandit_reward(
        session, user.id, row.session_id, body.video_id, body.rating
    )
    return FeedbackResponse(
        id=row.id, video_id=row.video_id, rating=body.rating, recorded=True
    )


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
    search: SearchServiceDep,
    video_id: Annotated[str, Query(min_length=11, max_length=11, pattern=r"^[A-Za-z0-9_-]{11}$")],
    limit: Annotated[int, Query(ge=1, le=25)] = 10,
) -> UpNextResponse:
    try:
        seed = await search.get_video(video_id)
    except YouTubeError as exc:
        raise translate_provider_error(exc) from exc
    prefs = await user_repo.get_preferences(session, user.id)
    hints = await user_repo.preference_hints(session, user.id)
    personal = prefs.personalization_enabled
    intent = MusicIntent(
        search_queries=[f"{seed.channel_title} songs"],
        reference_artists=[seed.channel_title],
        exclude_artists=hints.excluded_artists[:20],
        duration_minutes=max(10, limit * 4),
        discovery=prefs.discovery_preference,  # type: ignore[arg-type]
        playlist_title="Up next",
    )
    extra = await colisten_candidates(session, search, [video_id])
    try:
        result = await pipeline.run(
            intent, hints,
            await user_repo.feedback_signals(session, user.id) if personal else None,
            {video_id},
            extra_candidates=extra,
            ranker=await rec_repo.load_ranker(session),
            posteriors=await rec_repo.arm_posteriors(session, user.id if personal else None),
        )
    except YouTubeError as exc:
        raise translate_provider_error(exc) from exc
    return UpNextResponse(seed_video_id=video_id, tracks=result.tracks[:limit])


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
        return await radio.search(tag=tag, language=language, country_code=country, name=q,
                                  limit=limit)
    except RadioUnavailableError as exc:
        raise UpstreamError(str(exc), code="radio_unavailable",
                            headers={"Retry-After": "30"}) from exc


# --- Preferences ------------------------------------------------------------------------


@router.get(
    "/preferences", response_model=PreferencesOut, tags=["preferences"],
    dependencies=[DEFAULT_LIMIT],
)
async def get_preferences(user: CurrentUser, session: SessionDep) -> PreferencesOut:
    return await user_repo.preferences_out(session, user.id)


@router.put(
    "/preferences", response_model=PreferencesOut, tags=["preferences"],
    dependencies=[DEFAULT_LIMIT],
)
async def put_preferences(
    body: PreferencesBody, user: CurrentUser, session: SessionDep
) -> PreferencesOut:
    return await user_repo.replace_preferences(session, user.id, body)


@router.get(
    "/preferences/taste", response_model=TasteProfile, tags=["preferences"],
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
