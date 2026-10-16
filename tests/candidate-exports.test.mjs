import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {validateProject,encodeMIDI} from '../dist/music.js';
import {createOfflineAlternatives} from '../dist/candidates.js';
import {candidateComparisonReport} from '../dist/candidate-ui.js';
import {compareProjects} from '../dist/composition.js';
import {patternInstances} from '../dist/patterns.js';
import {decodeMIDI} from '../dist/midi.js';
import {playbackPlan} from '../dist/transport.js';
const file=name=>readFileSync(new URL('../examples/'+name,import.meta.url));
const load=name=>{const raw=JSON.parse(file(name)),p=validateProject(raw);assert.deepEqual(p,raw);return p};
const musical=ns=>ns.map(({id,...n})=>n).sort((a,b)=>a.start-b.start||a.pitch-b.pitch||a.duration-b.duration||a.velocity-b.velocity);

test('Actual quiet-browser A/B/C exports reproduce the frozen section/seed inputs and protect every outside ID and source',()=>{
 const before=load('long-song-demo.sprout'),report=JSON.parse(file('candidate-ab-comparison.json'));
 const expected=createOfflineAlternatives(before,report.a.prompt,{...report.a.context,controls:report.a.controls});
 const exported=['a','b','c'].map(letter=>load('candidate-'+letter+'.sprout'));
 assert.deepEqual(exported.map(p=>p.tracks.reduce((n,t)=>n+t.notes.length,0)),[690,734,814]);
 exported.forEach((p,index)=>{
  assert.equal(p.bars,32);assert.equal(p.bpm,86);assert.equal(p.key,'A minor');assert.deepEqual(p.sections,before.sections);assert.deepEqual(p.loopRange,before.loopRange);assert.deepEqual(p.patterns,before.patterns);assert.equal(patternInstances(p,p.patterns[0].id).length,4);
  p.tracks.forEach((t,i)=>{const old=before.tracks[i];assert.equal(t.id,old.id);assert.deepEqual(t.sound,old.sound);assert.deepEqual([t.instrument,t.name,t.volume,t.pan,t.muted,t.solo],[old.instrument,old.name,old.volume,old.pan,old.muted,old.solo]);assert.deepEqual(t.clips,old.clips);assert.deepEqual(t.notes.filter(n=>n.start<64||n.start>=96),old.notes.filter(n=>n.start<64||n.start>=96));assert.deepEqual(musical(t.notes),musical(expected[index].project.tracks[i].notes))});
 });
 assert.deepEqual(report.differences,compareProjects(exported[0],exported[1]));
 assert.deepEqual([report.differences.added,report.differences.removed,report.differences.modified],[58,14,64]);
 const a={...report.a,before,project:exported[0]},b={...report.b,before,project:exported[1]};assert.deepEqual(candidateComparisonReport(a,b),report);
});

test('Actual localhost mock-service candidate changes only target velocities, detaches two target refs and keeps other caches intact',()=>{
 const before=load('candidate-b.sprout'),p=load('candidate-mock-service.sprout'),diff=compareProjects(before,p);
 assert.deepEqual([diff.notesBefore,diff.notesAfter,diff.changedTracks,diff.added,diff.removed,diff.modified],[734,734,1,0,0,165]);
 assert.equal(diff.patterns.detached,2);assert.equal(diff.soundChanges,0);assert.deepEqual(diff.globals,[]);assert.deepEqual(p.patterns,before.patterns);assert.deepEqual(p.sections,before.sections);assert.deepEqual(p.loopRange,before.loopRange);
 p.tracks.forEach((t,i)=>{const old=before.tracks[i];if(i!==4){assert.deepEqual(t,old);return}assert.deepEqual(t.notes,old.notes.map(n=>({...n,velocity:42})));assert.deepEqual(t.sound,old.sound);assert.deepEqual([t.id,t.name,t.volume,t.pan,t.muted,t.solo],[old.id,old.name,old.volume,old.pan,old.muted,old.solo]);assert.deepEqual(t.clips.map(c=>[c.id,c.name,c.start,c.length,c.muted]),old.clips.map(c=>[c.id,c.name,c.start,c.length,c.muted]));assert.ok(t.clips.every(c=>!c.patternId))});
 assert.equal(patternInstances(p,p.patterns[0].id).length,2);
});

test('Actual applied-B MIDI and offline full/range WAV files match 734/122 events and bounded PCM without clipping',()=>{
 const p=load('candidate-b.sprout'),bytes=file('candidate-b.mid');assert.deepEqual(bytes,Buffer.from(encodeMIDI(p)));
 const events=playbackPlan(p,{range:null}).events,received=decodeMIDI(bytes).project;
 assert.equal(events.length,734);assert.equal(received.tracks.reduce((n,t)=>n+t.notes.length,0),734);assert.equal(playbackPlan(p,{range:p.loopRange}).events.length,122);
 // Pair within each instrument: different tracks can share pitch/onset, and MIDI tick rounding can reorder cross-track ties.
 for(const t of p.tracks){const original=events.filter(e=>e.t.id===t.id).sort((a,b)=>a.beat-b.beat||a.n.pitch-b.n.pitch),actual=received.tracks.find(x=>x.instrument===t.instrument).notes.sort((a,b)=>a.start-b.start||a.pitch-b.pitch);assert.equal(actual.length,original.length);for(let i=0;i<original.length;i++){assert.equal(actual[i].pitch,original[i].n.pitch);assert.equal(actual[i].velocity,original[i].n.velocity);assert.ok(Math.abs(actual[i].start-original[i].beat)<=1/480+.0001);assert.ok(Math.abs(actual[i].duration-original[i].n.duration)<=1/480+.0001)}}
 for(const [name,beats] of [['candidate-b.wav',128],['candidate-b-region.wav',32]]){
  const w=file(name);assert.equal(w.toString('ascii',0,4),'RIFF');assert.equal(w.toString('ascii',8,12),'WAVE');assert.equal(w.readUInt32LE(4),w.length-8);assert.equal(w.readUInt32LE(40),w.length-44);assert.equal(w.readUInt16LE(22),2);assert.equal(w.readUInt32LE(24),44100);assert.equal(w.readUInt16LE(34),16);assert.ok(Math.abs((w.length-44)/4/44100-(beats*60/p.bpm+2.42))<1/44100);
  let peak=0,sum=0,clipped=0;for(let i=44;i<w.length;i+=2){const value=w.readInt16LE(i)/32768;peak=Math.max(peak,Math.abs(value));sum+=value*value;if(Math.abs(value)>=.999)clipped++}assert.ok(peak>.01&&peak<.99);assert.ok(Math.sqrt(sum/((w.length-44)/2))>.01);assert.equal(clipped,0);
 }
});
