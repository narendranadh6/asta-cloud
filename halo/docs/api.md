# Halo REST API (v1)

Interactive docs: `http://localhost:8000/docs` (disabled in production). The machine-readable
spec is [`openapi.json`](openapi.json). Regenerate it with:

```bash
cd backend && python -c "import json; from app.main import create_app; \
  print(json.dumps(create_app().openapi(), indent=1))" > ../docs/openapi.json
```

## Conventions

* JSON bodies use `snake_case`. Timestamps are RFC 3339.
* **Auth:** `Authorization: Bearer <token>` on everything except `/health` and
  `/api/v1/auth/register`.
* **Errors:** always this shape:

```json
{"error": {"code": "track_unavailable", "message": "This song is no longer available from its source", "details": {}, "request_id": "…"}}
```

| Status | Codes |
|---|---|
| 401 | `unauthenticated`, `invalid_token`, `token_expired`, `account_deleted` |
| 404 | `not_found`, `track_unavailable` (another user's resources also return 404) |
| 422 | `validation_error`, `track_unavailable` (unverifiable ids, listed in `details.track_ids`), `invalid_reorder` |
| 429 | `rate_limited` (+ `Retry-After`) |
| 502 | `catalog_unavailable` (every source failed; + `Retry-After`), `search_failed` |
| 503 | `catalog_not_configured` (no music source enabled on the server) |

* **Track ids** are `<source>:<id>`, where source is `audius`, `jamendo` or `itunes`
  (e.g. `audius:D7KyD`). Every track has `stream_url` (play it directly; audio never goes
  through Halo), `is_preview` (true for 30-second iTunes previews), `license` (Jamendo's
  Creative Commons licence), `external_url` and `attribution` (`provider`, `label`, `url`),
  which clients must show. See [music-sources.md](music-sources.md).
* **Rate limits** (per user, per minute; configurable): search and tracks 30, AI 6,
  registration 10 per IP, everything else 120.

## Endpoints

The MusicBrainz and ListenBrainz endpoints return `503 metadata_disabled` /
`503 discovery_disabled` when switched off in configuration, and `502 metadata_unavailable` /
`502 discovery_unavailable` when the upstream service is down.

| Method | Path | Description |
|---|---|---|
| GET | `/health` | Status, `music_sources` (enabled sources), DB/cache/catalog checks (`checks.catalog` is `not_configured` with no source enabled), `ai_planner` |
| POST | `/api/v1/auth/register` | Create an anonymous account and return `{access_token, expires_at, user_id}` |
| POST | `/api/v1/auth/refresh` | New token for the current user |
| GET | `/api/v1/search?q=&kind=song\|artist&page_token=&limit=` | Results from every enabled source, ranked and deduplicated (full songs win over previews), with `sources` and `next_page_token` |
| GET | `/api/v1/search/suggestions?q=` | From your Halo history plus curated seeds |
| GET | `/api/v1/tracks/{track_id}` | One track with a fresh `stream_url`. 404 `track_unavailable` if it was removed or can't be streamed |
| GET | `/api/v1/artists/{artist_id}` | Artist page (Audius, Jamendo): profile, `top_tracks` (most played first), `albums`. Id is `<source>:<artist_id>` from a track. 404 `artist_unavailable` |
| GET | `/api/v1/albums/{album_id}` | Album page with its playable `tracks` in album order. 404 `album_unavailable` |
| GET | `/api/v1/history/search` | Your recent searches |
| DELETE | `/api/v1/history/search` | Clear search history |
| GET | `/api/v1/playlists?limit=&offset=` | Your playlists (summaries) |
| POST | `/api/v1/playlists` | Create. Every `track_ids` entry is verified with its source |
| GET | `/api/v1/playlists/{id}` | Playlist with ordered items |
| PATCH | `/api/v1/playlists/{id}` | Rename or describe; set `mood` |
| DELETE | `/api/v1/playlists/{id}` | Delete |
| POST | `/api/v1/playlists/{id}/items` | `{track_id, position?, note?}`. The track is verified first |
| DELETE | `/api/v1/playlists/{id}/items/{item_id}` | Remove an item. Positions are renumbered |
| PUT | `/api/v1/playlists/{id}/items/order` | `{item_ids: [...]}`. Must list every item exactly once |
| POST | `/api/v1/ai/playlist` | Studio. Body: `description, mood?, genres[], language?, energy?, duration_minutes, discovery, exclude_track_ids[]` |
| POST | `/api/v1/ai/chat` | Halo assistant. Body: `{message, conversation_id?, history[]}` |
| GET | `/api/v1/home` | Home feed: `{sections[], personalized, generated_at}`. Each section has `id, type, title, eyebrow` (why it's shown), `layout` (`rail`, `feature_rail`, `artist_rail`, `rows`, `tiles`, `local`), `items[]`, `source` and `score`. Sections arrive in display order; `local` sections are placeholders the app fills from data on the device. Weights: `HALO_HOME_SECTION_WEIGHTS` |
| GET | `/api/v1/discover/trending?genre=&limit=` | Full songs trending this week on Audius and Jamendo, interleaved |
| GET | `/api/v1/recommendations/next?track_id=&limit=` | Up next: co-listening, same artist and similar artists, ranked |
| GET | `/api/v1/radio/stations?tag=&language=&country=&q=&limit=` | Live internet radio stations (Radio Browser). `502 radio_unavailable` if the directory is down |
| GET | `/api/v1/metadata/track?track_id=` | Canonical facts from MusicBrainz: recording MBID, artist credit, earliest official release (album, date, label, catalog number, cover art), ISRCs, genres. `matched=false` when MusicBrainz isn't confident (score ≥ 85 and length within 25 s are required) |
| GET | `/api/v1/metadata/artist?name=` | MusicBrainz artist (MBID, type, area, life span, genres) plus ListenBrainz popular recordings when `HALO_LISTENBRAINZ_TOKEN` is set |
| GET | `/api/v1/discover/fresh-releases?days=&upcoming=&limit=` | Recent (or upcoming) releases from ListenBrainz with listen counts and Cover Art Archive artwork |
| GET | `/api/v1/discover/most-listened?range=week\|month\|quarter\|year\|all_time&limit=` | Most-listened recordings across ListenBrainz |
| POST | `/api/v1/recommendations/feedback` | `{track_id, rating: like\|dislike\|skip\|save, session_id?, artist?}`. Stored only with consent |
| GET | `/api/v1/preferences` | Explicit preferences |
| PUT | `/api/v1/preferences` | Replace preferences. Turning personalization on records the consent time |
| GET | `/api/v1/preferences/taste` | Taste profile inferred from Halo activity only |
| DELETE | `/api/v1/preferences/taste` | Reset taste memory (keeps playlists and explicit settings) |
| GET | `/api/v1/me/export` | Full JSON export |
| DELETE | `/api/v1/me` | Delete the account and all data |

### Example: AI playlist draft

```http
POST /api/v1/ai/playlist
{"description": "relaxing Telugu melodies from the 2000s", "mood": "calm", "duration_minutes": 45}
```

```json
{
  "session_id": null,
  "title": "Telugu Calm Melody",
  "explanation": "I looked for a calm mood; Telugu music; melody; from the 2000s.",
  "intent": {"mood": "calm", "language": "Telugu", "genres": ["melody"], "era": "2000s", "energy": 30,
             "duration_minutes": 45, "discovery": "balanced", "search_queries": ["Telugu melody songs 2000s", "..."]},
  "planner": "heuristic",
  "queries": ["Telugu melody songs 2000s", "Telugu calm songs 2000s"],
  "tracks": [{"track": {"id": "jamendo:…", "source": "jamendo", "title": "…", "artist": "…", "stream_url": "https://…",
                        "is_preview": false, "license": {"name": "CC BY-NC-SA 3.0", "url": "https://creativecommons.org/licenses/by-nc-sa/3.0/"},
                        "attribution": {"provider": "jamendo", "label": "Jamendo", "url": "https://www.jamendo.com/track/…"}},
              "score": 1.37, "reasons": ["Matches melody, telugu", "Found for “Telugu melody songs 2000s”"],
              "matched_query": "Telugu melody songs 2000s"}],
  "total_duration_seconds": 2710,
  "target_duration_seconds": 2700,
  "sources": ["audius", "itunes", "jamendo"],
  "warnings": []
}
```

Each track in a draft also carries `source` (`search`, `similar_artist`, `listenbrainz` or `co_listen`) and
`explore` (true for exploration slots, shown as "Something new for you").

`session_id` is set only when personalization is enabled. A draft isn't saved until the
client creates a playlist from the (edited) list of `track_ids`.
