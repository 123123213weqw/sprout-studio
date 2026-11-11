// M7 对拍:乐句变换(96 fixtures × 变换矩阵,uid/patternId 剥离摘要)。
import { writeFileSync, readFileSync, mkdirSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';
const repoRoot = new URL('..', import.meta.url).pathname;
let from = repoRoot;
try { readFileSync(`${repoRoot}dist/phrase-transform.js`); } catch { from = '/tmp/sprout-dist'; }
const { validateProject } = await import(`${from}/dist/music.js`);
const { planPhraseTransform } = await import(`${from}/dist/phrase-transform.js`);
const { checksum } = await import(`${from}/dist/storage.js`);
const stripIds = value => JSON.parse(JSON.stringify(value, (k, v) => (k === 'id' || k === 'patternId' ? undefined : v)));

const variants = [
  ['half', { ratio: 0.5 }],
  ['double', { ratio: 2, extend: true }],
  ['reverse', { reverse: true }],
  ['up12', { transpose: 12 }],
  ['snap', { transpose: 7, scale: 'A minor' }],
  ['clear-timing', { ratio: 0.5, timing: 'clear' }],
];
const files = [];
(function walk(d){ for (const e of readdirSync(d, { withFileTypes: true })) { const p = join(d, e.name); if (e.isDirectory()) walk(p); else if (e.name.endsWith('.sprout')) files.push(p); } })(join(repoRoot, 'examples'));

const results = {};
for (const f of files) {
  const rel = relative(join(repoRoot, 'examples'), f);
  const p = validateProject(JSON.parse(readFileSync(f, 'utf8')));
  const entry = {};
  const seenInstruments = new Set();
  for (const track of p.tracks) {
    if (seenInstruments.has(track.instrument)) continue;
    seenInstruments.add(track.instrument);
    for (const [index, clip] of (track.clips || []).entries()) {
      if (index > 0) break; // 每轨第一块
      for (const [name, controls] of variants) {
        const key = `${track.instrument}:${name}`;
        try {
          const r = planPhraseTransform(p, track.id, clip.id, { controls });
          entry[key] = checksum(JSON.stringify(stripIds(r.project)));
        } catch (e) {
          entry[key] = 'error:' + e.message;
        }
      }
      break;
    }
  }
  results[rel] = entry;
}
const outDir = join(repoRoot, 'shared/canonical');
mkdirSync(outDir, { recursive: true });
writeFileSync(join(outDir, 'm7-logic.json'), JSON.stringify({ version: 1, phrase: results }, null, 1) + '\n');
const total = Object.values(results).reduce((n, e) => n + Object.keys(e).length, 0);
console.log(`m7-logic.json: ${Object.keys(results).length} fixtures, ${total} digests`);
