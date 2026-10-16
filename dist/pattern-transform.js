import {copy,validateProject} from './music.js';
import {normalizePhraseControls,transformPhraseNotes} from './phrase-transform.js';
import {patternInstances,updatePattern} from './patterns.js';
import {notesInClip} from './clips.js';
import {expandedBars} from './limits.js';
import {performanceOverlaps} from './performance.js';
const EPS=.00005;
// All references are included, even muted tracks/clips; never silently detach a subset.
export function planPatternTransform(project,patternId,{controls={}}={}){
 const before=validateProject(copy(project)),source=before.patterns?.find(p=>p.id===patternId);if(!source)throw Error('请先选择仍存在的源乐句');
 const c=normalizePhraseControls(controls),transformed=transformPhraseNotes(source.notes,{length:source.length,kind:source.kind,controls:c}),refs=patternInstances(before,patternId),changes=source.notes.flatMap((n,i)=>JSON.stringify(n)===JSON.stringify(transformed.notes[i])?[]:[{id:n.id,before:copy(n),after:copy(transformed.notes[i])}]);
 const requiredEnd=refs.reduce((n,r)=>Math.max(n,r.start+transformed.length),before.bars*4);if(requiredEnd>before.bars*4+EPS&&!c.extend)throw Error('有共享实例会超出工程，请明确勾选空白延长');
 const bars=requiredEnd>before.bars*4+EPS?expandedBars(requiredEnd,before.bars):before.bars;
 for(const ref of refs){const track=before.tracks.find(t=>t.id===ref.trackId);if(track.clips.some(x=>x.id!==ref.clipId&&ref.start<x.start+x.length-EPS&&ref.start+transformed.length>x.start+EPS))throw Error(`“${track.name}”第 ${ref.start/4+1} 小节实例变长会碰到其他音块（空块也占位置），全部未改`)}
 const changed=transformed.length!==source.length||changes.length>0,extended=copy(before);extended.bars=bars;
 const next=changed?updatePattern(extended,patternId,{length:transformed.length,notes:transformed.notes}).project:copy(before);
 if(new TextEncoder().encode(JSON.stringify(next)).length>3000000)throw Error('共享变换后工程超过 3 MB 保存上限，没有改动');
 const after=next.patterns.find(p=>p.id===patternId),affected=refs.map(ref=>{const oldTrack=before.tracks.find(t=>t.id===ref.trackId),track=next.tracks.find(t=>t.id===ref.trackId),clip=track.clips.find(c=>c.id===ref.clipId),ids=notesInClip(track,clip).map(n=>n.id);return{...copy(ref),lengthBefore:ref.length,lengthAfter:clip.length,trackMuted:track.muted,trackSolo:track.solo,noteCount:ids.length}});
 const tracks=[...new Set(refs.map(r=>r.trackId))].map(id=>{const track=next.tracks.find(t=>t.id===id),oldTrack=before.tracks.find(t=>t.id===id),selected=new Set(refs.filter(r=>r.trackId===id).map(r=>r.clipId)),ids=track.clips.filter(c=>selected.has(c.id)).flatMap(c=>notesInClip(track,c).map(n=>n.id));return{id,name:track.name,overlapsBefore:performanceOverlaps(oldTrack,before.swing,ids).count,overlapsAfter:performanceOverlaps(track,next.swing,ids).count}});
 return{project:next,controls:c,patternId,tracks,sourceBefore:copy(source),sourceAfter:copy(after),changes,affected,report:{changed,sourceNotes:source.notes.length,changedSourceNotes:changes.length,instances:refs.length,changedInstances:changed?refs.length:0,instanceNotes:refs.length*source.notes.length,snapped:transformed.snapped,pitchChanged:changes.filter(x=>x.before.pitch!==x.after.pitch).length,moved:changes.filter(x=>x.before.start!==x.after.start).length,durationChanged:changes.filter(x=>x.before.duration!==x.after.duration).length,timingChanged:changes.filter(x=>(x.before.timingOffset||0)!==(x.after.timingOffset||0)||Object.hasOwn(x.before,'timingOffset')!==Object.hasOwn(x.after,'timingOffset')).length,lengthBefore:source.length,lengthAfter:after.length,barsBefore:before.bars,barsAfter:next.bars}};
}
