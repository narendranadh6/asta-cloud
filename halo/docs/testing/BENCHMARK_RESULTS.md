# Benchmark results

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
