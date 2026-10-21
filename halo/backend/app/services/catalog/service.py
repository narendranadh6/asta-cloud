"""One searchable catalog over every enabled source.

Sources are queried concurrently; a slow or failing source is skipped with a warning rather
than failing the search. Results are merged and ranked: text relevance first, full songs above
30-second previews, then popularity. Track metadata (never audio) is cached.
"""

from __future__ import annotations

import asyncio
import hashlib
import logging
import math
import re
from dataclasses import dataclass

from app.core.cache import KeyValueStore
from app.schemas import AlbumPage, ArtistPage, SearchKind, Track
from app.services.catalog.base import (
    CatalogNotConfiguredError,
    CatalogSource,
    CatalogUnavailableError,
    EntityUnavailableError,
    SearchPage,
    TrackUnavailableError,
)
from app.services.catalog.ids import is_valid_track_id, parse_track_id

logger = logging.getLogger("halo.catalog")

SOURCE_TIMEOUT_SECONDS = 6.0
_WORD = re.compile(r"[\w']+", re.UNICODE)


def _words(text: str) -> set[str]:
    return {w.casefold() for w in _WORD.findall(text)}


def _clean_title(title: str) -> str:
    return re.sub(r"\s*[\(\[].*?[\)\]]", "", title).strip()


def song_key(track: Track) -> str:
    """Same song from different sources (or re-uploads) shares a key."""
    title = _clean_title(track.title)
    return f"{' '.join(sorted(_words(track.artist)))}|{' '.join(sorted(_words(title)))}"


def relevance(track: Track, query: str, kind: SearchKind) -> float:
    terms = _words(query)
    if not terms:
        return 0.0
    title, artist = _words(track.title), _words(track.artist)
    title_hits = len(terms & title) / len(terms)
    artist_hits = len(terms & artist) / len(terms)
    score = (
        (0.4 * title_hits + 0.6 * artist_hits)
        if kind == "artist"
        else (0.6 * title_hits + 0.4 * artist_hits)
    )
    if " ".join(query.casefold().split()) == _clean_title(track.title).casefold():
        score += 0.3
    return score


def rank(tracks: list[Track], query: str, kind: SearchKind) -> list[Track]:
    """Order by relevance, full songs above previews, then popularity. When several sources
    carry the same song, the full song is kept and its previews are dropped."""

    def key(track: Track) -> float:
        popularity = math.log10((track.play_count or 0) + 1) / 7  # ~0..1
        full = 0.0 if track.is_preview else 0.25
        return relevance(track, query, kind) + full + 0.1 * popularity

    best: dict[str, tuple[float, Track]] = {}
    for track in tracks:
        dedupe, score = song_key(track), key(track)
        current = best.get(dedupe)
        if current is None:
            best[dedupe] = (score, track)
            continue
        current_score, current_track = current
        # A full song always beats a preview of it; otherwise the better score wins.
        if (current_track.is_preview and not track.is_preview) or (
            current_track.is_preview == track.is_preview and score > current_score
        ):
            best[dedupe] = (score, track)
    return [t for _, t in sorted(best.values(), key=lambda item: item[0], reverse=True)]


@dataclass(slots=True)
class CachedSearch:
    page: SearchPage
    cached: bool


class CatalogService:
    def __init__(
        self,
        sources: list[CatalogSource],
        store: KeyValueStore,
        *,
        search_ttl_seconds: int = 6 * 3600,
        track_ttl_seconds: int = 24 * 3600,
        timeout: float = SOURCE_TIMEOUT_SECONDS,
    ) -> None:
        self.sources = {s.name: s for s in sources}
        self._store = store
        self._search_ttl = search_ttl_seconds
        self._track_ttl = track_ttl_seconds
        self._timeout = timeout

    @property
    def configured(self) -> bool:
        return bool(self.sources)

    @property
    def source_names(self) -> list[str]:
        return list(self.sources)

    def _key(self, *parts: str) -> str:
        digest = hashlib.sha256("|".join(parts).encode()).hexdigest()[:32]
        return f"catalog:{digest}"

    async def _gather(self, calls: dict[str, object]) -> tuple[dict[str, list[Track]], list[str]]:
        names = list(calls)
        results = await asyncio.gather(
            *(asyncio.wait_for(calls[n], self._timeout) for n in names),  # type: ignore[arg-type]
            return_exceptions=True,
        )
        ok: dict[str, list[Track]] = {}
        warnings: list[str] = []
        for name, result in zip(names, results, strict=True):
            if isinstance(result, BaseException):
                logger.warning("catalog source %s failed: %s", name, result)
                warnings.append(f"{name} is unavailable right now")
            else:
                ok[name] = list(result)  # type: ignore[arg-type]
        if not ok and calls:
            raise CatalogUnavailableError(
                "Music sources are unavailable right now. Try again soon."
            )
        return ok, warnings

    def _require_sources(self) -> None:
        if not self.sources:
            raise CatalogNotConfiguredError(
                "No music sources are enabled on the server (HALO_AUDIUS_ENABLED, "
                "HALO_JAMENDO_CLIENT_ID or HALO_ITUNES_PREVIEWS_ENABLED)."
            )

    async def _remember(self, tracks: list[Track]) -> None:
        for track in tracks:
            await self._store.set_json(
                self._key("track", track.id), track.model_dump(mode="json"), self._track_ttl
            )

    async def search(
        self,
        query: str,
        *,
        kind: SearchKind = "song",
        page_token: str | None = None,
        max_results: int = 20,
    ) -> CachedSearch:
        self._require_sources()
        cleaned = " ".join(query.split())[:150]
        offset = int(page_token) if page_token and page_token.isdigit() else 0
        key = self._key("search", kind, cleaned.casefold(), str(offset), str(max_results))
        cached = await self._store.get_json(key)
        if cached is not None:
            return CachedSearch(
                page=SearchPage(
                    items=[Track.model_validate(t) for t in cached["items"]],
                    next_page_token=cached.get("next"),
                    prev_page_token=cached.get("prev"),
                    sources=list(cached.get("sources") or []),
                ),
                cached=True,
            )
        per_source = max(5, max_results)
        found, warnings = await self._gather(
            {
                name: source.search(cleaned, limit=per_source, offset=offset)
                for name, source in self.sources.items()
            }
        )
        items = rank([t for tracks in found.values() for t in tracks], cleaned, kind)[:max_results]
        more = any(len(tracks) >= per_source for tracks in found.values())
        page = SearchPage(
            items=items,
            next_page_token=str(offset + per_source) if more else None,
            prev_page_token=str(max(0, offset - per_source)) if offset else None,
            sources=sorted(found),
            warnings=warnings,
        )
        await self._store.set_json(
            key,
            {
                "items": [t.model_dump(mode="json") for t in items],
                "next": page.next_page_token,
                "prev": page.prev_page_token,
                "sources": page.sources,
            },
            self._search_ttl,
        )
        await self._remember(items)
        return CachedSearch(page=page, cached=False)

    async def trending(self, *, max_results: int = 20, genre: str | None = None) -> CachedSearch:
        self._require_sources()
        key = self._key("trending", genre or "", str(max_results))
        cached = await self._store.get_json(key)
        if cached is not None:
            return CachedSearch(
                page=SearchPage(
                    items=[Track.model_validate(t) for t in cached["items"]],
                    sources=list(cached.get("sources") or []),
                ),
                cached=True,
            )
        full = {n: s for n, s in self.sources.items() if s.full_tracks}
        found, warnings = await self._gather(
            {name: s.trending(limit=max_results, genre=genre) for name, s in full.items()}
        )
        # Interleave sources so one doesn't dominate, keeping each source's own order.
        lists = [found[name] for name in sorted(found)]
        merged: list[Track] = []
        for index in range(max(map(len, lists), default=0)):
            merged.extend(tracks[index] for tracks in lists if index < len(tracks))
        page = SearchPage(items=merged[:max_results], sources=sorted(found), warnings=warnings)
        await self._store.set_json(
            key,
            {"items": [t.model_dump(mode="json") for t in page.items], "sources": page.sources},
            3600,  # charts change; refresh hourly
        )
        await self._remember(page.items)
        return CachedSearch(page=page, cached=False)

    async def get_tracks(self, track_ids: list[str]) -> dict[str, Track]:
        """Tracks that still exist and stream, keyed by Halo track id. Unknown ids are omitted."""
        valid = [tid for tid in dict.fromkeys(track_ids) if is_valid_track_id(tid)]
        found: dict[str, Track] = {}
        missing: dict[str, list[str]] = {}
        for tid in valid:
            cached = await self._store.get_json(self._key("track", tid))
            if cached is not None:
                found[tid] = Track.model_validate(cached)
                continue
            source, source_id = parse_track_id(tid)
            if source in self.sources:
                missing.setdefault(source, []).append(source_id)
        if missing:
            fetched, _ = await self._gather(
                {name: self._lookup(name, ids) for name, ids in missing.items()}
            )
            tracks = [t for ts in fetched.values() for t in ts]
            await self._remember(tracks)
            found.update({t.id: t for t in tracks})
        return found

    async def _lookup(self, source: str, ids: list[str]) -> list[Track]:
        return list((await self.sources[source].get_tracks(ids)).values())  # type: ignore[index]

    async def get_track(self, track_id: str) -> Track:
        if not is_valid_track_id(track_id):
            raise TrackUnavailableError("Invalid track id")
        tracks = await self.get_tracks([track_id])
        if track_id not in tracks:
            raise TrackUnavailableError("This song is no longer available from its source")
        return tracks[track_id]

    async def get_artist(self, artist_id: str) -> ArtistPage:
        raw = await self._entity("artist", artist_id)
        page = ArtistPage.model_validate(raw)
        return page

    async def get_album(self, album_id: str) -> AlbumPage:
        raw = await self._entity("album", album_id)
        return AlbumPage.model_validate(raw)

    async def _entity(self, kind: str, entity_id: str) -> dict[str, object]:
        """An artist or album page from its source, cached like track metadata."""
        self._require_sources()
        missing = EntityUnavailableError(f"This {kind} isn't available", kind)
        if not is_valid_track_id(entity_id):
            raise missing
        source_name, source_id = parse_track_id(entity_id)
        source = self.sources.get(source_name)
        if source is None:
            raise missing
        key = self._key(kind, entity_id)
        cached = await self._store.get_json(key)
        if cached is not None:
            return dict(cached)
        lookup = source.get_artist(source_id) if kind == "artist" else source.get_album(source_id)
        try:
            page = await asyncio.wait_for(lookup, self._timeout)
        except TimeoutError as exc:
            raise CatalogUnavailableError(f"{source_name} is unavailable right now") from exc
        if page is None:
            raise missing
        tracks = page.top_tracks if isinstance(page, ArtistPage) else page.tracks
        await self._remember(tracks)
        dumped = page.model_dump(mode="json")
        await self._store.set_json(key, dumped, self._search_ttl)
        return dumped

    async def aclose(self) -> None:
        for source in self.sources.values():
            await source.aclose()


def build_catalog(settings: object, store: KeyValueStore) -> CatalogService:
    from app.core.config import Settings
    from app.services.catalog.audius import AudiusSource
    from app.services.catalog.itunes import ITunesPreviewSource
    from app.services.catalog.jamendo import JamendoSource

    assert isinstance(settings, Settings)
    sources: list[CatalogSource] = []
    if settings.audius_enabled:
        key = settings.audius_api_key.get_secret_value() if settings.audius_api_key else None
        sources.append(AudiusSource(base_url=settings.audius_base_url, api_key=key or None))
    jamendo = settings.jamendo_client_id.get_secret_value() if settings.jamendo_client_id else ""
    if jamendo.strip():
        sources.append(JamendoSource(jamendo.strip()))
    if settings.itunes_previews_enabled:
        sources.append(ITunesPreviewSource(country=settings.itunes_country))
    if not sources:
        logger.error("No catalog sources enabled: search will return 503")
    return CatalogService(
        sources,
        store,
        search_ttl_seconds=settings.catalog_search_ttl_seconds,
        track_ttl_seconds=settings.catalog_track_ttl_seconds,
    )
