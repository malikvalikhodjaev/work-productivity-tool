# Формат локальных снимков Coda

Дашборд читает два необязательных UTF-8 JSON-файла в `data/imports/`. Автоматическое получение из Coda ещё не реализовано. Файлы и личные ссылки не входят в Git.

Без файла API возвращает пустые массивы и `available: false`. Существующий корректный JSON получает `available: true`; ошибка чтения отображается явно. Не записывай `available` вручную. «Обновить» перечитывает файлы с диска.

## Работы, цели, Issues

Минимальное содержимое `data/imports/coda-snapshot.json`:

```json
{
  "capturedAt": null,
  "sources": {},
  "work": [],
  "goals": [],
  "issues": []
}
```

`capturedAt` — дата получения снимка или `null`, если неизвестна. В `sources` допустимы ключи `work`, `goals`, `issues` с HTTPS-ссылками на собственные таблицы. Неизвестные скалярные значения сохраняй как `null`; отсутствующие списки — как `[]`.

| Массив | Поля каждой строки |
| --- | --- |
| `work` | `title`, `stage`, `projects` (массив строк), `workType`, `goals` (массив строк), `deadline`, `done` (boolean) |
| `goals` | `title`, `status`, `area`, `measurement`, `completion`, `deadline` |
| `issues` | `title`, `status`, `note` |

`done` отражает отметку исходной таблицы. Наличие строки не означает активный проект, завершённую задачу или достижение цели.

## Отдельный пакет шаблонов

Минимальное содержимое `data/imports/alpha-reference.json`:

```json
{
  "capturedAt": null,
  "sources": {},
  "rows": [],
  "roles": [],
  "mistakes": [],
  "actions": [],
  "guidance": [],
  "objectFields": []
}
```

В `sources` допустимы `catalog` и `management` с HTTPS-ссылками на собственный справочник и пакет материалов.

| Массив | Поля каждой строки |
| --- | --- |
| `rows` | `level`, `area`, `alpha`, `state`, `question`, `checkStatus` |
| `roles` | `role`, `practice`, `area` |
| `mistakes` | `mistake`, `reason` |
| `actions` | `action`, `reason` |
| `guidance` | Строки с подсказками |
| `objectFields` | Строки с названиями полей карточки |

Строки шаблона не включаются в прогресс альф, часы и счётчики проектов. Для этого нужны экземпляры с явными связями и правилами учёта из ADR.
