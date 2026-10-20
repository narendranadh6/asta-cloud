"""Backend for iOS UI tests: the real API with the test YouTube stand-in.

    python -m tests.e2e_server   # serves http://127.0.0.1:8000

Test infrastructure only (CI simulator runs). Uses SQLite and in-process caching.
"""

from __future__ import annotations

import asyncio

import uvicorn

from app.core.cache import MemoryStore
from app.core.config import Settings
from app.db.base import Base
from app.db.session import create_engine
from app.main import create_app
from tests.fakes import FakeMetadataProvider

DATABASE_URL = "sqlite+aiosqlite:///./e2e.sqlite3"


async def _create_tables() -> None:
    engine = create_engine(DATABASE_URL)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    await engine.dispose()


async def main() -> None:
    await _create_tables()
    settings = Settings(
        environment="test",
        database_url=DATABASE_URL,
        redis_url=None,
        jwt_secret="e2e-secret-0123456789-0123456789-abcd",
    )
    app = create_app(settings, provider=FakeMetadataProvider(), store=MemoryStore())
    await uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=8000)).serve()


if __name__ == "__main__":
    asyncio.run(main())
