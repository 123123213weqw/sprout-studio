import {app,BrowserWindow,dialog,Menu,net,protocol,session,shell} from 'electron';
import {mkdir,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {STUDIO_URL,isStudioURL,isStudioDownload,isExternalURL,downloadName,readDesktopEnvironment,startLocalBackend,createProtocolHandler} from './runtime.mjs';

const configTemplate=`# Optional model settings. This file stays on this computer; never share it.
# Offline editing, instruments and rule-based composition need no key.
LLM_API_URL=https://api.deepseek.com/chat/completions
LLM_MODEL=deepseek-flash
LLM_API_KEY=
LLM_MAX_TOKENS=16384
LLM_JSON_MODE=1
# To reuse an already running V100 SSH bridge, uncomment this instead:
# SPROUT_REMOTE_SERVICE_URL=http://127.0.0.1:54173
# Restart Sprout Studio after editing. No model is called on startup.
`;

export async function launchDesktop({visible=true,onProgress=()=>{}}={}){
 onProgress('waiting for Electron ready');await app.whenReady();onProgress('Electron ready');
 const dataDirectory=app.getPath('userData'),configFile=join(dataDirectory,'desktop.env');
 await mkdir(dataDirectory,{recursive:true});
 const env=await readDesktopEnvironment(configFile,process.env),backend=await startLocalBackend(env);
 onProgress('private backend ready');
 protocol.handle('sprout',createProtocolHandler(backend.base,{fetcher:(url,options)=>net.fetch(url,options)}));
 const ownSession=session.defaultSession;
 ownSession.setPermissionRequestHandler((_contents,_permission,callback)=>callback(false));
 ownSession.setPermissionCheckHandler(()=>false);
 let window=null,quitting=false;
 const external=async value=>{
  if(!isExternalURL(value))return;
  const answer=await dialog.showMessageBox(window||undefined,{type:'question',title:'打开外部网页？',message:'此链接将在系统浏览器中打开。',detail:new URL(value).hostname,buttons:['取消','打开网页'],defaultId:0,cancelId:0});
  if(answer.response===1)await shell.openExternal(value);
 };
 const createWindow=async()=>{
  window=new BrowserWindow({title:'芽音 · Sprout Studio',width:1360,height:860,minWidth:940,minHeight:640,backgroundColor:'#15191f',show:false,
   webPreferences:{nodeIntegration:false,contextIsolation:true,sandbox:true,webSecurity:true,allowRunningInsecureContent:false,autoplayPolicy:'document-user-activation-required',devTools:!app.isPackaged}});
  window.webContents.setWindowOpenHandler(({url})=>{void external(url).catch(()=>{});return{action:'deny'}});
  window.webContents.on('will-navigate',(event,url)=>{if(!isStudioURL(url)){event.preventDefault();void external(url).catch(()=>{})}});
  window.webContents.on('will-attach-webview',event=>event.preventDefault());
  window.once('ready-to-show',()=>{if(visible)window?.show()});
  window.once('closed',()=>{window=null});
  onProgress('loading studio');
  await window.loadURL(STUDIO_URL);
  onProgress('studio loaded');
  return window;
 };
 ownSession.on('will-download',(event,item,contents)=>{
  if(!window||contents!==window.webContents||!isStudioDownload(item.getURL())){event.preventDefault();return}
  item.setSaveDialogOptions({title:'导出作品',defaultPath:join(app.getPath('documents'),downloadName(item.getFilename()))});
 });
 const click=id=>{if(window)void window.webContents.executeJavaScript(`document.getElementById(${JSON.stringify(id)})?.click()`,true).catch(()=>{})};
 const historyAction=async redo=>{
  const contents=window?.webContents;if(!contents)return;
  const typing=await contents.executeJavaScript(`(()=>{const t=document.activeElement;if(['INPUT','TEXTAREA','SELECT'].includes(t?.tagName)||t?.isContentEditable)return true;document.body.dispatchEvent(new KeyboardEvent('keydown',{key:'z',metaKey:${process.platform==='darwin'},ctrlKey:${process.platform!=='darwin'},shiftKey:${Boolean(redo)},bubbles:true,cancelable:true}));return false})()`);
  if(typing)redo?contents.redo():contents.undo();
 };
 const clipboardAction=async(action,key)=>{
  const contents=window?.webContents;if(!contents)return;
  const native=await contents.executeJavaScript(`(()=>{const t=document.activeElement;if(t?.id!=='piano-canvas')return true;t.dispatchEvent(new KeyboardEvent('keydown',{key:${JSON.stringify(key)},metaKey:${process.platform==='darwin'},ctrlKey:${process.platform!=='darwin'},bubbles:true,cancelable:true}));return false})()`);
  if(native)contents[action]();
 };
 const showConfig=async()=>{
  try{await writeFile(configFile,configTemplate,{flag:'wx',mode:0o600})}catch(error){if(error.code!=='EEXIST')throw error}
  const error=await shell.openPath(configFile);
  if(error)await dialog.showMessageBox(window||undefined,{type:'info',title:'模型配置文件',message:'请使用文本编辑器打开此文件，编辑后重启应用。',detail:configFile});
 };
 const menu=[
  ...(process.platform==='darwin'?[{label:app.name,submenu:[{role:'about'},{type:'separator'},{role:'hide'},{role:'hideOthers'},{role:'unhide'},{type:'separator'},{role:'quit'}]}]:[]),
  {label:'工程',submenu:[{label:'导入工程…',accelerator:'CmdOrCtrl+O',click:()=>click('import-file')},{label:'导入 MIDI…',click:()=>click('import-midi-file')},{label:'工程与备份…',click:()=>click('project-menu')},{label:'导出…',accelerator:'CmdOrCtrl+Shift+E',click:()=>click('export-btn')},...(process.platform==='darwin'?[]:[{type:'separator'},{role:'quit'}])]},
  {label:'编辑',submenu:[{label:'撤销',accelerator:'CmdOrCtrl+Z',click:()=>void historyAction(false).catch(()=>{})},{label:'重做',accelerator:'CmdOrCtrl+Shift+Z',click:()=>void historyAction(true).catch(()=>{})},{type:'separator'},{role:'cut'},...['copy','paste','selectAll'].map((action,i)=>({label:['复制','粘贴','全选'][i],accelerator:['CmdOrCtrl+C','CmdOrCtrl+V','CmdOrCtrl+A'][i],click:()=>void clipboardAction(action,['c','v','a'][i]).catch(()=>{})}))]},
  {label:'视图',submenu:[{role:'reload'},{role:'resetZoom'},{role:'zoomIn'},{role:'zoomOut'},{role:'togglefullscreen'},...(!app.isPackaged?[{role:'toggleDevTools'}]:[])]},
  {label:'模型连接',submenu:[{label:'编辑本机模型配置…',click:()=>void showConfig().catch(()=>dialog.showErrorBox('配置文件无法打开','请检查应用数据目录的写入权限。'))},{label:'重新启动以应用配置',click:()=>{app.relaunch();app.quit()}},{type:'separator'},{label:'离线功能无需配置或登录',enabled:false}]},
  {label:'窗口',submenu:[{role:'minimize'},{role:'zoom'},{role:'front'}]},
 ];
 Menu.setApplicationMenu(Menu.buildFromTemplate(menu));
 app.setAboutPanelOptions({applicationName:'芽音 · Sprout Studio',applicationVersion:app.getVersion(),copyright:'Instrument notices are bundled in dist/samples/licenses.'});
 const mainWindow=await createWindow();
 const reopen=()=>void createWindow().catch(()=>dialog.showErrorBox('窗口无法打开','请退出芽音后重新启动。工程仍保存在本机应用数据目录中。'));
 app.on('second-instance',()=>{if(quitting)return;if(window){if(window.isMinimized())window.restore();window.show();window.focus()}else reopen()});
 app.on('activate',()=>{if(!window&&!quitting)reopen()});
 app.on('window-all-closed',()=>{if(process.platform!=='darwin')app.quit()});
 app.on('before-quit',event=>{if(quitting)return;event.preventDefault();quitting=true;void backend.close().finally(()=>app.quit())});
 return{window:mainWindow,backend,dataDirectory,configFile,shutdown:()=>{quitting=true;return backend.close()}};
}
