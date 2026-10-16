// These measurable checks describe the four-bar fixture, not artistic quality.
export const TEST_HARMONY=Object.freeze([{start:0,chord:'Am',root:9,pcs:[9,0,4]},{start:4,chord:'F',root:5,pcs:[5,9,0]},{start:8,chord:'C',root:0,pcs:[0,4,7]},{start:12,chord:'G',root:7,pcs:[7,11,2]}]);
export function assessTestComposition(project){
 const notes=role=>project.tracks.filter(t=>t.instrument===role).flatMap(t=>t.notes),at=(n,start)=>Math.abs(n.start-start)<.0001,pc=n=>n.pitch%12;
 const piano=notes('keys'),bass=notes('bass'),hats=notes('hat');
 const harmony=TEST_HARMONY.map(bar=>{const pitches=[...new Set(piano.filter(n=>at(n,bar.start)).map(pc))];return{bar:bar.start/4+1,chord:bar.chord,pianoTriad:bar.pcs.every(p=>pitches.includes(p))&&pitches.every(p=>bar.pcs.includes(p)),bassRoot:bass.some(n=>at(n,bar.start)&&pc(n)===bar.root)}});
 const expectedHatOnsets=Array.from({length:32},(_,i)=>i*.5),missingHatOnsets=expectedHatOnsets.filter(start=>!hats.some(n=>at(n,start))),extraHatOnsets=hats.filter(n=>!expectedHatOnsets.some(start=>at(n,start))).map(n=>n.start);
 const am=new Set([9,11,0,2,4,5,7]),melodic=project.tracks.filter(t=>t.kind!=='drum').flatMap(t=>t.notes),outOfKey=melodic.filter(n=>!am.has(pc(n))).length;
 const allRolesHaveNotes=['keys','bass','lead','pad','pluck','kick','snare','hat'].every(role=>notes(role).length>0);
 return{harmony,hiHat:{expected:32,actual:hats.length,missingOnsets:missingHatOnsets,extraOnsets:extraHatOnsets,eighthNotes:missingHatOnsets.length===0&&extraHatOnsets.length===0&&hats.length===32},key:{name:'A minor',melodicNotes:melodic.length,outOfKey},allRolesHaveNotes,matchesExplicitBrief:harmony.every(b=>b.pianoTriad&&b.bassRoot)&&missingHatOnsets.length===0&&extraHatOnsets.length===0&&hats.length===32&&outOfKey===0&&allRolesHaveNotes,quality:'Not a listening test, style assessment, originality check or artistic-quality score.'};
}
