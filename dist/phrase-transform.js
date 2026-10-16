import {copy,validateProject,KEYS,performanceBeat} from './music.js';
import {notesInClip} from './clips.js';
import {expandedBars} from './limits.js';
import {performanceOverlaps} from './performance.js';
const EPS=.00005,MIN=.03125,round=n=>+n.toFixed(4);
export const PHRASE_DEFAULTS={ratio:1,reverse:false,transpose:0,scale:'keep',timing:'follow',extend:false};
export function normalizePhraseControls(input={}){
 if(!input||typeof input!=='object'||Array.isArray(input)||Object.keys(input).some(k=>!Object.hasOwn(PHRASE_DEFAULTS,k)))throw Error('乐句变换参数不正确');
 const c={...PHRASE_DEFAULTS,...input};
 if(![.5,1,2].includes(c.ratio)||typeof c.reverse!=='boolean'||typeof c.extend!=='boolean'||!Number.isInteger(c.transpose)||c.transpose< -24||c.transpose>24||!['keep',...Object.keys(KEYS)].includes(c.scale)||!['follow','keep','clear'].includes(c.timing))throw Error('请检查节奏倍数、倒序、半音或调内吸附参数');return c;
}
export function nearestScalePitch(pitch,key){
 if(!Number.isInteger(pitch)||pitch<24||pitch>108||!Object.hasOwn(KEYS,key))throw Error('音高或目标调性不正确');const k=KEYS[key];
 let best=null,distance=Infinity;for(let p=24;p<=108;p++)if(k.scale.includes(((p-k.root)%12+12)%12)){const d=Math.abs(p-pitch);if(d<distance){best=p;distance=d}}return best;
}
const differs=(a,b)=>a.pitch!==b.pitch||a.start!==b.start||a.duration!==b.duration||(a.timingOffset||0)!==(b.timingOffset||0)||Object.hasOwn(a,'timingOffset')!==Object.hasOwn(b,'timingOffset');
// Shared note math for local clips and explicitly edited relative Pattern sources.
export function transformPhraseNotes(notes,{start=0,length,kind='tonal',controls={}}={}){
 const c=normalizePhraseControls(controls),nextLength=round(length*c.ratio),end=round(start+nextLength);
 if(!Array.isArray(notes)||!Number.isFinite(start)||start<0||!Number.isFinite(length)||length<.25||length>256||!['tonal','drum'].includes(kind)||nextLength<.25||nextLength>256)throw Error('变换后音块长度须为 0.25–256 拍');
 if(kind==='drum'&&(c.transpose||c.scale!=='keep'))throw Error('鼓只变换节奏，不改变鼓音高或套用旋律音阶');let snapped=0;const ids=new Set();
 const transformed=notes.map(old=>{
  if(!old||typeof old.id!=='string'||!/^[a-zA-Z0-9_-]{1,80}$/.test(old.id)||ids.has(old.id)||!Number.isInteger(old.pitch)||old.pitch<24||old.pitch>108||!Number.isFinite(old.start)||!Number.isFinite(old.duration)||old.duration<MIN||!Number.isInteger(old.velocity)||old.velocity<1||old.velocity>127||old.start<start-EPS||old.start+old.duration>start+length+EPS||old.timingOffset!==undefined&&(!Number.isFinite(old.timingOffset)||Math.abs(old.timingOffset)>.04)||old.start+(old.timingOffset||0)<start-EPS||old.start+(old.timingOffset||0)+old.duration>start+length+EPS)throw Error('源音符 / 标识 / 微偏移数据不正确');ids.add(old.id);
  const n=copy(old),relative=round(old.start-start);n.duration=round(old.duration*c.ratio);n.start=round(start+(c.reverse?length-relative-old.duration:relative)*c.ratio);
  const pitch=old.pitch+c.transpose;if(pitch<24||pitch>108)throw Error('移调越过 24–108 音高边界；不会自动折返八度或裁掉音符');
  n.pitch=c.scale==='keep'?pitch:nearestScalePitch(pitch,c.scale);if(n.pitch!==pitch)snapped++;
  if(c.timing==='clear')delete n.timingOffset;else if(c.timing==='follow'&&old.timingOffset!==undefined)n.timingOffset=round(old.timingOffset*c.ratio*(c.reverse?-1:1));
  if(n.duration<MIN||n.start<start-EPS||n.start+n.duration>end+EPS||Math.abs(n.timingOffset||0)>.04||n.start+(n.timingOffset||0)<start-EPS||n.start+(n.timingOffset||0)+n.duration>end+EPS)throw Error('变换后音符 / 微偏移过短或越界；整块拒绝，可选择清除微偏移或减少变换');
  return differs(old,n)?n:copy(old);
 });return{notes:transformed,length:nextLength,snapped};
}
// A local note-domain transformation. No source mutation, audio reversal, ripple or generation.
export function planPhraseTransform(project,trackId,clipId,{controls={}}={}){
 const before=validateProject(project),c=normalizePhraseControls(controls),oldTrack=before.tracks.find(t=>t.id===trackId),oldClip=oldTrack?.clips.find(x=>x.id===clipId);
 if(!oldClip)throw Error('先选择仍存在的音块');if(oldTrack.kind==='drum'&&(c.transpose||c.scale!=='keep'))throw Error('鼓只变换节奏，不改变鼓音高或套用旋律音阶');
 const source=notesInClip(oldTrack,oldClip),length=round(oldClip.length*c.ratio),end=round(oldClip.start+length);
 if(length<.25||length>256)throw Error('变换后音块长度须为 0.25–256 拍');
 if(end>before.bars*4+EPS&&!c.extend)throw Error('变换超出工程，请明确勾选空白延长');
 const bars=end>before.bars*4+EPS?expandedBars(end,before.bars):before.bars;
 if(oldTrack.clips.some(x=>x.id!==clipId&&oldClip.start<x.start+x.length-EPS&&end>x.start+EPS))throw Error('变长后会碰到其他音块（空块也占位置）；整块没有改动');
 const out=copy(before),track=out.tracks.find(t=>t.id===trackId),clip=track.clips.find(x=>x.id===clipId),selected=new Set(source.map(n=>n.id)),result=transformPhraseNotes(source,{start:oldClip.start,length:oldClip.length,kind:oldTrack.kind,controls:c}),transformed=new Map(result.notes.map(n=>[n.id,n])),snapped=result.snapped;
 const changes=source.filter(n=>differs(n,transformed.get(n.id))).map(n=>({id:n.id,before:copy(n),after:copy(transformed.get(n.id))}));
 clip.length=length;track.notes=track.notes.map(n=>selected.has(n.id)?transformed.get(n.id):n);out.bars=bars;
 const clipChanged=length!==oldClip.length,changed=clipChanged||changes.length>0,detached=!!oldClip.patternId&&changed;
 if(detached)delete clip.patternId;
 const next=changed?validateProject(out):copy(before);
 if(new TextEncoder().encode(JSON.stringify(next)).length>3000000)throw Error('变换后工程超过 3 MB 保存上限，没有改动');
 const nextTrack=next.tracks.find(t=>t.id===trackId),nextClip=nextTrack.clips.find(x=>x.id===clipId);
 for(const x of changes){x.beatBefore=performanceBeat(x.before,before.swing,oldClip);x.beatAfter=performanceBeat(x.after,next.swing,nextClip)}
 const overlapsBefore=performanceOverlaps(oldTrack,before.swing,[...selected]),overlapsAfter=performanceOverlaps(nextTrack,next.swing,[...selected]);
 return{project:next,controls:c,trackId,clipId,changes,clipBefore:copy(oldClip),clipAfter:copy(nextClip),report:{changed:!!changed,targetNotes:source.length,changedNotes:changes.length,pitchChanged:changes.filter(x=>x.before.pitch!==x.after.pitch).length,moved:changes.filter(x=>x.before.start!==x.after.start).length,durationChanged:changes.filter(x=>x.before.duration!==x.after.duration).length,timingChanged:changes.filter(x=>(x.before.timingOffset||0)!==(x.after.timingOffset||0)||Object.hasOwn(x.before,'timingOffset')!==Object.hasOwn(x.after,'timingOffset')).length,snapped,detached,clipChanged,barsBefore:before.bars,barsAfter:bars,overlapsBefore,overlapsAfter}};
}
