import {normalizeModelReceipt} from './model-receipt.js';
import {copy,uid,validateProject,generateFromPrompt} from './music.js';
import {ensureClips,mergeClipVariation} from './clips.js';
import {reconcilePatternLibrary} from './patterns.js';
import {protectTrackSounds} from './sound-edit.js';
import {protectSections} from './sections-core.js';
import {sectionAt,mergeSectionVariation} from './sections.js';
import {CONTROL_PRESETS,normalizeControls,compareProjects} from './composition.js';

export const CANDIDATE_SCOPES=['all','selected','drums','clip','section'];
const idOK=id=>typeof id==='string'&&/^[a-zA-Z0-9_-]{1,80}$/.test(id);
const text=(s,max,name)=>{if(typeof s!=='string'||!s.trim()||s.length>max)throw Error(name+'不正确');return s.trim()};
export function projectFingerprint(project){return JSON.stringify(validateProject(project))}
export function candidateMatches(candidate,project){return projectFingerprint(candidate.before)===projectFingerprint(project)}

export function candidateContext(project,{scope='all',selectedTrackId,clipId,sectionId}={}){
 if(!CANDIDATE_SCOPES.includes(scope))throw Error('候选修改范围不正确');
 const out={scope};let scopeLabel='整首编曲';
 if(scope==='selected'||scope==='clip'){
  const t=project.tracks.find(t=>t.id===selectedTrackId);if(!t)throw Error('先选择候选目标轨道');out.selectedTrackId=t.id;scopeLabel='轨道 · '+t.name;
  if(scope==='clip'){const c=t.clips.find(c=>c.id===clipId);if(!c)throw Error('先选择候选目标音块');out.clipId=c.id;scopeLabel=`音块 · ${t.name} · 第 ${c.start/4+1} 小节起`;out.range={start:c.start,length:c.length}}
 }else if(scope==='section'){const s=sectionAt(project,sectionId);out.sectionId=s.id;out.range={start:s.start,length:s.length};scopeLabel=`段落 · ${s.name} · 第 ${s.start/4+1} 小节起`}
 else if(scope==='drums'){if(!project.tracks.some(t=>t.kind==='drum'))throw Error('当前工程没有鼓轨');scopeLabel='所有鼓轨'}
 return{...out,scopeLabel};
}
// One shared merge boundary for single candidates and all batch alternatives.
export function protectCandidate(before,next,scope='all',selectedTrackId,clipId,sectionId){
 candidateContext(before,{scope,selectedTrackId,clipId,sectionId});
 if(scope==='section')return mergeSectionVariation(before,next,sectionId);
 if(scope==='all')return protectSections(before,protectTrackSounds(before,reconcilePatternLibrary(before,next)));
 if(scope==='clip')return validateProject(mergeClipVariation(before,next,selectedTrackId,clipId));
 const ids=new Set(before.tracks.filter(t=>scope==='drums'?t.kind==='drum':t.id===selectedTrackId).map(t=>t.id)),p=copy(before);
 for(const t of p.tracks)if(ids.has(t.id)){const replacement=next.tracks.find(n=>n.id===t.id)||next.tracks.find(n=>n.instrument===t.instrument);if(!replacement)throw Error('模型未返回所选轨道');t.notes=copy(replacement.notes).filter(n=>n.start<before.bars*4).map(n=>({...n,duration:Math.min(n.duration,before.bars*4-n.start)}))}
 return validateProject(ensureClips(p));
}
export function normalizeCandidate(input,{now=Date.now()}={}){
 if(!input||typeof input!=='object'||Array.isArray(input))throw Error('候选数据不正确');
 const before=validateProject(input.before),project=validateProject(input.project),context=candidateContext(before,input.context||{});
 if(!['offline','llm'].includes(input.source))throw Error('候选来源不正确');
 const out={id:idOK(input.id)?input.id:uid(),label:text(input.label||'候选编曲',60,'候选名称'),createdAt:input.createdAt??now,before,project,context,source:input.source,summary:text(input.summary||'一版待审核编曲',700,'候选说明'),prompt:text(input.prompt||'未记录描述',1600,'候选描述')};
 if(!Number.isSafeInteger(out.createdAt)||out.createdAt<0)throw Error('候选时间不正确');
 const receipt=normalizeModelReceipt(input.receipt);if(receipt&&out.source==='llm')out.receipt=receipt;
 if(input.controls!=null)out.controls=normalizeControls(input.controls);
 if(input.seed!==undefined){if(!Number.isInteger(input.seed)||input.seed<0||input.seed>0xffffffff)throw Error('候选种子不正确');out.seed=input.seed}
 return out;
}
export function compareCandidates(a,b){if(projectFingerprint(a.before)!==projectFingerprint(b.before))throw Error('两版不是基于同一原稿，不能逐音对比；请分别查看与各自原稿的变化');return compareProjects(a.project,b.project)}
export function createOfflineAlternatives(project,prompt,options={}){
 const before=validateProject(project),description=text(prompt,1600,'编曲描述'),context=candidateContext(before,options),base=normalizeControls(options.controls||{},before.seed>>>0);
 return CONTROL_PRESETS.map((preset,index)=>{
  const {id,name,description:help,...values}=preset,controls=normalizeControls({...base,...values,seed:(base.seed+index)>>>0});
  const result=generateFromPrompt(before,description,{scope:context.scope==='clip'?'selected':context.scope,selectedTrackId:context.selectedTrackId,controls});
  const next=protectCandidate(before,result.project,context.scope,context.selectedTrackId,context.clipId,context.sectionId);
  return normalizeCandidate({...result,project:next,before,context,prompt:description,label:['A','B','C'][index]+' · '+name,summary:(help+'。'+result.summary).slice(0,700),controls,seed:controls.seed});
 });
}
