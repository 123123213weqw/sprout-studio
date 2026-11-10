// M3 灵感引擎对拍基准:generateProject 固定矩阵(确定性,uid 剥离后摘要)。
import { writeFileSync, readFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
const repoRoot = new URL('..', import.meta.url).pathname;
let from = repoRoot;
try { readFileSync(`${repoRoot}dist/music.js`); } catch { from = '/tmp/sprout-dist'; }
const { generateProject } = await import(`${from}/dist/music.js`);
const { checksum } = await import(`${from}/dist/storage.js`);
const stripIds = value => JSON.parse(JSON.stringify(value, (k, v) => (k === 'id' ? undefined : v)));

const keys = ['A minor', 'C major', 'D minor', 'E minor', 'G major', 'F major'];
const barsList = [4, 8];
const seeds = [1, 271828, 999];
const compositions = [null, { density: 80, complexity: 80, energy: 75, humanize: 25, progression: 'lift', voiceLeading: false, seed: 424242 }];
const generate = {};
for (const style of ['lofi', 'hiphop', 'house', 'ambient']) {
  for (const key of keys) {
    for (const bars of barsList) {
      for (const seed of seeds) {
        for (let ci = 0; ci < compositions.length; ci++) {
          const composition = compositions[ci];
          const id = `${style}|${key}|${bars}|${seed}|c${ci}`;
          try {
            const p = generateProject({ style, key, bars, seed, composition: composition ? { ...composition } : undefined });
            generate[id] = checksum(JSON.stringify(stripIds(p)));
          } catch (e) {
            generate[id] = 'error:' + e.message;
          }
        }
      }
    }
  }
}
const outDir = join(repoRoot, 'shared/canonical');
mkdirSync(outDir, { recursive: true });
writeFileSync(join(outDir, 'm3-logic.json'), JSON.stringify({ version: 1, generate }, null, 1) + '\n');
console.log(`m3-logic.json: ${Object.keys(generate).length} generate digests`);
