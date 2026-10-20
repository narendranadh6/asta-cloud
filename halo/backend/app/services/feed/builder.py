"""Server-driven Home feed.

Each section has a builder. Builders run concurrently, each with a timeout, so one slow or
failing source never breaks or holds up Home; shared sections are warmed at startup.
Sections are ordered by a configurable score (``HALO_HOME_SECTION_WEIGHTS``); a weight of 0
or less removes a section, so sections can be reordered or switched off without an app release.

Some sections come from data that lives only on the device (recently discovered songs,
playlists, recent searches). The server sends them as ``layout="local"`` placeholders with no
items: it decides where they go, and the app fills them in.
"""

from __future__ import annotations

import asyncio
import logging
import re
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from datetime import UTC, datetime

from app.schemas import HomeFeed, HomeItem, HomeSection
from app.services.music_sources.listenbrainz import ListenBrainzClient
from app.services.music_sources.similar_artists import SimilarArtistProvider
from app.services.youtube.service import YouTubeSearchService

logger = logging.getLogger("halo.feed")

SECTION_TIMEOUT_SECONDS = 3.0
ITEMS_PER_SECTION = 12

DEFAULT_WEIGHTS: dict[str, float] = {
    "because_you_like": 95,
    "moods": 90,
    "recently_discovered": 88,
    "languages": 76,
    "soundtracks": 72,
    "your_artists": 70,
    "fresh_releases": 68,
    "trending": 64,
    "your_playlists": 60,
    "most_listened": 50,
    "continue_exploring": 40,
}

# Languages with strong film-music industries: soundtracks are offered for these.
FILM_LANGUAGES = ("Telugu", "Hindi", "Tamil", "Malayalam", "Kannada")
DEFAULT_LANGUAGES = (*FILM_LANGUAGES, "Punjabi", "English")

MOODS: tuple[tuple[str, str, str], ...] = (
    ("focused", "Focus", "Deep work"),
    ("calm", "Chill", "Relax & unwind"),
    ("workout", "Workout", "High energy"),
    ("sleep", "Late Night", "Mellow beats"),
    ("happy", "Feel Good", "Positive vibes"),
    ("travel", "Travel", "Explore the world"),
)

_CHANNEL_NOISE = re.compile(r"\s*(- topic|vevo|official)\s*$", re.IGNORECASE)


def clean_channel(channel: str) -> str:
    """'Artist - Topic' / 'ArtistVEVO' → 'Artist'."""
    return _CHANNEL_NOISE.sub("", channel).strip()


@dataclass(slots=True)
class FeedContext:
    """What Halo knows about the listener. Personal signals only with consent."""

    personalized: bool = False
    languages: list[str] = field(default_factory=list)
    favorite_artists: list[str] = field(default_factory=list)
    excluded_artists: list[str] = field(default_factory=list)
    recent_liked_artist: str | None = None


Builder = Callable[[FeedContext], Awaitable[HomeSection | None]]


class HomeFeedBuilder:
    def __init__(
        self,
        *,
        search_service: YouTubeSearchService,
        listenbrainz: ListenBrainzClient | None,
        similar_artists: SimilarArtistProvider | None,
        weights: dict[str, float] | None = None,
        timeout: float = SECTION_TIMEOUT_SECONDS,
    ) -> None:
        self._search = search_service
        self._listenbrainz = listenbrainz
        self._similar = similar_artists
        self._weights = {**DEFAULT_WEIGHTS, **(weights or {})}
        self._timeout = timeout
        self._builders: dict[str, Builder] = {
            "because_you_like": self._because_you_like,
            "moods": self._moods,
            "recently_discovered": self._local(
                "recently_discovered", "Recently discovered", "Songs you opened in Halo"
            ),
            "languages": self._languages,
            "soundtracks": self._soundtracks,
            "your_artists": self._your_artists,
            "fresh_releases": self._fresh_releases,
            "trending": self._trending,
            "your_playlists": self._local("your_playlists", "Your playlists", None),
            "most_listened": self._most_listened,
            "continue_exploring": self._local(
                "continue_exploring", "Continue exploring", "Your recent searches"
            ),
        }

    def weight(self, section_type: str) -> float:
        return self._weights.get(section_type, 0.0)

    async def build(self, context: FeedContext) -> HomeFeed:
        active = [(t, b) for t, b in self._builders.items() if self.weight(t) > 0]
        results = await asyncio.gather(*(self._run(t, b, context) for t, b in active))
        sections = [s for s in results if s is not None]
        sections.sort(key=lambda s: -s.score)
        return HomeFeed(
            sections=sections,
            personalized=context.personalized,
            generated_at=datetime.now(UTC),
        )

    async def warm(self) -> None:
        """Fetch the sections shared by every listener (charts, new releases, trending) so
        their sources are cached before the first Home request. Failures are ignored."""
        context = FeedContext()
        await asyncio.gather(
            self._fresh_releases(context),
            self._most_listened(context),
            self._trending(context),
            return_exceptions=True,
        )

    async def _run(
        self, section_type: str, builder: Builder, context: FeedContext
    ) -> HomeSection | None:
        try:
            section = await asyncio.wait_for(builder(context), self._timeout)
        except Exception as exc:  # one section must never break Home
            logger.warning("home section %s skipped: %s", section_type, exc)
            return None
        if section is None:
            return None
        if section.layout != "local" and not section.items:
            return None
        section.score = self.weight(section_type)
        return section

    # --- Sections ----------------------------------------------------------------------

    @staticmethod
    def _local(section_type: str, title: str, eyebrow: str | None) -> Builder:
        """A placeholder the app fills from data on the device."""

        async def build(context: FeedContext) -> HomeSection:
            return HomeSection(
                id=section_type,
                type=section_type,
                title=title,
                eyebrow=eyebrow,
                layout="local",
                score=0,
            )

        return build

    async def _moods(self, context: FeedContext) -> HomeSection:
        return HomeSection(
            id="moods",
            type="moods",
            title="Play something for…",
            layout="tiles",
            score=0,
            items=[
                HomeItem(kind="mood", id=mood, title=title, subtitle=subtitle)
                for mood, title, subtitle in MOODS
            ],
        )

    async def _because_you_like(self, context: FeedContext) -> HomeSection | None:
        seed = context.recent_liked_artist
        if not context.personalized or not seed or self._similar is None:
            return None
        excluded = {a.casefold() for a in context.excluded_artists}
        similar = await self._similar.similar(seed, limit=ITEMS_PER_SECTION + 4)
        items = [
            HomeItem(
                kind="artist",
                id=f"artist:{a.name}",
                title=a.name,
                subtitle=f"Similar to {seed}",
                query=a.name,
            )
            for a in similar
            if a.name.casefold() not in excluded and a.name.casefold() != seed.casefold()
        ][:ITEMS_PER_SECTION]
        sources = sorted({a.source for a in similar})
        return HomeSection(
            id="because_you_like",
            type="because_you_like",
            title=f"Artists like {seed}",
            eyebrow=f"Because you saved {seed}",
            layout="artist_rail",
            items=items,
            source=", ".join(sources) or None,
            score=0,
        )

    async def _your_artists(self, context: FeedContext) -> HomeSection | None:
        if not context.favorite_artists:
            return None
        return HomeSection(
            id="your_artists",
            type="your_artists",
            title="Your artists",
            eyebrow="Favourites you chose",
            layout="artist_rail",
            score=0,
            items=[
                HomeItem(kind="artist", id=f"artist:{name}", title=name, query=name)
                for name in context.favorite_artists[:ITEMS_PER_SECTION]
            ],
        )

    def _languages_for(self, context: FeedContext) -> list[str]:
        chosen = [lang for lang in context.languages if lang]
        rest = [lang for lang in DEFAULT_LANGUAGES if lang not in chosen]
        return chosen + rest

    async def _languages(self, context: FeedContext) -> HomeSection:
        personal = bool(context.languages)
        return HomeSection(
            id="languages",
            type="languages",
            title="In your languages" if personal else "Explore by language",
            eyebrow="From your preferences" if personal else None,
            layout="tiles",
            score=0,
            items=[
                HomeItem(
                    kind="query",
                    id=f"lang:{lang}",
                    title=f"{lang} hits",
                    subtitle="Popular songs",
                    query=f"{lang} hit songs",
                )
                for lang in self._languages_for(context)
            ],
        )

    async def _soundtracks(self, context: FeedContext) -> HomeSection | None:
        langs = [lang for lang in self._languages_for(context) if lang in FILM_LANGUAGES]
        if not langs:
            return None
        return HomeSection(
            id="soundtracks",
            type="soundtracks",
            title="Movie soundtracks",
            eyebrow="Indian film music",
            layout="tiles",
            score=0,
            items=[
                HomeItem(
                    kind="query",
                    id=f"film:{lang}",
                    title=f"{lang} movie songs",
                    subtitle="Latest soundtracks",
                    query=f"latest {lang} movie songs",
                )
                for lang in langs
            ],
        )

    async def _fresh_releases(self, context: FeedContext) -> HomeSection | None:
        if self._listenbrainz is None:
            return None
        releases = await self._listenbrainz.fresh_releases(days=14)
        releases.sort(key=lambda r: (-r.listen_count, r.release_date))
        return HomeSection(
            id="fresh_releases",
            type="fresh_releases",
            title="New releases",
            eyebrow="Out in the last two weeks",
            layout="feature_rail",
            source="ListenBrainz · Cover Art Archive",
            score=0,
            items=[
                HomeItem(
                    kind="release",
                    id=r.release_mbid,
                    title=r.release_name,
                    subtitle=f"{r.artist_name} · {r.release_date}",
                    artwork_url=r.cover_art_url,
                    badge=r.release_type,
                    query=f"{r.artist_name} {r.release_name}",
                )
                for r in releases[:ITEMS_PER_SECTION]
            ],
        )

    async def _trending(self, context: FeedContext) -> HomeSection | None:
        if not getattr(self._search.provider, "configured", True):
            return None
        result = await self._search.trending(max_results=ITEMS_PER_SECTION)
        return HomeSection(
            id="trending",
            type="trending",
            title="Trending now",
            eyebrow="YouTube music chart",
            layout="rail",
            source="YouTube",
            score=0,
            items=[
                HomeItem(
                    kind="track",
                    id=t.video_id,
                    title=t.title,
                    subtitle=t.channel_title,
                    artwork_url=t.best_thumbnail,
                    track=t,
                )
                for t in result.page.items
            ],
        )

    async def _most_listened(self, context: FeedContext) -> HomeSection | None:
        if self._listenbrainz is None:
            return None
        recordings = await self._listenbrainz.top_recordings(range_="week", count=10)
        return HomeSection(
            id="most_listened",
            type="most_listened",
            title="Most listened this week",
            eyebrow="Open listening data",
            layout="rows",
            source="ListenBrainz",
            score=0,
            items=[
                HomeItem(
                    kind="recording",
                    id=r.recording_mbid or f"{r.artist_name}|{r.title}",
                    title=r.title,
                    subtitle=r.artist_name,
                    badge=f"#{rank}",
                    query=f"{r.artist_name} {r.title}",
                )
                for rank, r in enumerate(recordings, start=1)
            ],
        )
