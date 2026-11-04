# Benchmark results

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
