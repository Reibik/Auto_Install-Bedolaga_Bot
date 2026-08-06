#!/usr/bin/env bash

if [[ -n "${BEDOLAGA_UI_LOADED:-}" ]]; then
  return 0
fi
BEDOLAGA_UI_LOADED=1

UI_EMOJI_ENABLED=0
case "${BEDOLAGA_EMOJI:-auto}" in
  1 | true | yes | on) UI_EMOJI_ENABLED=1 ;;
  0 | false | no | off) UI_EMOJI_ENABLED=0 ;;
  *)
    if [[ -t 1 && "${TERM:-dumb}" != dumb && "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" =~ [Uu][Tt][Ff]-?8 ]]; then
      UI_EMOJI_ENABLED=1
    fi
    ;;
esac

UI_UNICODE_ENABLED=0
if [[ -t 1 && "${TERM:-dumb}" != dumb && "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" =~ [Uu][Tt][Ff]-?8 ]]; then
  UI_UNICODE_ENABLED=1
fi

ui_icon() {
  local name="$1"
  if [[ "$UI_EMOJI_ENABLED" -eq 1 ]]; then
    case "$name" in
      brand) printf '🚀' ;;
      info) printf 'ℹ️' ;;
      success) printf '✅' ;;
      warning) printf '⚠️' ;;
      error) printf '❌' ;;
      active) printf '⏳' ;;
      pending) printf '⏸️' ;;
      server) printf '🖥️' ;;
      docker) printf '🐳' ;;
      package) printf '📦' ;;
      status) printf '📊' ;;
      start) printf '▶️' ;;
      stop) printf '⏹️' ;;
      restart) printf '🔄' ;;
      update) printf '⬆️' ;;
      deploy) printf '🚀' ;;
      doctor) printf '🩺' ;;
      logs) printf '📜' ;;
      config) printf '⚙️' ;;
      backup) printf '💾' ;;
      archives) printf '📂' ;;
      rollback) printf '↩️' ;;
      exit) printf '🚪' ;;
      globe) printf '🌐' ;;
      bot) printf '🤖' ;;
      webhook) printf '📨' ;;
      lock) printf '🔐' ;;
      lightbulb) printf '💡' ;;
      party) printf '🎉' ;;
      healthy) printf '🟢' ;;
      starting) printf '🟡' ;;
      unhealthy) printf '🔴' ;;
      stopped) printf '⚪' ;;
      *) printf '•' ;;
    esac
  else
    case "$name" in
      success | healthy) printf '[OK]' ;;
      warning | starting) printf '[!]' ;;
      error | unhealthy) printf '[X]' ;;
      active) printf '[..]' ;;
      pending | stopped) printf '[-]' ;;
      *) printf '[>]' ;;
    esac
  fi
}

ui_clear() {
  if [[ -t 1 && "${TERM:-dumb}" != dumb ]]; then
    clear
  fi
}

ui_banner() {
  local subtitle="${1:-Bot + Cabinet Deployment Manager}"
  local brand_icon
  brand_icon="$(ui_icon brand)"
  if [[ "$UI_UNICODE_ENABLED" -eq 1 ]]; then
    printf '%b╭──%b %s %bBEDOLAGA MANAGER%b · %bv%s%b\n' "$C_BLUE" "$C_RESET" "$brand_icon" "$C_BOLD" "$C_RESET" "$C_CYAN" "$BEDOLAGA_VERSION" "$C_RESET"
    printf '%b│%b   %s\n' "$C_BLUE" "$C_RESET" "$subtitle"
    printf '%b╰────────────────────────────────────────────%b\n' "$C_BLUE" "$C_RESET"
  else
    printf '%b+--%b BEDOLAGA MANAGER · v%s\n' "$C_BLUE" "$C_RESET" "$BEDOLAGA_VERSION"
    printf '%b|%b   %s\n' "$C_BLUE" "$C_RESET" "$subtitle"
    printf '%b+--------------------------------------------%b\n' "$C_BLUE" "$C_RESET"
  fi
}

ui_section() {
  local title="$1"
  if [[ "$UI_UNICODE_ENABLED" -eq 1 ]]; then
    printf '\n%b───────────── %s ─────────────%b\n\n' "$C_BLUE" "$title" "$C_RESET"
  else
    printf '\n%b------------- %s -------------%b\n\n' "$C_BLUE" "$title" "$C_RESET"
  fi
}

ui_separator() {
  if [[ "$UI_UNICODE_ENABLED" -eq 1 ]]; then
    printf '\n%b──────────────────────────────────────────────%b\n\n' "$C_BLUE" "$C_RESET"
  else
    printf '\n%b----------------------------------------------%b\n\n' "$C_BLUE" "$C_RESET"
  fi
}

ui_menu_item() {
  local number="$1" icon="$2" label="$3"
  printf '  %2s. %s %s\n' "$number" "$(ui_icon "$icon")" "$label"
}

ui_key_value() {
  local icon="$1" label="$2" value="$3"
  printf '  %s  %-16s %s\n' "$(ui_icon "$icon")" "${label}:" "$value"
}

ui_service_row() {
  local service="$1" state="$2"
  local icon='stopped' state_text="$state"
  case "$state" in
    running/healthy) icon='healthy'; state_text='Работает · healthy' ;;
    running/none) icon='healthy'; state_text='Работает' ;;
    running/starting) icon='starting'; state_text='Запускается' ;;
    running/unhealthy) icon='unhealthy'; state_text='Ошибка · unhealthy' ;;
    exited/* | dead/*) icon='unhealthy'; state_text='Остановлен с ошибкой' ;;
    not-created) icon='stopped'; state_text='Не создан' ;;
    *) icon='stopped' ;;
  esac
  printf '  %s  %-16s %s\n' "$(ui_icon "$icon")" "$service" "$state_text"
}

ui_step() {
  local state="$1" text="$2"
  local icon="$state"
  case "$state" in
    done) icon='success' ;;
    active) icon='active' ;;
    pending) icon='pending' ;;
    failed) icon='error' ;;
  esac
  printf '  %s %s\n' "$(ui_icon "$icon")" "$text"
}

ui_progress() {
  local current="$1" total="$2" text="$3"
  printf '\n%b%s Шаг %s из %s · %s%b\n' "$C_CYAN" "$(ui_icon active)" "$current" "$total" "$text" "$C_RESET"
}

ui_hint() {
  printf '\n  %s %s\n' "$(ui_icon lightbulb)" "$*"
}

ui_install_success() {
  local bot_username="$1" cabinet_url="$2" webhook_url="$3" backup_status="${4:-Включены}" xray_url="${5:-}"
  printf '\n'
  if [[ "$UI_UNICODE_ENABLED" -eq 1 ]]; then
    printf '%b╭──%b %s %bBEDOLAGA УСПЕШНО УСТАНОВЛЕНА%b\n' "$C_GREEN" "$C_RESET" "$(ui_icon party)" "$C_BOLD" "$C_RESET"
    printf '%b╰────────────────────────────────────────────%b\n' "$C_GREEN" "$C_RESET"
  else
    printf '%b+--%b BEDOLAGA УСПЕШНО УСТАНОВЛЕНА\n' "$C_GREEN" "$C_RESET"
    printf '%b+--------------------------------------------%b\n' "$C_GREEN" "$C_RESET"
  fi
  printf '\n'
  ui_key_value bot 'Telegram Bot' "@${bot_username}"
  ui_key_value globe 'Cabinet' "$cabinet_url"
  ui_key_value webhook 'Webhook' "$webhook_url"
  [[ -z "$xray_url" ]] || ui_key_value status 'Xray Status' "$xray_url"
  ui_key_value lock 'HTTPS' 'Активен'
  ui_key_value backup 'Автобэкапы' "$backup_status"
  printf '\n  Команда управления: %bbedolaga%b\n' "$C_BOLD" "$C_RESET"
}

info() {
  printf '%s %s\n' "$(ui_icon info)" "$*"
  log_line INFO "$*"
}

success() {
  printf '%b%s%b %s\n' "$C_GREEN" "$(ui_icon success)" "$C_RESET" "$*"
  log_line OK "$*"
}

warn() {
  printf '%b%s%b %s\n' "$C_YELLOW" "$(ui_icon warning)" "$C_RESET" "$*" >&2
  log_line WARN "$*"
}

error() {
  printf '%b%s%b %s\n' "$C_RED" "$(ui_icon error)" "$C_RESET" "$*" >&2
  log_line ERROR "$*"
}
