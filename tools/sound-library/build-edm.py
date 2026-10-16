from pathlib import Path
import json,hashlib,wave
import numpy as np
w=Path(__file__).resolve().parent;out=w/'processed-edm';out.mkdir(exist_ok=True);rate=44100;dsp_rate=rate*4;assets=[];presets={};sha=lambda b:hashlib.sha256(b).hexdigest()
def blep(p,dt):
 y=np.zeros_like(p);m=p<dt;x=p[m]/dt;y[m]=2*x-x*x-1;m=p>1-dt;x=(p[m]-1)/dt;y[m]=x*x+2*x+1;return y
def saw(f,t,phase=0):
 p=(f*t+phase)%1;return 2*p-1-blep(p,f/dsp_rate)
def pulse(f,t,width=.5,phase=0):
 p=(f*t+phase)%1;return np.where(p<width,1.,-1.)+blep(p,f/dsp_rate)-blep((p-width)%1,f/dsp_rate)
def tri(f,t):
 y=np.zeros_like(t)
 for n in range(1,min(64,int(dsp_rate/2/f)),2):y+=(-1)**((n-1)//2)*np.sin(2*np.pi*n*f*t)/(n*n)
 return y*.8

def filt(x,cut,low=0):
 freqs=np.fft.rfftfreq(len(x),1/dsp_rate);h=1/np.sqrt(1+(freqs/max(40,cut))**8)
 if low:h*=np.sqrt(1-1/(1+(freqs/max(20,low))**8))
 return np.fft.irfft(np.fft.rfft(x)*h,n=len(x))
def signal(index,f,t,strength):
 if index==0:return np.sin(2*np.pi*(f*t+f*.9*.04*(1-np.exp(-t/.04))))*np.exp(-t/1.4)
 if index==1:return filt(.7*pulse(f,t,.35)+.3*np.sin(np.pi*f*t),600+strength*2200)*( .65+.35*np.exp(-t/.15))
 if index==2:return filt(saw(f*2**(-9/1200),t,.1)+saw(f*2**(9/1200),t,.6)+.7*np.sin(np.pi*f*t),800+strength*3000)/2.7
 if index==3:
  x=pulse(f,t,.28);env=np.exp(-t/(.12+strength*.25));return filt(x,300)+env*(filt(x,5000)-filt(x,300))+.13*np.sin(2*np.pi*f*3*t)*env
 if index==4:return filt(np.sin(2*np.pi*f*t+3.5*np.sin(np.pi*f*t)*( .7+.3*np.sin(2*np.pi*1.5*t))),f*10)
 if index==5:return np.sin(2*np.pi*f*t+2*np.sin(2*np.pi*f*2*t)*np.exp(-t/.3))*(.65+.35*np.exp(-t/.2))
 if index==6:return sum(saw(f*2**(c/1200),t,(i*.137)%1) for i,c in enumerate([-18,-11,-5,0,5,11,18]))/5
 if index==7:return .7*saw(f,t,.1)+.2*saw(f*1.005,t,.7)+.1*np.sin(4*np.pi*f*t)
 if index==8:return .55*saw(f,t)+.3*saw(f*1.5,t,.3)+.15*np.sin(np.pi*f*t)
 if index==9:return np.sin(2*np.pi*f*t+2.3*np.sin(2*np.pi*f*3.5*t)*np.exp(-t/.4))
 if index==10:return .7*pulse(f,t,.18)+.3*tri(f,t)
 if index==11:return filt(saw(f,t)*(.7+.3*saw(f*2,t)),f*12)
 if index==12:return filt((saw(f*.997,t,.3)+saw(f*1.003,t,.7)+tri(f,t))/3,1200+strength*1800)*(1-np.exp(-t/.28))
 if index==13:return (sum(np.sin(2*np.pi*f*2**(c/1200)*t+i) for i,c in enumerate([-9,0,9]))/3+.08*filt(np.random.default_rng(130+round(f)).normal(size=len(t)),10000,5000))*(1-np.exp(-t/.55))
 if index==14:return filt((saw(f*.995,t,.2)+saw(f*1.005,t,.6)+saw(f*2,t,.4))/3,3000)*(1-np.exp(-t/.75))
 if index==15:return (np.sin(2*np.pi*f*t+np.sin(2*np.pi*f*2.01*t))+.25*np.sin(2*np.pi*f*1.5*t))*(1-np.exp(-t/.4))
 if index==16:return filt((pulse(f*.996,t,.4)+pulse(f*1.004,t,.6))/2,500+strength*700)*(1-np.exp(-t/.5))
 if index==17:return (tri(f,t)+.6*tri(f*1.5,t)+.2*np.sin(np.pi*f*t))*(1-np.exp(-t/.8))*.6
 if index==18:return filt(saw(f,t),800+strength*6000)*np.exp(-t/(.16+strength*.18))
 if index==19:return np.sin(2*np.pi*f*t+2*np.sin(2*np.pi*f*2*t)*np.exp(-t/.06))*np.exp(-t/.5)
 if index==20:return (np.sin(2*np.pi*f*t)+.45*np.sin(2*np.pi*f*2.756*t)+.2*np.sin(2*np.pi*f*5.404*t))*np.exp(-t/.8)
 if index==21:return np.sin(2*np.pi*f*t+3*np.sin(2*np.pi*f*3.51*t)*np.exp(-t/.2))*np.exp(-t/1.2)
 if index==22:return filt(pulse(f,t,.4),1800+strength*2500)*np.exp(-t/.38)
 if index==23:return (np.sin(2*np.pi*f*t)+.35*np.sin(2*np.pi*f*2.01*t)*np.exp(-t/.25)+.2*np.sin(2*np.pi*f*7.13*t)*np.exp(-t/.08))*np.exp(-t/.45)
 raise ValueError(index)

def write(id,x,root,v,cap,loop,extra):
 x=x.copy();meta={};fade=min(2205,len(x)//4)
 if loop:
  start=round(.9*rate);end=round(2.9*rate);overlap=5292;weights=np.linspace(0,1,overlap);x[end-overlap:end]=x[end-overlap:end]*(1-weights)+x[start:start+overlap]*weights;meta=dict(loopStart=1.02,loopEnd=2.9,loopCrossfadeFrames=overlap)
 x[:132]*=np.linspace(0,1,132);x[-fade:]*=np.linspace(1,0,fade);assert np.isfinite(x).all() and np.max(np.abs(x))<1
 pcm=np.rint(x*32767).astype('<i2');target=out/(id+'.wav')
 with wave.open(str(target),'wb') as f:f.setparams((1,2,rate,len(pcm),'NONE','not compressed'));f.writeframes(pcm.tobytes())
 if loop:meta['loopSeamDelta']=abs(int(pcm[round(meta['loopEnd']*rate)-1])-int(pcm[round(meta['loopStart']*rate)]))/32768
 b=target.read_bytes();assets.append(dict(id=id,file='edm/'+id+'.wav',root=root,maxVelocity=80 if v==48 else 127,velocityAnchor=v,frames=len(pcm),sampleRate=rate,channels=1,bytes=len(b),sha256=sha(b),peak=float(np.max(np.abs(pcm.astype(np.int32))))/32768,library='Sprout original synthesized EDM',source='Original deterministic NumPy DSP; band-limited oscillators, FM and filtered noise',recipeVersion=1,recipeSha256=recipeSHA,maxSeconds=cap,endFadeFrames=fade,**extra,**meta));return id
names=['Sub tail','Square punch','Detuned Reese','Acid pulse','FM growl','Rubber FM','Festival supersaw','Focused saw','Fifths stack','Glass FM lead','Narrow pulse lead','Edge stack','Warm analog pad','Air halo','Slow synth strings','Glass cloud','Dark pulse pad','Fifths atmosphere','Short saw pluck','FM marimba','Glass keys','Digital bell','Soft pulse pluck','Metallic pluck'];recipeSHA=sha(Path(__file__).read_bytes())
for i,name in enumerate(names):
 role=['bass','lead','pad','pluck'][i//6];roots=list(range(28,65,6)) if role=='bass' else list(range(36,85,6)) if role=='pad' else list(range(48,97,6));loop=role in ['lead','pad'] or role=='bass' and i!=0;ids=[];cap=3.6 if loop else 4
 for root in roots:
  t=np.arange(round(cap*dsp_rate))/dsp_rate;f=440*2**((root-69)/12);xx=[]
  for v in [48,104]:
   x=signal(i,f,t,(v-1)/126);freqs=np.fft.rfftfreq(len(x),1/dsp_rate);x=np.fft.irfft(np.fft.rfft(x)/np.sqrt(1+(freqs/19000)**24),n=len(x))[::4];xx.append(x)
  same=bool(np.array_equal(xx[0],xx[1]));chosen=[(104,xx[1])] if same else list(zip([48,104],xx));scale=.68/max(float(np.max(np.abs(x))) for _,x in chosen)
  for v,x in chosen:ids.append(write(f'edm-{role}-{i%6+1}-{root}-v{v}',x*scale,root,v,cap,loop,dict(recipe=i,normalizationGain=scale,oversampling=4,velocityResponsesMerged=same)))
 id=f'edm-{role}-{i%6+1}';presets[id]=dict(name=name+' · synthesized',instrument=role,label=name.upper()[:22],kind='tonal',category='EDM '+{'bass':'basses','lead':'leads','pad':'pads','pluck':'plucks'}[role],origin='synthesized',source='sprout-dsp',gain=.8,release=.7 if role=='pad' else .3,attack=.003,previewDuration=1.1 if role=='pad' else .7,program={'bass':38,'lead':81,'pad':89,'pluck':10}[role],balance=.68,description=f'Original synthesized {name.lower()}; deterministic oscillator/FM recipe, not an acoustic recording or sampled hardware. Dry source; '+('crossfaded held-note loop.' if loop else 'one-shot decay.'),assets=ids)
dsp_rate=rate
for group in ['kick','snare','hat']:
 for variant in range(4):
  cap=(1.8 if variant==0 else .8) if group=='kick' else .65 if group=='snare' else .9 if variant==3 else .3;t=np.arange(round(cap*rate))/rate;xx=[]
  for vel in [48,104]:
   strength=vel/127;rng=np.random.default_rng(29000+variant+{'kick':0,'snare':10,'hat':20}[group]);noise=rng.normal(0,1,len(t))
   if group=='kick':
    base=[48,57,62,52][variant];drop=[120,190,280,140][variant];tau=[.035,.018,.008,.025][variant];phase=2*np.pi*(base*t+drop*tau*(1-np.exp(-t/tau)));x=np.sin(phase)*np.exp(-t/[.6,.18,.12,.22][variant])+filt(noise,12000,3500)*np.exp(-t/.004)*(.08+strength*.12);x=np.tanh(x*(1+variant*.6))/(1+variant*.2)
   elif group=='snare':
    if variant==1:
     env=sum(np.where(t>=d,np.exp(-np.maximum(0,t-d)/.012),0) for d in [0,.014,.028,.042])+.4*np.exp(-t/.12);x=filt(noise,11000,900)*env
    elif variant==3:x=np.sin(2*np.pi*800*t)*np.exp(-t/.018)+.5*np.sin(2*np.pi*1550*t)*np.exp(-t/.009)+.15*noise*np.exp(-t/.012)
    else:x=filt(noise,10000,700)*np.exp(-t/[.09,.13,.18,.04][variant])*(.6+.4*strength)+.5*np.sin(2*np.pi*(180*t+5*(1-np.exp(-t/.02))))*np.exp(-t/.04)
   else:
    x=filt(noise,[15000,8000,11000,14500][variant],[5500,3500,6500,4500][variant])*np.exp(-t/[.035,.055,.075,.23][variant]);x+=sum(pulse(f,t) for f in [330,421,537,619,827,1043])*.008*np.exp(-t/.035)
   xx.append(x)
  same=bool(np.array_equal(xx[0],xx[1]));chosen=[(104,xx[1])] if same else list(zip([48,104],xx));scale=.68/max(float(np.max(np.abs(x))) for _,x in chosen);ids=[];root={'kick':36,'snare':38,'hat':42}[group]
  for vel,x in chosen:ids.append(write(f'edm-{group}-{variant+1}-v{vel}',x*scale,root,vel,cap,False,dict(recipe=group+str(variant),normalizationGain=scale,velocityResponsesMerged=same,noiseSeed=29000+variant+{'kick':0,'snare':10,'hat':20}[group])))
  label={'kick':['Deep sub kick','Tight punch kick','Click house kick','Driven techno kick'],'snare':['Snappy snare','Layered clap','Noise snare','Dry rim'],'hat':['Bright closed hat','Dark closed hat','Noise shaker','Open decay hat']}[group][variant];id=f'edm-{group}-{variant+1}';presets[id]=dict(name=label+' · synthesized',instrument=group,label=label.upper()[:22],kind='drum',category='EDM drums',origin='synthesized',source='sprout-dsp',gain=.85 if group=='kick' else .7 if group=='snare' else .55,release=min(cap,.5 if group!='hat' else .65 if variant==3 else .2),balance=.68,description='Original deterministic synthesized '+label.lower()+'. Not an acoustic kit recording or a branded hardware sample. No automatic open/closed-hat choke group.',assets=ids)
(w/'edm-assets.json').write_text(json.dumps(assets,indent=2)+'\n');(w/'edm-presets.json').write_text(json.dumps(presets,indent=2)+'\n');(w/'edm-report.json').write_text(json.dumps(dict(presets=len(presets),files=len(assets),bytes=sum(a['bytes'] for a in assets),recipeSha256=recipeSHA,license='CC0-1.0 for generated PCM'),indent=2)+'\n');print(len(presets),len(assets),sum(a['bytes'] for a in assets))
