// View preferences are intentionally separate from songs, history and model settings.
export const VIEW_KEY='sprout-workspace-view-v1';
export const VIEW_DEFAULTS=Object.freeze({arrangeTools:false,clipTools:false,noteTools:false,focus:false});
export function normalizeWorkspaceView(value){
 const out={...VIEW_DEFAULTS};
 if(value&&typeof value==='object'&&!Array.isArray(value))for(const key of Object.keys(out))if(typeof value[key]==='boolean')out[key]=value[key];
 return out;
}
export function readWorkspaceView(storage){try{return normalizeWorkspaceView(JSON.parse(storage.getItem(VIEW_KEY)||'null'))}catch{return {...VIEW_DEFAULTS}}}
export function writeWorkspaceView(storage,value){try{storage.setItem(VIEW_KEY,JSON.stringify(normalizeWorkspaceView(value)));return true}catch{return false}}
export function toggleWorkspaceView(value,key){if(!Object.hasOwn(VIEW_DEFAULTS,key))throw Error('Unknown workspace view');const out=normalizeWorkspaceView(value);out[key]=!out[key];return out}
export function quietPreferenceUrl(url,quiet){const next=new URL(url);if(quiet)next.searchParams.set('silent','1');else next.searchParams.delete('silent');return next.pathname+next.search+next.hash}
export function displayTrackColor(color){
 if(typeof color!=='string'||!/^#[\da-f]{6}$/i.test(color))return '#9ba8b5';
 const neutral=[151,166,179];return '#'+neutral.map((v,i)=>Math.round(v*.58+parseInt(color.slice(1+i*2,3+i*2),16)*.42).toString(16).padStart(2,'0')).join('');
}
export function createWorkspaceView({root,storage,onLayout=()=>{}}){
 let state=readWorkspaceView(storage);
 const refresh=()=>{
  root.body.classList.toggle('focus-workspace',state.focus);
  for(const button of root.querySelectorAll('[data-view-toggle]')){
   const key=button.dataset.viewToggle;if(!Object.hasOwn(state,key))continue;
   button.setAttribute(key==='focus'?'aria-pressed':'aria-expanded',String(state[key]));
   if(key==='focus')button.textContent=state.focus?'退出专注':'专注模式';
  }
  for(const panel of root.querySelectorAll('[data-view-panel]'))if(Object.hasOwn(state,panel.dataset.viewPanel))panel.hidden=!state[panel.dataset.viewPanel];
 };
 const click=event=>{
  const button=event.target.closest('[data-view-toggle]');if(!button||!Object.hasOwn(VIEW_DEFAULTS,button.dataset.viewToggle))return;
  state=toggleWorkspaceView(state,button.dataset.viewToggle);writeWorkspaceView(storage,state);refresh();onLayout();
 };
 root.addEventListener('click',click);refresh();
 return {refresh,read:()=>({...state}),destroy:()=>root.removeEventListener('click',click)};
}
