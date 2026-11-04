# Playback routing

Today one `PlayerController` (iOS) plays everything through `StreamingAudioEngine` (`AVPlayer`):
a track's `stream_url` comes from the catalog source; previews are flagged and skipped by
Halo Drive. Failing streams are refreshed once through `/tracks/{id}`; three failures in a row
stop playback with a notice.

Queue bands (`PlaybackQueue`): **user** (Play Next / Add to Queue) → **context** (what was
started) → **flow** (Halo's picks). Halo Drive's `startHalo` keeps history and the user band;
`replaceUpcomingFlow` replaces only the flow band. The listener's queued songs are never removed
by Halo.

Ducking: `PlayerController.duck(reason, on)` lowers volume while Halo listens or speaks
(reasons are counted, so overlapping listen/speak doesn't un-duck early).

Target: a `PlaybackRouter` choosing a provider player per track (Audius/Jamendo stream,
MusicKit player for Apple Music subscribers), after an entitlement and rights check. Mixed
provider queues are not promised until both integrations allow it.
