# Halo

An AI-first iPhone music companion. Halo finds music with the YouTube Data API, builds
playlists with an AI planner that only uses **verified** search results, keeps a local-first
library, and hands playback off to **Brave** (or any browser). Halo has no ads, no
sponsored recommendations and no tracking.

> Halo does not play, download or modify YouTube content, and it cannot control Brave.
> No play/pause, no queue, no auto-advance, no background-play or ad-blocking guarantees.
> See [docs/brave-integration.md](docs/brave-integration.md).

## Layout

```
halo/
  backend/        FastAPI · SQLAlchemy 2 · Alembic · Redis · Pytest
  ios/            SwiftUI app (Swift 6, iOS 17+) · XcodeGen project · SwiftPM core package
  docs/           architecture · api · brave-integration · youtube-compliance · setup · openapi.json
  docker-compose.yml
  .env.example
```

## Quick start

```bash
cd halo && cp .env.example .env && docker compose up --build    # API → localhost:8000
open ios/Halo.xcodeproj                                          # run the Halo scheme
```

Set `HALO_YOUTUBE_API_KEY` in `.env` for music search. An LLM key and a Last.fm key are
optional. See [docs/setup.md](docs/setup.md).

## Features

| Screen | What it does |
|---|---|
| Onboarding | Languages, artists, genres, moods, explicit personalization consent. Skippable |
| Home | Greeting, AI DJ entry, moods, recently discovered, playlists, artists and searches, all from Halo activity |
| Search | Songs, artists, remixes, live. Suggestions, pagination, loading, empty, error and offline states, attribution |
| Song details | Artwork, source, save, add to playlist, related music, **Listen in Brave** with the destination shown |
| AI DJ | Chat → intent → queries → verified results → ranking → explanations → editable queue → save |
| Playlist Studio | Description, mood, genre, language, energy, duration, familiar↔discovery. Reorder, remove, regenerate, rename, save |
| Playlist details | Artwork, description, count, duration, reorder and remove, open a track or a linked YouTube playlist |
| Library | Saved songs, playlists, AI collections, favorite artists, recent searches, local filter |
| Mood Hub | Eight moods that steer discovery and generation |
| Taste Intelligence | Inferred taste (Halo activity only), corrections, exclusions, languages, reset, opt-out |
| Discover | YouTube's most-popular music chart, live and remix shelves, genres |
| Live Radio | Thousands of live stations (Radio Browser), native playback with lock-screen controls |
| Now in Brave | The song Halo handed off, open again, up-next picks you choose yourself |
| Browser handoff | Brave detection, destination choice, test, explicit limits |
| Settings | Appearance, language, AI personalization, privacy, history, browser, notifications, export, account deletion |

## Recommendations

Two-stage design based on published work from YouTube and Spotify: candidates from search,
similar artists (Last.fm/Deezer) and co-listening across opted-in listeners; a learnable
ranker; and a Thompson-sampling exploration budget. Details and sources:
[docs/recommendation-research.md](docs/recommendation-research.md).

## Verification status

See the CI workflow `Halo CI`: backend lint/type checks and tests on SQLite and PostgreSQL,
the Swift core on Linux, and the full Xcode build, unit tests and a simulator screenshot
tour on macOS. Brave handoff still needs a real-iPhone pass (checklist in
[docs/brave-integration.md](docs/brave-integration.md)).
