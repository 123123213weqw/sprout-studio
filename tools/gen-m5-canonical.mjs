// M5 对拍:generateFromPrompt 固定种子矩阵(uid/patternId 剥离摘要)。
import { writeFileSync, readFileSync, mkdirSync } from 'node:fs';
const repoRoot = new URL('..', import.meta.url).pathname;
let from = repoRoot;
try { readFileSync(`${repoRoot}dist/music.js`); } catch { from = '/tmp/sprout-dist'; }
const { validateProject, generateFromPrompt } = await import(`${from}/dist/music.js`);
const { checksum } = await import(`${from}/dist/storage.js`);
const stripIds = value => JSON.parse(JSON.stringify(value, (k, v) => (k === 'id' || k === 'patternId' ? undefined : v)));

const prompts = [
  '来一段温柔的雨夜 lo-fi,慢一点',
  '改成 house 舞曲,16 小节,126 bpm',
  '只要鼓更有力,半拍军鼓',
  '只改旋律,明亮一点,D 小调',
  '氛围空灵 32 小节,快一点',
];
const scopes = ['all', 'drums'];
const results = {};
for (const file of ['palette-demo.sprout', 'library-house.sprout', 'song-sections-start.sprout']) {
  const p = validateProject(JSON.parse(readFileSync(`${repoRoot}examples/${file}`, 'utf8')));
  for (const scope of scopes) {
    for (const prompt of prompts) {
      const id = `${file}|${scope}|${prompt}`;
      try {
        const r = generateFromPrompt(p, prompt, { scope });
        // 种子随机 → 用 controls.seed 固定:重建调用带 controls
        const r2 = generateFromPrompt(p, prompt, { scope, controls: { seed: 7777 } });
        results[id] = checksum(JSON.stringify(stripIds(r2.project))) + '|' + r2.summary;
      } catch (e) {
        results[id] = 'error:' + e.message;
      }
    }
  }
}
const outDir = `${repoRoot}shared/canonical`;
mkdirSync(outDir, { recursive: true });
writeFileSync(`${outDir}/m5-logic.json`, JSON.stringify({ version: 1, prompt: results }, null, 1) + '\n');
console.log(`m5-logic.json: ${Object.keys(results).length} prompt digests`);
