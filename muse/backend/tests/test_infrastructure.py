"""Cache/rate-limit stores, metadata retention and production config guards."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import fakeredis
import pytest
from sqlalchemy import select

from app.core.cache import MemoryStore, RedisStore
from app.core.config import YOUTUBE_MAX_RETENTION_SECONDS, Settings
from app.models import TrackReference
from app.services.youtube.mock import DemoMetadataProvider
from app.tasks.refresh_metadata import refresh_stale_tracks
from tests.conftest import AppFactory, register


@pytest.mark.parametrize("kind", ["memory", "redis"])
async def test_store_window_counter_and_json(kind: str) -> None:
    store = (
        MemoryStore() if kind == "memory"
        else RedisStore(fakeredis.FakeAsyncRedis(decode_responses=True))
    )
    assert [(await store.incr_window("k", 60))[0] for _ in range(3)] == [1, 2, 3]
    _, reset = await store.incr_window("k", 60)
    assert 0 < reset <= 60
    await store.set_json("j", {"a": [1, 2]}, 30)
    assert await store.get_json("j") == {"a": [1, 2]}
    await store.set_json("zero", {"x": 1}, 0)  # TTL 0 means "do not cache"
    assert await store.get_json("zero") is None
    await store.delete_prefix("j")
    assert await store.get_json("j") is None
    assert await store.ping()


def test_cache_ttl_clamped_to_youtube_retention_limit() -> None:
    settings = Settings(youtube_video_cache_ttl_seconds=10**9, youtube_search_cache_ttl_seconds=-5)
    assert settings.youtube_video_cache_ttl_seconds == YOUTUBE_MAX_RETENTION_SECONDS
    assert settings.youtube_search_cache_ttl_seconds == 0


def test_production_config_guard() -> None:
    with pytest.raises(RuntimeError, match="MUSE_JWT_SECRET"):
        Settings(environment="production").validate_for_production()
    with pytest.raises(RuntimeError, match="YOUTUBE_API_KEY"):
        Settings(
            environment="production", jwt_secret="x" * 40, youtube_provider="youtube"
        ).validate_for_production()
    Settings(environment="production", jwt_secret="x" * 40).validate_for_production()


async def test_refresh_stale_track_metadata(app_factory: AppFactory) -> None:
    app, client = await app_factory()
    async with client:
        auth = await register(client)
        search = await client.get("/api/v1/search", params={"q": "tamil", "limit": 1},
                                  headers=auth)
        video_id = search.json()["items"][0]["video_id"]
        await client.post("/api/v1/playlists", json={"name": "r", "video_ids": [video_id]},
                          headers=auth)
    factory = app.state.session_factory
    old = datetime.now(UTC) - timedelta(days=40)
    async with factory() as session:
        ref = (await session.execute(select(TrackReference))).scalar_one()
        ref.metadata_fetched_at = old
        session.add(TrackReference(
            provider="demo", provider_id="demoGoneXYZ", title="t", channel_title="c",
            metadata_fetched_at=old,
        ))
        await session.commit()
    async with factory() as session:
        report = await refresh_stale_tracks(session, DemoMetadataProvider())
    assert (report.refreshed, report.marked_unavailable) == (1, 1)
    async with factory() as session:
        gone = (await session.execute(
            select(TrackReference).where(TrackReference.provider_id == "demoGoneXYZ")
        )).scalar_one()
        assert gone.is_available is False and gone.thumbnail_url is None
        assert gone.metadata_fetched_at.replace(tzinfo=UTC) > old.replace(tzinfo=UTC)
