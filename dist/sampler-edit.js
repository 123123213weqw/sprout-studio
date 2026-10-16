import {copy,validateProject} from './music.js';
import {normalizeSampler,RECOMMENDED_SAMPLES,samplePreset} from './sampler-core.js';
export function setTrackSampler(project,trackId,settings){
 const out=copy(project),t=out.tracks.find(t=>t.id===trackId);if(!t)throw Error('采样目标轨道已不存在');
 if(settings===undefined)delete t.sampler;else t.sampler=normalizeSampler(t.instrument,settings);
 const next=validateProject(out);if(new TextEncoder().encode(JSON.stringify(next)).length>3000000)throw Error('采样设置会超过 3 MB 工程预算，没有修改工程');return next;
}
export function planSamplerPalette(project){
 const out=copy(project),changes=[];for(const t of out.tracks){const preset=RECOMMENDED_SAMPLES[t.instrument];if(!preset)throw Error('这个轨道没有对应的真实音源');if(t.sampler!==undefined){normalizeSampler(t.instrument,t.sampler);continue;}t.sampler=normalizeSampler(t.instrument,{preset});changes.push({trackId:t.id,name:t.name,instrument:t.instrument,preset,label:samplePreset(preset).name,notes:t.notes.length})}
 const next=validateProject(out);if(new TextEncoder().encode(JSON.stringify(next)).length>3000000)throw Error('真实音色设置会超过 3 MB 工程预算，没有修改工程');return {project:next,changes,presets:[...new Set(changes.map(x=>x.preset))]};
}
