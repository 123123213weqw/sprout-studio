// A receipt describes one successful response, not a permanent connection or quality score.
export function normalizeModelReceipt(value){
 if(!value||typeof value!=='object'||!['deepseek','compatible'].includes(value.provider))return undefined;
 const label=s=>typeof s==='string'&&/^[a-zA-Z0-9._:-]{1,120}$/.test(s)?s:undefined;
 if(!label(value.model)||!Number.isSafeInteger(value.elapsedMs)||value.elapsedMs<0||value.elapsedMs>120000)return undefined;
 const usage={};for(const key of ['prompt_tokens','completion_tokens','total_tokens']){const n=value.usage?.[key];if(Number.isSafeInteger(n)&&n>=0&&n<=10000000)usage[key]=n}
 const out={provider:value.provider,model:value.model,elapsedMs:value.elapsedMs,usage,format:value.format==='sprout-score-v1'?'sprout-score-v1':'project',verified:'validated-notes',quality:'not-rated'};
 const id=label(value.requestId);if(id)out.requestId=id;
 if(Number.isSafeInteger(value.maxOutputTokens)&&value.maxOutputTokens>=1024&&value.maxOutputTokens<=32768)out.maxOutputTokens=value.maxOutputTokens;
 return out;
}
export function receiptLabel(value){const r=normalizeModelReceipt(value);return r?`${r.provider==='deepseek'?'DeepSeek':'Model'} / ${r.model} · ${(r.elapsedMs/1000).toFixed(1)}s${r.usage.total_tokens===undefined?'':` · ${r.usage.total_tokens.toLocaleString('en-US')} tokens`}`:''}
