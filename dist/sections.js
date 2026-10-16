import {expandedBars} from './limits.js';
import {copy,uid,validateProject} from './music.js';
import {ensureClips,notesInClip} from './clips.js';
import {normalizeSections,SECTION_KINDS} from './sections-core.js';
import {materializedNotes,notesSignature} from './patterns-core.js';
const EPS=.00005,round=n=>+n.toFixed(4),overlap=(a,b,c,d)=>a<d-EPS&&b>c+EPS;
export {SECTION_KINDS};
export function sectionAt(project,id){const s=project.sections?.find(s=>s.id===id);if(!s)throw Error('请先选择一个歌曲段落');return s}
export function updateSection(project,{id,name,kind='custom',start,length}){const out=copy(project);if(id&&!out.sections?.some(s=>s.id===id))throw Error('段落已不存在');const section={id:id||uid(),name,kind,start,length};out.sections=normalizeSections([...(out.sections||[]).filter(s=>s.id!==id),section],out.bars*4);return{project:validateProject(out),sectionId:section.id}}
export function sectionTemplate(project,template='verse-chorus'){
 const out=copy(project),end=out.bars*4,kinds=template==='verse-chorus'?['verse','chorus']:template==='four-parts'?['intro','verse','chorus','outro']:null;if(!kinds)throw Error('歌曲骨架不正确');const length=end/kinds.length;
 out.sections=kinds.map((kind,i)=>({id:uid(),name:SECTION_KINDS[kind],kind,start:i*length,length}));return validateProject(out);
}
function sliceNote(n,a,b,{fresh=false,used}={}){const start=Math.max(n.start,a),stop=Math.min(n.start+n.duration,b);if(stop<=start+EPS)return null;if(stop-start<.03125-EPS)throw Error('段落切点产生过短音符，无法完整保留片段，请调整段落边界');const out={...n,id:fresh||used?.has(n.id)?uid():n.id,start:round(start),duration:round(stop-start)};used?.add(n.id);if(out.timingOffset!==undefined)out.timingOffset=round(Math.max(a-out.start,Math.min(out.timingOffset,b-out.start-out.duration)));return out}
function sliceClip(track,clip,a,b,{fresh=false,used,linked=false,wholeMove=false}={}){
 if(b-a<.25-EPS)throw Error('段落切点产生过短音块，请调整段落边界');const whole=Math.abs(a-clip.start)<EPS&&Math.abs(b-clip.start-clip.length)<EPS,next={...clip,id:fresh?uid():clip.id,start:round(a),length:round(b-a)};
 if(!whole||(!linked&&!wholeMove))delete next.patternId;
 let limitedTiming=0,notes=notesInClip(track,clip).map(n=>{const part=sliceNote(n,a,b,{fresh,used});if(part&&part.timingOffset!==n.timingOffset)limitedTiming++;return part}).filter(Boolean);
 if(next.patternId&&fresh)notes=materializedNotes(track._patterns.find(p=>p.id===next.patternId),next);
 return{clip:next,notes,limitedTiming};
}
// Copy/move act on every track from one frozen snapshot; no ripple or overwrite.
export function planSection(project,sectionId,{action='copy',start,linked=false,extend=false,name}={}){
 const before=validateProject(project),section=sectionAt(before,sectionId),a=section.start,b=a+section.length,out=copy(before);
 if(!['copy','move','clear','label-delete'].includes(action)||typeof linked!=='boolean'||typeof extend!=='boolean')throw Error('段落操作不正确');
 const report={tracks:0,clips:0,crossingClips:0,crossingNotes:0,linkedCopies:0,detached:0,limitedTiming:0,addedNotes:0,removedNotes:0,extended:false};
 if(action==='label-delete'){out.sections=out.sections.filter(s=>s.id!==sectionId);return{project:out,sectionId:null,report}}
 if(action!=='clear'){
  if(!Number.isInteger(start)||start<0||start%4)throw Error('目标起点须是完整小节');if(overlap(a,b,start,start+section.length))throw Error('源段落与目标范围不能重叠');
  const need=start+section.length;if(need>out.bars*4){if(!extend)throw Error('目标超出工程，可明确选择延长为留白');out.bars=expandedBars(need,out.bars);report.extended=true}
  const target={...section,id:action==='copy'?uid():section.id,name:name===undefined?(action==='copy'?section.name+' · 副本':section.name):name,start};out.sections=normalizeSections([...(out.sections||[]).filter(s=>action==='copy'||s.id!==sectionId),target],out.bars*4);
  for(const t of before.tracks)if(t.clips.some(c=>overlap(c.start,c.start+c.length,start,need)))throw Error('目标范围已有音块，不能覆盖。请先移走，或换一个空白位置');
 }
 const moved=[];
 for(const track of out.tracks){const source=before.tracks.find(t=>t.id===track.id),hit=source.clips.filter(c=>overlap(c.start,c.start+c.length,a,b));if(!hit.length)continue;report.tracks++;report.clips+=hit.length;const retained=[],pieces=[],used=new Set();source._patterns=before.patterns;
  for(const clip of source.clips){if(!hit.some(c=>c.id===clip.id)){retained.push({clip:copy(clip),notes:copy(notesInClip(source,clip))});continue}
   const left=Math.max(a,clip.start),right=Math.min(b,clip.start+clip.length),whole=left===clip.start&&right===clip.start+clip.length;if(!whole)report.crossingClips++;
   for(const n of notesInClip(source,clip))if(n.start<left-EPS&&n.start+n.duration>left+EPS||n.start<right-EPS&&n.start+n.duration>right+EPS)report.crossingNotes++;
   if(action==='copy')retained.push({clip:copy(clip),notes:copy(notesInClip(source,clip))});
   else {let first=true;for(const [lo,hi] of [[clip.start,left],[right,clip.start+clip.length]])if(hi>lo+EPS){const part=sliceClip(source,clip,lo,hi,{used});if(!first)part.clip.id=uid();first=false;retained.push(part);if(clip.patternId&&!part.clip.patternId)report.detached++;report.limitedTiming+=part.limitedTiming}}
   if(action!=='clear'){
    const part=sliceClip(source,clip,left,right,{fresh:action==='copy'||!whole,linked:action==='copy'&&linked,wholeMove:action==='move'&&whole});
    if(part.clip.patternId&&action==='copy')report.linkedCopies++;
    if(clip.patternId&&!part.clip.patternId)report.detached++;
    report.limitedTiming+=part.limitedTiming;
    const delta=start-a;part.clip.start=round(part.clip.start+delta);for(const n of part.notes)n.start=round(n.start+delta);pieces.push(part);moved.push(part.clip.id);
   }
  }
  const all=retained.concat(pieces);track.clips=all.map(x=>x.clip);track.notes=all.flatMap(x=>x.notes);
  if(track.clips.length>256)throw Error('段落操作超过每轨 256 音块上限');
  const oldIds=new Set(source.notes.map(n=>n.id)),newIds=new Set(track.notes.map(n=>n.id));report.addedNotes+=track.notes.filter(n=>!oldIds.has(n.id)).length;report.removedNotes+=source.notes.filter(n=>!newIds.has(n.id)).length;
 }
 const result=validateProject(ensureClips(out));return{project:result,sectionId:action==='copy'?result.sections.find(s=>s.start===start).id:sectionId,clipIds:moved,report};
}
// Range-only candidate merge preserves labels, settings, clips, library and outside tails.
export function mergeSectionVariation(before,next,sectionId){
 const section=sectionAt(before,sectionId),a=section.start,b=a+section.length,out=copy(before);
 for(const track of out.tracks){const src=next.tracks.find(t=>t.id===track.id)||next.tracks.find(t=>t.instrument===track.instrument);if(!src||src.instrument!==track.instrument)throw Error('候选缺少段落中的原乐器轨道');if(notesSignature(src.notes)===notesSignature(track.notes))continue;const notes=[];
  for(const n of track.notes){if(!overlap(n.start,n.start+n.duration,a,b)){notes.push(n);continue}const used=new Set();for(const [lo,hi] of [[0,a],[b,before.bars*4]]){const part=sliceNote(n,lo,hi,{used});if(part){const c=track.clips.find(c=>part.start>=c.start-EPS&&part.start<c.start+c.length-EPS);if(part.timingOffset!==undefined)part.timingOffset=round(Math.max(c.start-part.start,Math.min(n.timingOffset,c.start+c.length-part.start-part.duration)));notes.push(part)}}}
  for(const n of src.notes){if(!overlap(n.start,n.start+n.duration,a,b))continue;for(const clip of track.clips){const lo=Math.max(a,clip.start),hi=Math.min(b,clip.start+clip.length);if(hi<=lo+EPS)continue;const part=sliceNote(n,lo,hi,{fresh:true});if(part)notes.push(part)}}track.notes=notes;
 }
 return validateProject(ensureClips(out));
}
