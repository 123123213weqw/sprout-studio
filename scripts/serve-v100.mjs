import {readFile} from 'node:fs/promises';
import {homedir} from 'node:os';
import {createAppServer} from '../server.mjs';

let server;
try{
 const key=(await readFile(homedir()+'/.deepseek_key','utf8')).trim();
 if(!key||/[\x00-\x1f\x7f]/.test(key))throw Error('key');
 server=createAppServer({env:{LLM_API_URL:'https://api.deepseek.com/chat/completions',LLM_MODEL:'deepseek-flash',LLM_LOCK_MODEL:'1',LLM_API_KEY:key,LLM_MAX_TOKENS:'8192'}});
 server.on('error',()=>{console.error('V100 service could not bind its loopback port. No key was returned.');process.exitCode=1});
 server.listen(54173,'127.0.0.1',()=>console.log('V100 model service ready: DeepSeek V4.1 Flash (deepseek-flash), pinned, loopback only. No model called.'));
 const stop=()=>{server.close();server.closeAllConnections()};process.once('SIGTERM',stop);process.once('SIGINT',stop);process.once('SIGHUP',stop);process.stdin.resume();process.stdin.once('end',stop);
}catch{console.error('V100 key could not be loaded from ~/.deepseek_key. No key was returned.');process.exitCode=1}
