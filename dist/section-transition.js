import {copy,validateProject,uid,INSTRUMENTS} from './music.js';
import {sectionAt} from './sections.js';
import {clipAt,ensureClips,notesInClip} from './clips.js';
import {notesSignature} from './patterns-core.js';
import {randomAt} from './composition.js';
const EPS=.00005,round=n=>+n.toFixed(4);
export const FILL_STYLES={gentle:'轻轻带过去',rise:'逐渐加密',break:'留半拍呼吸'};
export const FILL_DEFAULTS={style:'gentle',bars:1,energy:70,seed:1,fillGaps:false};
export function normalizeFillControls(input={}){
 if(!input||typeof input!=='object'||Array.isArray(input)||Object.keys(input).some(k=>!Object.hasOwn(FILL_DEFAULTS,k)))throw Error('过门参数不正确');
 const c={...FILL_DEFAULTS,...input};
 if(!Object.hasOwn(FILL_STYLES,c.style)||![1,2].includes(c.bars)||!Number.isInteger(c.energy)||c.energy<30||c.energy>100||!Number.isInteger(c.seed)||c.seed<1||c.seed>2147483647||typeof c.fillGaps!=='boolean')throw Error('过门须为 1 / 2 小节、能量 30–100、种子 1–2147483647');
 return c;
}
// Explicit quarter/eighth/sixteenth grids; only the final bar gets the flourish.
export function fillPositions(instrument,style,bars){
 if(!['kick','snare','hat'].includes(instrument)||!Object.hasOwn(FILL_STYLES,style)||![1,2].includes(bars))throw Error('过门鼓型不正确');
 const result=[];
 for(let bar=0;bar<bars;bar++){
  const last=bar===bars-1;let beats;
  if(!last)beats=instrument==='kick'?[0,2]:instrument==='snare'?[1,3]:Array.from({length:8},(_,i)=>i/2);
  else if(style==='gentle')beats=instrument==='kick'?[0,2]:instrument==='snare'?[1,3,3.5]:Array.from({length:8},(_,i)=>i/2);
  else if(style==='rise')beats=instrument==='kick'?[0,2,2.5,3]:instrument==='snare'?[1,2,2.25,2.5,2.75,3,3.25,3.5,3.75]:[0,.5,1,1.5,2,2.25,2.5,2.75,3,3.25,3.5,3.75];
  else beats=instrument==='kick'?[0]:instrument==='snare'?[1,2,2.5,3]:[0,.5,1,1.5,2,2.5,3];
  for(const beat of beats)result.push(bar*4+beat);
 }
 return result;
}
export function planSectionFill(project,sectionId,{trackIds,controls={},idFactory=uid}={}){
 const before=validateProject(copy(project)),section=sectionAt(before,sectionId),c=normalizeFillControls(controls),end=section.start+section.length,start=end-c.bars*4;
 if(start<section.start)throw Error('段落不够长，不能放入这次过门');
 if(!Array.isArray(trackIds)||!trackIds.length||new Set(trackIds).size!==trackIds.length||trackIds.some(id=>!before.tracks.some(t=>t.id===id&&t.kind==='drum')))throw Error('请选择至少一条现有鼓轨，不得重复或选择旋律轨');
 if(typeof idFactory!=='function')throw Error('新标识生成器不正确');
 const out=copy(before),reserved=new Set([...(before.patterns||[]).flatMap(p=>[p.id,...p.notes.map(n=>n.id)]),...before.tracks.flatMap(t=>[t.id,...t.clips.map(x=>x.id),...t.notes.map(x=>x.id)]),...(before.sections||[]).map(s=>s.id)]);
 const fresh=()=>{for(let i=0;i<50;i++){const id=idFactory();if(typeof id==='string'&&/^[a-zA-Z0-9_-]{1,80}$/.test(id)&&!reserved.has(id)){reserved.add(id);return id}}throw Error('无法生成唯一标识，没有修改工程')};
 const report={start,end,tracks:[],addedNotes:0,removedNotes:0,trimmedNotes:0,limitedTiming:0,newClips:0,detached:0};
 for(const track of out.tracks.filter(t=>trackIds.includes(t.id))){
  const old=before.tracks.find(t=>t.id===track.id),row={id:track.id,name:track.name,instrument:track.instrument,added:0,removed:0,trimmed:0,newClips:0,detached:0,muted:track.muted,solo:track.solo,mutedHits:0},kept=[];
  for(const note of track.notes){
   const stop=round(note.start+note.duration);
   if(stop<=start+EPS||note.start>=end-EPS){kept.push(note);continue}
   const pieces=[];
   if(note.start<start-EPS)pieces.push({a:note.start,b:start});
   if(stop>end+EPS)pieces.push({a:end,b:stop});
   if(!pieces.length){row.removed++;continue}row.trimmed++;
   for(const [i,piece] of pieces.entries()){
    if(piece.b-piece.a<.03125-EPS)throw Error('边界长音会留下过短片段，请先调整音符');
    const n={...note,id:i?fresh():note.id,start:round(piece.a),duration:round(piece.b-piece.a)};
    if(n.timingOffset!==undefined){const offset=round(Math.max(piece.a-n.start,Math.min(n.timingOffset,piece.b-n.start-n.duration)));if(offset!==n.timingOffset)report.limitedTiming++;n.timingOffset=offset}
    kept.push(n);
   }
  }
  track.notes=kept;
  const positions=fillPositions(track.instrument,c.style,c.bars).map(x=>round(start+x)),gaps=[];let cursor=start;
  for(const clip of track.clips){if(clip.start+clip.length<=start+EPS||clip.start>=end-EPS)continue;if(clip.start>cursor+EPS)gaps.push({start:cursor,end:Math.min(end,clip.start)});cursor=Math.max(cursor,Math.min(end,clip.start+clip.length))}
  if(cursor<end-EPS)gaps.push({start:cursor,end});
  for(const gap of gaps.filter(g=>positions.some(p=>p>=g.start-EPS&&p<g.end-EPS))){
   if(!c.fillGaps)throw Error(`“${track.name}”过门位置有空白。可明确勾选“在空白处新建音块”`);
   if(gap.end-gap.start<.25-EPS)throw Error('过门空隙不足 1/4 拍，不能新建音块');
   track.clips.push({id:fresh(),name:'过门 · '+FILL_STYLES[c.style],start:round(gap.start),length:round(gap.end-gap.start),muted:false});row.newClips++;
  }
  track.clips.sort((a,b)=>a.start-b.start);
  for(const beat of positions){
   const clip=clipAt(track,beat),duration=track.instrument==='hat'?.0625:.125;
   if(!clip||beat+duration>Math.min(end,clip.start+clip.length)+EPS)throw Error('过门音符跨出音块边缘，请先调整音块，不会自动缩短');
   const accent=beat%1===0?1:.76,base=track.instrument==='hat'?92:118,jitter=Math.round((randomAt(c.seed,`${track.id}/${beat}`)-.5)*8);
   track.notes.push({id:fresh(),pitch:INSTRUMENTS[track.instrument].pitch,start:beat,duration,velocity:Math.max(1,Math.min(127,Math.round(base*c.energy/100*accent)+jitter))});row.added++;if(clip.muted)row.mutedHits++;
  }
  track.notes.sort((a,b)=>a.start-b.start||a.pitch-b.pitch||a.id.localeCompare(b.id));
  for(const clip of track.clips.filter(x=>x.patternId)){
   const previous=old.clips.find(x=>x.id===clip.id);if(notesSignature(notesInClip(track,clip),0,true)!==notesSignature(notesInClip(old,previous),0,true)){delete clip.patternId;row.detached++}
  }
  if(track.notes.length>4000||track.clips.length>256)throw Error('过门超过每轨 4000 音符 / 256 音块上限');
  report.tracks.push(row);report.addedNotes+=row.added;report.removedNotes+=row.removed;report.trimmedNotes+=row.trimmed;report.newClips+=row.newClips;report.detached+=row.detached;
 }
 if(out.tracks.reduce((n,t)=>n+t.notes.length,0)>12000)throw Error('过门超过全工程 12000 音符上限');
 const next=validateProject(ensureClips(out,{strict:true}));
 if(new TextEncoder().encode(JSON.stringify(next)).length>3000000)throw Error('过门后工程超过 3 MB 保存上限，没有修改音乐');
 return{project:next,controls:c,section:copy(section),report};
}
