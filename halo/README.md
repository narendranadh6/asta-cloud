# Halo

An AI-first iPhone music app. Halo plays free, legal music in its own player, and every song
plays in full: independent artists on **Audius** and Creative Commons songs on **Jamendo**.
It builds playlists with an AI planner that only uses **verified** catalog results, and keeps
a local-first library. Halo has no ads, no sponsored recommendations and no tracking.

> Audio streams from each source straight to the iPhone. Halo never downloads or stores
> audio. 30-second iTunes previews exist as an opt-in server source but are off by default.
> See [docs/music-sources.md](docs/music-sources.md).

## Layout

```
halo/
  backend/        FastAPI · SQLAlchemy 2 · Alembic · Redis · Pytest
  ios/            SwiftUI app (Swift 6, iOS 17+) · XcodeGen project · SwiftPM core package
  docs/           architecture · api · music-sources · setup · openapi.json
  docker-compose.yml
  .env.example
```

## Quick start

```bash
cd halo && cp .env.example .env && docker compose up --build    # API → localhost:8000
open ios/Halo.xcodeproj                                          # run the Halo scheme
```

Or without Docker, PostgreSQL or Redis (SQLite + in-process cache, real music):

```bash
cd halo/backend && pip install -e ".[dev]" && python -m app.local_server
```

Music works with no keys: Audius is on by default. Add a free Jamendo
client id (`HALO_JAMENDO_CLIENT_ID`) for Creative Commons songs. An LLM key and a Last.fm key
are optional. A YouTube API key is no longer used. See [docs/setup.md](docs/setup.md).

## Features

| Screen | What it does |
|---|---|
| Onboarding | Languages, artists, genres, moods, explicit personalization consent. Skippable |
| Home | Greeting, Halo assistant entry, moods, recently discovered, playlists, artists and searches, all from Halo activity |
| Search | Songs and artists across every source. Suggestions, pagination, loading, empty, error and offline states, attribution |
| Song details | Artwork, source and licence, play, play next, add to queue, save, add to playlist, related music |
| Halo assistant | Chat → intent → queries → verified results → ranking → explanations → editable queue → play or save |
| Playlist Studio | Description, mood, genre, language, energy, duration, familiar↔discovery. Reorder, remove, regenerate, rename, save |
| Playlist details | Artwork, description, count, duration, play, shuffle, play next, reorder and remove |
| Library | Saved songs, playlists, AI collections, favorite artists, recent searches, local filter |
| Mood Hub | Eight moods that steer discovery and generation |
| Taste Intelligence | Inferred taste (Halo activity only), corrections, exclusions, languages, reset, opt-out |
| Discover | Full songs trending this week (Audius, Jamendo), ListenBrainz fresh releases and charts, genres |
| Live Radio | Thousands of live stations (Radio Browser) in the same player |
| Now Playing | Mini player on every screen; full player with seek, shuffle, repeat, queue, AirPlay, lock-screen and Control Center controls, background audio |
| Settings | Appearance, language, AI personalization, privacy, history, notifications, export, account deletion |

## Recommendations

Two-stage design based on published work from YouTube and Spotify: candidates from search,
similar artists (Last.fm/Deezer) and co-listening across opted-in listeners; a learnable
ranker; and a Thompson-sampling exploration budget. Details and sources:
[docs/recommendation-research.md](docs/recommendation-research.md).

## Verification status

See the CI workflow `Halo CI`: backend lint/type checks and tests on SQLite and PostgreSQL,
the Swift core on Linux, and the full Xcode build, unit tests and a simulator screenshot
tour (against `python -m tests.e2e_server`, real music) on macOS. Background audio and
lock-screen controls still need a real-iPhone pass.
