# VPS · эксплуатация Indicators & Work

Первая установка: DigitalOcean Basic Regular, Ubuntu 24.04, 1 vCPU / 1 GiB. Docker Compose запускает один пишущий сервер. Данные — обычные файлы в постоянном каталоге; клиенты сохраняют изменения локально до отправки.

## Где что находится

| Место | Назначение |
| --- | --- |
| `/srv/indicators-work/current` | Развёрнутый комплект сервера |
| `current/data` | Личные данные, входящие, вложения, настройки и резервные копии |
| `/srv/indicators-work/runtime-compose.yaml` | Ограничение журналов контейнера: 3 файла по 10 МБ |
| `/srv/indicators-work/transfer-verification.json` | Результат проверки исходного финального пакета |
| `/srv/indicators-work/persistence-verification.json` | Проверка сохранения данных после перезапуска |

SSH-ключ и адрес хоста хранятся у владельца отдельно от публичного репозитория. Порты 8787/8789 опубликованы только на loopback VPS. Tailscale Serve направляет закрытый HTTPS-адрес на шлюз 8789; шлюз проверяет аккаунт владельца. Funnel не используется.

## Проверка и перезапуск

Команды выполняются после входа по SSH на свой VPS:

```sh
cd /srv/indicators-work/current
docker compose -p indicators-work -f compose.yaml -f /srv/indicators-work/runtime-compose.yaml ps
curl --fail http://127.0.0.1:8787/api/health
docker compose -p indicators-work -f compose.yaml -f /srv/indicators-work/runtime-compose.yaml logs --tail=100 dashboard
```

Штатный перезапуск:

```sh
cd /srv/indicators-work/current
docker compose -p indicators-work -f compose.yaml -f /srv/indicators-work/runtime-compose.yaml restart dashboard
```

Docker и tailscaled включены в systemd; контейнер использует `restart: unless-stopped`. После ручной остановки его нужно запустить явно:

```sh
cd /srv/indicators-work/current
docker compose -p indicators-work -f compose.yaml -f /srv/indicators-work/runtime-compose.yaml up -d --no-build
tailscale serve status
```

При выключенном ПК VPS продолжает работать. На телефоне и ПК для синхронизации нужен Tailscale под аккаунтом владельца. При отсутствии сети записи остаются на устройстве.

## Резервные копии

Приложение проверяет необходимость копии каждые 15 минут, при запуске и штатной остановке. Изменившиеся файлы копируются в `data/backups`; в манифесте есть SHA-256. Проверка и принудительная копия:

```sh
cd /srv/indicators-work/current
curl --fail http://127.0.0.1:8787/api/server-status
docker exec indicators-work-dashboard-1 node scripts/backup.mjs
```

Эти копии находятся на том же диске VPS. Отдельная выгрузка на ПК или другое хранилище нужна для восстановления при потере самого VPS. Финальный архив переноса на ПК сохраняется отдельно. Платные автоматические копии DigitalOcean данным развёртыванием не включаются.

Не публикуй `data/`, SQLite клиентов, архивы переноса, настройки Telegram и SSH-ключи в GitHub. На VPS каталог данных принадлежит UID 1000; личные файлы доступны владельцу контейнера, а не всем пользователям хоста.

## Если пропала связь

1. Проверь Tailscale на устройстве и актуальный адрес в настройках приложения.
2. По SSH проверь контейнер и локальный health указанными выше командами.
3. Проверь `tailscale status` и `tailscale serve status` на VPS.
4. Сверь текст ошибки и журналы. Не очищай клиентскую SQLite и очередь ради смены адреса.

Новый хост использует прежние `serverId` и `writingInstanceId`. Сообщение «другая установка сервера» означает, что нужно проверить архив и адрес; сброс привязки скрывает причину и не переносит данные.

## Windows после переезда

В `data/server-moved.json` локальной установки записан проверенный адрес VPS и идентификаторы архива. Ярлык и автозагрузка запускают клиент с удалённым сервером; старый `server.mjs` отказывается от записи. Не удаляй этот маркер для восстановления доступа.

Перед сменой адреса сохрани тексты, синхронизируй устройства и сделай копию SQLite. Изменяй адрес через настройки приложения. Не редактируй живую клиентскую SQLite другим процессом. Файлы SQLite, WAL и SHM сохраняются вместе при диагностике; исходники и проверенные копии не удаляются.

## Откат и обновление

Перед обновлением сохрани тексты и отдельную согласованную копию данных, зафиксируй версию образа. Старый и новый серверы одного архива не должны одновременно принимать записи или опрашивать Telegram.

Если VPS уже принял новые данные, для отката нужен его актуальный архив после остановки записи. Прежний снимок на ПК не включает новые записи. Порядок смены хоста и проверки финального пакета — [ADR-030](ADR-030-digitalocean-and-active-focus.md).

Источники установки: [Docker Engine для Ubuntu](https://docs.docker.com/engine/install/ubuntu/), [Tailscale для Linux](https://tailscale.com/docs/install/linux), [Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve).
