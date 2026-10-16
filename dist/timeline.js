const clamp=(n,a,b)=>Math.max(a,Math.min(b,n));
export const VIEW_ZOOMS=['auto','fit','8','16','32'];
export function normalizeView(input={}){if(!input||typeof input!=='object'||Array.isArray(input)||Object.keys(input).some(k=>!['zoom','follow'].includes(k)))throw Error('时间线视图不正确');const out={zoom:'auto',follow:false,...input};if(!VIEW_ZOOMS.includes(out.zoom)||typeof out.follow!=='boolean')throw Error('时间线视图不正确');return out}
export function timelineLayout(bars,viewport,trackWidth,zoom='auto'){
 if(!Number.isInteger(bars)||bars<1||bars>64||![viewport,trackWidth].every(Number.isFinite)||viewport<=trackWidth||trackWidth<0||!VIEW_ZOOMS.includes(zoom))throw Error('时间线尺寸不正确');const available=viewport-trackWidth,visible=zoom==='fit'?bars:zoom==='auto'?Math.min(bars,available<480?8:16):Math.min(bars,+zoom),laneWidth=available*bars/visible;
 return{laneWidth,width:trackWidth+laneWidth,available,visible,maxScroll:Math.max(0,laneWidth-available),beatWidth:laneWidth/(bars*4)};
}
export function visibleWindow(layout,scroll,bars){const left=clamp(scroll,0,layout.maxScroll),start=left/layout.beatWidth,end=Math.min(bars*4,start+layout.available/layout.beatWidth);return{start,end,first:Math.floor(start/4)+1,last:Math.min(bars,Math.ceil(end/4-.00001))}}
export function scrollForBeat(layout,beat,{anchor=0}={}){return clamp(beat*layout.beatWidth-layout.available*anchor,0,layout.maxScroll)}
// Piano buffers cover the visible width only; logical width never becomes a texture.
export function pianoWindow({beats,beatWidth,viewport,scroll=0}){if(![beats,beatWidth,viewport,scroll].every(Number.isFinite)||beats<=0||beatWidth<=0||viewport<=0)throw Error('钢琴视图尺寸不正确');const width=Math.max(viewport,beats*beatWidth),left=clamp(scroll,0,width-viewport);return{width,canvasWidth:viewport,beatWidth:width/beats,scroll:left,start:left/(width/beats),end:Math.min(beats,(left+viewport)/(width/beats))}}
