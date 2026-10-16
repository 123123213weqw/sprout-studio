# Sound library conversion recipes

These offline tools rebuild the additional FluidR3 responses and original EDM PCM. They are not application runtime dependencies. The browser uses fixed PCM files; it never runs C or Python. No binary, downloaded SoundFont, API key or environment file is included here.

## Inputs and licenses

- FluidR3 GM release 3.1, 148,398,306 bytes, SHA-256 `74594e8f4250680adf590507a306655a299935343583256f3b722c48a1bc1cb0`, from the [upstream release](https://github.com/pianobooster/fluid-soundfont/releases/tag/v3.1). Frank Wen's MIT notice and original credits are in `dist/samples/licenses/FluidR3-MIT.txt` and `FluidR3-README.txt`.
- TinySoundFont header from commit `853a0a171759f1ddba0de1442133a75912bbeffa`, SHA-256 `70d55963c98f60ebb81518eaa1f25d46888d5180eb5f5289fd6b74ffc177d197`, [upstream source](https://github.com/schellingb/TinySoundFont). Its MIT notice is retained in the header and `dist/samples/licenses/TinySoundFont-MIT.txt`.
- Original generated EDM PCM is dedicated under CC0. The exact Python recipe SHA-256 is recorded in each generated asset. The converter/recipe source is provided for inspection and reproducibility, not as a claim of full SF2 engine support.

## Rebuild on macOS

Use Python with NumPy. Download the verified source SoundFont to this directory as `FluidR3_GM.sf2`; the script refuses other source bytes. Compile only the small C wrapper, then run the Python recipes from this directory:

```sh
cc -O2 -dynamiclib render-bank.c -o render-bank.dylib -lm
python3 build-bank.py
python3 build-edm.py
```

This is C compilation, not Rust compilation. There is no Cargo step. Generated files and reports appear in `processed/`, `processed-edm/` and the JSON reports beside the scripts. These tools do not install or activate new voices automatically. Replace runtime assets and registries only after checksum, licensing, range, cache-budget and export tests pass; preserve the frozen legacy files.

The bank conversion compensates TinySoundFont's linear velocity gain before the app reapplies velocity, preserves bank-program timbre/envelopes in the recordings, merges near-identical velocity responses, omits unsupported silent roots and creates bounded sustain loops where appropriate. The original tonal EDM recipes synthesize at 4× sample rate before low-pass filtering and downsampling; no acoustic-recording claim is attached to them. Exact duplicate rendered velocity responses are merged.
