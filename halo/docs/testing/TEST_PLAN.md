# Test plan

| Layer | Where | How to run |
|---|---|---|
| Backend unit + API | `halo/backend/tests` | `pytest -q` |
| Session ranking | `tests/test_session.py` | constraints, valence, artist matching, interleaving, recency |
| Catalog quality | `tests/test_catalog_quality.py` | re-upload filter, language/energy/valence estimates |
| iOS core (Linux/macOS) | `halo/ios/Tests/HaloCoreTests` | `swift test` (Docker `swift:6.1-noble` on Linux) |
| Intent corpus | `IntentCorpusTests.swift` | 133 curated utterances; accuracy printed as `HALO-METRIC`, floor 0.98 |
| Drive session | `DriveSessionTests.swift` | start, rerank, ambiguity question, skips, offline pool |
| iOS app + UI tour | CI `ios-xcode` | simulator build, unit tests, screenshot tour |
| Speech capability spike | `Tests/HaloTests/SpeechSupportDiagnostics.swift` | prints `HALO-SPIKE` lines in CI |

Corpus rules: expectations describe what the listener means; misses are printed, not deleted;
the floor only rises. No song lyrics in fixtures.

Not yet covered: real-device speech accuracy (needs a device), held-out corpus from real
listeners, network-failure end-to-end tests on device, load tests.
