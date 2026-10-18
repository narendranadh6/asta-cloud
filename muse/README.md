# MUSE

An AI-first iPhone music companion. MUSE finds music with the YouTube Data API, builds
playlists with an AI planner that only uses **verified** search results, keeps a local-first
library, and hands playback off to **Brave** (or any browser). MUSE has no ads, no
sponsored recommendations and no tracking.

> MUSE does not play, download or modify YouTube content, and it cannot control Brave.
> No play/pause, no queue, no auto-advance, no background-play or ad-blocking guarantees.
> See [docs/brave-integration.md](docs/brave-integration.md).

## Layout

```
muse/
  backend/        FastAPI · SQLAlchemy 2 · Alembic · Redis · Pytest
  ios/            SwiftUI app (Swift 6, iOS 17+) · XcodeGen project · SwiftPM core package
  docs/           architecture · api · brave-integration · youtube-compliance · setup · openapi.json
  docker-compose.yml
  .env.example
```

## Quick start

```bash
cd muse && cp .env.example .env && docker compose up --build    # API → localhost:8000
open ios/MUSE.xcodeproj                                          # run the MUSE scheme
```

No keys are needed to try it. The backend serves a labelled demo catalog and a deterministic
AI planner until you add `MUSE_YOUTUBE_API_KEY` (and optionally an LLM key). See
[docs/setup.md](docs/setup.md).

## Features

| Screen | What it does |
|---|---|
| Onboarding | Languages, artists, genres, moods, explicit personalization consent. Skippable |
| Home | Greeting, AI DJ entry, moods, recently discovered, playlists, artists and searches, all from MUSE activity |
| Search | Songs, artists, remixes, live. Suggestions, pagination, loading, empty, error and offline states, attribution |
| Song details | Artwork, source, save, add to playlist, related music, **Listen in Brave** with the destination shown |
| AI DJ | Chat → intent → queries → verified results → ranking → explanations → editable queue → save |
| Playlist Studio | Description, mood, genre, language, energy, duration, familiar↔discovery. Reorder, remove, regenerate, rename, save |
| Playlist details | Artwork, description, count, duration, reorder and remove, open a track or a linked YouTube playlist |
| Library | Saved songs, playlists, AI collections, favorite artists, recent searches, local filter |
| Mood Hub | Eight moods that steer discovery and generation |
| Taste Intelligence | Inferred taste (MUSE activity only), corrections, exclusions, languages, reset, opt-out |
| Browser handoff | Brave detection, destination choice, test, explicit limits |
| Settings | Appearance, language, AI personalization, privacy, history, browser, notifications, export, account deletion |

## Verification status

| Check | Status |
|---|---|
| Backend: ruff, mypy, 91 pytest tests on SQLite and PostgreSQL 16 | ✅ passing |
| Alembic upgrade, `check`, downgrade on PostgreSQL | ✅ |
| Docker image builds, migrates and serves `/health` | ✅ |
| iOS core + view models: `swift build`/`swift test` (Swift 6.1, strict concurrency), 50 tests | ✅ on Linux |
| SwiftUI/SwiftData layers + `xcodebuild` | ⏳ needs macOS (runs in the `MUSE CI → ios-xcode` job) |
| Brave handoff on a real iPhone | ⏳ not yet verified. Follow the checklist |

Licensed native audio is not implemented. The provider interfaces (`MetadataProvider`,
`LLMClient`, `URLOpening`) are where a licensed audio provider would plug in.
