"""Cache/rate-limit stores, metadata retention and production config guards."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import fakeredis
import pytest
from sqlalchemy import select

from app.core.cache import MemoryStore, RedisStore
from app.core.config import CATALOG_MAX_CACHE_SECONDS, Settings
from app.models import TrackReference
from app.services.catalog.service import CatalogService
from app.tasks.refresh_metadata import refresh_stale_tracks
from tests.conftest import AppFactory, register
from tests.fakes import FakeCatalogSource


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


def test_cache_ttl_clamped() -> None:
    settings = Settings(catalog_track_ttl_seconds=10**9, catalog_search_ttl_seconds=-5)
    assert settings.catalog_track_ttl_seconds == CATALOG_MAX_CACHE_SECONDS
    assert settings.catalog_search_ttl_seconds == 0


def test_production_config_guard() -> None:
    with pytest.raises(RuntimeError, match="HALO_JWT_SECRET"):
        Settings(environment="production").validate_for_production()
    with pytest.raises(RuntimeError, match="music source"):
        Settings(
            environment="production",
            jwt_secret="x" * 40,
            audius_enabled=False,
            itunes_previews_enabled=False,
        ).validate_for_production()
    Settings(environment="production", jwt_secret="x" * 40).validate_for_production()


async def test_refresh_stale_track_metadata(app_factory: AppFactory) -> None:
    app, client = await app_factory()
    async with client:
        auth = await register(client)
        search = await client.get("/api/v1/search", params={"q": "tamil", "limit": 1},
                                  headers=auth)
        track_id = search.json()["items"][0]["id"]
        await client.post("/api/v1/playlists", json={"name": "r", "track_ids": [track_id]},
                          headers=auth)
    factory = app.state.session_factory
    old = datetime.now(UTC) - timedelta(days=40)
    async with factory() as session:
        ref = (await session.execute(select(TrackReference))).scalar_one()
        ref.metadata_fetched_at = old
        session.add(TrackReference(
            provider="audius", provider_id="tstGoneXYZ1", title="t", artist="c",
            stream_url="https://stream.test/gone.mp3", metadata_fetched_at=old,
        ))
        await session.commit()
    async with factory() as session:
        catalog = CatalogService([FakeCatalogSource()], app.state.store)
        report = await refresh_stale_tracks(session, catalog)
    assert (report.refreshed, report.marked_unavailable) == (1, 1)
    async with factory() as session:
        gone = (await session.execute(
            select(TrackReference).where(TrackReference.provider_id == "tstGoneXYZ1")
        )).scalar_one()
        assert gone.is_available is False and gone.stream_url is None
        assert gone.metadata_fetched_at.replace(tzinfo=UTC) > old.replace(tzinfo=UTC)
