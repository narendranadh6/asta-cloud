from __future__ import annotations

import os
from collections.abc import AsyncIterator, Callable
from typing import Any

import httpx
import pytest

from app.core.cache import MemoryStore
from app.core.config import Settings
from app.db.base import Base
from app.main import create_app
from app.services.ai.providers import IntentPlanner
from app.services.youtube.mock import DemoMetadataProvider

TEST_DATABASE_URL = os.environ.get("MUSE_TEST_DATABASE_URL", "sqlite+aiosqlite://")


def make_settings(**overrides: Any) -> Settings:
    base: dict[str, Any] = {
        "environment": "test",
        "database_url": TEST_DATABASE_URL,
        "redis_url": None,
        "youtube_provider": "mock",
        "llm_provider": "none",
        "jwt_secret": "test-secret-0123456789-0123456789-abcdef",
        "rate_limit_search_per_minute": 1000,
        "rate_limit_ai_per_minute": 1000,
        "rate_limit_default_per_minute": 1000,
        "rate_limit_auth_per_minute": 1000,
    }
    base.update(overrides)
    return Settings(**base)


AppFactory = Callable[..., Any]


@pytest.fixture
async def app_factory() -> AsyncIterator[AppFactory]:
    contexts: list[Any] = []

    async def _make(
        settings: Settings | None = None,
        provider: Any = None,
        planner: IntentPlanner | None = None,
    ) -> tuple[Any, httpx.AsyncClient]:
        app = create_app(
            settings or make_settings(),
            provider=provider or DemoMetadataProvider(),
            planner=planner or IntentPlanner(None),
            store=MemoryStore(),
        )
        ctx = app.router.lifespan_context(app)
        await ctx.__aenter__()
        contexts.append(ctx)
        async with app.state.engine.begin() as conn:
            await conn.run_sync(Base.metadata.drop_all)
            await conn.run_sync(Base.metadata.create_all)
        client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://testserver"
        )
        return app, client

    yield _make
    for ctx in reversed(contexts):
        await ctx.__aexit__(None, None, None)


@pytest.fixture
async def client(app_factory: AppFactory) -> AsyncIterator[httpx.AsyncClient]:
    _, http = await app_factory()
    async with http:
        yield http


async def register(client: httpx.AsyncClient) -> dict[str, str]:
    response = await client.post("/api/v1/auth/register", json={})
    assert response.status_code == 201, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


@pytest.fixture
async def auth(client: httpx.AsyncClient) -> dict[str, str]:
    return await register(client)
