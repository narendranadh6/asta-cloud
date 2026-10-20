"""Refresh stored track metadata (titles, artwork, stream URLs) from each track's source.

Tracks removed at the source stay in playlists but are marked unavailable. Run daily
(cron, Kubernetes CronJob, etc.):

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
from app.services.catalog.ids import SOURCES, make_track_id
from app.services.catalog.service import CatalogService

logger = logging.getLogger("halo.tasks.refresh")

REFRESH_AFTER = timedelta(days=7)
BATCH_SIZE = 50


@dataclass(slots=True)
class RefreshReport:
    refreshed: int = 0
    marked_unavailable: int = 0


async def refresh_stale_tracks(
    session: AsyncSession, catalog: CatalogService, *, now: datetime | None = None
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
                        TrackReference.provider.in_(catalog.source_names),
                        TrackReference.provider.in_(SOURCES),
                        TrackReference.metadata_fetched_at < cutoff,
                    )
                    .limit(BATCH_SIZE)
                )
            ).scalars()
        )
        if not stale:
            break
        ids = {make_track_id(r.provider, r.provider_id): r for r in stale}  # type: ignore[arg-type]
        fresh = await catalog.get_tracks(list(ids))
        for track_id, ref in ids.items():
            track = fresh.get(track_id)
            ref.metadata_fetched_at = now
            if track is None:
                # Keep the playlist entry, but it can no longer be played.
                ref.is_available = False
                ref.stream_url = None
                report.marked_unavailable += 1
            else:
                ref.is_available = True
                ref.title = track.title[:300]
                ref.artist = track.artist[:200]
                ref.album = track.album[:300] if track.album else None
                ref.artwork_url = track.artwork_url
                ref.stream_url = track.stream_url
                ref.is_preview = track.is_preview
                ref.duration_seconds = track.duration_seconds
                report.refreshed += 1
        await session.commit()
    return report


async def _main() -> None:
    from app.core.cache import MemoryStore
    from app.core.config import get_settings
    from app.db.session import create_engine, create_session_factory
    from app.services.catalog.service import build_catalog

    settings = get_settings()
    engine = create_engine(settings.database_url)
    catalog = build_catalog(settings, MemoryStore())
    try:
        async with create_session_factory(engine)() as session:
            report = await refresh_stale_tracks(session, catalog)
        logger.info("refreshed=%d unavailable=%d", report.refreshed, report.marked_unavailable)
    finally:
        await catalog.aclose()
        await engine.dispose()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    asyncio.run(_main())
