# Benchmark results

## 2026-11-06 (sixth milestone): weights tuned

### Command understanding: act-or-ask weights (cross-validated, development data)

`EvidenceTuningTests` (run with `HALO_TUNE=1`): 2,400 candidate weight/threshold settings,
5-fold cross-validation on 1,329 development commands (the corpus and the retired holdouts
v1–v4), the calibration table refit on each training split, exact accuracy scored on the held-out
fold. Chosen: unknown-word penalty 0.60 → 0.45, session-change threshold 0.60 → 0.50; lasting
changes keep 0.85. CV exact accuracy 88.5% → 89.2%, no fold worse. A re-run after the parsing
fixes kept these weights (best alternative +0.3 points in one fold only). The recognizer penalty
can't be tuned on text and was raised to 0.8 so barely-heard speech always asks. These weights
only decide act-or-ask; most errors are parsing, fixed separately.

### Holdout v5 (final, evaluated once on 363e40c; now retired)

`docs/testing/holdout-v5.json` (sha256 `7e9759ec…f75278849`): 375 commands and 44 sequences,
labeled from the specification only by a separate agent; same specification as v4.

| Measure | v5 | v4 | v3 |
|---|---|---|---|
| Exact intent | **88.5%** | 86.7% | 79.9% |
| Outcome only | **96.5%** | 93.9% | 90.9% |
| Entities | 87.5% (n=104) | 89.9% | 86.0% |
| Negation | 78.4% (n=37) | 85.3% | 86.5% |
| Unsupported / no-action acted on | **0 of 61** | 2 of 46 | 0 of 46 |
| Wrong-direction actions | 1 of 375 | 0 of 345 | 3 of 383 |
| Clarification precision / recall | **100%** / 78.1% | 73.3% / 75.9% | 48.4% / 62.5% |
| Conversation state | 84.1% (n=44) | 90.9% | 78.4% |
| Calibration ECE | 0.043 | 0.045 | 0.066 |

By form: English 95.5%, Telugu script 89.0%, romanized 82.3%, mixed 82.2%.

Lower than v4 on negation and conversations, from: "enough with the sad songs" (the one
wrong-direction action), two-word names cut by a following particle ("Gopi Sundar vi …"),
romanized "gayakudu/gayakudi" (singer), "edupu" (sad), undo "cancel cheyyi"/"venakki teesuko",
and ఇంకా not read as "more". All fixed after the evaluation with new development tests; v5
figures are from before.

### Ranking weights: session-v4 (SYNTHETIC)

`python -m app.tools.ranking_benchmark --tune`: 81 weight sets searched on seeds 11–13, the best
confirmed on unseen seeds 21–23 (synthetic catalog and listeners; no real listening data).

| On unseen seeds 21–23 | v3 | v4 (tuned) |
|---|---|---|
| Relevance@10 | 0.704 | **0.750** |
| Skip rate | 0.233 | **0.199** |
| Adjacent same-artist | 0.378 | 0.388 |
| Disliked-artist share | 0.110 | 0.115 |

On the original benchmark seed (not used in the search): relevance 0.755 → 0.799, skips
0.167 → 0.121, adjacent repeats 0.180 → 0.196, constraint violations 0. Changes: energy
1.0 → 1.4, recency 0.8 → 1.2, language 1.2 → 0.8, search rank 0.6 → 0.3 ("only" languages stay
hard constraints). The phone's on-device ranker uses the same weights.

---

## 2026-11-06 (fifth milestone): weak areas

### Holdout v4 (final, evaluated once on c278a65; now retired)

`docs/testing/holdout-v4.json` (sha256 `ea965a2d…cf021d4027`): 345 single commands and 44
sequences, labeled by a separate agent from the specification only (written through a generator
script it authored; labels by the same spec). The spec adds the playback convention decided this
milestone: accepting a mood or setting a rule without a play verb changes the session but doesn't
start music; bare requests still play.

| Measure | v4 | v3 | v2 |
|---|---|---|---|
| Exact intent | **86.7%** | 79.9% | 74.8% |
| Outcome only | 93.9% | 90.9% | 87.4% |
| Entities | 89.9% (n=99) | 86.0% | 84.0% |
| Negation | 85.3% (n=34) | 86.5% | 78.1% |
| Unsupported / no-action acted on | 4.3% (2 of 46) | 0.0% | 2.3% |
| Wrong-direction actions | **0 of 345** | 3 of 383 | — |
| Clarification precision / recall | **73.3% / 75.9%** | 48.4% / 62.5% | 45.5% / 50.0% |
| Conversation state | **90.9%** (n=44) | 78.4% | 56.2% |
| Calibration ECE | 0.045 | 0.066 | 0.102 |

Different, independently written sets: indicative, not a controlled before/after.

By form: English 89.9%, Telugu script 87.1%, romanized 84.1%, mixed 83.8%. Sequences: Telugu
100%, English 90.9%, mixed 90.9%, romanized 81.8%.

By category: ambiguous artist, follow-up reference, no action, noisy, unsupported 100%; era 93.3%,
discovery 92.3%, question 92.3%, vibe 89.5%, double negative 88.2% (was 21.4%), entity 88.2%,
artist 86.4%, rating 85.7%, negative 85.3%, tempo 83.3%, undo 83.3%, transport 78.9%, language
76.5%, current song 75.0%, incomplete 58.8%, relative date 58.3%.

The 2 false actions were negated controls ("తర్వాత పాటకి వెళ్ళకు" skipped; "Don't skip this one ra"
excluded the song). Fixed after the evaluation, by rule: Telugu negative imperatives are
recognized by form (కు/కండి after a bare consonant; not నాకు, ఎందుకు), and a negated control does
nothing whatever else the sentence says. v4 figures are from before this fix.

Remaining (next round, new development tests, holdout v5):
* **Language preference words**: "lean towards", "priority ivvu" (favor); a refused language in a
  two-language sentence ("English lo kaadu, play Telugu", "Telugu chalu") still mixes.
* **Relative dates without a play verb or with extra words**: "this month's releases please",
  "best songs of this year" ("best", "hit" become names), "came out this week" read as a question.
* **Transport phrasings**: "start this song over", "modati nunchi", "upcoming song remove",
  "ముందు పాట" (previous) fall back to resume or nothing.
* **Song-level never in Telugu** ("మళ్ళీ ఎప్పుడూ పెట్టకు", "malli eppudu") and two actions in one
  sentence ("this song vaddu, next one pettu").
* **Incomplete with Telugu fillers** ("ee... ante...", "adi... umm") and "peru gurthu ledu".

---

## 2026-11-04 (fourth milestone): negation fixes and Context follow-ups

### Holdout v3 (final, evaluated once; now retired)

`docs/testing/holdout-v3.json` (sha256 `4f22e18d…7c3b9a`): 383 single commands and 37 sequences,
written and labeled by a separate agent from the specification only, frozen before evaluation,
scored by the same evaluator as v2 (`HoldoutV2EvaluationTests.runSingles`). Measured on commit
2cd3025, after the negation fixes and before anything below that was changed after reading it.
Two conventions that were ambiguous in v2 were fixed in the v3 specification as product
decisions: known films use their canonical spelling, and any tempo request also sets energy.

| Measure | v3 | v2 (previous milestone) |
|---|---|---|
| Exact intent | **79.9%** | 74.8% |
| Outcome only | 90.9% | 87.4% |
| Entities | 86.0% (n=100) | 84.0% |
| Negation | 86.5% (n=37) | 78.1% |
| Unsupported / no-action requests acted on | **0.0%** (0 of 46) | 2.3% |
| Clarification precision / recall | 48.4% / 62.5% | 45.5% / 50.0% |
| Conversation state | **78.4%** (n=37) | 56.2% |
| Calibration ECE | 0.066 | 0.102 |
| Latency (Linux container, debug) | 3.2 ms | 2.6 ms |

The two sets are different and independently written, so the comparison is indicative, not a
controlled before/after.

By form: English 89.3%, mixed 85.6%, Telugu script 72.3%, romanized 71.9%. Sequences: mixed
100%, English 80.0%, romanized 66.7%, Telugu 66.7%.

By category: ambiguous artist 100%, question 100%, no action 100%, unsupported 96.3%, current song
90.0%, relative date 87.5%, rating 86.7%, negative 86.5%, entity (film/album/song/genre) 86.4%,
artist 85.7%, language 85.7%, noisy 80.0%, transport 77.3%, vibe 77.4%, era 75.0%, discovery
71.4%, tempo 66.7%, follow-up reference 58.8%, incomplete 25.0%, double negative 21.4%.

Calibration (stated → observed on executed commands): 0.71 → 0.600 (45), 0.91 → 0.881 (42),
0.96 → 0.897 (203). Still somewhat overconfident.

**Wrong-direction actions remaining at evaluation time: 3 of 383** — "skip this artist for
today" (more of the artist) and "sad songs inka chalu" / "విషాద పాటలు ఇక చాలు" ("enough sad songs":
played sad songs). Fixed after the evaluation with new development tests ("skip" aimed at an
artist refuses it; "chalu/చాలు" negates); the v3 figures above are from before that fix.

Other failure modes (not fixed; for the next milestone with new development tests and holdout v4):
* **Double negatives and acceptances**: the label convention adds no "play" for "I don't mind sad
  songs" while Halo adds one whenever "songs" is said (convention to decide); "not bad, keep it",
  "baagane undi, unchu" are not recognized as "keep"; a leading "kaadu, …" / "కాదు, …" ("no, …")
  is taken into the name.
* **Incomplete requests with fillers** ("play songs by... umm", "can you put on uh") resume or do
  nothing instead of asking; bare "pettaku", "bhasha maarchu" don't ask.
* **Follow-up words** "vaalla / వాళ్ళ" ("their") and undo phrasings ("go back to how it was",
  "mundu unnatte cheyyi") are not understood ("go back" is read as previous track).
* **Telugu**: tempo adjectives (వేగమైన, నెమ్మదైన), "beat ekkuva unna", multi-word Telugu-script
  names in exclusions (దేవి శ్రీ ప్రసాద్ వద్దు), "inkeppudu" scope with -aku forms.

---

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
