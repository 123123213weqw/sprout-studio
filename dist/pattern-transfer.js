import {copy,uid,validateProject,KEYS} from './music.js';
import {normalizePatterns,notesSignature,PATTERN_LIMITS} from './patterns-core.js';

export const PATTERN_FILE_FORMAT='sprout-pattern-library';
export const PATTERN_FILE_VERSION=1;
export const PATTERN_FILE_MAX_BYTES=3000000;
const byteLength=text=>new TextEncoder().encode(text).length;
const safeId=id=>typeof id==='string'&&/^[a-zA-Z0-9_-]{1,80}$/.test(id);
const object=value=>value&&typeof value==='object'&&!Array.isArray(value);
function fields(value,allowed,message){
 if(!object(value)||Object.keys(value).some(key=>!allowed.includes(key)))throw Error(message);
}
function context(value){
 if(value===undefined)return undefined;
 fields(value,['bpm','key','swing'],'乐句参考信息格式不正确');
 if(!Number.isFinite(value.bpm)||value.bpm<40||value.bpm>200||!Object.hasOwn(KEYS,value.key)||!Number.isFinite(value.swing)||value.swing<0||value.swing>45)throw Error('乐句参考速度、调性或摇摆不正确');
 return{bpm:value.bpm,key:value.key,swing:value.swing};
}
export function validatePatternLibrary(input){
 fields(input,['format','version','context','patterns'],'请选择Sprout 乐句文件，不是音频或任意 JSON');
 if(input.format!==PATTERN_FILE_FORMAT||input.version!==PATTERN_FILE_VERSION)throw Error('不支持这个乐句文件格式或版本');
 if(!Array.isArray(input.patterns)||!input.patterns.length||input.patterns.length>PATTERN_LIMITS.patterns)throw Error('乐句文件须包含 1–64 个 Pattern');
 for(const p of input.patterns){
  fields(p,['id','name','instrument','kind','length','notes'],'乐句含有不支持的字段');
  if(typeof p.name!=='string'||!p.name.trim()||p.name.length>60||/[\x00-\x1f\x7f]/.test(p.name)||!Array.isArray(p.notes))throw Error('乐句名称或音符格式不正确');
  for(const n of p.notes){fields(n,['id','pitch','start','duration','velocity','timingOffset'],'乐句音符含有不支持的字段');if(!Number.isInteger(n.velocity))throw Error('乐句力度须为 1–127 的整数')}
 }
 const patterns=normalizePatterns(input.patterns);
 input.patterns.forEach((p,i)=>{if(p.kind!==undefined&&p.kind!==patterns[i].kind)throw Error('乐句音源种类不一致')});
 const reference=context(input.context);
 return{format:PATTERN_FILE_FORMAT,version:PATTERN_FILE_VERSION,...(reference?{context:reference}:{}),patterns};
}
function select(patterns,ids){
 if(!Array.isArray(ids)||!ids.length||ids.length>64||new Set(ids).size!==ids.length||ids.some(id=>!safeId(id)||!patterns.some(p=>p.id===id)))throw Error('请至少选择一个存在的乐句，不能重复选择');
 const wanted=new Set(ids);return patterns.filter(p=>wanted.has(p.id));
}
export function exportPatternLibrary(project,{ids}={}){
 const p=validateProject(project),patterns=p.patterns||[];
 if(!patterns.length)throw Error('工程的 Pattern 库还是空的，请先从音块存入乐句');
 return validatePatternLibrary({format:PATTERN_FILE_FORMAT,version:PATTERN_FILE_VERSION,context:{bpm:p.bpm,key:p.key,swing:p.swing},patterns:select(patterns,ids===undefined?patterns.map(x=>x.id):ids)});
}
export function serializePatternLibrary(library){
 const text=JSON.stringify(validatePatternLibrary(library),null,2);
 if(byteLength(text)>PATTERN_FILE_MAX_BYTES)throw Error('乐句文件超过 3 MB，请减少导出数量');
 return text;
}
export function readPatternFile(text){
 if(typeof text!=='string'||byteLength(text)>PATTERN_FILE_MAX_BYTES)throw Error('乐句或工程文件超过 3 MB 上限');
 let raw;try{raw=JSON.parse(text)}catch{throw Error('文件不是完整 JSON，没有导入任何乐句')}
 if(object(raw)&&Object.hasOwn(raw,'format'))return{library:validatePatternLibrary(raw),origin:'library'};
 let project;try{project=validateProject(raw)}catch{throw Error('不是有效的Sprout 乐句文件或完整工程；工程共享缓存也必须一致')}
 if(!project.patterns?.length)throw Error('这个工程没有库中的 Pattern；请先从音块存入，再导出乐句');
 return{library:exportPatternLibrary(project),origin:'project'};
}
const contentKey=p=>JSON.stringify([p.instrument,p.length,notesSignature(p.notes)]);
function uniqueName(name,names){
 if(!names.has(name)){names.add(name);return name}
 for(let i=2;i<=128;i++){const suffix=` · 导入 ${i}`,next=name.slice(0,60-suffix.length)+suffix;if(!names.has(next)){names.add(next);return next}}
 throw Error('乐句重名过多，请先整理库中的名称');
}
function newId(used,factory){
 for(let i=0;i<32;i++){const id=factory();if(!safeId(id))throw Error('无法生成有效的乐句标识');if(!used.has(id)){used.add(id);return id}}
 throw Error('乐句标识发生碰撞，没有导入任何内容');
}
// Import adds sources only. No track, clip, source reference or model call is created.
export function planPatternImport(project,input,{ids,duplicates='skip',idFactory=uid}={}){
 if(!['skip','copies'].includes(duplicates)||typeof idFactory!=='function')throw Error('重复乐句处理方式不正确');
 const before=validateProject(project),library=validatePatternLibrary(input),chosen=select(library.patterns,ids===undefined?library.patterns.map(p=>p.id):ids);
 const p=copy(before),existing=p.patterns||[],names=new Set(existing.map(x=>x.name)),content=new Map();
 for(const source of existing)if(!content.has(contentKey(source)))content.set(contentKey(source),source);
 const used=new Set([p.id,...(p.sections||[]).map(s=>s.id),...existing.flatMap(x=>[x.id,...x.notes.map(n=>n.id)]),...p.tracks.flatMap(t=>[t.id,...t.notes.map(n=>n.id),...t.clips.map(c=>c.id)]),...library.patterns.flatMap(x=>[x.id,...x.notes.map(n=>n.id)])]);
 const added=[],items=[];
 for(const source of chosen){
  const key=contentKey(source),match=content.get(key);
  if(duplicates==='skip'&&match){items.push({sourceId:source.id,action:'skip',name:source.name,duplicateName:match.name});continue}
  const next={...copy(source),id:newId(used,idFactory),name:uniqueName(source.name,names),notes:source.notes.map(n=>({...n,id:newId(used,idFactory)}))};
  added.push(next);if(!content.has(key))content.set(key,next);
  items.push({sourceId:source.id,action:'add',patternId:next.id,name:source.name,importedName:next.name,renamed:source.name!==next.name});
 }
 if(added.length){p.version=3;p.patterns=normalizePatterns([...existing,...added])}
 const next=validateProject(p);
 if(byteLength(JSON.stringify(next))>PATTERN_FILE_MAX_BYTES)throw Error('导入后工程超过 3 MB 保存上限，请减少所选乐句');
 return{project:next,addedIds:added.map(p=>p.id),items,stats:{selected:chosen.length,added:added.length,skipped:chosen.length-added.length,renamed:items.filter(x=>x.renamed).length,patternsBefore:existing.length,patternsAfter:existing.length+added.length,notesBefore:existing.reduce((n,p)=>n+p.notes.length,0),notesAfter:existing.concat(added).reduce((n,p)=>n+p.notes.length,0)}};
}
