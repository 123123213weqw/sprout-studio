# Restrained product decisions

## Product goal

A beginner should be able to describe a musical change, hear a candidate, understand what it changes, and apply or undo it without needing to understand model APIs. The timeline and notes remain the product, not a decorative AI chat screen.

## Decision rule

Every proposed interface element must support a concrete action, a necessary distinction, or recovery from a meaningful failure. If removing it does not make one of those worse, it should be removed or folded into an existing disclosure. Keep existing neutral colors, system type and compact control styling; do not add gradients, decorative cards, mascots, badges or a second competing accent.

## Implemented behavior and rationale

| Decision | User need | Trade-off | Verification |
| --- | --- | --- | --- |
| Generate a candidate, never replace the song immediately | Explore without losing current work | One explicit Apply step | Existing candidate/backup/stale-result regression tests |
| Return notes, not an entire project, from DeepSeek | Keep chosen sampled instruments and editing structure intact | This profile cannot change tempo/key/length by prompt | All/track/clip/drum/section boundary and sample-preservation tests |
| Fixed token and replacement-note budgets | Avoid an open-ended wait or unexpectedly large response | Dense 32/64-bar songs should be developed by clip or section | Token, note-budget, truncation and malformed-response tests |
| No paid automatic retries | Make each provider invocation intentional | User must choose to retry after a temporary failure | Single-request runner and existing request-gate tests |
| Read-only configuration check | Diagnose setup without spending tokens or uploading music | Configuration validity does not prove authentication | Status route tests; missing key produces not-ready |
| Receipt attached only to successful model candidates | Distinguish a returned model response from offline rules | Additional metadata, not a quality rating or billing invoice | Sanitization and candidate-persistence tests |
| Keep the V100 key on V100; relay through a loopback SSH tunnel | Avoid asking a beginner to manage keys in a music project | Requires an active SSH connection; there is no silent provider fallback | Real local-to-V100 edit plus bridge, origin, outage and cancellation tests |
| Own four-bar blank test fixture | Test the provider without changing or uploading the current song | Does not prove the user's whole arrangement is good | Input immutability, eight sampled roles, MIDI round-trip |

## Evidence from real model tests

The first real response produced valid eight-instrument MIDI but did not follow its own claimed bass and hi-hat instructions. A more explicit prompt fixed the hats, but still missed one bass root. This supports a factual candidate review, not a model self-awarded quality badge. The third real request confirmed that a flute-only edit kept seven other tracks unchanged. Rendered WAV/stems establish non-silent, unclipped output, not artistic quality.

The V100 connection reuses the existing assistant protocol and candidate controls. It adds no competing dashboard, model chat page, decorative connection card or public-hosting flow. The one extra launcher has a specific job: make the remote-key setup repeatable without requiring a beginner to type or copy a secret.

## Additional evidence from the six-call batch

Numeric chord/bass anchors eliminated the specific root-mapping miss in both the full arrangement and the chorus test. That supports supplying concrete musical reference data rather than expecting a beginner to debug a model's prose. The clip and drum cases followed exact timing/pitch lists; all scope protections held.

One ambient result still omitted two requested instrument roles. This strengthens the proposed factual review summary (which tracks contain notes, which are rests), rather than an AI “success” badge or silent note injection. The omission is a measured failure, not a reason to force drums into every ambient song. No new visual element was implemented without screenshot evidence.

## Next interface pass — proposed, not visually verified

These are scoped improvements, not a new visual direction:

1. **One obvious Generate action.** Keep the prompt and scope beside it. Place alternative generation and low-frequency parameters behind the existing disclosure, rather than competing for attention.
2. **Simple connection settings first.** Show generation mode and read-only readiness check; put protocol URLs and model override under Advanced. A beginner using the bundled server should never need to edit those addresses.
3. **A compact, factual candidate source line.** Use the successful-response receipt for provider/model, elapsed time and reported token total. Do not use a green “connected” badge as proof of permanent availability or a “best result” score.
4. **Progress messages describe the next decision.** Waiting, stopped, failed and ready are distinct. Explain whether current work changed; avoid repeating the same long warning in several places.
5. **One primary decision per stage.** Generate before a candidate exists, Apply when reviewing one, with audition and discard as secondary actions. No autoplay.

These proposals are grounded in source structure, **not a completed visual audit**. The current browser tab was on a connection-error document when the local server was restored, and browser automation was blocked from reloading it. No workaround or alternative browser was used. Screenshot-based evaluation and UI implementation are pending a user refresh. No visual-improvement claim is made for this delivery.

## Visual acceptance criteria for the next pass

- Capture the current workspace, connection settings and candidate review before edits.
- Preserve the working timeline/editor proportions and existing sound controls.
- Test desktop and 390-pixel mobile widths, keyboard focus, modal scrolling, cancellation and Apply/Undo.
- Save before/after evidence at matching viewport/state; explain each intentional difference.
- Inspect layout, typography, spacing, color, copy and source attribution, not only whether the buttons click.
- Screenshots alone cannot establish screen-reader correctness or full accessibility compliance; test semantics and keyboard behavior separately.

## v0.28 — recording quality before more interface

| Decision | Reason | Deliberate limit |
| --- | --- | --- |
| Add actual guitar, solo violin and clarinet to the existing source menu | Answer the reported synthetic timbre with genuinely different recordings | No extra dashboard, effects panel or decorative instrument cards |
| Guitar microphone signal, four dynamics and two recorded takes | Preserve acoustic body/attack and reduce identical retriggers | Not a full guitar fingering or release-noise engine |
| Longer explicit previews for bowed/wind voices | A 280 ms test note hides their natural attack and sustain | No automatic preview; quiet/stale-window guards remain |
| Keep previous voices and notes unchanged | Timbre updates must not silently change saved work | New recordings are opt-in source choices |
| Bulk-fill only synth tracks | Choosing recordings for remaining tracks must not erase a guitar/violin/clarinet already selected | Existing sampled sources need individual changes, not a blanket reset |
| Bounded LRU decoded cache plus separate prepared-buffer ceiling | More real recordings must not make later source switches fail at the old cache limit | Memory is not zero-cost; the full library is 100.88 MB on disk |
| Source-only, performance-only derivative and authored demo kept distinct | Let the user hear what changed rather than presenting edited music as raw model output | No claim that sample count or signal tests prove subjective realism |

No layout or styling redesign was attempted without a usable screenshot. New choices reuse the existing responsive source/add-instrument controls; visual verification remains unperformed in this run.

## v0.29 — a larger library without a wall of choices

| Decision | Reason | Deliberate limit |
| --- | --- | --- |
| Count presets separately from files and source families | Answer “100+ sounds” without inflating counts with takes or pretending all sounds are acoustic | 179 sounds includes related program variations, not 179 independent instrument families |
| Source labels for recordings, SoundFont and original synthesis | A choir/EDM sound must not be mislabeled as a newly recorded person or acoustic instrument | No text-to-singing, full vocalist system or hardware-sample claim |
| One search field and one native category selector | Find a sound without adding another dashboard or decorative cards | Literal token search over fixed metadata; no network recommendation service |
| Featured 24 first, explicit Show more | Avoid 179 simultaneous buttons and accidental auto-audition | No infinite scroll or hover-triggered playback |
| Native optgroups for changing an existing compatible source | Preserve keyboard/browser semantics instead of a custom combobox | Source changes stay compatible with the track's coarse musical role |
| Root-scoped preparation and pinned active buffers | Keep a large collection usable without loading every voice into audio memory | Finite cache budgets; oversized combinations fail explicitly |
| Every preset gets an offline audition, plus authored genre sketches | Catch empty/broken registrations and test real audio, not merely labels | Signal tests cannot replace the user's ears or current visual QA |

Search/filter/load/stale-window behavior is covered by component-level mock-DOM tests. This is not a screenshot or accessibility audit of the running browser. Existing colors, layout and source controls remain the visual foundation.
