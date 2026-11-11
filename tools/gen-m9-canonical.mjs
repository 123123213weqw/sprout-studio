// M9 对拍:表演整理(performance.js)。
import { writeFileSync, readFileSync, mkdirSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';
const repoRoot = new URL('..', import.meta.url).pathname;
let from = repoRoot;
try { readFileSync(`${repoRoot}dist/performance.js`); } catch { from = '/tmp/sprout-dist'; }
const { validateProject } = await import(`${from}/dist/music.js`);
const { planPerformance, PERFORMANCE_PRESETS } = await import(`${from}/dist/performance.js`);
const { checksum } = await import(`${from}/dist/storage.js`);
const stripIds = value => JSON.parse(JSON.stringify(value, (k, v) => (k === 'id' || k === 'patternId' ? undefined : v)));

const files = [];
(function walk(d){ for (const e of readdirSync(d, { withFileTypes: true })) { const p = join(d, e.name); if (e.isDirectory()) walk(p); else if (e.name.endsWith('.sprout')) files.push(p); } })(join(repoRoot, 'examples'));

const results = {};
for (const f of files) {
  const rel = relative(join(repoRoot, 'examples'), f);
  const p = validateProject(JSON.parse(readFileSync(f, 'utf8')));
  const entry = {};
  for (const track of p.tracks) {
    const selected = track.notes.slice(0, Math.min(8, track.notes.length)).map(n => n.id);
    if (!selected.length) continue;
    for (const preset of PERFORMANCE_PRESETS) {
      const key = `${track.instrument}:${preset.id}`;
      try {
        const r = planPerformance(p, track.id, { scope: 'selected', ids: selected, controls: preset.controls });
        entry[key] = r.project ? checksum(JSON.stringify(stripIds(r.project))) : 'blocked:' + r.report.blocked.join(';');
      } catch (e) { entry[key] = 'error:' + e.message; }
    }
    // 修剪重叠变体
    try {
      const r = planPerformance(p, track.id, { scope: 'track', controls: { ...preset0(PERFORMANCE_PRESETS), overlap: 'trim', timing: 'natural' } });
      entry[`${track.instrument}:trim`] = r.project ? checksum(JSON.stringify(stripIds(r.project))) : 'blocked:' + r.report.blocked.join(';');
    } catch (e) { entry[`${track.instrument}:trim`] = 'error:' + e.message; }
    break; // 每工程第一条有音符的轨
  }
  results[rel] = entry;
}
function preset0(list) { return list[0].controls; }
const outDir = join(repoRoot, 'shared/canonical');
mkdirSync(outDir, { recursive: true });
writeFileSync(join(outDir, 'm9-logic.json'), JSON.stringify({ version: 1, performance: results }, null, 1) + '\n');
const total = Object.values(results).reduce((n, e) => n + Object.keys(e).length, 0);
console.log(`m9-logic.json: ${Object.keys(results).length} fixtures, ${total} digests`);
