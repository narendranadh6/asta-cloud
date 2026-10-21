# Halo architecture

```
┌──────────────────────── iPhone ────────────────────────┐        ┌────────────── Backend (FastAPI) ───────────────┐
│ SwiftUI features (MVVM, @Observable view models)        │        │ api/v1/routes.py  (auth, validation, errors)    │
│   Home · Search · Song · Halo assistant · Studio · Library ·     │ HTTPS  │   ├─ rate_limit (Redis fixed window)            │
│   Mood Hub · Taste · Radio · Now Playing · Settings     │ ─────▶ │   ├─ services/catalog  (sources + cache)        │
│ Core/Networking  APIClient (actor, retries, Keychain)   │  JSON  │   ├─ services/ai       (LLM planner + fallback) │
│ Core/Persistence SwiftData library + playlist sync      │        │   ├─ services/recommendations (pipeline)        │
│ Core/Playback    PlayerController · AVPlayer · queue    │        │   └─ repositories (SQLAlchemy 2, PostgreSQL)    │
└──────────────┬──────────────────────────────────────────┘        └───────────┬───────────────┬────────────────────┘
               │ audio stream (stream_url), never via the backend              │               │
               ▼                                                               ▼               ▼
     Audius · Jamendo · Apple previews · radio streams        Audius · Jamendo · iTunes Search   LLM provider (optional)
```

## Principles

* **Free, legal sources only.** Full songs from Audius and Jamendo, labelled 30-second
  previews from the iTunes Search API. Rules per source: [music-sources.md](music-sources.md).
* **Audio never touches the backend.** The server stores ids (`<source>:<id>`) plus minimal
  metadata (title, artist, album, artwork URL, stream URL, duration). The iPhone streams audio
  straight from the source.
* **Verified references.** Every playable id comes back from a source in the same request.
  The LLM produces search *text* only.
* **Local first.** SwiftData holds the library on the device. Backend sync is optional and
  best-effort.
* **Honest labels.** Previews are always marked as previews, and licences and sources are
  shown with every track.
* **Provider isolation.** `CatalogSource` (one per music source; fakes live only in the test
  suite), `LLMClient` (Anthropic, OpenAI-compatible, or none), `AudioEngine` (AVPlayer or test
  fake) and `HTTPTransport` (URLSession or test fake) are interfaces, so another licensed
  source is one more `CatalogSource`.

## Backend

| Layer | Path | Notes |
|---|---|---|
| Config | `app/core/config.py` | `HALO_*` env vars. A production guard rejects missing secrets, no enabled music source, or debug mode. Cache TTL is clamped to 30 days |
| Errors | `app/core/errors.py` | Every error is `{"error": {code, message, details?, request_id}}`. Validation errors never echo input |
| Auth | `app/core/security.py`, `api/deps.py` | Anonymous device accounts. HS256 JWT bearer token (30 days), stored in the iOS Keychain. All user data is filtered by owner. A missing resource and someone else's resource both return 404 |
| Rate limits | `app/core/rate_limit.py` | Per-user (or per-IP before auth) fixed windows in Redis, with an in-memory fallback |
| Cache | `app/core/cache.py` | Redis JSON cache. Store errors never fail a request |
| Catalog | `app/services/catalog/` | `audius.py`, `jamendo.py`, `itunes.py` (one `CatalogSource` each), `service.py` (concurrent fan-out with a 6 s timeout per source, ranking by relevance + full-song bonus + popularity, dedupe that keeps full songs over previews, metadata cache), `ids.py` (`<source>:<id>` validation) |
| AI | `app/services/ai/` | `intent.py` (Pydantic `MusicIntent`, rejects URLs), `heuristic.py` (deterministic planner), `providers.py` (Anthropic / OpenAI-compatible with fallback) |
| Recommendations | `app/services/recommendations/pipeline.py` | Retrieval → filtering → scoring → diversity → duration fit |
| Data | `app/models`, `alembic/versions` | UUID primary keys, `created_at`/`updated_at`, indexes, cascading deletes |
| Retention | `app/tasks/refresh_metadata.py` | Daily job: refresh references (and stream URLs) older than 7 days, or mark them unavailable |
| Local run | `app/local_server.py` | `python -m app.local_server`: SQLite (`halo-local.sqlite3`), in-process cache, real sources. `tests/e2e_server.py` wraps it for the iOS UI tests |

### Recommendation pipeline (v2)

See [recommendation-research.md](recommendation-research.md) for where each technique comes
from (YouTube's two-stage recommender, Spotify's BaRT bandits and playlist co-occurrence).

1. **Intent extraction.** The LLM returns `MusicIntent` JSON, validated by Pydantic. On any
   failure the heuristic planner runs instead. Studio form values override both.
2. **Candidate generation** from four sources:
   * `search`: 1–5 planner queries against the catalog.
   * `similar_artist`: artists similar to the request's or listener's favourites, from
     Last.fm `artist.getSimilar` or Deezer related artists, then searched in the catalog.
   * `listenbrainz`: LB Radio for the seed artist (resolved to an MBID through
     MusicBrainz): popular recordings by similar artists, with the popularity window set by
     the discovery level. Up to `HALO_LISTENBRAINZ_TRACK_LOOKUPS` of them are matched on
     the catalog by search, and kept only when the result's title overlaps the recording's.
     ListenBrainz artist radio is also the first similar-artist provider.
   * `co_listen`: item-to-item co-occurrence in playlists of listeners who opted in to
     personalization, cosine-normalised. A pair must come from at least two listeners, so
     no single person's playlist can be read back.
3. **Filtering.** Duplicates, excluded artists, disliked songs, tracks without a stream,
   items under 60 s, long-form compilations unless asked for.
4. **Ranking.** Heuristic relevance (query rank, intent-term overlap, favourites, likes,
   popularity per discovery level) becomes one feature of a logistic-regression ranker that
   also sees the source, co-listening score and popularity. `python -m app.tasks.train_ranker`
   retrains it from logged feedback, shrinking toward hand-set defaults while data is scarce.
5. **Exploration.** 10% / 20% / 35% of slots (familiar / balanced / discovery) go to items
   the ranker alone would not pick. The source for each slot is chosen by Thompson sampling
   over per-listener Beta posteriors (plus a down-weighted population prior), and the pick is
   labelled "Something new for you".
6. **Diversity and length.** Per-artist caps, near-duplicate suppression, fitted to the
   requested duration. Exploration picks are spread through the list.
7. **Feedback.** Like/save count as a success and dislike/skip as a failure for the source
   that produced the item. The features logged with each session are the ranker's training
   data. All of this is stored only with personalization consent.

### Data model

`users` 1–1 `user_preferences`; `users` 1–n `artist_preferences`, `playlists`,
`search_history`, `recommendation_sessions`, `recommendation_feedback`, `ai_conversations`;
`bandit_arms` (per-listener and global source statistics), `model_artifacts` (ranker
weights); `playlists` 1–n `playlist_items` n–1 `track_references` (global, unique on
`provider + provider_id`). Deleting a user cascades to everything they own.

## iOS

* **Swift 6** language mode with complete strict concurrency. iOS 17+. SwiftUI with
  `@Observable` view models.
* `Core/Networking/APIClient` is an actor. It auto-registers, stores the token in the
  Keychain, re-registers once on 401, retries idempotent requests on transient errors with
  exponential backoff (respecting `Retry-After` up to 10 s), and never retries POST.
* `Core/Persistence`: SwiftData models `TrackEntity`, `PlaylistEntity`, `PlaylistItemEntity`,
  `RecentSearchEntity`, `ArtistEntity`. `LibraryStore` owns every mutation, keeps positions
  contiguous, and enforces retention. `PlaylistSyncService` mirrors playlists using
  `PlaylistSyncPlanner`, a pure, tested diff that handles duplicate songs.
* `Core/Playback`: `PlayerController` is the one player (songs and Live Radio), so the mini
  player, Now Playing and the lock screen always agree. `PlaybackQueue` is pure, tested value
  logic (shuffle, repeat off/all/one, play next, reorder). `StreamingAudioEngine` wraps
  `AVPlayer` with a `.playback` audio session (background audio, AirPlay);
  `SystemMediaControls` publishes Now Playing info and handles `MPRemoteCommandCenter`
  (lock screen, Control Center, headphones).
* `Core/DesignSystem`: colour tokens (`#080811`, `#17132D`, `#8355F7`, `#D34EDB`, `#488EFF`,
  `#FFFFFF`, `#A6A2BB`), glass cards that turn opaque under Reduce Transparency, a static glow
  under Reduce Motion, Dynamic Type text styles, 44 pt minimum hit targets, and haptics.
* The platform-neutral code (networking, models, the player and queue, and the UI-free view models
  for Search, Halo assistant, Studio and settings) is also a Swift package (`ios/Package.swift`), so it
  compiles and its tests run with `swift test` on macOS or Linux. The SwiftUI and SwiftData
  layers build only with Xcode.

## Security & privacy

* HTTPS in production (ATS). HSTS header in production. `NSAllowsLocalNetworking` only for
  local development.
* Secrets come from the environment only (`.env` is git-ignored). The LLM, Last.fm and
  Audius keys never leave the server.
* Personalization is **off by default**. When off, no recommendation sessions, feedback or
  conversations are stored. Raw AI prompts are stored only if the user also enables "Keep AI
  DJ conversations".
* No analytics or advertising SDKs. The privacy manifest declares no tracking.
* Data export (`GET /api/v1/me/export` plus the on-device library) and account deletion
  (`DELETE /api/v1/me` plus a local wipe).
* Logs never include prompts, queries or preferences. Catalog sources log only failures.

### Open music metadata

* **MusicBrainz** (`app/services/music_sources/musicbrainz.py`) identifies what a catalog
  track is. The title is cleaned ("Artist - Song (Official Video)" → artist, song), searched,
  and accepted
  only with score ≥ 85 and a length within 25 s. Halo then reads the recording, its ISRCs and
  genres, and the earliest official release with labels and Cover Art Archive artwork.
  Responses are cached for 30 days and requests are spaced to 1/s. The iOS Song Details
  screen shows this as "About this recording", credited to MusicBrainz (CC0).
* **ListenBrainz** (`listenbrainz.py`, `discovery.py`) provides fresh releases, sitewide
  most-listened charts, LB Radio and per-artist popularity. Discover shows "Fresh releases"
  and "Most listened this week"; tapping one searches the catalog for it, so what plays is
  always a real, verified track.

### Home feed

`GET /api/v1/home` is assembled by `app/services/feed/builder.py`. Each section type has a
builder; builders run concurrently, each with a 3-second timeout, and a failing or slow builder only
removes its own section. The shared sections (charts, new releases, trending) are warmed when
the server starts, so the first Home request is served from the cache. Sections are ordered by score, using defaults in `DEFAULT_WEIGHTS`
overridden by `HALO_HOME_SECTION_WEIGHTS` (JSON). A weight of 0 or less removes a section, so the
Home layout changes without an app release.

| Section | Data | Needs |
|---|---|---|
| `because_you_like` | Similar artists (ListenBrainz, Last.fm, Deezer) to the artist of the listener's latest save | Personalization consent |
| `moods` | Mood hubs | — |
| `languages`, `soundtracks` | Language and Indian film-music searches; the listener's languages first | Languages are used only with consent |
| `your_artists` | Favourite artists the listener chose | — |
| `fresh_releases`, `most_listened` | ListenBrainz | ListenBrainz enabled |
| `trending` | Full songs trending this week on Audius and Jamendo | A full-song source |
| `recently_discovered`, `your_playlists`, `continue_exploring` | On-device data (SwiftData) | — |

The iOS app (`HomeViewModel`, `HomeSectionView`) draws each layout; unknown layouts and item kinds
are skipped, so the server can add sections without breaking older apps. Until the first feed
arrives, or when offline, Home shows the on-device sections.
