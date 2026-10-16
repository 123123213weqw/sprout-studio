import {expandedBars} from './limits.js';
import {normalizePatterns,patternCompatible,materializedNotes,patternInstances,notesSignature,flattenPatterns} from './patterns-core.js';
import {ensureClips,notesInClip,createClip} from './clips.js';
import {copy,uid,validateProject} from './music.js';
export {patternInstances,patternCompatible,flattenPatterns} from './patterns-core.js';
const EPS=.00005,round=n=>+n.toFixed(4),clone=p=>ensureClips(copy(p));
function findPattern(p,id){const pattern=p.patterns?.find(x=>x.id===id);if(!pattern)throw Error('请先选择一个 Pattern');return pattern}
function findClip(p,trackId,clipId){const track=p.tracks.find(t=>t.id===trackId),clip=track?.clips.find(c=>c.id===clipId);if(!clip)throw Error('音块已不存在');return{track,clip}}
function bind(track,clip,pattern){const old=new Set(notesInClip(track,clip));track.notes=track.notes.filter(n=>!old.has(n));clip.patternId=pattern.id;clip.length=pattern.length;track.notes.push(...materializedNotes(pattern,clip))}
export function capturePattern(project,trackId,clipId,{name,linkSource=false}={}){
 const p=clone(project),{track,clip}=findClip(p,trackId,clipId);if(typeof linkSource!=='boolean')throw Error('关联参数不正确');const pattern=normalizePatterns([{id:uid(),name:name||clip.name,instrument:track.instrument,length:clip.length,notes:notesInClip(track,clip).map(n=>({...n,id:uid(),start:round(n.start-clip.start)}))}])[0];p.patterns||=[];p.patterns.push(pattern);p.version=3;if(linkSource)bind(track,clip,pattern);return{project:validateProject(ensureClips(p)),patternId:pattern.id};
}
export function placePattern(project,patternId,trackId,start,{linked=true,extend=false}={}){
 const p=clone(project),pattern=findPattern(p,patternId),track=p.tracks.find(t=>t.id===trackId);if(!track||!patternCompatible(pattern,track))throw Error('Pattern 与目标音源不兼容；鼓只可放入同种鼓轨');if(!Number.isFinite(start)||start<0||typeof linked!=='boolean'||typeof extend!=='boolean')throw Error('放置位置或关联方式不正确');
 if(start+pattern.length>p.bars*4+EPS){if(!extend)throw Error('放置超出工程，可明确选择空白延长');p.bars=expandedBars(start+pattern.length,p.bars)}
 const created=createClip(p,trackId,start,pattern.length),out=created.project,{track:target,clip}=findClip(out,trackId,created.clipId);clip.name=pattern.name.slice(0,40);if(linked)bind(target,clip,pattern);else target.notes.push(...pattern.notes.map(n=>({...n,id:uid(),start:round(start+n.start)})));return{project:validateProject(ensureClips(out)),clipId:clip.id,extended:out.bars!==project.bars};
}
export function linkClip(project,patternId,trackId,clipId,{replace=false}={}){
 if(typeof replace!=='boolean')throw Error('替换参数不正确');
 const p=clone(project),pattern=findPattern(p,patternId),{track,clip}=findClip(p,trackId,clipId);if(!patternCompatible(pattern,track))throw Error('Pattern 与目标轨道不兼容');if(Math.abs(clip.length-pattern.length)>EPS)throw Error('关联音块须与 Pattern 等长');if(!replace&&notesSignature(notesInClip(track,clip),clip.start)!==notesSignature(pattern.notes))throw Error('当前音块内容不同。只能明确替换内容后关联');bind(track,clip,pattern);return validateProject(ensureClips(p));
}
export function detachPatternClip(project,trackId,clipId){const p=clone(project),{clip}=findClip(p,trackId,clipId);delete clip.patternId;return validateProject(p)}
export function updatePattern(project,patternId,changes){
 const p=clone(project),source=findPattern(p,patternId);if(!changes||typeof changes!=='object'||Object.keys(changes).some(key=>!['name','length','notes'].includes(key)))throw Error('共享 Pattern 修改参数不正确');const next=normalizePatterns([{...source,...copy(changes)}])[0],instances=patternInstances(p,patternId);p.patterns=p.patterns.map(pattern=>pattern.id===patternId?next:pattern);
 for(const ref of instances){const {track,clip}=findClip(p,ref.trackId,ref.clipId);bind(track,clip,next)}
 return{project:validateProject(ensureClips(p)),affected:instances,patternId};
}
export function removePattern(project,patternId,{detach=false}={}){
 if(typeof detach!=='boolean')throw Error('独立化参数不正确');
 const p=clone(project);findPattern(p,patternId);const refs=patternInstances(p,patternId);if(refs.length&&!detach)throw Error('仍有共享音块使用这个 Pattern，请先独立化或明确保留音符并解除全部关联');for(const ref of refs)delete findClip(p,ref.trackId,ref.clipId).clip.patternId;p.patterns=p.patterns.filter(x=>x.id!==patternId);return validateProject(p);
}
export function reconcilePatternLibrary(before,next){
 const p=flattenPatterns(next);if(before.patterns!==undefined){p.version=3;p.patterns=copy(before.patterns);for(const t of p.tracks){const old=before.tracks.find(x=>x.id===t.id);for(const c of t.clips){const previous=old?.clips.find(x=>x.id===c.id);if(previous?.patternId)c.patternId=previous.patternId}}}return validateProject(ensureClips(p));
}
