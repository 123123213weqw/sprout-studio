import {copy,uid,validateProject} from './music.js';

export const VAULT_DB='sprout-project-vault';
export const JOURNAL_KEY='sprout-recovery-journal-v1';
export const LEGACY_KEY='sprout-project-v1';
export const LIMITS={versions:24,versionBytes:8*1024*1024,history:8,historyBytes:1536*1024,projectBytes:3e6,journalBytes:2*(3e6+1536*1024)+65536};
const bytes=text=>new TextEncoder().encode(text).length;
const validRevision=state=>Number.isSafeInteger(state?.revision)&&state.revision>=0?state.revision:0;
// Detect accidental corruption, not an authenticity or encryption mechanism.
export function checksum(text){let value=0x811c9dc5;for(const b of new TextEncoder().encode(text)){value^=b;value=Math.imul(value,0x01000193)}return(value>>>0).toString(16).padStart(8,'0')}
export class StorageConflict extends Error{constructor(){super('另一个页面已经保存了新版本，当前页面没有覆盖它。');this.name='StorageConflict'}}

export function packProject(project,{label='自动保存',reason='automatic',now=Date.now()}={}){
 const p=validateProject(project),payload=JSON.stringify(p),size=bytes(payload);
 if(size>LIMITS.projectBytes)throw Error('工程数据超过 3 MB，请减少音符或保存文件备份');
 return{id:uid(),createdAt:now,label:String(label).slice(0,60),reason,payload,checksum:checksum(payload),size};
}
export function unpackProject(entry){
 if(!entry||typeof entry.payload!=='string'||bytes(entry.payload)>LIMITS.projectBytes||checksum(entry.payload)!==entry.checksum)throw Error('版本数据校验失败');
 return validateProject(JSON.parse(entry.payload));
}
export function projectSummary(project){return{name:project.name,id:project.id,bpm:project.bpm,key:project.key,bars:project.bars,tracks:project.tracks.length,notes:project.tracks.reduce((sum,t)=>sum+t.notes.length,0),clips:project.tracks.reduce((sum,t)=>sum+(t.clips?.length||0),0)}}
export function boundedVersions(entries){
 const ordered=[...entries].sort((a,b)=>(a.createdAt||0)-(b.createdAt||0));let total=0,out=[];
 for(let i=ordered.length-1;i>=0;i--){const e=ordered[i],size=typeof e?.payload==='string'?bytes(e.payload):0;if(out.length>=LIMITS.versions||total+size>LIMITS.versionBytes)continue;total+=size;out.unshift(e)}
 return out;
}
function packHistory(history,future,now){
 let size=0;const pack=list=>{const result=[];for(const p of [...list].slice(-LIMITS.history).reverse()){let e;try{e=packProject(p,{now,label:'撤销历史',reason:'history'})}catch{break}if(size+e.size>LIMITS.historyBytes)break;size+=e.size;result.unshift(e)}return result};
 return{history:pack(history),future:pack(future)};
}
// Order matters: two workspaces may sound identical while their redo paths differ.
function timelineChecksum(entry,history=[],future=[]){return checksum(JSON.stringify({project:entry?.checksum,history:(Array.isArray(history)?history:[]).map(e=>e?.checksum),future:(Array.isArray(future)?future:[]).map(e=>e?.checksum)}))}
function unpackTimeline(record){
 let size=0,omitted=0;const unpack=list=>{const out=[];if(!Array.isArray(list)){if(list!=null)omitted++;return out}const entries=list.slice(-LIMITS.history);omitted+=Math.max(0,list.length-entries.length);
  for(let i=entries.length-1;i>=0;i--)try{const e=entries[i],p=unpackProject(e),n=bytes(e.payload);if(size+n>LIMITS.historyBytes){omitted+=i+1;break}size+=n;out.unshift(p)}catch{omitted++}
  return out;
 };return{history:unpack(record.history),future:unpack(record.future),omitted};
}
function readJournal(local,key=JOURNAL_KEY){
 const raw=local?.getItem(key);if(!raw)return null;if(bytes(raw)>LIMITS.journalBytes)throw Error('应急记录过大');
 const record=JSON.parse(raw),project=unpackProject(record?.entry);if(![undefined,1,2].includes(record.format))throw Error('未知应急格式');
 const rich=record.format===2,timeline=rich?unpackTimeline(record):{history:[],future:[],omitted:0};
 const timelineValid=!rich||(/^[a-f0-9]{8}$/.test(record.intentChecksum)&&Array.isArray(record.history)&&Array.isArray(record.future)&&timeline.omitted===0&&record.timelineChecksum===timelineChecksum(record.entry,record.history,record.future));
 return{raw,record,project,rich,timelineValid,...timeline};
}
function journalMatches(journal,state){
 if(journal.record.entry.checksum!==state.current?.checksum)return false;
 return!journal.rich||(journal.timelineValid&&journal.record.intentChecksum===timelineChecksum(state.current,state.history||[],state.future||[]));
}
const emptyState=()=>({format:1,revision:0,current:null,previous:null,versions:[],history:[],future:[],writer:null,lastAutomaticAt:0});

export function openIndexedDB(factory=globalThis.indexedDB,key='active'){
 return new Promise((resolve,reject)=>{
  if(!factory)return reject(Error('此浏览器没有可用的 IndexedDB'));
  let settled=false;const request=factory.open(VAULT_DB,1),timer=setTimeout(()=>{settled=true;reject(Error('本机版本库未能及时打开'))},2500);
  request.onupgradeneeded=()=>{if(!request.result.objectStoreNames.contains('workspace'))request.result.createObjectStore('workspace')};
  request.onerror=()=>{if(settled)return;settled=true;clearTimeout(timer);reject(request.error||Error('本机版本库不可用'))};
  request.onsuccess=()=>{if(settled){request.result.close();return}settled=true;clearTimeout(timer);const db=request.result;db.onversionchange=()=>db.close();resolve(new IndexedDBAdapter(db,key))};
 });
}
export class IndexedDBAdapter{
 constructor(db,key='active'){this.db=db;this.key=key}
 read(){return new Promise((resolve,reject)=>{const tx=this.db.transaction('workspace','readonly'),request=tx.objectStore('workspace').get(this.key);let value;request.onsuccess=()=>value=request.result;tx.oncomplete=()=>resolve(value||null);tx.onabort=tx.onerror=()=>reject(tx.error||Error('无法读取本机版本库'))})}
 update(expected,mutate){return new Promise((resolve,reject)=>{
  const tx=this.db.transaction('workspace','readwrite'),store=tx.objectStore('workspace'),request=store.get(this.key);let next,error;
  request.onsuccess=()=>{try{const current=request.result||emptyState();if(validRevision(current)!==expected)throw new StorageConflict();next=mutate(copy(current));next.revision=expected+1;store.put(next,this.key)}catch(e){error=e;tx.abort()}};
  tx.oncomplete=()=>resolve(next);tx.onabort=tx.onerror=()=>reject(error||tx.error||Error('本机保存失败'));
 })}
 close(){this.db.close()}
}

export class ProjectVault{
 constructor(adapter,{local=null,now=()=>Date.now(),writer=uid(),journalKey=JOURNAL_KEY,scope='legacy',allowLegacy=true,open}={}){this.journalKey=journalKey;this.scope=scope;this.allowLegacy=allowLegacy;this.open=open;this.adapter=adapter;this.local=local;this.now=now;this.writer=writer;this.revision=0;this.state=emptyState();this.queue=Promise.resolve();this.unavailable=!adapter;this.lastError=null;this.recoveredJournal=null;this.journalStatus={saved:false,history:0,future:0,omitted:0,reason:'none'};this.channel=null;this.onRemoteChange=()=>{};
 }
 connectChannel(){if(typeof BroadcastChannel!=='function')return;try{this.channel=new BroadcastChannel(this.scope==='legacy'?'sprout-vault-revisions':'sprout-vault-revisions:'+this.scope);this.channel.onmessage=e=>{if(e.data?.writer!==this.writer&&Number.isSafeInteger(e.data?.revision)&&e.data.revision>this.revision)this.onRemoteChange(e.data.revision)}}catch{}}
 async load(){
  const messages=[];try{if(this.adapter)this.state=await this.adapter.read()||emptyState()}catch{this.unavailable=true;messages.push('版本库读取失败，尝试应急记录。')}
  this.revision=validRevision(this.state);let project=null,recovered=false,source='none',entry=null;
  try{if(this.state.current){project=unpackProject(this.state.current);entry=this.state.current;source='vault'}}catch{messages.push('最近的工程记录损坏，正在找可用版本。')}
  if(!project){const candidates=[this.state.previous,...(Array.isArray(this.state.versions)?this.state.versions:[])].filter(Boolean).sort((a,b)=>(b.createdAt||0)-(a.createdAt||0));for(const candidate of candidates)try{project=unpackProject(candidate);entry=candidate;source='backup';recovered=true;break}catch{} }
  let journal=null;try{journal=readJournal(this.local,this.journalKey)}catch{messages.push('应急记录未通过校验，已忽略。')}
  let timeline=source==='vault'?unpackTimeline(this.state):{history:[],future:[],omitted:0};
  const differs=journal&&(!entry||journal.record.entry.checksum!==entry.checksum||(journal.rich&&journal.timelineValid&&!journalMatches(journal,{...this.state,current:entry})));
  if(differs&&(!entry||journal.record.createdAt>=entry.createdAt)&&(!project||journal.record.baseRevision===this.revision||journal.record.writer===this.state.writer)){
   project=journal.project;source='journal';recovered=true;this.recoveredJournal=journal.raw;
   timeline=journal.timelineValid?{history:journal.history,future:journal.future,omitted:journal.record.historyOmitted||0}:{history:[],future:[],omitted:0};
   messages.push(journal.rich&&journal.timelineValid?`已恢复应急工程，可撤销 ${timeline.history.length} 步、重做 ${timeline.future.length} 步。`:'已恢复离开页面前的应急工程；这条记录不含可验证的撤销 / 重做历史。');
  }else if(differs&&(!entry||journal.record.createdAt>=entry.createdAt))messages.push('另一页面的应急记录保留在版本窗口，请手动选择，未覆盖当前工程。');
  if(journal?.rich&&!journal.timelineValid)messages.push('应急撤销 / 重做历史未通过校验，未使用；工程音乐单独校验。');
  if(timeline.omitted)messages.push('部分撤销 / 重做历史受容量限制或损坏未恢复；重要原稿请下载文件。');
  if(!project&&this.allowLegacy)try{const legacy=this.local?.getItem(LEGACY_KEY);if(legacy){project=validateProject(JSON.parse(legacy));source='legacy';messages.push('旧版工程已迁移，首次保存会建立版本库。')}}catch{messages.push('旧版工程记录无法读取；未删除原记录。')}
  const {history,future}=timeline;
  return{project,history,future,recovered,source,messages,available:!!this.adapter&&!this.unavailable};
 }
 writeJournal(project,{history=[],future=[]}={}){
  this.journalStatus={saved:false,history:0,future:0,omitted:history.length+future.length,reason:'unavailable'};
  if(!this.local)return false;
  try{
   const entry=packProject(project,{now:this.now(),reason:'emergency',label:'离开前 / 应急记录'}),undo=packHistory(history,future,entry.createdAt),intentChecksum=timelineChecksum(entry,undo.history,undo.future);
   const record={format:2,writer:this.writer,baseRevision:this.revision,createdAt:entry.createdAt,entry,...undo,timelineChecksum:intentChecksum,intentChecksum,historyOmitted:history.length+future.length-undo.history.length-undo.future.length};
   let existing=null;try{existing=readJournal(this.local,this.journalKey)}catch{}
   // A recovering page may adopt only the exact journal it actually loaded.
   // Another page's later write must remain intact, even with identical music.
   if(existing?.record.writer&&existing.record.writer!==this.writer&&existing.raw!==this.recoveredJournal&&!journalMatches(existing,this.state)&&existing.record.createdAt>=(this.state.current?.createdAt||0)){
    this.journalStatus.reason='foreign';return false;
   }
   try{this.local.setItem(this.journalKey,JSON.stringify(record))}
   catch(error){
    if(!undo.history.length&&!undo.future.length)throw error;
    // Atomic setItem leaves the old record intact if both attempts fail.
    record.history=[];record.future=[];record.timelineChecksum=timelineChecksum(entry);record.historyOmitted=history.length+future.length;
    this.local.setItem(this.journalKey,JSON.stringify(record));
   }
   this.recoveredJournal=null;this.journalStatus={saved:true,history:record.history.length,future:record.future.length,omitted:record.historyOmitted,reason:record.historyOmitted?'limited':'complete'};return true;
  }catch{this.journalStatus.reason='failed';return false}
 }
 enqueue(action){const result=this.queue.then(action);this.queue=result.catch(()=>{});return result}
 save(project,{history=[],future=[],checkpointLabel=null,reason='automatic'}={}){
  const now=this.now(),entry=packProject(project,{now,label:checkpointLabel||'自动保存',reason}),undo=packHistory(history,future,now);
  return this.enqueue(async()=>{
   if(!this.adapter||this.unavailable)throw Error('本机版本库不可用，请保存工程文件。');
   try{const next=await this.adapter.update(this.revision,state=>{
     const current=state.current,validCurrent=(()=>{try{if(current){unpackProject(current);return true}}catch{}return false})();
     let versions=Array.isArray(state.versions)?state.versions:[];
     if(current&&!validCurrent&&typeof current.payload==='string'&&bytes(current.payload)<=LIMITS.projectBytes&&!versions.some(v=>v.reason==='damaged'&&v.payload===current.payload))versions=[...versions,{...current,id:uid(),label:'损坏的旧记录（仅下载）',reason:'damaged'}];
     const automatic=!checkpointLabel&&(!state.lastAutomaticAt||now-state.lastAutomaticAt>=60000);
     if(checkpointLabel||automatic){versions=[...versions,{...entry,label:checkpointLabel||(!current?'第一次保存':'自动版本'),reason:checkpointLabel?reason:'automatic'}]}
     return{format:1,revision:state.revision,writer:this.writer,updatedAt:now,current:entry,previous:validCurrent&&current.checksum!==entry.checksum?current:state.previous||null,versions:boundedVersions(versions),history:undo.history,future:undo.future,timelineChecksum:timelineChecksum(entry,undo.history,undo.future),lastAutomaticAt:automatic?now:state.lastAutomaticAt||0};
    });this.state=next;this.revision=next.revision;this.lastError=null;this.channel?.postMessage({writer:this.writer,revision:this.revision});
    // Compare the intended ordered timeline as well as music. A pending older
    // save must not clear a newer undo/redo-only journal.
    try{const journal=readJournal(this.local,this.journalKey);if(journal&&(journal.record.writer===this.writer||journal.raw===this.recoveredJournal)&&journalMatches(journal,next)){this.local.removeItem(this.journalKey);this.recoveredJournal=null}}catch{}
    return{revision:this.revision,history:undo.history.length,future:undo.future.length,versions:next.versions.length};
   }catch(error){this.lastError=error;throw error}
  });
 }
 checkpoint(project,label,options={}){return this.save(project,{...options,checkpointLabel:String(label||'我的保存点').slice(0,60),reason:options.reason||'manual'})}
 async list(){await this.queue;let state=this.state;if(this.adapter)state=await this.adapter.read()||emptyState();const versions=Array.isArray(state.versions)?state.versions:[];const rows=[];
  for(const entry of versions){let summary=null;try{summary=projectSummary(unpackProject(entry))}catch{}rows.push({id:entry.id,label:String(entry.label||'未命名版本').slice(0,60),createdAt:entry.createdAt||0,reason:entry.reason,valid:!!summary,summary})}
  if(state.previous&&!versions.some(v=>v.checksum===state.previous.checksum)){let summary=null;try{summary=projectSummary(unpackProject(state.previous))}catch{}rows.push({id:'previous',label:'上一次有效保存',createdAt:state.previous.createdAt||0,reason:'previous',valid:!!summary,summary})}
  try{const journal=readJournal(this.local,this.journalKey);if(journal&&!journalMatches(journal,state)){const summary=projectSummary(journal.project);rows.push({id:'journal',label:'未提交的应急记录',createdAt:journal.record.createdAt,reason:'emergency',valid:true,summary})}}catch{}
  return rows.sort((a,b)=>b.createdAt-a.createdAt);
 }
 async get(id){await this.queue;const state=this.adapter?await this.adapter.read()||emptyState():this.state;let entry;if(id==='previous')entry=state.previous;else if(id==='journal'){try{entry=JSON.parse(this.local?.getItem(this.journalKey)||'null')?.entry}catch{}}else entry=state.versions?.find(e=>e.id===id);if(!entry)throw Error('这个版本已经不在本机版本库里');return unpackProject(entry)}
 async getRaw(id){await this.queue;const state=this.adapter?await this.adapter.read()||emptyState():this.state;const entry=id==='previous'?state.previous:state.versions?.find(e=>e.id===id);if(typeof entry?.payload!=='string')throw Error('没有可下载的原始数据');return entry.payload}
 async rebase(){await this.queue;if(!this.adapter)throw Error('本机版本库不可用');this.state=await this.adapter.read()||emptyState();this.revision=validRevision(this.state);this.unavailable=false;return this.state.current?unpackProject(this.state.current):null}
 async retryStorage(open=this.open||openIndexedDB){await this.queue;if(this.adapter&&!this.unavailable)return;const next=await open();this.adapter?.close?.();this.adapter=next;this.unavailable=false;
  // Keep the last observed revision. Retrying is not permission to overwrite a newer workspace.
 }
 close(){this.channel?.close();this.adapter?.close?.()}
}

export function workspaceKey(id='legacy'){if(typeof id!=='string'||!/^[a-zA-Z0-9-]{1,80}$/.test(id))throw Error('工程工作区标识不正确');return id==='legacy'?'active':'project:'+id}
export function workspaceJournalKey(id='legacy'){workspaceKey(id);return id==='legacy'?JOURNAL_KEY:JOURNAL_KEY+':'+id}
export async function createProjectVault({workspaceId='legacy'}={}){const key=workspaceKey(workspaceId);let local=null;try{local=globalThis.localStorage}catch{}let adapter=null;try{adapter=await openIndexedDB(undefined,key)}catch{}return new ProjectVault(adapter,{local,journalKey:workspaceJournalKey(workspaceId),scope:workspaceId,allowLegacy:workspaceId==='legacy',open:()=>openIndexedDB(undefined,key)})}
