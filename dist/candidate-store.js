import {copy} from './music.js';
import {checksum,LIMITS as PROJECT_LIMITS} from './storage.js';
import {normalizeCandidate,projectFingerprint} from './candidates.js';

export const CANDIDATE_DB='sprout-candidate-shelf';
export const SHELF_LIMITS={entries:6,bytes:8*1024*1024};
const bytes=value=>new TextEncoder().encode(value).length;
export class CandidateConflict extends Error{constructor(){super('另一页面修改了候选架。请重新读取后再操作，这次没有覆盖。');this.name='CandidateConflict'}}
export function packCandidate(input){const c=normalizeCandidate(input),payload=JSON.stringify(c);for(const p of [c.before,c.project])if(bytes(JSON.stringify(p))>PROJECT_LIMITS.projectBytes)throw Error('候选原稿或工程超过 3 MB，请下载文件并减少音符');return{id:c.id,payload,checksum:checksum(payload)}}
export function unpackCandidate(record){if(!record||typeof record.payload!=='string'||bytes(record.payload)>SHELF_LIMITS.bytes||checksum(record.payload)!==record.checksum)throw Error('候选数据校验失败，没有自动覆盖旧记录');const raw=JSON.parse(record.payload),c=normalizeCandidate(raw);if(c.id!==record.id||JSON.stringify(c)!==record.payload)throw Error('候选记录格式或标识不一致');return c}
function validateState(state){if(state==null)return{format:1,revision:0,entries:[]};if(state.format!==1||!Number.isSafeInteger(state.revision)||state.revision<0||!Array.isArray(state.entries)||state.entries.length>SHELF_LIMITS.entries||bytes(JSON.stringify(state.entries))>SHELF_LIMITS.bytes)throw Error('候选架数据不正确，没有自动重置');const ids=new Set();for(const r of state.entries){const c=unpackCandidate(r);if(ids.has(c.id))throw Error('候选标识重复');ids.add(c.id)}return state}
function bounded(entries){if(entries.length>SHELF_LIMITS.entries)throw Error('候选架最多保留 6 版，请先下载或移除不需要的候选');const records=entries.map(packCandidate);if(bytes(JSON.stringify(records))>SHELF_LIMITS.bytes)throw Error('候选架超过 8 MiB，请先下载或移除较大的候选');return records}
export class CandidateStore{
 constructor(adapter,{open}={}){this.adapter=adapter;this.open=open;this.entries=[];this.revision=0;this.available=!!adapter;this.error=null;this.queue=Promise.resolve();this.lastRemoved=null}
 async load(){try{if(!this.adapter)throw Error('候选架存储不可用，候选仍可直接导出');const state=validateState(await this.adapter.read());this.revision=state.revision;this.entries=state.entries.map(unpackCandidate);this.available=true;this.error=null;return this.list()}catch(e){this.available=false;this.error=e.message;throw e}}
 enqueue(operation){const pending=this.queue.then(operation);this.queue=pending.catch(()=>{});return pending}
 mutate(change){return this.enqueue(async()=>{if(!this.available||!this.adapter)throw Error(this.error||'候选架存储不可用，请先重新读取');const next=change(copy(this.entries)),records=bounded(next);const saved=await this.adapter.update(this.revision,()=>({format:1,entries:records}));this.revision=saved.revision;this.entries=saved.entries.map(unpackCandidate);return this.list()})}
 saveMany(candidates){if(!Array.isArray(candidates)||!candidates.length)throw Error('没有候选可保存');const incoming=candidates.map(c=>normalizeCandidate(c));return this.mutate(entries=>{for(const c of incoming){if(entries.some(old=>old.id===c.id))throw Error('这版已经在候选架，不需要重复保存');entries.push(c)}return entries})}
 rename(id,label){if(typeof label!=='string'||!label.trim()||label.length>60)throw Error('候选名称须为 1–60 个字符');return this.mutate(entries=>{const c=entries.find(c=>c.id===id);if(!c)throw Error('候选已不存在');c.label=label.trim();return entries})}
 async remove(id){let removed,index;const result=await this.mutate(entries=>{index=entries.findIndex(c=>c.id===id);if(index<0)throw Error('候选已不存在');[removed]=entries.splice(index,1);return entries});this.lastRemoved={candidate:removed,index};return result}
 async undoRemove(){const removed=this.lastRemoved;if(!removed)throw Error('当前页面没有可撤销的候选移除');const result=await this.mutate(entries=>{if(entries.some(c=>c.id===removed.candidate.id))throw Error('这版已经恢复');entries.splice(Math.min(removed.index,entries.length),0,removed.candidate);return entries});this.lastRemoved=null;return result}
 get(id){const c=this.entries.find(c=>c.id===id);if(!c)throw Error('候选已不存在');return copy(c)}
 list(project){const current=project?projectFingerprint(project):null;return this.entries.map(c=>({id:c.id,label:c.label,createdAt:c.createdAt,source:c.source,context:copy(c.context),notesBefore:c.before.tracks.reduce((n,t)=>n+t.notes.length,0),notesAfter:c.project.tracks.reduce((n,t)=>n+t.notes.length,0),seed:c.seed,controls:c.controls?copy(c.controls):undefined,matches:current==null?undefined:projectFingerprint(c.before)===current}))}
 size(){return bytes(JSON.stringify(this.entries.map(packCandidate)))}
 async reload(){await this.queue;try{if(this.open){const adapter=await this.open();this.adapter?.close?.();this.adapter=adapter}return await this.load()}catch(e){this.available=false;this.error=e.message;throw e}}
}
class CandidateDBAdapter{
 constructor(db){this.db=db}
 close(){this.db.close()}
 read(){return new Promise((resolve,reject)=>{const tx=this.db.transaction('shelf','readonly'),r=tx.objectStore('shelf').get('active');let state;r.onsuccess=()=>state=r.result;tx.oncomplete=()=>resolve(state||null);tx.onabort=tx.onerror=()=>reject(tx.error||Error('无法读取候选架'))})}
 update(expected,change){return new Promise((resolve,reject)=>{const tx=this.db.transaction('shelf','readwrite'),store=tx.objectStore('shelf'),r=store.get('active');let next,error;r.onsuccess=()=>{try{const old=validateState(r.result);if(old.revision!==expected)throw new CandidateConflict();next=change(copy(old));next.revision=expected+1;validateState(next);store.put(next,'active')}catch(e){error=e;tx.abort()}};tx.oncomplete=()=>resolve(next);tx.onabort=tx.onerror=()=>reject(error||tx.error||Error('候选架保存失败'))})}
}
export function openCandidateDB(factory=globalThis.indexedDB){return new Promise((resolve,reject)=>{if(!factory)return reject(Error('此浏览器没有可用的候选架存储'));let settled=false;const request=factory.open(CANDIDATE_DB,1),timer=setTimeout(()=>{settled=true;reject(Error('候选架未能及时打开'))},2500);request.onupgradeneeded=()=>{if(!request.result.objectStoreNames.contains('shelf'))request.result.createObjectStore('shelf')};request.onerror=()=>{if(settled)return;settled=true;clearTimeout(timer);reject(request.error||Error('候选架不可用'))};request.onsuccess=()=>{if(settled){request.result.close();return}settled=true;clearTimeout(timer);const db=request.result;db.onversionchange=()=>db.close();resolve(new CandidateDBAdapter(db))}})}
export async function createCandidateStore(){let adapter,error;try{adapter=await openCandidateDB()}catch(e){error=e}const store=new CandidateStore(adapter,{open:openCandidateDB});if(error)store.error=error.message;try{await store.load()}catch{}return store}
