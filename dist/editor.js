import {MAX_BEATS} from './limits.js';
import {KEYS,copy,uid,validateProject,noteName} from './music.js';
import {ensureClips,clipAt} from './clips.js';
const EPS=.00005,round=value=>+value.toFixed(4);
const finite=(value,label)=>{if(!Number.isFinite(value))throw Error(label+'必须是有效数字');return value};
function find(project,trackId){const track=project.tracks.find(t=>t.id===trackId);if(!track)throw Error('轨道已不存在');return track}
function finish(project,track,expected){
 if(track.notes.length>4000||project.tracks.reduce((n,t)=>n+t.notes.length,0)>12000)throw Error('音符数量超过工程上限');
 for(const n of expected){
  if(n.pitch<24||n.pitch>108||!Number.isInteger(n.pitch))throw Error('音高超出 C1–C8 范围');
  if(n.start<0||n.duration<.03125-EPS||n.start+n.duration>project.bars*4+EPS)throw Error('音符超出工程范围，整组没有移动');
  const c=clipAt(track,n.start);if(c&&n.start+n.duration>c.start+c.length+EPS)throw Error('音符会跨过音块终点，请先延长音块或换一个位置');
 }
 const lengths=new Map(track.notes.map(n=>[n.id,n.duration]));ensureClips(project);
 if(track.notes.some(n=>Math.abs(n.duration-lengths.get(n.id))>EPS))throw Error('空隙放不下完整音符，请先建立足够长的音块');
 return validateProject(project);
}
export function selectedNotes(track,ids){const set=new Set(ids);return track.notes.filter(n=>set.has(n.id))}
export function selectInRectangle(track,{start,end,low,high}){return track.notes.filter(n=>n.start<end&&n.start+n.duration>start&&n.pitch>=low&&n.pitch<=high).map(n=>n.id)}
// All-or-nothing edits retain IDs and durations unless a change was explicitly requested.
export function transformNotes(project,trackId,ids,{deltaBeat=0,deltaPitch=0,deltaDuration=0,duration,velocity,quantize,duplicate=false}={}){
 const out=copy(project),track=find(out,trackId),notes=selectedNotes(track,ids);if(!notes.length)throw Error('请先选择音符');
 [deltaBeat,deltaPitch,deltaDuration].forEach((v,i)=>finite(v,['移动拍数','移调','长度变化'][i]));if(!Number.isInteger(deltaPitch))throw Error('移调必须是整数半音');
 if(duration!==undefined)finite(duration,'长度');if(velocity!==undefined&&(finite(velocity,'力度')<1||velocity>127))throw Error('力度必须在 1–127 之间');
 if(quantize!==undefined&&![.25,.5,1].includes(quantize))throw Error('不支持这个网格');
 const changed=notes.map(n=>{const next={...n,id:duplicate?uid():n.id,start:round(n.start+deltaBeat),pitch:n.pitch+deltaPitch,duration:round(duration??n.duration+deltaDuration),velocity:velocity===undefined?n.velocity:Math.round(velocity)};
  if(track.kind==='drum'&&deltaPitch)throw Error('鼓音符不能移调，请换用其他鼓轨');
  if(quantize){next.start=round(Math.round(next.start/quantize)*quantize);next.duration=round(Math.max(quantize,Math.round(next.duration/quantize)*quantize))}return next});
 if(duplicate)track.notes.push(...changed);else{const map=new Map(changed.map(n=>[n.id,n]));track.notes=track.notes.map(n=>map.get(n.id)||n)}
 return{project:finish(out,track,changed),ids:changed.map(n=>n.id)};
}
export function copyNotes(track,ids){const notes=selectedNotes(track,ids);if(!notes.length)throw Error('请先选择音符');const start=Math.min(...notes.map(n=>n.start)),end=Math.max(...notes.map(n=>n.start+n.duration));return{kind:track.kind,instrument:track.instrument,span:round(end-start),notes:notes.map(n=>({...n,start:round(n.start-start)}))}}
export function pasteNotes(project,trackId,clipboard,start){
 finite(start,'粘贴位置');const track=find(project,trackId);if(!clipboard?.notes?.length)throw Error('先复制一些音符');
 if(clipboard.kind!==track.kind||(track.kind==='drum'&&clipboard.instrument!==track.instrument))throw Error('只支持同类乐器间粘贴；鼓需要使用同一种音源');
 return insertNotes(project,trackId,clipboard.notes.map(n=>({...n,start:round(start+n.start),id:uid()})));
}
export function removeNotes(project,trackId,ids){const out=copy(project),t=find(out,trackId),set=new Set(ids);t.notes=t.notes.filter(n=>!set.has(n.id));return validateProject(out)}
export function insertNotes(project,trackId,notes,{replaceRange,clipId,rejectOverlap=false}={}){
 const out=copy(project),track=find(out,trackId),added=notes.map(n=>({...n,id:uid()}));
 if(clipId){const c=track.clips.find(c=>c.id===clipId);if(!c)throw Error('请重新选择音块');if(added.some(n=>n.start<c.start-EPS||n.start+n.duration>c.start+c.length+EPS))throw Error('和弦超出选中音块，请减小长度或延长音块')}
 if(replaceRange){const [start,end]=replaceRange;finite(start,'替换起点');finite(end,'替换终点');if(start<0||end<=start||end>out.bars*4)throw Error('替换范围无效');
  if(clipId){const c=track.clips.find(c=>c.id===clipId);if(start<c.start-EPS||end>c.start+c.length+EPS)throw Error('替换范围超出所选音块')}
  track.notes=track.notes.flatMap(n=>{const stop=n.start+n.duration;if(stop<=start+EPS||n.start>=end-EPS)return[n];const parts=[];
   if((start>n.start+EPS&&start-n.start<.03125-EPS)||(stop>end+EPS&&stop-end<.03125-EPS))throw Error('替换切点离音符边缘太近，无法保留完整的范围外尾部，请调整范围');
   if(start-n.start>=.03125-EPS)parts.push({...n,duration:round(start-n.start)});
   if(stop-end>=.03125-EPS)parts.push({...n,id:parts.length?uid():n.id,start:end,duration:round(stop-end)});return parts});
 }
 if(rejectOverlap&&added.some(a=>track.notes.some(b=>a.pitch===b.pitch&&a.start<b.start+b.duration-EPS&&a.start+a.duration>b.start+EPS)))throw Error('这里有同音高的音符。换一个位置，或选择“替换这个范围”');
 track.notes.push(...added);return{project:finish(out,track,added),ids:added.map(n=>n.id)};
}
export function diatonicChord(key,degree,{octave=3,seventh=false,inversion=0}={}){
 const k=KEYS[key];if(!k||!Number.isInteger(degree)||degree<0||degree>6)throw Error('无效的调性或和弦级数');
 if(!Number.isInteger(octave)||octave<2||octave>6)throw Error('八度须为 2–6');const voices=seventh?4:3;if(!Number.isInteger(inversion)||inversion<0||inversion>=voices)throw Error('无效转位');
 const pitch=d=>(octave+1)*12+(k.root%12)+k.scale[d%7]+12*Math.floor(d/7);
 const base=[0,2,4,...(seventh?[6]:[])].map(offset=>pitch(degree+offset)),third=base[1]-base[0],fifth=base[2]-base[0],quality=fifth===6?'dim':third===3?'minor':'major',root=noteName(base[0]).replace(/\d+$/,'');
 const seventhInterval=seventh?base[3]-base[0]:null,suffix=quality==='dim'?(seventh?'m7♭5':'dim'):seventh?(quality==='minor'?'m7':seventhInterval===11?'maj7':'7'):quality==='minor'?'m':'';
 const pitches=base.slice(inversion).concat(base.slice(0,inversion).map(p=>p+12));if(pitches.some(p=>p>108))throw Error('这个八度与转位超出音域');
 return{degree,quality,label:root+suffix,pitches};
}
export function chordPlan(key,{degrees=[0],start=0,length=4,octave=3,seventh=false,inversion=0,mode='block',step=.5,velocity=78}={}){
 finite(start,'起点');finite(length,'长度');if(!Array.isArray(degrees)||!degrees.length||degrees.length>16||length<.25||start<0||start+length>MAX_BEATS)throw Error('和弦范围不合法');
 if(!['block','up','down'].includes(mode)||![.25,.5,1].includes(step)||!Number.isFinite(velocity)||velocity<1||velocity>127)throw Error('和弦参数不合法');
 const span=length/degrees.length,chords=degrees.map(d=>diatonicChord(key,d,{octave,seventh,inversion})),notes=[];
 if(mode!=='block'&&span<step-EPS)throw Error('每个和弦的长度不能小于一个分解步长');
 chords.forEach((chord,i)=>{const at=start+i*span;if(mode==='block')chord.pitches.forEach(pitch=>notes.push({pitch,start:round(at),duration:round(span),velocity:Math.round(velocity)}));else{const pitches=mode==='down'?[...chord.pitches].reverse():chord.pitches;for(let j=0;j*step<span-EPS;j++)notes.push({pitch:pitches[j%pitches.length],start:round(at+j*step),duration:round(Math.min(step*.85,span-j*step)),velocity:Math.round(velocity)})}});
 if(notes.some(n=>n.duration<.03125))throw Error('和弦切分太短，请增加长度');return{notes,chords,labels:chords.map(c=>c.label),start,length};
}
