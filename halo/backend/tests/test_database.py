"""Database engine regressions."""

from __future__ import annotations

from pathlib import Path

import pytest
from sqlalchemy import text
from sqlalchemy.pool import StaticPool

from app.db.base import Base
from app.db.session import _is_in_memory, create_engine, create_session_factory
from app.models import User, UserPreferences


async def test_one_requests_rollback_never_undoes_another_requests_signup(tmp_path: Path) -> None:
    """Regression: on a file database, every session shared one connection, so a failing
    request's rollback erased a concurrent sign-up's user and its preferences insert failed
    with "FOREIGN KEY constraint failed"."""
    engine = create_engine(f"sqlite+aiosqlite:///{tmp_path / 'halo.sqlite3'}")
    assert not isinstance(engine.pool, StaticPool)
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    factory = create_session_factory(engine)
    async with factory() as signup, factory() as failing:
        user = User(display_name=None)
        signup.add(user)
        await signup.flush()
        await failing.execute(text("select 1"))
        await failing.rollback()  # e.g. an unauthenticated request ending in 401
        signup.add(UserPreferences(user_id=user.id))
        await signup.commit()
    async with factory() as check:
        assert await check.get(User, user.id) is not None
    await engine.dispose()


@pytest.mark.parametrize(
    ("url", "in_memory"),
    [
        ("sqlite+aiosqlite://", True),
        ("sqlite+aiosqlite:///:memory:", True),
        ("sqlite+aiosqlite:///file:db?mode=memory&cache=shared&uri=true", True),
        ("sqlite+aiosqlite:///./halo-local.sqlite3", False),
        ("sqlite+aiosqlite:////tmp/e2e.sqlite3", False),
    ],
)
def test_only_in_memory_databases_share_a_connection(url: str, in_memory: bool) -> None:
    assert _is_in_memory(url) is in_memory
