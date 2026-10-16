import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {createAppServer} from '../server.mjs';
import {readRemoteStatus} from '../bridge.mjs';

const root=fileURLToPath(new URL('../',import.meta.url)),sshOptions=['-o','BatchMode=yes','-o','ForwardAgent=no','-o','StrictHostKeyChecking=yes','-o','ConnectTimeout=12'];
const remote='WZU_Server',base='http://127.0.0.1:54173';let tunnel,server,stopping=false;
const stop=()=>{if(stopping)return;stopping=true;server?.close();server?.closeAllConnections();tunnel?.stdin.end();tunnel?.kill('SIGTERM')};
process.once('SIGINT',stop);process.once('SIGTERM',stop);
const run=(cmd,args)=>new Promise((resolve,reject)=>{const child=spawn(cmd,args,{cwd:root,stdio:'inherit'});child.once('error',reject);child.once('exit',code=>code===0?resolve():reject(Error('command failed')))});
try{
 const excludes=['.git/','target/','node_modules/','.env','.env.*','*.pem','*.key','*.cookie','*.cookies','screenshots/','examples/','dist/samples/'];
 await run('rsync',['-az','-e',['ssh',...sshOptions].join(' '),...excludes.map(p=>'--exclude='+p),'./',remote+':~/codex-build/seed-studio/']);
 tunnel=spawn('ssh',[...sshOptions,'-T','-o','ExitOnForwardFailure=yes','-L','127.0.0.1:54173:127.0.0.1:54173',remote,'cd ~/codex-build/seed-studio && node scripts/serve-v100.mjs'],{cwd:root,stdio:['pipe','pipe','inherit']});
 tunnel.stdout.on('data',chunk=>process.stdout.write(chunk));tunnel.once('error',()=>{console.error('Unable to start the V100 SSH connection.');stop();process.exitCode=1});tunnel.once('exit',()=>{if(!stopping){console.error('V100 SSH connection ended. Restart this command to reconnect.');stop();process.exitCode=1}});
 let ready=false;for(let n=0;n<24&&!stopping;n++){try{const state=await readRemoteStatus(base);if(state.ready&&state.provider?.id==='deepseek'){ready=true;break}}catch{}await new Promise(resolve=>setTimeout(resolve,500))}
 if(!ready||stopping)throw Error('not ready');
 server=createAppServer({env:{SPROUT_REMOTE_SERVICE_URL:base}});server.on('error',()=>{console.error('Local port 4173 is busy. Stop the previous Sprout server, then try again.');stop();process.exitCode=1});
 server.listen(4173,'127.0.0.1',()=>console.log('Sprout Local: http://127.0.0.1:4173/\nDeepSeek V4.1 Flash is pinned and available through V100. The key stays on V100; no model called on startup.'));
}catch{console.error('V100 startup failed. Check SSH access, ~/.deepseek_key on V100, and the loopback ports. No credentials were copied.');stop();process.exitCode=1}
