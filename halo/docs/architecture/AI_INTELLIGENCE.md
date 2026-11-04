# Halo intelligence: Context, Flow, Recall

## Halo Context (built: phase 1 + this slice)

Pipeline: transcript → `IntentParser.parse` → `EntityResolver.resolve` → `IntentDelta` →
`SessionState.apply` → effects (`startPlaying`, `rerank`, `transport`, `skipCurrent`,
`feedback`, `answer`).

* **Deterministic first.** The parser is a lexicon plus ordered rules (English, Telugu script,
  romanized Telugu, mixed). It runs in well under a millisecond (see
  `testing/BENCHMARK_RESULTS.md`). Unknown words lower confidence; low confidence on a
  profile-scoped change triggers a yes/no confirmation.
* **Follow-ups are deltas.** "Newer", "same vibe but English", "not too much Anirudh" change
  only what they mention; everything else in the session stays. `undo` restores the previous
  state (up to 10 steps).
* **Explicit beats inferred.** Vibe targets record their source; skips are inferred, weak
  (−0.1 to that artist for skips in the first 30 s), ignored while the vibe is locked, and never
  saved to the profile. Halo's own skips (after "I don't like this") are not counted.
* **Scopes.** `session` (default), `today` (currently ends with the drive), `profile`
  (likes, "never again": sent as feedback only when personalization is on).
* **Entities.** `EntityResolver` maps nicknames, romanizations and Telugu script to canonical
  names (DSP → Devi Sri Prasad, ilayaraja → Ilaiyaraaja, దేవిశ్రీ → Devi Sri Prasad) using a
  spelling-tolerant key. A name shared by two artists ("raja") is ambiguous: Halo asks
  "Ilaiyaraaja or Yuvan Shankar Raja?" and acts only on the answer. Unknown names pass through
  as said and are searched; nothing is guessed. Film titles are never resolved to artists.
* **Artist matching** uses whole words of the credit, the same rule on server and phone.
* **Moods.** "No sad songs" is a hard exclusion of songs whose valence is known to be ≤ 0.3;
  songs with unknown valence stay. Valence comes from the source's mood or tag words only.
* **No emotion inference.** Halo never infers how the listener feels from voice or behaviour;
  moods are only what the listener asks for.

Limitations: the alias table is small and hand-checked; names said in a pattern the parser
doesn't know ("Thaman mass beats") lose the name; Telugu speech recognition is not available
on the tested simulator, so Telugu-script handling is exercised by text only.

## Halo Flow 2.0 (partly built)

Built: session-aware candidates, hard constraints, valence/energy/tempo/language/recency/
discovery/seed/artist features, artist cap 2, language interleaving, Flow-band-only
replacement, on-device re-ranking when offline. Next: replay and session-duration signals,
personalization reset in the Drive UI, a measured offline replay of the weights.

## Halo Recall (not started)

Plan: query understanding → entity and era extraction → metadata search (MusicBrainz, catalog)
→ ranked candidates with calibrated confidence → one clarification question when weak.
Lyric matching only through a licensed lyrics provider; no lyrics are stored or shipped in
tests. Query-by-humming starts as a research prototype (pitch contour + DTW over an
authorised reference set); conventional fingerprinting is not used for humming. "Identified"
and "playable" are reported separately.
