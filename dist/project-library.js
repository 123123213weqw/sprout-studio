import {copy,uid,validateProject} from './music.js';
import {openIndexedDB,createProjectVault,workspaceKey,packProject,unpackProject,projectSummary,StorageConflict} from './storage.js';

export const LIBRARY_LIMITS={projects:12,catalogBytes:32768};
export class LibraryConflict extends Error{constructor(){super('另一页面更新了工程库。请重新读取后操作，这次没有覆盖。');this.name='LibraryConflict'}}
const empty=()=>({format:1,revision:0,activeId:null,entries:[]});
const byteSize=value=>new TextEncoder().encode(JSON.stringify(value)).length;
export function validateCatalog(input){
 if(input==null)return empty();const s=copy(input);
 if(s.format!==1||!Number.isSafeInteger(s.revision)||s.revision<0||!Array.isArray(s.entries)||s.entries.length>LIBRARY_LIMITS.projects||byteSize(s)>LIBRARY_LIMITS.catalogBytes)throw Error('工程库目录未通过校验，没有自动重置');
 const ids=new Set();for(const row of s.entries){workspaceKey(row?.id);if(ids.has(row.id)||typeof row.archived!=='boolean'||!Number.isFinite(row.createdAt)||row.createdAt<0||!Number.isFinite(row.lastOpenedAt)||row.lastOpenedAt<0)throw Error('工程库目录项目不正确');ids.add(row.id)}
 if(s.activeId!==null&&!s.entries.some(e=>e.id===s.activeId&&!e.archived))throw Error('上次打开的工程标识不正确');return s;
}
export function restorableWorkspace(state){
 if(!state||!Number.isSafeInteger(state.revision)||state.revision<0)throw Error('工程工作区记录缺失或版本号损坏');
 const candidates=[state.current,state.previous,...(Array.isArray(state.versions)?[...state.versions].sort((a,b)=>(b.createdAt||0)-(a.createdAt||0)):[])];
 for(let i=0;i<candidates.length;i++)try{const project=unpackProject(candidates[i]);return{project,recovered:i!==0}}catch{}
 throw Error('工程没有可校验的音乐，原记录未删除');
}
export function initialWorkspace(project,{now=Date.now(),writer=uid()}={}){
 const entry=packProject(project,{now,label:'第一次保存',reason:'automatic'});return{format:1,revision:1,current:entry,previous:null,versions:[copy(entry)],history:[],future:[],writer,updatedAt:now,lastAutomaticAt:now};
}
// Pure transaction plan; the adapter commits workspace and directory together.
export function changeCatalog(input,workspace,op){
 const old=validateCatalog(input),next=copy(old);workspaceKey(op.id);let row=next.entries.find(e=>e.id===op.id),writeWorkspace;
 if(op.kind==='create'||op.kind==='register'){
  if(row)throw Error('这个工程已经在库里');if(next.entries.length>=LIBRARY_LIMITS.projects)throw Error('工程库最多保留 12 个工程（含归档），没有自动删掉旧作品');
  if(op.kind==='create'){if(workspace!=null)throw Error('工程工作区标识冲突');restorableWorkspace(op.workspace);writeWorkspace=copy(op.workspace)}
  else if(op.id!=='legacy'||next.entries.length)throw Error('旧工程只能登记到空工程库');
  row={id:op.id,createdAt:op.now,lastOpenedAt:op.now,archived:false};next.entries.push(row);if(op.kind==='register')next.activeId=row.id;
 }else{
  if(!row)throw Error('工程已不在这个目录中');
  if(op.kind==='select'){if(row.archived)throw Error('请先从归档中恢复工程');restorableWorkspace(workspace);if(workspace.revision!==op.expectedWorkspaceRevision)throw new StorageConflict();row.lastOpenedAt=op.now;next.activeId=row.id}
  else if(op.kind==='archive'){if(row.id===next.activeId)throw Error('请先打开另一个工程，再归档当前工程');row.archived=true}
  else if(op.kind==='restore'){row.archived=false}
  else throw Error('未知工程库操作');
 }
 next.revision=old.revision+1;validateCatalog(next);return{catalog:next,workspace:writeWorkspace};
}
export class ProjectLibrary{
 constructor(adapter,{now=()=>Date.now(),openVault=id=>createProjectVault({workspaceId:id}),open}={}){this.adapter=adapter;this.now=now;this.openVault=openVault;this.open=open;this.state=empty();this.available=!!adapter;this.error=null;this.queue=Promise.resolve()}
 get activeId(){return this.state.activeId}
 async load(){try{if(!this.adapter)throw Error('本机工程库不可用，当前工程仍可下载');this.state=validateCatalog(await this.adapter.read());this.available=true;this.error=null;return this.state}catch(e){this.available=false;this.error=e.message;throw e}}
 enqueue(fn){const result=this.queue.then(fn);this.queue=result.catch(()=>{});return result}
 transact(op){return this.enqueue(async()=>{if(!this.adapter||!this.available)throw Error(this.error||'工程库不可用');workspaceKey(op.id);const s=await this.adapter.transact(this.state.revision,op);this.state=validateCatalog(s);return copy(s)})}
 async ensureLegacy(){if(this.state.entries.length)return;await this.transact({kind:'register',id:'legacy',now:this.now()})}
 async create(project,{duplicate=false,name}={}){
  const p=validateProject(project);p.id=uid();if(name!=null){if(typeof name!=='string'||!name.trim()||name.length>60)throw Error('工程名称须为 1–60 个字符');p.name=name.trim()}else if(duplicate)p.name=(p.name+' 副本').slice(0,60);
  const id=uid(),now=this.now(),workspace=initialWorkspace(p,{now});await this.transact({kind:'create',id,workspace,now});return{id,project:copy(p)};
 }
 async openProject(id){
  const row=this.state.entries.find(e=>e.id===id);if(!row||row.archived)throw Error('工程未登记或还在归档中');const vault=await this.openVault(id);
  try{const loaded=await vault.load();if(!loaded.available||!loaded.project)throw Error('目标工程没有可用的本机记录；当前工作区未切换');await this.transact({kind:'select',id,expectedWorkspaceRevision:vault.revision,now:this.now()});return{vault,loaded,id}}catch(e){vault.close();throw e}
 }
 archive(id){return this.transact({kind:'archive',id,now:this.now()})}
 restore(id){return this.transact({kind:'restore',id,now:this.now()})}
 async list(){await this.queue;if(!this.adapter||!this.available)throw Error(this.error||'工程库不可用');const rows=[];for(const row of this.state.entries){try{const state=await this.adapter.workspace(row.id),r=restorableWorkspace(state);rows.push({...copy(row),valid:true,recovered:r.recovered,summary:projectSummary(r.project),bytes:byteSize(state),history:state.history?.length||0,future:state.future?.length||0,versions:state.versions?.length||0})}catch(e){rows.push({...copy(row),valid:false,error:e.message,bytes:0})}}return rows.sort((a,b)=>b.lastOpenedAt-a.lastOpenedAt||b.createdAt-a.createdAt)}
 async getProject(id){await this.queue;if(!this.state.entries.some(e=>e.id===id))throw Error('工程不在库中');return restorableWorkspace(await this.adapter.workspace(id)).project}
 async getRaw(id){await this.queue;if(!this.state.entries.some(e=>e.id===id))throw Error('工程不在库中');const state=await this.adapter.workspace(id);if(state==null)throw Error('没有可下载的记录');return JSON.stringify(state,null,2)}
 async reload(){await this.queue;if(!this.adapter&&this.open)this.adapter=await this.open();return this.load()}
 close(){this.adapter?.close?.()}
}
export class LibraryDBAdapter{
 constructor(db){this.db=db}
 close(){this.db.close()}
 read(){return this.readKey('project-library')}
 workspace(id){return this.readKey(workspaceKey(id))}
 readKey(key){return new Promise((resolve,reject)=>{const tx=this.db.transaction('workspace','readonly'),r=tx.objectStore('workspace').get(key);let state;r.onsuccess=()=>state=r.result;tx.oncomplete=()=>resolve(state||null);tx.onabort=tx.onerror=()=>reject(tx.error||Error('工程库读取失败'))})}
 transact(expected,op){const key=workspaceKey(op.id);return new Promise((resolve,reject)=>{
  const tx=this.db.transaction('workspace','readwrite'),store=tx.objectStore('workspace'),r=store.get('project-library');let next,error;
  const fail=e=>{error=e;tx.abort()};r.onsuccess=()=>{let catalog;try{catalog=validateCatalog(r.result);if(catalog.revision!==expected)throw new LibraryConflict()}catch(e){return fail(e)}const w=store.get(key);w.onsuccess=()=>{try{const result=changeCatalog(catalog,w.result,op);next=result.catalog;if(result.workspace)store.put(result.workspace,key);store.put(next,'project-library')}catch(e){fail(e)}}};
  tx.oncomplete=()=>resolve(next);tx.onabort=tx.onerror=()=>reject(error||tx.error||Error('工程库保存失败，旧工程没有被替换'));
 })}
}
export async function createProjectLibrary(){const open=async()=>{const adapter=await openIndexedDB();return new LibraryDBAdapter(adapter.db)};let adapter;try{adapter=await open()}catch{}const library=new ProjectLibrary(adapter,{open});try{await library.load()}catch{}return library}
