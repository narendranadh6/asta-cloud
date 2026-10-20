# Halo roadmap (v3: personalized discovery)

Status: proposed, awaiting approval to start Phase 2. Last updated 2026-10-20.

## Decisions

| Decision | Choice | Consequence |
|---|---|---|
| Song playback | **(a) Brave hand-off only** | Songs keep the honest "Now in Brave" screen. Full transport controls (play/pause, queue, lock screen) exist for Live Radio, which plays in the app. Every player sits behind `PlaybackProvider`, so a licensed in-app provider can be added later without UI rewrites. |
| Reference products | Spotify, Apple Music, YouTube Music: studied for user-facing principles only | No proprietary code, private APIs, assets, names ("Quick picks", "Daily Mix", "Made For You", "Listen Now"), or exact layouts |
| REA (`morluto/rea`) | Installed as a tool, not used on third-party apps | REA is a reverse-engineering toolkit. Running it on Spotify, Apple Music or YouTube Music would break their terms and this project's originality rules. Allowed uses: Halo's own builds and permissively licensed open-source apps. |

## What playback mode (a) means for signals

Halo cannot see what happens in Brave, so song events are limited to what happens in Halo:
`HANDOFF` (intent to play), `LIKE`, `DISLIKE`, `SAVE`, `ADD_TO_PLAYLIST`, `QUEUE_ADD`, `SEARCH`,
`ARTIST_VIEW`, `ALBUM_VIEW`, `IMPRESSION`, and `RETURN` (the user came back after N seconds; a weak signal).
Live Radio provides real `PLAY` / `PAUSE` / `RESUME` / `STOP` with listening time. The event schema keeps
`SKIP` / `COMPLETE` / `REPLAY` so a future in-app provider needs no migration.

## Architecture

```
Events (iOS, batched, offline-safe) → POST /events (202) → Redis stream → worker
   → short-term session profile (Redis, ~2 h half-life)
   → long-term taste (Postgres, ~60-day half-life; artist/genre/language/album affinity)
Candidate sources: history · similar artists (ListenBrainz/Last.fm/Deezer) · same artist/album ·
   co-listening · LB Radio · fresh releases · trending (YouTube chart, ListenBrainz charts) ·
   regional/language pools · rediscovery
Ranker: readable linear score with configurable weights + existing learned ranker,
   per-feature contributions logged as reasons
Re-rank: artist/album/language diversity limits + bandit exploration slots
Feed builder: sections scored, ordered and trimmed → GET /home
```

* Cold start: personal weight = n / (n + 20) interactions; onboarding choices + regional/language popularity + fresh releases.
* A session's interests only reach long-term taste after appearing in ≥ 3 sessions on different days.
* Feed items are MusicBrainz/ListenBrainz entities; a YouTube video is matched only on tap and stored
  (`track_references.recording_mbid`), to stay within the 10,000-unit daily YouTube quota.
* Film/soundtrack links only when MusicBrainz says so (release-group secondary type "Soundtrack",
  film relationships). Language comes from release metadata (`tel`, `hin`, `tam`, `mal`, `kan`, `eng`).

## Phases

| # | Phase | Main work | Database |
|---|---|---|---|
| 1 | Assessment | This document | — |
| 2 | Design system | Tokens for typography, spacing, radii, artwork sizes, surfaces, motion; skeleton/empty/error states | — |
| 3 | Navigation + Home | `GET /home` with server-ordered sections; iOS feed renderer per section type | Feed cache in Redis |
| 4 | Catalog | Store canonical MusicBrainz entities; artist and album pages; soundtracks | 0003: artists, release_groups, recordings |
| 5 | Events | `POST /events`, worker, iOS `EventRecorder` (consent-gated) | 0004: listening_events |
| 6 | Taste profile | Long-term + session profiles | taste_profiles + Redis |
| 7 | Candidates | One module per source | — |
| 8 | Ranking | Weight sets, reason logging, diversity re-rank, offline replay | — |
| 9 | Sparks | Small set of very likely next listens | — |
| 10 | Song/Artist radio | Gradual drift outward from a seed | Redis state |
| 11 | Search | Grouped results (top, songs, artists, albums, soundtracks) | — |
| 12 | Player surfaces | `PlaybackCenter` + providers (Brave hand-off, Live Radio); mini-player and Now Playing for radio; "Now in Brave" for songs | — |
| 13 | Performance | Artwork disk cache and prefetch, signposts, pagination, indexes | Indexes |
| 14 | Polish | Accessibility, full screenshot tour, load tests | — |
