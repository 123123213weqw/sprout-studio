import {MAX_BARS} from './limits.js';
// Song labels are optional, bar-aligned metadata, never note containers.
export const SECTION_KINDS={intro:'前奏',verse:'主歌',chorus:'副歌',bridge:'过渡',outro:'尾奏',custom:'自定义'};
const safeId=id=>typeof id==='string'&&/^[a-zA-Z0-9_-]{1,80}$/.test(id);
export function normalizeSections(input,end){
 if(!Array.isArray(input)||input.length>MAX_BARS)throw Error('歌曲段落最多 64 个');const ids=new Set();
 const sections=input.map(s=>{if(!s||!safeId(s.id)||ids.has(s.id)||typeof s.name!=='string'||!s.name.trim()||s.name.trim().length>40||!Number.isInteger(s.start)||s.start<0||s.start%4||!Number.isInteger(s.length)||s.length<4||s.length%4||s.start+s.length>end||s.kind!==undefined&&typeof s.kind!=='string'||!Object.hasOwn(SECTION_KINDS,s.kind??'custom'))throw Error('段落须有唯一标识、名称，且按完整小节放在工程内');ids.add(s.id);return{id:s.id,name:s.name.trim(),kind:s.kind??'custom',start:s.start,length:s.length}}).sort((a,b)=>a.start-b.start);
 for(let i=1;i<sections.length;i++)if(sections[i].start<sections[i-1].start+sections[i-1].length)throw Error('歌曲段落不能重叠');return sections;
}
export function resizeSections(project,end){if(project.sections!==undefined)project.sections=normalizeSections(project.sections.filter(s=>s.start<end).map(s=>({...s,length:Math.min(s.length,end-s.start)})),end);return project}
export function protectSections(before,next){const out=JSON.parse(JSON.stringify(next));if(before.sections===undefined)delete out.sections;else out.sections=JSON.parse(JSON.stringify(before.sections));return resizeSections(out,out.bars*4)}
