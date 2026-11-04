# Halo: current state (audit)

Audited 2026-11-04 on branch `muse-app` at commit 93e3799, before the HALO Context slice.
Every claim cites the code or a run. "Verified" means a test or CI run exercised it.

## 1. Repository structure

| Path | What it is |
|---|---|
| `halo/backend/` | FastAPI service (Python 3.12+), SQLAlchemy + Alembic, Redis cache, worker tasks |
| `halo/backend/app/services/catalog/` | Catalog sources: `audius.py`, `jamendo.py`, `itunes.py` (off by default), `service.py` (merge, dedupe, cache), `features.py`, `quality.py` |
| `halo/backend/app/services/music_sources/` | Metadata and discovery: MusicBrainz, ListenBrainz, similar artists (Last.fm/Deezer), radio (Radio Browser) |
| `halo/backend/app/services/ai/` | `MusicIntent` model, LLM providers (Anthropic, OpenAI-compatible), keyword fallback (`heuristic.py`) |
| `halo/backend/app/services/recommendations/` | v2 pipeline (`pipeline.py`), Thompson sampling (`bandit.py`), learned ranker (`ranker.py`), Halo Drive sessions (`session.py`) |
| `halo/ios/Halo/Core/` | Platform-neutral Swift: networking, models, playback, persistence, voice (`Core/Voice`) |
| `halo/ios/Halo/Features/` | SwiftUI screens, including `Drive/` (speech, voice, Drive screen) |
| `halo/ios/Package.swift` | The Core code as a Swift package, so its tests run on Linux |
| `.github/workflows/halo-ci.yml` | backend, catalog-audit, ios-core-linux, ios-xcode (macOS simulator + UI tour) |

There is no Android code (`find . -name "*.kt"` finds nothing).

## 2. Technology stack

* Backend: FastAPI, Pydantic v2, SQLAlchemy 2 async (SQLite locally, PostgreSQL in CI), Alembic,
  Redis, httpx. Lint: ruff; types: mypy.
* iOS: Swift 6 (strict concurrency), SwiftUI, SwiftData, AVFoundation (`AVPlayer`),
  MediaPlayer (lock screen), Speech (`SFSpeechRecognizer`), `AVSpeechSynthesizer`. iOS 17+.

## 3. Existing features (verified by tests or CI)

* Search and playback of full songs from Audius and Jamendo; Live Radio. One
  `PlayerController` with queue bands (user / context / Flow), shuffle, repeat, session restore,
  lock-screen controls, background audio (`PlayerController.swift`, `PlaybackQueue.swift`).
* Halo Flow: autoplay refill from `/recommendations/next`; during a drive, from the session.
* AI planner: `/ai/chat` turns text into a `MusicIntent` (LLM when configured, keyword
  fallback otherwise); the planner only produces search queries, never URLs (`ai/intent.py`).
* Recommendations v2: candidate sources, scoring, diversity, Thompson-sampling exploration
  (`bandit.py`), optional learned ranker.
* Halo Drive (phase 1, commit 93e3799): push-to-talk speech, deterministic multilingual parser
  (`IntentParser`), `IntentDelta`/`SessionState` with undo, `POST /session/candidates`,
  on-device re-ranking (`SessionRanker`), short spoken replies with ducking, Drive screen.
* Re-upload filter for Audius (`quality.py`), on by default.

## 4. Missing (before this slice)

* Entity resolution: "DSP" stayed "dsp"; aliases and spellings were not mapped.
* Artist matching was exact: "not too much Anirudh" (key `anirudh`) never matched
  "Anirudh Ravichander" (`SessionRanker.swift`, `session.py` used `_key(artist) in excluded`).
* "No sad songs" set a valence target, but tracks had no valence and neither ranker scored it.
* `SessionState.recordSkip` existed but nothing called it.
* No measured intent accuracy; ~40 hand-written parser assertions only.
* Halo Recall, a rights resolver, entitlement checks, Siri/App Intents, CarPlay, Android:
  not started (no code found).

## 5. Technical risks

* Catalog: Audius search finds Telugu film songs, but many are unauthorised re-uploads
  (catalog audit, CI job `catalog-audit`). The filter removes the obvious ones; it can't prove a
  remaining upload is authorised. Licensed Telugu film music needs a licensed provider.
* Speech: on the CI simulator `te-IN` recognition does not exist; `en-IN` exists but is
  server-based there (HALO-SPIKE lines, CI run 39711685970). Real devices are untested.
* The CI UI-test backend log shows a `FOREIGN KEY constraint failed` inserting
  `user_preferences` during registration (run 39711685970). Requests still succeed (201); not
  yet investigated.
* Session `today` scope ends with the drive; it isn't persisted until midnight yet.

## 6. Test coverage (baseline, 2026-11-04)

| Suite | Command | Result |
|---|---|---|
| Backend | `pytest -q` (in `halo/backend`) | 135 passed |
| iOS core on Linux | `swift test` (in `halo/ios`, Docker `swift:6.1-noble`) | 106 passed |
| iOS simulator + UI tour | CI `ios-xcode` | passed (run 39711685970) |

## 7. Catalog limitations

See `CATALOG_AND_RIGHTS.md`. In short: only Audius (artist uploads, terms require attribution
and `app_name`) and Jamendo (Creative Commons, per-track licence) play in full; iTunes previews
are off. No mainstream label catalog; no offline downloads.

## 8. Security concerns

* Provider keys come from environment variables only; none are in the repo.
* The device account is anonymous; the token is in the Keychain.
* Voice: audio is never stored or uploaded by Halo; Apple's recognizer may use Apple's
  servers when on-device recognition isn't available for the locale (documented in Settings).

## 9. Recommended migration strategy

Keep the existing modules and extend them: the Drive session layer already has the right
shape (`IntentDelta` → `SessionState` → candidates → `SessionRanker`). Add the missing pieces
behind the same interfaces (entity resolver, mood features, skip signals), measure on a corpus,
then build Recall and the provider/rights abstraction as new modules beside the catalog.
