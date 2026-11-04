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

## Target (later)

Interfaces: `MusicCatalogProvider`, `MusicSearchProvider`, `MusicPlaybackProvider`,
`MusicRightsResolver`, `MusicEntitlementChecker`, `PlaybackRouter`. Every track will carry a
canonical identity, provider identity, rights status, territory and entitlement requirements;
the router refuses playback without a positive rights check.

* **Apple Music (MusicKit):** deferred by the owner. Constraints to verify first: subscriber-only
  full playback through `ApplicationMusicPlayer`, no audio access or proxying, developer token
  and terms. Never extract audio.
* **Halo independent catalog:** artist onboarding with rights declarations (sound recording and
  composition separately), upload validation and transcoding, takedown workflow, usage ledger.
  An upload never establishes ownership by itself. Needs legal agreements: approval required.
