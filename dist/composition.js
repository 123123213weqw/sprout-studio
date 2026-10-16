import {clipAt} from './clips.js';
export const CONTROL_DEFAULTS={density:50,complexity:35,energy:50,humanize:15,progression:'warm',voiceLeading:true,seed:271828};
export const CONTROL_PRESETS=[{id:'sparse',name:'留一点空白',description:'简洁骨架 · 温柔力度',density:20,complexity:15,energy:30,humanize:20},{id:'balanced',name:'刚刚好',description:'适中密度 · 有一点变化',density:50,complexity:35,energy:50,humanize:15},{id:'active',name:'多一点能量',description:'更密节奏 · 更多切分与填充',density:80,complexity:80,energy:75,humanize:25}];
const clamp=(n,a,b)=>Math.max(a,Math.min(b,n)),round=n=>+n.toFixed(4);
export function normalizeControls(input={},seed=CONTROL_DEFAULTS.seed){
 if(!input||typeof input!=='object'||Array.isArray(input))throw Error('编曲参数须为对象');
 const allowed=new Set(Object.keys(CONTROL_DEFAULTS));if(Object.keys(input).some(key=>!allowed.has(key)))throw Error('包含未知的编曲参数');
 const out={...CONTROL_DEFAULTS,seed,...input};for(const key of ['density','complexity','energy','humanize']){if(!Number.isFinite(out[key])||out[key]<0||out[key]>100)throw Error('密度、复杂度、能量与人性化须为 0–100');out[key]=Math.round(out[key])}
 if(!['warm','lift','home'].includes(out.progression)||typeof out.voiceLeading!=='boolean')throw Error('和弦进行或声部连接参数不正确');
 if(!Number.isInteger(out.seed)||out.seed<0||out.seed>0xffffffff)throw Error('变奏种子须为 0–4294967295 整数');return out;
}
export function progressionFor(mode,name='warm'){return name==='home'?[0,3,4,0]:name==='lift'?(mode==='minor'?[0,3,5,4]:[0,5,3,4]):mode==='minor'?[0,5,2,6]:[0,4,5,3]}
// Stable per-event randomness avoids density changes reordering the random stream.
export function randomAt(seed,key){let h=(seed^0x811c9dc5)>>>0;for(let i=0;i<key.length;i++){h^=key.charCodeAt(i);h=Math.imul(h,0x01000193)}h^=h>>>16;h=Math.imul(h,0x7feb352d);h^=h>>>15;h=Math.imul(h,0x846ca68b);h^=h>>>16;return(h>>>0)/4294967296}
export function voiceLead(pitches,previous){
 const base=[...pitches].sort((a,b)=>a-b);if(!previous?.length)return base;
 let best=base,score=Infinity;for(let inversion=0;inversion<base.length;inversion++){const rotated=base.slice(inversion).concat(base.slice(0,inversion).map(p=>p+12));for(const shift of [-24,-12,0,12]){const candidate=rotated.map(p=>p+shift);if(candidate.some(p=>p<42||p>84))continue;const distance=candidate.reduce((sum,p,i)=>sum+Math.abs(p-previous[Math.min(i,previous.length-1)]),0)+Math.abs(candidate.length-previous.length)*12;if(distance<score){best=candidate;score=distance}}}return best;
}
export function applyPerformance(project,controls,{trackIds,range,density=false}={}){
 const c=normalizeControls(controls),ids=trackIds?new Set(trackIds):null;
 for(const t of project.tracks){if(ids&&!ids.has(t.id))continue;const inside=n=>!range||n.start>=range.start-.00005&&n.start<range.start+range.length-.00005;
  const groups=new Map();for(const n of [...t.notes].sort((a,b)=>a.start-b.start||a.pitch-b.pitch))if(inside(n)){const key=n.start.toFixed(4);if(!groups.has(key))groups.set(key,[]);groups.get(key).push(n)}
  const firstByBar=new Map();for(const [key,notes] of groups){const bar=Math.floor(notes[0].start/4);if(!firstByBar.has(bar))firstByBar.set(bar,key)}
  const removed=new Set();for(const [key,notes] of groups){const label=`${t.instrument}:${key}`,anchor=firstByBar.get(Math.floor(notes[0].start/4))===key;
   if(density&&!anchor&&randomAt(c.seed,'density:'+label)>.05+.0095*c.density){notes.forEach(n=>removed.add(n.id));continue}
   let low=-.04*c.humanize/100,high=.04*c.humanize/100;for(const n of notes){const region=clipAt(t,n.start),start=Math.max(region?.start??0,range?.start??0),end=Math.min(region?region.start+region.length:project.bars*4,range?range.start+range.length:project.bars*4);low=Math.max(low,start-n.start);high=Math.min(high,end-n.start-n.duration)}
   const offset=round(clamp((randomAt(c.seed,'time:'+label)*2-1)*.04*c.humanize/100,low,high));
   notes.forEach(n=>{n.velocity=clamp(Math.round(n.velocity*(.7+.006*c.energy)+(randomAt(c.seed,`velocity:${label}:${n.pitch}`)*2-1)*7*c.humanize/100),1,127);if(c.humanize)n.timingOffset=offset;else delete n.timingOffset});
  }t.notes=t.notes.filter(n=>!removed.has(n.id));
 }return project;
}
const identity=n=>`${n.pitch}:${n.start.toFixed(4)}`;
export function compareProjects(before,after){
 const aPatterns=before.patterns||[],bPatterns=after.patterns||[],patterns={before:aPatterns.length,after:bPatterns.length,created:bPatterns.filter(b=>!aPatterns.some(a=>a.id===b.id)).length,deleted:aPatterns.filter(a=>!bPatterns.some(b=>b.id===a.id)).length,modified:bPatterns.filter(b=>aPatterns.some(a=>a.id===b.id&&JSON.stringify(a)!==JSON.stringify(b))).length,linked:0,detached:0};
 for(const t of after.tracks)for(const c of t.clips||[]){const old=before.tracks.find(x=>x.id===t.id)?.clips?.find(x=>x.id===c.id);if(c.patternId&&c.patternId!==old?.patternId)patterns.linked++;if(old?.patternId&&old.patternId!==c.patternId)patterns.detached++}
 const tracks=[];for(const id of new Set([...before.tracks.map(t=>t.id),...after.tracks.map(t=>t.id)])){const a=before.tracks.find(t=>t.id===id),b=after.tracks.find(t=>t.id===id),pool=new Map();for(const n of a?.notes||[]){const key=identity(n);if(!pool.has(key))pool.set(key,[]);pool.get(key).push(n)}let added=0,modified=0;for(const n of b?.notes||[]){const old=pool.get(identity(n))?.shift();if(!old)added++;else if(old.duration!==n.duration||old.velocity!==n.velocity||(old.timingOffset||0)!==(n.timingOffset||0))modified++}const removed=[...pool.values()].reduce((n,list)=>n+list.length,0);const soundChanged=!!a&&!!b&&(a.instrument!==b.instrument||JSON.stringify(a.sound??null)!==JSON.stringify(b.sound??null)||JSON.stringify(a.sampler??null)!==JSON.stringify(b.sampler??null));tracks.push({id,name:b?.name||a.name,kind:b?.kind||a.kind,before:a?.notes.length||0,after:b?.notes.length||0,added,removed,modified,created:!a,deleted:!b,soundChanged,changed:!!(added||removed||modified||!a||!b||soundChanged)})}
 return{tracks,patterns,soundChanges:tracks.filter(t=>t.soundChanged).length,changedTracks:tracks.filter(t=>t.changed).length,notesBefore:before.tracks.reduce((n,t)=>n+t.notes.length,0),notesAfter:after.tracks.reduce((n,t)=>n+t.notes.length,0),added:tracks.reduce((n,t)=>n+t.added,0),removed:tracks.reduce((n,t)=>n+t.removed,0),modified:tracks.reduce((n,t)=>n+t.modified,0),globals:['bpm','key','bars','style','swing'].filter(key=>before[key]!==after[key]).map(key=>({key,before:before[key],after:after[key]}))};
}
