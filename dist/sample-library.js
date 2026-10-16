import {sampleAsset,samplePreset,sampleVoicePlan,sampleLayers,normalizeSampler,sampleAssetsForPitches} from './sampler-core.js';
const ascii=(v,off,n)=>Array.from({length:n},(_,i)=>String.fromCharCode(v.getUint8(off+i))).join('');
export function decodeSamplePCM(bytes){
 const b=bytes instanceof ArrayBuffer?new Uint8Array(bytes):bytes;if(!(b instanceof Uint8Array)||b.byteLength<44||b.byteLength>1200000)throw Error('采样文件大小不正确');
 const v=new DataView(b.buffer,b.byteOffset,b.byteLength);if(ascii(v,0,4)!=='RIFF'||ascii(v,8,4)!=='WAVE'||v.getUint32(4,true)+8!==b.byteLength)throw Error('采样不是完整 WAV');
 let fmt=null,data=null,off=12;for(;off+8<=b.length;){const id=ascii(v,off,4),size=v.getUint32(off+4,true),start=off+8;if(start+size>b.length)throw Error('采样 WAV 区块损坏');
  if(id==='fmt '){if(fmt||size<16)throw Error('采样格式区块不正确');fmt={format:v.getUint16(start,true),channels:v.getUint16(start+2,true),rate:v.getUint32(start+4,true),byteRate:v.getUint32(start+8,true),align:v.getUint16(start+12,true),bits:v.getUint16(start+14,true)}}
  if(id==='data'){if(data)throw Error('采样数据区块重复');data={start,size}}off=start+size+(size%2);
 }
 if(off!==b.length)throw Error('采样 WAV 末尾区块不完整');
 if(!fmt||!data||fmt.format!==1||fmt.bits!==16||![1,2].includes(fmt.channels)||fmt.rate<16000||fmt.rate>96000||fmt.align!==fmt.channels*2||fmt.byteRate!==fmt.rate*fmt.align||data.size%fmt.align)throw Error('仅支持完整的 16-bit PCM 采样');
 const frames=data.size/fmt.align;if(frames<16||frames/fmt.rate>6.1)throw Error('采样长度不正确');const channels=Array.from({length:fmt.channels},()=>new Float32Array(frames));
 for(let i=0;i<frames;i++)for(let ch=0;ch<fmt.channels;ch++)channels[ch][i]=v.getInt16(data.start+i*fmt.align+ch*2,true)/32768;
 return {frames,sampleRate:fmt.rate,channels,duration:frames/fmt.rate};
}
export function createSampleLibrary({fetchBytes=async asset=>{
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),15000);
 try{const url=new URL('./samples/'+asset.file,import.meta.url);url.searchParams.set('v',asset.sha256);const r=await fetch(url,{signal:controller.signal,cache:'force-cache'});if(!r.ok)throw Error('HTTP '+r.status);const length=Number(r.headers.get('content-length'));if(length&&length!==asset.bytes)throw Error('采样文件长度不匹配');return new Uint8Array(await r.arrayBuffer())}finally{clearTimeout(timer)}
},verify=async(bytes,expected)=>{if(!globalThis.crypto?.subtle)return;const digest=await crypto.subtle.digest('SHA-256',bytes);if([...new Uint8Array(digest)].map(x=>x.toString(16).padStart(2,'0')).join('')!==expected)throw Error('采样文件校验失败')}}={}){
 const RAW_LIMIT=96000000,CONTEXT_LIMIT=256000000,pcm=new Map(),pending=new Map(),contextBuffers=new WeakMap(),takeCounters=new WeakMap();let voices=0,lastAsset=null,lastError=null,totalPCM=0,evicted=0,nativeEvicted=0;
 const cost=data=>data.frames*data.channels.length*4;
 function touch(id){const data=pcm.get(id);pcm.delete(id);pcm.set(id,data);return data}
 function contextState(ctx){let state=contextBuffers.get(ctx);if(!state){state={buffers:new Map(),bytes:0,pins:new Set(),queue:Promise.resolve()};contextBuffers.set(ctx,state)}return state}
 async function load(id){const asset=sampleAsset(id);if(pcm.has(id))return touch(id);if(pending.has(id))return pending.get(id);
  const task=Promise.resolve().then(async()=>{try{const bytes=await fetchBytes(asset);if(bytes.byteLength!==asset.bytes)throw Error('采样文件长度不匹配');await verify(bytes,asset.sha256);const data=decodeSamplePCM(bytes);if(data.frames!==asset.frames||data.sampleRate!==asset.sampleRate||data.channels.length!==asset.channels)throw Error('采样参数不匹配');const size=cost(data);if(size>RAW_LIMIT)throw Error('Sample exceeds the 96 MB decoded cache budget');
   // Evict only decoded cache entries, never buffers used by scheduled voices.
   while(totalPCM+size>RAW_LIMIT){const first=pcm.keys().next().value;totalPCM-=cost(pcm.get(first));pcm.delete(first);evicted++}totalPCM+=size;pcm.set(id,data);return data;
  }catch(e){lastError='采样加载失败：'+asset.id;throw Error(lastError+'。请重试或切回合成音源。',{cause:e})}finally{pending.delete(id)}});pending.set(id,task);return task;
 }
 async function loadPreset(id){const ids=samplePreset(id).assets;for(let i=0;i<ids.length;i+=4)await Promise.all(ids.slice(i,i+4).map(load));lastError=null;return ids.length}
 const assetCost=id=>{const a=sampleAsset(id);return a.frames*a.channels*4};
 function selectedAssets(tracks){const ids=new Set();for(const t of tracks)if(t.sampler){const c=normalizeSampler(t.instrument,t.sampler);for(const id of sampleAssetsForPitches(c.preset,t.notes.map(n=>n.pitch)))ids.add(id)}return ids}
 function protectedCost(ids){return [...ids].reduce((n,id)=>n+assetCost(id),0)}
 function prepareIds(ctx,ids,protect=new Set(ids)){
  const state=contextState(ctx),task=state.queue.then(async()=>{const keep=new Set([...state.pins,...protect]);if(protectedCost(keep)>CONTEXT_LIMIT)throw Error('This sound combination exceeds the 256 MB prepared-buffer budget. Stop playback or use fewer sampled roots before retrying.');
   const missing=ids.filter(id=>!state.buffers.has(id)),extra=missing.reduce((n,id)=>n+assetCost(id),0);
   while(state.bytes+extra>CONTEXT_LIMIT){const candidate=[...state.buffers.keys()].find(id=>!keep.has(id));if(candidate===undefined)throw Error('Stop playback before loading more sampled voices. Active audio buffers were kept intact.');state.buffers.delete(candidate);state.bytes-=assetCost(candidate);nativeEvicted++}
   for(let i=0;i<missing.length;i+=4){const batch=missing.slice(i,i+4),data=await Promise.all(batch.map(load));for(let j=0;j<batch.length;j++){const d=data[j],b=ctx.createBuffer(d.channels.length,d.frames,d.sampleRate);d.channels.forEach((x,ch)=>b.getChannelData(ch).set(x));state.buffers.set(batch[j],b);state.bytes+=cost(d)}}lastError=null;return state.buffers;
  });state.queue=task.catch(()=>{});return task;
 }
 async function prepare(ctx,presetId){return prepareIds(ctx,sampleAssetsForPitches(presetId))}
 async function prepareNote(ctx,presetId,pitch){return prepareIds(ctx,sampleAssetsForPitches(presetId,[pitch]))}
 async function prepareTracks(ctx,tracks){const ids=selectedAssets(tracks);return prepareIds(ctx,[...ids],ids)}
 function retainTracks(ctx,tracks){const ids=selectedAssets(tracks),state=contextState(ctx);if([...ids].some(id=>!state.buffers.has(id)))throw Error('Selected sample roots are not prepared');state.pins=ids}
 function releaseTracks(ctx){const state=contextBuffers.get(ctx);if(state)state.pins.clear()}
 function resetPerformance(ctx){takeCounters.delete(ctx)}
 function stateTouch(map,id){const buffer=map.get(id);map.delete(id);map.set(id,buffer)}
 function play(ctx,target,instrument,pitch,when,duration,velocity,active,cutoff,settings){
  if(!Number.isFinite(when)||when<0||(!Number.isFinite(cutoff)&&cutoff!==Infinity)||cutoff<0)throw Error('采样调度时间不正确');
  const config=normalizeSampler(instrument,settings);let counters=takeCounters.get(ctx);if(!counters){counters=new Map();takeCounters.set(ctx,counters)}const key=config.preset+':'+pitch,take=counters.get(key)??0,layers=sampleLayers(config.preset,pitch,velocity,take),map=contextBuffers.get(ctx)?.buffers;if(layers.some(x=>!map?.has(x.asset.id)))throw Error('采样尚未加载，请重试播放');
  const plans=layers.map(layer=>({layer,buffer:map.get(layer.asset.id),plan:sampleVoicePlan(instrument,config,pitch,duration,velocity,map.get(layer.asset.id).duration,layer.asset.id)}));if(cutoff<=Math.max(ctx.currentTime,when))return;counters.set(key,(take+1)>>>0);
  for(const {layer,buffer,plan} of plans){const at=Math.max(ctx.currentTime,when),end=Math.min(at+plan.end,cutoff);if(end<=at)continue;
  stateTouch(map,layer.asset.id);const source=ctx.createBufferSource(),gain=ctx.createGain(),filter=ctx.createBiquadFilter();source.buffer=buffer;source.playbackRate.value=plan.rate;source.loop=plan.loop;if(plan.loop){source.loopStart=plan.loopStart;source.loopEnd=plan.loopEnd}filter.type='lowpass';filter.frequency.value=Math.min(plan.cutoff,ctx.sampleRate*.49);filter.Q.value=.55;
  const attack=Math.min(plan.attack,(end-at)/4),releaseAt=Math.min(Math.max(at+attack,at+plan.releaseAt),end),peak=plan.peak*layer.weight;gain.gain.setValueAtTime(0,at);gain.gain.linearRampToValueAtTime(peak,at+attack);gain.gain.setValueAtTime(peak,releaseAt);gain.gain.linearRampToValueAtTime(0,end);
  source.connect(filter);filter.connect(gain);gain.connect(target);active?.add(source);source.onended=()=>{active?.delete(source);source.disconnect();filter.disconnect();gain.disconnect()};source.start(at);source.stop(end);voices++;lastAsset=plan.asset.id;
  }
 }
 return {load,loadPreset,prepare,prepareNote,prepareTracks,retainTracks,releaseTracks,resetPerformance,play,status:ctx=>({loaded:pcm.size,pending:pending.size,pcmBytes:totalPCM,evicted,nativeEvicted,preparedBytes:ctx?contextBuffers.get(ctx)?.bytes??0:0,voices,lastAsset,lastError})};
}
export const sampleLibrary=createSampleLibrary();
