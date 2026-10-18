"""Key-value backend for caching and rate limiting.

Redis is used when configured and reachable. An in-process store is used for tests and
single-process development so the API still runs without Redis.
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from typing import Any, Protocol

logger = logging.getLogger("muse.cache")


class KeyValueStore(Protocol):
    async def get_json(self, key: str) -> Any | None: ...

    async def set_json(self, key: str, value: Any, ttl_seconds: int) -> None: ...

    async def incr_window(self, key: str, window_seconds: int) -> tuple[int, int]:
        """Increment a fixed-window counter. Returns (count, seconds_until_reset)."""
        ...

    async def delete_prefix(self, prefix: str) -> None: ...

    async def ping(self) -> bool: ...

    async def close(self) -> None: ...


class MemoryStore:
    def __init__(self) -> None:
        self._data: dict[str, tuple[float, Any]] = {}
        self._lock = asyncio.Lock()

    def _alive(self, key: str) -> Any | None:
        item = self._data.get(key)
        if item is None:
            return None
        expires_at, value = item
        if expires_at < time.monotonic():
            self._data.pop(key, None)
            return None
        return value

    async def get_json(self, key: str) -> Any | None:
        raw = self._alive(key)
        return None if raw is None else json.loads(raw)

    async def set_json(self, key: str, value: Any, ttl_seconds: int) -> None:
        if ttl_seconds <= 0:
            return
        self._data[key] = (time.monotonic() + ttl_seconds, json.dumps(value))

    async def incr_window(self, key: str, window_seconds: int) -> tuple[int, int]:
        async with self._lock:
            now = time.monotonic()
            item = self._data.get(key)
            if item is None or item[0] < now:
                self._data[key] = (now + window_seconds, 1)
                return 1, window_seconds
            expires_at, count = item
            self._data[key] = (expires_at, int(count) + 1)
            return int(count) + 1, max(1, int(expires_at - now))

    async def delete_prefix(self, prefix: str) -> None:
        for key in [k for k in self._data if k.startswith(prefix)]:
            self._data.pop(key, None)

    async def ping(self) -> bool:
        return True

    async def close(self) -> None:
        self._data.clear()


class RedisStore:
    def __init__(self, client: Any) -> None:
        self._client = client

    @classmethod
    def from_url(cls, url: str) -> RedisStore:
        from redis import asyncio as redis_asyncio

        return cls(redis_asyncio.from_url(url, decode_responses=True))

    async def get_json(self, key: str) -> Any | None:
        try:
            raw = await self._client.get(key)
        except Exception:  # cache failures must never break requests
            logger.warning("redis get failed", exc_info=True)
            return None
        return None if raw is None else json.loads(raw)

    async def set_json(self, key: str, value: Any, ttl_seconds: int) -> None:
        if ttl_seconds <= 0:
            return
        try:
            await self._client.set(key, json.dumps(value), ex=ttl_seconds)
        except Exception:
            logger.warning("redis set failed", exc_info=True)

    async def incr_window(self, key: str, window_seconds: int) -> tuple[int, int]:
        pipe = self._client.pipeline(transaction=True)
        pipe.incr(key)
        pipe.expire(key, window_seconds, nx=True)
        pipe.ttl(key)
        count, _, ttl = await pipe.execute()
        return int(count), max(1, int(ttl))

    async def delete_prefix(self, prefix: str) -> None:
        async for key in self._client.scan_iter(match=f"{prefix}*"):
            await self._client.delete(key)

    async def ping(self) -> bool:
        try:
            return bool(await self._client.ping())
        except Exception:
            return False

    async def close(self) -> None:
        await self._client.aclose()


def create_store(redis_url: str | None) -> KeyValueStore:
    if redis_url:
        return RedisStore.from_url(redis_url)
    return MemoryStore()
