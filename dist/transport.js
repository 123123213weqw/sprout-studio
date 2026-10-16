import {audibleNotes,clipAt} from './clips.js';
import {performanceBeat} from './music.js';
import {normalizeRange} from './ranges.js';
export {normalizeRange,windowAtTime} from './ranges.js';
const EPS=.00005,round=n=>+n.toFixed(4);
export function playbackPlan(project,{range,trackIds,from}={}){
 const window=normalizeRange(range,project.bars*4),ids=trackIds?new Set(trackIds):null;
 if(from!==undefined&&(!Number.isFinite(from)||from<window.start-EPS||from>window.end+EPS))throw Error('播放定位须在练习范围内');const left=from??window.start;
 if(trackIds&&(!Array.isArray(trackIds)||!trackIds.length||trackIds.some(id=>!project.tracks.some(t=>t.id===id))))throw Error('预览轨道不存在');
 const events=[];for(const t of project.tracks){if(ids&&!ids.has(t.id))continue;for(const n of audibleNotes(t)){
  const originalBeat=performanceBeat(n,project.swing,clipAt(t,n.start)),end=Math.min(originalBeat+n.duration,window.end),beat=Math.max(originalBeat,left);
  if(end-beat<=EPS)continue;
  events.push({t,n:{...n,duration:round(end-beat)},beat:round(beat),originalBeat,resumed:originalBeat<left-EPS});
 }}events.sort((a,b)=>a.beat-b.beat||a.n.pitch-b.n.pitch);
 const metronome=[];for(let beat=Math.ceil(left-EPS);beat<window.end-EPS;beat++)metronome.push({beat,metro:true,accent:beat%4===0});
 return{range:window,events,metronome,length:window.end-window.start,seconds:(window.end-window.start)*60/project.bpm};
}
export function timelineEvents(plan){return[...plan.events,...plan.metronome].sort((a,b)=>a.beat-b.beat||Number(!!b.metro)-Number(!!a.metro))}
