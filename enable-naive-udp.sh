#!/usr/bin/env bash
set -euo pipefail

CADDY_SERVICE="caddy-naive"
CADDY_BIN="/usr/local/bin/caddy-naive"
BUILD_DIR="/root"
NEW_CADDY="${BUILD_DIR}/caddy"
XCADDY="${XCADDY:-}"

# Отдельный каталог для временных файлов (не в /tmp, чтобы не упираться в tmpfs)
BUILD_TMP="${BUILD_DIR}/caddy-build-tmp"
mkdir -p "$BUILD_TMP"

OLD_BACKUP="${CADDY_BIN}_old_$(date +%Y%m%d-%H%M%S)"

log() {
  echo -e "\033[0;32m[INFO]\033[0m $*"
}

warn() {
  echo -e "\033[1;33m[WARN]\033[0m $*"
}

err() {
  echo -e "\033[0;31m[ERROR]\033[0m $*" >&2
}

need_root() {
  if [[ "$EUID" -ne 0 ]]; then
    err "Запусти скрипт от root: sudo bash enable-naive-udp.sh"
    exit 1
  fi
}

install_go_if_needed() {
  if command -v go >/dev/null 2>&1; then
    log "Go найден: $(go version)"
    return
  fi

  log "Go не найден, пробуем установить"

  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y golang-go
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y golang
  elif command -v yum >/dev/null 2>&1; then
    yum install -y golang
  else
    err "Не удалось установить Go автоматически: не найден apt-get, dnf или yum"
    echo ""
    echo "Установи Go вручную и запусти скрипт снова."
    exit 1
  fi

  if ! command -v go >/dev/null 2>&1; then
    err "Go был установлен, но команда go всё ещё не найдена"
    exit 1
  fi

  log "Go установлен: $(go version)"
}

install_xcaddy_if_needed() {
  if [[ -n "$XCADDY" && -x "$XCADDY" ]]; then
    log "xcaddy найден: $XCADDY"
    return
  fi

  if command -v xcaddy >/dev/null 2>&1; then
    XCADDY="$(command -v xcaddy)"
    log "xcaddy найден: $XCADDY"
    return
  fi

  local gopath
  gopath="$(go env GOPATH)"
  XCADDY="${gopath}/bin/xcaddy"

  if [[ -x "$XCADDY" ]]; then
    log "xcaddy найден: $XCADDY"
    return
  fi

  log "xcaddy не найден, устанавливаем через go install"

  go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

  if [[ ! -x "$XCADDY" ]]; then
    err "xcaddy был установлен, но бинарник не найден или не исполняемый: $XCADDY"
    exit 1
  fi

  log "xcaddy установлен: $XCADDY"
}

check_requirements() {
  log "Проверяем зависимости"

  install_go_if_needed
  install_xcaddy_if_needed

  if [[ ! -f "$CADDY_BIN" ]]; then
    err "Не найден текущий caddy-naive: $CADDY_BIN"
    exit 1
  fi

  if ! command -v systemctl >/dev/null 2>&1; then
    err "systemctl не найден"
    exit 1
  fi

  log "OK"
}

build_caddy() {
  log "Собираем новый Caddy с naive forwardproxy UDP support (минимальные ресурсы)"

  rm -f "$NEW_CADDY"

  # 1. Перенаправляем временные файлы в отдельный каталог на диске
  export TMPDIR="$BUILD_TMP"
  log "TMPDIR=$TMPDIR"

  # 2. Очищаем кэш Go — экономит сотни мегабайт места и ускоряет сборку
  log "Очищаем кэш Go..."
  go clean -cache -modcache -testcache -fuzzcache

  # 3. Ограничиваем параллелизм компиляции — снижает пиковое потребление RAM
  export GOMAXPROCS=2
  log "GOMAXPROCS=$GOMAXPROCS"

  cd "$BUILD_DIR"

  # 4. Сборка с минимальным бинарником (-ldflags="-s -w")
  "$XCADDY" build \
    --with github.com/caddyserver/forwardproxy@caddy2=github.com/aUsernameWoW/forwardproxy@naive \
    -ldflags="-s -w"

  if [[ ! -x "$NEW_CADDY" ]]; then
    err "Сборка завершилась, но бинарник не найден или не исполняемый: $NEW_CADDY"
    exit 1
  fi

  log "Новый Caddy собран: $NEW_CADDY"
  ls -lh "$NEW_CADDY"

  log "Версия нового Caddy:"
  "$NEW_CADDY" version || true

  # 5. Опционально: чистим TMPDIR после успешной сборки (раскомментируй, если хочешь сразу освободить место)
  # rm -rf "${BUILD_TMP:?}"/*
}

stop_current_caddy() {
  log "Останавливаем текущий сервис: $CADDY_SERVICE"

  systemctl stop "$CADDY_SERVICE"

  if systemctl is-active --quiet "$CADDY_SERVICE"; then
    err "Не удалось остановить $CADDY_SERVICE"
    exit 1
  fi

  log "$CADDY_SERVICE остановлен"
}

install_new_caddy() {
  log "Делаем backup старого бинарника"

  mv "$CADDY_BIN" "$OLD_BACKUP"
  log "Старый бинарник сохранён как: $OLD_BACKUP"

  log "Устанавливаем новый бинарник"

  mv "$NEW_CADDY" "$CADDY_BIN"

  chmod 755 "$CADDY_BIN"

  if command -v setcap >/dev/null 2>&1; then
    setcap 'cap_net_bind_service=+ep' "$CADDY_BIN" 2>/dev/null || warn "Не удалось установить setcap, сервис всё равно может работать через AmbientCapabilities"
  fi

  log "Новый бинарник установлен: $CADDY_BIN"
  "$CADDY_BIN" version || true
}

start_caddy() {
  log "Запускаем сервис: $CADDY_SERVICE"

  systemctl reset-failed "$CADDY_SERVICE" 2>/dev/null || true
  systemctl start "$CADDY_SERVICE"

  sleep 2

  if systemctl is-active --quiet "$CADDY_SERVICE"; then
    log "$CADDY_SERVICE запущен"
  else
    err "$CADDY_SERVICE не запустился"
    echo ""
    echo "Последние логи:"
    journalctl -u "$CADDY_SERVICE" -n 80 --no-pager || true
    echo ""
    echo "Откатить старый бинарник можно так:"
    echo "  systemctl stop $CADDY_SERVICE"
    echo "  mv $CADDY_BIN ${CADDY_BIN}.failed"
    echo "  mv $OLD_BACKUP $CADDY_BIN"
    echo "  systemctl start $CADDY_SERVICE"
    exit 1
  fi
}

verify() {
  log "Проверяем статус сервиса"

  systemctl status "$CADDY_SERVICE" --no-pager | sed -n '1,20p' || true

  echo ""
  log "Проверяем слушающие порты"

  ss -tlnp | grep -E ':80|:443|:8080|:3000' || true

  echo ""
  log "Проверяем версию установленного бинарника"

  "$CADDY_BIN" version || true

  echo ""
  log "Проверяем HTTP-ответы"

  if ss -tlnp | grep -q ':80'; then
    curl -I --max-time 8 http://127.0.0.1/ || true
  fi

  if ss -tlnp | grep -q ':8080'; then
    curl -I --max-time 8 http://127.0.0.1:8080/ || true
  fi

  echo ""
  log "Готово. Старый бинарник сохранён:"
  echo "  $OLD_BACKUP"
}

main() {
  need_root
  check_requirements
  build_caddy
  stop_current_caddy
  install_new_caddy
  start_caddy
  verify
}

main "$@"
