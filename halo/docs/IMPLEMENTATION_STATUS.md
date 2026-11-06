# Implementation status

Updated 2026-11-04 (third milestone: Context 2.0).

Legend: **implemented and tested** = code plus automated tests run in this repository;
**not device-tested** = runs in tests/simulator only; **proposed** = not built; **blocked** =
needs permission, licence, hardware or a paid service.

Sixth milestone (weights): act-or-ask weights tuned by cross-validation on development data
(+0.7 points CV); ranking weights session-v4 tuned on synthetic seeds and confirmed on unseen
ones (relevance 0.704 → 0.750, skips 0.233 → 0.199); parsing gaps from v4/v5 fixed. Holdout v5:
exact 88.5%, outcome 96.5%, false actions 0 of 61, clarify precision 100%.

Fifth milestone (weak areas): acceptances and rules don't start playback (decided), double
negatives, interjections, incomplete-with-fillers, "their" follow-ups, undo phrasings, Telugu
tempo and names, negated controls by rule. Holdout v4: exact 86.7%, conversation state 90.9%,
clarify P/R 73.3%/75.9%, wrong-direction 0 of 345, false actions 2 of 46 (fixed after).

Fourth milestone: negation fixed (no wrong-direction action in the development tests; 3 of
383 on holdout v3 at evaluation time, fixed afterwards); names in any phrasing, questions about
"next", Telugu stems, nameless follow-ups. Holdout v3: exact 79.9%, false actions 0.0%,
conversation state 78.4% (details in testing/BENCHMARK_RESULTS.md).

| Context 2.0 item | Status |
|---|---|
| Decision layer: execute / clarify / unsupported / no action | Implemented and tested |
| Unrelated requests never act (false-action rate 2.3% on holdout v2) | Implemented and tested |
| Calibrated confidence (dev-fitted table; overconfident on holdout, ECE 0.102) | Implemented and tested |
| Telugu-script stems, relative dates, tempo, genres, songs, albums, films | Implemented and tested (gaps listed in BENCHMARK_RESULTS) |
| Context references ("not too much" = last artist, "this song", "never") | Implemented and tested |
| Clarification keeps the session; incomplete requests completed by the answer | Implemented and tested |
| Session expiry after 2 h idle (today's exclusions kept) | Implemented and tested |
| Speech capability probe and route planner | Implemented and tested (fakes); simulator in CI; **not device-tested** |
| Consent before any audio/text leaves the iPhone (Apple server, fallback) | Implemented and tested (logic); UI **not device-tested** |
| Typing fallback; recognition failures change nothing | Implemented and tested |
| Speech test screen (WER + intent match, text only) | Implemented; **no recordings made** |
| AI fallback interface + validation (off by default) | Implemented and tested; **no provider enabled** (paid; needs approval) |
| Halo server speech recognition | Proposed (consent and routing ready; no provider) |
| Rights gate fails closed (commercial default) | Implemented and tested; **commercial use blocked** until Audius terms / Jamendo licence are confirmed |
| MusicBrainz alias import | Proposed: their data is CC0 but the public API has rate limits and terms to check; kept optional |
| Siri / App Intents, CarPlay | Not started; CarPlay blocked on the entitlement |


| Area | Completed | Tested | Partial | Blocked | Not started |
|---|---|---|---|---|---|
| Halo Context: parser, deltas, session, undo | ✓ | ✓ corpus + unit | | | |
| Entity resolver (aliases, spellings, ambiguity) | ✓ static table | ✓ | MusicBrainz-backed store | | |
| Artist matching on credits | ✓ server + phone | ✓ | | | |
| Mood exclusion ("no sad songs") | ✓ | ✓ | valence only from tags/moods | | |
| Listening signals (early/late skips, completions, replays) | ✓ capped, session-only, explicit wins | ✓ | session length | | |
| "Not today" until local midnight (explicit time zone, DST-safe) | ✓ persisted on device | ✓ | | | |
| Reset personalization | ✓ Drive "Reset", Taste "Reset taste memory" clears Drive memory too | ✓ logic; UI built in CI | | | |
| Session candidates + on-device ranking | ✓ `session-v3` (artist spacing) | ✓ | | | |
| Rights as a hard constraint | ✓ `SourcePolicyRightsResolver` on every candidate | ✓ | | | |
| Provider-independent interfaces (search, metadata, playback, rights, entitlement, router) | ✓ interfaces + current sources | ✓ | MusicKit / HALO catalog adapters | approval / agreements | |
| Ranking benchmark | ✓ synthetic, reproducible | ✓ | real data | no authorised data yet | |
| Holdout evaluation | ✓ v1 frozen, 68.1% | ✓ | | | v2 after fixes |
| Sign-up FOREIGN KEY failure (SQLite) | ✓ fixed | ✓ regression test | | | |
| Halo Drive screen, push-to-talk, replies | ✓ | ✓ simulator build + UI tour | device testing | | |
| Telugu speech recognition | | spike | | `te-IN` absent on simulator | |
| LLM fallback parser | | | | | ✓ |
| Halo Recall | | | | | ✓ |
| Provider / rights / entitlement layer | | | | | ✓ |
| Apple Music (MusicKit) | | | | deferred by owner | |
| Independent catalog | | | | legal agreements | |
| Siri / App Intents | | | | | ✓ |
| CarPlay | | | | entitlement request (owner) | |
| Android | | | | | ✓ |
| Production hardening | | | CI, typed APIs | | load/security tests |
