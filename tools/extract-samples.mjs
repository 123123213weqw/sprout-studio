// 一次性提取:采样资产表(SAMPLE_ASSETS 2259 条)与完整 preset 定义(SAMPLE_PRESETS)
// → shared/samples.json。与 extract-tables.mjs 同性质:留档的迁移期工具。
// 之后 shared/samples.json 是采样映射的唯一事实来源(校验/选样/音频层共用)。
import { writeFileSync, readFileSync, mkdirSync } from 'node:fs';

const repoRoot = new URL('..', import.meta.url).pathname;
let from = null;
try { readFileSync(`${repoRoot}dist/sampler-core.js`); from = repoRoot; }
catch { from = '/tmp/sprout-dist'; readFileSync(`${from}/dist/sampler-core.js`); }

const { SAMPLE_ASSETS } = await import(`${from}/dist/sample-assets.js`);
const { SAMPLE_PRESETS } = await import(`${from}/dist/sampler-core.js`);

const out = { version: 1, presets: SAMPLE_PRESETS, assets: SAMPLE_ASSETS };
mkdirSync(`${repoRoot}shared`, { recursive: true });
writeFileSync(`${repoRoot}shared/samples.json`, JSON.stringify(out));
console.log(`shared/samples.json: ${Object.keys(SAMPLE_PRESETS).length} presets, ${SAMPLE_ASSETS.length} assets`);
