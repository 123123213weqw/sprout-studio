import test from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';
import {validateProject,copy,encodeMIDI} from '../dist/music.js';
import {notesSignature,materializedNotes,patternInstances} from '../dist/patterns-core.js';
import {exportPatternLibrary,readPatternFile,serializePatternLibrary,planPatternImport} from '../dist/pattern-transfer.js';
import {decodeMIDI} from '../dist/midi.js';import {playbackPlan} from '../dist/transport.js';
const file=name=>readFileSync(new URL('../examples/'+name,import.meta.url));
const project=name=>{const p=JSON.parse(file(name));assert.deepEqual(validateProject(p),p);return p};
const library=name=>readPatternFile(file(name).toString('utf8')).library;
const factory=patterns=>{const remaining=patterns.flatMap(p=>[p.id,...p.notes.map(n=>n.id)]);return()=>{assert.ok(remaining.length);return remaining.shift()}};

test('Actual quiet-browser three-phrase and single-phrase downloads contain exact sources, relative notes and reference context',()=>{
 const original=project('long-song-demo.sprout'),source=project('portable-source-project.sprout'),all=library('portable-phrases.sprout-patterns'),one=library('portable-kick.sprout-patterns');
 assert.deepEqual({...source,patterns:source.patterns.slice(0,1)},original);assert.deepEqual(all,exportPatternLibrary(source));assert.deepEqual(readPatternFile(JSON.stringify(source)).library,all);
 assert.deepEqual(all.patterns.map(p=>[p.instrument,p.length,p.notes.length]),[['keys',8,16],['kick',8,6],['lead',8,8]]);assert.deepEqual(all.context,{bpm:86,key:'A minor',swing:12});
 assert.equal(serializePatternLibrary(all),file('portable-phrases.sprout-patterns').toString('utf8'));
 const imported=project('portable-import-demo.sprout');assert.deepEqual(one,exportPatternLibrary(imported,{ids:[imported.patterns[1].id]}));assert.equal(one.patterns[0].notes.length,6);
});
test('Actual default skip and selected explicit-copy imports reproduce the complete pure plan, preserving four refs and unchanged MIDI',()=>{
 const before=project('long-song-demo.sprout'),input=library('portable-phrases.sprout-patterns'),imported=project('portable-import-demo.sprout'),copied=project('portable-copy-demo.sprout');
 const r=planPatternImport(before,input,{idFactory:factory(imported.patterns.slice(1))});assert.deepEqual(r.project,imported);assert.deepEqual([r.stats.selected,r.stats.added,r.stats.skipped],[3,2,1]);assert.deepEqual(imported.tracks,before.tracks);
 const explicit=planPatternImport(imported,input,{ids:[input.patterns[1].id],duplicates:'copies',idFactory:factory(copied.patterns.slice(3))});assert.deepEqual(explicit.project,copied);assert.deepEqual([explicit.stats.added,explicit.stats.renamed],[1,1]);assert.equal(copied.patterns[3].name,'雨夜底鼓 · 两小节 · 导入 2');assert.equal(patternInstances(copied,copied.patterns[3].id).length,0);
 assert.equal(patternInstances(imported,imported.patterns[0].id).length,4);assert.deepEqual(file('portable-import-demo.mid'),file('long-song-demo.mid'));assert.deepEqual(file('portable-import-demo.mid'),Buffer.from(encodeMIDI(imported)));
});
test('Actual second blank project imports all three sources under fresh IDs without creating a single note or clip',()=>{
 const start=project('portable-target-start.sprout'),imported=project('portable-target-library.sprout'),input=library('portable-phrases.sprout-patterns'),source=project('portable-source-project.sprout');
 assert.notEqual(start.id,source.id);assert.equal(start.bars,8);assert.equal(start.tracks.reduce((n,t)=>n+t.notes.length,0),0);assert.equal(start.patterns,undefined);
 const r=planPatternImport(start,input,{idFactory:factory(imported.patterns)});assert.deepEqual(r.project,imported);assert.equal(r.stats.added,3);assert.deepEqual(imported.tracks,start.tracks);
 imported.patterns.forEach((p,i)=>{assert.notEqual(p.id,input.patterns[i].id);assert.equal(notesSignature(p.notes),notesSignature(input.patterns[i].notes));assert.equal(patternInstances(imported,p.id).length,0)});
 assert.equal(playbackPlan(imported).events.length,0);assert.deepEqual(encodeMIDI(imported),encodeMIDI(start));
});
test('Actual deliberate three-track placement, 30-note MIDI and offline range WAV exactly match source materialization and playback timing',()=>{
 const imported=project('portable-target-library.sprout'),p=project('portable-arranged-demo.sprout'),wanted=copy(imported);wanted.name='乐句拼装 · 静音示例';wanted.bars=16;wanted.loopRange={start:32,end:40};
 assert.deepEqual(p.patterns,imported.patterns);assert.equal(p.tracks.reduce((n,t)=>n+t.notes.length,0),30);
 for(const source of imported.patterns){const target=wanted.tracks.find(t=>t.instrument===source.instrument),actual=p.tracks.find(t=>t.id===target.id),added=actual.clips.filter(c=>!target.clips.some(old=>old.id===c.id));assert.equal(added.length,1);const c=added[0];assert.deepEqual([c.start,c.length,c.patternId],[32,8,source.id]);target.clips.push(copy(c));target.notes.push(...materializedNotes(source,c));assert.equal(patternInstances(p,source.id).length,1)}
 assert.deepEqual(validateProject(wanted),p);const events=playbackPlan(p,{range:null}).events,midi=decodeMIDI(file('portable-arranged-demo.mid')).project;assert.deepEqual(file('portable-arranged-demo.mid'),Buffer.from(encodeMIDI(p)));assert.equal(events.length,30);assert.equal(midi.tracks.reduce((n,t)=>n+t.notes.length,0),30);
 for(const t of p.tracks.filter(t=>t.notes.length)){const notes=midi.tracks.find(x=>x.instrument===t.instrument).notes.sort((a,b)=>a.start-b.start||a.pitch-b.pitch),plan=events.filter(e=>e.t.id===t.id).sort((a,b)=>a.beat-b.beat||a.n.pitch-b.n.pitch);assert.equal(notes.length,plan.length);plan.forEach((e,i)=>{assert.equal(notes[i].pitch,e.n.pitch);assert.equal(notes[i].velocity,e.n.velocity);assert.ok(Math.abs(notes[i].start-e.beat)<1/480+.0001);assert.ok(Math.abs(notes[i].duration-e.n.duration)<1/480+.0001)})}
 const wav=file('portable-arranged-region.wav');assert.equal(wav.toString('ascii',0,4),'RIFF');assert.equal(wav.toString('ascii',8,12),'WAVE');assert.equal(wav.readUInt32LE(4),wav.length-8);assert.equal(wav.readUInt32LE(40),wav.length-44);assert.deepEqual([wav.readUInt16LE(22),wav.readUInt32LE(24),wav.readUInt16LE(34)],[2,44100,16]);assert.ok(Math.abs((wav.length-44)/4/44100-(8*60/p.bpm+1.5))<1/44100);assert.equal(playbackPlan(p,{range:p.loopRange}).events.length,30);
 let sum=0,peak=0,clipped=0;for(let i=44;i<wav.length;i+=2){const v=wav.readInt16LE(i)/32768;sum+=v*v;peak=Math.max(peak,Math.abs(v));if(Math.abs(v)>=.999)clipped++}assert.ok(peak>.01&&peak<.99);assert.ok(Math.sqrt(sum/((wav.length-44)/2))>.01);assert.equal(clipped,0);
});
