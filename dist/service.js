// Sprout's browser-facing protocol, not an upstream provider API or credential store.
export const SERVICE_PROTOCOL='sprout-compose',SERVICE_VERSION=1;
export const SERVICE_MESSAGES={
 endpoint:'地址需要 HTTPS 或本机 HTTP，不能含账号、密钥参数或片段。',
 status_address:'状态地址与编曲地址必须属于同一服务；请填写该服务提供的状态地址。',
 status_protocol:'没有兼容的Sprout 状态接口。在线静态演示不含模型后端；请配置自己的编曲服务。',
 network:'未能连接服务。检查服务是否启动、地址、网络和跨域许可；浏览器不会提供更细的网络原因。',
 timeout:'服务等待超时，工作区没有改变。可稍后按原范围重试。',
 unauthorized:'服务拒绝认证。请在服务端检查凭据或访问权限，不要把密钥填进网页。',
 not_found:'服务地址不存在。请使用Sprout 编曲协议地址，不是模型厂商的 Chat Completions 地址。',
 rate_limit:'服务仍在处理请求或请求过快。请稍后重试，没有自动再次调用。',
 unconfigured:'服务端尚未配置模型地址或模型名。先完成服务端配置，再重新检查。',
 model_locked:'This service uses a fixed model. Clear the model override in Assistant settings to use the configured model.',
 configuration:'服务端模型配置无效。检查地址、模型名和凭据格式；网页不会接收密钥。',
 response_json:'服务没有返回完整 JSON。检查是否误填了网页或代理地址。',
 response_large:'服务返回超过 3 MB 上限，结果未采用。请缩短编曲范围。',
 response_project:'服务返回的工程不符合Sprout 工程格式，结果未采用；请检查服务协议。',
 input:'请求参数不正确，请检查描述、模型名和所选范围。',
 provider_http:'模型接口返回错误。请在服务端检查模型、权限、额度和接口地址。',
 provider_json:'模型接口或编曲结果不是完整 JSON，结果未采用。',
 provider_truncated:'模型输出被截断。请减少小节数或调整服务端输出限额。',
 provider_refusal:'模型没有提供编曲结果，请修改描述后再生成。',
 provider_shape:'模型接口格式不兼容，需使用 Chat Completions 兼容响应。',
 provider_empty:'The model returned no notes. Nothing was applied; try a shorter, more specific phrase.',
 provider_project:'模型的音符或范围格式不正确，结果未采用。',
 server:'编曲服务暂时失败，工作区没有改变。可稍后重试。'
};
const retryCodes=new Set(['network','timeout','rate_limit','server']);
export class ServiceError extends Error{constructor(code,status){super(SERVICE_MESSAGES[code]||SERVICE_MESSAGES.server);this.name='ServiceError';this.code=SERVICE_MESSAGES[code]?code:'server';this.retryable=retryCodes.has(this.code);if(Number.isInteger(status))this.status=status}}
export function serviceUrl(value,base){let url;try{url=new URL(value,base)}catch{throw new ServiceError('endpoint')}
 // Only the desktop renderer may resolve relative endpoints to its fixed local origin.
 let desktop=false;try{const parent=new URL(base);desktop=parent.protocol==='sprout:'&&parent.host==='studio'&&!parent.username&&!parent.password&&url.protocol==='sprout:'&&url.host==='studio'}catch{}
 if(!desktop&&url.protocol!=='https:'&&!(url.protocol==='http:'&&['localhost','127.0.0.1','[::1]'].includes(url.hostname)))throw new ServiceError('endpoint');
 if(url.username||url.password||url.hash||[...url.searchParams.keys()].some(k=>/key|token|secret|password|auth|credential/i.test(k)))throw new ServiceError('endpoint');return url;
}
export function statusUrl(compose,status,base){const c=serviceUrl(compose,base),s=serviceUrl(status,base);if(c.origin!==s.origin)throw new ServiceError('status_address');return{compose:c,status:s}}
export function abortable(promise,signal){if(!signal)return promise;if(signal.aborted){Promise.resolve(promise).catch(()=>{});return Promise.reject(signal.reason)}return new Promise((resolve,reject)=>{const cleanup=()=>signal.removeEventListener('abort',abort),abort=()=>{cleanup();reject(signal.reason)};signal.addEventListener('abort',abort,{once:true});Promise.resolve(promise).then(value=>{cleanup();resolve(value)},error=>{cleanup();reject(error)})})}
export async function readBoundedJSON(response,{signal,maxBytes=3000000,requireJSON=true}={}){
 if(requireJSON&&!/\bapplication\/(?:[a-z0-9.+-]*\+)?json\b/i.test(response.headers?.get?.('content-type')||''))throw new ServiceError('response_json');
 if(Number(response.headers?.get?.('content-length'))>maxBytes)throw new ServiceError('response_large');
 const reader=response.body?.getReader();let text='';if(reader){let total=0;const decoder=new TextDecoder();try{while(true){const {value,done}=await abortable(reader.read(),signal);if(done)break;total+=value.byteLength;if(total>maxBytes)throw new ServiceError('response_large');text+=decoder.decode(value,{stream:true})}text+=decoder.decode()}catch(e){reader.cancel().catch(()=>{});throw e}finally{reader.releaseLock()}}
 else{text=await abortable(response.text(),signal);if(new TextEncoder().encode(text).length>maxBytes)throw new ServiceError('response_large')}
 try{return JSON.parse(text)}catch{throw new ServiceError('response_json')}
}
function httpError(response,data){const status=response.status;let code;if(status===401||status===403)code='unauthorized';else if(status===404)code='not_found';else if(status===429)code='rate_limit';else if(status===400&&data?.code==='model_locked')code='model_locked';else if(status===400||status===413||status===415)code='input';else if(data&&SERVICE_MESSAGES[data.code])code=data.code;else code='server';return new ServiceError(code,status)}
function transportError(e,signal){if(signal?.aborted)throw signal.reason;if(e instanceof ServiceError)throw e;throw new ServiceError('network')}
export async function requestComposition(endpoint,input,{base,signal,fetcher=fetch}={}){const url=serviceUrl(endpoint,base);signal?.throwIfAborted();let payload;try{payload=JSON.stringify(input)}catch{throw new ServiceError('input')}try{const response=await abortable(fetcher(url.href,{method:'POST',headers:{'Content-Type':'application/json'},body:payload,signal,credentials:'omit',redirect:'error'}),signal);let data;try{data=await readBoundedJSON(response,{signal})}catch(e){if(!response.ok&&e instanceof ServiceError&&e.code==='response_json')throw httpError(response);throw e}if(!response.ok)throw httpError(response,data);if(!data||typeof data!=='object'||Array.isArray(data)||!data.project)throw new ServiceError('response_project');return data}catch(e){transportError(e,signal)}}
export function normalizeServiceStatus(data,compose){if(!data||data.protocol!==SERVICE_PROTOCOL||data.protocolVersion!==SERVICE_VERSION||typeof data.ready!=='boolean'||typeof data.composePath!=='string')throw new ServiceError('status_protocol');let declared;try{declared=new URL(data.composePath,compose)}catch{throw new ServiceError('status_protocol')}if(declared.origin!==compose.origin||declared.pathname!==compose.pathname||declared.search!==compose.search)throw new ServiceError('status_protocol');
 const checks={};for(const key of ['endpoint','model']){if(!['missing','invalid','valid'].includes(data.checks?.[key]))throw new ServiceError('status_protocol');checks[key]=data.checks[key]}let provider;if(data.provider?.id==='deepseek'){if(data.provider.format!=='sprout-score-v1'||data.provider.thinking!=='disabled'||!Number.isSafeInteger(data.provider.maxOutputTokens)||data.provider.maxOutputTokens<1024||data.provider.maxOutputTokens>32768||!['missing','invalid','valid'].includes(data.checks?.credential))throw new ServiceError('status_protocol');provider={id:'deepseek',format:'sprout-score-v1',thinking:'disabled',maxOutputTokens:data.provider.maxOutputTokens};checks.credential=data.checks.credential}if(provider&&(checks.credential==='valid'&&!data.apiKeyPresent||checks.credential==='missing'&&data.apiKeyPresent))throw new ServiceError('status_protocol');if(typeof data.apiKeyPresent!=='boolean'||data.ready!==Object.values(checks).every(v=>v==='valid'))throw new ServiceError('status_protocol');
 let selection;if(data.selection!==undefined){if(!provider||data.selection?.model!=='deepseek-flash'||data.selection?.label!=='DeepSeek V4.1 Flash'||data.selection?.locked!==true)throw new ServiceError('status_protocol');selection={model:'deepseek-flash',label:'DeepSeek V4.1 Flash',locked:true}}
 const limits={};for(const key of ['maxInputNotes','maxGeneratedNotes','maxProjectBytes','maxBars','timeoutMs','maxConcurrent']){const n=data.limits?.[key],max={maxInputNotes:12000,maxGeneratedNotes:12000,maxProjectBytes:3000000,maxBars:64,timeoutMs:120000,maxConcurrent:16}[key];if(!Number.isSafeInteger(n)||n<1||n>max)throw new ServiceError('status_protocol');limits[key]=n}
 return{...(selection?{selection}:{}),...(provider?{provider}:{}),protocol:SERVICE_PROTOCOL,protocolVersion:SERVICE_VERSION,ready:data.ready,composePath:declared.pathname,checks,apiKeyPresent:data.apiKeyPresent,jsonMode:data.jsonMode!==false,limits};
}
export async function probeService(composeEndpoint,statusEndpoint,{base,signal,fetcher=fetch}={}){const urls=statusUrl(composeEndpoint,statusEndpoint,base);signal?.throwIfAborted();try{const response=await abortable(fetcher(urls.status.href,{method:'GET',headers:{Accept:'application/json'},signal,credentials:'omit',redirect:'error'}),signal);if(!response.ok)throw response.status===404?new ServiceError('status_protocol',404):httpError(response);return normalizeServiceStatus(await readBoundedJSON(response,{signal,maxBytes:32000}),urls.compose)}catch(e){transportError(e,signal)}}
export class RequestGate{
 constructor(){this.current=null;this.sequence=0}
 begin(timeoutMs=90000){if(this.current)throw Error('已有请求正在等待');if(!Number.isSafeInteger(timeoutMs)||timeoutMs<1||timeoutMs>120000)throw Error('请求超时设置不正确');const controller=new AbortController(),ticket={id:++this.sequence,controller,signal:AbortSignal.any([controller.signal,AbortSignal.timeout(timeoutMs)])};this.current=ticket;return ticket}
 isCurrent(ticket){return this.current===ticket}
 finish(ticket){if(!this.isCurrent(ticket))return false;this.current=null;return true}
 cancel(){const ticket=this.current;if(!ticket)return false;this.current=null;ticket.controller.abort(new DOMException('已取消生成','AbortError'));return true}
}
