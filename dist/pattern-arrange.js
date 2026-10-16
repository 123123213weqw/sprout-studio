import {copy,uid,validateProject} from './music.js';
import {expandedBars,MAX_PROJECT_NOTES} from './limits.js';
import {patternCompatible,patternInstances,materializedNotes} from './patterns-core.js';
import {notesInClip} from './clips.js';
const EPS=.00005,round=n=>+n.toFixed(4),safeId=id=>typeof id==='string'&&/^[a-zA-Z0-9_-]{1,80}$/.test(id);
export const PATTERN_BATCH_MAX=32,PATTERN_INSTANCE_MAX=4096,PATTERN_PROJECT_MAX_BYTES=3000000;
const totalNotes=p=>p.tracks.reduce((n,t)=>n+t.notes.length,0);
function sourceAt(p,id){const source=p.patterns?.find(x=>x.id===id);if(!source)throw Error('源乐句已不存在，请重新打开 Pattern 库');return source}
function saved(p){const next=validateProject(p);if(new TextEncoder().encode(JSON.stringify(next)).length>PATTERN_PROJECT_MAX_BYTES)throw Error('操作后工程超过 3 MB 保存上限，请减少所选数量');return next}
function reservedIds(p){return new Set([p.id,...(p.sections||[]).map(s=>s.id),...(p.patterns||[]).flatMap(s=>[s.id,...s.notes.map(n=>n.id)]),...p.tracks.flatMap(t=>[t.id,...t.clips.map(c=>c.id),...t.notes.map(n=>n.id)])])}
function newId(used,factory){for(let i=0;i<32;i++){const id=factory();if(!safeId(id))throw Error('无法生成有效的音块标识');if(!used.has(id)){used.add(id);return id}}throw Error('音块标识发生碰撞，没有放置任何内容')}
// Adds a whole explicit series, never overwrites, fills unrelated tracks, or changes the source.
export function planPatternSeries(project,patternId,trackId,{start,count=1,interval,linked=true,extend=false,idFactory=uid}={}){
 const before=validateProject(project),source=sourceAt(before,patternId),old=before.tracks.find(t=>t.id===trackId);
 if(!old||!patternCompatible(source,old))throw Error('乐句与轨道不兼容；鼓只可放到同种鼓轨');
 if(!Number.isFinite(start)||start<0||!Number.isInteger(count)||count<1||count>PATTERN_BATCH_MAX||typeof linked!=='boolean'||typeof extend!=='boolean'||typeof idFactory!=='function')throw Error('起点、份数或关联方式不正确；一次可放 1–32 份');
 interval=interval===undefined?source.length:interval;
 if(!Number.isFinite(interval)||interval<.25||interval>256)throw Error('间隔须为 0.25–256 拍');
 start=round(start);interval=round(interval);
 if(count>1&&interval<source.length-EPS)throw Error('间隔短于乐句长度，会让新音块互相重叠');
 const rows=Array.from({length:count},(_,i)=>({index:i+1,start:round(start+i*interval),length:source.length})),end=round(rows.at(-1).start+source.length);
 if(end>before.bars*4+EPS&&!extend)throw Error('放置超出工程，请明确勾选空白延长');
 const bars=end>before.bars*4+EPS?expandedBars(end,before.bars):before.bars;
 for(let i=0;i<rows.length;i++){const r=rows[i];if(i&&r.start<rows[i-1].start+source.length-EPS)throw Error('舍入后新音块互相重叠');if(old.clips.some(c=>r.start<c.start+c.length-EPS&&r.start+source.length>c.start+EPS))throw Error(`第 ${r.index} 份的第 ${round(r.start/4+1)} 小节已有音块，整组没有放置`)}
 const addedNotes=count*source.notes.length;
 if(old.clips.length+count>256)throw Error('目标轨道超过 256 音块上限，没有部分放置');
 if(old.notes.length+addedNotes>4000)throw Error('目标轨道超过 4000 音符上限，没有部分放置');
 if(totalNotes(before)+addedNotes>MAX_PROJECT_NOTES)throw Error('工程超过 12000 音符上限，没有部分放置');
 const p=copy(before),target=p.tracks.find(t=>t.id===trackId),used=reservedIds(before),clipIds=[];p.bars=bars;
 for(const row of rows){const clip={id:newId(used,idFactory),name:source.name.slice(0,40),start:row.start,length:source.length,muted:false,...(linked?{patternId}: {})};let notes;
  if(linked){notes=materializedNotes(source,clip);for(const n of notes){if(used.has(n.id))throw Error('共享音符标识碰撞，没有放置任何内容');used.add(n.id)}}
  else notes=source.notes.map(n=>({...n,id:newId(used,idFactory),start:round(row.start+n.start)}));
  target.clips.push(clip);target.notes.push(...notes);clipIds.push(clip.id);row.clipId=clip.id;
 }
 const next=saved(p);
 return{project:next,trackId,patternId,clipIds,rows,stats:{count,addedNotes,linked,interval,extended:bars!==before.bars,barsBefore:before.bars,barsAfter:bars,trackClipsBefore:old.clips.length,trackClipsAfter:old.clips.length+count,trackNotesBefore:old.notes.length,trackNotesAfter:old.notes.length+addedNotes,projectNotesBefore:totalNotes(before),projectNotesAfter:totalNotes(next),referencesBefore:patternInstances(before,patternId).length,referencesAfter:patternInstances(next,patternId).length}};
}
// Only current references to this source may be selected; ordinary copies are never swept in.
export function planPatternInstances(project,patternId,{clipIds,action='mute'}={}){
 const before=validateProject(project);sourceAt(before,patternId);
 if(!['mute','unmute','detach','delete'].includes(action))throw Error('请选择静音、取消块静音、独立化或删除所选块');
 const refs=patternInstances(before,patternId);
 if(!Array.isArray(clipIds)||!clipIds.length||clipIds.length>PATTERN_INSTANCE_MAX||new Set(clipIds).size!==clipIds.length||clipIds.some(id=>!safeId(id)||!refs.some(r=>r.clipId===id)))throw Error('请至少选择一个仍关联此源的音块，不能重复或包含独立副本');
 const selected=new Set(clipIds),affected=refs.filter(r=>selected.has(r.clipId)),p=copy(before),rows=[];
 for(const t of p.tracks){const clips=t.clips.filter(c=>selected.has(c.id)),removed=new Set();
  for(const c of clips){const notes=notesInClip(t,c),changed=action==='delete'||action==='detach'||c.muted!==(action==='mute');rows.push({trackId:t.id,clipId:c.id,trackName:t.name,clipName:c.name,start:c.start,length:c.length,notes:notes.length,mutedBefore:c.muted,mutedAfter:action==='mute'?true:action==='unmute'?false:c.muted,changed});
   if(action==='delete')notes.forEach(n=>removed.add(n.id));else if(action==='detach')delete c.patternId;else c.muted=action==='mute';
  }
  if(action==='delete'){t.clips=t.clips.filter(c=>!selected.has(c.id));t.notes=t.notes.filter(n=>!removed.has(n.id))}
 }
 const next=saved(p),changed=rows.filter(r=>r.changed).length;
 return{project:next,patternId,action,rows,affected,stats:{selected:rows.length,changed,selectedNotes:rows.reduce((n,r)=>n+r.notes,0),deletedNotes:action==='delete'?rows.reduce((n,r)=>n+r.notes,0):0,referencesBefore:refs.length,referencesAfter:patternInstances(next,patternId).length,projectNotesBefore:totalNotes(before),projectNotesAfter:totalNotes(next)}};
}
