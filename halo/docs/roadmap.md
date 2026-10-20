# Halo roadmap (v3: personalized discovery)

Status: proposed, awaiting approval to start Phase 2. Last updated 2026-10-20.

## Decisions

| Decision | Choice | Consequence |
|---|---|---|
| Song playback | **In-app audio from free sources** | Full songs stream from Audius and Jamendo (Creative Commons); mainstream songs fall back to labelled 30-second iTunes previews linked to Apple Music. YouTube was removed because its terms forbid audio-only and background playback. One `PlayerController` plays songs and Live Radio with queue, shuffle, repeat, mini player, Now Playing, AirPlay and lock-screen controls. Another licensed source is one more `CatalogSource`. |
| Reference products | Spotify, Apple Music, YouTube Music: studied for user-facing principles only | No proprietary code, private APIs, assets, names ("Quick picks", "Daily Mix", "Made For You", "Listen Now"), or exact layouts |
| REA (`morluto/rea`) | Installed as a tool, not used on third-party apps | REA is a reverse-engineering toolkit. Running it on Spotify, Apple Music or YouTube Music would break their terms and this project's originality rules. Allowed uses: Halo's own builds and permissively licensed open-source apps. |

## What in-app playback means for signals

Halo plays every song itself, so song events are real listening signals: `PLAY`, `PAUSE`,
`RESUME`, `SKIP`, `COMPLETE`, `REPLAY` with listening time, plus `LIKE`, `DISLIKE`, `SAVE`,
`ADD_TO_PLAYLIST`, `QUEUE_ADD`, `SEARCH`, `ARTIST_VIEW`, `ALBUM_VIEW` and `IMPRESSION`. Live Radio
reports the same play events. Previews are flagged (`is_preview`), so a finished 30-second
preview isn't read as a skip.

## Architecture

```
Events (iOS, batched, offline-safe) → POST /events (202) → Redis stream → worker
   → short-term session profile (Redis, ~2 h half-life)
   → long-term taste (Postgres, ~60-day half-life; artist/genre/language/album affinity)
Candidate sources: history · similar artists (ListenBrainz/Last.fm/Deezer) · same artist/album ·
   co-listening · LB Radio · fresh releases · trending (Audius/Jamendo, ListenBrainz charts) ·
   regional/language pools · rediscovery
Ranker: readable linear score with configurable weights + existing learned ranker,
   per-feature contributions logged as reasons
Re-rank: artist/album/language diversity limits + bandit exploration slots
Feed builder: sections scored, ordered and trimmed → GET /home
```

* Cold start: personal weight = n / (n + 20) interactions; onboarding choices + regional/language popularity + fresh releases.
* A session's interests only reach long-term taste after appearing in ≥ 3 sessions on different days.
* Feed items are MusicBrainz/ListenBrainz entities; a playable catalog track is matched only on tap
  and stored (`track_references.recording_mbid`), to keep source requests low.
* Film/soundtrack links only when MusicBrainz says so (release-group secondary type "Soundtrack",
  film relationships). Language comes from release metadata (`tel`, `hin`, `tam`, `mal`, `kan`, `eng`).

## Phases

| # | Phase | Main work | Database |
|---|---|---|---|
| 1 | Assessment | This document | — |
| 2 | Design system | Tokens for typography, spacing, radii, artwork sizes, surfaces, motion; skeleton/empty/error states | — |
| 3 | Navigation + Home | `GET /home` with server-ordered sections; iOS feed renderer per section type | Feed cache in Redis |
| 4 | Catalog | Store canonical MusicBrainz entities; artist and album pages; soundtracks | 0004: artists, release_groups, recordings |
| 5 | Events | `POST /events`, worker, iOS `EventRecorder` (consent-gated) | 0005: listening_events |
| 6 | Taste profile | Long-term + session profiles | taste_profiles + Redis |
| 7 | Candidates | One module per source | — |
| 8 | Ranking | Weight sets, reason logging, diversity re-rank, offline replay | — |
| 9 | Sparks | Small set of very likely next listens | — |
| 10 | Song/Artist radio | Gradual drift outward from a seed | Redis state |
| 11 | Search | Grouped results (top, songs, artists, albums, soundtracks) | — |
| 12 | Player surfaces | `PlayerController` for songs and Live Radio; queue, shuffle, repeat, play next; mini player, Now Playing, queue view, AirPlay, lock screen and Control Center, background audio | — |
| 13 | Performance | Artwork disk cache and prefetch, signposts, pagination, indexes | Indexes |
| 14 | Polish | Accessibility, full screenshot tour, load tests | — |
