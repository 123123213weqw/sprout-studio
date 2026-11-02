import {app,dialog,protocol} from 'electron';
import {join} from 'node:path';
import {SCHEME} from './runtime.mjs';

// A stable scheme and profile keep projects independent of the private server's port.
app.setName('Sprout Studio');
app.setPath('userData',join(app.getPath('appData'),'Sprout Studio'));
protocol.registerSchemesAsPrivileged([SCHEME]);
if(!app.requestSingleInstanceLock())app.quit();
else{
 // Do not hold the ESM entry-point promise while waiting for Electron's ready event.
 void import('./application.mjs').then(({launchDesktop})=>launchDesktop()).catch(error=>{
  console.error('Desktop startup failed:',error.code||error.name);dialog.showErrorBox('Sprout Studio 无法启动','本机服务或桌面配置无法读取。请检查 desktop.env 的格式，然后重新启动。');app.exit(1);
 });
}
