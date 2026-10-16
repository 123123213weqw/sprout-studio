import {copy,validateProject,performanceBeat,swungBeat} from './music.js';
import {clipAt,notesInClip,ensureClips} from './clips.js';
import {randomAt} from './composition.js';
const EPS=.00005,MIN=.0313,round=n=>+n.toFixed(4),floor=n=>Math.floor((n+1e-10)*10000)/10000,clamp=(n,a,b)=>Math.max(a,Math.min(b,n));
export const PERFORMANCE_DEFAULTS={grid:0,strength:100,velocityScale:100,velocitySpread:0,timing:'keep',timingAmount:20,seed:271828,overlap:'keep'};
export const PERFORMANCE_PRESETS=[
 {id:'tidy',name:'整齐一点',description:'对齐起点 · 清除微偏移',controls:{...PERFORMANCE_DEFAULTS,grid:.25,timing:'clear'}},
 {id:'natural',name:'自然一点',description:'少量松紧 · 保留原节奏',controls:{...PERFORMANCE_DEFAULTS,timing:'natural',timingAmount:25,velocitySpread:5}},
 {id:'soft',name:'轻一点',description:'力度 ×80% · 不动时间',controls:{...PERFORMANCE_DEFAULTS,velocityScale:80}},
 {id:'strong',name:'有力一点',description:'力度 ×120% · 不动时间',controls:{...PERFORMANCE_DEFAULTS,velocityScale:120}}
];
export function normalizePerformance(input={}){
 if(!input||typeof input!=='object'||Array.isArray(input)||Object.keys(input).some(k=>!Object.hasOwn(PERFORMANCE_DEFAULTS,k)))throw Error('演奏整理参数格式不正确');
 const c={...PERFORMANCE_DEFAULTS,...input};if(![0,.125,.25,.5,1].includes(c.grid))throw Error('不支持这个起点网格');
 for(const [key,min,max,label] of [['strength',0,100,'对齐程度'],['velocityScale',25,200,'力度比例'],['velocitySpread',0,20,'力度变化'],['timingAmount',0,100,'时间松紧']]){if(!Number.isFinite(c[key])||c[key]<min||c[key]>max)throw Error(`${label}须为 ${min}–${max}`);c[key]=Math.round(c[key])}
 if(!['keep','clear','natural'].includes(c.timing)||!['keep','trim'].includes(c.overlap))throw Error('时间或重叠处理方式不正确');
 if(!Number.isInteger(c.seed)||c.seed<0||c.seed>0xffffffff)throw Error('演奏种子须为 0–4294967295 整数');return c;
}
export function performanceTargets(project,trackId,{scope='selected',ids=[],clipId}={}){
 const track=project.tracks.find(t=>t.id===trackId);if(!track)throw Error('目标轨道已不存在');if(!['selected','clip','track'].includes(scope))throw Error('整理范围不正确');let notes;
 if(scope==='selected'){if(!Array.isArray(ids)||ids.some(id=>typeof id!=='string')||new Set(ids).size!==ids.length)throw Error('音符选择格式不正确');const set=new Set(ids);notes=track.notes.filter(n=>set.has(n.id));if(notes.length!==ids.length)throw Error('所选音符已改变，请重新选择')}
 else if(scope==='clip'){const clip=track.clips.find(c=>c.id===clipId);if(!clip)throw Error('先选择一个音块');notes=notesInClip(track,clip)}else notes=track.notes;
 if(!notes.length)throw Error('这个范围没有音符');return notes.map(n=>n.id);
}
function events(track,swing){return track.notes.map(n=>{const start=performanceBeat(n,swing,clipAt(track,n.start));return{note:n,start,end:start+n.duration}}).sort((a,b)=>a.note.pitch-b.note.pitch||a.start-b.start||a.note.start-b.note.start||a.note.id.localeCompare(b.note.id))}
// Count every relevant pair, but cap detail rows to avoid a quadratic-sized report.
export function performanceOverlaps(track,swing,ids){
 const selected=new Set(ids),rows=[],active=[];let count=0,pitch=null;
 for(const event of events(track,swing)){if(pitch!==event.note.pitch){active.length=0;pitch=event.note.pitch}for(let i=active.length-1;i>=0;i--)if(active[i].end<=event.start+EPS)active.splice(i,1);
  for(const earlier of active)if(selected.has(earlier.note.id)||selected.has(event.note.id)){count++;if(rows.length<30)rows.push({pitch,earlierId:earlier.note.id,laterId:event.note.id,start:event.start,end:Math.min(earlier.end,event.end),earlierSelected:selected.has(earlier.note.id),laterSelected:selected.has(event.note.id)})}active.push(event);
 }return{count,rows,truncated:count>rows.length};
}
const differs=(a,b)=>a.start!==b.start||a.duration!==b.duration||a.velocity!==b.velocity||(a.timingOffset||0)!==(b.timingOffset||0);
export function planPerformance(project,trackId,{controls={},...selection}={}){
 const before=validateProject(project),c=normalizePerformance(controls),ids=performanceTargets(before,trackId,selection),chosen=new Set(ids),out=copy(before),track=out.tracks.find(t=>t.id===trackId),original=before.tracks.find(t=>t.id===trackId),oldNotes=new Map(original.notes.map(n=>[n.id,n])),owners=new Map(original.notes.map(n=>[n.id,clipAt(original,n.start)]));
 let limitedTiming=0,clampedVelocity=0;const groups=new Map();
 for(const n of track.notes)if(chosen.has(n.id)){
  const region=owners.get(n.id),old=oldNotes.get(n.id);if(!region)throw Error('音符没有所属音块');
  if(c.grid)n.start=round(n.start+(Math.round(n.start/c.grid)*c.grid-n.start)*c.strength/100);
  if(n.start<region.start-EPS||n.start+n.duration>region.start+region.length+EPS||clipAt(track,n.start)?.id!==region.id)throw Error('对齐后音符越过原音块边界；整组不会改动，请降低对齐程度或延长音块');
  const raw=Math.round(n.velocity*c.velocityScale/100+(randomAt(c.seed,`velocity:${track.id}:${n.id}`)*2-1)*c.velocitySpread);n.velocity=clamp(raw,1,127);if(raw!==n.velocity)clampedVelocity++;
  if(c.timing==='clear')delete n.timingOffset;
  else if(c.timing==='natural'){const key=`${region.id}:${old.start.toFixed(4)}`;if(!groups.has(key))groups.set(key,[]);groups.get(key).push(n)}
  else if(n.start+(n.timingOffset||0)<region.start-EPS||n.start+(n.timingOffset||0)+n.duration>region.start+region.length+EPS)throw Error('对齐后原微偏移越界；请选择清除或重新生成微偏移，整组不会改动');
 }
 for(const [key,notes] of groups){const extent=.04*c.timingAmount/100;let low=-extent,high=extent;for(const n of notes){const region=owners.get(n.id);low=Math.max(low,region.start-n.start);high=Math.min(high,region.start+region.length-n.start-n.duration)}const raw=(randomAt(c.seed,`time:${track.id}:${key}`)*2-1)*extent,offset=round(clamp(raw,low,high));if(raw<low||raw>high)limitedTiming+=notes.length;for(const n of notes){if(offset)n.timingOffset=offset;else delete n.timingOffset}}
 const blocked=[];if(c.overlap==='trim'){
  const ordered=events(track,out.swing);for(let i=0;i<ordered.length-1;i++){const current=ordered[i],next=ordered[i+1],n=current.note;if(!chosen.has(n.id)||n.pitch!==next.note.pitch||current.end<=next.start+EPS)continue;
   // Use the unclamped onset: reducing length may release a clip-end swing clamp.
   const region=owners.get(n.id),onset=Math.max(region.start,swungBeat(n.start,out.swing)+(n.timingOffset||0)),available=floor(next.start-onset);
   if(available<MIN){blocked.push('同音高同时起音或间隔太小，无法只缩短前音；请手动移开 / 删除重复音符，或保留重叠。');continue}n.duration=round(Math.min(n.duration,available));
  }
 }
 const overlapBefore=performanceOverlaps(original,before.swing,ids),overlapAfter=performanceOverlaps(track,out.swing,ids);if(c.overlap==='trim'&&overlapAfter.count)blocked.push('仍有与选区有关的重叠：未选中的前音保持不变。请扩大整理范围或选择保留重叠。');
 // Keep numerically unchanged notes byte-for-byte, including optional zero offsets.
 track.notes=track.notes.map(n=>chosen.has(n.id)&&!differs(oldNotes.get(n.id),n)?copy(oldNotes.get(n.id)):n);
 for(const n of track.notes)if(chosen.has(n.id)){const region=owners.get(n.id);if(n.duration<MIN-EPS||n.start+(n.timingOffset||0)<region.start-EPS||n.start+(n.timingOffset||0)+n.duration>region.start+region.length+EPS)throw Error('整理结果超出音块或音符长度边界，整组不会改动')}
 const changes=track.notes.filter(n=>chosen.has(n.id)&&differs(oldNotes.get(n.id),n)).map(n=>{const old=oldNotes.get(n.id),region=owners.get(n.id);return{id:n.id,before:copy(old),after:copy(n),beatBefore:performanceBeat(old,before.swing,region),beatAfter:performanceBeat(n,out.swing,region)}});
 const report={targetCount:ids.length,changed:changes.length,moved:changes.filter(x=>x.before.start!==x.after.start).length,velocity:changes.filter(x=>x.before.velocity!==x.after.velocity).length,timing:changes.filter(x=>(x.before.timingOffset||0)!==(x.after.timingOffset||0)).length,shortened:changes.filter(x=>x.before.duration!==x.after.duration).length,limitedTiming,clampedVelocity,overlapBefore,overlapAfter,blocked:[...new Set(blocked)],detached:0};
 if(report.blocked.length)return{project:null,ids,controls:c,changes,report};
 const plannedNotes=copy(track.notes);ensureClips(out);const result=validateProject(out),newTrack=result.tracks.find(t=>t.id===trackId);
 // The normalizer must never silently trim, move or edit an unselected note.
 const byId=new Map(newTrack.notes.map(n=>[n.id,n]));for(const n of plannedNotes){const actual=byId.get(n.id);if(!actual||differs(actual,n))throw Error('整理结果校验改变了音符，整组没有应用')}
 report.detached=original.clips.filter(old=>old.patternId&&!newTrack.clips.find(x=>x.id===old.id)?.patternId).length;
 return{project:result,ids,controls:c,changes,report};
}
