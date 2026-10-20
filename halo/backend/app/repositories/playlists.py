"""Playlist persistence. All queries are scoped to the owning user."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.errors import AppError, NotFoundError
from app.models import Playlist, PlaylistItem, RecommendationSession, TrackReference
from app.schemas import (
    PlaylistCreate,
    PlaylistDetail,
    PlaylistItemOut,
    PlaylistSummary,
    PlaylistUpdate,
    Track,
)
from app.services.catalog.ids import make_track_id

MAX_PLAYLIST_ITEMS = 500


async def upsert_track(session: AsyncSession, track: Track) -> TrackReference:
    ref = (
        await session.execute(
            select(TrackReference).where(
                TrackReference.provider == track.source,
                TrackReference.provider_id == track.source_id,
            )
        )
    ).scalar_one_or_none()
    if ref is None:
        ref = TrackReference(provider=track.source, provider_id=track.source_id)
        session.add(ref)
    ref.title = track.title[:300]
    ref.artist = track.artist[:200]
    ref.album = track.album[:300] if track.album else None
    ref.artwork_url = track.artwork_url[:500] if track.artwork_url else None
    ref.stream_url = track.stream_url[:1000] if track.stream_url else None
    ref.is_preview = track.is_preview
    ref.duration_seconds = track.duration_seconds
    ref.metadata_fetched_at = datetime.now(UTC)
    ref.is_available = True
    await session.flush()
    return ref


async def _load(session: AsyncSession, user_id: uuid.UUID, playlist_id: uuid.UUID) -> Playlist:
    playlist = (
        await session.execute(
            select(Playlist)
            .where(Playlist.id == playlist_id)
            .options(selectinload(Playlist.items).joinedload(PlaylistItem.track))
            .execution_options(populate_existing=True)
        )
    ).scalar_one_or_none()
    # Same response for "missing" and "someone else's" so ids cannot be probed.
    if playlist is None or playlist.user_id != user_id:
        raise NotFoundError("Playlist not found")
    return playlist


def _item_out(item: PlaylistItem) -> PlaylistItemOut:
    track = item.track
    return PlaylistItemOut(
        id=item.id,
        position=item.position,
        note=item.note,
        track_id=make_track_id(track.provider, track.provider_id),  # type: ignore[arg-type]
        title=track.title,
        artist=track.artist,
        album=track.album,
        artwork_url=track.artwork_url,
        duration_seconds=track.duration_seconds,
        stream_url=track.stream_url,
        is_preview=track.is_preview,
        is_available=track.is_available,
        added_at=item.created_at,
    )


def _summary_fields(playlist: Playlist, items: list[PlaylistItem]) -> dict[str, object]:
    return {
        "id": playlist.id,
        "name": playlist.name,
        "description": playlist.description,
        "mood": playlist.mood,
        "is_ai_generated": playlist.is_ai_generated,
        "item_count": len(items),
        "total_duration_seconds": sum(i.track.duration_seconds or 0 for i in items),
        "artwork_url": next((i.track.artwork_url for i in items if i.track.artwork_url), None),
        "created_at": playlist.created_at,
        "updated_at": playlist.updated_at,
    }


def to_detail(playlist: Playlist) -> PlaylistDetail:
    items = sorted(playlist.items, key=lambda i: i.position)
    return PlaylistDetail(
        **_summary_fields(playlist, items),  # type: ignore[arg-type]
        items=[_item_out(i) for i in items],
    )


async def list_playlists(
    session: AsyncSession, user_id: uuid.UUID, limit: int, offset: int
) -> tuple[list[PlaylistSummary], int]:
    total = (
        await session.execute(select(func.count(Playlist.id)).where(Playlist.user_id == user_id))
    ).scalar_one()
    rows = (
        (
            await session.execute(
                select(Playlist)
                .where(Playlist.user_id == user_id)
                .options(selectinload(Playlist.items).joinedload(PlaylistItem.track))
                .order_by(Playlist.updated_at.desc())
                .limit(limit)
                .offset(offset)
            )
        )
        .scalars()
        .unique()
    )
    summaries = [
        PlaylistSummary(**_summary_fields(p, sorted(p.items, key=lambda i: i.position)))  # type: ignore[arg-type]
        for p in rows
    ]
    return summaries, int(total)


async def get_playlist(
    session: AsyncSession, user_id: uuid.UUID, playlist_id: uuid.UUID
) -> PlaylistDetail:
    return to_detail(await _load(session, user_id, playlist_id))


async def create_playlist(
    session: AsyncSession,
    user_id: uuid.UUID,
    body: PlaylistCreate,
    tracks: list[Track],
) -> PlaylistDetail:
    session_id = body.recommendation_session_id
    if session_id is not None:
        rec = await session.get(RecommendationSession, session_id)
        if rec is None or rec.user_id != user_id:
            session_id = None
    playlist = Playlist(
        user_id=user_id,
        name=body.name,
        description=body.description,
        mood=body.mood,
        is_ai_generated=body.is_ai_generated,
        recommendation_session_id=session_id,
    )
    session.add(playlist)
    await session.flush()
    for position, track in enumerate(tracks):
        ref = await upsert_track(session, track)
        session.add(PlaylistItem(playlist_id=playlist.id, track_id=ref.id, position=position))
    await session.flush()
    return await get_playlist(session, user_id, playlist.id)


async def update_playlist(
    session: AsyncSession, user_id: uuid.UUID, playlist_id: uuid.UUID, body: PlaylistUpdate
) -> PlaylistDetail:
    playlist = await _load(session, user_id, playlist_id)
    for field in body.model_fields_set:
        setattr(playlist, field, getattr(body, field))
    playlist.updated_at = datetime.now(UTC)
    await session.flush()
    return to_detail(playlist)


async def delete_playlist(
    session: AsyncSession, user_id: uuid.UUID, playlist_id: uuid.UUID
) -> None:
    playlist = await _load(session, user_id, playlist_id)
    await session.delete(playlist)
    await session.flush()


def _renumber(items: list[PlaylistItem]) -> None:
    for index, item in enumerate(items):
        item.position = index


async def add_item(
    session: AsyncSession,
    user_id: uuid.UUID,
    playlist_id: uuid.UUID,
    track: Track,
    position: int | None,
    note: str | None,
) -> PlaylistDetail:
    playlist = await _load(session, user_id, playlist_id)
    items = sorted(playlist.items, key=lambda i: i.position)
    if len(items) >= MAX_PLAYLIST_ITEMS:
        raise AppError(
            f"A playlist can hold at most {MAX_PLAYLIST_ITEMS} songs", code="playlist_full"
        )
    ref = await upsert_track(session, track)
    item = PlaylistItem(playlist_id=playlist.id, track_id=ref.id, position=len(items), note=note)
    item.track = ref
    index = len(items) if position is None else min(position, len(items))
    items.insert(index, item)
    playlist.items.append(item)
    _renumber(items)
    playlist.updated_at = datetime.now(UTC)
    await session.flush()
    return await get_playlist(session, user_id, playlist_id)


async def remove_item(
    session: AsyncSession, user_id: uuid.UUID, playlist_id: uuid.UUID, item_id: uuid.UUID
) -> PlaylistDetail:
    playlist = await _load(session, user_id, playlist_id)
    target = next((i for i in playlist.items if i.id == item_id), None)
    if target is None:
        raise NotFoundError("Playlist item not found")
    playlist.items.remove(target)
    await session.delete(target)
    _renumber(sorted(playlist.items, key=lambda i: i.position))
    playlist.updated_at = datetime.now(UTC)
    await session.flush()
    return await get_playlist(session, user_id, playlist_id)


async def reorder_items(
    session: AsyncSession, user_id: uuid.UUID, playlist_id: uuid.UUID, item_ids: list[uuid.UUID]
) -> PlaylistDetail:
    playlist = await _load(session, user_id, playlist_id)
    current = {i.id: i for i in playlist.items}
    if len(item_ids) != len(set(item_ids)) or set(item_ids) != set(current):
        raise AppError(
            "item_ids must list every item in the playlist exactly once",
            code="invalid_reorder",
            status_code=422,
        )
    _renumber([current[i] for i in item_ids])
    playlist.updated_at = datetime.now(UTC)
    await session.flush()
    return to_detail(playlist)
