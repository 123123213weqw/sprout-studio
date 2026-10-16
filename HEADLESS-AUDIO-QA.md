# Headless audio verification — v0.26

## Method

The actual app exports `renderWAV` and `createSampleLibrary` were used, with the unchanged bundled, hash-verified sample assets. The only injected component was `OfflineAudioContext` from the published, prebuilt macOS arm64 binary of [node-web-audio-api 2.2.0](https://github.com/ircam-ismm/node-web-audio-api). It was installed in the separate work directory with `--ignore-scripts`; no Cargo/Rust compilation ran locally or remotely. This is a QA dependency, not an app runtime dependency.

No hardware audio device was opened and no automatic playback occurred. Numeric verification is not a subjective listening verdict or a browser rendering comparison. Backend/DSP implementations may have small numerical differences from a browser.

## Results

| Output | Seconds including tail | Peak PCM16 amplitude | RMS | Clipped samples |
| --- | --- | --- | --- | --- |
| Descriptive 62-note arrangement | 13.0828 | 0.22177 | 0.03856 | 0 |
| Explicit 83-note arrangement | 13.0828 | 0.24911 | 0.03068 | 0 |
| Flute edit, 79 total notes | 13.0828 | 0.24911 | 0.03138 | 0 |

The explicit arrangement's kick, snare, hi-hat, double bass, piano, flute, cello and harp were also rendered separately. Each contains nonzero audio and zero clipped samples. Hashes, exact peaks, RMS, frame counts and sample-library diagnostics are retained in `examples/deepseek-live/explicit/audio-checks.json`; eight WAV stems are beside it.

The project remained byte-identical in memory before/after each render. Actual-file regressions recompute WAV headers, hashes, nonzero samples and clipping rather than trusting the JSON report alone.

The separately labeled reviewed demo also has a WAV render. It changes one bass note through the existing editor; it is not an untouched DeepSeek response. Its numeric results are in `examples/deepseek-live/reviewed/audio-checks.json`.

## v0.27 batch

All six additional accepted outputs were rendered; their mixes and the eight raw numeric-harmony stems are non-silent and unclipped. Clip/section exports use only their selected windows. The ambient cello and flute have positive RMS beyond six seconds of their source recordings, inside the requested held notes (6.25-second bodies). Full measurements and hashes are in `examples/deepseek-batch-v27/*/audio-checks.json`. The ambient kick/snare omission remains unfilled.

## Remaining checks

Browser playback, current UI appearance, focus/modal behavior and subjective balance/usefulness have not been verified in this run. The in-app browser remains blocked on its connection-error document; no alternate browser or policy workaround was used. Those limits do not negate the completed real API, MIDI and offline signal checks.

## v0.28 acoustic recording checks

Eight additional WAV files were rendered through the unchanged shared sample/synth routing and the new recorded sources. All have nonzero PCM and no full-scale samples. The authored trio contains 46 editable notes; the source-only DeepSeek derivative retains all 80 original notes and mix values, while a separate performance derivative changes only saved microtiming/velocity through the existing editor. Both are explicitly distinguished from the raw provider response. Violin/clarinet stay audible in the 7–9 second window beyond their five-second source bounds and finish within the declared export tail.

The guitar test alternates actual recorded takes at identical pitch and velocity, with deterministic sequence reset at transport/export start. Per-context buffers remain valid after raw-cache eviction. Tests prepare every current asset, verifying 201,729,212 bytes of prepared PCM under the separate 256 MB ceiling while the decoded cache stays within 96 MB. This is not a total-process memory measurement.

Evidence: `examples/acoustic-v28/audio-checks.json`; 25 new recording/artifact tests bring the suite to 655 passes. No paid calls, browser-policy workaround, hardware audio context or local Rust compilation was used. This remains signal and behavior verification, not subjective listening or visual QA.

## v0.29 full library coverage

All 179 preset IDs have corresponding actual offline WAV auditions, each with nonzero PCM and zero full-scale samples. The 128 bank programs, 24 original EDM tonal patches, twelve EDM percussion patches and fifteen existing presets are counted separately from the 2,259 source WAV files. The authored eight-track EDM sketch has 120 notes, peak 0.41858 and RMS 0.09292; the acoustic/choir sketch has 70 notes, peak 0.19525 and RMS 0.03633. Neither is labeled raw model output.

The v0.28 acoustic trio and v0.27 raw numeric DeepSeek arrangement were re-rendered with current code and matched their existing WAV bytes exactly. All 264 prior source records and PCM files are preserved. Cache tests exercise every bank program while keeping selected guitar roots pinned; raw and prepared cache ceilings hold without removing active project buffers.

Evidence is in `examples/sound-library-v29/`. All checks use the published prebuilt offline audio package, not a browser-policy workaround or hardware output. C-only source conversion was used, with no Rust compilation, no extra paid model call and no subjective-listening verdict.
