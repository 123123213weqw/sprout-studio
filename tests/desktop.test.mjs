import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {STUDIO_URL,SCHEME,isStudioURL,isExternalURL,isStudioDownload,downloadName,readDesktopEnvironment,startLocalBackend,createProtocolHandler} from '../desktop/runtime.mjs';
import {serviceUrl,probeService} from '../dist/service.js';
import {RUNTIME_FILES} from '../desktop/package.mjs';

test('Desktop origin is stable and exposes fetch without Node privileges',()=>{
 assert.equal(STUDIO_URL,'sprout://studio/');assert.equal(SCHEME.privileges.standard,true);assert.equal(SCHEME.privileges.secure,true);assert.equal(SCHEME.privileges.supportFetchAPI,true);
 assert.equal(SCHEME.privileges.bypassCSP,undefined);
 for(const url of ['sprout://studio/','sprout://studio/app.js','sprout://studio/?workspace=abc'])assert.ok(isStudioURL(url));
 for(const url of ['sprout://other/','sprout://studio:10/','sprout://user@studio/','https://studio/','file:///etc/passwd','invalid'])assert.equal(isStudioURL(url),false);
});
test('External links and blob exports reject privileged schemes and foreign origins',()=>{
 assert.ok(isExternalURL('https://www.electronjs.org/docs/'));
 for(const url of ['http://site.example/','file:///tmp/a','javascript:alert(1)','https://secret@site.example/'])assert.equal(isExternalURL(url),false);
 assert.ok(isStudioDownload('blob:sprout://studio/abc'));
 for(const url of ['blob:https://site.example/abc','https://site.example/abc','blob:sprout://other/abc'])assert.equal(isStudioDownload(url),false);
 assert.equal(downloadName('../../song.mid'),'song.mid');assert.equal(downloadName('C:\\private\\song.wav'),'song.wav');assert.equal(downloadName('\0../'),'sprout-export');
});
test('Desktop service endpoints require a desktop base and never relax provider validation',()=>{
 assert.equal(serviceUrl('/api/compose',STUDIO_URL).href,'sprout://studio/api/compose');
 for(const [value,base] of [['sprout://studio/api/compose',undefined],['sprout://studio/api/compose','https://site.example/'],['sprout://other/api/compose',STUDIO_URL],['sprout://studio:2/api/compose',STUDIO_URL],['/api/compose','file:///app/'],['sprout://studio/api/compose?key=secret',STUDIO_URL]])assert.throws(()=>serviceUrl(value,base));
 assert.equal(serviceUrl('/api/compose','http://127.0.0.1:4173').protocol,'http:');
});
test('Desktop config reads only approved server fields and does not inherit arbitrary environment',async()=>{
 const directory=await mkdtemp(join(tmpdir(),'sprout-env-'));const file=join(directory,'desktop.env');
 try{
  assert.deepEqual(await readDesktopEnvironment(file,{LLM_MODEL:'inherited',SECRET_OTHER:'hidden'}),{LLM_MODEL:'inherited'});
  await writeFile(file,'LLM_MODEL=deepseek-flash\nLLM_API_KEY="test-value"\nELECTRON_RUN_AS_NODE=1\nPORT=9999\n');
  assert.deepEqual(await readDesktopEnvironment(file,{LLM_MODEL:'inherited'}),{LLM_MODEL:'deepseek-flash',LLM_API_KEY:'test-value'});
  await writeFile(file,'x'.repeat(65537));await assert.rejects(readDesktopEnvironment(file),/check its format and size/);
 }finally{await rm(directory,{recursive:true,force:true})}
});
test('Private backend uses a free loopback port and closes cleanly',async()=>{
 const first=await startLocalBackend(),second=await startLocalBackend();
 try{assert.notEqual(first.base,second.base);assert.equal(new URL(first.base).hostname,'127.0.0.1');const health=await(await fetch(first.base+'/api/health')).json();assert.ok(health.ok);assert.equal(health.llmConfigured,false)}finally{await Promise.all([first.close(),second.close()])}
 await assert.rejects(fetch(first.base+'/api/health'));
});
test('Desktop protocol serves actual assets and passes local assistant status checks',async()=>{
 const backend=await startLocalBackend();
 try{
  const handler=createProtocolHandler(backend.base),fetcher=(url,options)=>handler(new Request(url,options));
  const page=await handler(new Request(STUDIO_URL));assert.equal(page.status,200);assert.match(page.headers.get('content-type'),/text\/html/);assert.match(page.headers.get('content-security-policy'),/script-src 'self'/);assert.match(await page.text(),/id="import-midi-file"/);
  const result=await probeService('/api/compose','/api/llm/status',{base:STUDIO_URL,fetcher});assert.equal(result.ready,false);
  const head=await handler(new Request(STUDIO_URL+'app.js',{method:'HEAD'}));assert.equal(head.status,200);assert.equal(await head.text(),'');
 }finally{await backend.close()}
});
test('Desktop protocol binds requests to one backend and strips renderer origin/credentials',async()=>{
 let seen;const handler=createProtocolHandler('http://127.0.0.1:43210',{fetcher:async(url,options)=>{seen={url,options};return new Response('{}',{headers:{'Content-Type':'application/json'}})}});
 const request=new Request(STUDIO_URL+'api/compose',{method:'POST',headers:{'Content-Type':'application/json',Origin:'sprout://studio',Cookie:'private'},body:'{}'});
 assert.equal((await handler(request)).status,200);assert.equal(seen.url,'http://127.0.0.1:43210/api/compose');assert.deepEqual(seen.options.headers,{'Content-Type':'application/json'});assert.equal(seen.options.redirect,'error');
 for(const base of ['https://127.0.0.1:3/','http://localhost:3/','http://127.0.0.1/','http://127.0.0.1:3/path','http://secret@127.0.0.1:3/'])assert.throws(()=>createProtocolHandler(base));
});
test('Desktop protocol rejects foreign URLs, writes outside compose and oversized bodies',async()=>{
 let calls=0;const handler=createProtocolHandler('http://127.0.0.1:43210',{fetcher:async()=>{calls++;return new Response('{}')}});
 assert.equal((await handler(new Request('sprout://other/app.js'))).status,403);
 assert.equal((await handler(new Request(STUDIO_URL+'app.js',{method:'POST',body:'x'}))).status,405);
 assert.equal((await handler(new Request(STUDIO_URL+'api/compose',{method:'POST',body:'x'.repeat(3000001)}))).status,413);
 assert.equal(calls,0);
});
test('Desktop protocol errors do not echo private upstream data',async()=>{
 const handler=createProtocolHandler('http://127.0.0.1:43210',{fetcher:async()=>{throw Error('PRIVATE-KEY-OR-ENDPOINT')}});
 const response=await handler(new Request(STUDIO_URL));assert.equal(response.status,502);assert.ok(!(await response.text()).includes('PRIVATE'));
});
test('Desktop packaging uses an explicit runtime allowlist, not the source working directory',()=>{
 assert.ok(RUNTIME_FILES.includes('dist'));assert.ok(RUNTIME_FILES.includes('desktop/main.mjs'));
 for(const path of ['.env','.openai','.git','node_modules','examples','screenshots','tests','desktop/smoke.mjs'])assert.ok(!RUNTIME_FILES.includes(path));
});
