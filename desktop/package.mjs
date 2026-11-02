import {cp,mkdir,mkdtemp,readFile,readdir,rm,lstat,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve,basename,extname,sep} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';

export const RUNTIME_FILES=['dist','desktop/main.mjs','desktop/application.mjs','desktop/runtime.mjs','server.mjs','bridge.mjs','llm.mjs','llm-config.mjs','deepseek.mjs'];
async function regularTree(path){
 if(basename(path).startsWith('.')||['.key','.pem','.cookie','.cookies','.p12','.pfx'].includes(extname(path)))throw Error('Private or hidden files are not allowed in the runtime');
 const info=await lstat(path);if(info.isSymbolicLink())throw Error('Runtime symlinks are not allowed');
 if(info.isDirectory())for(const item of await readdir(path))await regularTree(join(path,item));
 else if(!info.isFile())throw Error('Unexpected runtime file');
}
export async function stageRuntime(root,destination){
 const pkg=JSON.parse(await readFile(join(root,'package.json'),'utf8'));
 for(const relative of RUNTIME_FILES){const from=join(root,relative);await regularTree(from);await mkdir(join(destination,relative,'..'),{recursive:true});await cp(from,join(destination,relative),{recursive:true})}
 const manifest=JSON.parse(await readFile(join(destination,'dist/samples/manifest.json'),'utf8'));
 for(const asset of manifest.assets){
  const path=resolve(destination,'dist/samples',asset.file),base=resolve(destination,'dist/samples')+sep;
  if(!path.startsWith(base))throw Error('Invalid sample path');
  const bytes=await readFile(path);
  if(createHash('sha256').update(bytes).digest('hex')!==asset.sha256)throw Error('Sample checksum mismatch: '+asset.id);
 }
 await writeFile(join(destination,'package.json'),JSON.stringify({name:'sprout-studio',productName:'Sprout Studio',version:pkg.version,private:true,type:'module',main:'desktop/main.mjs',description:'Local beginner-friendly music studio'},null,2)+'\n');
 return{version:pkg.version,samples:manifest.assets.length,electronVersion:pkg.devDependencies.electron};
}
async function run(command,args){await new Promise((resolve,reject)=>{const child=spawn(command,args,{stdio:'inherit'});child.once('error',reject);child.once('exit',code=>code===0?resolve():reject(Error(command+' failed')))})}
export async function packageDesktop(){
 const root=fileURLToPath(new URL('../',import.meta.url)),stage=await mkdtemp(join(root,'.desktop-stage-'));
 try{
  const metadata=await stageRuntime(root,stage),{packager}=await import('@electron/packager');
  const platform=process.platform,arch=process.arch;
  if(!['darwin','win32','linux'].includes(platform))throw Error('Unsupported packaging platform');
  const out=join(root,'desktop-build',metadata.version);await mkdir(out,{recursive:true});
  const checksums=JSON.parse(await readFile(join(root,'node_modules/electron/checksums.json'),'utf8'));
  const paths=await packager({dir:stage,out,name:'Sprout Studio',appBundleId:'studio.sprout.desktop',appVersion:metadata.version,
   platform,arch,electronVersion:metadata.electronVersion,download:{checksums},asar:true,prune:false,overwrite:true,
   ...(platform==='darwin'?{darwinDarkModeSupport:true,appCategoryType:'public.app-category.music',osxSign:{identity:'-',identityValidation:false,optionsForFile:()=>({hardenedRuntime:false})}}:{})});
  let archive;
  if(platform==='darwin'){
   archive=join(out,`Sprout-Studio-${metadata.version}-mac-${arch}.zip`);
   await run('/usr/bin/ditto',['-c','-k','--sequesterRsrc','--keepParent',join(paths[0],'Sprout Studio.app'),archive]);
  }
  const record={...metadata,platform,arch,paths,archive:archive||null,signing:platform==='darwin'?'ad-hoc; not notarized':'not signed'};
  await writeFile(join(out,'build.json'),JSON.stringify(record,null,2)+'\n');console.log(JSON.stringify(record,null,2));return record;
 }finally{await rm(stage,{recursive:true,force:true})}
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))await packageDesktop();
