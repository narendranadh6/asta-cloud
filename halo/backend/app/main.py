"""Halo API application factory."""

from __future__ import annotations

import logging
import uuid
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from app.api.v1.routes import router as v1_router
from app.core.cache import KeyValueStore, MemoryStore, create_store
from app.core.config import Settings, get_settings
from app.core.errors import install_error_handlers
from app.core.security import bearer_token, decode_access_token
from app.db.session import create_engine, create_session_factory
from app.services.ai.providers import IntentPlanner, build_planner
from app.services.music_sources.discovery import ListenBrainzDiscovery
from app.services.music_sources.listenbrainz import ListenBrainzClient
from app.services.music_sources.musicbrainz import MusicBrainzClient
from app.services.music_sources.radio import RadioBrowserClient
from app.services.music_sources.similar_artists import build_similar_artists
from app.services.recommendations.pipeline import RecommendationPipeline
from app.services.youtube.base import MetadataProvider
from app.services.youtube.service import YouTubeSearchService, build_provider

logger = logging.getLogger("halo")


def create_app(
    settings: Settings | None = None,
    *,
    provider: MetadataProvider | None = None,
    planner: IntentPlanner | None = None,
    store: KeyValueStore | None = None,
) -> FastAPI:
    settings = settings or get_settings()
    settings.validate_for_production()
    logging.basicConfig(level=logging.DEBUG if settings.debug else logging.INFO)

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        engine = create_engine(settings.database_url)
        kv = store or create_store(settings.redis_url)
        if not isinstance(kv, MemoryStore) and not await kv.ping():
            logger.warning("Redis unreachable; falling back to in-process cache/rate limits")
            kv = MemoryStore()
        metadata = provider or build_provider(settings)
        search_service = YouTubeSearchService(
            metadata,
            kv,
            search_ttl_seconds=settings.youtube_search_cache_ttl_seconds,
            video_ttl_seconds=settings.youtube_video_cache_ttl_seconds,
        )
        app.state.settings = settings
        app.state.engine = engine
        app.state.session_factory = create_session_factory(engine)
        app.state.store = kv
        app.state.search_service = search_service
        app.state.planner = planner or build_planner(settings)
        app.state.musicbrainz = (
            MusicBrainzClient(kv, contact=settings.musicbrainz_contact)
            if settings.musicbrainz_enabled
            else None
        )
        lb_token = (
            settings.listenbrainz_token.get_secret_value() if settings.listenbrainz_token else ""
        )
        app.state.listenbrainz = (
            ListenBrainzClient(kv, token=lb_token.strip() or None)
            if settings.listenbrainz_enabled
            else None
        )
        app.state.discovery = (
            ListenBrainzDiscovery(app.state.musicbrainz, app.state.listenbrainz)
            if app.state.musicbrainz and app.state.listenbrainz
            else None
        )
        app.state.similar_artists = build_similar_artists(settings, kv, first=app.state.discovery)
        app.state.radio = RadioBrowserClient(kv, base_url=settings.radio_browser_base_url)
        app.state.pipeline = RecommendationPipeline(
            search_service,
            similar_artists=app.state.similar_artists,
            track_discovery=app.state.discovery,
            track_lookups=settings.listenbrainz_track_lookups,
        )
        try:
            yield
        finally:
            await app.state.planner.aclose()
            await app.state.similar_artists.aclose()
            await app.state.radio.aclose()
            for client in (app.state.musicbrainz, app.state.listenbrainz):
                if client is not None:
                    await client.aclose()
            await metadata.aclose()
            await kv.close()
            await engine.dispose()

    app = FastAPI(
        title=settings.api_title,
        version="0.1.0",
        description=(
            "Halo discovers music metadata via the YouTube Data API and hands playback off "
            "to an external browser. It never streams, downloads or modifies YouTube content."
        ),
        lifespan=lifespan,
        docs_url="/docs" if settings.environment != "production" else None,
        redoc_url="/redoc" if settings.environment != "production" else None,
    )
    install_error_handlers(app)

    if settings.cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins,
            allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
            allow_headers=["Authorization", "Content-Type"],
        )

    @app.middleware("http")
    async def request_context(
        request: Request, call_next: Callable[[Request], Awaitable[Response]]
    ) -> Response:
        request.state.request_id = request.headers.get("X-Request-ID") or uuid.uuid4().hex
        # Identify the caller early so rate limits key on the user, not the IP.
        token = bearer_token(request.headers.get("Authorization"))
        if token:
            try:
                request.state.user_id = str(decode_access_token(token, settings))
            except Exception:
                request.state.user_id = None
        response = await call_next(request)
        response.headers["X-Request-ID"] = request.state.request_id
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Cache-Control"] = "no-store"
        if settings.environment == "production":
            response.headers["Strict-Transport-Security"] = "max-age=63072000; includeSubDomains"
        return response

    @app.get("/health", tags=["health"])
    async def health(request: Request) -> dict[str, object]:
        checks: dict[str, str] = {}
        try:
            async with request.app.state.engine.connect() as conn:
                await conn.execute(text("SELECT 1"))
            checks["database"] = "ok"
        except Exception:
            checks["database"] = "unavailable"
        checks["cache"] = "ok" if await request.app.state.store.ping() else "unavailable"
        provider = request.app.state.search_service.provider
        checks["youtube"] = "ok" if getattr(provider, "configured", True) else "not_configured"
        healthy = checks["database"] == "ok" and checks["youtube"] == "ok"
        return {
            "status": "ok" if healthy else "degraded",
            "version": app.version,
            "metadata_provider": request.app.state.search_service.provider.name,
            "ai_planner": "llm" if request.app.state.planner.uses_llm else "heuristic",
            "checks": checks,
        }

    app.include_router(v1_router)
    return app


app = create_app()
