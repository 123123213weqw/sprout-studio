// M2 纯函数对拍基准:移调与长度调整。与 gen-m1-canonical 同性质。
import { writeFileSync, readFileSync, mkdirSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';

const repoRoot = new URL('..', import.meta.url).pathname;
let from = repoRoot;
try { readFileSync(`${repoRoot}dist/music.js`); } catch { from = '/tmp/sprout-dist'; }
const { validateProject, transposeProject } = await import(`${from}/dist/music.js`);
const { resizeProject } = await import(`${from}/dist/music.js`);
const { checksum } = await import(`${from}/dist/storage.js`);

const stripIds = value => JSON.parse(JSON.stringify(value, (k, v) => (k === 'id' ? undefined : v)));

const transpose = {};
const resize = {};
const files = [];
(function walk(d){ for (const e of readdirSync(d, { withFileTypes: true })) { const p = join(d, e.name); if (e.isDirectory()) walk(p); else if (e.name.endsWith('.sprout')) files.push(p); } })(join(repoRoot, 'examples'));

for (const f of files) {
  const rel = relative(join(repoRoot, 'examples'), f);
  const p = validateProject(JSON.parse(readFileSync(f, 'utf8')));
  // 移调:当前调 → C major → 回原调(移调会改音高,往返不保证一致,逐段摘录即可)
  const keys = ['A minor', 'C major', 'D minor', 'E minor', 'G major', 'F major'];
  const target = keys.find(k => k !== p.key) ?? 'C major';
  const moved = transposeProject(p, target);
  transpose[rel] = { target, digest: checksum(JSON.stringify(stripIds(moved))) };
  // 长度:延长一档(repeat)与缩到 4 小节(可能因段落对齐抛错,记录错误)
  const longer = [16, 32, 64].find(b => b > p.bars) ?? 64;
  try {
    const grown = resizeProject(p, longer, { fill: 'repeat' });
    resize[rel] = { bars: longer, digest: checksum(JSON.stringify(stripIds(grown))) };
  } catch (e) {
    resize[rel] = { bars: longer, error: String(e.message) };
  }
}

const outDir = join(repoRoot, 'shared/canonical');
mkdirSync(outDir, { recursive: true });
writeFileSync(join(outDir, 'm2-logic.json'), JSON.stringify({ version: 1, transpose, resize }, null, 1) + '\n');
console.log(`m2-logic.json: ${Object.keys(transpose).length} transpose, ${Object.keys(resize).length} resize digests`);
