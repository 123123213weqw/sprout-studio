import {copy,INSTRUMENTS,noteName} from './music.js';
import {patternInstances} from './patterns-core.js';
import {exportPatternLibrary,serializePatternLibrary,readPatternFile,planPatternImport,PATTERN_FILE_MAX_BYTES} from './pattern-transfer.js';
const $=s=>document.querySelector(s);
const escape=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const bytes=text=>new TextEncoder().encode(text).length;
const keyLabel=key=>({'A minor':'A 小调','C major':'C 大调','D minor':'D 小调','E minor':'E 小调','G major':'G 大调','F major':'F 大调'}[key]||key);
export function createPatternTransferUI({getProject,getRevision,commit,modal,toast,download,projectFilename,clipSVG,library}){
 let flow=0;
 const invalidate=()=>++flow;
 const guard=(at,ticket)=>{if(at!==getRevision()||ticket!==flow)throw Error('工程或窗口已改变，请重新打开乐句导入 / 导出。')};
 function chooseImport(){
  const at=getRevision(),ticket=invalidate();
  const d=modal('导入乐句 · 先选文件',`<div class="pattern-form pattern-transfer"><p>把其他作品里的乐句收藏带到这里。只读取本机文件，不上传、不调用模型、不播放。</p><button class="accent" id="transfer-choose-file">选择乐句或工程文件</button><input id="transfer-file" type="file" accept=".sprout-patterns,.sprout,.json,application/json" hidden><div class="modal-notice">支持芽音 .sprout-patterns 乐句文件，或完整 .sprout 工程中的 Pattern 库。完整工程只提取已经存入库的源乐句，不导入轨道、音色、混音或引用；不会从普通音块自动推导乐句。上限 3 MB。</div><div id="transfer-error" role="status" class="export-progress"></div></div>`,'<button class="quiet" id="transfer-back">返回库</button>');
  const root=$('.pattern-transfer'),input=$('#transfer-file');let readSequence=0;
  const live=()=>ticket===flow&&root.isConnected&&d.open;
  d.addEventListener('close',()=>{if(ticket===flow)invalidate()},{once:true});
  $('#transfer-back').onclick=()=>library();$('#transfer-choose-file').onclick=()=>input.click();
  input.onchange=async()=>{
   const file=input.files?.[0],sequence=++readSequence;input.value='';if(!file)return;
   $('#transfer-error').textContent='正在本机读取与校验；工程还没有改变…';
   try{
    guard(at,ticket);if(file.size>PATTERN_FILE_MAX_BYTES)throw Error('文件超过 3 MB，没有读取或导入内容');
    const text=await file.text();if(!live()||sequence!==readSequence)return;guard(at,ticket);
    const parsed=readPatternFile(text);if(!live()||sequence!==readSequence)return;
    chooser({mode:'import',libraryData:parsed.library,at,filename:file.name,origin:parsed.origin});
   }catch(e){if(live()&&sequence===readSequence)$('#transfer-error').textContent=e.message}
  };
 }
 function chooseExport(patternId){
  try{const p=copy(getProject());chooser({mode:'export',libraryData:exportPatternLibrary(p),at:getRevision(),initialId:patternId,filename:projectFilename(p)+'-乐句收藏.sprout-patterns'})}catch(e){toast(e.message)}
 }
 function chooser({mode,libraryData,at,filename,origin,initialId}){
  const importing=mode==='import',ticket=invalidate(),sources=libraryData.patterns,selection=new Set(initialId?[initialId]:sources.map(p=>p.id));
  let page=0,plan=null,text=null;const reference=libraryData.context;
  const d=modal(importing?'导入乐句 · 先看影响':'导出乐句 · 跨工程收藏',`<div class="pattern-form pattern-transfer"><p>${importing?`${origin==='project'?'从完整工程提取库中乐句':'芽音乐句文件'}：${escape(filename.slice(0,250))}。`:'只导出所选源乐句；不会修改工程，也不会导出轨道、声音参数或已有引用。'}<br>选择要${importing?'加入当前工程':'留作文件'}的乐句，再确认。</p>${reference?`<div class="transfer-reference">参考 ${escape(keyLabel(reference.key))} · ${reference.bpm} BPM · 摇摆 ${reference.swing}%<small>仅作提示，不自动转调、不覆盖本工程速度或摇摆。音符使用固定 MIDI 音高和相对拍数。</small></div>`:''}${importing?'<label class="modal-label" for="transfer-duplicates">内容相同的乐句</label><select id="transfer-duplicates"><option value="skip">跳过相同内容（默认，不覆盖）</option><option value="copies">仍作为新收藏导入（全新标识）</option></select>':''}<div class="transfer-tools"><button class="quiet compact" id="transfer-all">全选</button><button class="quiet compact" id="transfer-none">全不选</button><span>${sources.length} 个源乐句 · 只存库，不放置</span></div><div id="transfer-list" class="transfer-list"></div><div class="pattern-pagination"><button class="quiet compact" id="transfer-prev">上一页</button><span id="transfer-page"></span><button class="quiet compact" id="transfer-next">下一页</button></div><section id="transfer-inspect" class="transfer-inspect" aria-label="静音乐句预览"></section><div id="transfer-summary" class="chord-preview" role="status"></div><div class="modal-notice">${importing?'导入只追加源库，现有音符、音块、共享引用、标签和音色保持。所有新源与音符使用新标识；名称相同会自动加“导入”后缀，不覆盖或绑定旧源。作为一次编辑，可撤销，随当前工程本机保存。之后仍需主动放置才进入歌曲。':'文件最多 64 个源 / 12,000 个源音符，每源最多 4,000 音符，3 MB。分享的是音符收藏，不是采样、完整歌曲或插件预设；接收方可选择导入，不自动影响已有引用。'}</div><div id="transfer-error" class="export-progress" role="status"></div></div>`,'<button class="quiet" id="transfer-back">取消，返回库</button><button class="accent" id="transfer-apply">'+(importing?'只加入库，不播放':'下载乐句文件')+'</button>');
  d.addEventListener('close',()=>{if(ticket===flow)invalidate()},{once:true});
  function inspect(source){
   const pitches=source.notes.map(n=>n.pitch),micro=source.notes.filter(n=>n.timingOffset).length;
   $('#transfer-inspect').innerHTML=`<span class="eyebrow">静音乐句预览 · ${escape(INSTRUMENTS[source.instrument].name)}</span><h3>${escape(source.name)}</h3><div class="chord-note-map" style="--track-color:${INSTRUMENTS[source.instrument].color}">${clipSVG({notes:source.notes},0,source.length)}</div><p>${source.length/4} 小节 · ${source.notes.length} 音符 · ${pitches.length?`音高 ${noteName(Math.min(...pitches))}–${noteName(Math.max(...pitches))}`:'空乐句'} · ${micro} 音符有微偏移</p><small>图中显示前 120 个音符；文件保留全部。${source.kind==='drum'?'鼓只能放到同种鼓轨。':'可放到旋律音源轨，但不会自动按目标调性改音高。'}</small>`;
  }
  function rows(){
   const start=page*8;
   $('#transfer-list').innerHTML=sources.slice(start,start+8).map((p,i)=>`<article class="transfer-row"><label><input type="checkbox" data-transfer-id="${escape(p.id)}" ${selection.has(p.id)?'checked':''} aria-label="选择乐句 ${start+i+1} ${escape(p.name)}"><span><strong>${escape(p.name)}</strong><small>${escape(INSTRUMENTS[p.instrument].name)} · ${p.length/4} 小节 · ${p.notes.length} 音符${importing?'':` · ${patternInstances(getProject(),p.id).length} 引用`}</small><small data-transfer-status="${escape(p.id)}"></small></span></label><button class="quiet compact" data-transfer-peek="${escape(p.id)}" aria-label="查看乐句 ${start+i+1}">看音符</button></article>`).join('');
   $('#transfer-page').textContent=`${page+1} / ${Math.ceil(sources.length/8)} 页`;$('#transfer-prev').disabled=page===0;$('#transfer-next').disabled=(page+1)*8>=sources.length;
  }
  function update(){
   plan=null;text=null;
   try{
    guard(at,ticket);const ids=[...selection];
    if(importing){
     plan=planPatternImport(getProject(),libraryData,{ids,duplicates:$('#transfer-duplicates').value});const s=plan.stats;
     $('#transfer-summary').innerHTML=`<h3>选 ${s.selected} 个 · 新增 ${s.added} · 跳过 ${s.skipped}</h3><p>源库 ${s.patternsBefore} → ${s.patternsAfter} 个，库音符 ${s.notesBefore} → ${s.notesAfter}。${s.renamed?`${s.renamed} 个名称加后缀。`:''}<br>轨道音符、现有引用和工程设置完全不变。${s.added?'确认后仅存入库，尚未放进歌曲。':'没有需要新增的乐句，可取消或明确选择新收藏。'}</p>`;
     $('#transfer-apply').disabled=!s.added;
    }else{
     const out={...libraryData,patterns:sources.filter(p=>selection.has(p.id))};text=serializePatternLibrary(out);
     $('#transfer-summary').innerHTML=`<h3>${ids.length} 个源乐句 · ${out.patterns.reduce((n,p)=>n+p.notes.length,0)} 音符</h3><p>文件约 ${(bytes(text)/1024).toFixed(1)} KiB；仅含乐句、来源音源种类与参考速度 / 调性。没有轨道、混音、音色、模型地址或密钥。</p>`;$('#transfer-apply').disabled=false;
    }
    $('#transfer-error').textContent='';
   }catch(e){$('#transfer-error').textContent=e.message;$('#transfer-summary').textContent='尚未改变或导出任何内容。请调整选择。';$('#transfer-apply').disabled=true}
   document.querySelectorAll('[data-transfer-status]').forEach(node=>{const id=node.dataset.transferStatus,item=plan?.items.find(p=>p.sourceId===id);node.textContent=!selection.has(id)?'未选择':importing?(item?.action==='skip'?`跳过：与“${item.duplicateName}”内容相同`:item?.renamed?`将命名为：${item.importedName}`:item?'将新增独立源，无关联实例':'尚未通过校验'):'所选源会写入文件'});
  }
  $('#transfer-list').onchange=e=>{const id=e.target.dataset.transferId;if(!id)return;if(e.target.checked)selection.add(id);else selection.delete(id);update()};
  $('#transfer-list').onclick=e=>{const id=e.target.closest('[data-transfer-peek]')?.dataset.transferPeek;if(id)inspect(sources.find(p=>p.id===id))};
  $('#transfer-all').onclick=()=>{sources.forEach(p=>selection.add(p.id));rows();update()};$('#transfer-none').onclick=()=>{selection.clear();rows();update()};
  $('#transfer-prev').onclick=()=>{page--;rows();update()};$('#transfer-next').onclick=()=>{page++;rows();update()};
  if(importing)$('#transfer-duplicates').onchange=update;
  $('#transfer-back').onclick=()=>library();
  $('#transfer-apply').onclick=()=>{
   try{
    guard(at,ticket);
    if(importing){if(!plan?.stats.added)throw Error('没有要新增的乐句');const added=plan.stats.added,id=plan.addedIds[0];if(commit(plan.project,undefined,{restart:false})){toast(`已向库中加入 ${added} 个乐句，没有放置或播放，可一次撤销。`);library(id)}}
    else{if(!text)throw Error('请先选择要导出的乐句');download(text,filename,'application/json');d.close();toast('乐句文件已下载；工程与声音都没有改变。')}
   }catch(e){$('#transfer-error').textContent=e.message;$('#transfer-apply').disabled=true}
  };
  rows();inspect(sources.find(p=>p.id===initialId)||sources[0]);update();
 }
 return{importFile:chooseImport,exportFile:chooseExport,invalidate};
}
