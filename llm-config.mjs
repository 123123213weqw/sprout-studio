import {deepSeekProfile} from './deepseek.mjs';
import {serviceUrl,SERVICE_PROTOCOL,SERVICE_VERSION,ServiceError} from './dist/service.js';
export function validateProviderConfig({endpoint,model,apiKey}={}){let url;try{url=serviceUrl(endpoint)}catch{throw new ServiceError('configuration')};if(typeof model!=='string'||!model.trim()||model.length>120||/[\x00-\x1f\x7f]/.test(model)||apiKey!=null&&(typeof apiKey!=='string'||/[\x00-\x1f\x7f]/.test(apiKey)))throw new ServiceError('configuration');return{endpoint:url.href,model:model.trim(),apiKey:apiKey||undefined}}

export function validateRequestedModel(requested,env={}){
 const config=validateProviderConfig({endpoint:env.LLM_API_URL,model:requested||env.LLM_MODEL,apiKey:env.LLM_API_KEY});
 if(env.LLM_LOCK_MODEL==='1'&&config.model!==String(env.LLM_MODEL||'').trim())throw new ServiceError('model_locked');
 return config;
}
export function serviceStatus(env={}){
 let endpoint=env.LLM_API_URL?'valid':'missing',model=env.LLM_MODEL?'valid':'missing';
 let profile=null;if(endpoint==='valid'){try{const url=serviceUrl(env.LLM_API_URL);profile=deepSeekProfile(url.href,env.LLM_MAX_TOKENS===undefined?16384:Number(env.LLM_MAX_TOKENS))}catch{endpoint='invalid'}}
 if(model==='valid'&&(typeof env.LLM_MODEL!=='string'||!env.LLM_MODEL.trim()||env.LLM_MODEL.length>120||/[\x00-\x1f\x7f]/.test(env.LLM_MODEL)))model='invalid';
 // Keyless local models remain supported. Only the fixed public Flash identity is disclosed; credentials and endpoint values are never returned.
 if(env.LLM_API_KEY!=null&&(typeof env.LLM_API_KEY!=='string'||/[\x00-\x1f\x7f]/.test(env.LLM_API_KEY)))endpoint='invalid';
 const checks={endpoint,model};if(profile)checks.credential=typeof env.LLM_API_KEY!=='string'?env.LLM_API_KEY==null?'missing':'invalid':!env.LLM_API_KEY.trim()?'missing':/[\x00-\x1f\x7f]/.test(env.LLM_API_KEY)?'invalid':'valid';
 return{...(profile&&env.LLM_LOCK_MODEL==='1'&&env.LLM_MODEL==='deepseek-flash'?{selection:{model:'deepseek-flash',label:'DeepSeek V4.1 Flash',locked:true}}:{}),...(profile?{provider:{id:'deepseek',format:profile.format,thinking:profile.thinking,maxOutputTokens:profile.maxOutputTokens}}:{}),protocol:SERVICE_PROTOCOL,protocolVersion:SERVICE_VERSION,composePath:'/api/compose',ready:Object.values(checks).every(v=>v==='valid'),checks,apiKeyPresent:typeof env.LLM_API_KEY==='string'&&!!env.LLM_API_KEY.trim(),jsonMode:!!profile||env.LLM_JSON_MODE!=='0',limits:{maxInputNotes:12000,maxGeneratedNotes:5000,maxProjectBytes:3000000,maxBars:64,timeoutMs:80000,maxConcurrent:1}};
}
