import {remoteService,readRemoteStatus,composeRemote} from './bridge.mjs';
import {createServer} from 'node:http';
import {readFile,stat} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {resolve,extname,sep} from 'node:path';
import {validateProject} from './dist/music.js';
import {normalizeControls} from './dist/composition.js';
import {sectionAt} from './dist/sections.js';
import {ServiceError,abortable} from './dist/service.js';
import {serviceStatus,validateRequestedModel} from './llm-config.mjs';
import {composeWithModel} from './llm.mjs';
const {version}=JSON.parse(await readFile(new URL('./package.json',import.meta.url),'utf8'));
const dir=resolve(fileURLToPath(new URL('./dist/',import.meta.url)));
const mime={'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'text/javascript; charset=utf-8','.svg':'image/svg+xml','.json':'application/json; charset=utf-8','.wav':'audio/wav','.txt':'text/plain; charset=utf-8'};
const json=(res,status,data)=>{if(res.destroyed||res.writableEnded)return;res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'});res.end(JSON.stringify(data))};
async function body(req){let bytes=0,chunks=[];for await(const part of req){bytes+=part.length;if(bytes>3000000)throw Error('large');chunks.push(part)}try{return JSON.parse(Buffer.concat(chunks).toString('utf8'))}catch{throw Error('json')}}
export function createAppServer({env=process.env,compose=composeWithModel,now=Date.now,minIntervalMs=1500}={}){
 const remote=remoteService(env);let activeCalls=0,lastCall=-Infinity;
 const readStatus=()=>remote?readRemoteStatus(remote):serviceStatus(env);
 const app=createServer(async(req,res)=>{try{const url=new URL(req.url,'http://localhost'),pathname=decodeURIComponent(url.pathname);res.setHeader('X-Content-Type-Options','nosniff');res.setHeader('Referrer-Policy','no-referrer');if(!/^(127\.0\.0\.1|localhost|\[::1\])(?::\d+)?$/.test(req.headers.host||''))return json(res,403,{error:'仅允许本机访问',code:'unauthorized'});
  if(pathname==='/api/health'){if(req.method!=='GET')return json(res,405,{error:'仅支持 GET'});let ready=false;try{ready=(await readStatus()).ready}catch{}return json(res,200,{ok:true,llmConfigured:ready,...(remote?{remoteBridge:true}:{}),version})}
  if(pathname==='/api/compose'||pathname==='/api/llm/status'){
   const origin=req.headers.origin;if(origin){const allowed=new Set([`http://127.0.0.1:${app.address()?.port}`,`http://localhost:${app.address()?.port}`]);if(!allowed.has(origin))return json(res,403,{error:'只允许本机工作站发起请求',code:'unauthorized'})}
   if(pathname==='/api/llm/status'){if(req.method!=='GET')return json(res,405,{error:'仅支持 GET'});try{return json(res,200,await readStatus())}catch(e){return json(res,502,{error:'The V100 service is unavailable. Start the SSH bridge or use offline mode.',code:e instanceof ServiceError?e.code:'network'})}}
   if(req.method!=='POST')return json(res,405,{error:'仅支持 POST',code:'input'});if(!req.headers['content-type']?.startsWith('application/json'))return json(res,415,{error:'需要 application/json',code:'input'});
   let state;try{state=await readStatus()}catch{return json(res,502,{error:'The V100 bridge is unavailable. The project was not changed.',code:'network'})}if(!state.ready)return json(res,503,{error:state.checks.credential==='missing'?'Add LLM_API_KEY to the server .env file, then restart. Offline composition is still available.':state.checks.endpoint==='missing'||state.checks.model==='missing'?'尚未配置大模型。请在服务端 .env 中设置 LLM_API_URL 和 LLM_MODEL，或切回离线灵感引擎。':'服务端模型配置无效。',code:state.checks.credential==='missing'||state.checks.endpoint==='missing'||state.checks.model==='missing'?'unconfigured':'configuration'});
   const blocked=()=>{if(activeCalls>=1||now()-lastCall<minIntervalMs){res.setHeader('Retry-After','2');json(res,429,{error:'请求正在处理或过快，请稍后再试。',code:'rate_limit'});return true}return false};if(blocked())return;
   let input;try{input=await body(req);if(typeof input.prompt!=='string'||!input.prompt.trim()||input.prompt.length>1600)throw Error('prompt');input.project=validateProject(input.project);if(input.controls!==undefined)input.controls=normalizeControls(input.controls,input.project.seed);if(!['all','selected','drums','section'].includes(input.scope||'all'))throw Error('scope');if(input.scope==='selected'&&!input.project.tracks.some(t=>t.id===input.selectedTrackId))throw Error('track');if(input.clipRange&&(input.scope!=='selected'||!input.project.tracks.find(t=>t.id===input.selectedTrackId)?.clips?.some(c=>c.start===input.clipRange.start&&c.length===input.clipRange.length)))throw Error('clip');if(input.scope==='section'){const s=sectionAt(input.project,input.selectedSectionId);if(!input.sectionRange||s.start!==input.sectionRange.start||s.length!==input.sectionRange.length||input.clipRange)throw Error('section')}else if(input.sectionRange||input.selectedSectionId)throw Error('section');if(remote){if(input.model!==undefined&&(typeof input.model!=='string'||!input.model.trim()||input.model.length>120||/[\x00-\x1f\x7f]/.test(input.model)))throw Error('model')}else{const normalized=validateRequestedModel(input.model,env);if(input.model!==undefined)input.model=normalized.model}}catch(e){return json(res,e instanceof ServiceError&&e.code!=='model_locked'?503:400,{error:e instanceof ServiceError?e.message:'请求参数不正确。请检查描述、模型名或所选范围。',code:e instanceof ServiceError?e.code:'input'})}
   // Recheck after asynchronous body reading: two simultaneous POSTs cannot both reserve a slot.
   if(res.destroyed||blocked())return;activeCalls++;lastCall=now();const controller=new AbortController();const disconnected=()=>{if(!res.writableEnded)controller.abort(new DOMException('客户端已断开','AbortError'))};req.once('aborted',disconnected);res.once('close',disconnected);
   try{const output=await abortable((remote?composeRemote(input,{base:remote,signal:controller.signal}):compose(input,{endpoint:env.LLM_API_URL,apiKey:env.LLM_API_KEY,model:input.model||env.LLM_MODEL,jsonMode:env.LLM_JSON_MODE!=='0',maxOutputTokens:env.LLM_MAX_TOKENS===undefined?16384:Number(env.LLM_MAX_TOKENS),signal:controller.signal})),controller.signal);if(!controller.signal.aborted)json(res,200,output)}catch(e){if(!controller.signal.aborted){const code=e.name==='TimeoutError'?'timeout':e instanceof ServiceError?e.code:'server';json(res,502,{error:e instanceof ServiceError?e.message:code==='timeout'?'模型请求超时。':'编曲服务失败。请检查服务端配置后重试。',code})}}finally{req.off('aborted',disconnected);res.off('close',disconnected);activeCalls--}
   return;
  }
  if(req.method!=='GET'&&req.method!=='HEAD'){res.writeHead(405);return res.end('Method not allowed')}
  const file=resolve(dir,'.'+(pathname==='/'?'/index.html':pathname));if(!file.startsWith(dir+sep)){res.writeHead(403);return res.end('Forbidden')};const meta=await stat(file);if(!meta.isFile())throw Error('Not found');const data=await readFile(file);res.writeHead(200,{'Content-Type':mime[extname(file)]||'application/octet-stream','Cache-Control':'no-cache'});res.end(req.method==='HEAD'?undefined:data)
 }catch{if(!res.destroyed&&!res.writableEnded){res.writeHead(404);res.end('Not found')}}});return app;
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{process.loadEnvFile?.(fileURLToPath(new URL('./.env',import.meta.url)))}catch(e){if(e.code!=='ENOENT')console.warn('Unable to load .env. Check its format.')}
 const server=createAppServer();server.listen(Number(process.env.PORT||4173),'127.0.0.1',()=>console.log(`Sprout Local: http://127.0.0.1:${server.address().port}\nLLM: ${serviceStatus(process.env).ready?'Configuration valid (no model called)':'Not ready (offline composition available)'}`));
}
