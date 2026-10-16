import {EXTRA_SAMPLE_PRESETS} from './sample-presets-extra.js';
import {INSTRUMENTS} from './instruments.js';
import {SAMPLE_ASSETS} from './sample-assets.js';
export const SAMPLE_PRESETS=Object.freeze({
 'vsco-piano':{name:'立式钢琴 · 采样',instrument:'keys',label:'PIANO SAMPLE',kind:'tonal',gain:.8,release:.2,program:0,description:'经典版本：真实立式钢琴，8 个采样音区、2 个力度层平滑混合；不循环延音。',assets:SAMPLE_ASSETS.slice(0,16).map(x=>x.id)},
 'vsco-kick':{name:'管弦底鼓 · 采样',instrument:'kick',label:'KICK SAMPLE',kind:'drum',gain:.85,release:.55,description:'管弦大鼓录音，两档力度；不是电子 808。',assets:['kick-soft','kick-hard']},
 'vsco-snare':{name:'军鼓 · 采样',instrument:'snare',label:'SNARE SAMPLE',kind:'drum',gain:.7,release:.4,description:'带响弦的军鼓录音，两档力度。',assets:['snare-soft','snare-hard']},
 'vsco-cymbal':{name:'短镲 · 采样',instrument:'hat',label:'CYMBAL SAMPLE',kind:'drum',gain:.45,release:.18,description:'短击镲录音经闸门缩短，用于踩镲声部；不是踩镲录音。',assets:['cymbal']},
 'vsco-piano-full':{name:'立式钢琴 · 细分采样',instrument:'keys',label:'PIANO 14 ZONES',kind:'tonal',gain:.8,release:.3,program:0,balance:.68,description:'14 个真实根音、两层力度混合，缩小变速跨度并平衡各音区；钢琴不循环。',assets:SAMPLE_ASSETS.filter(x=>x.id.startsWith('piano-')).map(x=>x.id)},
 'vsco-bass':{name:'低音提琴拨奏 · 采样',instrument:'bass',label:'BASS PIZZ SAMPLE',kind:'tonal',gain:.95,release:.3,program:43,balance:.68,description:'真实低音提琴拨奏，12 个根音、单档录音；力度控制音量，不是电贝斯。',assets:SAMPLE_ASSETS.filter(x=>x.id.startsWith('bass-')).map(x=>x.id)},
 'vsco-flute':{name:'长笛 · 采样',instrument:'lead',label:'FLUTE SAMPLE',kind:'tonal',gain:.7,release:.18,attack:.012,program:73,balance:.68,description:'真实长笛，10 个根音、单档录音；保留吹奏起音，长音使用交叉淡化延音循环。',assets:SAMPLE_ASSETS.filter(x=>x.id.startsWith('flute-')).map(x=>x.id)},
 'vsco-cello':{name:'大提琴弦乐 · 采样',instrument:'pad',label:'CELLO SAMPLE',kind:'tonal',gain:.6,release:.9,attack:.1,program:42,balance:.68,description:'真实大提琴组，13 个根音、单档录音；保留拉弓起音，长音使用交叉淡化循环，不是全弦乐团。',assets:SAMPLE_ASSETS.filter(x=>x.id.startsWith('cello-')).map(x=>x.id)},
 'vsco-harp':{name:'竖琴拨弦 · 采样',instrument:'pluck',label:'HARP SAMPLE',kind:'tonal',gain:.8,release:.8,program:46,balance:.68,description:'真实竖琴，12 个根音、单档录音；保留拨弦衰减，不循环，不是吉他录音。',assets:SAMPLE_ASSETS.filter(x=>x.id.startsWith('harp-')).map(x=>x.id)},
 'karoryfer-guitar':{name:'Archtop guitar · microphone',instrument:'pluck',label:'ACOUSTIC GUITAR',previewDuration:.9,kind:'tonal',gain:.8,release:.45,program:24,balance:.68,source:'karoryfer',description:'Microphone-recorded archtop guitar: 16 roots, four recorded playing intensities and two alternating takes per intensity. Natural decay; no synthetic pitch variation or sustain loop.',assets:SAMPLE_ASSETS.filter(x=>x.id.startsWith('guitar-')).map(x=>x.id)},
 'vsco-violin':{name:'Solo violin · bowed',instrument:'lead',label:'SOLO VIOLIN',previewDuration:1.25,kind:'tonal',gain:.8,release:.35,attack:.015,program:40,balance:.68,description:'Recorded solo violin with vibrato: 11 roots and two recorded dynamics. Original bow attack, fine-tuning corrections and crossfaded sustain loops. Repeated attacks are not true legato.',assets:SAMPLE_ASSETS.filter(x=>x.id.startsWith('violin-')).map(x=>x.id)},
 'vsco-clarinet':{name:'Clarinet · sustained',instrument:'lead',label:'CLARINET',previewDuration:1.25,kind:'tonal',gain:.7,release:.2,attack:.008,program:71,balance:.68,description:'Recorded clarinet: ten roots and three recorded dynamics. Breath attack and crossfaded sustain loops; velocity blends the recordings. No modeled breath or legato transitions.',assets:SAMPLE_ASSETS.filter(x=>x.id.startsWith('clarinet-')).map(x=>x.id)},
 'sonic-kick':{name:'架子鼓底鼓 · 采样',instrument:'kick',label:'KIT KICK SAMPLE',kind:'drum',gain:.85,release:.45,balance:.68,source:'sonic',description:'真实架子鼓底鼓录音，单档素材；力度控制音量，保留原音高。',assets:['kit-kick']},
 'sonic-snare':{name:'架子鼓军鼓 · 采样',instrument:'snare',label:'KIT SNARE SAMPLE',kind:'drum',gain:.75,release:.3,balance:.68,source:'sonic',description:'真实架子鼓军鼓，两档录音平滑混合；保留原音高。',assets:['kit-snare-soft','kit-snare-hard']},
 'sonic-hat':{name:'闭合踩镲 · 采样',instrument:'hat',label:'CLOSED HAT SAMPLE',kind:'drum',gain:.6,release:.14,balance:.68,source:'sonic',description:'真正闭合踩镲录音，单档素材；不是短击镲替代，不包含开镲或脚踏切换。',assets:['kit-hat']},
 ...EXTRA_SAMPLE_PRESETS
});
export const RECOMMENDED_SAMPLES=Object.freeze({keys:'vsco-piano-full',bass:'vsco-bass',lead:'vsco-flute',pad:'vsco-cello',pluck:'vsco-harp',kick:'sonic-kick',snare:'sonic-snare',hat:'sonic-hat'});
for(const preset of Object.values(SAMPLE_PRESETS)){Object.freeze(preset.assets);Object.freeze(preset)}
for(const asset of SAMPLE_ASSETS)Object.freeze(asset);Object.freeze(SAMPLE_ASSETS);
const assetIndex=new Map(SAMPLE_ASSETS.map(a=>[a.id,a]));
const presetZones=new Map(Object.entries(SAMPLE_PRESETS).map(([id,p])=>{const groups=new Map();for(const key of p.assets){const a=assetIndex.get(key);if(!groups.has(a.root))groups.set(a.root,[]);groups.get(a.root).push(a)}for(const group of groups.values())group.sort((a,b)=>a.maxVelocity-b.maxVelocity);return [id,groups]}));
export function samplePreset(id){if(typeof id!=='string'||!Object.hasOwn(SAMPLE_PRESETS,id))throw Error('不支持的采样音源');return SAMPLE_PRESETS[id]}
export function samplerInfo(id){const preset=samplePreset(id),roots=[...presetZones.get(id).keys()].sort((a,b)=>a-b),assets=preset.assets.map(sampleAsset);return {roots,velocityLayers:Math.max(...roots.map(root=>new Set(assets.filter(a=>a.root===root).map(a=>a.maxVelocity)).size)),alternateTakes:Math.max(...assets.map(a=>(a.roundRobin??0)+1)),files:assets.length,bytes:assets.reduce((n,a)=>n+a.bytes,0),looped:assets.some(a=>a.loopEnd!==undefined),range:[roots[0],roots.at(-1)]}}
export function normalizeSampler(instrument,input){
 if(!Object.hasOwn(INSTRUMENTS,instrument)||!input||typeof input!=='object'||Array.isArray(input)||Object.keys(input).some(x=>!['preset','gain','release','cutoff'].includes(x)))throw Error('采样设置不正确');
 const preset=samplePreset(input.preset);if(preset.instrument!==instrument)throw Error('采样与当前音源不兼容');
 const out={preset:input.preset,gain:input.gain??preset.gain,release:input.release??preset.release,cutoff:input.cutoff??18000};
 for(const [key,min,max] of [['gain',.05,1.5],['release',.02,2],['cutoff',200,18000]]){if(!Number.isFinite(out[key])||out[key]<min||out[key]>max)throw Error('采样参数超出范围：'+key);out[key]=+out[key].toFixed(4)}return out;
}
export function sampleAsset(id){const asset=assetIndex.get(id);if(!asset)throw Error('采样文件不存在');return asset}
function takeIndex(take){if(!Number.isSafeInteger(take)||take<0||take>0xffffffff)throw Error('Invalid recorded take index');return take}
function recordedLayers(group){const layers=new Map();for(const asset of group){if(!layers.has(asset.maxVelocity))layers.set(asset.maxVelocity,[]);layers.get(asset.maxVelocity).push(asset)}return [...layers.values()].map(takes=>takes.sort((a,b)=>(a.roundRobin??0)-(b.roundRobin??0)))}
export function pickSample(presetId,pitch,velocity,take=0){
 samplePreset(presetId);takeIndex(take);if(!Number.isInteger(pitch)||pitch<24||pitch>108||!Number.isInteger(velocity)||velocity<1||velocity>127)throw Error('采样音符参数不正确');
 const zones=presetZones.get(presetId),roots=[...zones.keys()].sort((a,b)=>Math.abs(a-pitch)-Math.abs(b-pitch)||a-b),group=zones.get(roots[0]),layers=recordedLayers(group),chosen=layers.find(x=>velocity<=x[0].maxVelocity)||layers.at(-1);
 return chosen[take%chosen.length];
}
export function sampleLayers(presetId,pitch,velocity,take=0){
 const chosen=pickSample(presetId,pitch,velocity,take),layers=recordedLayers(presetZones.get(presetId).get(chosen.root)),at=i=>layers[i][take%layers[i].length];
 if(layers.length===1)return [{asset:at(0),weight:1}];
 // Preserve legacy two-layer blending exactly; new libraries use recorded dynamic centers.
 const anchors=layers.map(x=>x[0].velocityAnchor);if(anchors.every(Number.isFinite)){
  if(velocity<=anchors[0])return [{asset:at(0),weight:1}];if(velocity>=anchors.at(-1))return [{asset:at(layers.length-1),weight:1}];
  const hi=anchors.findIndex(x=>x>=velocity),lo=hi-1,mix=(velocity-anchors[lo])/(anchors[hi]-anchors[lo]);return [{asset:at(lo),weight:1-mix},{asset:at(hi),weight:mix}].filter(x=>x.weight>0);
 }
 const mix=(velocity-1)/126;return [{asset:at(0),weight:1-mix},{asset:at(layers.length-1),weight:mix}].filter(x=>x.weight>0);
}
export function sampleAssetsForPitches(presetId,pitches){
 const preset=samplePreset(presetId);if(pitches===undefined)return [...preset.assets];if(!Array.isArray(pitches)||pitches.length>12000)throw Error('Invalid sample pitch selection');const roots=new Set(pitches.map(p=>pickSample(presetId,p,64).root));return preset.assets.filter(id=>roots.has(sampleAsset(id).root));
}
export function sampleVoicePlan(instrument,settings,pitch,duration,velocity,bufferDuration,assetId){
 const config=normalizeSampler(instrument,settings),preset=samplePreset(config.preset),chosen=pickSample(config.preset,pitch,velocity),asset=assetId===undefined?chosen:sampleAsset(assetId);if(!preset.assets.includes(asset.id)||asset.root!==chosen.root)throw Error('采样层不兼容');
 if(!Number.isFinite(duration)||duration<=0||!Number.isFinite(bufferDuration)||bufferDuration<=0)throw Error('采样播放长度不正确');
 const loop=preset.kind==='tonal'&&Number.isFinite(asset.loopStart)&&Number.isFinite(asset.loopEnd)&&asset.loopStart>=0&&asset.loopEnd>asset.loopStart&&asset.loopEnd<=bufferDuration;
 const rate=preset.kind==='tonal'?2**((pitch-asset.root+(asset.tuneCents??0)/100)/12):1,natural=bufferDuration/rate,end=loop?duration+config.release:Math.min(natural,preset.kind==='tonal'?duration+config.release:config.release),releaseAt=preset.kind==='tonal'?Math.min(duration,Math.max(0,end-.01)):Math.max(0,end-Math.min(.04,end/4));
 const zonePeak=Math.max(...presetZones.get(config.preset).get(asset.root).map(a=>a.peak)),balance=preset.balance?Math.min(4,preset.balance/zonePeak):1;
 return {asset,rate,end,releaseAt,attack:Math.min(preset.attack??.003,end/4),peak:config.gain*(velocity/127)*(preset.kind==='tonal'?.6:.8)*balance,cutoff:config.cutoff,loop,loopStart:loop?asset.loopStart:0,loopEnd:loop?asset.loopEnd:0};
}
