"""Refresh or purge stored track metadata older than the provider retention window.

YouTube API Services Developer Policies require non-authorized API data to be refreshed
or deleted within 30 days. Run this daily (cron, Kubernetes CronJob, etc.):

    python -m app.tasks.refresh_metadata
"""

from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import TrackReference
from app.services.youtube.base import MetadataProvider

logger = logging.getLogger("muse.tasks.refresh")

REFRESH_AFTER = timedelta(days=25)  # refresh comfortably inside the 30-day window
BATCH_SIZE = 50


@dataclass(slots=True)
class RefreshReport:
    refreshed: int = 0
    marked_unavailable: int = 0


async def refresh_stale_tracks(
    session: AsyncSession, provider: MetadataProvider, *, now: datetime | None = None
) -> RefreshReport:
    now = now or datetime.now(UTC)
    cutoff = now - REFRESH_AFTER
    report = RefreshReport()
    while True:
        stale = list(
            (
                await session.execute(
                    select(TrackReference)
                    .where(
                        TrackReference.provider == provider.name,
                        TrackReference.metadata_fetched_at < cutoff,
                    )
                    .limit(BATCH_SIZE)
                )
            ).scalars()
        )
        if not stale:
            break
        fresh = await provider.get_videos([t.provider_id for t in stale])
        for ref in stale:
            track = fresh.get(ref.provider_id)
            ref.metadata_fetched_at = now
            if track is None:
                # Keep the id (the user's playlist entry) but drop cached metadata.
                ref.is_available = False
                ref.title = "Unavailable video"
                ref.channel_title = "Unavailable"
                ref.thumbnail_url = None
                ref.duration_seconds = None
                report.marked_unavailable += 1
            else:
                ref.is_available = True
                ref.title = track.title[:300]
                ref.channel_title = track.channel_title[:200]
                ref.thumbnail_url = track.best_thumbnail
                ref.duration_seconds = track.duration_seconds
                report.refreshed += 1
        await session.commit()
    return report


async def _main() -> None:
    from app.core.config import get_settings
    from app.db.session import create_engine, create_session_factory
    from app.services.youtube.service import build_provider

    settings = get_settings()
    engine = create_engine(settings.database_url)
    provider = build_provider(settings)
    try:
        async with create_session_factory(engine)() as session:
            report = await refresh_stale_tracks(session, provider)
        logger.info("refreshed=%d unavailable=%d", report.refreshed, report.marked_unavailable)
    finally:
        await provider.aclose()
        await engine.dispose()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    asyncio.run(_main())
