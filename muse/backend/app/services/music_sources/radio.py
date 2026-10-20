"""Live internet radio from the community Radio Browser directory.

https://www.radio-browser.info/ : public-domain station data, no API key. Stations are
broadcast by their owners; MUSE only lists them and plays the station's own stream URL.
The API asks clients to send a descriptive User-Agent.
"""

from __future__ import annotations

import hashlib
import logging
from typing import Any

import httpx
from pydantic import BaseModel

from app.core.cache import KeyValueStore

logger = logging.getLogger("muse.radio")

CACHE_TTL_SECONDS = 15 * 60


class RadioStation(BaseModel):
    id: str
    name: str
    stream_url: str
    homepage: str | None = None
    favicon: str | None = None
    tags: list[str]
    country_code: str | None = None
    language: str | None = None
    codec: str | None = None
    bitrate: int | None = None
    popularity: int = 0


class RadioUnavailableError(Exception):
    pass


def _station(item: dict[str, Any]) -> RadioStation | None:
    url = str(item.get("url_resolved") or item.get("url") or "")
    if not url.startswith(("https://", "http://")) or not item.get("stationuuid"):
        return None
    if str(item.get("lastcheckok", 1)) != "1":
        return None
    favicon = str(item.get("favicon") or "")
    homepage = str(item.get("homepage") or "")
    return RadioStation(
        id=str(item["stationuuid"]),
        name=" ".join(str(item.get("name", "")).split())[:120] or "Unnamed station",
        stream_url=url,
        homepage=homepage if homepage.startswith("https://") else None,
        favicon=favicon if favicon.startswith("https://") else None,
        tags=[t.strip() for t in str(item.get("tags", "")).split(",") if t.strip()][:8],
        country_code=item.get("countrycode") or None,
        language=item.get("language") or None,
        codec=item.get("codec") or None,
        bitrate=int(item["bitrate"]) if str(item.get("bitrate", "")).isdigit() else None,
        popularity=int(item.get("clickcount") or 0),
    )


class RadioBrowserClient:
    def __init__(
        self,
        store: KeyValueStore,
        *,
        base_url: str = "https://de1.api.radio-browser.info",
        http_client: httpx.AsyncClient | None = None,
        timeout: float = 8.0,
    ) -> None:
        self._store = store
        self._client = http_client or httpx.AsyncClient(
            base_url=base_url,
            timeout=timeout,
            headers={"User-Agent": "MUSE/0.1 (+https://github.com/narendranadh6/asta-cloud)"},
        )

    async def search(
        self,
        *,
        tag: str | None = None,
        language: str | None = None,
        country_code: str | None = None,
        name: str | None = None,
        limit: int = 30,
    ) -> list[RadioStation]:
        params: dict[str, Any] = {
            "hidebroken": "true",
            "order": "clickcount",
            "reverse": "true",
            "limit": max(1, min(limit, 100)),
        }
        if tag:
            params["tag"] = tag.lower()[:40]
        if language:
            params["language"] = language.lower()[:40]
        if country_code:
            params["countrycode"] = country_code.upper()[:2]
        if name:
            params["name"] = name[:60]
        key = "radio:" + hashlib.sha256(repr(sorted(params.items())).encode()).hexdigest()[:32]
        cached = await self._store.get_json(key)
        if cached is not None:
            return [RadioStation.model_validate(item) for item in cached]
        try:
            response = await self._client.get("/json/stations/search", params=params)
        except httpx.HTTPError as exc:
            raise RadioUnavailableError("Live radio is unavailable right now") from exc
        if response.status_code != 200:
            raise RadioUnavailableError("Live radio is unavailable right now")
        stations = [s for s in (_station(item) for item in response.json()) if s is not None]
        await self._store.set_json(key, [s.model_dump() for s in stations], CACHE_TTL_SECONDS)
        return stations

    async def aclose(self) -> None:
        await self._client.aclose()
