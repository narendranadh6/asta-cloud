"""Async engine and session factory."""

from __future__ import annotations

from collections.abc import AsyncIterator

from sqlalchemy import event
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.pool import StaticPool


def create_engine(database_url: str) -> AsyncEngine:
    if database_url.startswith("sqlite"):
        if _is_in_memory(database_url):
            # In-memory SQLite (tests) only exists on one connection, so it is shared.
            engine = create_async_engine(
                database_url,
                connect_args={"check_same_thread": False},
                poolclass=StaticPool,
            )
        else:
            # A file database gets a connection per session. Sharing one connection lets one
            # request's rollback undo another's uncommitted work (a sign-up's new user vanished
            # and its preferences insert failed with "FOREIGN KEY constraint failed").
            # Concurrent writers wait for SQLite's lock instead of failing at once.
            engine = create_async_engine(database_url, connect_args={"timeout": 30})

        @event.listens_for(engine.sync_engine, "connect")
        def _enable_foreign_keys(dbapi_connection, _record):  # type: ignore[no-untyped-def]
            cursor = dbapi_connection.cursor()
            cursor.execute("PRAGMA foreign_keys=ON")
            cursor.close()

        return engine
    return create_async_engine(database_url, pool_pre_ping=True, pool_size=10, max_overflow=10)


def _is_in_memory(database_url: str) -> bool:
    path = database_url.split("://", 1)[-1].lstrip("/").split("?", 1)[0]
    return path in ("", ":memory:") or "mode=memory" in database_url


def create_session_factory(engine: AsyncEngine) -> async_sessionmaker[AsyncSession]:
    return async_sessionmaker(engine, expire_on_commit=False, autoflush=False)


async def session_scope(factory: async_sessionmaker[AsyncSession]) -> AsyncIterator[AsyncSession]:
    async with factory() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
