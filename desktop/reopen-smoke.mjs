// This second process reopens only the disposable profile created by smoke.mjs.
import {app,protocol} from 'electron';
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {SCHEME} from './runtime.mjs';

if(!process.env.SPROUT_DESKTOP_QA_DIR)throw Error('A disposable QA directory is required');
const directory=resolve(process.env.SPROUT_DESKTOP_QA_DIR);
app.setName('Sprout Desktop QA');app.setPath('userData',join(directory,'profile'));
app.commandLine.appendSwitch('mute-audio');protocol.registerSchemesAsPrivileged([SCHEME]);
for(const key of ['LLM_API_URL','LLM_MODEL','LLM_API_KEY','LLM_MAX_TOKENS','LLM_JSON_MODE','LLM_LOCK_MODEL','SPROUT_REMOTE_SERVICE_URL'])delete process.env[key];
async function run(){let desktop;
 try{
  const before=JSON.parse(await readFile(join(directory,'results.json'),'utf8'));
  const {launchDesktop}=await import('./application.mjs');desktop=await launchDesktop({visible:false});
  for(let n=0;n<60;n++){if(await desktop.window.webContents.executeJavaScript(`document.querySelector('#project-name')?.value==='desktop-qa'`))break;if(n===59)throw Error('Saved project did not reopen');await new Promise(r=>setTimeout(r,100))}
  const marker=await desktop.window.webContents.executeJavaScript(`localStorage.getItem('sprout-desktop-qa')`);assert.equal(marker,'retained');
  const result={passed:true,project:'desktop-qa',settingsRetained:true,oldPrivateBackend:before.privateBackend,newPrivateBackend:desktop.backend.base,stablePage:desktop.window.webContents.getURL()};
  await writeFile(join(directory,'reopen-results.json'),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));await desktop.shutdown();app.exit(0);
 }catch(error){console.error(error.stack);await desktop?.shutdown();app.exit(1)}
}
void run();
