const EPS=.00005,round=n=>+n.toFixed(4);
export function normalizeRange(range,end){
 if(!Number.isFinite(end)||end<=0)throw Error('工程播放长度不正确');
 if(range==null)return{start:0,end};
 if(typeof range!=='object'||Array.isArray(range)||Object.keys(range).some(k=>!['start','end'].includes(k))||!Number.isFinite(range.start)||!Number.isFinite(range.end)||range.start<0||range.end>end+EPS||range.end-range.start<.25-EPS)throw Error('练习范围须在工程内，且至少为四分之一拍');
 const normalized={start:round(range.start),end:round(Math.min(end,range.end))};if(normalized.end-normalized.start<.25-EPS)throw Error('舍入后的练习范围短于四分之一拍');return normalized;
}
export function windowAtTime(elapsed,offset,range,bpm,loop=true){
 const position=offset+Math.max(0,elapsed)*bpm/60,length=range.end-range.start;
 return loop?range.start+((position-range.start)%length+length)%length:Math.min(range.end,Math.max(range.start,position));
}
