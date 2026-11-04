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
| iOS app + UI tour | CI `ios-xcode` | simulator build, unit tests, screenshot tour |
| Speech capability spike | `Tests/HaloTests/SpeechSupportDiagnostics.swift` | prints `HALO-SPIKE` lines in CI |

Corpus rules: expectations describe what the listener means; misses are printed, not deleted;
the floor only rises. No song lyrics in fixtures.

Not yet covered: real-device speech accuracy (needs a device), held-out corpus from real
listeners, network-failure end-to-end tests on device, load tests.
