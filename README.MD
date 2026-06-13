# enable-naive-udp.sh

Скрипт для замены установленного `caddy-naive` на сборку Caddy с поддержкой UDP для `naiveproxy`.

Скрипт собирает новый бинарник Caddy через `xcaddy` с модифицированным `forwardproxy`, делает резервную копию текущего бинарника, заменяет его и перезапускает `systemd`-сервис.

## Что делает скрипт

Скрипт выполняет следующие действия:

1. Проверяет, что запущен от `root`.
2. Проверяет наличие текущего бинарника `caddy-naive`.
3. Проверяет наличие `systemctl`.
4. Проверяет наличие Go.
5. Если Go не найден — пытается установить его через пакетный менеджер системы.
6. Проверяет наличие `xcaddy`.
7. Если `xcaddy` не найден — устанавливает его командой:

   ```bash
   go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
   ```

8. Собирает новый Caddy с поддержкой UDP:

   ```bash
   xcaddy build \
     --with github.com/caddyserver/forwardproxy@caddy2=github.com/aUsernameWoW/forwardproxy@naive
   ```

9. Останавливает текущий сервис `caddy-naive`.
10. Делает резервную копию старого бинарника.
11. Устанавливает новый бинарник вместо старого.
12. При наличии `setcap` выдаёт бинарнику право слушать привилегированные порты `80` и `443`.
13. Запускает сервис `caddy-naive`.
14. Показывает статус сервиса, слушающие порты и версию установленного Caddy.

## Требования

Поддерживаемая среда:

- установленный и настроенный сервис `caddy-naive`;
- установленный текущий бинарник:

  ```text
  /usr/local/bin/caddy-naive
  ```

Скрипт умеет автоматически установить Go, если в системе есть один из пакетных менеджеров:

- `apt-get`;
- `dnf`;
- `yum`.

`xcaddy` устанавливается автоматически через:
`xcaddy` устанавливается автоматически через:

```bash
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
```

Обычно бинарник `xcaddy` после установки будет находиться здесь:

```text
/root/go/bin/xcaddy
```

## Пути по умолчанию

В скрипте используются следующие значения:

```bash
CADDY_SERVICE="caddy-naive"
CADDY_BIN="/usr/local/bin/caddy-naive"
BUILD_DIR="/root"
NEW_CADDY="${BUILD_DIR}/caddy"
```

Где:

- `CADDY_SERVICE` — имя `systemd`-сервиса;
- `CADDY_BIN` — путь к установленному бинарнику `caddy-naive`;
- `BUILD_DIR` — директория, в которой будет выполняться сборка;
- `NEW_CADDY` — временный путь к новому собранному бинарнику.

Если у вас другие пути или другое имя сервиса, измените эти переменные в начале скрипта.

## Быстрый запуск


```bash
curl -fsSL https://raw.githubusercontent.com/WildSpy/caddy-naive-udp-support/main/enable-naive-udp.sh | sudo bash
```

## Что будет с текущим бинарником

Перед заменой старый бинарник сохраняется в резервную копию рядом с исходным файлом.

Например:

```text
/usr/local/bin/caddy-naive_old_20260613-153000
```

Точный путь будет показан в конце выполнения скрипта.

## Откат

Если после замены сервис не запустился, скрипт покажет команды для отката.

Вручную откат можно выполнить так:

```bash
systemctl stop caddy-naive
mv /usr/local/bin/caddy-naive /usr/local/bin/caddy-naive.failed
mv /usr/local/bin/caddy-naive_old_YYYYMMDD-HHMMSS /usr/local/bin/caddy-naive
systemctl start caddy-naive
```

Замените:

```text
/usr/local/bin/caddy-naive_old_YYYYMMDD-HHMMSS
```

на реальный путь к backup-файлу, который вывел скрипт.

