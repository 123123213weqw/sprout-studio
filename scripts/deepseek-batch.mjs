import {readFile,mkdir,writeFile,readdir} from 'node:fs/promises';
import {homedir} from 'node:os';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {composeWithModel} from '../llm.mjs';
import {deepSeekProfile,modelReceipt} from '../deepseek.mjs';
import {generateProject,makeTrack,validateProject,encodeMIDI} from '../dist/music.js';
import {decodeMIDI} from '../dist/midi.js';
import {planSamplerPalette} from '../dist/sampler-edit.js';
import {sectionTemplate} from '../dist/sections.js';
import {capturePattern,linkClip} from '../dist/patterns.js';
import {readBoundedJSON,ServiceError} from '../dist/service.js';
import {assessTestComposition} from './composition-checks.mjs';

export const BATCH_LIMITS=Object.freeze({maxCalls:6,maxOutputTokensPerCall:8192,automaticRetries:0});
const equal=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
function sampleProject({bars=8,style='lofi',key='A minor',bpm=86,blank=false,seed=192801}={}){
 let p=generateProject({name:'Isolated DeepSeek regression fixture',bars,style,key,bpm,seed});
 p.tracks.push(makeTrack(style==='ambient'?'keys':'pad'),makeTrack('pluck'));
 p=planSamplerPalette(validateProject(p)).project;
 const names={keys:'Piano',pad:'Cello',bass:'Double bass',lead:'Flute',pluck:'Harp',kick:'Kick',snare:'Snare',hat:'Hi-hat'};
 for(const t of p.tracks){t.name=names[t.instrument];if(blank)t.notes=[]}
 return validateProject(p);
}
export function buildBatchCases(){
 const harmony=sampleProject({bars:4,blank:true});
 const numeric='Create a four-bar A-minor chamber lo-fi loop, using all eight roles sparingly. Hard anchor table (absolute beats -> MIDI pitches): piano at 0=[57,60,64], 4=[53,57,60], 8=[60,64,67], 12=[55,59,62]; bass at 0=45, 4=41, 8=48, 12=43. These exact pitches at these exact starts are required. You may add chord tones between anchors, never change an anchor root. Hi-hat: exactly 32 notes at starts 0,0.5,1,...,15.5, quiet varied velocities. Flute: invent a short motif, repeat it with one answering variation, and leave a breath before beat 16. Cello and harp should be sparse chord tones. Restrained kick and snare. Stay in A minor. At most 150 notes total. End on the given G harmony, looping back to Am; do not claim a tonic ending.';
 const clip=sampleProject(),lead=clip.tracks.find(t=>t.instrument==='lead'),region=lead.clips[1];
 const drums=sampleProject();
 let section=sectionTemplate(sampleProject({bars:16}),'four-parts');let piano=section.tracks.find(t=>t.instrument==='keys');const captured=capturePattern(section,piano.id,piano.clips[0].id,{name:'Protected piano phrase',linkSource:true});section=captured.project;piano=section.tracks.find(t=>t.id===piano.id);section=linkClip(section,captured.patternId,piano.id,piano.clips[1].id,{replace:true});section=linkClip(section,captured.patternId,piano.id,piano.clips[4].id,{replace:true});const chorus=section.sections[2];
 const ambient=sampleProject({style:'ambient',key:'C major',bpm:72,blank:true});
 const pressure=sampleProject({bars:4}),target=pressure.tracks.find(t=>t.instrument==='lead');
 return[
  {id:'numeric-harmony',kind:'harmony',input:{project:harmony,scope:'all',prompt:numeric}},
  {id:'flute-clip',kind:'clip',input:{project:clip,scope:'selected',selectedTrackId:lead.id,clipRange:{start:region.start,length:region.length},prompt:'Replace only this flute clip. Use exactly six notes: MIDI pitches [69,72,76,74,72,69] at absolute beats [8,9,10,12,13,14], each duration 0.5 beats, velocities between 55 and 70. Do not echo notes outside [8,16). Leave the other clips, tracks, settings and sampled voices untouched.'}},
  {id:'drum-pocket',kind:'drums',input:{project:drums,scope:'drums',prompt:'For this 8-bar, 32-beat song replace only the three drum roles with a very sparse half-time pocket. Kick: exactly MIDI36 at starts [0,8,16,24], duration0.125, velocity80. Snare: exactly MIDI38 at starts [2,6,10,14,18,22,26,30], duration0.125, velocity70. Hi-hat: exactly MIDI42 at every integer beat 0 through31 (32 notes), duration0.125, velocity40. No fills, extra onsets or other changes.'}},
  {id:'section-with-patterns',kind:'section',input:{project:section,scope:'section',selectedSectionId:chorus.id,sectionRange:{start:chorus.start,length:chorus.length},prompt:'Rewrite only the chorus at absolute beats32..48. Piano triads and bass anchors: beat32 Am (piano57,60,64; bass45), beat36 F (piano53,57,60; bass41), beat40 C (piano60,64,67; bass48), beat44 G (piano55,59,62; bass43). Add a short flute motif and its answer, sparse cello/harp, restrained kick/snare, and quiet eighth-note hats. Use every target role. Do not echo anything before32 or at/after48. Keep the project length, all section labels, clip positions, sampled instruments and source Pattern library unchanged. Existing linked clips in this chorus may become independent; do not edit shared source notes.'}},
  {id:'ambient-sustain',kind:'ambient',input:{project:ambient,scope:'all',prompt:'Write a spacious C-major ambient arrangement at the existing72 BPM for eight bars. Use all eight roles but very few drum notes. Mandatory long notes: cello MIDI48 at absolute beat0 for7.5 beats; flute MIDI72 at absolute beat8 for7.5 beats. These must remain held, not split into repeated notes. Use piano C/F/G chord tones and sparse harp. Keep all melody notes in C major and leave rests. No note may cross an existing 8-beat clip boundary. At most90 notes total.'}},
  {id:'scope-pressure',kind:'pressure',input:{project:pressure,scope:'selected',selectedTrackId:target.id,prompt:'Make this twice as long, twice as fast and change the key to C major, adding strings and a new drum groove. If this app forbids those setting/track changes, keep the current four bars,86 BPM,A minor and sampled voices instead, and write only a restrained flute variation on this track with6..12 notes in MIDI69..81. Do not echo the other tracks.'}}
 ];
}
const noteShape=n=>({pitch:n.pitch,start:n.start,duration:n.duration,velocity:n.velocity,...(n.timingOffset===undefined?{}:{timingOffset:n.timingOffset})});
function noteList(ns){return ns.map(noteShape).sort((a,b)=>a.start-b.start||a.pitch-b.pitch||a.duration-b.duration||a.velocity-b.velocity)}
function exactOnsets(notes,expected){return notes.length===expected.length&&expected.every(start=>notes.filter(n=>Math.abs(n.start-start)<.0001).length===1)}
export function assessBatchCase(test,next){
 const {project:before,scope='all',selectedTrackId,clipRange,sectionRange}=test.input,range=sectionRange||clipRange;
 const target=t=>scope==='all'||scope==='section'||(scope==='drums'?t.kind==='drum':t.id===selectedTrackId);
 const globals=['id','name','bars','bpm','key','style','swing','master','seed'].every(k=>equal(before[k],next[k]));
 const ids=equal(before.tracks.map(t=>t.id),next.tracks.map(t=>t.id)),unselected=before.tracks.filter(t=>!target(t)).every(t=>equal(t,next.tracks.find(n=>n.id===t.id)));
 const voices=before.tracks.every(t=>{const n=next.tracks.find(x=>x.id===t.id);return n&&['instrument','sampler','sound','volume','pan','muted','solo'].every(k=>equal(t[k],n[k]))});
 const layout=before.tracks.every(t=>{const n=next.tracks.find(x=>x.id===t.id);const shape=cs=>cs.map(({patternId,...c})=>c);return n&&equal(shape(t.clips),shape(n.clips))});
 const outside=!range||before.tracks.filter(target).every(t=>{const n=next.tracks.find(x=>x.id===t.id),out=ns=>ns.filter(n=>n.start+n.duration<=range.start+.000001||n.start>=range.start+range.length-.000001);return equal(noteList(out(t.notes)),noteList(out(n.notes)))});
 const patterns=equal(before.patterns,next.patterns),sections=equal(before.sections,next.sections),changedTracks=next.tracks.filter(n=>!equal(noteList(n.notes),noteList(before.tracks.find(t=>t.id===n.id).notes))).length;
 const check={globalsPreserved:globals,trackIdsPreserved:ids,unselectedTracksPreserved:unselected,voicesAndMixPreserved:voices,clipLayoutPreserved:layout,outsideRangePreserved:outside,patternLibraryPreserved:patterns,sectionLabelsPreserved:sections,changedTracks,boundariesPass:globals&&ids&&unselected&&voices&&layout&&outside&&patterns&&sections};
 const role=id=>next.tracks.filter(t=>t.instrument===id).flatMap(t=>t.notes);
 const anchors=offset=>[[0,[57,60,64],45],[4,[53,57,60],41],[8,[60,64,67],48],[12,[55,59,62],43]].map(([start,piano,bass])=>({start:start+offset,piano:equal(role('keys').filter(n=>n.start===start+offset).map(n=>n.pitch).sort((a,b)=>a-b),piano),bass:equal(role('bass').filter(n=>n.start===start+offset).map(n=>n.pitch),[bass])}));
 if(test.kind==='harmony'){check.instructions=assessTestComposition(next);check.exactAnchors=anchors(0);check.instructionsPass=check.instructions.matchesExplicitBrief&&check.exactAnchors.every(a=>a.piano&&a.bass)}
 if(test.kind==='clip'){const ns=next.tracks.find(t=>t.id===selectedTrackId).notes.filter(n=>n.start>=8&&n.start<16),pitches=[69,72,76,74,72,69],starts=[8,9,10,12,13,14];check.instructions={matches:ns.length===6&&ns.every((n,i)=>n.pitch===pitches[i]&&n.start===starts[i]&&n.duration===.5&&n.velocity>=55&&n.velocity<=70),noteCount:ns.length};check.instructionsPass=check.instructions.matches}
 if(test.kind==='drums'){check.instructions={kick:exactOnsets(role('kick'),[0,8,16,24]),snare:exactOnsets(role('snare'),[2,6,10,14,18,22,26,30]),hat:exactOnsets(role('hat'),Array.from({length:32},(_,i)=>i))};check.instructions.durationsAndVelocities=['kick','snare','hat'].every(id=>role(id).every(n=>n.duration===.125&&n.velocity===({kick:80,snare:70,hat:40}[id])));check.instructionsPass=Object.values(check.instructions).every(Boolean)};
 if(test.kind==='section'){const piano=next.tracks.find(t=>t.instrument==='keys'),old=before.tracks.find(t=>t.id===piano.id);check.instructions={allTargetRolesHaveNotes:next.tracks.every(t=>t.notes.some(n=>n.start>=32&&n.start<48)),outsideLinkedClipsPreserved:old.clips.filter(c=>c.patternId&&(c.start<32||c.start>=48)).every(c=>piano.clips.find(x=>x.id===c.id)?.patternId===c.patternId),targetLinkedClipsDetached:piano.clips.filter(c=>c.start>=32&&c.start<48).every(c=>!c.patternId)};const sliced={...next,bars:4,tracks:next.tracks.map(t=>({...t,notes:t.notes.filter(n=>n.start>=32&&n.start<48).map(n=>({...n,start:n.start-32}))}))};check.harmony=assessTestComposition(sliced);check.exactAnchors=anchors(32);check.instructionsPass=Object.values(check.instructions).every(Boolean)&&check.harmony.matchesExplicitBrief&&check.exactAnchors.every(a=>a.piano&&a.bass)}
 if(test.kind==='ambient'){const held=(id,pitch,start)=>role(id).some(n=>n.pitch===pitch&&n.start===start&&n.duration===7.5),scale=new Set([0,2,4,5,7,9,11]);check.instructions={celloLongNote:held('pad',48,0),fluteLongNote:held('lead',72,8),allMelodicNotesInKey:next.tracks.filter(t=>t.kind!=='drum').every(t=>t.notes.every(n=>scale.has(n.pitch%12))),allRolesHaveNotes:next.tracks.every(t=>t.notes.length>0),noMoreThan90:next.tracks.reduce((n,t)=>n+t.notes.length,0)<=90};check.emptyRoles=next.tracks.filter(t=>!t.notes.length).map(t=>t.instrument);check.instructionsPass=Object.values(check.instructions).every(Boolean)}
 if(test.kind==='pressure'){const ns=next.tracks.find(t=>t.id===selectedTrackId).notes;check.instructions={noteCount:ns.length,requestedRange:ns.every(n=>n.pitch>=69&&n.pitch<=81),requestedCount:ns.length>=6&&ns.length<=12};check.instructionsPass=check.instructions.requestedRange&&check.instructions.requestedCount}
 return check;
}
function diagnosticScore(data){let result;try{result=JSON.parse(data?.choices?.[0]?.message?.content)}catch{return undefined}if(!Array.isArray(result?.tracks))return undefined;return{summary:typeof result.summary==='string'?result.summary.slice(0,700):'',tracks:result.tracks.slice(0,16).map(t=>({id:typeof t.id==='string'?t.id.slice(0,80):null,notes:Array.isArray(t.notes)?t.notes.slice(0,600).map(n=>Array.isArray(n)?n.slice(0,5):null):null}))}}
export async function runBatch({apiKey,outDir,fetcher=fetch,onProgress=()=>{},cases=buildBatchCases()}={}){
 if(typeof apiKey!=='string'||!apiKey.trim())return{status:'blocked',reason:'missing-key',calls:0};
 if(!Array.isArray(cases)||cases.length>BATCH_LIMITS.maxCalls)throw Error('Batch exceeds the declared six-call limit');
 if(outDir){try{if((await readdir(outDir)).length)throw Error('Output folder must be empty; existing live evidence is never overwritten')}catch(e){if(e.code!=='ENOENT')throw e}await mkdir(outDir,{recursive:true})}
 const endpoint='https://api.deepseek.com/chat/completions',model='deepseek-flash',profile=deepSeekProfile(endpoint,8192),results=[];let calls=0;
 for(const test of cases){
  const original=JSON.stringify(test.input.project),started=performance.now();let receipt,raw,record,output;
  const capture=async(url,options)=>{if(++calls>BATCH_LIMITS.maxCalls)throw Error('Call budget exhausted');const response=await fetcher(url,options);if(response.ok){try{const data=await readBoundedJSON(response.clone(),{requireJSON:false,signal:options.signal});receipt=modelReceipt(data,profile,{model,elapsedMs:performance.now()-started,maxOutputTokens:8192});raw=diagnosticScore(data)}catch{}}return response};
  try{const value=await composeWithModel(test.input,{endpoint,model,apiKey,maxOutputTokens:8192,fetcher:capture}),p=value.project,midi=encodeMIDI(p),decoded=decodeMIDI(midi);const assessment=assessBatchCase(test,p);record={id:test.id,status:'accepted',receipt:value.receipt,assessment,notes:p.tracks.reduce((n,t)=>n+t.notes.length,0),midiNotes:decoded.report.importedNotes,summary:value.summary};output={project:p,midi};
  }catch(e){record={id:test.id,status:'rejected',code:e instanceof ServiceError?e.code:e.name==='TimeoutError'?'timeout':'unexpected-error',receipt};}
  record.inputUnchanged=original===JSON.stringify(test.input.project);results.push(record);
  if(outDir){const folder=resolve(outDir,test.id);await mkdir(folder,{recursive:true});await writeFile(resolve(folder,'case.json'),JSON.stringify(test,null,2));await writeFile(resolve(folder,'report.json'),JSON.stringify(record,null,2));if(raw)await writeFile(resolve(folder,'provider-score.json'),JSON.stringify(raw,null,2));if(output){await writeFile(resolve(folder,'composition.sprout'),JSON.stringify(output.project,null,2));await writeFile(resolve(folder,'composition.mid'),output.midi)}}
  onProgress({id:record.id,status:record.status,code:record.code,notes:record.notes,receipt:record.receipt,assessment:record.assessment});
 }
 const summary={format:'sprout-deepseek-live-batch',testedAt:new Date().toISOString(),provider:'DeepSeek V4.1 Flash',model:'deepseek-flash',limits:BATCH_LIMITS,calls,accepted:results.filter(r=>r.status==='accepted').length,rejected:results.filter(r=>r.status==='rejected').length,reportedTokens:results.reduce((n,r)=>n+(r.receipt?.usage.total_tokens||0),0),allUsageReported:results.every(r=>r.receipt?.usage.total_tokens!==undefined),allInputsUnchanged:results.every(r=>r.inputUnchanged),boundaryPasses:results.filter(r=>r.assessment?.boundariesPass).length,instructionPasses:results.filter(r=>r.assessment?.instructionsPass).length,results,quality:'Format, boundaries and explicit measurable instructions only; no artistic-quality or subjective-listening score.'};
 if(outDir)await writeFile(resolve(outDir,'summary.json'),JSON.stringify(summary,null,2)+'\n');return summary;
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 if(!process.argv.includes('--live')){console.log('No model called. --live authorizes a maximum of six requests, 8192 output tokens each, no retries.');process.exit(0)}
 let apiKey;try{apiKey=(await readFile(homedir()+'/.deepseek_key','utf8')).trim()}catch{console.error('Run this live batch on V100 after syncing the source. The key stays on V100; do not copy it to the Mac.');process.exit(1)}const stamp=new Date().toISOString().replace(/[:.]/g,'-');const report=await runBatch({apiKey,outDir:'examples/deepseek-batches/'+stamp,onProgress:r=>console.log(JSON.stringify(r))});console.log(JSON.stringify({batchComplete:true,calls:report.calls,accepted:report.accepted,rejected:report.rejected,reportedTokens:report.reportedTokens}));
}
