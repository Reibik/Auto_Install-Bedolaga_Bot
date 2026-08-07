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
# Переменная раскрывается во вложенном bash, а не в текущем процессе.
# shellcheck disable=SC2016
emoji_output="$(NO_COLOR=1 BEDOLAGA_EMOJI=1 LANG=C.UTF-8 bash -c '
  source "$BEDOLAGA_TEST_PROJECT_ROOT/lib/common.sh"
  source "$BEDOLAGA_TEST_PROJECT_ROOT/lib/ui.sh"
  ui_icon success
')"
[[ "$emoji_output" == '✅' ]] || fail "forced emoji mode is incorrect"

printf 'UI tests passed.\n'
