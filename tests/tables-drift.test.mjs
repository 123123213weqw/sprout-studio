import test from 'node:test';import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {INSTRUMENTS} from '../dist/instruments.js';
import {KEYS,STYLES} from '../dist/music.js';
import {BAR_LENGTHS,MAX_BARS,MAX_BEATS,MAX_PROJECT_NOTES} from '../dist/limits.js';
import {SECTION_KINDS} from '../dist/sections-core.js';
import {WAVEFORMS,SOUND_DEFAULTS,soundDefinition} from '../dist/sound.js';
import {CONTROL_DEFAULTS} from '../dist/composition.js';
import {PATTERN_LIMITS} from '../dist/patterns-core.js';
import {SAMPLE_PRESETS} from '../dist/sampler-core.js';
import {SAMPLE_ASSETS} from '../dist/sample-assets.js';
// 互维护契约:dist 内联常量表必须与 shared/tables.json + shared/samples.json(单一数据事实来源)一致。
// 改数据的流程:改 shared/*.json → node tools/sync-shared.mjs → 同步改本测试对应的 dist 字面量 → 两栈测试全绿。
const tables=JSON.parse(readFileSync(new URL('../shared/tables.json',import.meta.url),'utf8'));
const samples=JSON.parse(readFileSync(new URL('../shared/samples.json',import.meta.url),'utf8'));
test('instruments, keys, styles and section kinds match shared/tables.json',()=>{
 assert.deepEqual(tables.instruments,Object.fromEntries(Object.entries(INSTRUMENTS).map(([id,i])=>[id,{name:i.name,label:i.label,kind:i.kind,icon:i.icon,color:i.color,...(i.pitch!==undefined?{pitch:i.pitch}:{})}])));
 assert.deepEqual(tables.keys,KEYS);
 assert.deepEqual(tables.styles,STYLES);
 assert.deepEqual(Object.keys(tables.sectionKinds),Object.keys(SECTION_KINDS));
 assert.deepEqual(Object.keys(tables.waveforms),Object.keys(WAVEFORMS));
});
test('sound defaults and field specs match shared/tables.json',()=>{
 assert.deepEqual(tables.sound.defaults,SOUND_DEFAULTS);
 const definitions=Object.fromEntries(Object.keys(SOUND_DEFAULTS).map(instrument=>{const d=soundDefinition(instrument);return[instrument,{kind:d.kind,fields:d.fields.map(f=>({key:f.key,min:f.min,max:f.max,label:f.label,unit:f.unit}))}]}));
 assert.deepEqual(tables.sound.definitions,definitions);
});
test('control defaults and limits match shared/tables.json',()=>{
 assert.deepEqual(tables.controlDefaults,CONTROL_DEFAULTS);
 assert.deepEqual(tables.limits,{barLengths:BAR_LENGTHS,maxBars:MAX_BARS,maxBeats:MAX_BEATS,maxProjectNotes:MAX_PROJECT_NOTES,patternLimits:PATTERN_LIMITS});
});
test('sample preset manifest matches shared/tables.json',()=>{
 assert.deepEqual(tables.samplePresets,Object.entries(SAMPLE_PRESETS).map(([id,p])=>({id,instrument:p.instrument,kind:p.kind,gain:p.gain,release:p.release})));
});
test('full sample presets and assets match shared/samples.json',()=>{
 assert.deepEqual(samples.presets,SAMPLE_PRESETS);
 assert.deepEqual(samples.assets,SAMPLE_ASSETS);
});
