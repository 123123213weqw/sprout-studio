// 一次性提取:从 dist JS 的内联常量表生成 shared/tables.json。
// 与 restore-release-media.py 同性质:迁移期工具,产出物提交进仓库;
// 之后 shared/tables.json 是唯一数据事实来源,本脚本仅留档(重跑会先 diff 再覆盖)。
//
// 用法:node tools/extract-tables.mjs [--from /tmp/sprout-dist]
// (dist 在工作区可能被删除;默认从 git HEAD 提取到 /tmp 再导入)
import { writeFileSync, readFileSync, mkdirSync } from 'node:fs';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const repoRoot = new URL('..', import.meta.url).pathname;
let from = process.argv.indexOf('--from') + 1 ? process.argv[process.argv.indexOf('--from') + 1] : null;
if (!from) {
  // 默认:直接读工作区 dist;不存在则从 git HEAD 提取
  try { readFileSync(`${repoRoot}dist/instruments.js`); from = repoRoot; }
  catch {
    const { execSync } = require('node:child_process');
    execSync(`mkdir -p /tmp/sprout-dist && git -C ${repoRoot} archive HEAD dist | tar -x -C /tmp/sprout-dist`);
    from = '/tmp/sprout-dist';
  }
}

const INSTRUMENTS = (await import(`${from}/dist/instruments.js`)).INSTRUMENTS;
const { KEYS, STYLES } = await import(`${from}/dist/music.js`);
const { BAR_LENGTHS, MAX_BARS, MAX_BEATS, MAX_PROJECT_NOTES } = await import(`${from}/dist/limits.js`);
const { SECTION_KINDS } = await import(`${from}/dist/sections-core.js`);
const { WAVEFORMS, SOUND_DEFAULTS, soundDefinition } = await import(`${from}/dist/sound.js`);
const { CONTROL_DEFAULTS } = await import(`${from}/dist/composition.js`);
const { PATTERN_LIMITS } = await import(`${from}/dist/patterns-core.js`);
const { SAMPLE_PRESETS } = await import(`${from}/dist/sampler-core.js`);

const instruments = Object.fromEntries(Object.entries(INSTRUMENTS).map(([id, i]) => [
  id,
  { name: i.name, label: i.label, kind: i.kind, icon: i.icon, color: i.color, ...(i.pitch !== undefined ? { pitch: i.pitch } : {}) },
]));

// soundDefinition() 是函数;逐乐器调用,固化字段顺序(key/min/max 决定 normalizeSound 的校验次序)
const soundDefinitions = Object.fromEntries(Object.keys(SOUND_DEFAULTS).map(instrument => {
  const d = soundDefinition(instrument);
  return [instrument, { kind: d.kind, fields: d.fields.map(f => ({ key: f.key, min: f.min, max: f.max, label: f.label, unit: f.unit })) }];
}));

const tables = {
  version: 1,
  instruments,
  keys: KEYS,
  styles: STYLES,
  sectionKinds: SECTION_KINDS,
  waveforms: WAVEFORMS,
  sound: { defaults: SOUND_DEFAULTS, definitions: soundDefinitions },
  controlDefaults: CONTROL_DEFAULTS,
  limits: { barLengths: BAR_LENGTHS, maxBars: MAX_BARS, maxBeats: MAX_BEATS, maxProjectNotes: MAX_PROJECT_NOTES, patternLimits: PATTERN_LIMITS },
  // 校验层只需要兼容性与默认值;完整资产表(2259 条 SAMPLE_ASSETS)留给 M1 的媒体清单
  samplePresets: Object.entries(SAMPLE_PRESETS).map(([id, p]) => ({ id, instrument: p.instrument, kind: p.kind, gain: p.gain, release: p.release })),
};

mkdirSync(`${repoRoot}shared`, { recursive: true });
writeFileSync(`${repoRoot}shared/tables.json`, JSON.stringify(tables, null, 2) + '\n');
console.log(`shared/tables.json: ${Object.keys(instruments).length} instruments, ${tables.samplePresets.length} presets, ${Object.keys(KEYS).length} keys`);
