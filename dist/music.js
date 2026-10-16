import {normalizeSampler,samplePreset} from './sampler-core.js';
import {BAR_LENGTHS,validBars} from './limits.js';
import {INSTRUMENTS} from './instruments.js';
import {normalizeSound} from './sound.js';
import {normalizeControls,progressionFor,voiceLead,applyPerformance} from './composition.js';
import {ensureClips,resizeClipProject,audibleNotes,clipAt} from './clips.js';
import {normalizeRange} from './ranges.js';
import {normalizeSections} from './sections-core.js';
export const STYLES=[{id:'lofi',icon:'☾',name:'Lo-fi',desc:'温暖 · 松弛 · 雨夜',bpm:86},{id:'hiphop',icon:'≋',name:'Hip-hop',desc:'节奏 · 厚实 · 律动',bpm:92},{id:'house',icon:'⌁',name:'House',desc:'明亮 · 跳舞 · 能量',bpm:124},{id:'ambient',icon:'∿',name:'Ambient',desc:'空灵 · 氛围 · 沉浸',bpm:72}];
export const KEYS={'A minor':{root:57,scale:[0,2,3,5,7,8,10],mode:'minor'},'C major':{root:60,scale:[0,2,4,5,7,9,11],mode:'major'},'D minor':{root:50,scale:[0,2,3,5,7,8,10],mode:'minor'},'E minor':{root:52,scale:[0,2,3,5,7,8,10],mode:'minor'},'G major':{root:55,scale:[0,2,4,5,7,9,11],mode:'major'},'F major':{root:53,scale:[0,2,4,5,7,9,11],mode:'major'}};
export {INSTRUMENTS} from './instruments.js';
export const clamp=(n,min,max)=>Math.max(min,Math.min(max,n));
export const copy=x=>JSON.parse(JSON.stringify(x));
export const uid=()=>globalThis.crypto?.randomUUID?.()||`n-${Date.now().toString(36)}-${Math.random().toString(36).slice(2,9)}`;
export function rng(seed){let a=seed>>>0;return()=>{a+=0x6D2B79F5;let t=a;t=Math.imul(t^t>>>15,t|1);t^=t+Math.imul(t^t>>>7,t|61);return((t^t>>>14)>>>0)/4294967296}}
export function noteName(pitch){const names=['C','C♯','D','D♯','E','F','F♯','G','G♯','A','A♯','B'];return names[((pitch%12)+12)%12]+(Math.floor(pitch/12)-1)}
export function makeTrack(instrument){const i=INSTRUMENTS[instrument];if(!i)throw Error('不支持的音源');return{id:uid(),instrument,name:i.name,kind:i.kind,color:i.color,volume:instrument==='keys'?.62:instrument==='hat'?.45:.72,pan:instrument==='hat'?.18:instrument==='lead'?.12:0,muted:false,solo:false,notes:[]}}
function add(track,pitch,start,duration,velocity){track.notes.push({id:uid(),pitch,start:+start.toFixed(4),duration:+duration.toFixed(4),velocity:clamp(Math.round(velocity),1,127)})}
function scalePitch(key,degree,octave=0){const k=KEYS[key];const q=Math.floor(degree/7);return k.root+k.scale[((degree%7)+7)%7]+(q+octave)*12}
export function generateProject({style='lofi',key='A minor',bars=8,seed=271828,bpm,name,composition}={}){
 const spec=STYLES.find(s=>s.id===style)||STYLES[0];if(!KEYS[key])key='A minor';bars=validBars(bars)?bars:8;
 const controls=composition?normalizeControls(composition,seed):null;if(controls)seed=controls.seed;const complexity=controls?.complexity;
 const random=rng(seed),tracks=['kick','snare','hat','bass',style==='ambient'?'pad':'keys','lead'].map(makeTrack),[kick,snare,hat,bass,chords,lead]=tracks;
 const minor=KEYS[key].mode==='minor',progression=progressionFor(KEYS[key].mode,controls?.progression);let previousVoicing=null;
 for(let bar=0;bar<bars;bar++){
  const base=bar*4,degree=progression[Math.floor(bar/2)%4],last=bar===bars-1;
  const kickSteps=style==='house'?[0,4,8,12]:style==='hiphop'?[0,6,8,11]:style==='ambient'?[0]:[0,7,10];
  const effectiveKick=controls&&complexity<30?(style==='house'?kickSteps:style==='ambient'?[0]:[0,8]):controls&&complexity>75&&style==='house'?[...kickSteps,15]:kickSteps;
  effectiveKick.forEach((s,index)=>add(kick,36,base+s*.25,.13,style==='ambient'?65:100-index*6+random()*12));
  if(style!=='ambient')for(const beat of(style==='house'?[1,3]:[1,3]))add(snare,38,base+beat,.14,85+random()*15);
  if(style==='lofi'&&bar%2===1&&(!controls||complexity>=45))add(snare,38,base+2.75,.13,35+random()*15);
  const hStep=style==='house'||controls&&complexity>=60?1:2;for(let s=0;s<16;s+=hStep){if(style==='ambient'&&s!==6&&s!==14)continue;if(style==='lofi'&&random()<.10&&s!==0)continue;add(hat,42,base+s*.25,.08,style==='house'?(s%4===2?78:43):(s%4===0?60:37)+random()*16)}
  if(last&&style!=='ambient'&&(!controls||complexity>=65)){add(snare,38,base+3.5,.13,60);add(snare,38,base+3.75,.13,72)}
  const root=scalePitch(key,degree,-1),bassEvents=style==='house'?[[0,.75],[1,.5],[1.75,.25],[2,.75],[3,.5],[3.75,.25]]:style==='ambient'?[[0,3.8]]:[[0,1.35],[1.75,.5],[2.5,.9],[3.5,.4]];
  if(controls&&complexity<25)bassEvents.splice(0,bassEvents.length,[0,3.5]);
  bassEvents.forEach(([start,dur],idx)=>add(bass,root+(idx===2?7:0),base+start,dur,78+random()*14));
  let pitches=[0,2,4,...(controls?(complexity>=60?[6]:[]):style==='house'?[]:[6])].map(d=>scalePitch(key,degree+d,0));if(controls?.voiceLeading){pitches=voiceLead(pitches,previousVoicing);previousVoicing=pitches}
  const chordStarts=style==='house'?[.5,1.5,2.5,3.5]:style==='ambient'||controls&&complexity<25?[0]:[0,2.5];
  chordStarts.forEach(s=>pitches.forEach((p,j)=>add(chords,p,base+s,style==='ambient'?3.8:style==='house'?.4:s===0?2.1:1.35,style==='ambient'?48:57-j*3+random()*10)));
  const rhythm=style==='ambient'?[1,3]:controls&&complexity<30?[.5,2.5]:bar%2===0?[.5,1.25,2.5,3.25]:[0,.75,1.5,2.75];
  const contour=bar%4===3?[4,2,1,0]:bar%4===2?[2,4,6,4]:[4,2,4,6];
  rhythm.forEach((beat,idx)=>{if(random()<.12&&idx!==0)return;const melodicDegree=degree+contour[idx]+(random()>(controls&&complexity<30?1:.8)?1:0);add(lead,scalePitch(key,melodicDegree,1),base+beat,style==='ambient'?.8:idx===3?.65:.45,style==='ambient'?45:60+random()*16)});
 }
 if(style==='ambient'){kick.volume=.46;hat.volume=.24;snare.volume=.35;bass.volume=.50;chords.volume=.52;lead.volume=.50}
 const generated=ensureClips({version:2,id:uid(),name:name||({lofi:'午夜漫游',hiphop:'街角节拍',house:'微光舞池',ambient:'云层之间'}[style]),style,key,bars,bpm:bpm||spec.bpm,swing:style==='house'?0:style==='ambient'?5:12,master:.75,seed,tracks});if(controls){generated.composition=controls;applyPerformance(generated,controls,{density:true})}return validateProject(generated);
}
export function validateProject(input){
 if(!input||typeof input!=='object'||Array.isArray(input))throw Error('工程格式不正确');
 if(!validBars(input.bars))throw Error('工程长度必须为 4、8、16、32 或 64 小节');
 if(!Number.isFinite(input.bpm)||input.bpm<40||input.bpm>200)throw Error('速度须在 40–200 BPM 之间');
 if(!Object.hasOwn(KEYS,input.key))throw Error('暂不支持这个调性');
 if(!Array.isArray(input.tracks)||input.tracks.length<1||input.tracks.length>16)throw Error('轨道数量须在 1–16 之间');
 if(input.version===3&&!Array.isArray(input.patterns)||input.patterns!==undefined&&input.version!==3)throw Error('共享 Pattern 工程须使用版本 3 和完整 Pattern 库');
 let total=0;const ids=new Set(),noteIds=new Set();const p={version:input.version===2?2:1,id:typeof input.id==='string'&&/^[a-zA-Z0-9_-]{1,80}$/.test(input.id)?input.id:uid(),name:String(input.name||'未命名作品').slice(0,60),style:STYLES.some(s=>s.id===input.style)?input.style:'lofi',key:input.key,bars:input.bars,bpm:input.bpm,swing:clamp(Number.isFinite(input.swing)?input.swing:0,0,45),master:clamp(Number.isFinite(input.master)?input.master:.75,0,1),seed:Number.isFinite(input.seed)?input.seed:1,tracks:[]};
 if(input.composition!==undefined)p.composition=normalizeControls(input.composition,p.seed);
 if(input.loopRange!==undefined)p.loopRange=normalizeRange(input.loopRange,p.bars*4);
 if(input.sections!==undefined)p.sections=normalizeSections(input.sections,p.bars*4);
 if(input.patterns!==undefined){p.version=3;p.patterns=copy(input.patterns)}
 for(const t of input.tracks){
  if(!t||!Object.hasOwn(INSTRUMENTS,t.instrument))throw Error('工程包含不支持的音源');if(!Array.isArray(t.notes)||t.notes.length>4000)throw Error('轨道音符数量不正确');
  const meta=INSTRUMENTS[t.instrument];let id=typeof t.id==='string'&&/^[a-zA-Z0-9_-]{1,80}$/.test(t.id)?t.id:uid();if(ids.has(id))id=uid();ids.add(id);
  const out={id,instrument:t.instrument,kind:meta.kind,name:String(t.name||meta.name).slice(0,40),color:meta.color,volume:clamp(Number.isFinite(t.volume)?t.volume:.7,0,1),pan:clamp(Number.isFinite(t.pan)?t.pan:0,-1,1),muted:t.muted===true,solo:t.solo===true,notes:[]};if(t.clips!==undefined)out.clips=copy(t.clips);if(t.sound!==undefined)out.sound=normalizeSound(t.instrument,t.sound);if(t.sampler!==undefined)out.sampler=normalizeSampler(t.instrument,t.sampler);
  for(const n of t.notes){if(!n||!Number.isInteger(n.pitch)||n.pitch<24||n.pitch>108||!Number.isFinite(n.start)||n.start<0||n.start>p.bars*4-.03125||!Number.isFinite(n.duration)||n.duration<.03125||n.duration>p.bars*4||!Number.isFinite(n.velocity)||n.velocity<1||n.velocity>127)throw Error('音符数据不合法');let nid=typeof n.id==='string'&&/^[a-zA-Z0-9_-]{1,80}$/.test(n.id)&&!noteIds.has(n.id)?n.id:uid();noteIds.add(nid);out.notes.push({id:nid,pitch:meta.kind==='drum'?meta.pitch:n.pitch,start:+n.start.toFixed(4),duration:+Math.min(n.duration,p.bars*4-n.start).toFixed(4),velocity:Math.round(n.velocity),...(n.timingOffset===undefined?{}:(Number.isFinite(n.timingOffset)&&Math.abs(n.timingOffset)<=.04?{timingOffset:+n.timingOffset.toFixed(4)}:(()=>{throw Error('人性化偏移数据不合法')})()))})}
  total+=out.notes.length;if(total>12000)throw Error('工程超过 12000 音符上限');out.notes.sort((a,b)=>a.start-b.start||a.pitch-b.pitch);p.tracks.push(out)
 }
 return ensureClips(p,{strict:input.version===2||input.version===3});
}
export function resizeProject(project,bars,options){if(!validBars(bars))throw Error('不支持的长度');return resizeClipProject(ensureClips(copy(project)),bars,options)}
export function transposeProject(project,newKey){if(!Object.hasOwn(KEYS,newKey))throw Error('无效调性');const p=copy(project),old=KEYS[p.key],next=KEYS[newKey];for(const t of p.tracks)if(t.kind!=='drum')for(const n of t.notes){const delta=n.pitch-old.root;const octave=Math.floor(delta/12);const pc=((delta%12)+12)%12;let deg=0;for(let i=1;i<7;i++)if(Math.abs(old.scale[i]-pc)<Math.abs(old.scale[deg]-pc))deg=i;n.pitch=clamp(next.root+12*octave+next.scale[deg],24,108)}p.key=newKey;return ensureClips(p)}
export function generateFromPrompt(project,prompt,{scope='all',selectedTrackId,controls}={}){
 const text=String(prompt).trim();if(!text)throw Error('先写下你想要的感觉');if(!['all','selected','drums','section'].includes(scope))throw Error('修改范围不正确');
 const p=ensureClips(copy(project)),parameters=controls?normalizeControls(controls,p.seed):null;let style=p.style;
 if(/house|舞曲|四四拍|跳舞/i.test(text))style='house';else if(/hip.?hop|嘻哈|说唱|boom.?bap/i.test(text))style='hiphop';else if(/ambient|氛围|空灵|冥想/i.test(text))style='ambient';else if(/lo.?fi|雨夜|松弛/i.test(text))style='lofi';
 let targets;if(scope==='selected')targets=p.tracks.filter(t=>t.id===selectedTrackId);else if(scope==='drums'||/只.*(?:鼓|节奏)/.test(text))targets=p.tracks.filter(t=>t.kind==='drum');else if(/只.*贝斯/.test(text))targets=p.tracks.filter(t=>t.instrument==='bass');else if(/只.*(?:旋律|主旋律)/.test(text))targets=p.tracks.filter(t=>t.instrument==='lead');else if(/只.*(?:钢琴|和弦)/.test(text))targets=p.tracks.filter(t=>['keys','pad'].includes(t.instrument));else targets=p.tracks;
 if(!targets.length)throw Error('这个范围没有可编曲的轨道，请先添加对应乐器');const narrow=scope!=='all'||targets.length!==p.tracks.length,ids=new Set(targets.map(t=>t.id));
 const requestedBars=text.match(/(?:做|生成|改成|长度|扩展)?\s*(4|8|16|32|64)\s*小节/);let bars=narrow?p.bars:requestedBars?+requestedBars[1]:p.bars;
 const tempo=text.match(/(\d{2,3})\s*(?:bpm|拍每分钟)/i);let bpm=narrow?p.bpm:tempo?clamp(+tempo[1],40,200):style!==p.style?STYLES.find(x=>x.id===style).bpm:p.bpm;
 if(!narrow){if(/慢一点|更慢|放慢/.test(text))bpm=clamp(bpm-8,40,200);if(/快一点|更快|加快/.test(text))bpm=clamp(bpm+8,40,200)}
 let key=p.key;if(!narrow)for(const candidate of Object.keys(KEYS)){const [root,mode]=candidate.split(' ');if(new RegExp(`${root}\\s*(?:${mode==='minor'?'minor|小调':'major|大调'})`,'i').test(text))key=candidate}
 const seed=parameters?.seed??((p.seed+Math.floor(Math.random()*100000)+1)>>>0),base=generateProject({style,key,bars,seed,bpm,name:p.name,composition:parameters||undefined});let out=bars===p.bars?copy(p):resizeProject(p,bars);
 if(!narrow){out.bpm=bpm;out.key=key;out.style=style;out.swing=/律动|摇摆/.test(text)?24:base.swing;out.seed=seed;if(parameters)out.composition=parameters;else delete out.composition}
 for(const t of out.tracks){if(!ids.has(t.id))continue;const src=base.tracks.find(x=>x.instrument===t.instrument)||base.tracks.find(x=>x.instrument===({pluck:'lead',pad:'keys',keys:'pad'}[t.instrument]));if(!src)throw Error('没有这个乐器的离线编曲模板');
  t.notes=src.notes.filter(n=>clipAt(t,n.start)).map(n=>{const c=clipAt(t,n.start);return{...copy(n),id:uid(),duration:+Math.min(n.duration,c.start+c.length-n.start).toFixed(4)}}).filter(n=>n.duration>=.03125);
  if(!parameters&&/温柔|柔和|安静|少一点|不要太满|稀疏/.test(text)){t.notes=t.notes.filter((n,i)=>t.instrument==='hat'?i%2===0:t.instrument==='lead'?i%3!==2:true).map(n=>({...n,velocity:clamp(Math.round(n.velocity*.8),15,110)}))}
  if(!parameters&&/有力|强烈|能量|厚实/.test(text))t.notes=t.notes.map(n=>({...n,velocity:clamp(n.velocity+14,1,127)}));
  if(/半拍/.test(text)&&t.instrument==='snare'){t.notes=[];for(let b=0;b<out.bars;b++)if(clipAt(t,b*4+2))add(t,38,b*4+2,.13,95)}
  if(/更多|丰富|更有变化/.test(text)&&t.instrument==='bass')t.notes=t.notes.map((n,i)=>({...n,pitch:n.pitch+(i%3===1?12:0)}));
  if(/明亮|开心/.test(text)&&['lead','pluck'].includes(t.instrument))t.notes=t.notes.map(n=>({...n,pitch:clamp(n.pitch+12,24,108)}));
 }
 const names=targets.map(t=>t.name).join('、'),summary=narrow?`仅更新${names}，保持其他轨道、音块布局与全局设置。`:`重新编写 ${STYLES.find(s=>s.id===style).name} 音符，保留原有乐器、音块布局与混音。`;
 return{project:validateProject(ensureClips(out)),summary:summary+`${out.bpm} BPM · ${out.bars} 小节。`,source:'offline',controls:parameters,seed};
}

export const beatToSeconds=(beats,bpm)=>beats*60/bpm;
export function performanceBeat(note,swing,clip){const beat=swungBeat(note.start,swing)+(note.timingOffset||0);return Math.max(clip?.start??0,Math.min(beat,clip?clip.start+clip.length-note.duration:Infinity))}
export function swungBeat(start,swing){const tick=Math.round(start*4);return Math.abs(start*4-tick)<.001&&tick%2===1?start+swing/100*.25:start}
function vlq(n){let buffer=n&127;const bytes=[];while((n>>>=7)){buffer<<=8;buffer|=(n&127)|128}while(true){bytes.push(buffer&255);if(buffer&128)buffer>>>=8;else break}return bytes}
const u16=n=>[(n>>>8)&255,n&255],u32=n=>[(n>>>24)&255,(n>>>16)&255,(n>>>8)&255,n&255];
function chunk(type,bytes){return[...new TextEncoder().encode(type),...u32(bytes.length),...bytes]}
export function encodeMIDI(project){const p=validateProject(project),ppq=480,tempo=Math.round(60000000/p.bpm),totalTicks=p.bars*4*ppq;const keySignatures={'A minor':[0,1],'C major':[0,0],'D minor':[255,1],'E minor':[1,1],'G major':[1,0],'F major':[255,0]};const conductor=[0,255,89,2,...keySignatures[p.key],0,255,81,3,...u32(tempo).slice(1),0,255,88,4,4,2,24,8,...vlq(totalTicks),255,47,0];const chunks=[chunk('MTrk',conductor)];let melodicChannel=0;
 for(const t of p.tracks){if(t.kind!=='drum'&&melodicChannel===9)melodicChannel++;if(t.kind!=='drum'&&melodicChannel>15)throw Error('标准 MIDI 最多支持 15 个非鼓音源，请减少乐器轨道');const channel=t.kind==='drum'?9:melodicChannel++;const name=new TextEncoder().encode(t.name);const events=[];
 const programs={bass:33,keys:4,lead:80,pad:89,pluck:24};if(t.kind!=='drum')events.push({tick:0,order:0,data:[192|channel,t.sampler?samplePreset(t.sampler.preset).program??programs[t.instrument]??0:programs[t.instrument]??0]});events.push({tick:0,order:0,data:[176|channel,7,Math.round(t.volume*127)]},{tick:0,order:0,data:[176|channel,10,Math.round((t.pan+1)*63.5)]});
 for(const n of audibleNotes(t)){const midiPitch=t.kind==='drum'&&t.sampler?(samplePreset(t.sampler.preset).midiPitch??n.pitch):n.pitch;const start=Math.round(performanceBeat(n,p.swing,clipAt(t,n.start))*ppq),end=Math.min(totalTicks,Math.round((performanceBeat(n,p.swing,clipAt(t,n.start))+n.duration)*ppq));events.push({tick:start,order:2,data:[144|channel,midiPitch,n.velocity]},{tick:Math.max(start+1,end),order:1,data:[128|channel,midiPitch,0]})}
 events.sort((a,b)=>a.tick-b.tick||a.order-b.order);let last=0,bytes=[0,255,3,...vlq(name.length),...name];for(const e of events){bytes.push(...vlq(e.tick-last),...e.data);last=e.tick}bytes.push(...vlq(Math.max(0,totalTicks-last)),255,47,0);chunks.push(chunk('MTrk',bytes));
 }
 const data=[...chunk('MThd',[...u16(1),...u16(chunks.length),...u16(ppq)]),...chunks.flat()];return new Uint8Array(data);
}
export const PROJECT_SCHEMA={type:'object',additionalProperties:false,required:['summary','project'],properties:{summary:{type:'string'},project:{type:'object',required:['name','style','bpm','key','bars','swing','tracks'],properties:{name:{type:'string'},style:{enum:STYLES.map(s=>s.id)},bpm:{type:'number',minimum:40,maximum:200},key:{enum:Object.keys(KEYS)},bars:{enum:BAR_LENGTHS},swing:{type:'number',minimum:0,maximum:45},tracks:{type:'array',minItems:1,maxItems:16,items:{type:'object',required:['instrument','notes'],properties:{id:{type:'string'},name:{type:'string'},instrument:{enum:Object.keys(INSTRUMENTS)},volume:{type:'number',minimum:0,maximum:1},pan:{type:'number',minimum:-1,maximum:1},notes:{type:'array',maxItems:4000,items:{type:'object',required:['pitch','start','duration','velocity'],properties:{pitch:{type:'integer',minimum:24,maximum:108},start:{type:'number',minimum:0},duration:{type:'number',minimum:.03125},velocity:{type:'number',minimum:1,maximum:127}}}}}}}}}}};
