// M8 对拍:段落复制/移动/清空/仅删标签(planSection)。
import { writeFileSync, readFileSync, mkdirSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';
const repoRoot = new URL('..', import.meta.url).pathname;
let from = repoRoot;
try { readFileSync(`${repoRoot}dist/sections.js`); } catch { from = '/tmp/sprout-dist'; }
const { validateProject } = await import(`${from}/dist/music.js`);
const { planSection } = await import(`${from}/dist/sections.js`);
const { checksum } = await import(`${from}/dist/storage.js`);
const stripIds = value => JSON.parse(JSON.stringify(value, (k, v) => (k === 'id' || k === 'patternId' ? undefined : v)));

const files = [];
(function walk(d){ for (const e of readdirSync(d, { withFileTypes: true })) { const p = join(d, e.name); if (e.isDirectory()) walk(p); else if (e.name.endsWith('.sprout')) files.push(p); } })(join(repoRoot, 'examples'));

const results = {};
for (const f of files) {
  const rel = relative(join(repoRoot, 'examples'), f);
  const p = validateProject(JSON.parse(readFileSync(f, 'utf8')));
  if (!p.sections?.length) continue;
  const entry = {};
  for (const [index, section] of p.sections.entries()) {
    const sid = section.id;
    // copy 到段末之后的空白(延长允许),move 同位起,clear,label-delete
    const target = p.bars * 4; // 工程末尾(允许延长)
    for (const [name, fn] of [
      ['copy-end', () => planSection(p, sid, { action: 'copy', start: target, extend: true })],
      ['copy-linked', () => planSection(p, sid, { action: 'copy', start: target, extend: true, linked: true })],
      ['move-end', () => planSection(p, sid, { action: 'move', start: target, extend: true })],
      ['clear', () => planSection(p, sid, { action: 'clear' })],
      ['label-delete', () => planSection(p, sid, { action: 'label-delete' })],
    ]) {
      const key = `s${index}:${name}`;
      try {
        const r = fn();
        entry[key] = checksum(JSON.stringify(stripIds(r.project)));
      } catch (e) {
        entry[key] = 'error:' + e.message;
      }
    }
    break; // 每工程第一段
  }
  results[rel] = entry;
}
const outDir = join(repoRoot, 'shared/canonical');
mkdirSync(outDir, { recursive: true });
writeFileSync(join(outDir, 'm8-logic.json'), JSON.stringify({ version: 1, sectionOps: results }, null, 1) + '\n');
const total = Object.values(results).reduce((n, e) => n + Object.keys(e).length, 0);
console.log(`m8-logic.json: ${Object.keys(results).length} fixtures, ${total} digests`);
