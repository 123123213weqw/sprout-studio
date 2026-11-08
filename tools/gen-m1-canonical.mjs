// M1 纯逻辑对拍基准生成器:用 JS 实现(dist)产出 transport / 采样选择 / 采样发声计划
// 的 FNV-32 摘要 → shared/canonical/m1-logic.json。Swift 侧(sproutkit M1LogicTests)
// 用相同输入矩阵计算摘要并逐个比较。两侧语义有意变更时,重跑本脚本并提交。
import { writeFileSync, readFileSync, mkdirSync, readdirSync } from 'node:fs';
import { join, relative, dirname } from 'node:path';

const repoRoot = new URL('..', import.meta.url).pathname;
let from = repoRoot;
try { readFileSync(`${repoRoot}dist/music.js`); } catch { from = '/tmp/sprout-dist'; }

const { validateProject, encodeMIDI } = await import(`${from}/dist/music.js`);
const { playbackPlan, timelineEvents } = await import(`${from}/dist/transport.js`);
const { SAMPLE_PRESETS, pickSample, sampleLayers, sampleVoicePlan } = await import(`${from}/dist/sampler-core.js`);
const { decodeMIDI } = await import(`${from}/dist/midi.js`);
const { checksum } = await import(`${from}/dist/storage.js`);

const r4 = x => +(x.toFixed(4));
const num = x => String(+(x.toFixed(4)));

// ---- transport 摘要:每个 fixture 一次默认播放计划 ----
function transportDigest(project) {
  const plan = playbackPlan(project, { range: project.loopRange });
  const lines = [`R|${num(plan.range.start)}|${num(plan.range.end)}|${num(plan.length)}|${num(plan.seconds)}`];
  for (const e of timelineEvents(plan)) {
    if (e.metro) { lines.push(`M|${num(e.beat)}|${e.accent ? 1 : 0}`); continue; }
    const to = e.n.timingOffset === undefined ? '-' : num(e.n.timingOffset);
    lines.push(`E|${num(e.beat)}|${num(e.originalBeat)}|${e.resumed ? 1 : 0}|${e.t.__index}|${String(e.n.pitch)}|${num(e.n.start)}|${num(e.n.duration)}|${String(e.n.velocity)}|${to}`);
  }
  return checksum(lines.join('\n'));
}

const transport = {};
const files = [];
(function walk(d){ for (const e of readdirSync(d, { withFileTypes: true })) { const p = join(d, e.name); if (e.isDirectory()) walk(p); else if (e.name.endsWith('.sprout')) files.push(p); } })(join(repoRoot, 'examples'));
for (const f of files) {
  const p = validateProject(JSON.parse(readFileSync(f, 'utf8')));
  p.tracks.forEach((t, i) => { t.__index = i; });
  transport[relative(join(repoRoot, 'examples'), f)] = transportDigest(p);
}

// ---- 采样选择摘要:每 preset 固定矩阵 ----
const sampler = {};
for (const id of Object.keys(SAMPLE_PRESETS)) {
  const lines = [];
  for (let pitch = 24; pitch <= 108; pitch++) {
    for (const v of [1, 5, 13, 33, 53, 73, 93, 113, 127]) {
      for (const take of [0, 1, 2]) {
        const picked = pickSample(id, pitch, v, take);
        lines.push(`P|${pitch}|${v}|${take}|${picked.id}`);
        const layers = sampleLayers(id, pitch, v, take).map(x => `${x.asset.id}:${x.weight.toFixed(6)}`).join(';');
        lines.push(`L|${pitch}|${v}|${take}|${layers}`);
      }
    }
  }
  sampler[id] = checksum(lines.join('\n'));
}

// ---- 采样发声计划摘要 ----
const voicePlan = {};
for (const [id, preset] of Object.entries(SAMPLE_PRESETS)) {
  const lines = [];
  for (const pitch of [24, 40, 55, 60, 67, 72, 79, 84, 96, 108]) {
    for (const v of [1, 33, 64, 96, 127]) {
      const a = pickSample(id, pitch, v);
      const plan = sampleVoicePlan(preset.instrument, { preset: id }, pitch, 1.5, v, a.frames / a.sampleRate);
      lines.push(`V|${pitch}|${v}|${plan.asset.id}|rate:${plan.rate.toFixed(6)}|end:${plan.end.toFixed(4)}|rel:${plan.releaseAt.toFixed(4)}|atk:${plan.attack.toFixed(4)}|peak:${plan.peak.toFixed(6)}|loop:${plan.loop ? 1 : 0}`);
    }
  }
  voicePlan[id] = checksum(lines.join('\n'));
}

// ---- MIDI 编解码摘要:每个 fixture 编码 → 字节摘要;解码回读 → 去掉随机 id 后的工程/报告摘要 ----
const stripIds = value => JSON.parse(JSON.stringify(value, (k, v) => (k === 'id' ? undefined : v)));
const fnv32Bytes = bytes => { let v = 0x811c9dc5; for (const b of bytes) { v ^= b; v = Math.imul(v, 0x01000193); } return (v >>> 0).toString(16).padStart(8, '0'); };
const midi = {};
for (const f of files) {
  const p = validateProject(JSON.parse(readFileSync(f, 'utf8')));
  const bytes = encodeMIDI(p);
  const encode = fnv32Bytes(bytes);
  const hasNotes = p.tracks.some(t => t.notes.length);
  const decoded = hasNotes ? decodeMIDI(bytes) : null;
  midi[relative(join(repoRoot, 'examples'), f)] = {
    encode,
    ...(decoded ? {
      project: checksum(JSON.stringify(stripIds(decoded.project))),
      report: checksum(JSON.stringify(decoded.report)),
    } : {}),
  };
}

const outDir = join(repoRoot, 'shared/canonical');
mkdirSync(outDir, { recursive: true });
writeFileSync(join(outDir, 'm1-logic.json'), JSON.stringify({ version: 1, transport, sampler, voicePlan, midi }, null, 1) + '\n');
console.log(`m1-logic.json: ${Object.keys(transport).length} transport, ${Object.keys(sampler).length} sampler, ${Object.keys(voicePlan).length} voicePlan, ${Object.keys(midi).length} midi digests`);
