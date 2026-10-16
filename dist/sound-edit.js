import {copy,validateProject,INSTRUMENTS} from './music.js';
import {normalizeSound} from './sound.js';
export function setTrackSound(project,trackId,sound){const p=copy(project),track=p.tracks.find(t=>t.id===trackId);if(!track)throw Error('音色目标轨道已不存在');if(sound===undefined)delete track.sound;else track.sound=normalizeSound(track.instrument,sound);const next=validateProject(p);if(new TextEncoder().encode(JSON.stringify(next)).length>3000000)throw Error('应用音色后工程超过 3 MB 保存上限，没有修改音乐');return next}
export function protectTrackSounds(before,next){const p=copy(next);for(const t of p.tracks){const old=before.tracks.find(x=>x.id===t.id)||before.tracks.find(x=>x.instrument===t.instrument);if(old?.instrument===t.instrument&&old.sound!==undefined)t.sound=copy(old.sound);else delete t.sound;if(old?.instrument===t.instrument&&old.sampler!==undefined)t.sampler=copy(old.sampler);else delete t.sampler}return validateProject(p)}
export function changeTrackInstrument(project,trackId,instrument,{name}={}){
 const p=copy(project),t=p.tracks.find(t=>t.id===trackId);if(!t||!Object.hasOwn(INSTRUMENTS,instrument)||INSTRUMENTS[instrument].kind!==t.kind)throw Error('新音源与轨道类型不匹配');if(name!==undefined)t.name=String(name||t.name).slice(0,40);
 if(t.instrument!==instrument){t.instrument=instrument;t.color=INSTRUMENTS[instrument].color;delete t.sound;delete t.sampler;if(t.kind==='drum'){t.notes.forEach(n=>n.pitch=INSTRUMENTS[instrument].pitch);t.clips.forEach(c=>delete c.patternId)}}return validateProject(p);
}
