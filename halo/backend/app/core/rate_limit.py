"""Fixed-window rate limiting keyed by authenticated user, or client IP as a fallback."""

from __future__ import annotations

import logging
from collections.abc import Awaitable, Callable

from fastapi import Request

from app.core.errors import RateLimitedError

logger = logging.getLogger("halo.ratelimit")

WINDOW_SECONDS = 60


def client_identity(request: Request) -> str:
    user_id = getattr(request.state, "user_id", None)
    if user_id:
        return f"user:{user_id}"
    # Behind a trusted proxy, configure uvicorn --proxy-headers so client.host is real.
    host = request.client.host if request.client else "unknown"
    return f"ip:{host}"


async def enforce_rate_limit(request: Request, bucket: str, limit_per_minute: int) -> None:
    if limit_per_minute <= 0:
        return
    store = request.app.state.store
    key = f"rl:{bucket}:{client_identity(request)}"
    try:
        count, reset_in = await store.incr_window(key, WINDOW_SECONDS)
    except Exception:
        # Fail open on store outages: availability over strictness for a music app,
        # while upstream quota is still protected by the YouTube cache.
        logger.warning("rate limit store unavailable", exc_info=True)
        return
    if count > limit_per_minute:
        raise RateLimitedError(
            "Too many requests. Please slow down and try again shortly.",
            details={"bucket": bucket, "limit_per_minute": limit_per_minute,
                     "retry_after_seconds": reset_in},
            headers={"Retry-After": str(reset_in)},
        )


def rate_limit(bucket: str, setting_name: str) -> Callable[[Request], Awaitable[None]]:
    """FastAPI dependency factory. The limit is read from settings at request time."""

    async def _dependency(request: Request) -> None:
        limit = int(getattr(request.app.state.settings, setting_name))
        await enforce_rate_limit(request, bucket, limit)

    return _dependency
