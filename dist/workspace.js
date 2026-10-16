import {copy,validateProject} from './music.js';
import {normalizeView} from './timeline.js';
import {normalizeRange} from './transport.js';
// Do all potentially throwing preparation before closing the old vault or
// replacing live project/history. UI rendering then consumes one coherent plan.
export function prepareWorkspace(loaded,view){
 if(!loaded?.available||!loaded.project)throw Error('目标工程没有可用记录');const project=validateProject(loaded.project),timeline=normalizeView(view),range=normalizeRange(project.loopRange,project.bars*4);
 const track=project.tracks.find(t=>t.instrument==='keys'||t.instrument==='pad')||project.tracks[0];
 return{project,timeline,range,trackId:track.id,clipId:track.clips?.[0]?.id||null,sectionId:project.sections?.[0]?.id||null,history:copy(loaded.history||[]),future:copy(loaded.future||[])};
}
// Each tab carries its workspace identity in its URL. The directory's last
// choice is only a default for fresh tabs, not a reason to hijack another tab.
export function resolveWorkspace(catalog,requested){
 const fallback=catalog?.activeId||'legacy';if(!requested)return{id:fallback,message:null};
 if(catalog?.entries?.some(e=>e.id===requested&&!e.archived)||requested==='legacy'&&!catalog?.entries?.length)return{id:requested,message:null};
 return{id:fallback,message:'链接中的工程不在这个浏览器或已归档；已打开当前可用工作区。工程库不是云同步，请用工程文件搬运作品。'};
}
export function workspaceUrl(input,id){
 if(typeof id!=='string'||!/^[a-zA-Z0-9-]{1,80}$/.test(id))throw Error('工程链接标识不正确');const url=new URL(input);url.searchParams.set('workspace',id);return url.href;
}
