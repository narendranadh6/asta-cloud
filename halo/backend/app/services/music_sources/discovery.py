"""Track-level discovery from ListenBrainz, keyed by artist names via MusicBrainz."""

from __future__ import annotations

import logging

from app.services.music_sources.listenbrainz import (
    ListenBrainzClient,
    ListenBrainzUnavailableError,
    PopularRecording,
)
from app.services.music_sources.musicbrainz import MusicBrainzClient, MusicBrainzUnavailableError
from app.services.music_sources.similar_artists import SimilarArtist

logger = logging.getLogger("halo.discovery")


class ListenBrainzDiscovery:
    """Similar artists and their popular tracks from real listening data.

    MusicBrainz resolves an artist name to its MBID; ListenBrainz's artist radio then returns
    popular recordings by similar artists. Failures return empty results so recommendations
    still work from other sources.
    """

    name = "listenbrainz"

    def __init__(self, musicbrainz: MusicBrainzClient, listenbrainz: ListenBrainzClient) -> None:
        self._mb = musicbrainz
        self._lb = listenbrainz

    async def tracks(
        self, seed_artist: str, *, discovery: str = "balanced", limit: int = 6
    ) -> list[PopularRecording]:
        try:
            artist = await self._mb.find_artist(seed_artist)
            if artist is None:
                return []
            recordings = await self._lb.artist_radio(artist.mbid, discovery=discovery)
        except (MusicBrainzUnavailableError, ListenBrainzUnavailableError, ValueError, KeyError):
            logger.warning("ListenBrainz discovery unavailable for one seed")
            return []
        for recording in recordings:
            recording.similar_to = artist.name
        return recordings[:limit]

    async def similar(self, artist: str, *, limit: int = 10) -> list[SimilarArtist]:
        """SimilarArtistProvider interface: artists ranked by ListenBrainz radio listen counts."""
        recordings = await self.tracks(artist, limit=50)
        best: dict[str, int] = {}
        for recording in recordings:
            name = recording.artist_name
            best[name] = max(best.get(name, 0), recording.listen_count)
        ranked = sorted(best.items(), key=lambda item: -item[1])[:limit]
        top = ranked[0][1] if ranked else 1
        return [
            SimilarArtist(name=name, score=round(count / max(top, 1), 3), source=self.name)
            for name, count in ranked
            if name
        ]

    async def aclose(self) -> None:
        return None
