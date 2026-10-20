"""Similar-artist graphs from open music APIs.

Used for candidate generation ("fans of X also listen to Y"), the same idea as the
artist-similarity signals described for Spotify and Last.fm. Only artist *names* are
taken from these services; every playable track still comes from the verified catalog
results.

* Last.fm ``artist.getSimilar`` (free API key): https://www.last.fm/api/show/artist.getSimilar
* Deezer ``/artist/{id}/related`` (no key): https://developers.deezer.com/api/artist/related
"""

from __future__ import annotations

import hashlib
import logging
from dataclasses import dataclass
from typing import Any, Protocol

import httpx

from app.core.cache import KeyValueStore

logger = logging.getLogger("halo.similar_artists")

CACHE_TTL_SECONDS = 7 * 24 * 3600  # artist graphs change slowly


@dataclass(frozen=True, slots=True)
class SimilarArtist:
    name: str
    score: float  # 0..1, higher is more similar
    source: str


class SimilarArtistProvider(Protocol):
    name: str

    async def similar(self, artist: str, *, limit: int = 10) -> list[SimilarArtist]: ...

    async def aclose(self) -> None: ...


class NoSimilarArtists:
    name = "none"

    async def similar(self, artist: str, *, limit: int = 10) -> list[SimilarArtist]:
        return []

    async def aclose(self) -> None:
        return None


class LastFmSimilarArtists:
    name = "lastfm"

    def __init__(
        self, api_key: str, *, http_client: httpx.AsyncClient | None = None, timeout: float = 6.0
    ) -> None:
        self._key = api_key
        self._client = http_client or httpx.AsyncClient(
            base_url="https://ws.audioscrobbler.com/2.0/",
            timeout=timeout,
            headers={"User-Agent": "Halo/0.1 (+https://github.com/narendranadh6/asta-cloud)"},
        )

    async def similar(self, artist: str, *, limit: int = 10) -> list[SimilarArtist]:
        response = await self._client.get(
            "",
            params={
                "method": "artist.getsimilar",
                "artist": artist,
                "api_key": self._key,
                "format": "json",
                "limit": limit,
                "autocorrect": 1,
            },
        )
        if response.status_code != 200:
            return []
        data: dict[str, Any] = response.json()
        items = data.get("similarartists", {}).get("artist", [])
        out: list[SimilarArtist] = []
        for item in items[:limit]:
            name = str(item.get("name", "")).strip()
            try:
                score = float(item.get("match", 0))
            except (TypeError, ValueError):
                score = 0.0
            if name:
                out.append(
                    SimilarArtist(name=name, score=max(0.0, min(score, 1.0)), source=self.name)
                )
        return out

    async def aclose(self) -> None:
        await self._client.aclose()


class DeezerRelatedArtists:
    name = "deezer"

    def __init__(
        self, *, http_client: httpx.AsyncClient | None = None, timeout: float = 6.0
    ) -> None:
        self._client = http_client or httpx.AsyncClient(
            base_url="https://api.deezer.com", timeout=timeout
        )

    async def similar(self, artist: str, *, limit: int = 10) -> list[SimilarArtist]:
        found = await self._client.get("/search/artist", params={"q": artist, "limit": 1})
        if found.status_code != 200:
            return []
        hits = found.json().get("data", [])
        if not hits:
            return []
        related = await self._client.get(
            f"/artist/{int(hits[0]['id'])}/related", params={"limit": limit}
        )
        if related.status_code != 200:
            return []
        items = related.json().get("data", [])[:limit]
        # Deezer returns related artists ordered by relevance without a score.
        return [
            SimilarArtist(
                name=str(item["name"]),
                score=round(1.0 - i / max(len(items), 1), 3),
                source=self.name,
            )
            for i, item in enumerate(items)
            if item.get("name")
        ]

    async def aclose(self) -> None:
        await self._client.aclose()


class CachedSimilarArtists:
    """Tries providers in order, caches results, and never raises."""

    def __init__(self, providers: list[SimilarArtistProvider], store: KeyValueStore) -> None:
        self._providers = providers
        self._store = store
        self.name = "+".join(p.name for p in providers) or "none"

    async def similar(self, artist: str, *, limit: int = 10) -> list[SimilarArtist]:
        cleaned = " ".join(artist.split())[:100]
        if not cleaned or not self._providers:
            return []
        key = (
            "sim:"
            + hashlib.sha256(f"{self.name}|{cleaned.lower()}|{limit}".encode()).hexdigest()[:32]
        )
        cached = await self._store.get_json(key)
        if cached is not None:
            return [SimilarArtist(**item) for item in cached]
        for provider in self._providers:
            try:
                result = await provider.similar(cleaned, limit=limit)
            except (httpx.HTTPError, ValueError, KeyError, TypeError):
                logger.warning("similar-artist provider %s failed", provider.name)
                continue
            if result:
                await self._store.set_json(
                    key,
                    [{"name": r.name, "score": r.score, "source": r.source} for r in result],
                    CACHE_TTL_SECONDS,
                )
                return result
        return []

    async def aclose(self) -> None:
        for provider in self._providers:
            await provider.aclose()


def build_similar_artists(
    settings: object, store: KeyValueStore, first: SimilarArtistProvider | None = None
) -> CachedSimilarArtists:
    from app.core.config import Settings

    assert isinstance(settings, Settings)
    providers: list[SimilarArtistProvider] = [first] if first is not None else []
    if settings.lastfm_api_key and settings.lastfm_api_key.get_secret_value().strip():
        providers.append(LastFmSimilarArtists(settings.lastfm_api_key.get_secret_value()))
    if settings.deezer_enabled:
        providers.append(DeezerRelatedArtists())
    return CachedSimilarArtists(providers, store)
