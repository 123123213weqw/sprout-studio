import {readFile,stat} from 'node:fs/promises';
import {parseEnv} from 'node:util';

export const STUDIO_URL='sprout://studio/';
export const SCHEME={scheme:'sprout',privileges:{standard:true,secure:true,supportFetchAPI:true,corsEnabled:true,stream:true}};
export const CONTENT_POLICY="default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; media-src 'self' blob:; connect-src 'self' https: http://127.0.0.1:* http://localhost:*; object-src 'none'; frame-src 'none'; base-uri 'self'; form-action 'none'";
const configKeys=['LLM_API_URL','LLM_MODEL','LLM_API_KEY','LLM_MAX_TOKENS','LLM_JSON_MODE','LLM_LOCK_MODEL','SPROUT_REMOTE_SERVICE_URL'];

export function isStudioURL(value){
 try{const u=new URL(value);return u.protocol==='sprout:'&&u.hostname==='studio'&&!u.port&&!u.username&&!u.password}catch{return false}
}
export function isExternalURL(value){
 try{const u=new URL(value);return u.protocol==='https:'&&!u.username&&!u.password&&value.length<=2048}catch{return false}
}
export function isStudioDownload(value){return typeof value==='string'&&value.startsWith('blob:')&&isStudioURL(value.slice(5))}
export function downloadName(value){
 const cleaned=String(value||'').split(/[\\/]/).at(-1).replace(/[\x00-\x1f\x7f]/g,'').replace(/^\.+/,'').trim().slice(0,160);
 return cleaned||'sprout-export';
}
export async function readDesktopEnvironment(path,inherited={}){
 const result=Object.fromEntries(configKeys.filter(k=>typeof inherited[k]==='string').map(k=>[k,inherited[k]]));
 try{
  if((await stat(path)).size>65536)throw Error('Desktop configuration is too large');
  const parsed=parseEnv(await readFile(path,'utf8'));
  for(const key of configKeys)if(Object.hasOwn(parsed,key))result[key]=parsed[key];
 }catch(error){if(error.code!=='ENOENT')throw Error('Unable to read desktop.env; check its format and size')}
 return result;
}
export async function startLocalBackend(env={}){
 const {createAppServer}=await import('../server.mjs');
 const server=createAppServer({env});
 await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve)});
 return{base:`http://127.0.0.1:${server.address().port}`,server,close:()=>new Promise(resolve=>{server.close(resolve);server.closeAllConnections()})};
}
async function boundedBody(request){
 const chunks=[];let size=0;
 if(request.body)for await(const chunk of request.body){size+=chunk.byteLength;if(size>3000000)throw Error('large');chunks.push(chunk)}
 return Buffer.concat(chunks);
}
export function createProtocolHandler(base,{fetcher=fetch}={}){
 const target=new URL(base);
 if(target.protocol!=='http:'||target.hostname!=='127.0.0.1'||!target.port||target.username||target.password||target.pathname!=='/'||target.search||target.hash)throw Error('Invalid private backend');
 return async request=>{
  if(!isStudioURL(request.url))return new Response('Forbidden',{status:403});
  const url=new URL(request.url),method=request.method;
  if(!['GET','HEAD','POST'].includes(method)||method==='POST'&&url.pathname!=='/api/compose')return new Response('Method not allowed',{status:405});
  try{
   if(Number(request.headers.get('content-length'))>3000000)return new Response('Request too large',{status:413});
   const body=method==='POST'?await boundedBody(request):undefined;
   const upstream=await fetcher(target.origin+url.pathname+url.search,{method,headers:method==='POST'?{'Content-Type':request.headers.get('content-type')||''}:{},body,signal:request.signal,redirect:'error'});
   const headers=new Headers(upstream.headers);headers.set('Content-Security-Policy',CONTENT_POLICY);
   return new Response(method==='HEAD'?null:upstream.body,{status:upstream.status,statusText:upstream.statusText,headers});
  }catch(error){return new Response(error.message==='large'?'Request too large':'Local service unavailable',{status:error.message==='large'?413:502})}
 };
}
