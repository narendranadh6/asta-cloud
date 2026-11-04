# Catalog and rights

## Sources today

| Source | What plays | Rights basis | Status |
|---|---|---|---|
| Audius | Full songs uploaded by artists | Audius API terms (attribution, `app_name`); uploader-asserted rights | On; re-upload filter on (`HALO_FILTER_REUPLOADS`) |
| Jamendo | Full songs | Creative Commons per track (`license_ccurl`), shown in the player | On when `HALO_JAMENDO_CLIENT_ID` is set |
| iTunes Search | 30-second previews | Apple preview terms | Off by default (`HALO_ITUNES_PREVIEWS_ENABLED`) |
| Radio Browser | Live stations | Station streams as listed | On |
| MusicBrainz, ListenBrainz, Last.fm, Deezer | Metadata and similarity only | Their API terms | On (no audio) |

Not verified here (needs legal review, not engineering): commercial-use terms of each API for
a paid product, territory restrictions, and whether every Audius upload is authorised. The
catalog audit shows many Telugu film songs on Audius are unauthorised re-uploads; the filter
removes obvious ones by name patterns, which is a mitigation, not proof of rights.

## Rights policy (fails closed)

`RightsPolicy` (settings `HALO_DEPLOYMENT_USE`, `HALO_AUDIUS_COMMERCIAL_TERMS_CONFIRMED`,
`HALO_JAMENDO_COMMERCIAL_LICENSE`): the default deployment use is **commercial**, and then
nothing plays until rights are confirmed per source — Audius after its API terms are reviewed for
that use, Jamendo only with a Jamendo commercial licence (a Creative Commons licence on a track is
not enough for a commercial service; many are NC). Unknown or unparseable licences are refused in
every mode. The local server runs as non-commercial (personal/development use).

Search and identification are separate from playback authorization: every track returned by the
catalog carries `playback_authorized` and a `playback_restriction` reason; a refused track can
still be found and shown, but its stream URL is withheld. Decisions are made when tracks are
read, so a policy change also applies to cached results.

Not implemented on purpose: scraping or proxying audio from sites without rights (e.g. "Naa
Songs" style download sites), DRM circumvention, or treating API access as permission to play.

## Rights gate (built)

`app/services/catalog/rights.py`: `SourcePolicyRightsResolver.decide(track)` allows only full
streams from authorised sources (Audius under its API terms; Jamendo with a CC licence) and
refuses previews, missing streams and any unknown source by default. Session candidates apply
it before scoring, so no weight, client field or model output can bring a refused track back.
`OpenCatalogEntitlements` allows Audius/Jamendo and refuses anything needing a subscription.

## Provider interfaces (built as interfaces; adapters later)

`app/services/catalog/providers.py`: `MusicSearchProvider`, `MusicMetadataProvider`,
`MusicPlaybackProvider`, `MusicCatalogProvider`, `PlaybackDescriptor` (`stream_url` for sources
the app streams; `device_player` for a provider's own on-device player, e.g. MusicKit, where
Halo never touches audio) and `PlaybackRouter` (rights → entitlement → player descriptor).
Only `StreamUrlPlayback` exists; MusicKit and HALO-owned adapters are not implemented and are
refused by the router until they are, with their rights basis and entitlement check.

## Target (later)

Every track will carry a canonical identity, provider identity, rights status, territory and
entitlement requirements; the router refuses playback without a positive rights check.

* **Apple Music (MusicKit):** deferred by the owner. Constraints to verify first: subscriber-only
  full playback through `ApplicationMusicPlayer`, no audio access or proxying, developer token
  and terms. Never extract audio.
* **Halo independent catalog:** artist onboarding with rights declarations (sound recording and
  composition separately), upload validation and transcoding, takedown workflow, usage ledger.
  An upload never establishes ownership by itself. Needs legal agreements: approval required.
