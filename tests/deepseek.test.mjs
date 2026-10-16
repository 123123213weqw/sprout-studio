import test from 'node:test';
import assert from 'node:assert/strict';
import {once} from 'node:events';
import {composeWithModel} from '../llm.mjs';
import {DEEPSEEK_DEFAULTS,deepSeekProfile,deepSeekMessages,expandDeepSeekScore,scoreTargets,modelReceipt} from '../deepseek.mjs';
import {generateProject,copy,encodeMIDI} from '../dist/music.js';
import {normalizeCandidate} from '../dist/candidates.js';
import {normalizeModelReceipt,receiptLabel} from '../dist/model-receipt.js';
import {sectionTemplate} from '../dist/sections.js';
import {serviceStatus} from '../llm-config.mjs';
import {createAppServer} from '../server.mjs';
import {decodeMIDI} from '../dist/midi.js';
import {runLiveTest,testInput} from '../scripts/test-deepseek.mjs';

const config={...DEEPSEEK_DEFAULTS,apiKey:'SYNTHETIC-KEY-NOT-REAL'};
const input=()=>({prompt:'A restrained four-bar melody',project:generateProject({bars:4}),scope:'all'});
function score(i){return{summary:'A test-only score, not a real model result.',tracks:scoreTargets(i).map(t=>({id:t.id,notes:t.windows.length?[[({kick:36,snare:38,hat:42}[t.instrument]||60),t.windows[0].start,.25,64]]:[]}))}}
const response=(s,extra={})=>new Response(JSON.stringify({id:'mock-request-only',model:'deepseek-flash',usage:{prompt_tokens:123,completion_tokens:100,total_tokens:223},choices:[{finish_reason:'stop',message:{content:JSON.stringify(s)}}],...extra}));
const run=(i,s,opts={})=>composeWithModel(i,{...config,fetcher:async()=>response(s),...opts});
const notes=p=>p.tracks.map(t=>t.notes.map(({id,...n})=>n));

test('DeepSeek profile only applies to the official HTTPS completion routes and bounds tokens',()=>{
 for(const p of ['/chat/completions','/v1/chat/completions'])assert.equal(deepSeekProfile('https://api.deepseek.com'+p).format,'sprout-score-v1');
 for(const url of ['http://api.deepseek.com/chat/completions','https://api.deepseek.com/','https://api.deepseek.com/chat/completions?x=1','https://api.deepseek.com:123/chat/completions'])assert.throws(()=>deepSeekProfile(url),e=>e.code==='configuration');
 for(const n of [NaN,0,1023,32769,2.5])assert.throws(()=>deepSeekProfile(config.endpoint,n));
 assert.equal(deepSeekProfile('https://api.deepseek.com.attacker.example/chat/completions'),null);
});
test('Official DeepSeek requests use bounded tokens, disabled thinking and JSON even if generic JSON mode is off',async()=>{
 const i=input();let sent,url;const out=await run(i,score(i),{jsonMode:false,maxOutputTokens:4096,fetcher:async(u,o)=>{url=u;sent=JSON.parse(o.body);assert.equal(o.headers.Authorization,'Bearer '+config.apiKey);assert.equal(o.redirect,'error');return response(score(i))}});
 assert.equal(url,config.endpoint);assert.equal(sent.max_tokens,4096);assert.deepEqual(sent.thinking,{type:'disabled'});assert.deepEqual(sent.response_format,{type:'json_object'});assert.ok(sent.messages[0].content.includes('JSON'));const context=JSON.parse(sent.messages[1].content);assert.ok(context.noteBudget<=Math.floor(4096/24));assert.equal(out.receipt.provider,'deepseek');assert.equal(out.receipt.usage.total_tokens,223);assert.ok(!JSON.stringify(out).includes(config.apiKey));
});
test('Compact context contains explicit target windows and numeric note tuples, not audio or credentials',()=>{
 const i=input();i.scope='selected';i.selectedTrackId=i.project.tracks[4].id;i.clipRange={start:8,length:8};const payload=deepSeekMessages(i,{maxOutputTokens:16384});const ctx=JSON.parse(payload.messages[1].content);
 assert.deepEqual(ctx.targets.map(t=>t.id),[i.selectedTrackId]);assert.ok(ctx.targets[0].windows.every(w=>w.start>=8&&w.end<=16));assert.ok(ctx.project.tracks[0].notes[0].every(Number.isFinite));assert.equal(ctx.project.tracks[0].sampler,undefined);assert.ok(!JSON.stringify(payload).includes(config.apiKey));
});
test('DeepSeek all-track score preserves globals, sampled instruments, mix and immutable input',async()=>{
 const i=testInput(),before=JSON.stringify(i.project),out=await run(i,score(i));assert.equal(JSON.stringify(i.project),before);for(const key of ['bars','bpm','key','style','swing','master'])assert.deepEqual(out.project[key],i.project[key]);
 for(const t of out.project.tracks){const old=i.project.tracks.find(x=>x.id===t.id);for(const key of ['id','instrument','sampler','volume','pan','muted','solo','clips'])assert.deepEqual(t[key],old[key]);assert.equal(t.notes.length,1)}
 assert.equal(decodeMIDI(encodeMIDI(out.project)).report.importedNotes,8);
});
test('Selected-track DeepSeek score cannot alter unrelated tracks or duplicate-instrument track identity',async()=>{
 const i=input();const twin=copy(i.project.tracks[4]);twin.id='twin-piano';i.project.tracks.push(twin);i.scope='selected';i.selectedTrackId=twin.id;const out=await run(i,score(i));
 for(const t of out.project.tracks)if(t.id!==twin.id)assert.deepEqual(t,i.project.tracks.find(x=>x.id===t.id));assert.equal(out.project.tracks.at(-1).notes.length,1);
});
test('Clip-only DeepSeek output preserves both adjacent clips and their notes',async()=>{
 const i=input(),t=i.project.tracks[4];i.scope='selected';i.selectedTrackId=t.id;i.clipRange={start:8,length:8};const out=await run(i,score(i));
 const strip=ns=>ns.map(({id,...n})=>n);assert.deepEqual(strip(out.project.tracks[4].notes.filter(n=>n.start<8)),strip(t.notes.filter(n=>n.start<8)));assert.deepEqual(out.project.tracks[4].clips,t.clips);
});
test('Section-only DeepSeek output preserves labels, globals and notes outside the section',async()=>{
 const i=input();i.project=sectionTemplate(i.project);const s=i.project.sections[1];i.scope='section';i.selectedSectionId=s.id;i.sectionRange={start:s.start,length:s.length};const out=await run(i,score(i));
 assert.deepEqual(out.project.sections,i.project.sections);for(let j=0;j<out.project.tracks.length;j++)assert.deepEqual(out.project.tracks[j].notes.filter(n=>n.start<s.start&&n.start+n.duration<=s.start),i.project.tracks[j].notes.filter(n=>n.start<s.start&&n.start+n.duration<=s.start));
});
test('Drums-only DeepSeek score preserves all melodic notes and only accepts role-specific pitches',async()=>{
 const i=input();i.scope='drums';const out=await run(i,score(i));for(let j=3;j<i.project.tracks.length;j++)assert.deepEqual(out.project.tracks[j],i.project.tracks[j]);const bad=score(i);bad.tracks[0].notes[0][0]=38;await assert.rejects(run(i,bad),e=>e.code==='provider_project');
});
test('Compact score rejects missing, duplicate and invented track IDs without instrument fallback',async()=>{
 const i=input(),s=score(i);for(const change of [x=>x.tracks.pop(),x=>x.tracks[1].id=x.tracks[0].id,x=>x.tracks[0].id='invented',x=>delete x.tracks]){const bad=copy(s);change(bad);await assert.rejects(run(i,bad),e=>e.code==='provider_project')}
});
test('Compact score rejects malformed, out-of-window, duplicate, fractional or excessive notes',()=>{
 const i=input(),s=score(i);for(const tuple of [[36,-1,.25,64],[36,16,.25,64],[36,15.9,.5,64],[36,0,.001,64],[36,0,.25,128],[36,0,.25,2.5],[36.1,0,.25,64],[36,0,.25],[36,0,.25,64,1],['36',0,.25,64]]){const bad=copy(s);bad.tracks[0].notes=[tuple];assert.throws(()=>expandDeepSeekScore(bad,i,160),e=>e.code==='provider_project')}
 const dup=copy(s);dup.tracks[0].notes.push(dup.tracks[0].notes[0]);assert.throws(()=>expandDeepSeekScore(dup,i,160));assert.throws(()=>expandDeepSeekScore(s,i,1));
});
test('Empty and truncated DeepSeek results fail without fallback generation or automatic retries',async()=>{
 const i=input(),s=score(i);s.tracks.forEach(t=>t.notes=[]);await assert.rejects(run(i,s),e=>e.code==='provider_empty');
 for(const [data,code] of [[{choices:[{finish_reason:'length',message:{content:'{}'}}]},'provider_truncated'],[{choices:[{message:{content:''}}]},'provider_empty']]){let calls=0;await assert.rejects(run(i,{}, {fetcher:async()=>{calls++;return new Response(JSON.stringify(data))}}),e=>e.code===code);assert.equal(calls,1)}
});
test('A note budget counts only replacements, not thousands of preserved input notes',async()=>{
 const i=input();i.project.tracks[0].notes=Array.from({length:3000},(_,j)=>({id:'kick-'+j,pitch:36,start:(j%64)*.25,duration:.125,velocity:64}));i.project.tracks[1].notes=Array.from({length:3000},(_,j)=>({id:'snare-'+j,pitch:38,start:(j%64)*.25,duration:.125,velocity:64}));i.scope='selected';i.selectedTrackId=i.project.tracks[4].id;
 const out=await run(i,score(i));assert.equal(out.project.tracks[0].notes.length,3000);assert.equal(out.project.tracks[1].notes.length,3000);
});
test('Receipt normalization is bounded, strips unknown fields and never claims artistic quality',()=>{
 const receipt=modelReceipt({id:'req-1',model:'deepseek-flash',usage:{total_tokens:200,prompt_tokens:NaN,completion_tokens:-1},apiKey:config.apiKey},deepSeekProfile(config.endpoint),{model:'fallback',elapsedMs:123,maxOutputTokens:16384});assert.equal(receipt.quality,'not-rated');assert.deepEqual(receipt.usage,{total_tokens:200});assert.equal(receipt.apiKey,undefined);assert.ok(receiptLabel(receipt).includes('200 tokens'));
 assert.equal(normalizeModelReceipt({...receipt,elapsedMs:Infinity}),undefined);assert.equal(normalizeModelReceipt({...receipt,provider:'untrusted'}),undefined);assert.equal(normalizeModelReceipt({...receipt,model:'<script>secret</script>'}),undefined);assert.equal(normalizeModelReceipt({...receipt,requestId:'unsafe\ntext'}).requestId,undefined);
});
test('Only model candidates retain a sanitized response receipt across persistence',async()=>{
 const i=input(),out=await run(i,score(i)),c=normalizeCandidate({...out,before:i.project,prompt:i.prompt,receipt:{...out.receipt,headers:{Authorization:config.apiKey}}});assert.equal(c.receipt.provider,'deepseek');assert.equal(c.receipt.headers,undefined);assert.equal(normalizeCandidate({...c,source:'offline'}).receipt,undefined);
});
test('DeepSeek configuration status discloses the profile but no model, endpoint or key values',()=>{
 const env={LLM_API_URL:config.endpoint,LLM_MODEL:config.model,LLM_API_KEY:config.apiKey,LLM_MAX_TOKENS:'4096'};const s=serviceStatus(env);assert.equal(s.provider.id,'deepseek');assert.equal(s.provider.maxOutputTokens,4096);for(const value of [config.apiKey,config.endpoint,config.model])assert.ok(!JSON.stringify(s).includes(value));assert.equal(serviceStatus({...env,LLM_MAX_TOKENS:'NaN'}).ready,false);
});
test('Live test refuses missing credentials and non-DeepSeek destinations before networking',async()=>{
 let calls=0;const fetcher=async()=>{calls++;throw Error('must not call')};assert.deepEqual(await runLiveTest({env:{},fetcher}),{status:'blocked',reason:'missing-api-key',calls:0});assert.equal((await runLiveTest({env:{LLM_API_KEY:config.apiKey,LLM_API_URL:'https://other.example/chat'},fetcher})).reason,'not-official-deepseek-endpoint');assert.equal(calls,0);
});
test('Live runner can verify note-to-MIDI round-trip using an explicitly synthetic transport fixture',async()=>{
 const report=await runLiveTest({env:{LLM_API_KEY:config.apiKey},fetcher:async(u,o)=>{const ctx=JSON.parse(JSON.parse(o.body).messages[1].content);return response({summary:'Synthetic transport test only.',tracks:ctx.targets.map(t=>({id:t.id,notes:[[({kick:36,snare:38,hat:42}[t.instrument]||60),0,.25,64]]}))})}});
 assert.equal(report.status,'passed-structural-checks');assert.equal(report.calls,1);assert.equal(report.checks.notes,8);assert.equal(report.checks.midiNotes,8);assert.equal(report.checks.sampledTracks,8);assert.ok(report.audio.includes('Not rendered'));
});
test('Server forwards only the server-side token cap and returns the successful receipt',async()=>{
 let opts;const server=createAppServer({env:{LLM_API_URL:config.endpoint,LLM_MODEL:config.model,LLM_API_KEY:config.apiKey,LLM_MAX_TOKENS:'2048'},compose:async(i,o)=>{opts=o;return run(i,score(i))}});server.listen(0,'127.0.0.1');await once(server,'listening');
 try{const r=await fetch(`http://127.0.0.1:${server.address().port}/api/compose`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({...input(),maxOutputTokens:32768})});assert.equal(r.status,200);assert.equal(opts.maxOutputTokens,2048);assert.equal((await r.json()).receipt.provider,'deepseek')}finally{server.close();server.closeAllConnections();await once(server,'close')}
});
test('An empty DeepSeek key is explicitly unready, while a keyless local model remains supported',async()=>{
 const {normalizeServiceStatus}=await import('../dist/service.js');const env={LLM_API_URL:config.endpoint,LLM_MODEL:config.model};const state=serviceStatus(env);assert.equal(state.ready,false);assert.equal(state.checks.credential,'missing');assert.equal(normalizeServiceStatus(state,new URL('http://127.0.0.1:4173/api/compose')).ready,false);
 assert.equal(serviceStatus({LLM_API_URL:'http://localhost:1234/v1/chat/completions',LLM_MODEL:'local-model'}).ready,true);
});
test('DeepSeek status normalization retains only the bounded public profile and rejects inconsistent credential state',async()=>{
 const {normalizeServiceStatus}=await import('../dist/service.js');const s=serviceStatus({LLM_API_URL:config.endpoint,LLM_MODEL:config.model,LLM_API_KEY:config.apiKey}),url=new URL('http://127.0.0.1:4173/api/compose');
 const out=normalizeServiceStatus({...s,provider:{...s.provider,key:config.apiKey}},url);assert.equal(out.provider.key,undefined);assert.equal(out.checks.credential,'valid');assert.throws(()=>normalizeServiceStatus({...s,checks:{...s.checks,credential:'missing'}},url));
});
test('Invalid DeepSeek key types and whitespace never crash or report ready',()=>{
 for(const key of [1,{},[],true,'   ','bad\nheader']){const state=serviceStatus({LLM_API_URL:config.endpoint,LLM_MODEL:config.model,LLM_API_KEY:key});assert.equal(state.ready,false)}
});
test('Live runner redacts malformed configuration and refuses credential-bearing URLs before networking',async()=>{
 let calls=0;for(const endpoint of ['not a url SECRET','https://user:SECRET@api.deepseek.com/chat/completions','https://api.deepseek.com/chat/completions#SECRET']){const out=await runLiveTest({env:{LLM_API_KEY:config.apiKey,LLM_API_URL:endpoint},fetcher:async()=>{calls++}});assert.equal(out.status,'blocked');assert.ok(!JSON.stringify(out).includes('SECRET'))}assert.equal(calls,0);
});
test('Live runner sanitizes HTTP failure evidence and never retries or applies it',async()=>{
 let calls=0;const out=await runLiveTest({env:{LLM_API_KEY:config.apiKey},fetcher:async()=>{calls++;return new Response('SECRET-UPSTREAM-ERROR',{status:401})}});assert.equal(out.status,'failed');assert.equal(out.reason,'unauthorized');assert.equal(out.calls,1);assert.equal(calls,1);assert.equal(out.inputUnchanged,true);assert.ok(!JSON.stringify(out).includes('SECRET'));
});
