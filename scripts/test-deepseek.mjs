import {assessTestComposition} from './composition-checks.mjs';
import {mkdir,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {composeWithModel} from '../llm.mjs';
import {DEEPSEEK_DEFAULTS,deepSeekProfile} from '../deepseek.mjs';
import {generateProject,makeTrack,validateProject,encodeMIDI} from '../dist/music.js';
import {planSamplerPalette} from '../dist/sampler-edit.js';
import {decodeMIDI} from '../dist/midi.js';
import {ServiceError} from '../dist/service.js';

export function testInput({brief='explicit'}={}){
 let project=generateProject({name:'DeepSeek four-bar composition test',bars:4,bpm:86,key:'A minor',seed:271828});
 project.tracks.push(makeTrack('pad'),makeTrack('pluck'));
 project=validateProject(project);project=planSamplerPalette(project).project;
 const names={kick:'Kick',snare:'Snare',hat:'Hi-hat',bass:'Double bass',keys:'Piano',lead:'Flute',pad:'Cello',pluck:'Harp'};
 for(const t of project.tracks){t.name=names[t.instrument];t.notes=[]}
 const descriptive='Compose a complete four-bar A minor chamber lo-fi phrase at the existing 86 BPM. Piano states a simple Am–F–C–G harmony, pizzicato double bass supports roots, flute repeats a short memorable motif with one answering variation. Use cello and harp sparingly, restrained kick and snare, quiet eighth-note hi-hat. Leave space and finish deliberately. Include notes for all eight roles, no more than 150 notes total.';
 const explicit='Compose an original four-bar chamber lo-fi loop at the existing 86 BPM in A minor. Absolute beats 0–16. Hard musical requirements: bar 1 starts at beat 0, Am chord (pitch classes A C E), bass root A; bar 2 starts beat 4, F chord (F A C), bass root F; bar 3 starts beat 8, C chord (C E G), bass root C; bar 4 starts beat 12, G chord (G B D), bass root G. Piano must sound the specified three-note triad together exactly at each bar start, using inversions if useful. Double bass must play the specified root exactly at each bar start; additional bass notes must belong to that bar chord. Hi-hat must play exactly 32 quiet eighth notes at absolute beats 0,0.5,1,1.5,...,15.5 (not every whole beat); vary velocities subtly. Flute should invent a short motif, repeat it with a small answering variation and leave a breath before beat 16. Cello and harp should be sparse and harmonically aligned to the active bar. Use restrained kick and snare. Include all eight instrument roles, with at least one note each, no more than 150 notes total. Write your summary only after checking that the notes actually match these instructions. Do not claim a final tonic cadence: this ends on G and loops back to Am.';
 return{prompt:brief==='descriptive'?descriptive:explicit,project:validateProject(project),scope:'all'};
}
export async function runLiveTest({env=process.env,outDir,fetcher=fetch,brief='explicit'}={}){
 if(typeof env.LLM_API_KEY!=='string'||!env.LLM_API_KEY.trim())return{status:'blocked',reason:'missing-api-key',calls:0};
 const endpoint=env.LLM_API_URL||DEEPSEEK_DEFAULTS.endpoint,model=env.LLM_MODEL||DEEPSEEK_DEFAULTS.model,maxOutputTokens=env.LLM_MAX_TOKENS===undefined?DEEPSEEK_DEFAULTS.maxOutputTokens:Number(env.LLM_MAX_TOKENS);
 try{if(!deepSeekProfile(endpoint,maxOutputTokens))return{status:'blocked',reason:'not-official-deepseek-endpoint',calls:0}}catch{return{status:'blocked',reason:'invalid-deepseek-configuration',calls:0}};
 const input=testInput({brief});const before=JSON.stringify(input.project);let calls=0;
 try{
  const result=await composeWithModel(input,{endpoint,model,apiKey:env.LLM_API_KEY,maxOutputTokens,fetcher:async(...args)=>{calls++;return fetcher(...args)}});
  const bytes=encodeMIDI(result.project),decoded=decodeMIDI(bytes),notes=result.project.tracks.reduce((n,t)=>n+t.notes.length,0);
  const checks={inputUnchanged:JSON.stringify(input.project)===before,tracks:result.project.tracks.length,notes,midiNotes:decoded.report.importedNotes,sampledTracks:result.project.tracks.filter(t=>t.sampler).length,allRolesHaveNotes:result.project.tracks.every(t=>t.notes.length>0),settingsPreserved:result.project.bars===input.project.bars&&result.project.bpm===input.project.bpm&&result.project.key===input.project.key};
  if(!checks.inputUnchanged||notes!==checks.midiNotes||!checks.settingsPreserved)throw new ServiceError('provider_project');
  const report={status:'passed-structural-checks',testedAt:new Date().toISOString(),calls,brief,receipt:result.receipt,checks,musicalInstructions:assessTestComposition(result.project),summary:result.summary,audio:'Not rendered or listened to by this CLI. Validate WAV playback in the app; structural checks are not a musical-quality verdict.'};
  if(outDir){await mkdir(outDir,{recursive:true});await writeFile(resolve(outDir,'input.sprout'),JSON.stringify(input.project,null,2));await writeFile(resolve(outDir,'composition.sprout'),JSON.stringify(result.project,null,2));await writeFile(resolve(outDir,'composition.mid'),bytes);await writeFile(resolve(outDir,'report.json'),JSON.stringify(report,null,2))}
  return report;
 }catch(e){return{status:'failed',reason:e instanceof ServiceError?e.code:e.name==='TimeoutError'?'timeout':'unexpected-error',calls,inputUnchanged:JSON.stringify(input.project)===before}}
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{process.loadEnvFile(fileURLToPath(new URL('../.env',import.meta.url)))}catch(e){if(e.code!=='ENOENT'){console.error('Unable to load the project .env file. Check its format.');process.exit(1)}}
 const flags=process.argv.slice(2),out=flags.indexOf('--out');
 if(!flags.includes('--live')){console.log('No model called. Run npm run test:deepseek -- --live to authorize one bounded API request.');process.exit(0)}
 const report=await runLiveTest({outDir:out>=0?resolve(flags[out+1]||'examples/deepseek-live'):resolve('examples/deepseek-live')});console.log(JSON.stringify(report,null,2));if(report.status!=='passed-structural-checks')process.exitCode=1;
}
