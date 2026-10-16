from pathlib import Path
import ctypes,json,hashlib,wave,shutil,time
import numpy as np
w=Path(__file__).resolve().parent;out=w/'processed';out.mkdir(exist_ok=True)
sha=lambda b:hashlib.sha256(b).hexdigest();bank=w/'FluidR3_GM.sf2';assert sha(bank.read_bytes())=='74594e8f4250680adf590507a306655a299935343583256f3b722c48a1bc1cb0'
lib=ctypes.CDLL(str(w/'render-bank.dylib'));lib.open_bank.argtypes=[ctypes.c_char_p];lib.open_bank.restype=ctypes.c_int;lib.preset_name.argtypes=[ctypes.c_int];lib.preset_name.restype=ctypes.c_char_p;lib.render_note.argtypes=[ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.POINTER(ctypes.c_float),ctypes.c_int];lib.render_note.restype=ctypes.c_int
assert lib.open_bank(str(bank).encode())>=128;rate=44100;assets=[];presets={};report=[]
family=['Pianos','Mallets','Organs','Guitars','Basses','Solo strings','Strings and choir','Brass','Reeds','Winds','Synth leads','Synth pads','Textures','World instruments','Tuned percussion','Sound effects']
def settings(p):
 cat=family[p//8]
 if p<8:role='keys';roots=list(range(24,97,6));loop=False;cap=5
 elif p<16:role='pluck';roots=list(range(48,97,4));loop=False;cap=4
 elif p<24:role='keys';roots=list(range(36,97,6));loop=True;cap=3.6
 elif p<32:role='pluck';roots=list(range(40,89,4));loop=False;cap=4
 elif p<40:role='bass';roots=list(range(28,65,4));loop=p>=38;cap=3.6
 elif p==43:role='bass';roots=list(range(28,65,4));loop=True;cap=4
 elif p<48:role='lead' if p in [40,41] else 'pad' if p in [42,44] else 'pluck';roots=list(range(48,89,4));loop=p not in [45,46,47];cap=4
 elif p<56:role='pad';roots=list(range(48,85,4));loop=p!=55;cap=3.6;cat='Choirs and voices' if p in [52,53,54] else 'Strings'
 elif p<80:role='lead';roots=list(range(48 if p<72 else 60,89 if p<72 else 97,4));loop=True;cap=3.6
 elif p<88:role='lead';roots=list(range(48,97,4));loop=True;cap=3.6
 elif p<104:role='pad';roots=list(range(36,85,6));loop=True;cap=3.6
 elif p in [109,110,111]:role='lead';roots=list(range(48,89,4));loop=True;cap=3.6
 elif p<120:role='pluck';roots=list(range(48,97,4));loop=False;cap=4
 else:role='lead';roots=[60];loop=False;cap=4
 return cat,role,roots,loop,cap

def write(id,x,root,maxvel,anchor,p,loop,cap,extra):
 inputPeak=float(np.max(np.abs(x)));threshold=max(1e-6,inputPeak*.0005);found=np.flatnonzero(np.abs(x)>=threshold);trim=min(int(found[0]) if len(found) else 0,len(x)-441);x=x[trim:].copy();meta={}
 if loop:
  start=int(.9*rate);end=min(int(2.9*rate),len(x)-int(.2*rate));overlap=int(.12*rate)
  if end-start<rate*.7:raise ValueError('Insufficient sustain '+id)
  weights=np.linspace(0,1,overlap);x[end-overlap:end]=x[end-overlap:end]*(1-weights)+x[start:start+overlap]*weights
  meta=dict(loopStart=(start+overlap)/rate,loopEnd=end/rate,loopCrossfadeFrames=overlap)
 fade=min(2205,len(x)//4);x[-fade:]*=np.linspace(1,0,fade);assert np.max(np.abs(x))<.99,id
 pcm=np.rint(np.clip(x,-1,1)*32767).astype('<i2');target=out/(id+'.wav')
 with wave.open(str(target),'wb') as wav:wav.setparams((1,2,rate,len(pcm),'NONE','not compressed'));wav.writeframes(pcm.tobytes())
 if loop:meta['loopSeamDelta']=abs(int(pcm[round(meta['loopEnd']*rate)-1])-int(pcm[round(meta['loopStart']*rate)]))/32768
 b=target.read_bytes();r=dict(id=id,file='fluid/'+id+'.wav',root=root,maxVelocity=maxvel,velocityAnchor=anchor,frames=len(pcm),sampleRate=rate,channels=1,bytes=len(b),sha256=sha(b),peak=float(np.max(np.abs(pcm.astype(np.int32))))/32768,library='FluidR3 GM',sourceProgram=p,sourceBank=0,sourceSha256=sha_bank,sourceFile='FluidR3_GM.sf2',sourceRelease='v3.1',leadingFramesRemoved=trim,maxSeconds=cap,endFadeFrames=fade,**extra,**meta);assets.append(r);return r
sha_bank=sha(bank.read_bytes());startTime=time.time()
for p in range(128):
 cat,role,roots,loop,cap=settings(p);name=lib.preset_name(p).decode('latin1').strip();preset_id=f'fluid-{p:03}';records=[];kept=0
 for root in roots:
  renders=[]
  for vel in [48,104]:
   x=np.zeros(round(cap*rate),dtype=np.float32);assert lib.render_note(p,root,vel,x.ctypes.data_as(ctypes.POINTER(ctypes.c_float)),len(x));assert np.isfinite(x).all();x=x.astype(np.float64)*(127/vel);renders.append(x)
  if max(np.max(np.abs(x)) for x in renders)<=1e-6:
   print('SKIP unsupported silent root',p,root,flush=True);continue
  a,b=renders;relative=float(np.sqrt(np.mean((a-b)**2))/max(1e-10,np.sqrt(np.mean(b*b))));same=relative<.002
  chosen=[(104,b)] if same else [(48,a),(104,b)];peak=max(float(np.max(np.abs(x))) for _,x in chosen);scale=min(200,.68/peak)
  for vel,x in chosen:
   id=f'fluid-{p:03}-{root}-v{vel}';r=write(id,x*scale,root,127 if same or vel==104 else 80,64 if same else vel,p,loop,cap,dict(normalizationGain=scale,renderVelocity=vel,velocityGainCompensation=127/vel,velocityResponsesMerged=same,unmergedRelativeDifference=relative));records.append(id);kept+=1
 assert records,(p,'No playable roots');actual_roots=sorted(set(a['root'] for a in assets if a['sourceProgram']==p))
 description=f'FluidR3 GM bank 0 program {p+1}: {name}. Pre-rendered SoundFont response; acoustic/electronic source varies. {len(actual_roots)} roots, '+('crossfaded sustain loop.' if loop else 'natural one-shot decay.')+' Not a full SF2 engine or a fresh instrument recording.'
 presets[preset_id]=dict(name=name+' · Fluid',instrument=role,label=name.upper()[:22],kind='tonal',category=cat,origin='soundfont',source='fluid',gain=.75 if role in ['lead','pad'] else .85,release=.5 if role=='pad' else .25 if role=='bass' else .35,attack=.003,previewDuration=1.1 if loop else .7,program=p,balance=.68,description=description,assets=records)
 report.append(dict(program=p,name=name,category=cat,roots=actual_roots,files=kept,looped=loop));(w/'conversion-progress.json').write_text(json.dumps(dict(completedPrograms=p+1,totalPrograms=128,files=len(assets),seconds=time.time()-startTime,last=name),indent=2)+'\n');print(p,name,kept,flush=True)
lib.close_bank();(w/'fluid-assets.json').write_text(json.dumps(assets,indent=2)+'\n');(w/'fluid-presets.json').write_text(json.dumps(presets,indent=2)+'\n');(w/'fluid-report.json').write_text(json.dumps(dict(sourceSha256=sha_bank,sourceBytes=bank.stat().st_size,converterHeaderSha256=sha((w/'tsf.h').read_bytes()),converterSourceSha256=sha((w/'render-bank.c').read_bytes()),converter='TinySoundFont; local C-only offline conversion',programs=report,files=len(assets),bytes=sum(a['bytes'] for a in assets),seconds=time.time()-startTime),indent=2)+'\n');print('DONE',len(assets),sum(a['bytes'] for a in assets),time.time()-startTime,flush=True)
