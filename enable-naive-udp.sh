#!/usr/bin/env bash
set -euo pipefail

CADDY_SERVICE="caddy-naive"
CADDY_BIN="/usr/local/bin/caddy-naive"
BUILD_DIR="/root"
NEW_CADDY="${BUILD_DIR}/caddy"

# Прямая ссылка на бинарник (версия 2.11.4)
DOWNLOAD_URL="https://github.com/2Dem13/caddy-naive-udp-support/releases/download/2.11.4/caddy"

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

check_requirements() {
  log "Проверяем зависимости"

  if [[ ! -f "$CADDY_BIN" ]]; then
    err "Не найден текущий caddy-naive: $CADDY_BIN"
    exit 1
  fi

  if ! command -v systemctl >/dev/null 2>&1; then
    err "systemctl не найден"
    exit 1
  fi

  if ! command -v curl >/dev/null 2>&1; then
    err "curl не найден — требуется для скачивания бинарника"
    exit 1
  fi

  log "OK"
}

fetch_binary() {
  log "Скачиваем бинарный файл: $DOWNLOAD_URL"

  rm -f "$NEW_CADDY"

  curl -L -o "$NEW_CADDY" "$DOWNLOAD_URL"

  if [[ ! -s "$NEW_CADDY" ]]; then
    err "Файл скачался пустым или не скачался"
    exit 1
  fi

  chmod 755 "$NEW_CADDY"

  if [[ ! -x "$NEW_CADDY" ]]; then
    err "Скачанный файл не является исполняемым"
    exit 1
  fi

  log "Бинарник скачан и сделан исполняемым: $NEW_CADDY"
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
  fetch_binary
  stop_current_caddy
  install_new_caddy
  start_caddy
  verify
}

main "$@"
