// M6 对拍:段落 CRUD/骨架 + 过门填充(确定性输入,uid/patternId 剥离摘要)。
import { writeFileSync, readFileSync, mkdirSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';
const repoRoot = new URL('..', import.meta.url).pathname;
let from = repoRoot;
try { readFileSync(`${repoRoot}dist/sections.js`); } catch { from = '/tmp/sprout-dist'; }
const { validateProject } = await import(`${from}/dist/music.js`);
const { sectionTemplate, updateSection } = await import(`${from}/dist/sections.js`);
const { planSectionFill } = await import(`${from}/dist/section-transition.js`);
const { checksum } = await import(`${from}/dist/storage.js`);
const stripIds = value => JSON.parse(JSON.stringify(value, (k, v) => (k === 'id' || k === 'patternId' ? undefined : v)));

const files = [];
(function walk(d){ for (const e of readdirSync(d, { withFileTypes: true })) { const p = join(d, e.name); if (e.isDirectory()) walk(p); else if (e.name.endsWith('.sprout')) files.push(p); } })(join(repoRoot, 'examples'));

const results = {};
for (const f of files) {
  const rel = relative(join(repoRoot, 'examples'), f);
  const p = validateProject(JSON.parse(readFileSync(f, 'utf8')));
  const entry = {};
  // 骨架模板(所有 fixtures)
  for (const tpl of ['verse-chorus', 'four-parts']) {
    try { entry[`tpl:${tpl}`] = checksum(JSON.stringify(stripIds(sectionTemplate(p, tpl)))); }
    catch (e) { entry[`tpl:${tpl}`] = 'error:' + e.message; }
  }
  // 段落 CRUD:添加一个副歌(起点 0 长度 4)
  try { entry['add'] = checksum(JSON.stringify(stripIds(updateSection(p, { name: '新副歌', kind: 'chorus', start: 0, length: 4 }).project))); }
  catch (e) { entry['add'] = 'error:' + e.message; }
  // 过门:对有 sections 的工程,取第一个段落 × 三种风格 × 1/2 小节 × fillGaps
  if (p.sections?.length) {
    const section = p.sections[p.sections.length - 1];
    const drumIds = p.tracks.filter(t => t.kind === 'drum').map(t => t.id);
    if (drumIds.length) {
      for (const style of ['gentle', 'rise', 'break']) {
        for (const bars of [1, 2]) {
          const key = `fill:${style}:${bars}`;
          try {
            const r = planSectionFill(p, section.id, { trackIds: drumIds, controls: { style, bars, energy: 70, seed: 42, fillGaps: true } });
            entry[key] = checksum(JSON.stringify(stripIds(r.project)));
          } catch (e) { entry[key] = 'error:' + e.message; }
        }
      }
    }
  }
  results[rel] = entry;
}
const outDir = join(repoRoot, 'shared/canonical');
mkdirSync(outDir, { recursive: true });
writeFileSync(join(outDir, 'm6-logic.json'), JSON.stringify({ version: 1, sections: results }, null, 1) + '\n');
const total = Object.values(results).reduce((n, e) => n + Object.keys(e).length, 0);
console.log(`m6-logic.json: ${Object.keys(results).length} fixtures, ${total} digests`);
