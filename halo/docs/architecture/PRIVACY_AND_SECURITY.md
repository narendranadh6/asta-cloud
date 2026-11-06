# Privacy and security

| Data | Where | Retention |
|---|---|---|
| Session state (vibe, language, exclusions, skips) | Phone memory only; sent with each candidates request | Ends with the drive; server keeps nothing (`session.py`) |
| Microphone audio | Never stored by Halo | Only while the Talk button is active |
| Transcripts | Phone memory for the current turn | Not stored; may be sent to the server LLM fallback only when that ships, with consent |
| Long-term preferences, feedback | Server, only with personalization consent | Deletable (`DELETE /me`) |
| "Not today" artists | Phone (UserDefaults), names and end times only | Until local midnight, or Reset |
| Inferred listening signals | Phone memory, inside the drive's session | End of the drive, or Reset |
| Provider keys | Server environment variables | Never in the app or repo |
| Device token | iOS Keychain | Until account deletion |

| Consent choices | Phone (UserDefaults): processor, choice, date, disclosure version | Until changed in Settings › Voice & privacy |
| Speech test results | Phone memory: prompt id, transcript, WER, timings (no audio) | Until the tester clears or shares them |

Consent (`VoiceConsent`): nothing is granted by default; each processor has a versioned
disclosure stating what leaves the iPhone, who processes it and what is kept, and a new version
asks again. Processors: Apple's server speech recognition (used only when the device can't
recognize the language on-device), Halo server speech (not available: no provider), and the
command fallback (text only). Halo's statements cover only what Halo does; Apple's own handling
is referred to Apple's privacy policy, which Halo has not independently verified.

Before this milestone, Apple's server recognition could be used without a prompt whenever
on-device recognition wasn't available; it now requires consent, and the listener enforces
on-device recognition when routed there.

Rules in code:

* Tap the Halo orb to talk (push-to-talk). The wake word "Halo" is **opt-in** (Settings ›
  Halo Drive › Listen for "Halo", off by default) and only runs while the app is open in the
  foreground, with **on-device recognition required** (`requiresOnDeviceRecognition`): if the
  iPhone can't recognize the language on the device, the option is unavailable, so continuous
  audio never leaves the phone. Each utterance is checked for the wake word and discarded; nothing
  is stored. It stops when the app leaves the foreground, pauses while a command is heard or
  Halo speaks, and iOS shows its microphone indicator while it runs. Listening when the app is
  closed or the phone is locked isn't possible for third-party apps; Siri is the route for that.
* On-device recognition when the locale supports it (`requiresOnDeviceRecognition`).
* Halo never infers emotions from voice.
* External text (metadata, transcripts, provider responses) is untrusted: the planner rejects
  URL-like queries, IDs are validated (`TrackID.isValid`, `is_valid_track_id`), request sizes
  are bounded (Pydantic limits on every session field).
* No language model can bypass catalog validation: playable tracks only come from sources.

Open items: device testing of the consent flow; a provider and data-processing terms before any
Halo server speech or the command fallback is enabled.
