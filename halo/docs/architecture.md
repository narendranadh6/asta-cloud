# Halo architecture

```
┌──────────────────────── iPhone ────────────────────────┐        ┌────────────── Backend (FastAPI) ───────────────┐
│ SwiftUI features (MVVM, @Observable view models)        │        │ api/v1/routes.py  (auth, validation, errors)    │
│   Home · Search · Song · AI DJ · Studio · Library ·     │ HTTPS  │   ├─ rate_limit (Redis fixed window)            │
│   Mood Hub · Taste · Settings · Browser · Onboarding    │ ─────▶ │   ├─ services/youtube  (Data API v3 + cache)    │
│ Core/Networking  APIClient (actor, retries, Keychain)   │  JSON  │   ├─ services/ai       (LLM planner + fallback) │
│ Core/Persistence SwiftData library + playlist sync      │        │   ├─ services/recommendations (pipeline)        │
│ Core/BrowserIntegration  Brave deep link / HTTPS        │        │   └─ repositories (SQLAlchemy 2, PostgreSQL)    │
└──────────────┬──────────────────────────────────────────┘        └───────────┬───────────────┬────────────────────┘
               │ UIApplication.open(brave://open-url?url=…)                    │               │
               ▼                                                               ▼               ▼
        Brave (external, uncontrolled)                              YouTube Data API v3   LLM provider (optional)
```

## Principles

* **Metadata only.** Halo stores YouTube ids plus minimal metadata (title, channel,
  thumbnail URL, duration). It never handles audio or video.
* **Verified references.** Every playable id comes back from the provider in the same
  request (search results go through `videos.list`). The LLM produces search *text* only.
* **Local first.** SwiftData holds the library on the device. Backend sync is optional and
  best-effort.
* **Honest boundaries.** After handoff, Halo doesn't show or imply any playback state.
* **Provider isolation.** `MetadataProvider` (YouTube; a fake lives only in the test suite), `LLMClient` (Anthropic,
  OpenAI-compatible, or none), `URLOpening` (UIKit or test fake) and `HTTPTransport`
  (URLSession or test fake) are interfaces, so a licensed audio provider can be added
  later as another provider behind its own interface.

## Backend

| Layer | Path | Notes |
|---|---|---|
| Config | `app/core/config.py` | `HALO_*` env vars. A production guard rejects missing secrets or debug mode. Cache TTL is clamped to 30 days |
| Errors | `app/core/errors.py` | Every error is `{"error": {code, message, details?, request_id}}`. Validation errors never echo input |
| Auth | `app/core/security.py`, `api/deps.py` | Anonymous device accounts. HS256 JWT bearer token (30 days), stored in the iOS Keychain. All user data is filtered by owner. A missing resource and someone else's resource both return 404 |
| Rate limits | `app/core/rate_limit.py` | Per-user (or per-IP before auth) fixed windows in Redis, with an in-memory fallback |
| Cache | `app/core/cache.py` | Redis JSON cache. Store errors never fail a request |
| YouTube | `app/services/youtube/` | `client.py` (real API: retries, quota and error mapping, HTML unescape, region checks), `service.py` (caching facade), `ids.py` (validation) |
| AI | `app/services/ai/` | `intent.py` (Pydantic `MusicIntent`, rejects URLs), `heuristic.py` (deterministic planner), `providers.py` (Anthropic / OpenAI-compatible with fallback) |
| Recommendations | `app/services/recommendations/pipeline.py` | Retrieval → filtering → scoring → diversity → duration fit |
| Data | `app/models`, `alembic/versions` | UUID primary keys, `created_at`/`updated_at`, indexes, cascading deletes |
| Retention | `app/tasks/refresh_metadata.py` | Daily job: refresh references older than 25 days, or mark them unavailable |

### Recommendation pipeline (v2)

See [recommendation-research.md](recommendation-research.md) for where each technique comes
from (YouTube's two-stage recommender, Spotify's BaRT bandits and playlist co-occurrence).

1. **Intent extraction.** The LLM returns `MusicIntent` JSON, validated by Pydantic. On any
   failure the heuristic planner runs instead. Studio form values override both.
2. **Candidate generation** from four sources:
   * `search`: 1–5 planner queries against the YouTube Data API (results re-verified).
   * `similar_artist`: artists similar to the request's or listener's favourites, from
     Last.fm `artist.getSimilar` or Deezer related artists, then searched on YouTube.
   * `listenbrainz`: LB Radio for the seed artist (resolved to an MBID through
     MusicBrainz): popular recordings by similar artists, with the popularity window set by
     the discovery level. Up to `HALO_LISTENBRAINZ_TRACK_LOOKUPS` of them are matched on
     YouTube by search, and kept only when the result's title overlaps the recording's.
     ListenBrainz artist radio is also the first similar-artist provider.
   * `co_listen`: item-to-item co-occurrence in playlists of listeners who opted in to
     personalization, cosine-normalised. A pair must come from at least two listeners, so
     no single person's playlist can be read back.
3. **Filtering.** Duplicates, excluded artists, disliked videos, live-now streams, items
   under 60 s, long-form compilations unless asked for.
4. **Ranking.** Heuristic relevance (query rank, intent-term overlap, favourites, likes,
   popularity per discovery level) becomes one feature of a logistic-regression ranker that
   also sees the source, co-listening score and popularity. `python -m app.tasks.train_ranker`
   retrains it from logged feedback, shrinking toward hand-set defaults while data is scarce.
5. **Exploration.** 10% / 20% / 35% of slots (familiar / balanced / discovery) go to items
   the ranker alone would not pick. The source for each slot is chosen by Thompson sampling
   over per-listener Beta posteriors (plus a down-weighted population prior), and the pick is
   labelled "Something new for you".
6. **Diversity and length.** Per-channel caps, near-duplicate suppression, fitted to the
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
* `Core/BrowserIntegration`: see [brave-integration.md](brave-integration.md).
* `Core/DesignSystem`: colour tokens (`#080811`, `#17132D`, `#8355F7`, `#D34EDB`, `#488EFF`,
  `#FFFFFF`, `#A6A2BB`), glass cards that turn opaque under Reduce Transparency, a static glow
  under Reduce Motion, Dynamic Type text styles, 44 pt minimum hit targets, and haptics.
* The platform-neutral code (networking, models, browser logic, and the UI-free view models
  for Search, AI DJ, Studio and settings) is also a Swift package (`ios/Package.swift`), so it
  compiles and its tests run with `swift test` on macOS or Linux. The SwiftUI and SwiftData
  layers build only with Xcode.

## Security & privacy

* HTTPS in production (ATS). HSTS header in production. `NSAllowsLocalNetworking` only for
  local development.
* Secrets come from the environment only (`.env` is git-ignored). The YouTube key never
  leaves the server.
* Personalization is **off by default**. When off, no recommendation sessions, feedback or
  conversations are stored. Raw AI prompts are stored only if the user also enables "Keep AI
  DJ conversations".
* No analytics or advertising SDKs. The privacy manifest declares no tracking.
* Data export (`GET /api/v1/me/export` plus the on-device library) and account deletion
  (`DELETE /api/v1/me` plus a local wipe).
* Logs never include prompts, queries or preferences. The YouTube client logs only error
  classes.

### Open music metadata

* **MusicBrainz** (`app/services/music_sources/musicbrainz.py`) identifies what a YouTube
  upload is. The title is parsed ("Artist - Song (Official Video)"), searched, and accepted
  only with score ≥ 85 and a length within 25 s. Halo then reads the recording, its ISRCs and
  genres, and the earliest official release with labels and Cover Art Archive artwork.
  Responses are cached for 30 days and requests are spaced to 1/s. The iOS Song Details
  screen shows this as "About this recording", credited to MusicBrainz (CC0).
* **ListenBrainz** (`listenbrainz.py`, `discovery.py`) provides fresh releases, sitewide
  most-listened charts, LB Radio and per-artist popularity. Discover shows "Fresh releases"
  and "Most listened this week"; tapping one searches YouTube for it, so playback stays
  a Brave handoff of a real, verified video.
