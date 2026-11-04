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

## Context 2.0: deciding before acting (built)

`IntentInterpreter.interpret(text)` returns an `IntentDecision` and changes nothing:

* **no action**: noise only, "never mind", a bare "no", negated controls ("don't skip",
  "aapakandi"), or nothing understood.
* **unsupported**: requests outside music (calls, messages, alarms, weather, maps, apps, news,
  lyrics) with no music in the sentence, or only an unsupported language. These never fall back
  to a player action; a bare play verb resumes only when every word is understood.
* **clarify**: a name shared by two artists ("raja"); an incomplete request ("play songs by",
  "set the language to", "don't play"), completed by the next answer; or evidence too weak for
  the change's risk.
* **execute**: otherwise; the delta goes through `SessionState.apply` as before.

Evidence is a deterministic score (unknown-word share, unresolved names, conflicting dimensions,
recognizer confidence). `IntentCalibration` maps it to an estimated chance of being right using a
table fitted on development data (isotonic, Laplace-smoothed); `CalibrationTests` refits it and
fails if the stored table drifts. Required confidence depends on risk: transport/questions 0.5,
session changes 0.6, lasting changes (likes, "never", profile exclusions) 0.85. The table is
optimistic on new phrasing (holdout v2: ECE 0.102) and is never shown as a probability.

Entities: `EntityResolver` knows artists and a short list of film titles (only titles that
aren't everyday words); names known by their first words keep the known part ("thaman lately");
everyday words never become names; genres, albums and song titles are their own entity kinds.
Context: "not too much" refers to the artist named last (`lastMentioned`), "this song" skips and
keeps that song out of the session, "never" makes a lasting exclusion that needs confirmation.

The optional AI fallback (`/api/v1/intent/fallback`, off by default) is consulted only for
commands the phone couldn't act on and only with consent; its output must parse entirely into
Halo's wire vocabulary and goes through the same reducer; lasting changes still ask first.

## Halo Flow 2.0 (built: `session-v3`)

* **Hard constraints first**, on server and phone: rights (`SourcePolicyRightsResolver`: full
  stream, authorised source, Jamendo licence), not already played, excluded tracks and artists
  (credit word match), "today" exclusions until local midnight, avoided moods, "only" languages.
* **Score**: rank, energy, tempo, valence, language, recency, discovery, seed, artist weights
  (unchanged from v2). Artist cap 2 per response.
* **Spacing** (new): never the same artist twice in a row, or straight after the song just
  heard, when a song within 0.5 of the score can go there instead. Halves back-to-back repeats
  in the benchmark at no measurable relevance cost.
* **Listening signals** (`SessionState.record`): early skip (< 30 s or < 25 %) −0.1 and that
  song stays out for the session; late skip −0.03; completion +0.05; replay +0.15. Inferred
  weights are capped at ±0.4, kept apart from explicit ones (explicit always wins), ignored
  while the vibe is locked, and never written to the profile. A short skip is never a dislike.
* **"Not today"** ends at the next local midnight computed with an explicit `TimeZone` and the
  calendar (DST-safe), stored on the device only (`TodayExclusionStore`).
* **Reset**: Drive "Reset" forgets the drive's steering, signals and today's exclusions and keeps
  playing; Taste "Reset taste memory" also clears Drive's on-device memory.
* **Queue**: Halo only replaces its own Flow band; songs the listener queued stay first through
  every change (tested over a five-command drive).

## Halo Recall (not started)

Plan: query understanding → entity and era extraction → metadata search (MusicBrainz, catalog)
→ ranked candidates with calibrated confidence → one clarification question when weak.
Lyric matching only through a licensed lyrics provider; no lyrics are stored or shipped in
tests. Query-by-humming starts as a research prototype (pitch contour + DTW over an
authorised reference set); conventional fingerprinting is not used for humming. "Identified"
and "playable" are reported separately.
