# DeepSeek composition (local v0.27)

## Current model selection — confirmed 2026-10-15

**DeepSeek V4.1 Flash uses API ID `deepseek-flash`.** This was confirmed both by an authenticated `/models` metadata request from V100 and the [official model table](https://api-docs.deepseek.com/quick_start/pricing/). The three earlier real composition calls already used this ID; there was no V4 Pro generation in those tests.

The V100 launcher now pins the model and exposes only its fixed public identity in read-only status. A Pro/other-model override is rejected before a provider generation request; clear a previously saved override in Assistant settings if necessary. The bridge is restored. No additional generation calls were made to verify this patch; 612 automated tests pass.

## What is implemented

The local server recognizes only the official `https://api.deepseek.com/chat/completions` and `/v1/chat/completions` routes as the DeepSeek profile. Other Chat Completions services retain the existing full-project protocol.

DeepSeek receives the prompt, numeric note context, selected target IDs and explicit allowed beat windows. It returns compact `[pitch, start, duration, velocity]` tuples, not a replacement application document. The server validates every target and note before merging anything. The browser still stages a candidate; generation never applies or plays it automatically.

- Default model: `deepseek-flash` (configurable server-side).
- JSON output and thinking disabled for this bounded note task.
- Default maximum output: 16,384 tokens; configurable from 1,024 to 32,768 with `LLM_MAX_TOKENS`.
- At most 512 replacement notes, with a smaller budget for short windows or smaller token caps. This deliberately favors sparse, complete phrases. For dense or long arrangements, generate individual clips/sections rather than one entire song.
- Tempo, key, length, instruments, samples, track IDs, mix and clip boundaries stay fixed. Change these explicitly in the editor before generating.
- Exact target IDs are required, including when two tracks use the same instrument. Unknown, duplicate or missing target IDs are rejected.
- Invalid pitches, velocities, duplicate pitch/onset pairs, cross-window notes, excessive notes, empty results and truncated responses are rejected, not silently repaired or substituted with offline music.
- Existing cancellation, late-result rejection, one-request concurrency and pre-apply backup remain in effect. No automatic paid retries.

## V100 setup (current working configuration)

Use `npm run start:v100` or open `Start with V100.command` on the Mac. Stop an older Sprout server first if port 4173 is occupied. The launcher:

1. Syncs app source to `WZU_Server:~/codex-build/seed-studio/`, excluding credentials, environment files, Git data, dependencies, examples and audio assets.
2. Starts the remote model service on V100 loopback port 54173; it reads the existing `~/.deepseek_key` there, never copying it to the Mac or printing it.
3. Uses an SSH tunnel bound to Mac loopback only, with host-key checking retained and agent forwarding disabled.
4. Serves the normal app and its samples locally on port 4173. Browser protocol addresses stay `/api/compose` and `/api/llm/status`; the local server relays model requests through the tunnel.

Choose the model service in the existing assistant settings, then Generate intentionally. Startup and configuration checks make no model calls. Closing the launcher stops the tunnel and service; there is no permanent daemon or public listener. If V100 is unavailable, the app reports the failure rather than falling back to a different paid provider. Offline tools remain usable.

The current V100 bridge was exercised with its installed Node 20.20.2 for this narrow server path. The packaged local app still requires Node 22+. No runtime was installed or upgraded on V100.

## Alternative: local-key setup

1. Copy `.env.example` to `.env` if the file does not exist.
2. Set `LLM_API_KEY` in that local file. Do not put credentials in browser settings, prompts, music projects, logs or source control.
3. Restart the local server with `npm start`.
4. In assistant settings, select the model service. Keep browser addresses `/api/compose` and `/api/llm/status` unchanged.
5. Check configuration, then explicitly generate a candidate. Review, audition and apply separately.

A configuration check does not call DeepSeek or verify account balance, credentials or music quality. An empty DeepSeek key is reported as not ready; keyless local compatible servers still work.

## One-call real-provider test

```sh
npm run test:deepseek -- --live
```

Without `--live`, the command makes no request. With it, the runner uses the local `.env`, refuses a non-official destination, and makes at most one bounded request. It creates its own blank four-bar, eight-track sampled project; no existing browser workspace is read or sent.

Successful output is saved under `examples/deepseek-live/`: input, generated `.sprout`, MIDI and a sanitized report. The report includes model/request ID when available, elapsed time, reported token usage, note count, sample count and MIDI round-trip checks. It does **not** record credentials, headers, upstream error bodies or reasoning content. This CLI does not render or listen to audio. Import the generated project into a separate workspace and verify WAV/audio before judging musical usefulness.

`passed-structural-checks` means parsable, valid notes and a successful MIDI round-trip—not that the music sounds good. Missing credentials produce `blocked`, with zero model calls. A failed provider response is not retried automatically.

## Additional real-model regression batch (v0.27)

Six further calls completed at the declared cap, without retries: all six passed format/scope preservation, and five passed their explicit measurable musical requirements. The numeric harmony and shared-Pattern chorus both followed all four chord/bass anchors and eighth-note hats. The ambient response omitted two requested roles. No result was silently corrected. [Full batch evidence](examples/deepseek-batch-v27/README.md).

The batch used 23,441 reported tokens; all recorded tests together total nine requests / 30,751 tokens. All six mixes and eight numeric-harmony stems are non-silent and unclipped. Held cello/flute samples continue past six seconds. 630 automated tests replay actual output without making paid calls.

The optional batch CLI is inert without `--live`, runs on V100 using the existing remote key, caps calls at six / output at 8,192 tokens each, and creates new timestamped folders instead of overwriting evidence.

## Earlier test evidence

Three authenticated `deepseek-flash` calls completed on V100: two eight-instrument arrangements and one flute-only edit through the local API/SSH bridge. Total reported usage was 7,310 tokens. No automatic retries were used. See [actual projects, MIDI, WAV and findings](examples/deepseek-live/README.md).

The first arrangement had 62 notes. Explicit beat/chord guidance increased the second to 83 notes and fixed the requested hi-hat rhythm, but still missed the F bass root at the second bar's downbeat. It is not reported as fully instruction-compliant. The bridge edit returned 11 flute notes and preserved seven unselected tracks, for 79 total notes.

Both full mixes and all eight stems of the explicit arrangement were rendered with the actual app graph and sampled assets using an offline Node backend. They are non-silent and unclipped. This is separate from browser/UI verification and subjective listening. [Audio QA details](HEADLESS-AUDIO-QA.md).

Synthetic unit tests remain labeled separately and never spend provider tokens during `npm test`.

## Official references checked 2026-10-15

- [Chat Completions](https://api-docs.deepseek.com/api/create-chat-completion/): model IDs, disabled thinking, token limit, JSON response and response usage.
- [JSON output](https://api-docs.deepseek.com/guides/json_mode/): JSON instructions/example, reasonable output limit, possible empty content.

The model name is a server setting rather than a hard-coded assumption about future provider availability.
