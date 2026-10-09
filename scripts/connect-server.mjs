import { execFileSync } from 'node:child_process';
import { mkdirSync, copyFileSync, existsSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { replaceFile } from '../lib/atomic-file.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const dataDir=process.env.DASHBOARD_DATA_DIR??path.join(root,'data');
const read=args=>JSON.parse(execFileSync('tailscale',args,{encoding:'utf8',stdio:['ignore','pipe','inherit']}));
const status=read(['status','--json']);
if(status.BackendState!=='Running') throw new Error('Войди в Tailscale на этом сервере: tailscale up.');
const dns=status.Self.DNSName.replace(/\.$/,'');
const login=status.User[String(status.Self.UserID)]?.LoginName;
if(!/^[a-z0-9-]+\.[a-z0-9-]+\.ts\.net$/.test(dns)||!login) throw new Error('Нужен вошедший пользовательский хост с DNS Tailscale.');
const existing=read(['serve','status','--json']);
if(Object.values(existing.AllowFunnel??{}).some(Boolean)) throw new Error('Funnel включён. Сначала отключи открытый доступ.');
for(const [host,web] of Object.entries(existing.Web??{})) for(const [route,handler] of Object.entries(web.Handlers??{})) {
  if(host===dns+':443'&&(route!=='/'||handler.Proxy!=='http://127.0.0.1:8789')) throw new Error('Порт 443 занят другим приложением. Настройка сохранена.');
}
mkdirSync(dataDir,{recursive:true});
const stamp=new Date().toISOString().replaceAll(':','-');
for(const [name,value] of [['remote-access.json',{version:1,url:'https://'+dns,allowedLogin:login,access:'read-write'}],['hosting.json',{version:1,provider:'computer'}]]) {
  const file=path.join(dataDir,name);if(existsSync(file)) copyFileSync(file,file+'.before-'+stamp);
  writeFileSync(file+'.tmp',JSON.stringify(value,null,2)+'\n');replaceFile(file+'.tmp',file);
}
execFileSync('tailscale',['serve','--bg','--https=443','http://127.0.0.1:8789'],{stdio:'inherit'});
console.log('Закрытый адрес владельца: https://'+dns);
