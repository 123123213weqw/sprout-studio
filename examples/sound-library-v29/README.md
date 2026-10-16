# Sound library audio examples

This folder contains an actual offline audition for every one of the 179 playable preset IDs, plus two authored musical sketches. None of these new examples required a paid model call or opened hardware audio. The renderer is the published prebuilt `node-web-audio-api` 2.2.0 package running the app's PCM sampler and `renderWAV`; this is not a browser or subjective-listening verdict.

## Musical sketches

- `edm-sketch.wav`: 9.22 seconds, 120 notes, eight tracks. Reese bass, supersaw lead, warm pad, FM pluck, house kick, layered clap, closed hat and open-decay hat. Peak 0.41858, RMS 0.09292, no full-scale samples. Matching `.sprout` and `.mid` files preserve the editable composition and performed MIDI hints.
- `acoustic-choir-sketch.wav`: 11.733 seconds, 70 notes, eight tracks. Detailed piano/guitar/clarinet recordings combined with soundbank contrabass, marimba, choir, trumpet and strings. Peak 0.19525, RMS 0.03633, no full-scale samples. This is an authored demo, not raw DeepSeek output.

## Individual sounds

`auditions/<preset-id>.wav` contains one short test note for each source. Bass auditions use E2, most melodic leads use A4, other tonal sources use C4, and drums use their editing-role key. The note, velocity, exported region, file checksum and measured PCM values are recorded in `audio-checks.json`. These are diagnostic notes, not finished performances.

All 179 auditions are non-silent and unclipped. Their distinct file hashes establish distinct rendered files, not a scientific claim that every related piano/program variation is a separate physical instrument or perceptually unrelated timbre. The library contains 15 detailed recording presets, 128 mixed acoustic/electronic SoundFont patches and 36 original synthesized EDM patches. Choir/ooh sounds do not constitute a complete singing system.

`legacy-replay.json` records two current-code re-renders that matched the earlier acoustic trio and raw 80-note DeepSeek WAV bytes exactly. Original model evidence and the 264 prior source recordings were not overwritten. No current browser workspace was read or edited to make this folder.
