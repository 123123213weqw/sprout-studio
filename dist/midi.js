import {samplePreset} from './sampler-core.js';
import {BAR_LENGTHS,MAX_BARS} from './limits.js';
import {makeTrack,validateProject,uid,clamp,KEYS} from './music.js';

// Standard MIDI Files (SMF), format 0 / 1, metrical PPQ division.
// Parse first, then explicitly report the fixed-tempo/synth limitations before import.
export function decodeMIDI(input,{name='导入的 MIDI'}={}) {
  const bytes=input instanceof Uint8Array?input:new Uint8Array(input);
  if(bytes.length>5e6)throw Error('MIDI 文件不能超过 5 MB');
  const view=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);
  const text=(at,len)=>new TextDecoder().decode(bytes.subarray(at,at+len));
  const need=(at,len,end=bytes.length)=>{if(at+len>end)throw Error('MIDI 文件被截断或事件长度不正确')};
  need(0,14);if(text(0,4)!=='MThd')throw Error('不是标准 MIDI 文件（缺少 MThd）');
  const headerLength=view.getUint32(4);if(headerLength<6)throw Error('MIDI 头部不正确');need(8,headerLength);
  const format=view.getUint16(8),count=view.getUint16(10),ppq=view.getUint16(12);
  if(format!==0&&format!==1)throw Error('只支持标准 MIDI format 0 和 1，不支持独立多序列 format 2');
  if(!count||count>256||(format===0&&count!==1))throw Error('MIDI 轨道数量不正确');
  if(ppq&0x8000)throw Error('暂不支持 SMPTE 时间码 MIDI，请在原软件转成 PPQ 后导入');
  if(!ppq)throw Error('MIDI PPQ 不能为零');
  const raw=[],tempos=[],signatures=[],keys=[],flags=new Set();
  let offset=8+headerLength,eventCount=0,noteCount=0,lastTick=0,unclosed=0,unmatched=0;
  for(let index=0;index<count;index++) {
    // Unknown chunks are permitted by SMF; their lengths remain bounded by the file.
    while(true){need(offset,8);const len=view.getUint32(offset+4);need(offset+8,len);if(text(offset,4)==='MTrk')break;offset+=8+len}
    const end=offset+8+view.getUint32(offset+4);let at=offset+8,tick=0,running=0,trackName='',ended=false;
    const states=new Map(),active=new Map();
    const byte=()=>{need(at,1,end);return bytes[at++]};
    const vlq=()=>{let result=0;for(let i=0;i<4;i++){const b=byte();result=result*128+(b&127);if(!(b&128))return result}throw Error('MIDI 可变长整数超过 4 字节')};
    const state=channel=>{if(!states.has(channel))states.set(channel,{channel,program:0,firstProgram:null,volume:.7,pan:0,notes:[]});return states.get(channel)};
    while(at<end) {
      if(++eventCount>200000)throw Error('MIDI 事件过多（最多 200000）');tick+=vlq();if(tick>1e9)throw Error('MIDI 时间范围过大');
      let status=byte();if(status<128){if(!running)throw Error('MIDI running status 没有前置状态');at--;status=running}
      if(status===0xff){running=0;const type=byte(),len=vlq();need(at,len,end);const data=bytes.subarray(at,at+len);at+=len;
        if(type===0x2f){if(len!==0)throw Error('MIDI 结束事件长度不正确');ended=true;break}
        if(type===3)trackName=new TextDecoder().decode(data).replace(/[\u0000-\u001f]/g,'').slice(0,40);
        if(type===0x51){if(len!==3)throw Error('MIDI 速度事件长度不正确');const us=data[0]*65536+data[1]*256+data[2];if(!us)throw Error('MIDI 速度不能为零');tempos.push({tick,us})}
        if(type===0x58){if(len!==4)throw Error('MIDI 拍号事件长度不正确');signatures.push({tick,numerator:data[0],denominator:2**data[1]})}
        if(type===0x59){if(len!==2)throw Error('MIDI 调号事件长度不正确');keys.push({tick,sf:data[0]>127?data[0]-256:data[0],minor:data[1]===1})}
        continue;
      }
      if(status===0xf0||status===0xf7){running=0;const len=vlq();need(at,len,end);at+=len;flags.add('sysex');continue}
      if(status<0x80||status>0xef)throw Error('MIDI 包含不支持的系统事件');
      running=status;const type=status>>4,channel=status&15,a=byte(),b=type===0xc||type===0xd?0:byte();if(a>127||b>127)throw Error('MIDI 通道事件数据不正确');
      const s=state(channel),noteKey=channel+':'+a;
      if(type===9&&b>0){s.firstProgram??=s.program;const n={pitch:a,startTick:tick,velocity:b,program:s.program};if(!active.has(noteKey))active.set(noteKey,[]);active.get(noteKey).push(n);s.notes.push(n);if(++noteCount>12000)throw Error('MIDI 超过 12000 个音符上限')}
      else if(type===8||(type===9&&b===0)){const queue=active.get(noteKey);if(queue?.length)queue.shift().endTick=tick;else unmatched++}
      else if(type===0xc){if(s.firstProgram!==null&&s.program!==a)flags.add('program');s.program=a}
      else if(type===0xb){if(s.notes.length&&(a===7||a===10))flags.add('automation');else if(a===7)s.volume=b/127;else if(a===10)s.pan=(b-64)/64;if(a===64||a===66||a===67)flags.add('pedal');else if(a!==7&&a!==10)flags.add('controllers')}
      else if(type===0xe)flags.add('bend');else if(type===0xa||type===0xd)flags.add('pressure');
    }
    if(!ended)flags.add('missingEnd');lastTick=Math.max(lastTick,tick);
    for(const s of states.values())if(s.notes.length){for(const n of s.notes)if(n.endTick===undefined){n.endTick=Math.max(n.startTick+1,tick);unclosed++}raw.push({...s,name:trackName||`MIDI 轨道 ${index+1}`,index})}
    offset=end;
  }
  if(!raw.length)throw Error('MIDI 文件没有可导入的音符');
  if(offset<bytes.length)flags.add('trailing');
  tempos.sort((a,b)=>a.tick-b.tick);const tempoAtZero=tempos.filter(t=>t.tick===0).at(-1)?.us||500000;
  const requestedBpm=60000000/tempoAtZero,bpm=clamp(+requestedBpm.toFixed(3),40,200);
  const sourceBeats=Math.max(lastTick,...raw.flatMap(t=>t.notes.map(n=>n.endTick)))/ppq;
  const sourceBars=Math.max(1,Math.ceil(sourceBeats/4-.00001)),bars=BAR_LENGTHS.find(b=>b>=sourceBars)||MAX_BARS;
  let key='C major';const keyEvent=keys.filter(k=>k.tick===0).at(-1);
  if(keyEvent){const roots=keyEvent.minor?['A♭','E♭','B♭','F','C','G','D','A','E','B','F♯','C♯','G♯','D♯','A♯']:['C♭','G♭','D♭','A♭','E♭','B♭','F','C','G','D','A','E','B','F♯','C♯'];const label=roots[keyEvent.sf+7]+(keyEvent.minor?' minor':' major');if(KEYS[label])key=label;else flags.add('key')}
  const tracks=[],stats={sourceNotes:raw.reduce((sum,t)=>sum+t.notes.length,0),importedNotes:0,outOfRange:0,unsupportedDrums:0,trimmed:0,shortened:0,shortNotes:0};
  const instrumentFor=program=>samplePreset('fluid-'+String(program).padStart(3,'0')).instrument;
  for(const s of raw){const groups=new Map();for(const n of s.notes){const start=+(n.startTick/ppq).toFixed(4),end=+(n.endTick/ppq).toFixed(4);
      if(start>bars*4-.03125){stats.trimmed++;continue}
      let instrument;if(s.channel===9){instrument=[35,36].includes(n.pitch)?'kick':[37,38,39,40].includes(n.pitch)?'snare':[42,44,46,70].includes(n.pitch)?'hat':null;if(!instrument){stats.unsupportedDrums++;continue}}
      else{if(n.pitch<24||n.pitch>108){stats.outOfRange++;continue}instrument=instrumentFor(s.firstProgram??s.program)}
      if(!groups.has(instrument)){const t=makeTrack(instrument);t.name=(s.name+(s.channel===9&&s.name!==t.name?' · '+t.name:'')).slice(0,40);t.volume=s.volume;t.pan=clamp(s.pan,-1,1);t.notes=[];groups.set(instrument,t)}
      if(end>bars*4)stats.shortened++;let duration=Math.min(end,bars*4)-start;if(duration<.03125){duration=.03125;stats.shortNotes++}
      groups.get(instrument).notes.push({id:uid(),pitch:s.channel===9?({kick:36,snare:38,hat:42}[instrument]):n.pitch,start,duration:+duration.toFixed(4),velocity:n.velocity});stats.importedNotes++;
    }tracks.push(...groups.values())}
  if(!tracks.length)throw Error('没有可用音符：仅支持音高 24–108 和底鼓、军鼓、踩镲');if(tracks.length>16)throw Error(`映射后有 ${tracks.length} 条轨道，超过 16 条上限。请在原软件拆分导出。`);
  const warnings=['声音会映射为内置合成音源，不会还原原软件的音色或效果。'];
  if(sourceBars>MAX_BARS)warnings.push(`原文件约 ${sourceBars} 小节，仅导入前 64 小节（${stats.trimmed} 个音符超出范围）。`);
  if(new Set(tempos.map(t=>t.us)).size>1||tempos.some(t=>t.tick>0&&t.us!==tempoAtZero))warnings.push('原文件含速度变化；本版按起始速度播放，音符的拍位置不变。');
  if(bpm!==+requestedBpm.toFixed(3))warnings.push(`原速度 ${requestedBpm.toFixed(1)} BPM 已限制到 ${bpm} BPM。`);
  if(signatures.some(s=>s.numerator!==4||s.denominator!==4))warnings.push('原文件含非 4/4 拍号；本版用每 4 拍一小节显示，不移动音符。');
  if(flags.has('key'))warnings.push('原调号暂不支持，显示为 C 大调；音高原样保留，不自动转调。');
  if(keys.some(k=>k.tick>0))warnings.push('调号变化仅作音符保留；当前只显示起始调性。');
  if(!keyEvent)warnings.push('未指定调号，显示为 C 大调；不会改变音高。');
  if(stats.unsupportedDrums)warnings.push(`${stats.unsupportedDrums} 个其他打击乐音符未导入；只映射底鼓、军鼓和踩镲。`);
  if(stats.outOfRange)warnings.push(`${stats.outOfRange} 个超出音高 24–108 的音符未导入。`);
  if(stats.shortened)warnings.push(`${stats.shortened} 个跨工程终点的音符已裁短。`);
  if(stats.shortNotes)warnings.push(`${stats.shortNotes} 个极短音符延长到 1/128 全音符。`);
  if(flags.has('program'))warnings.push('轨道中途换音色使用第一次发声时的音色映射。');
  if([...flags].some(f=>['automation','pedal','controllers','bend','pressure','sysex'].includes(f)))warnings.push('音量/声像自动化、踏板、弯音、触后及 SysEx 暂未还原；只保留初始混音和音符。');
  if(unclosed)warnings.push(`${unclosed} 个未配对的 note-on 已在轨道末尾结束。`);
  if(unmatched)warnings.push(`${unmatched} 个无对应 note-on 的 note-off 已忽略。`);
  if(flags.has('missingEnd'))warnings.push('部分轨道缺少结束标记，已按轨道数据边界恢复。');
  if(flags.has('trailing'))warnings.push('已忽略轨道之后的附加数据。');
  // One region per imported track preserves sustained notes across legacy 2-bar seams.
  for(const t of tracks)t.clips=[{id:uid(),name:t.name,start:0,length:bars*4,muted:false}];
  const project=validateProject({version:2,id:uid(),name:String(name).replace(/\.(mid|midi)$/i,'').slice(0,60),style:'lofi',key,bars,bpm,swing:0,master:.75,seed:1,tracks});
  return {project,report:{format,ppq,sourceBars,bars,bpm,key,tracks:tracks.length,...stats,warnings}};
}
