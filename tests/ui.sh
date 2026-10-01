#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BEDOLAGA_LIB_ROOT="$PROJECT_ROOT"
export NO_COLOR=1
export BEDOLAGA_EMOJI=0
export LANG=C

# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/common.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/ui.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[[ -z "$C_RED" && -z "$C_GREEN" && -z "$C_RESET" ]] || fail "NO_COLOR did not disable ANSI colors"
[[ "$(ui_icon success)" == '[OK]' ]] || fail "emoji fallback is incorrect"

output="$({
  ui_banner 'UI test'
  ui_section 'Services'
  ui_service_row bot running/healthy
  ui_service_row caddy running/unhealthy
  ui_step active 'Working'
  ui_hint 'Run a command'
  ui_manager_update 1.2.0 1.3.0 'Automatic stable update'
})"
grep -q 'BEDOLAGA MANAGER' <<<"$output" || fail "banner is missing"
grep -q 'bot.*Работает' <<<"$output" || fail "healthy service row is missing"
grep -q 'caddy.*Ошибка' <<<"$output" || fail "unhealthy service row is missing"
grep -q '1.2.0.*1.3.0' <<<"$(tr '\n' ' ' <<<"$output")" || fail "manager update versions are missing"
grep -q 'Automatic stable update' <<<"$output" || fail "manager update notes are missing"
[[ "$output" != *$'\033'* ]] || fail "ANSI escape found with NO_COLOR"

export BEDOLAGA_TEST_PROJECT_ROOT="$PROJECT_ROOT"

[[ "$(ui_service_row bot exited/0)" == *'Остановлен'* ]] || fail 'normal stop was not displayed'
[[ "$(ui_service_row bot exited/0)" != *'код'* ]] || fail 'normal stop was marked as failure'
[[ "$(ui_service_row bot exited/137)" == *'код 137'* ]] || fail 'nonzero exit code missing'
[[ "$(ui_service_row bot paused/healthy)" == *'На паузе'* ]] || fail 'paused status missing'
[[ "$(ui_service_row bot restarting/none)" == *'Перезапускается'* ]] || fail 'restart status missing'

for BEDOLAGA_UI_WIDTH in 20 32 48 80 0080; do
  ui_refresh_geometry
  narrow_output="$({
    ui_banner 'Сервисы и диагностика проекта'
    ui_section 'Резервное копирование и восстановление'
    ui_menu_item 1 config 'Параметры конфигурации бота'
    ui_key_value globe 'Cabinet' 'https://cabinet.long-example-domain.example.com/api'
    ui_service_row bot exited/137
    ui_service_row cabinet running/healthy
    ui_progress 2 7 'Подготовка исходников компонентов'
    ui_manager_update 1.3.1 1.4.0 'Понятное описание изменений для пользователей'
  })"
  while IFS= read -r line; do
    LC_ALL=C.UTF-8
    ((${#line} <= UI_WIDTH)) || fail "line exceeds $UI_WIDTH columns: $line"
  done <<<"$narrow_output"
done
BEDOLAGA_UI_WIDTH=invalid
ui_refresh_geometry
[[ "$UI_WIDTH" == 80 ]] || fail 'invalid width was accepted'
# Переменная раскрывается во вложенном bash, а не в текущем процессе.
# shellcheck disable=SC2016
emoji_output="$(NO_COLOR=1 BEDOLAGA_EMOJI=1 LANG=C.UTF-8 bash -c '
  source "$BEDOLAGA_TEST_PROJECT_ROOT/lib/common.sh"
  source "$BEDOLAGA_TEST_PROJECT_ROOT/lib/ui.sh"
  ui_icon success
')"
[[ "$emoji_output" == '✅' ]] || fail "forced emoji mode is incorrect"

UI_EMOJI_ENABLED=1 UI_UNICODE_ENABLED=1
for BEDOLAGA_UI_WIDTH in 20 32 40 80; do
  ui_refresh_geometry
  emoji_rows="$({
    ui_banner 'Bot + Cabinet · управление'
    ui_menu_item 1 restart 'Перезапустить выбранный сервис'
    ui_key_value globe 'Адрес' 'https://cabinet.long-example-domain.example.com'
    ui_service_row bot running/healthy
    ui_hint 'Проверьте состояние сервисов'
  })"
  while IFS= read -r line; do
    # All built-in emoji icons occupy two cells, including variation selectors.
    for icon_name in brand restart globe healthy lightbulb; do
      glyph="$(ui_icon "$icon_name")"
      line="${line//$glyph/xx}"
    done
    ((${#line} <= UI_WIDTH)) || fail "emoji line exceeds $UI_WIDTH cells: $line"
  done <<<"$emoji_rows"
done

# Styling must not rely solely on colour, and dangerous labels must be red.
C_RED=$'\033[31m' C_YELLOW=$'\033[33m' C_RESET=$'\033[0m'
coloured="$(ui_danger_item 3 rollback 'Восстановить из архива')"
[[ "$coloured" == *"${C_RED}Восстановить"* ]] || fail 'dangerous label is not red'
coloured="$(warn 'Предупреждение' 2>&1)"
[[ "$coloured" == *"$C_YELLOW"* && "$coloured" == *'Предупреждение'* ]] || fail 'warning colour or text missing'

printf 'UI tests passed.\n'
