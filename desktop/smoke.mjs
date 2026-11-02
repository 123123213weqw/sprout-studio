// Actual Electron checks run with a temporary profile, muted output and no model calls.
import {app,protocol,Menu} from 'electron';
import assert from 'node:assert/strict';
import {writeFile,readFile} from 'node:fs/promises';
import {mkdtempSync,mkdirSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {SCHEME} from './runtime.mjs';

const directory=process.env.SPROUT_DESKTOP_QA_DIR?resolve(process.env.SPROUT_DESKTOP_QA_DIR):mkdtempSync(join(tmpdir(),'sprout-desktop-qa-'));
mkdirSync(join(directory,'profile'),{recursive:true});
app.setName('Sprout Desktop QA');app.setPath('userData',join(directory,'profile'));
app.commandLine.appendSwitch('mute-audio');
protocol.registerSchemesAsPrivileged([SCHEME]);
for(const key of ['LLM_API_URL','LLM_MODEL','LLM_API_KEY','LLM_MAX_TOKENS','LLM_JSON_MODE','LLM_LOCK_MODEL','SPROUT_REMOTE_SERVICE_URL'])delete process.env[key];
let desktop;const checks=[],errors=[];
console.log('Desktop QA main module initialized');
const record=(name,detail)=>{checks.push({name,detail});console.log('PASS '+name)};
async function run(){try{
 const {launchDesktop}=await import('./application.mjs');desktop=await launchDesktop({visible:false,onProgress:stage=>console.log('STAGE '+stage)});
 const contents=desktop.window.webContents;contents.setAudioMuted(true);
 contents.on('console-message',details=>{if(details.level==='error')errors.push(details.message)});
 contents.on('render-process-gone',(_event,details)=>errors.push('Renderer exited: '+details.reason));
 for(let n=0;n<60;n++){if(await contents.executeJavaScript(`Boolean(document.querySelector('#arrangement')?.children.length&&document.querySelector('#project-name')?.value)`))break;if(n===59)throw Error('Studio did not initialize');await new Promise(r=>setTimeout(r,100))}
 const identity=await contents.executeJavaScript(`({url:location.href,origin:location.origin,node:typeof require,process:typeof process,name:document.querySelector('#project-name').value})`);
 assert.equal(new URL(identity.url).protocol,'sprout:');assert.equal(identity.node,'undefined');assert.equal(identity.process,'undefined');record('Actual studio loads in a sandboxed desktop renderer',identity);
 const health=await contents.executeJavaScript(`fetch('/api/health').then(r=>r.json())`);assert.equal(health.ok,true);assert.equal(health.llmConfigured,false);record('Bundled backend is available without model configuration',health);
 const sound=await contents.executeJavaScript(`(async()=>{const {SAMPLE_ASSETS}=await import('./sample-assets.js');const {SAMPLE_PRESETS}=await import('./sampler-core.js');const asset=SAMPLE_ASSETS[0],bytes=await(await fetch('samples/'+asset.file)).arrayBuffer();const sha=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),b=>b.toString(16).padStart(2,'0')).join('');return{presets:Object.keys(SAMPLE_PRESETS).length,assets:SAMPLE_ASSETS.length,checksumMatches:sha===asset.sha256}})()`);
 assert.equal(sound.presets,179);assert.equal(sound.assets,2259);assert.equal(sound.checksumMatches,true);record('Recorded sound library loads through the desktop protocol',sound);
 await contents.executeJavaScript(`localStorage.setItem('sprout-desktop-qa','retained');document.querySelector('#project-name').value='Desktop QA song';document.querySelector('#project-name').dispatchEvent(new Event('change',{bubbles:true}));document.querySelector('#project-name').blur()`);
 await new Promise(r=>setTimeout(r,250));
 const editMenu=Menu.getApplicationMenu().items.find(item=>item.label==='编辑').submenu;
 editMenu.items[0].click();await new Promise(r=>setTimeout(r,100));
 assert.notEqual(await contents.executeJavaScript(`document.querySelector('#project-name').value`),'Desktop QA song');
 editMenu.items[1].click();await new Promise(r=>setTimeout(r,100));
 assert.equal(await contents.executeJavaScript(`document.querySelector('#project-name').value`),'Desktop QA song');record('Native menu undo and redo preserve project editing',true);
 await new Promise(r=>setTimeout(r,200));await new Promise(resolve=>{contents.once('did-finish-load',resolve);contents.reload()});
 for(let n=0;n<60;n++){if(await contents.executeJavaScript(`document.querySelector('#project-name')?.value==='Desktop QA song'`))break;if(n===59)throw Error('Project did not survive reload');await new Promise(r=>setTimeout(r,100))}
 assert.equal(await contents.executeJavaScript(`localStorage.getItem('sprout-desktop-qa')`),'retained');record('Project and local settings survive a renderer reload',true);
 const midi=await contents.executeJavaScript(`(async()=>{const {decodeMIDI}=await import('./midi.js');const {encodeMIDI,makeTrack,validateProject}=await import('./music.js');const t=makeTrack('keys');t.notes=[{id:'qa-note',pitch:60,start:0,duration:1,velocity:96}];t.clips=[{id:'qa-clip',start:0,length:32,name:'QA',muted:false}];const p=validateProject({version:2,id:'qa-project',name:'Desktop MIDI',style:'lofi',key:'C major',bars:8,bpm:120,swing:0,master:.7,seed:1,tracks:[t]});const bytes=encodeMIDI(p);const transfer=new DataTransfer();transfer.items.add(new File([bytes],'desktop-qa.mid',{type:'audio/midi'}));const input=document.querySelector('#import-midi-file');input.files=transfer.files;input.dispatchEvent(new Event('change',{bubbles:true}));return{bytes:bytes.byteLength,notes:decodeMIDI(bytes).report.importedNotes}})()`);
 for(let n=0;n<60;n++){if(await contents.executeJavaScript(`Boolean(document.querySelector('#confirm-midi-import'))`))break;await new Promise(r=>setTimeout(r,50))}
 assert.equal(midi.notes,1);assert.equal(await contents.executeJavaScript(`document.querySelector('#modal').open&&Boolean(document.querySelector('#confirm-midi-import'))`),true);
 await contents.executeJavaScript(`document.querySelector('#confirm-midi-import').click()`);
 for(let n=0;n<60;n++){if(await contents.executeJavaScript(`document.querySelector('#project-name').value==='desktop-qa'`))break;if(n===59)throw Error('MIDI UI import did not complete');await new Promise(r=>setTimeout(r,100))}
 record('Actual MIDI file input, preview and explicit import work',midi);
 await contents.executeJavaScript(`document.querySelector('#piano-canvas').focus()`);
 editMenu.items[6].click();await new Promise(r=>setTimeout(r,100));
 assert.match(await contents.executeJavaScript(`document.querySelector('#note-selection-count').textContent`),/1/);
 editMenu.items[4].click();await new Promise(r=>setTimeout(r,100));editMenu.items[5].click();await new Promise(r=>setTimeout(r,100));
 assert.equal(await contents.executeJavaScript(`document.querySelector('#modal').open&&document.querySelector('#modal').textContent.includes('粘贴')`),true);
 await contents.executeJavaScript(`document.querySelector('#modal').close()`);record('Native select/copy/paste shortcuts route to piano notes, not browser text',true);
 const exported=new Promise((resolve,reject)=>{
  const timer=setTimeout(()=>reject(Error('Export timed out')),10000);
  contents.session.once('will-download',(_event,item)=>{item.setSavePath(join(directory,'export.sprout'));item.once('done',(_event,state)=>{clearTimeout(timer);state==='completed'?resolve():reject(Error('Export '+state))})});
 });
 await contents.executeJavaScript(`document.querySelector('#export-btn').click();document.querySelector('#export-project').click()`);
 await exported;const project=JSON.parse(await readFile(join(directory,'export.sprout'),'utf8'));assert.equal(project.tracks[0].notes.length,1);record('Native download produces a valid project file',{name:project.name,notes:project.tracks[0].notes.length});
 await contents.executeJavaScript(`document.querySelector('#modal').close()`);
 const audio=await contents.executeJavaScript(`(async()=>{const {renderWAV}=await import('./audio.js');const {makeTrack,validateProject}=await import('./music.js');const t=makeTrack('keys');t.sampler={preset:'vsco-piano-full',gain:.8,release:.2,cutoff:18000};t.notes=[{id:'qa-audio-note',pitch:60,start:0,duration:1,velocity:100}];t.clips=[{id:'qa-audio-clip',name:'QA',start:0,length:32,muted:false}];const p=validateProject({version:2,id:'qa-audio',name:'QA',style:'lofi',key:'C major',bars:8,bpm:120,swing:0,master:.7,seed:1,tracks:[t]});const bytes=await renderWAV(p,{range:{start:0,end:4}});const view=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);let peak=0;for(let i=44;i<view.byteLength;i+=2)peak=Math.max(peak,Math.abs(view.getInt16(i,true)/32768));return{bytes:view.byteLength,peak}})()`);
 assert.ok(audio.bytes>44);assert.ok(audio.peak>0&&audio.peak<1);record('Actual Chromium offline audio renders sampled piano without clipping',audio);
 assert.deepEqual(errors,[]);record('No captured renderer console errors or process failures',true);
 const backend=desktop.backend.base;await desktop.backend.close();await assert.rejects(fetch(backend+'/api/health'));record('Quitting can close the owned backend cleanly',true);
 await writeFile(join(directory,'results.json'),JSON.stringify({passed:checks.length,checks,errors,privateBackend:desktop.backend.base},null,2)+'\n');console.log('Desktop QA directory: '+directory);await desktop.shutdown();app.exit(0);
}catch(error){
 console.error(error.stack);await writeFile(join(directory,'results.json'),JSON.stringify({passed:checks.length,checks,errors,failure:error.message},null,2)+'\n');await desktop?.shutdown();app.exit(1);
}}
void run();
