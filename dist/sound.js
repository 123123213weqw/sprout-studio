import {normalizeSampler} from './sampler-core.js';
import {INSTRUMENTS} from './instruments.js';
const round=n=>+n.toFixed(4),clamp=(n,a,b)=>Math.max(a,Math.min(b,n));
export const WAVEFORMS={native:'原生多层',sine:'正弦 · 纯净',triangle:'三角 · 柔和',sawtooth:'锯齿 · 丰富',square:'方波 · 明显'};
export const SOUND_DEFAULTS={
 kick:{decay:.37,tone:43},snare:{decay:.19,tone:1800,body:.3},hat:{decay:.085,tone:8000},
 bass:{attack:.008,decay:.08,sustain:.82,release:.06,cutoff:800,resonance:.55,waveform:'native'},
 keys:{attack:.008,decay:.35,sustain:.72,release:.17,cutoff:3200,resonance:.55,waveform:'native'},
 lead:{attack:.008,decay:.12,sustain:.82,release:.15,cutoff:3200,resonance:.55,waveform:'native'},
 pad:{attack:.28,decay:.6,sustain:.8,release:.6,cutoff:1500,resonance:.55,waveform:'native'},
 pluck:{attack:.008,decay:.24,sustain:.15,release:.24,cutoff:3200,resonance:.55,waveform:'native'}
};
const melodicFields=[
 {key:'attack',label:'慢慢出现',technical:'Attack',min:.001,max:2,step:.001,unit:'秒',hint:'从安静升到峰值。短音会在起音中提前进入释放，不强行发满。'},
 {key:'release',label:'松开后余音',technical:'Release',min:.005,max:3,step:.005,unit:'秒',hint:'音符结束后淡出。循环右边界会硬停止，离线 WAV 会保留尾音。'},
 {key:'cutoff',label:'明亮程度',technical:'Low-pass',min:30,max:18000,step:10,unit:'Hz',log:true,hint:'低通截止频率；越高保留的高频越多。'},
 {key:'sustain',label:'持续的音量',technical:'Sustain',min:0,max:1,step:.01,unit:'比例',hint:'衰减后维持的峰值比例，不是轨道音量。'},
 {key:'decay',label:'从峰值落下',technical:'Decay',min:.005,max:2,step:.005,unit:'秒',advanced:true,hint:'从峰值衰减到持续音量的时间。'},
 {key:'resonance',label:'滤波突出感',technical:'Q',min:.1,max:4,step:.05,unit:'Q',advanced:true,hint:'突出截止频率附近的频率；不是混响或 EQ。'}
];
export function soundDefinition(instrument){
 if(typeof instrument!=='string'||!Object.hasOwn(INSTRUMENTS,instrument))throw Error('不支持的音源');
 if(INSTRUMENTS[instrument].kind==='tonal')return{kind:'tonal',fields:melodicFields.map(x=>({...x}))};
 const range=instrument==='kick'?[30,100]:instrument==='snare'?[300,6000]:[2000,14000];
 return{kind:'drum',fields:[{key:'decay',label:'鼓声长短',technical:'Decay',min:.02,max:1.5,step:.005,unit:'秒',hint:'一次击打的自然衰减，与 MIDI 音符的网格长度分开。'},{key:'tone',label:instrument==='kick'?'鼓体音高':'明亮程度',technical:instrument==='kick'?'Body Hz':'Filter Hz',min:range[0],max:range[1],step:instrument==='kick'?1:10,unit:'Hz',log:instrument!=='kick',hint:instrument==='kick'?'鼓体最终频率；MIDI 仍导出底鼓音高 36。':'改变噪声滤波中心 / 截止，不改变导出的 MIDI 鼓音高。'},...(instrument==='snare'?[{key:'body',label:'鼓体 / 沙沙声',technical:'Body mix',min:0,max:1,step:.01,unit:'比例',hint:'0 为纯噪声，1 为鼓体振荡器。'}]:[])]};
}
export function normalizeSound(instrument,input={}){
 const definition=soundDefinition(instrument),defaults=SOUND_DEFAULTS[instrument];
 if(!input||typeof input!=='object'||Array.isArray(input))throw Error('音色设置须为对象');
 if(Object.keys(input).some(key=>!Object.hasOwn(defaults,key)))throw Error('这个音源包含未知或不适用的音色参数');
 const result={...defaults,...input};for(const field of definition.fields){const value=result[field.key];if(!Number.isFinite(value)||value<field.min||value>field.max)throw Error(`${field.label}须为 ${field.min}–${field.max} ${field.unit}`);result[field.key]=round(value)}
 if(definition.kind==='tonal'&&(typeof result.waveform!=='string'||!Object.hasOwn(WAVEFORMS,result.waveform)))throw Error('不支持的波形');return result;
}
export const SOUND_PRESETS=[{id:'soft',name:'柔和一点',description:'慢起音 · 收一点高频'},{id:'clear',name:'清晰一点',description:'快起音 · 留更多高频'},{id:'short',name:'短促一点',description:'少一点持续与尾音'}];
export function soundPreset(instrument,id){
 const defaults=normalizeSound(instrument);if(!SOUND_PRESETS.some(p=>p.id===id))throw Error('不存在这个音色预设');const definition=soundDefinition(instrument);let values;
 if(definition.kind==='tonal'){values=id==='soft'?{attack:Math.max(.05,defaults.attack*1.5),decay:.4,sustain:.65,release:Math.min(1.8,defaults.release*2+.2),cutoff:defaults.cutoff*.55,resonance:.5,waveform:'native'}:id==='clear'?{attack:.005,decay:.12,sustain:.75,release:.14,cutoff:defaults.cutoff*2.2,resonance:.65,waveform:'native'}:{attack:.003,decay:.08,sustain:.1,release:.055,cutoff:defaults.cutoff,resonance:.5,waveform:'native'}}
 else{values=id==='soft'?{decay:defaults.decay*1.3,tone:defaults.tone*.8}:id==='clear'?{decay:defaults.decay*.8,tone:defaults.tone*1.2}:{decay:defaults.decay*.4,tone:defaults.tone};if(instrument==='snare')values.body=id==='soft'?.55:id==='clear'?.2:.35}
 for(const field of definition.fields)if(values[field.key]!==undefined)values[field.key]=round(clamp(values[field.key],field.min,field.max));return normalizeSound(instrument,values);
}
// Linear ADSR with an early note-off sampled continuously during attack/decay.
export function envelopePlan(duration,sound){
 if(!Number.isFinite(duration)||duration<=0)throw Error('音符时长须为正数');const {attack,decay,sustain,release}=sound;
 if(![attack,decay,sustain,release].every(Number.isFinite)||attack<=0||decay<=0||release<=0||sustain<0||sustain>1)throw Error('包络参数不正确');
 const points=[{time:0,value:0}],attackEnd=Math.min(duration,attack);points.push({time:attackEnd,value:attackEnd/attack});
 if(duration>attack){const decayEnd=Math.min(duration,attack+decay);points.push({time:decayEnd,value:1-(1-sustain)*(decayEnd-attack)/decay});if(duration>attack+decay)points.push({time:duration,value:sustain})}
 const offLevel=points.at(-1).value;points.push({time:duration+release,value:0});return{points,duration,end:duration+release,offLevel};
}
export function envelopeValue(plan,time){if(time<=0)return 0;for(let i=1;i<plan.points.length;i++){const a=plan.points[i-1],b=plan.points[i];if(time<=b.time)return a.value+(b.value-a.value)*(time-a.time)/(b.time-a.time)}return 0}
export function audioTailSeconds(project){let tail=1.5;for(const t of project.tracks)if(t.sampler!==undefined){const sampler=normalizeSampler(t.instrument,t.sampler);tail=Math.max(tail,sampler.release+1.02)}else if(t.sound!==undefined){const sound=normalizeSound(t.instrument,t.sound);tail=Math.max(tail,(t.kind==='drum'?sound.decay+.02:sound.release+.02)+1)}return round(tail)}
