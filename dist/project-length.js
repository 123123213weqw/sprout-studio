import {copy,validateProject,resizeProject} from './music.js';
import {validBars} from './limits.js';
export function planProjectLength(project,bars,{fill='blank'}={}){
 if(!validBars(bars)||!['blank','repeat'].includes(fill))throw Error('工程长度或扩展方式不正确');const before=validateProject(project),out=validateProject(resizeProject(before,bars,{fill}));
 const oldNotes=before.tracks.flatMap(t=>t.notes),notes=out.tracks.flatMap(t=>t.notes),oldClips=before.tracks.flatMap(t=>t.clips),clips=out.tracks.flatMap(t=>t.clips),noteIds=new Set(notes.map(n=>n.id)),oldIds=new Set(oldNotes.map(n=>n.id)),clipIds=new Set(clips.map(c=>c.id)),oldClipIds=new Set(oldClips.map(c=>c.id));
 const oldNoteMap=new Map(oldNotes.map(n=>[n.id,n])),oldClipMap=new Map(oldClips.map(c=>[c.id,c])),clipMap=new Map(clips.map(c=>[c.id,c]));
 const report={before:before.bars,after:bars,fill,addedNotes:notes.filter(n=>!oldIds.has(n.id)).length,removedNotes:oldNotes.filter(n=>!noteIds.has(n.id)).length,shortenedNotes:notes.filter(n=>{const old=oldNoteMap.get(n.id);return old&&n.duration<old.duration-.00005}).length,addedClips:clips.filter(c=>!oldClipIds.has(c.id)).length,removedClips:oldClips.filter(c=>!clipIds.has(c.id)).length,shortenedClips:clips.filter(c=>{const old=oldClipMap.get(c.id);return old&&c.length<old.length-.00005}).length,detached:oldClips.filter(c=>c.patternId&&clipMap.has(c.id)&&!clipMap.get(c.id).patternId).length,sectionsRemoved:(before.sections||[]).filter(s=>!out.sections?.some(n=>n.id===s.id)).length,sectionsTrimmed:(out.sections||[]).filter(s=>{const old=before.sections?.find(o=>o.id===s.id);return old&&s.length<old.length}).length,rangeChanged:JSON.stringify(before.loopRange)!==JSON.stringify(out.loopRange),seconds:bars*4*60/out.bpm};
 return{project:copy(out),report};
}
