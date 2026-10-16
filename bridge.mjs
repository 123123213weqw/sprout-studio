import {probeService,requestComposition,ServiceError} from './dist/service.js';
import {validateProject} from './dist/music.js';
import {normalizeModelReceipt} from './dist/model-receipt.js';

export function remoteService(env={}){
 const value=env.SPROUT_REMOTE_SERVICE_URL;if(!value)return null;
 let url;try{url=new URL(value)}catch{throw new ServiceError('configuration')}
 // The remote API is reachable only through an explicitly bound local SSH tunnel.
 if(url.protocol!=='http:'||!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||!url.port||url.username||url.password||url.pathname!=='/'||url.search||url.hash)throw new ServiceError('configuration');
 return url.origin;
}
export function readRemoteStatus(base,{fetcher=fetch,signal}={}){
 const deadline=AbortSignal.timeout(4000);return probeService(base+'/api/compose',base+'/api/llm/status',{fetcher,signal:signal?AbortSignal.any([deadline,signal]):deadline});
}
export async function composeRemote(input,{base,signal,fetcher=fetch}={}){
 const deadline=AbortSignal.timeout(85000),combined=signal?AbortSignal.any([signal,deadline]):deadline;
 const data=await requestComposition(base+'/api/compose',input,{signal:combined,fetcher});let project;try{project=validateProject(data.project)}catch{throw new ServiceError('response_project')}
 return{project,summary:typeof data.summary==='string'?data.summary.slice(0,700):'A model candidate is ready for review.',source:'llm',receipt:normalizeModelReceipt(data.receipt),controls:input.controls,seed:input.controls?.seed};
}
