import {existsSync,readFileSync} from 'node:fs';

export function readHosting(file) {
  if (!existsSync(file)) return {provider:'computer',requiresComputer:true,explicit:false};
  const value=JSON.parse(readFileSync(file,'utf8').replace(/^\uFEFF/,''));
  if (value.version!==1 || !['computer','digitalocean'].includes(value.provider)) throw new Error('Некорректная настройка хостинга.');
  return {provider:value.provider,requiresComputer:value.provider==='computer',explicit:true};
}
