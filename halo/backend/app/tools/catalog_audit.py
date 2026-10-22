"""Halo Drive spike: how much Telugu music can Halo actually play?

Searches the enabled free sources for Telugu terms and for well-known Telugu artists and
films, and reports how many playable results come back and how many look like a real match
(the query appears in the artist, title, genre or tags). Metadata only; prints counts and a
few "title — artist" samples.

    python -m app.tools.catalog_audit   # Audius, plus Jamendo if HALO_JAMENDO_CLIENT_ID is set
"""

from __future__ import annotations

import asyncio
import os
import re

from app.schemas import Track
from app.services.catalog.audius import AudiusSource
from app.services.catalog.base import CatalogSource
from app.services.catalog.jamendo import JamendoSource

GENERAL = ["telugu", "telugu songs", "tollywood", "తెలుగు", "telugu folk", "telugu devotional"]
ARTISTS = [
    "Anirudh",
    "Devi Sri Prasad",
    "DSP",
    "Thaman",
    "Sid Sriram",
    "M. M. Keeravani",
    "Ilaiyaraaja",
    "S. P. Balasubrahmanyam",
    "Chitra",
    "Shreya Ghoshal",
]
FILMS = ["Pushpa", "RRR", "Ala Vaikunthapurramuloo", "Baahubali", "Jersey"]


def _matches(track: Track, query: str) -> bool:
    words = [w for w in re.findall(r"\w+", query.lower()) if len(w) > 2] or [query.lower()]
    text = " ".join(filter(None, [track.title, track.artist, track.genre, track.album])).lower()
    return all(word in text for word in words)


async def _audit(
    source: CatalogSource, queries: list[str]
) -> list[tuple[str, int, int, list[str]]]:
    rows = []
    for query in queries:
        try:
            tracks = await source.search(query, limit=50)
        except Exception as exc:  # noqa: BLE001 - report and continue
            rows.append((query, -1, -1, [f"error: {exc}"]))
            continue
        relevant = [t for t in tracks if _matches(t, query)]
        samples = [f"{t.title[:50]} — {t.artist[:30]}" for t in relevant[:3]]
        rows.append((query, len(tracks), len(relevant), samples))
    return rows


async def main() -> None:
    sources: list[CatalogSource] = [AudiusSource()]
    client_id = os.environ.get("HALO_JAMENDO_CLIENT_ID", "").strip()
    if client_id:
        sources.append(JamendoSource(client_id))
    for source in sources:
        print(f"\n=== {source.name} (playable results of 50, and how many match the query) ===")
        for group, queries in (("general", GENERAL), ("artists", ARTISTS), ("films", FILMS)):
            print(f"-- {group}")
            for query, total, relevant, samples in await _audit(source, queries):
                print(
                    f"HALO-AUDIT {source.name:7} {query!r:28} "
                    f"playable={total:3} matching={relevant:3}"
                )
                for sample in samples:
                    print(f"           {sample}")
        await source.aclose()


if __name__ == "__main__":
    asyncio.run(main())
