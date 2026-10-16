import {generateProject,validateProject} from './music.js';
export const PROJECT_STARTS=[{id:'blank',label:'空白 · 自己开始'},{id:'lofi',label:'Lo-fi · 温柔'},{id:'hiphop',label:'Hip-hop · 律动'},{id:'house',label:'House · 电子'},{id:'ambient',label:'Ambient · 氛围'}];
export function createStartProject({template='blank',bars=8}={}){
 if(!PROJECT_STARTS.some(p=>p.id===template)||![8,16,32].includes(bars))throw Error('新工程起点或长度不正确');const p=generateProject({style:template==='blank'?'lofi':template,bars,key:'A minor'});if(template==='blank')p.tracks.forEach(t=>t.notes=[]);return validateProject(p);
}
