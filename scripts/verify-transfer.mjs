import {createHash} from 'node:crypto';
import {existsSync,lstatSync,readFileSync,readdirSync,realpathSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
function safeFile(root,relative) {
  if(typeof relative!=='string'||!relative||relative.includes('\\')||path.posix.isAbsolute(relative)||relative.split('/').some(p=>!p||p==='.'||p==='..'||p.includes(':')))throw new Error('Invalid transfer path.');
  if(relative.split('/').includes('native-signing'))throw new Error('Signing keys must not be transferred to the server.');
  let file=root;
  for(const part of relative.split('/')) {
    file=path.join(file,part);
    if(lstatSync(file).isSymbolicLink())throw new Error('Symbolic links are not allowed in a transfer.');
  }
  if(!lstatSync(file).isFile())throw new Error('Transfer entry is not a file.');
  return file;
}
function inventory(root,relative='') {
  return readdirSync(path.join(root,relative),{withFileTypes:true}).flatMap(entry=>{
    if(entry.isSymbolicLink())throw new Error('Symbolic links are not allowed in a transfer.');
    const name=relative?relative+'/'+entry.name:entry.name;
    return entry.isDirectory()?inventory(root,name):name==='transfer-manifest.json'?[]:[name];
  }).sort();
}
function archiveIdentity(root) {
  const read=name=>existsSync(path.join(root,'data',name))?JSON.parse(readFileSync(path.join(root,'data',name),'utf8').replace(/^\uFEFF/,'')):{};
  return {serverId:read('dashboard.json').offlineSync?.serverId??null,writingInstanceId:read('writing.json').instanceId??null};
}
export function createTransferManifest(root,{final=false,now=new Date()}={}) {
  root=realpathSync(root);
  const files=inventory(root).map(relative=>{
    const bytes=readFileSync(safeFile(root,relative));
    return {path:relative,sha256:hash(bytes),size:bytes.length};
  });
  return {version:2,createdAt:now.toISOString(),consistency:final?'offline-final':'live-preview',identity:archiveIdentity(root),files};
}
export function verifyTransfer(root,{requireFinal=false}={}) {
  root=realpathSync(root);
  const manifest=JSON.parse(readFileSync(path.join(root,'transfer-manifest.json'),'utf8').replace(/^\uFEFF/,''));
  if(manifest.version!==2||!Array.isArray(manifest.files)||!['offline-final','live-preview'].includes(manifest.consistency))throw new Error('Unsupported transfer manifest.');
  if(requireFinal&&manifest.consistency!=='offline-final')throw new Error('This is a live preview. Stop the old server and export with -FinalTransfer.');
  const seen=new Set();
  for(const entry of manifest.files) {
    if(seen.has(entry.path))throw new Error('Duplicate transfer path.');
    seen.add(entry.path);
    const bytes=readFileSync(safeFile(root,entry.path));
    if(bytes.length!==entry.size||hash(bytes)!==entry.sha256)throw new Error('Transfer checksum mismatch: '+entry.path);
  }
  if(JSON.stringify([...seen].sort())!==JSON.stringify(inventory(root)))throw new Error('Unlisted or missing transfer files.');
  const identity=archiveIdentity(root);
  if(identity.serverId!==manifest.identity?.serverId||identity.writingInstanceId!==manifest.identity?.writingInstanceId)throw new Error('Archive identity changed during transfer.');
  return {verified:true,consistency:manifest.consistency,files:seen.size,identity};
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const root=path.resolve(process.argv[2]??'.');
  console.log(JSON.stringify(verifyTransfer(root,{requireFinal:process.argv.includes('--final')})));
}
