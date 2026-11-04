# Benchmark results

## 2026-11-04 (third milestone): Context 2.0

### Holdout v2 (final, evaluated once; now retired)

`docs/testing/holdout-v2.json` (sha256 `d15df26f…151185`): 294 single commands and 32 multi-turn
sequences, written and labeled by a separate agent from the label specification only (no access
to the code), frozen before any evaluation, run once (`HoldoutV2EvaluationTests`). Holdout v1 was
retired to development data before this milestone, because its misses had been read.
After this single run the v2 misses were read to describe failure modes, so v2 is retired too.

| Measure | Result |
|---|---|
| Exact intent (outcome + operations) | **74.8%** |
| Outcome only (execute / clarify / unsupported / no action) | 87.4% |
| Entity extraction (81 cases with entities) | 84.0% |
| Negation (32 negative instructions) | 78.1% |
| Unsupported / no-action requests that Halo acted on | **2.3%** (1 of 43) |
| Clarification precision / recall | 45.5% / 50.0% (10 right, 12 unneeded, 10 missed) |
| Conversation state (32 sequences) | **56.2%** |
| Parse + resolve + decide latency (Linux container, debug) | 2.6 ms per command |

By form (exact): English 80.5% (113), mixed 78.6% (56), Telugu script 75.4% (61),
romanized Telugu 60.9% (64). Sequences: English 90.0%, mixed 57.1%, Telugu 42.9%, romanized 25.0%.

By category (exact): language 100%, no action 100%, rating 92.9%, unsupported 88.5%,
transport 82.6%, noisy 81.8%, discovery 81.2%, question 80.0%, negative 78.1%, vibe 75.0%,
era 75.0%, entity (film/album/song/genre) 64.7%, artist 61.9%, current song 54.5%,
ambiguous artist 50.0%, incomplete 50.0%, relative date 45.5%, tempo 36.4%.

Outcome confusion (label → Halo): execute→execute 207, execute→clarify 12, execute→no action 12,
clarify→clarify 10, clarify→no action 9, clarify→execute 1, unsupported→unsupported 23,
unsupported→no action 2, unsupported→execute 1, no action→no action 17.

Calibration on executed commands (table fitted on development data): stated 0.82 → observed
0.667 (48), 0.86 → 0.769 (39), 0.97 → 0.885 (122); ECE 0.102. The table is **overconfident**
on unseen phrasing, as expected from a development-data fit; it is not a calibrated
probability for new speech and is not shown to listeners as one.

Not comparable with v1 (different labels, outcomes and vocabulary). For reference only, the
retired v1 now reads 87.2% — it is development data.

Failure modes found (to fix next, with new development tests, then a fresh holdout v3):
* **Wrong-direction negation**: "Don't ever play this singer again" → *more* of the artist;
  "Never ever play this track" → resume. Negation scope misses "don't ever"/"never ever".
* **Prefix matching**: "news" matches "new" (the one false action: "Read me the news").
* **Questions read as controls**: "What's playing next?" → next song.
* **Evidence counts resolved names as unknown words**, so clean requests ("Play Sid Sriram")
  ask for confirmation — most of the 12 unneeded clarifications.
* **Telugu forms still missing**: హుషారైన (stem written as హుషారు), వచ్చిన/విడుదలైన and "vachina"
  become names; "purana", "vaddandi", "pettaku" variants, "bhasha maarchu".
* **Ambiguous "Raja" in other phrasings** ("something by Raja", "Raja music") is not caught.
* **Follow-up references** without a name ("not too many though", "kaani ekkuva vaddu").
* **Label conventions** that differ from the implementation and count as misses: film names
  in lowercase in labels vs canonical capitalization (5 cases differ only by case); tempo
  requests that the labeler did not also label as energy.

---

## 2026-11-04 (second milestone): independent holdout and ranking benchmark

### Holdout v1: Halo Context on unseen commands

`docs/testing/holdout-v1.json` (sha256 `d9f77ea0…f0f4d`): 188 single commands and 22 multi-turn
sequences, written and labeled by a separate agent from the label specification only, without
access to the parser, lexicon or development corpus, and with no lyrics. Frozen before the
first run; evaluated once (`HoldoutEvaluationTests`); the parser was **not** changed after
seeing the results. One spelling mapping only: the labeler wrote `recency:newer`/`recency:older`
for the schema's `newer`/`older`.

| Set | Overall | English | Mixed | Romanized Telugu | Telugu script |
|---|---|---|---|---|---|
| Single commands (188) | **68.1%** | 74.5% (51) | 72.3% (47) | 63.0% (46) | 61.4% (44) |
| Follow-up sequences (22) | **63.6%** | 88.9% (9) | 60.0% (5) | 40.0% (5) | 33.3% (3) |

By category (single commands): rating 92.9%, transport 82.4%, artist 78.9%, language 78.6%,
noisy 76.9%, unsupported 76.9%, era 71.4%, ambiguous artist 66.7%, vibe 65.2%, discovery 52.9%,
negative 42.9%, question 42.9%.

Errors (60 misses): wrong value or target 37, understood nothing 13, added an operation 5,
acted when it should not 3, missed an operation 2.

What the misses show (described, not fixed against):
* **Leftover words become names.** Unknown words next to a play verb are taken as an artist or
  film ("for the drive" → artist "drive"; "too much Thaman lately" → "thaman lately").
* **Telugu-script vocabulary is thin.** Adjective forms (ప్రశాంతమైన, సంతోషకరమైన), number words
  (తొంభైల), "singer" (గాయకుడు), "released" (విడుదల) are missing.
* **A bare verb falls back to "resume".** Unrelated requests ("call Amma", "set an alarm")
  resume playback instead of doing nothing.
* **Question phrasings** beyond the lexicon's ("when did this come out", "what's coming up").
* **Convention differences** with the labeler, e.g. whether "Telugu songs matrame" starts
  music; these are counted as misses.

The development corpus (133 cases) reads 100% after the "Thaman mass beats" fix; the gap to
68.1% is the honest measure of overfitting. Next step: development tests for the failure modes
above written from their principles, then a fresh holdout v2.

### Ranking: session-v2 versus Flow 2.0 (session-v3), SYNTHETIC

`python -m app.tools.ranking_benchmark` (seed 20261104; output is identical between runs).
**Synthetic** catalog (420 songs, 50 artists with a long-tail song count) and eight scripted
listeners with hidden likes and dislikes; 30 turns, top 10 measured, five songs heard per turn.
No real listening data was available. It shows how the rankers behave, not what real
listeners prefer.

| Metric (mean per turn) | v2 | **v3 (shipped)** | v3 without spacing | v3 + variety weight |
|---|---|---|---|---|
| Relevance@10 (hidden truth) | 0.759 | 0.755 | 0.755 | 0.741 |
| Unique artists in top 10 | 0.605 | 0.606 | 0.606 | 0.580 |
| Adjacent same-artist pairs | 0.377 | **0.180** | 0.398 | 0.173 |
| Recently heard artist share | 0.477 | 0.490 | 0.490 | 0.464 |
| Disliked-artist share | 0.133 | 0.133 | 0.133 | 0.136 |
| Hard-constraint violations | 0 | 0 | 0 | 0 |
| Skip rate (simulated) | 0.167 | 0.167 | 0.167 | 0.205 |

Reading: artist spacing halves back-to-back repeats at no measurable relevance cost. A
"variety" weight against recently heard artists lowered relevance and raised skips, so it was
left out of v3 (it stays an ablation). The new listening signals (completion, replay, capped
skips) did not change relevance or skip rate in this simulation; their benefit — short skips
no longer accumulate into an artist ban, explicit requests always win — is behavioural and is
covered by unit tests, not claimed as a quality gain.

### Context and ranking latency (Linux container, debug build)

Parse + resolve 0.38–0.41 ms per command; session update + on-device re-rank of 200 candidates
1.2–1.5 ms.

---

## 2026-11-04 (first milestone)

Measured 2026-11-04 in a Linux container (Docker `swift:6.1-noble`, debug build), not on a
phone. Device numbers are still to be measured.

## Intent understanding (text → operations, after entity resolution)

Corpus: 133 curated utterances (`IntentCorpusTests.swift`). A case is correct only when the
full set of operations matches.

| Run | Overall | English (82) | Romanized Telugu (27) | Telugu script (13) | Mixed (11) |
|---|---|---|---|---|---|
| Before this slice (parser of 93e3799 + resolver) | 90.2% | 90.2% | 85.2% | 92.3% | 100% |
| After this slice | 99.2% | 100% | 96.3% | 100% | 100% |

Caveat: the same corpus was used to find and fix the parser's mistakes, so the 99.2% is a
development-set number and overstates real-world accuracy. The 90.2% is the untuned baseline.
A held-out set of real transcripts is needed before claiming an accuracy target.

Remaining miss: "Thaman mass beats" (the name isn't captured without "songs"/a play verb).
One expectation was aligned with the existing convention rather than the first draft:
"Konchem energetic songs pettu" is a small step up (+0.12), and Halo Drive now starts music
when such a nudge arrives with nothing playing.

## Latency

| Metric | Target | Measured |
|---|---|---|
| Parse + resolve one utterance | < 500 ms per command | 0.38–0.41 ms |
| Session update + on-device re-rank of 200 candidates | < 100 ms / < 150 ms | 1.2–1.5 ms |

Speech capture, network and audio start are not included and not yet measured.
