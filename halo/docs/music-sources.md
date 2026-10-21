# Music sources

Halo plays only music that is free and legal to stream. Audio goes straight from each source
to the iPhone; the backend never downloads, proxies or stores audio. It caches track
**metadata** only (search pages 6 h, tracks 24 h, charts 1 h; at most 30 days).

| Source | What plays | Key | Setting | Code |
|---|---|---|---|---|
| [Audius](https://docs.audius.org/) | Full songs published by the artists | None (optional key raises rate limits) | `HALO_AUDIUS_ENABLED` (default `true`), `HALO_AUDIUS_API_KEY` | `backend/app/services/catalog/audius.py` |
| [Jamendo](https://developer.jamendo.com/v3.0) | Full Creative Commons songs | Free client id | `HALO_JAMENDO_CLIENT_ID` (off while empty) | `jamendo.py` |
| [iTunes Search API](https://performance-partners.apple.com/search-api) | 30-second previews | None | `HALO_ITUNES_PREVIEWS_ENABLED` (default `false`), `HALO_ITUNES_COUNTRY` (default `IN`) | `itunes.py` |

Track ids are `<source>:<id>` (`audius:D7KyD`, `jamendo:1532771`, `itunes:1440857781`).
`CatalogService` (`service.py`) queries every enabled source concurrently (6 s each; a slow or
failing source is skipped with a warning), ranks by text relevance, then a bonus for full
songs, then popularity, and drops a preview when the same song is available in full. Trending
uses Audius and Jamendo only. With no source enabled, catalog endpoints return
`503 catalog_not_configured` and production startup fails.

Every track carries `attribution` (`provider`, `label`, `url`), and the app shows it on rows,
cards, Song Details and Now Playing.

## Audius

* Every request sends `app_name=Halo`, as the Audius API asks of every app. Change
  `APP_NAME` in `audius.py` if you ship under another name.
* Streams come from `/v1/tracks/{id}/stream`. Unlisted, deleted, non-streamable and gated
  (paid or token-gated) tracks are dropped.
* Attribution: artist name, "Audius" badge and a link to the track page on audius.co.
* Enable: on by default. Set `HALO_AUDIUS_ENABLED=false` to turn it off. An API key from
  [audius.co](https://audius.co) (`HALO_AUDIUS_API_KEY`) is optional.

## Jamendo

* Every track has a Creative Commons licence (`license_ccurl`). Halo shows it per track as
  "“Title” by Artist · CC BY-NC-SA 3.0", linked to the licence, on Song Details and Now Playing,
  plus a link to the track on jamendo.com. This is the attribution CC licences require.
* Most Jamendo music is **non-commercial** (NC). The free API client id covers
  non-commercial use, which is how Halo runs: no ads, no paid tier. A paid or ad-supported
  deployment needs a commercial agreement with Jamendo first (see the API terms on
  devportal.jamendo.com).
* Enable: create an app at [devportal.jamendo.com](https://devportal.jamendo.com) and set
  `HALO_JAMENDO_CLIENT_ID`. Jamendo is skipped while it's empty.

## iTunes previews

Apple allows previews only to promote the song in its store
([Search API terms](https://performance-partners.apple.com/search-api)). Halo:

* labels every preview "Preview" (`is_preview: true`, gold badge) and never presents it as a
  full song;
* attributes it ("Preview courtesy of Apple Music") and links to the song's Apple page with
  **Listen on Apple Music**;
* streams `previewUrl` directly, never saves it, and doesn't build charts from previews;
* uses the store set by `HALO_ITUNES_COUNTRY` (two-letter code, default `IN`), which is where
  most mainstream and Indian songs come from.

Enable: off by default, because Halo plays full songs only. Set
`HALO_ITUNES_PREVIEWS_ENABLED=true` to add previews; the app still hides them in Search.

## Not used

YouTube was removed: its terms forbid audio-only and background playback, which an in-app
music player needs. The YouTube Data API key (`HALO_YOUTUBE_API_KEY`) is no longer read.
