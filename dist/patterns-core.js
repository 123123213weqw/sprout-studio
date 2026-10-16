import {MAX_BEATS} from './limits.js';
import {INSTRUMENTS} from './instruments.js';
const EPS=.00005,round=n=>+n.toFixed(4),safeId=id=>typeof id==='string'&&/^[a-zA-Z0-9_-]{1,80}$/.test(id);
export const PATTERN_LIMITS={patterns:64,notes:12000,perPattern:4000};
export function normalizePatterns(input){
 if(!Array.isArray(input)||input.length>PATTERN_LIMITS.patterns)throw Error('Pattern 库最多支持 64 个乐句');let total=0;const ids=new Set();
 return input.map(pattern=>{if(!pattern||!safeId(pattern.id)||ids.has(pattern.id)||!Object.hasOwn(INSTRUMENTS,pattern.instrument)||!Number.isFinite(pattern.length)||pattern.length<.25||pattern.length>MAX_BEATS||!Array.isArray(pattern.notes)||pattern.notes.length>PATTERN_LIMITS.perPattern)throw Error('Pattern 数据、标识或长度不正确');ids.add(pattern.id);const meta=INSTRUMENTS[pattern.instrument],noteIds=new Set(),length=round(pattern.length);
  const notes=pattern.notes.map(n=>{if(!n||!safeId(n.id)||noteIds.has(n.id)||!Number.isInteger(n.pitch)||n.pitch<24||n.pitch>108||meta.kind==='drum'&&n.pitch!==meta.pitch||!Number.isFinite(n.start)||n.start<0||!Number.isFinite(n.duration)||n.duration<.03125||n.start+n.duration>length+EPS||!Number.isFinite(n.velocity)||n.velocity<1||n.velocity>127)throw Error('Pattern 音符不合法');noteIds.add(n.id);const note={id:n.id,pitch:n.pitch,start:round(n.start),duration:round(n.duration),velocity:Math.round(n.velocity)};
   if(note.duration<.03125||note.start+note.duration>length+EPS)throw Error('Pattern 音符舍入后越界');if(n.timingOffset!==undefined){if(!Number.isFinite(n.timingOffset)||Math.abs(n.timingOffset)>.04||n.start+n.timingOffset< -EPS||n.start+n.timingOffset+n.duration>length+EPS)throw Error('Pattern 微时间偏移越界');note.timingOffset=round(n.timingOffset);if(note.start+note.timingOffset< -EPS||note.start+note.timingOffset+note.duration>length+EPS)throw Error('Pattern 微时间偏移舍入后越界')}return note;
  }).sort((a,b)=>a.start-b.start||a.pitch-b.pitch||a.id.localeCompare(b.id));total+=notes.length;if(total>PATTERN_LIMITS.notes)throw Error('Pattern 库音符超过 12000 上限');return{id:pattern.id,name:String(pattern.name||'未命名乐句').slice(0,60),instrument:pattern.instrument,kind:meta.kind,length,notes};
 });
}
// Stable 64-bit IDs are for note identity, not a security hash; collisions reject.
export function instanceNoteId(clipId,patternId,noteId){let hash=0xcbf29ce484222325n;for(const ch of `${clipId}/${patternId}/${noteId}`){hash^=BigInt(ch.charCodeAt(0));hash=BigInt.asUintN(64,hash*0x100000001b3n)}return'link_'+hash.toString(16).padStart(16,'0')}
export function patternCompatible(pattern,track){return pattern.kind===track.kind&&(pattern.kind!=='drum'||pattern.instrument===track.instrument)}
export function materializedNotes(pattern,clip){return pattern.notes.map(n=>({...n,id:instanceNoteId(clip.id,pattern.id,n.id),start:round(clip.start+n.start)}))}
export function patternInstances(project,patternId){return project.tracks.flatMap(t=>t.clips.filter(c=>c.patternId===patternId).map(c=>({trackId:t.id,trackName:t.name,clipId:c.id,clipName:c.name,start:c.start,length:c.length,muted:c.muted})))}
export function notesSignature(notes,origin=0,includeId=false){return notes.map(n=>JSON.stringify({...(includeId?{id:n.id}:{}),pitch:n.pitch,start:round(n.start-origin),duration:round(n.duration),velocity:Math.round(n.velocity),timingOffset:round(n.timingOffset||0)})).sort().join('|')}
export function synchronizePatterns(project,{strict=false}={}){
 if(project.patterns===undefined){if(project.tracks.some(t=>t.clips.some(c=>c.patternId!==undefined)))throw Error('共享音块缺少 Pattern 库');return project}
 project.patterns=normalizePatterns(project.patterns);const patterns=new Map(project.patterns.map(p=>[p.id,p]));
 for(const track of project.tracks)for(const clip of track.clips){if(clip.patternId===undefined)continue;if(!safeId(clip.patternId)||!patterns.has(clip.patternId))throw Error('共享音块引用了不存在的 Pattern');const pattern=patterns.get(clip.patternId);if(!patternCompatible(pattern,track))throw Error('Pattern 与轨道音源不兼容');const existing=track.notes.filter(n=>n.start>=clip.start-EPS&&n.start<clip.start+clip.length-EPS),expected=materializedNotes(pattern,clip);
  if(Math.abs(clip.length-pattern.length)>EPS||notesSignature(existing,clip.start,strict)!==notesSignature(expected,clip.start,strict)){if(strict)throw Error('共享 Pattern 与音块缓存不一致，拒绝恢复');delete clip.patternId;continue}
  const ids=new Set(existing.map(n=>n.id));track.notes=track.notes.filter(n=>!ids.has(n.id)).concat(expected).sort((a,b)=>a.start-b.start||a.pitch-b.pitch);
 }
 const ids=new Set();for(const t of project.tracks)for(const n of t.notes){if(ids.has(n.id))throw Error('Pattern 实例音符标识碰撞');ids.add(n.id)}project.version=3;return project;
}
export function flattenPatterns(project){const p=JSON.parse(JSON.stringify(project));delete p.patterns;p.version=2;for(const t of p.tracks)for(const c of t.clips)delete c.patternId;return p}
