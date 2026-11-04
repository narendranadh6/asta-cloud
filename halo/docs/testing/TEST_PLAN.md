# Test plan

| Layer | Where | How to run |
|---|---|---|
| Backend unit + API | `halo/backend/tests` | `pytest -q` |
| Session ranking | `tests/test_session.py` | constraints, valence, artist matching, interleaving, recency |
| Catalog quality | `tests/test_catalog_quality.py` | re-upload filter, language/energy/valence estimates |
| iOS core (Linux/macOS) | `halo/ios/Tests/HaloCoreTests` | `swift test` (Docker `swift:6.1-noble` on Linux) |
| Intent corpus | `IntentCorpusTests.swift` | 133 curated utterances; accuracy printed as `HALO-METRIC`, floor 0.98 |
| Drive session | `DriveSessionTests.swift` | start, rerank, ambiguity question, skips, offline pool |
| Flow 2.0 | `FlowTwoTests.swift` | signals and caps, explicit-over-inferred, midnight in time zones and DST, persistence, reset, queued songs kept, rights/playability, spacing |
| Holdout | `HoldoutEvaluationTests.swift` + `docs/testing/holdout-v1.json` | report only, frozen, never tuned against |
| Rights and routing | `backend/tests/test_rights.py` | policy, router order, refused tracks never ranked |
| Ranking benchmark | `backend/tests/test_ranking_benchmark.py`, `python -m app.tools.ranking_benchmark` | synthetic, reproducible, zero constraint violations |
| Database | `backend/tests/test_database.py` | concurrent rollback can't undo a sign-up (FK regression) |
| Context 2.0 | `ContextTwoTests.swift` | milestone examples, unrelated requests, no action, clarify, common words, Telugu script, entities, negation scopes, wire round trip, conversations, drive decisions, fallback |
| Calibration | `CalibrationTests.swift` | refits the table on development data; fails on drift |
| Holdout v2, v3 | `HoldoutV2EvaluationTests.swift` + `docs/testing/holdout-v2.json`, `holdout-v3.json` | report only; each run once and retired; reports also written to `ios/.build/holdout-reports` |
| Negation | `NegationTests.swift` | intensified English, Telugu negative imperatives, false negations, never-opposite-action safety, scope, skip/enough |
| Context follow-ups | `ContextThreeTests.swift` | evidence for known names, false prefixes, questions about next, Telugu forms, names in any phrasing, nameless follow-ups, particles |
| Speech routing and consent | `SpeechCapabilityTests.swift` | on-device first, consent before server, typing fallback, revocation, disclosures, WER |
| AI fallback | `backend/tests/test_intent_fallback.py` | grammar, whole-answer validation, minimal payload, timeouts, consent and disabled endpoint |
| Rights policy | `backend/tests/test_rights.py` | commercial fail-closed, CC parsing, search without streams |
| Real-device speech | `docs/testing/SPEECH_EVALUATION.md` | procedure only; no recordings yet |

Datasets: development = the 133-case corpus, the retired holdout v1 and the Context 2.0 tests.
Holdouts are frozen before evaluation, run once, and retired once their misses are read; a new
holdout (v3) is needed before the next accuracy claim.
| iOS app + UI tour | CI `ios-xcode` | simulator build, unit tests, screenshot tour |
| Speech capability spike | `Tests/HaloTests/SpeechSupportDiagnostics.swift` | prints `HALO-SPIKE` lines in CI |

Corpus rules: expectations describe what the listener means; misses are printed, not deleted;
the floor only rises. No song lyrics in fixtures.

Not yet covered: real-device speech accuracy (needs a device), held-out corpus from real
listeners, network-failure end-to-end tests on device, load tests.
