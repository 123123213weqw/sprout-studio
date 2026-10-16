# Local sound library v0.29

The local app includes **179 playable presets and 2,259 PCM WAV files totaling 767.07 MB**: 15 detailed recording presets, 128 FluidR3 soundbank programs and 36 original synthesized EDM patches. The last two groups are not claimed to be newly recorded acoustic instruments. No account, online sound service or plugin installation is needed. Playback starts only after an explicit user action. The original synths and 84 previously bundled recordings are unchanged.

## Choose a sound

- **Add instrument** lists recorded instruments separately from synths. Adding an instrument creates an empty track; it does not compose or play.
- On an existing track, open **Source** to change its recording. Guitar is compatible with the pluck role; solo violin and clarinet are compatible with the melody/lead role.
- The bulk **Use recordings on synth tracks** action fills unsampled tracks only. Starting with v0.28, it preserves every existing sampled voice and its custom settings, including older piano presets. It no longer overwrites a chosen guitar/violin/clarinet with the standard palette.
- Source changes load and verify the recordings, save a backup and apply as one undoable edit. Notes, mix, clip layouts, shared Patterns and saved inactive synth settings stay intact. Loading failures never silently substitute a synth.
- Source previews are explicit. New guitar previews hold for 0.9 seconds; new violin/clarinet previews hold for 1.25 seconds so their attacks are not reduced to a 280 ms blip. Quiet mode and stale-window guards still prevent playback.

## Detailed acoustic recordings

| Recording | Coverage | Why it is different |
| --- | --- | --- |
| Microphone-recorded archtop guitar | 16 roots, E2–C6; 4 playing intensities × 2 recorded takes = 128 files | Real plucks and body resonance, not a harp or oscillator renamed guitar. Repeated pitches alternate actual recordings. The electric-pickup recordings are not used. |
| Solo violin with vibrato | 11 roots, G3–C6; 2 recorded dynamics = 22 files | Preserves bow attack, recorded vibrato and source fine-tuning corrections. Crossfaded body loops support held notes. |
| Sustained clarinet | 10 roots, D3–D6; 3 recorded dynamics = 30 files | Preserves the breath/reed attack and blends adjacent recorded dynamics. Crossfaded body loops support held notes. |

The guitar uses the microphone signal from [Karoryfer Shinyguitar](https://github.com/sfzinstruments/karoryfer.shinyguitar), played and mapped by D. Smolken / Karoryfer Lecolds, pinned to commit `57243cca85277dbcc120ce17c6178032f93c80f3`. Its upstream CC0 license, readme and acoustic mapping are bundled.

Violin and clarinet come from [VSCO 2 Community Edition](https://github.com/sgossner/VSCO-2-CE), CC0. Recordings are pinned to `440300901dfe9275fd84e0b7763af1f8443ae62e`; numeric root mappings are pinned to `6dd651d55dde97fd4028699be9d4481f26917891`. Credits: Versilian Studios / Sam Gossner, Ivy Audio / Simon Dalzell; original sample cutting by Elan Hickler / Soundemote. Complete licenses and the used mappings are included under `dist/samples/licenses/`.

## Existing choices remain available

- Upright piano: classic eight-root/two-layer preset and fourteen-root/two-layer preset.
- Contrabass pizzicato: twelve roots; not electric bass.
- Flute: ten roots, one recorded dynamic, with sustain loops.
- Cello section: thirteen roots, one recorded dynamic, with sustain loops; not a full orchestra.
- Harp: twelve roots, natural plucked decay; not guitar.
- Orchestral bass drum, snare and gated short cymbal.
- Acoustic kit kick, snare and genuine closed hi-hat, from the [Sonic Pi CC0 collection](https://github.com/samblenny/web-midi-drumkit/blob/main/LICENSES/LICENSE_SAMPLES.md), credited to menegass / Freesound, Sonic Pi and samblenny. The short orchestral cymbal remains accurately labeled rather than presented as a hi-hat.

## Playback and storage decisions

New guitar recordings retain up to 3.8 seconds of natural decay and never loop. New violin/clarinet recordings retain up to five seconds with a 160 ms crossfaded sustain-body loop. Source mapping layer gains are applied before per-root common normalization and PCM16 conversion; different takes are not individually flattened to identical volume. Fine tuning follows the retained mappings. New velocity layers blend between neighboring recorded dynamic centers; old two-layer behavior is unchanged.

Alternate takes are selected deterministically per context, preset and played pitch. Explicit transport starts and offline renders reset the sequence; repeated notes during playback cycle it. No random tuning or hidden timing edits are added to songs. A failed or expired event does not advance the sequence. Previews cycle takes without changing project data.

Files are loaded lazily in batches of four from fixed, checksum-versioned bundled paths. The decoded PCM cache stays within **96 MB**, evicting least-recently-used cache entries as needed. The prepared-buffer cache has a separate **256 MB per-context ceiling** and evicts idle buffers when browsing more sources. Active project roots are pinned until playback stops. Native preparation uses only roots referenced by project notes; a guitar preview prepares eight files at its root, not the entire 128-file preset. Source application still verifies the full selected preset before saving a backup. A combination too large for the cache fails explicitly rather than dropping a voice. These are cache budgets, not total-process memory guarantees: active source references, multiple contexts, audio graphs and project data use additional memory.

Projects save a fixed preset ID and bounded gain/release/filter settings, not arbitrary sample URLs or embedded audio. WAV export uses the same sampler as playback. MIDI carries actual performed notes and General MIDI hints, not the recordings; another player may sound different. Legacy projects remain compatible.

## What this does not solve

More recordings are not a complete virtual-instrument engine. There are no true legato transition samples, bow-direction logic, guitar fret/string fingering, pedal resonance, modeled breath or full SFZ/VST support. A rigid score can still sound rigid. Existing performance editing provides explicit, saved timing and velocity variation; phrases, rests and note lengths still matter. Nothing automatically rewrites the user's arrangement.

[The acoustic examples](examples/acoustic-v28/README.md) separate a source-only comparison, an editable natural-performance derivative and an authored trio. Objective PCM tests establish non-silent output and zero clipping, not a subjective claim that realism is solved. Current browser visual/listening QA is not claimed.

## Broad soundbank and EDM coverage

The [FluidR3 GM source](https://github.com/pianobooster/fluid-soundfont/releases/tag/v3.1), by Frank Wen and credited contributors, supplies 128 bank-zero program responses under MIT. The original notices are bundled. It contains acoustic and electronic patches: a SoundFont label is not a fresh-recording guarantee. Choir, ooh and synth-voice programs are available; there is no text-to-singing system or complete vocalist library.

FluidR3 was rendered offline using pinned, MIT-licensed TinySoundFont C code. The app does not run an SF2 engine. Selected roots and velocity responses are baked to PCM; unsupported silent roots are omitted and near-identical velocity responses are merged. Converter linear velocity gain is removed before the app reapplies velocity, avoiding accidental double attenuation. The fine-grained SF2 controller/modulator behavior is not reconstructed. Rebuild sources and notices are under `tools/sound-library/`.

The 36 original EDM patches contain six basses, six leads, six pads, six plucks and twelve kick/snare/hat/percussion sounds. Tonal synthesis uses 4× oversampling followed by low-pass filtering and downsampling. These are original synthesized PCM patches, not hardware sample captures. They include supersaw, detuned Reese, acid-style pulse, FM/glass, sub-tail, clap, rim and open-decay sounds. Identical velocity responses are merged, not marketed as extra recorded layers. Their generated PCM is dedicated under CC0.

Search and category filtering work without fetching audio, writing a project or playing a preview. The menu distinguishes recordings, soundbank and synthesized sources. Native Source selects use compatible category groups. The actual [179 auditions and two musical sketches](examples/sound-library-v29/README.md) establish non-silent and unclipped output, not a claim of subjective realism.

General MIDI program hints now reconstruct the corresponding coarse musical roles for all 128 bank programs. New clap/rim/open-hat/shaker-like sources include appropriate percussion hints; MIDI import maps those sounds into the existing snare/hat editing roles without dropping notes. MIDI still does not embed source recordings or recreate this app's effects.
