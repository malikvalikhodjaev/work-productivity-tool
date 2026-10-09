import { cpSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root=fileURLToPath(new URL('../',import.meta.url));
const target=process.argv[2];if(!target)throw new Error('Укажи каталог подготовленного Vinext Site.');
const checkout=resolve(target);
if(!readFileSync(join(checkout,'.openai','hosting.json'),'utf8'))throw new Error('Сначала создай Site и сохрани его project_id.');
for(const name of ['src/lib','src/docs','src/shells','public','app/[[...path]]'])mkdirSync(join(checkout,name),{recursive:true});
cpSync(join(root,'lib'),join(checkout,'src/lib'),{recursive:true});
for(const name of ['ADR-001-time-sources.md','ADR-002-personal-work-loop.md'])cpSync(join(root,'docs',name),join(checkout,'src/docs',name));
for(const name of ['index.html','alphas.html']){
  const html=readFileSync(join(root,'public',name),'utf8')
    .replace('<head>','<head>\n<meta name="dashboard-access" content="viewer"><meta name="dashboard-hosting" content="sites">')
    .replace('Факт — из локальных записей','Факт — из сохранённых записей снимка')
    .replace('История сохраняется на этом компьютере в','Сохранённая история показана в снимке; исходная таблица')
    .replace('Недельные записи хранятся локально','Закрытая веб-версия · снимок данных')
    .replace('Данные хранятся в локальном data/dashboard.json. Экспорт JSON — переносимая копия объектов и истории. Несохранённый черновик остаётся в этом браузере.','Просмотр сохранённого снимка data/dashboard.json. Экспорт JSON включает объекты и историю. Редактирование доступно на ПК.');
  writeFileSync(join(checkout,'src/shells',name),html);
}
cpSync(join(root,'public'),join(checkout,'public'),{recursive:true,filter:path=>!['index.html','alphas.html'].includes(path.split(/[\\/]/).at(-1))});
const offline=readFileSync(join(root,'public/offline.html'),'utf8').replace('Нет соединения с ПК','Нет соединения').replace('Проверь интернет, подключение Tailscale и что компьютер включён. Если ПК спит, его нужно разбудить.','Проверь интернет и открой дашборд снова.').replace('Данные обновляются с компьютера. Офлайн-копия показателей не хранится.','Офлайн-копия личных данных не хранится. Снимок доступен после восстановления связи.');
writeFileSync(join(checkout,'public/offline.html'),offline);
cpSync(join(root,'hosting/sites/runtime.ts'),join(checkout,'src/runtime.ts'));
cpSync(join(root,'hosting/sites/schema.ts'),join(checkout,'db/schema.ts'));
writeFileSync(join(checkout,'app/[[...path]]/route.ts'),`import { handle } from '../../src/runtime';\nexport const dynamic='force-dynamic';\nexport const GET=handle;\nexport const HEAD=handle;\nexport const POST=handle;\nexport const PUT=handle;\nexport const PATCH=handle;\nexport const DELETE=handle;\nexport const OPTIONS=handle;\n`);
console.log('Sites sources prepared. No personal data copied.');
