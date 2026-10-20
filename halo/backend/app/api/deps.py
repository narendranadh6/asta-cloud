"""Shared FastAPI dependencies."""

from __future__ import annotations

import uuid
from collections.abc import AsyncIterator
from datetime import UTC, datetime, timedelta
from typing import Annotated

from fastapi import Depends, Header, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.errors import AuthenticationError
from app.core.security import bearer_token, decode_access_token
from app.db.session import session_scope
from app.models import User
from app.services.ai.providers import IntentPlanner
from app.services.music_sources.radio import RadioBrowserClient
from app.services.recommendations.pipeline import RecommendationPipeline
from app.services.youtube.service import YouTubeSearchService


def get_settings_dep(request: Request) -> Settings:
    settings: Settings = request.app.state.settings
    return settings


async def get_session(request: Request) -> AsyncIterator[AsyncSession]:
    async for session in session_scope(request.app.state.session_factory):
        yield session


def get_search_service(request: Request) -> YouTubeSearchService:
    service: YouTubeSearchService = request.app.state.search_service
    return service


def get_planner(request: Request) -> IntentPlanner:
    planner: IntentPlanner = request.app.state.planner
    return planner


def get_pipeline(request: Request) -> RecommendationPipeline:
    pipeline: RecommendationPipeline = request.app.state.pipeline
    return pipeline


def get_radio(request: Request) -> RadioBrowserClient:
    radio: RadioBrowserClient = request.app.state.radio
    return radio


SessionDep = Annotated[AsyncSession, Depends(get_session)]
SettingsDep = Annotated[Settings, Depends(get_settings_dep)]
SearchServiceDep = Annotated[YouTubeSearchService, Depends(get_search_service)]
PlannerDep = Annotated[IntentPlanner, Depends(get_planner)]
PipelineDep = Annotated[RecommendationPipeline, Depends(get_pipeline)]
RadioDep = Annotated[RadioBrowserClient, Depends(get_radio)]


async def get_current_user(
    request: Request,
    session: SessionDep,
    settings: SettingsDep,
    authorization: Annotated[str | None, Header()] = None,
) -> User:
    token = bearer_token(authorization)
    if token is None:
        raise AuthenticationError("Authentication required", headers={"WWW-Authenticate": "Bearer"})
    user_id = decode_access_token(token, settings)
    user = await session.get(User, user_id)
    if user is None:
        raise AuthenticationError("Account no longer exists", code="account_deleted")
    now = datetime.now(UTC)
    last_seen = user.last_seen_at
    if last_seen is not None and last_seen.tzinfo is None:
        last_seen = last_seen.replace(tzinfo=UTC)
    if last_seen is None or now - last_seen > timedelta(hours=1):
        user.last_seen_at = now
    request.state.user_id = str(user.id)
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]


def user_id_of(user: User) -> uuid.UUID:
    return user.id
