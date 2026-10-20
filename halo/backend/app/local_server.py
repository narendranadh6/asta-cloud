"""Run Halo on one machine without Docker, PostgreSQL or Redis.

    python -m app.local_server            # http://127.0.0.1:8000

Uses real music sources (Audius, plus Jamendo when HALO_JAMENDO_CLIENT_ID is set, plus iTunes
previews), a local SQLite file and an in-process cache. Settings still come from the
environment or a .env file; HALO_DATABASE_URL and HALO_REDIS_URL override the local defaults.
For production use the Docker image with PostgreSQL and Redis instead.
"""

from __future__ import annotations

import asyncio
import os

import uvicorn

from app.core.config import Settings
from app.db.base import Base
from app.db.session import create_engine
from app.main import create_app

DEFAULT_DATABASE_URL = "sqlite+aiosqlite:///./halo-local.sqlite3"


async def _create_tables(database_url: str) -> None:
    engine = create_engine(database_url)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    await engine.dispose()


def local_settings() -> Settings:
    overrides: dict[str, object] = {}
    if "HALO_DATABASE_URL" not in os.environ:
        overrides["database_url"] = DEFAULT_DATABASE_URL
    if "HALO_REDIS_URL" not in os.environ:
        overrides["redis_url"] = None
    return Settings(**overrides)  # type: ignore[arg-type]


async def main(host: str = "127.0.0.1", port: int = 8000) -> None:
    settings = local_settings()
    if settings.database_url.startswith("sqlite"):
        await _create_tables(settings.database_url)
    app = create_app(settings)
    await uvicorn.Server(uvicorn.Config(app, host=host, port=port)).serve()


if __name__ == "__main__":
    asyncio.run(main(port=int(os.environ.get("HALO_PORT", "8000"))))
