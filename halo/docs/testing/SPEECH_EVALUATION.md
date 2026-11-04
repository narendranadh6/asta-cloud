# Speech evaluation on a real iPhone (procedure)

Text-only tests say nothing about speech recognition. This procedure measures it on real
devices. **No results exist yet**: none have been recorded.

## Before recording

1. Each tester agrees in writing that their spoken commands will be recognized on the device
   (and, only if they also allow it, by Apple's server), that **no audio is kept**, and that
   only the recognized text, the prompt id and timings are exported.
2. Note the iPhone model, iOS version, and the capability report from
   Settings › Voice & privacy › This iPhone ("Share this report").

## Recording

1. Settings › Voice & privacy › Speech test. Read each prompt once at normal speed; the app
   records only the recognizer's text. Prompts cover English, romanized Telugu, Telugu script
   and mixed speech (commands only, no lyrics). A tester may use their own prompt sheet.
2. Repeat in a quiet room and in a moving car (passenger), with and without music playing.
3. Share results (JSON, text only) and clear them on the phone.

## Scoring

Per prompt the app computes word error rate and whether the transcript is understood exactly
like the typed prompt (`SpeechEvaluation.score`). Report per locale, route (on-device / Apple
server) and form: mean WER, intent-match rate, latency. Include the device report. Never pool
results from different routes.

## What must not be claimed

* Simulator capabilities as iPhone capabilities.
* Speech accuracy from text-only holdouts.
* Telugu speech recognition unless `te-IN` shows a recognizer on the tested device.
