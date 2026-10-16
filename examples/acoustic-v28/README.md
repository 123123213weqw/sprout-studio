# Acoustic recordings — v0.28 examples

These are local, offline exports through the application's actual sampler and `renderWAV`. No hardware audio context was opened and no new model calls were made. The QA renderer is the published, prebuilt `node-web-audio-api` 2.2.0 package, kept outside the app; no Rust compilation was performed. Browser playback and subjective listening are not claimed as tested.

## Start with the trio

`acoustic-trio.wav` is a 13.207-second authored demonstration of microphone-recorded archtop guitar, solo violin and clarinet. Its 46 notes include saved strum offsets, varied playing intensity, phrase lengths and rests. It is **not an unmodified DeepSeek response**. The matching `.sprout` file is editable; the `.mid` file carries the performed notes but not the recordings. Each voice also has a separate `solo-*.wav` export.

## Compare sound and performance separately

1. Original: `../deepseek-batch-v27/numeric-harmony/composition.wav`. This remains the raw 80-note model arrangement.
2. `deepseek-same-notes-new-voices.wav`: exactly the same 80 note IDs, pitches, grid starts, durations, velocities, mix and global settings. Only flute → clarinet and harp → microphone guitar source settings changed.
3. `deepseek-natural-performance.wav`: a separate copy using the existing explicit performance editor. Grid starts, pitches, note lengths and note count remain fixed; saved microtiming and velocities change. `performance-edits.json` records the changes. It is not a raw model result.

The comparisons are not loudness-normalized: identical mix settings expose the genuine level differences between sources. Louder does not necessarily mean more realistic.

## Focused checks

- `guitar-alternate-takes.wav`: sixteen identical C4 notes, same velocity and length, to isolate actual take alternation. Repetition here is intentional, not a musical demo.
- `held-strings-wind.wav`: held violin and clarinet. The 7–9 second window is non-silent beyond their five-second recordings, with finite release and tail afterward.
- `audio-checks.json`: exact SHA-256, PCM frame count, peak, RMS, clipping and source list for all eight exports. All are non-silent and have zero full-scale samples. Measurements do not prove subjective realism.

Original raw DeepSeek project bytes and all 84 legacy sample records/files are preserved. No current browser workspace was read or modified to make these examples.
