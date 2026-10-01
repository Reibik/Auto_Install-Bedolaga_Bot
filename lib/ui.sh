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
      sparkle) printf '✨' ;;
      shield) printf '🛡️' ;;
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
  ui_refresh_geometry
  if [[ -t 1 && "${TERM:-dumb}" != dumb ]]; then
    clear
  fi
}

ui_refresh_geometry() {
  local columns="${BEDOLAGA_UI_WIDTH:-}"
  if [[ -z "$columns" && -t 1 ]]; then
    columns="$(tput cols 2>/dev/null || true)"
  fi
  [[ -n "$columns" ]] || columns="${COLUMNS:-80}"
  [[ "$columns" =~ ^[0-9]{1,4}$ ]] || columns=80
  columns=$((10#$columns))
  ((columns >= 20)) || columns=20
  ((columns <= 80)) || columns=80
  UI_WIDTH="$columns"
}

# Wrap plain text before applying ANSI colours. C.UTF-8 keeps Cyrillic intact
# even when the terminal uses LANG=C and the ASCII UI has been selected.
ui_wrap_text() {
  local LC_ALL=C.UTF-8
  local text="$1" width="${2:-$UI_WIDTH}" indent="${3:-}" chunk
  text="${text//$'\n'/ }"
  text="${text//$'\r'/}"
  text="${text//$'\t'/ }"
  while ((${#text} > width)); do
    chunk="${text:0:width}"
    if [[ "$chunk" == *' '* && -n "${chunk% *}" ]]; then
      chunk="${chunk% *}"
    fi
    printf '%s\n%s' "$chunk" "$indent"
    text="${text:${#chunk}}"
    text="${text#"${text%%[![:space:]]*}"}"
  done
  printf '%s\n' "$text"
}

ui_rule() {
  local character='-' rule
  [[ "$UI_UNICODE_ENABLED" -eq 0 ]] || character='─'
  printf -v rule '%*s' "$UI_WIDTH" ''
  printf '%b%s%b\n' "$C_BLUE" "${rule// /$character}" "$C_RESET"
}

ui_refresh_geometry

ui_banner() {
  local subtitle="${1:-Bot · Cabinet · Xray Monitoring}"
  if ((UI_WIDTH < 36)); then
    printf '%bBEDOLAGA MANAGER%b\n' "$C_BOLD" "$C_RESET"
    printf '%bv%s%b\n' "$C_CYAN" "$BEDOLAGA_VERSION" "$C_RESET"
  else
    printf '%s %bBEDOLAGA MANAGER%b  %bv%s%b\n' "$(ui_icon brand)" "$C_BOLD" "$C_RESET" "$C_CYAN" "$BEDOLAGA_VERSION" "$C_RESET"
  fi
  [[ -z "$subtitle" ]] || ui_wrap_text "$subtitle"
  ui_rule
}

ui_section() {
  local title="$1"
  printf '\n%b' "$C_BOLD"
  ui_wrap_text "$title"
  printf '%b' "$C_RESET"
}

ui_separator() {
  ui_rule
}

ui_menu_item() {
  local number="$1" icon="$2" label="$3" label_colour="${4:-$C_RESET}" icon_text indent prefix_width
  icon_text="$(ui_icon "$icon")"
  prefix_width=$((10 + ${#icon_text}))
  [[ "$UI_EMOJI_ENABLED" -eq 0 ]] || prefix_width=12
  printf -v indent '%*s' "$prefix_width" ''
  printf '  %b[%2s]%b  %s  ' "$C_CYAN" "$number" "$C_RESET" "$icon_text"
  printf '%b' "$label_colour"
  ui_wrap_text "$label" "$((UI_WIDTH - prefix_width))" "$indent"
  printf '%b' "$C_RESET"
}

ui_danger_item() {
  local number="$1" icon="$2" label="$3"
  ui_menu_item "$number" "$icon" "$label" "$C_RED"
}

ui_key_value() {
  local icon="$1" label="$2" value="$3" colour="${4:-}" icon_text indent prefix_width
  if [[ -z "$colour" ]]; then
    case "$icon" in
      healthy | success) colour="$C_GREEN" ;;
      unhealthy | error) colour="$C_RED" ;;
      warning | starting | pending) colour="$C_YELLOW" ;;
      *) colour="$C_RESET" ;;
    esac
  fi
  icon_text="$(ui_icon "$icon")"
  prefix_width=$((3 + ${#icon_text}))
  [[ "$UI_EMOJI_ENABLED" -eq 0 ]] || prefix_width=5
  printf -v indent '%*s' "$prefix_width" ''
  printf '%b  %s ' "$colour" "$icon_text"
  ui_wrap_text "${label}: $value" "$((UI_WIDTH - prefix_width))" "$indent"
  printf '%b' "$C_RESET"
}

ui_state_details() {
  local state="$1"
  UI_STATE_ICON=warning
  UI_STATE_TEXT='Состояние неизвестно'
  UI_STATE_COLOR="$C_YELLOW"
  case "$state" in
    running/healthy | running/none) UI_STATE_ICON=healthy; UI_STATE_TEXT='Работает'; UI_STATE_COLOR="$C_GREEN" ;;
    running/starting) UI_STATE_ICON=starting; UI_STATE_TEXT='Запускается' ;;
    running/unhealthy) UI_STATE_ICON=unhealthy; UI_STATE_TEXT='Ошибка health check'; UI_STATE_COLOR="$C_RED" ;;
    exited/0) UI_STATE_ICON=stopped; UI_STATE_TEXT='Остановлен'; UI_STATE_COLOR="$C_RESET" ;;
    exited/[0-9]*) UI_STATE_ICON=unhealthy; UI_STATE_TEXT="Завершён · код ${state#*/}"; UI_STATE_COLOR="$C_RED" ;;
    exited/*) UI_STATE_ICON=stopped; UI_STATE_TEXT='Остановлен · код неизвестен' ;;
    dead/*) UI_STATE_ICON=unhealthy; UI_STATE_TEXT='Недоступен · dead'; UI_STATE_COLOR="$C_RED" ;;
    created/*) UI_STATE_ICON=stopped; UI_STATE_TEXT='Ещё не запущен'; UI_STATE_COLOR="$C_RESET" ;;
    paused/*) UI_STATE_ICON=pending; UI_STATE_TEXT='На паузе' ;;
    restarting/*) UI_STATE_ICON=starting; UI_STATE_TEXT='Перезапускается' ;;
    removing/*) UI_STATE_ICON=pending; UI_STATE_TEXT='Удаляется' ;;
    not-created) UI_STATE_ICON=stopped; UI_STATE_TEXT='Не создан'; UI_STATE_COLOR="$C_RESET" ;;
    unavailable/*) UI_STATE_TEXT='Docker недоступен' ;;
  esac
}

ui_service_row() {
  local service="$1" state="$2"
  ui_state_details "$state"
  ui_key_value "$UI_STATE_ICON" "$service" "$UI_STATE_TEXT" "$UI_STATE_COLOR"
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
  printf '  %s ' "$(ui_icon "$icon")"
  ui_wrap_text "$text" "$((UI_WIDTH - 6))" '      '
}

ui_progress() {
  local current="$1" total="$2" text="$3"
  printf '\n%b' "$C_CYAN"
  ui_wrap_text "Шаг $current из $total · $text"
  printf '%b' "$C_RESET"
}

ui_hint() {
  ui_key_value lightbulb 'Подсказка' "$*"
}

ui_manager_update() {
  local current_version="$1" next_version="$2"
  local arrow='->'
  shift 2
  [[ "$UI_UNICODE_ENABLED" -eq 0 ]] || arrow='→'
  ui_section 'Обновление Manager'
  ui_key_value package 'Сейчас' "v$current_version"
  ui_key_value update 'Новая версия' "v$next_version" "$C_GREEN"
  ui_key_value update 'Переход' "v$current_version $arrow v$next_version"
  if [[ "$#" -gt 0 ]]; then
    printf '\n  %bЧто изменилось:%b\n' "$C_BOLD" "$C_RESET"
    local note
    for note in "$@"; do
      printf '  %b*%b ' "$C_CYAN" "$C_RESET"
      ui_wrap_text "$note" "$((UI_WIDTH - 4))" '    '
    done
  fi
  ui_hint 'Стабильный релиз проверен. Начинаю безопасное обновление.'
}

ui_install_success() {
  local bot_username="$1" cabinet_url="$2" webhook_url="$3" backup_status="${4:-Включены}" xray_url="${5:-}"
  printf '\n'
  printf '%b' "$C_GREEN"
  ui_wrap_text 'BEDOLAGA УСПЕШНО УСТАНОВЛЕНА'
  printf '%b' "$C_RESET"
  ui_rule
  printf '\n'
  ui_key_value bot 'Telegram Bot' "@${bot_username}"
  ui_key_value globe 'Cabinet' "$cabinet_url"
  ui_key_value webhook 'Webhook' "$webhook_url"
  [[ -z "$xray_url" ]] || ui_key_value status 'Xray Status' "$xray_url"
  ui_key_value lock 'HTTPS' 'Активен'
  ui_key_value backup 'Автобэкапы' "$backup_status"
  ui_key_value config 'Команда' 'bedolaga'
}

info() {
  printf '%b%s%b ' "$C_CYAN" "$(ui_icon info)" "$C_RESET"
  ui_wrap_text "$*" "$((UI_WIDTH - 6))" '      '
  log_line INFO "$*"
}

success() {
  printf '%b%s ' "$C_GREEN" "$(ui_icon success)"
  ui_wrap_text "$*" "$((UI_WIDTH - 6))" '      '
  printf '%b' "$C_RESET"
  log_line OK "$*"
}

warn() {
  { printf '%b%s ' "$C_YELLOW" "$(ui_icon warning)"; ui_wrap_text "$*" "$((UI_WIDTH - 6))" '      '; printf '%b' "$C_RESET"; } >&2
  log_line WARN "$*"
}

error() {
  { printf '%b%s ' "$C_RED" "$(ui_icon error)"; ui_wrap_text "$*" "$((UI_WIDTH - 6))" '      '; printf '%b' "$C_RESET"; } >&2
  log_line ERROR "$*"
}
