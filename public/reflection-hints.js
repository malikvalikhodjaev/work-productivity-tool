const topics = [
  {id:'feynman', label:'Понять и объяснить', source:'feynman', credit:'По твоему шаблону объяснения идей', questions:[
    'Что именно я пытаюсь понять: понятие, проблему или ситуацию?',
    'Как объяснить эту мысль своими словами человеку, который с ней ещё не знаком?',
    'Какой конкретный пример делает объяснение понятным?',
    'Где моё объяснение перестаёт быть ясным? Что я упускаю?',
    'Почему предложенный способ решения имеет смысл?',
    'Что я могу восстановить из памяти, прежде чем смотреть в источник?',
    'С чем сверить объяснение и что уточнить после проверки?'
  ]},
  {id:'oz', label:'Получить результат · Оз', source:'oz', credit:'Вопросы по мотивам «Принципа Оз»', questions:[
    'Что ещё я могу сделать, чтобы добиться нужного результата?',
    'Что происходит на самом деле? Какой факт я упускаю?',
    'Что в моих действиях помогает этому разрыву сохраняться?',
    'Какую часть ситуации я могу изменить сейчас?',
    'Какой ещё способ стоит попробовать?',
    'Что конкретно я сделаю сегодня и как проверю результат?'
  ]},
  {id:'lift', label:'Снять препятствие · LIFT', credit:'Вопросы по твоей подборке LIFT', questions:[
    'Какую неприятную обратную связь я пока не учитываю?',
    'Что действительно тормозит результат? Что ещё не пробовал?',
    'Что могу исправить в своём способе действий?',
    'Какой шаг за ближайшие 24 часа изменит ситуацию?'
  ]},
  {id:'done', label:'Что сделано', source:'done', credit:'Твой пост · вопрос с изображения и вопросы о пользе', questions:[
    'Что удалось сделать за эту неделю?',
    'Что я уже сделал сегодня для нужного результата?',
    'Что изменилось для людей или системы благодаря этой работе?',
    'Какое подтверждение результата у меня есть?'
  ]}
];
const algorithm = [
  ['Проверить требования', 'Кому и зачем это нужно? Какой запрос стоит пересмотреть?'],
  ['Удалить лишнее', 'Какой шаг или элемент можно убрать?'],
  ['Упростить оставшееся', 'Как получить тот же результат проще?'],
  ['Ускорить цикл', 'Где сократить ожидание и быстрее проверить результат?'],
  ['Автоматизировать', 'Что из проверенного процесса теперь стоит автоматизировать?']
];
let sourceRequest;
function loadSources() {
  return sourceRequest ??= fetch('/api/reflection-hints', {cache:'no-store'})
    .then(response => { if (!response.ok) throw new Error('Источники недоступны'); return response.json(); })
    .catch(() => { sourceRequest = null; return {sources:{}}; });
}

export function mountReflectionHints(container, {defaultTopic='oz'} = {}) {
  if (!container || container.dataset.reflectionMounted) return;
  container.dataset.reflectionMounted = 'true';
  container.classList.add('reflection-hints');
  container.innerHTML = `<details class="reflection-question"><summary>Вопрос для размышления</summary><div class="reflection-controls"><label>Тема <select aria-label="Тема подсказки"></select></label><span class="reflection-counter"></span><button type="button" class="text-button reflection-next">Другой вопрос →</button></div><p class="reflection-prompt" aria-live="polite"></p><div class="reflection-credit"><span></span><a target="_blank" rel="noopener noreferrer" hidden>Источник ↗</a></div></details><details class="reflection-algorithm"><summary>Алгоритм Маска · 5 шагов</summary><ol></ol><div class="reflection-credit"><span>Порядок важен: следующий шаг после предыдущего.</span><a class="reflection-musk" target="_blank" rel="noopener noreferrer" hidden>Твои заметки ↗</a><a class="reflection-musk-original" target="_blank" rel="noopener noreferrer" hidden>Интервью ↗</a></div></details>`;
  const select = container.querySelector('select'), prompt = container.querySelector('.reflection-prompt');
  const counter = container.querySelector('.reflection-counter'), credit = container.querySelector('.reflection-question .reflection-credit span');
  const link = container.querySelector('.reflection-question a');
  let position = 0, config = {sources:{}};
  for (const topic of topics) {
    const option = document.createElement('option'); option.value=topic.id; option.textContent=topic.label; select.append(option);
  }
  select.value = topics.some(topic => topic.id === defaultTopic) ? defaultTopic : 'oz';
  const attach = (element, source) => {
    const value = config.sources?.[source]?.url;
    let valid = false;
    try { const url=new URL(value); valid=['http:','https:'].includes(url.protocol)&&!url.username&&!url.password; } catch {}
    element.hidden = !valid;
    if (valid) element.href=value; else element.removeAttribute('href');
  };
  const render = () => {
    const topic = topics.find(item => item.id === select.value);
    prompt.textContent = topic.id==='done' && position===0 && config.doneQuote ? config.doneQuote : topic.questions[position];
    counter.textContent = `${position+1} / ${topic.questions.length}`;
    credit.textContent = topic.credit;
    attach(link, topic.source);
  };
  select.addEventListener('change', () => { position=0; render(); });
  container.querySelector('.reflection-next').addEventListener('click', () => {
    const topic=topics.find(item => item.id===select.value); position=(position+1)%topic.questions.length; render();
  });
  const list=container.querySelector('ol');
  for (const [title, question] of algorithm) {
    const item=document.createElement('li'), strong=document.createElement('strong'), text=document.createElement('span');
    strong.textContent=title; text.textContent=question; item.append(strong,text); list.append(item);
  }
  render();
  loadSources().then(value => {
    config=value; render(); attach(container.querySelector('.reflection-musk'),'musk'); attach(container.querySelector('.reflection-musk-original'),'muskOriginal');
  });
}

mountReflectionHints(document.getElementById('work-reflection'));
