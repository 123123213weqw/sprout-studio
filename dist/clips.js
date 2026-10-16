// Regions own notes by their start beat. Regions on one track never overlap.
// Keeping absolute note times makes v1 files and external model responses interoperable.
import {expandedBars,validBars} from './limits.js';
import {synchronizePatterns} from './patterns-core.js';
import {normalizeSections,resizeSections} from './sections-core.js';
const clone = value => JSON.parse(JSON.stringify(value));
const id = () => globalThis.crypto.randomUUID();
const safeId = value => typeof value === 'string' && /^[a-zA-Z0-9_-]{1,80}$/.test(value);
const round = value => +value.toFixed(4);
const EPS = .00005;
export const notesInClip = (track, clip) => track.notes.filter(n => n.start >= clip.start - EPS && n.start < clip.start + clip.length - EPS);
export function clipAt(track, beat) { return track.clips?.find(c => beat >= c.start - EPS && beat < c.start + c.length - EPS); }
export const audibleNotes = track => track.notes.filter(n => !clipAt(track, n.start)?.muted);

export function ensureClips(project, {strict = false} = {}) {
  const end = project.bars * 4, ids = new Set();
  if(project.sections!==undefined)project.sections=normalizeSections(project.sections,end);
  for (const track of project.tracks) {
    if (track.clips === undefined) {
      track.clips = [];
      const span = project.version>=2 ? 8 : end;
      for (let start = 0; start < end; start += span) track.clips.push({id:id(), name:track.name, start, length:Math.min(span,end-start), muted:false});
    }
    if (!Array.isArray(track.clips) || track.clips.length > 256) throw Error('音块数量不正确');
    track.clips = track.clips.map(c => {
      if (!c || !Number.isFinite(c.start) || !Number.isFinite(c.length) || c.start < 0 || c.length < .25 || c.start + c.length > end + EPS) throw Error('音块位置或长度不合法');
      let cid = safeId(c.id) && !ids.has(c.id) ? c.id : id(); ids.add(cid);
      return {id:cid, name:String(c.name || track.name).slice(0,40), start:round(c.start), length:round(c.length), muted:c.muted===true,...(c.patternId===undefined?{}:{patternId:c.patternId})};
    }).sort((a,b) => a.start-b.start);
    for (let i=1;i<track.clips.length;i++) if (track.clips[i].start < track.clips[i-1].start + track.clips[i-1].length - EPS) throw Error('同一轨道的音块不能重叠');
    for (const note of track.notes) {
      let region = clipAt(track,note.start);
      if (!region) {
        if (strict) throw Error('音符必须位于一个音块内');
        const previous = track.clips.filter(c=>c.start+c.length<=note.start+EPS).at(-1);
        const next = track.clips.find(c=>c.start>note.start);
        const start = Math.max(previous ? previous.start+previous.length : 0, Math.floor(note.start/4)*4);
        const stop = Math.min(next?.start ?? end, Math.max(start+4, Math.ceil((note.start+note.duration)/4)*4));
        region = {id:id(),name:track.name,start:round(start),length:round(stop-start),muted:false};
        if (region.length < .25 || track.clips.length >= 256) throw Error('这个空隙放不下音块');
        track.clips.push(region); track.clips.sort((a,b)=>a.start-b.start);
      }
      if(strict && note.start+note.duration>region.start+region.length+EPS)throw Error('音符超出所属音块的边界');
      if(Number.isFinite(note.timingOffset))note.timingOffset=round(Math.max(region.start-note.start,Math.min(note.timingOffset,region.start+region.length-note.start-Math.min(note.duration,region.start+region.length-note.start))));
      note.duration = round(Math.min(note.duration,region.start+region.length-note.start));
      if (note.duration < .03125 - EPS) throw Error('音符距离音块边缘太近');
    }
  }
  project.version = project.patterns===undefined?2:3;
  return synchronizePatterns(project,{strict});
}

function find(project, trackId, clipId) {
  const track = project.tracks.find(t=>t.id===trackId), clip = track?.clips?.find(c=>c.id===clipId);
  if (!track || !clip) throw Error('请先选择一个音块');
  return {track,clip};
}
function space(track,start,length,end,except) {
  if (!Number.isFinite(start) || !Number.isFinite(length) || start<0 || length<.25 || start+length>end+EPS) throw Error('音块超出工程范围');
  if (track.clips.some(c=>c.id!==except && start<c.start+c.length-EPS && start+length>c.start+EPS)) throw Error('这里已有音块。先移走或删除它。');
}
export function firstClipSpace(track,length,end,from=0) {
  const gaps=[];let cursor=0;
  for (const c of [...track.clips].sort((a,b)=>a.start-b.start)) { if(c.start-cursor>=length-EPS)gaps.push({start:cursor,end:c.start});cursor=c.start+c.length; }
  if(end-cursor>=length-EPS)gaps.push({start:cursor,end});
  for(const g of gaps){const at=Math.max(g.start,from);if(at+length<=g.end+EPS)return round(at)}
  return gaps.length ? round(gaps[0].start) : null;
}
export function createClip(project,trackId,start,length=4) {
  const out=clone(project),track=out.tracks.find(t=>t.id===trackId);
  if(!track)throw Error('轨道不存在');space(track,start,length,out.bars*4);
  if(track.clips.length>=256)throw Error('这条轨道的音块已满');
  const clip={id:id(),name:track.name,start:round(start),length:round(length),muted:false};track.clips.push(clip);
  return {project:ensureClips(out),clipId:clip.id};
}
export function moveClip(project,trackId,clipId,start,{duplicate=false}={}) {
  const out=clone(project),{track,clip}=find(out,trackId,clipId),notes=notesInClip(track,clip);
  space(track,start,clip.length,out.bars*4,duplicate?null:clip.id);
  const offset=round(start-clip.start);
  if(duplicate){if(track.clips.length>=256)throw Error('这条轨道的音块已满');const next={...clip,id:id(),start:round(start),name:clip.name+' 副本'};delete next.patternId;track.clips.push(next);for(const n of notes)track.notes.push({...n,id:id(),start:round(n.start+offset)});return {project:ensureClips(out),clipId:next.id}}
  for(const n of notes)n.start=round(n.start+offset);clip.start=round(start);return {project:ensureClips(out),clipId};
}
// All copies use the original snapshot; collision rejects the whole operation.
export function repeatClip(project,trackId,clipId,{count=3,start,gap=0,extend=false}={}) {
 const out=clone(project),{track,clip}=find(out,trackId,clipId),source=notesInClip(track,clip);
 if(!Number.isInteger(count)||count<1||count>32||!Number.isFinite(gap)||gap<0||gap>64||typeof extend!=='boolean')throw Error('复制数量须为 1–32，间隔不能小于零');
 start=start??clip.start+clip.length;if(!Number.isFinite(start)||start<0)throw Error('复制起点不正确');
 const positions=Array.from({length:count},(_,i)=>round(start+i*(clip.length+gap))),requiredEnd=positions.at(-1)+clip.length;
 if(requiredEnd>out.bars*4+EPS){if(!extend)throw Error('复制会超出工程。可选择延长工程，新增部分仅留空白');out.bars=expandedBars(requiredEnd,out.bars)}
 if(track.clips.length+count>256||track.notes.length+source.length*count>4000||out.tracks.reduce((sum,t)=>sum+t.notes.length,0)+source.length*count>12000)throw Error('复制超过音块或音符容量上限');
 const clipIds=[];for(const [i,at] of positions.entries()){space(track,at,clip.length,out.bars*4);const next={...clip,id:id(),start:at,name:String(clip.name+' · '+(i+2)).slice(0,40)};delete next.patternId;track.clips.push(next);clipIds.push(next.id);for(const n of source)track.notes.push({...n,id:id(),start:round(n.start-clip.start+at)})}
 return{project:ensureClips(out),clipIds,positions,addedNotes:source.length*count,extended:out.bars!==project.bars};
}
export function resizeClip(project,trackId,clipId,length) {
  const out=clone(project),{track,clip}=find(out,trackId,clipId);space(track,clip.start,length,out.bars*4,clipId);
  const notes=new Set(notesInClip(track,clip));track.notes=track.notes.filter(n=>!notes.has(n)||n.start<clip.start+length-EPS);
  for(const n of track.notes)if(notes.has(n))n.duration=round(Math.min(n.duration,clip.start+length-n.start));
  clip.length=round(length);return ensureClips(out);
}
export function updateClip(project,trackId,clipId,{start,length,name,muted}) {
  const out=clone(project),{track,clip}=find(out,trackId,clipId),notes=new Set(notesInClip(track,clip)),offset=start-clip.start;
  space(track,start,length,out.bars*4,clipId);
  track.notes=track.notes.filter(n=>!notes.has(n)||n.start-clip.start<length-EPS);
  for(const n of track.notes)if(notes.has(n)){n.start=round(n.start+offset);n.duration=round(Math.min(n.duration,start+length-n.start))}
  Object.assign(clip,{start:round(start),length:round(length),name:String(name||clip.name).slice(0,40),muted:!!muted});
  return ensureClips(out);
}
export function removeClip(project,trackId,clipId) {
  const out=clone(project),{track,clip}=find(out,trackId,clipId),notes=new Set(notesInClip(track,clip));
  track.notes=track.notes.filter(n=>!notes.has(n));track.clips=track.clips.filter(c=>c.id!==clipId);return out;
}
export function splitClip(project,trackId,clipId,beat) {
  const out=clone(project),{track,clip}=find(out,trackId,clipId),end=clip.start+clip.length;
  if(!Number.isFinite(beat)||beat<clip.start+.25||beat>end-.25)throw Error('分割点须位于音块内部');
  const notes=notesInClip(track,clip),right={...clip,id:id(),start:round(beat),length:round(end-beat),name:clip.name+' · B'};
  for(const n of notes)if(n.start<beat&&n.start+n.duration>beat){track.notes.push({...n,id:id(),start:round(beat),duration:round(n.start+n.duration-beat)});n.duration=round(beat-n.start)}
  clip.length=round(beat-clip.start);track.clips.push(right);return {project:ensureClips(out),clipId:right.id};
}
export function resizeClipProject(project,bars,{fill='repeat'}={}) {
  if(!validBars(bars)||!['blank','repeat'].includes(fill))throw Error('工程长度或扩展方式不正确');
  const out=clone(project),oldEnd=out.bars*4,end=bars*4;
  for(const track of out.tracks){const clips=clone(track.clips),notes=clone(track.notes);
    if(end>oldEnd&&fill==='repeat')for(let offset=oldEnd;offset<end;offset+=oldEnd){for(const c of clips)if(c.start+offset<end){const next={...c,id:id(),start:c.start+offset,length:Math.min(c.length,end-c.start-offset)};delete next.patternId;track.clips.push(next)};for(const n of notes)if(n.start+offset<end)track.notes.push({...n,id:id(),start:n.start+offset,duration:Math.min(n.duration,end-n.start-offset)})}
    track.clips=track.clips.filter(c=>c.start<end-.25+EPS).map(c=>({...c,length:Math.min(c.length,end-c.start)}));
    track.notes=track.notes.filter(n=>n.start<end-.03125+EPS&&clipAt(track,n.start)).map(n=>({...n,duration:Math.min(n.duration,end-n.start)}));
  }
  if(out.loopRange){if(out.loopRange.start>=end-.25+EPS)delete out.loopRange;else out.loopRange.end=Math.min(out.loopRange.end,end)}
  out.bars=bars;resizeSections(out,end);return ensureClips(out);
}
export function mergeClipVariation(before,next,trackId,clipId) {
  const out=clone(before),{track,clip}=find(out,trackId,clipId),source=next.tracks.find(t=>t.id===trackId)||next.tracks.find(t=>t.instrument===track.instrument);
  if(!source)throw Error('生成结果缺少所选轨道');const existing=new Set(notesInClip(track,clip));
  track.notes=track.notes.filter(n=>!existing.has(n)).concat(source.notes.filter(n=>n.start>=clip.start&&n.start<=clip.start+clip.length-.03125).map(n=>({...n,id:id(),duration:Math.min(n.duration,clip.start+clip.length-n.start)})));
  return ensureClips(out);
}
