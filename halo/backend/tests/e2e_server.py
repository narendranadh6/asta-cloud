"""Backend for the iOS UI tests in CI: the real local server with real music sources.

    python -m tests.e2e_server   # serves http://127.0.0.1:8000

Uses a fresh SQLite database each run. The CI runners have internet access, so the
screenshot tour shows real Audius and iTunes data.
"""

from __future__ import annotations

import asyncio
import os

os.environ.setdefault("HALO_DATABASE_URL", "sqlite+aiosqlite:///./e2e.sqlite3")
os.environ.setdefault("HALO_JWT_SECRET", "e2e-secret-0123456789-0123456789-abcd")

if __name__ == "__main__":
    from app.local_server import main

    if os.path.exists("e2e.sqlite3"):
        os.remove("e2e.sqlite3")
    asyncio.run(main())
