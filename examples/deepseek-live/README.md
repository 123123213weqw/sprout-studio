# Authenticated DeepSeek tests — 2026-10-15

All three requests used the official DeepSeek API from V100. The key stayed on V100. The local browser's existing song was not read or changed. No automatic retries were used.

| Test | Real notes / MIDI | Time | Reported tokens | Observed result |
| --- | --- | --- | --- | --- |
| Descriptive four-bar prompt | 62 / 62 | 4.938 s | 2,415 | Eight sampled roles; piano chords correct, bass roots 2/4, hi-hat quarter notes rather than eighth notes |
| Explicit beat/chord prompt | 83 / 83 | 5.572 s | 2,874 | Eight roles; piano chords correct, bass roots 3/4, all 32 requested hi-hat onsets; not full instruction compliance |
| Local API → SSH → V100, flute-only edit | 79 / 79 total; 11 flute notes | 2.149 s | 2,021 | Seven unselected tracks unchanged; all sampled instrument settings retained |

**Total: 3 real requests, 7,310 reported tokens.** This is token usage, not a currency bill. Each subfolder contains the actual project, MIDI and sanitized receipt/report. The `descriptive` and `explicit` folders retain their separate inputs, so the second request is not presented as a corrected version of the first output.

The `explicit` mix and eight isolated stems were rendered with the app's actual `renderWAV` and sample library using the prebuilt Node Web Audio 2.2.0 offline backend. Every stem is non-silent and has zero clipped PCM16 samples. The mixes are 13.0828 seconds including the release tail. This exercises the audio graph, sample assets and WAV encoding without opening a hardware audio device; it is not browser playback verification or a subjective listening verdict.

The model's summaries are retained as model-authored claims. They are **not** treated as verified explanations: both full-arrangement responses misstated some bass-root compliance. `instruction-checks.json` / `report.json` record independent checks.

Files at this folder's root preserve the initial descriptive CLI download. Named subfolders are the authoritative per-test evidence.

## Disclosed reviewed demo (no extra model call)

`reviewed/` is the 83-note explicit result with **one** bass note edited from MIDI 45 (A2) to MIDI 41 (F2) at beat 4, using the app's existing `transformNotes` operation. Its report identifies that edit and the original request. It is not presented as an untouched or automatically correct model result. The inverse editor operation restores the exact original project. All measured fixture requirements pass after that edit; subjective music quality still requires listening. The raw model output remains unchanged in `explicit/`.
