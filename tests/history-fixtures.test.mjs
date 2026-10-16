import test from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';
import {validateProject} from '../dist/music.js';
const bytes=path=>readFile(new URL('../examples/'+path,import.meta.url));
const project=async path=>JSON.parse(await bytes(path));
for(const [filename,name] of [['history-renamed.sprout','刷新历史 · 安静验证'],['history-redone.sprout','重做路径 · 安静验证']])test('Actual immediate-refresh export '+filename+' differs only in intended name',async()=>{const p=await project(filename),before=await project('long-song-demo.sprout');assert.equal(p.name,name);assert.deepEqual(validateProject(p),p);assert.deepEqual({...p,name:before.name},before);assert.equal(p.tracks.reduce((n,t)=>n+t.notes.length,0),816);assert.deepEqual(p.loopRange,{start:64,end:96});assert.equal(p.patterns.length,1)});
test('Actual twice-undone and immediately refreshed original is byte-exact to the main example',async()=>{assert.deepEqual(await bytes('history-restored.sprout'),await bytes('long-song-demo.sprout'))});
