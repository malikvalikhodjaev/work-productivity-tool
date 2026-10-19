import {existsSync,readFileSync} from 'node:fs';

export function movedServer(file) {
  if(!existsSync(file))return null;
  const value=JSON.parse(readFileSync(file,'utf8').replace(/^\uFEFF/,''));
  const url=new URL(value.url);
  if(value.version!==1||url.protocol!=='https:'||!/^https:\/\/[a-z0-9-]+\.[a-z0-9-]+\.ts\.net\/?$/.test(value.url))throw new Error('Некорректный адрес перенесённого сервера.');
  return url.origin;
}
