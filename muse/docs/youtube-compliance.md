# YouTube API Services compliance

MUSE uses the **YouTube Data API v3** only to search for and read public video
**metadata**. It is designed around the
[YouTube API Services Terms of Service](https://developers.google.com/youtube/terms/api-services-terms-of-service)
and [Developer Policies](https://developers.google.com/youtube/terms/developer-policies).
Review both, and complete Google's API compliance audit if you need more quota, before
shipping.

## What MUSE does

| Area | Behaviour | Where |
|---|---|---|
| API key | Lives only on the backend (`MUSE_YOUTUBE_API_KEY`). It is never shipped in the iOS app or returned by any endpoint | `backend/app/core/config.py` |
| Endpoints | `search.list` (`type=video`, `videoCategoryId=10`, `safeSearch=moderate`) and `videos.list` (`snippet,contentDetails,status,statistics`) | `backend/app/services/youtube/client.py` |
| Verification | Every search result is re-checked with `videos.list`. Private, unprocessed or region-blocked videos are dropped. Ids must match `^[A-Za-z0-9_-]{11}$` | `client.py`, `ids.py` |
| No fabricated ids | Playlists and AI drafts accept only ids that the provider confirms in the same request. The LLM may only produce search text; queries containing URLs or `v=` are rejected | `routes.py::verified_tracks`, `ai/intent.py` |
| Attribution | Every track carries `attribution` (`provider`, `label`, `url`). The app shows a YouTube badge on rows, "Source: YouTube" on details, and "Results and metadata provided by YouTube" under results | `schemas`, `TrackRow`, `SongDetailView` |
| Playback | Handed off to the user's browser or the YouTube site. No embedded or custom player, no fake playback controls | `BrowserIntegration/` |
| Content | No downloading, caching, proxying or extraction of audio/video streams. No ad blocking or modification | (not implemented by design) |
| Storage window | Metadata cache TTLs are clamped to 30 days (`YOUTUBE_MAX_RETENTION_SECONDS`). Stored track references are refreshed after 25 days or marked unavailable (`python -m app.tasks.refresh_metadata`, run daily). The iOS app refreshes saved metadata after 25 days and purges unsaved "discovered" entries after 30 | `config.py`, `tasks/refresh_metadata.py`, `LibraryStore.enforceRetention` |
| Thumbnails | Only HTTPS thumbnail URLs returned by the API are used, and they are loaded directly from YouTube's CDN | `client.py` |
| Deletion | Users can delete their account (`DELETE /api/v1/me`), which cascades to every stored reference they own | `routes.py` |

## Quota

Default quota is 10,000 units per day. A search costs about 101 units (`search.list` = 100,
plus one `videos.list` = 1), so one AI playlist with five planned queries costs about 505.

Protections:

* Redis cache of search pages (6 h) and videos (24 h), keyed by normalised query.
* Per-user rate limits: 30 searches/min, 6 AI requests/min (`MUSE_RATE_LIMIT_*`).
* A quota error surfaces as `503 search_quota_exceeded` with `Retry-After`. Saved music keeps
  working.

## Demo mode

Without an API key the backend serves a **fictional** demo catalog (`provider: "demo"`).
Demo items are labelled everywhere, carry no real YouTube ids, and the app refuses to hand
them off to a browser.

## Related videos

YouTube removed `search.list?relatedToVideoId` in 2023. MUSE's "related music" is therefore
a channel search, which is real data, not a guess.

## Search suggestions

The Data API has no suggestion endpoint, and MUSE doesn't scrape unofficial ones.
Suggestions come from the user's own MUSE search history plus a curated seed list.
