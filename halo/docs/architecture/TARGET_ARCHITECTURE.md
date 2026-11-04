# Halo: target architecture

Status labels: **built** (in code, tested), **next** (planned for the next phases), **later**.

```
 voice / text ─▶ IntentParser ─▶ EntityResolver ─▶ IntentDelta
                    (on-device, deterministic)        │
                                                      ▼
                                      SessionReducer (SessionState.apply, undo)
                                                      │ session state (never stored server-side)
                         ┌────────────────────────────┴───────────────────────────┐
                         ▼                                                        ▼
         POST /session/candidates (server)                          SessionRanker (on-device)
         candidates → hard constraints → score → diversify          re-rank the pool, offline OK
                         │                                                        │
                         └───────────────▶ SmartQueue (PlaybackQueue bands) ◀─────┘
                                           user · context · Halo Flow
                                                      │
                                          PlaybackRouter ─▶ provider players
```

| Component | Where | Status |
|---|---|---|
| `IntentDelta` / `SessionOperation` | `ios/Halo/Core/Voice/IntentDelta.swift` | built |
| `IntentParser` + `VoiceLexicon` | `Core/Voice/IntentParser.swift`, `VoiceLexicon.swift` | built |
| `EntityResolver` (aliases, spellings, ambiguity) | `Core/Voice/EntityResolver.swift` | built (static table) |
| `SessionReducer` | `SessionState.apply` / `undo` | built |
| `SessionRanker` (mirror of server `session-v2`) | `Core/Voice/SessionRanker.swift` | built |
| Session candidates | `backend/app/services/recommendations/session.py` | built |
| Smart queue | `PlaybackQueue` (user, context, flow bands) | built |
| Entity store with provider ids (MusicBrainz) | backend | next |
| LLM fallback parser (transcript only, validated output) | backend `services/ai` | next |
| Halo Recall (memory search, clarification) | new `services/recall` | later |
| Provider / rights / entitlement layer | new `services/catalog/rights` | later |
| Siri App Intents, CarPlay (entitlement required) | iOS | later |
| Android (Media3, Android Auto) | new app | later |

Design rules that hold everywhere:

* One ranking definition: weights are versioned (`session-v2`) and identical on server and phone.
* Hard constraints (exclusions, avoided moods, "only" languages, playability) apply before scoring.
* Session changes never write the long-term profile; only explicit profile-scoped operations
  ("never play this again", "I like this") become feedback, and only with consent.
* No language model chooses songs; models may only produce structured operations or queries
  that are validated, and every playable track comes from a catalog source.
