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

Rules in code:

* Push-to-talk only; no wake word; the microphone never starts by itself.
* On-device recognition when the locale supports it (`requiresOnDeviceRecognition`).
* Halo never infers emotions from voice.
* External text (metadata, transcripts, provider responses) is untrusted: the planner rejects
  URL-like queries, IDs are validated (`TrackID.isValid`, `is_valid_track_id`), request sizes
  are bounded (Pydantic limits on every session field).
* No language model can bypass catalog validation: playable tracks only come from sources.

Open items: an explicit consent screen before any server speech or LLM fallback.
