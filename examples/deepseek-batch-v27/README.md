# Real DeepSeek V4.1 Flash regression batch — 2026-10-15

Six authenticated calls ran on V100 with `deepseek-flash`, at most 8,192 output tokens per call and **no automatic retries**. They used isolated, generated projects rather than a human workspace. The key stayed on V100. No account-balance information or credentials are stored in these artifacts.

## Observed results

| Case | Notes / MIDI notes | Scope/data protection | Measured instructions |
| --- | --- | --- | --- |
| Numeric harmony | 80 / 80 | Pass | All four piano triads and bass roots, all 32 eighth-note hats, all eight roles, notes in key |
| Flute clip | 228 / 228 total | Pass; one clip changed | Exact six requested pitches, starts, durations and velocity range |
| Half-time drums | 170 / 170 total | Pass; melodic tracks unchanged | Exact kick, snare and hi-hat onset lists |
| Chorus with shared Patterns | 451 / 451 total | Pass; outside music, source library and labels unchanged | All four chord/root anchors and hats; target links detached, outside links retained |
| Ambient long notes | 34 / 34 | Pass | Requested held cello/flute notes and key passed, but kick and snare were left silent despite “all eight roles” |
| Conflicting scope request | 113 / 113 total | Pass; globals/other tracks fixed | 12 flute notes within the requested pitch range |

**6/6 valid, scope-safe responses; 5/6 pass all measured case requirements.** This does not imply artistic quality, originality, good balance or subjective listening approval. The ambient failure remains in the evidence; no drum notes were silently filled in.

Reported usage: **23,441 tokens** for this batch. Together with the earlier three real requests, the recorded total is nine requests and 30,751 tokens. These are provider-reported token counts, not a currency invoice. Paid test calls stopped at the declared six-request cap.

## Artifacts and verification

Each folder contains the exact input case, sanitized numeric provider score, accepted project, MIDI, WAV and assessment. Original full-project note counts are shown for local edits; the clip and section WAVs render only their target windows. `audio-checks.json` records the range and exact file hashes.

All six mixes are non-silent, PCM16 stereo 44.1 kHz, with no clipped samples. The eight stems of `numeric-harmony` are also non-silent and unclipped. Its raw, unedited model output is a stronger instruction-following example than the earlier manually reviewed demo.

The ambient cello and flute were rendered separately. Their requested 7.5-beat notes last 6.25 seconds at 72 BPM; measurable audio remains after six seconds, while the note is still held. This exercises the sample sustain loops, not just MIDI duration.

Rendering used the unchanged app `renderWAV` graph and verified samples with a prebuilt Node Web Audio offline backend. No hardware audio device was opened, no Rust compilation occurred, and no browser playback or subjective listening verdict is claimed.

Automated regressions replay these recorded provider scores through the actual adapter without network access. They also exercise the browser's flatten/stage protection path for the shared-Pattern section, recheck actual MIDI files and WAV hashes/signals, and retain the observed ambient omission.

## Re-running intentionally

After source sync, run on V100:

```sh
node scripts/deepseek-batch.mjs --live
```

Without `--live`, no key is read and no model is called. Each CLI run creates a new timestamped output folder under `examples/deepseek-batches/`; it never overwrites this frozen regression evidence. Do not copy the V100 key to the Mac. `npm test` never starts a paid run.
