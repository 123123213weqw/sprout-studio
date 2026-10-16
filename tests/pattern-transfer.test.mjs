import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {generateProject,validateProject,copy,encodeMIDI,makeTrack} from '../dist/music.js';
import {capturePattern,placePattern,patternInstances} from '../dist/patterns.js';
import {notesSignature,normalizePatterns} from '../dist/patterns-core.js';
import {packProject,unpackProject} from '../dist/storage.js';
import {playbackPlan} from '../dist/transport.js';
import {PATTERN_FILE_FORMAT,PATTERN_FILE_MAX_BYTES,validatePatternLibrary,exportPatternLibrary,serializePatternLibrary,readPatternFile,planPatternImport} from '../dist/pattern-transfer.js';
const original=()=>JSON.parse(readFileSync(new URL('../examples/long-song-demo.sprout',import.meta.url)));
const source=(id='source',name='乐句')=>({id,name,instrument:'keys',kind:'tonal',length:8,notes:[{id:'note',pitch:60,start:1,duration:.5,velocity:80,timingOffset:.02}]});
const bundle=patterns=>({format:PATTERN_FILE_FORMAT,version:1,context:{bpm:100,key:'C major',swing:0},patterns});
const ids=()=>{let i=0;return()=>`import_${++i}`};
const musical=p=>notesSignature(p.notes);

test('Portable export includes selected source phrases and reference context only, without modifying or playing project',()=>{
 const p=original(),before=copy(p);p.privateSettings={token:'test-only-do-not-export'};
 const all=exportPatternLibrary(p),text=serializePatternLibrary(all),decoded=readPatternFile(text);
 assert.equal(decoded.origin,'library');assert.deepEqual(decoded.library,all);assert.deepEqual(all.patterns,p.patterns);assert.deepEqual(all.context,{bpm:86,key:'A minor',swing:12});
 assert.deepEqual(Object.keys(all),['format','version','context','patterns']);for(const key of ['tracks','token','sound','api','sections','loopRange','patternId'])assert.ok(!text.includes('"'+key+'"'));
 delete p.privateSettings;assert.deepEqual(p,before);assert.ok(new TextEncoder().encode(text).length<PATTERN_FILE_MAX_BYTES);
});
test('Selecting export source follows library order, keeps every note ID and rejects empty/unknown/duplicate selectors',()=>{
 const p=original(),t=p.tracks[0],r=capturePattern(p,t.id,t.clips[0].id,{name:'鼓收藏'}),all=r.project.patterns;
 assert.deepEqual(exportPatternLibrary(r.project,{ids:[all[1].id,all[0].id]}).patterns,all);
 assert.deepEqual(exportPatternLibrary(r.project,{ids:[all[1].id]}).patterns,[all[1]]);
 for(const selected of [[],['missing'],[all[0].id,all[0].id],null,'all'])assert.throws(()=>exportPatternLibrary(r.project,{ids:selected}));
 assert.throws(()=>exportPatternLibrary(generateProject()),/还是空/);
});
test('Whole project extraction validates complete v3 cache but imports only existing source library',()=>{
 const p=original(),decoded=readPatternFile(JSON.stringify(p));assert.equal(decoded.origin,'project');assert.deepEqual(decoded.library,exportPatternLibrary(p));
 const broken=copy(p);broken.tracks[4].notes[0].velocity=1;assert.throws(()=>readPatternFile(JSON.stringify(broken)),/缓存/);
 assert.throws(()=>readPatternFile(JSON.stringify(generateProject())),/没有库/);
});
test('Unknown file formats, versions, nested extra fields and malformed JSON never become partial imports',()=>{
 const invalid=[null,[],{},bundle([]),{...bundle([source()]),format:'other'},{...bundle([source()]),version:2},{...bundle([source()]),endpoint:'test-only'},bundle([{...source(),sound:{attack:1}}]),bundle([{...source(),notes:[{...source().notes[0],apiKey:'test-only'}]}])];
 for(const raw of invalid)assert.throws(()=>readPatternFile(JSON.stringify(raw)));
 assert.throws(()=>readPatternFile('{ "test-only-secret":'),e=>e.message.includes('完整 JSON')&&!e.message.includes('test-only-secret'));
});
test('Phrase validation rejects duplicate IDs, inherited instruments, wrong kind, fractional velocities and bad relative timing',()=>{
 const bad=[{...source(),name:''},{...source(),name:5},{...source(),name:'a\n'},{...source(),name:'x'.repeat(61)},{...source(),id:'bad/id'},{...source(),instrument:'constructor'},{...source(),kind:'drum'},{...source(),length:257},{...source(),notes:[{...source().notes[0],start:-1}]},{...source(),notes:[{...source().notes[0],duration:9}]},{...source(),notes:[{...source().notes[0],velocity:80.2}]},{...source(),notes:[{...source().notes[0],timingOffset:.041}]}];
 for(const p of bad)assert.throws(()=>validatePatternLibrary(bundle([p])));
 assert.throws(()=>validatePatternLibrary(bundle([source(),source()])));
 assert.throws(()=>validatePatternLibrary(bundle([{...source(),notes:[source().notes[0],source().notes[0]]}])));
 assert.throws(()=>validatePatternLibrary(bundle([{...source(),instrument:'kick',kind:'drum'}])));
});
test('Reference tempo/key/swing is optional, strictly validated and never a project edit',()=>{
 const b=bundle([source()]);delete b.context;assert.equal(validatePatternLibrary(b).context,undefined);
 for(const ref of [{bpm:20,key:'C major',swing:0},{bpm:100,key:'constructor',swing:0},{bpm:100,key:'C major',swing:46},{bpm:100,key:'C major',swing:0,model:'test-only'}])assert.throws(()=>validatePatternLibrary({...b,context:ref}));
 const p=original(),next=planPatternImport(p,bundle([source()])).project;assert.deepEqual([next.bpm,next.key,next.swing],[p.bpm,p.key,p.swing]);
});
test('Import only adds sources, regenerates IDs and preserves every original shared cache, sound, label and MIDI byte',()=>{
 const p=original(),before=copy(p),b=bundle([source(p.patterns[0].id,'柔和电钢琴')]),f=ids(),result=planPatternImport(p,b,{idFactory:f});
 assert.deepEqual(p,before);assert.equal(result.stats.added,1);assert.equal(result.stats.renamed,1);assert.equal(result.project.patterns[1].name,'柔和电钢琴 · 导入 2');
 const added=result.project.patterns[1];assert.notEqual(added.id,b.patterns[0].id);assert.notEqual(added.notes[0].id,b.patterns[0].notes[0].id);assert.equal(musical(added),musical(b.patterns[0]));
 const next=copy(result.project);next.patterns=next.patterns.slice(0,1);assert.deepEqual(next,p);assert.deepEqual(encodeMIDI(result.project),encodeMIDI(p));assert.deepEqual(playbackPlan(result.project).events,playbackPlan(p).events);
 assert.equal(patternInstances(result.project,added.id).length,0);assert.equal(patternInstances(result.project,p.patterns[0].id).length,4);assert.deepEqual(unpackProject(packProject(result.project)),result.project);
});
test('Default content dedupe ignores note IDs, source IDs, names and absent/zero timing, but keeps pitch/duration/velocity differences',()=>{
 const p=original(),first=p.patterns[0],same={...copy(first),id:'other',name:'不同名称',notes:first.notes.map((n,i)=>({...n,id:'different_'+i,timingOffset:n.timingOffset||0}))};
 const result=planPatternImport(p,bundle([same]));assert.equal(result.stats.skipped,1);assert.equal(result.stats.added,0);assert.deepEqual(result.project,p);
 for(const mutate of [n=>n.pitch++,n=>n.velocity--,n=>n.duration-=.01]){const q=copy(same);mutate(q.notes[0]);assert.equal(planPatternImport(p,bundle([q])).stats.added,1)}
});
test('Matching content on a different source instrument is a distinct phrase, never silently merged',()=>{
 const p=original(),same={...copy(p.patterns[0]),id:'pad_source',instrument:'pad'};assert.equal(planPatternImport(p,bundle([same])).stats.added,1);
});
test('File-internal duplicates are resolved deterministically in file order, and explicit copies keep both independently',()=>{
 const p=generateProject(),a=source('a','第一句'),b=source('b','第二句'),input=bundle([a,b]);
 const result=planPatternImport(p,input,{ids:['b','a'],idFactory:ids()});assert.equal(result.stats.added,1);assert.equal(result.items[1].duplicateName,'第一句');assert.equal(result.project.patterns[0].name,'第一句');
 const onlyB=planPatternImport(p,input,{ids:['b']});assert.equal(onlyB.project.patterns[0].name,'第二句');
 const both=planPatternImport(p,input,{duplicates:'copies',idFactory:ids()});assert.equal(both.stats.added,2);assert.equal(new Set(both.project.patterns.flatMap(x=>[x.id,...x.notes.map(n=>n.id)])).size,4);assert.deepEqual(input,bundle([a,b]));
});
test('Explicit copies never overwrite or rebind an existing identical source and its four instances',()=>{
 const p=original(),result=planPatternImport(p,exportPatternLibrary(p),{duplicates:'copies'});assert.equal(result.stats.added,1);assert.equal(result.stats.renamed,1);assert.deepEqual(result.project.patterns[0],p.patterns[0]);assert.deepEqual(result.project.tracks,p.tracks);assert.equal(patternInstances(result.project,result.addedIds[0]).length,0);
});
test('Long and repeated names get bounded unique suffixes without losing original names',()=>{
 const p=generateProject(),name='字'.repeat(60),b=bundle([source('a',name),source('b',name),source('c',name)]),r=planPatternImport(p,b,{duplicates:'copies'});
 assert.equal(r.stats.renamed,2);assert.ok(r.project.patterns.every(x=>x.name.length<=60));assert.equal(new Set(r.project.patterns.map(x=>x.name)).size,3);assert.equal(r.project.patterns[0].name,name);assert.match(r.project.patterns[2].name,/导入 3$/);
});
test('Empty phrases are valid explicit sources, import upgrades v2 once and no tracks or sounds are created',()=>{
 const p=generateProject(),empty={...source(),notes:[]},r=planPatternImport(p,bundle([empty]));assert.equal(r.project.version,3);assert.deepEqual(r.project.tracks,p.tracks);assert.equal(r.project.patterns[0].notes.length,0);assert.equal(r.stats.notesAfter,0);assert.deepEqual(encodeMIDI(r.project),encodeMIDI(p));
});
test('Import selection and duplicate policy errors reject instead of silently choosing other phrases',()=>{
 const p=original(),b=bundle([source()]);for(const selected of [[],['missing'],['source','source'],null,'all'])assert.throws(()=>planPatternImport(p,b,{ids:selected}));
 for(const duplicates of ['replace','merge',false,null])assert.throws(()=>planPatternImport(p,b,{duplicates}));
});
test('Generated identifier collisions are retried against all project IDs, and persistent collisions/invalid IDs reject atomically',()=>{
 const p=original(),b=bundle([source()]),existing=p.tracks[0].notes[0].id;let count=0;const r=planPatternImport(p,b,{idFactory:()=>++count<4?existing:'fresh_'+count});assert.equal(r.stats.added,1);assert.equal(count,5);
 const before=copy(p);assert.throws(()=>planPatternImport(p,b,{idFactory:()=>existing}),/碰撞/);assert.throws(()=>planPatternImport(p,b,{idFactory:()=>'/bad'}),/有效/);assert.deepEqual(p,before);
 for(const reserved of [p.sections[0].id,b.patterns[0].id,b.patterns[0].notes[0].id])assert.throws(()=>planPatternImport(p,b,{idFactory:()=>reserved}),/碰撞/);
});
test('64-source capacity is all-or-none, while duplicate skipping can succeed at full capacity',()=>{
 const p=original();p.patterns=normalizePatterns([...p.patterns,...Array.from({length:63},(_,i)=>({...source('existing_'+i,'已有 '+i),notes:[]}))]);const before=copy(p),b=bundle([source('new_a'),source('new_b')]);
 assert.throws(()=>planPatternImport(p,b,{duplicates:'copies'}),/64/);assert.deepEqual(p,before);
 const r=planPatternImport(p,exportPatternLibrary(p));assert.equal(r.stats.added,0);assert.equal(r.stats.skipped,64);assert.deepEqual(r.project,p);
});
function dense(id,count=4000){return{...source(id,id),length:256,notes:Array.from({length:count},(_,i)=>({id:'n_'+i,pitch:60,start:1+(i%250),duration:.1,velocity:80}))}}
test('Per-source and aggregate library-note limits reject whole files and whole imports without touching existing data',()=>{
 assert.throws(()=>validatePatternLibrary(bundle([dense('too_many',4001)])),/数据/);assert.throws(()=>validatePatternLibrary(bundle([dense('a'),dense('b'),dense('c'),dense('d',1)])),/12000/);
 const p=original();p.patterns=normalizePatterns([dense('a'),dense('b'),dense('c')]);for(const t of p.tracks)for(const c of t.clips)delete c.patternId;const before=copy(p);
 assert.throws(()=>planPatternImport(p,bundle([source('new')]),{duplicates:'copies'}),/12000/);assert.deepEqual(p,before);
});
test('File cap uses UTF-8 bytes before parsing, not JS character count, and does not expose raw malformed content',()=>{
 assert.throws(()=>readPatternFile(' '.repeat(PATTERN_FILE_MAX_BYTES+1)),/3 MB/);assert.throws(()=>readPatternFile('字'.repeat(1000001)),/3 MB/);
 assert.throws(()=>readPatternFile('字'.repeat(1000000)),/完整 JSON/);assert.throws(()=>readPatternFile(new Uint8Array([1])),/3 MB/);
});
test('A newly imported source can be deliberately placed as a shared or independent clip only after import',()=>{
 const p=generateProject({bars:16}),t=p.tracks[4];t.clips=[];t.notes=[];const r=planPatternImport(validateProject(p),bundle([source()])),shared=placePattern(r.project,r.addedIds[0],t.id,8),independent=placePattern(r.project,r.addedIds[0],t.id,8,{linked:false});
 assert.equal(patternInstances(r.project,r.addedIds[0]).length,0);assert.equal(patternInstances(shared.project,r.addedIds[0]).length,1);assert.equal(patternInstances(independent.project,r.addedIds[0]).length,0);assert.equal(shared.project.tracks[4].notes[0].start,9);assert.equal(shared.project.tracks[4].notes[0].timingOffset,.02);
 assert.equal(musical({...source(),notes:independent.project.tracks[4].notes.map(n=>({...n,start:n.start-8}))}),musical(source()));
});
test('Imports exceeding the complete project save-byte budget reject, even when individual note counts fit',()=>{
 let p=generateProject({bars:64});p.tracks=[];
 for(let ti=0;ti<3;ti++){const t=makeTrack('keys');t.clips=[{id:'clip_'+ti,name:'dense',start:0,length:256,muted:false}];t.notes=Array.from({length:4000},(_,i)=>({id:`t${ti}_n${i}_`+'x'.repeat(65),pitch:60,start:1+(i%250),duration:.1,velocity:80,timingOffset:0}));p.tracks.push(t)}
 p=validateProject(p);assert.ok(new TextEncoder().encode(JSON.stringify(p)).length<PATTERN_FILE_MAX_BYTES);
 let i=0;assert.throws(()=>planPatternImport(p,bundle([dense('a'),dense('b'),dense('c')]),{duplicates:'copies',idFactory:()=>('fresh_'+(++i)).padEnd(80,'y')}),/保存上限/);
});
test('Pretty export enforces its own byte cap so every downloaded file can be read back',()=>{
 const b=bundle([dense('a'),dense('b'),dense('c')]);for(const p of b.patterns)for(const n of p.notes){n.id=n.id.padEnd(80,'x');n.start=123.1234;n.duration=123.1234;n.velocity=127;n.timingOffset=.0333}
 assert.throws(()=>serializePatternLibrary(b),/减少导出/);
});
