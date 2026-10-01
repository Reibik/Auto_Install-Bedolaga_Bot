#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
export BEDOLAGA_INSTALL_ROOT="$TEST_ROOT/opt"
export BEDOLAGA_CONFIG_ROOT="$TEST_ROOT/config"
export BEDOLAGA_DATA_ROOT="$TEST_ROOT/data"
export NO_COLOR=1 BEDOLAGA_EMOJI=0 LANG=C.UTF-8 BEDOLAGA_UI_WIDTH=80
# Sourcing the CLI loads functions only, never starts a menu or an update.
# shellcheck disable=SC1091
source "$PROJECT_ROOT/bedolaga"
trap - ERR
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_root() { :; }

TEST_PS_FAIL=0 TEST_INSPECT_FAIL=0 TEST_CONTAINER_ID=fixture
compose() {
  [[ "$*" == 'ps -a -q bot' ]] || fail 'unexpected compose call'
  [[ "$TEST_PS_FAIL" == 0 ]] || return 1
  printf '%s' "$TEST_CONTAINER_ID"
}
docker() {
  [[ "$1" == inspect ]] || fail 'unexpected docker call'
  [[ "$TEST_INSPECT_FAIL" == 0 ]] || return 1
  printf '%s\n' "$TEST_DOCKER_STATE"
}
for TEST_DOCKER_STATE in running/healthy/0 running/none/0 exited/0/0 exited/none/137 paused/healthy/0 restarting/none/1; do
  actual="$(service_state bot || true)"
  case "$TEST_DOCKER_STATE" in
    exited/*) expected="exited/${TEST_DOCKER_STATE##*/}" ;;
    *) expected="${TEST_DOCKER_STATE%/*}" ;;
  esac
  [[ "$actual" == "$expected" ]] || fail "unexpected service state: $actual"
done
TEST_PS_FAIL=1
[[ "$(service_state bot || true)" == unavailable/unknown ]] || fail 'docker failure was shown as missing container'
TEST_PS_FAIL=0 TEST_INSPECT_FAIL=1
[[ "$(service_state bot || true)" == unavailable/unknown ]] || fail 'inspect failure was ignored'
TEST_INSPECT_FAIL=0 TEST_CONTAINER_ID=''
[[ "$(service_state bot || true)" == not-created ]] || fail 'missing container state is wrong'

ensure_runtime_dirs
touch "$COMPOSE_FILE" "$STACK_ENV"
TEST_SUMMARY_STATE=running/healthy
TEST_XRAY_ENABLED=0
service_state() { printf '%s\n' "$TEST_SUMMARY_STATE"; }
xray_monitoring_enabled() { [[ "$TEST_XRAY_ENABLED" == 1 ]]; }
summary="$(menu_summary)"
grep -q 'Все сервисы работают' <<<"$summary" || fail 'healthy summary missing'
grep -q 'Bot: Работает' <<<"$summary" || fail 'Bot status missing'
grep -q 'Xray: Не включён' <<<"$summary" || fail 'disabled Xray missing'
TEST_SUMMARY_STATE=running/unhealthy
summary="$(menu_summary)"
grep -q 'Требуют внимания' <<<"$summary" || fail 'unhealthy summary missing'
[[ "$summary" != *'Остановлен / не запущен'* ]] || fail 'unhealthy stack was called stopped'
TEST_SUMMARY_STATE=exited/0
grep -q 'Остановлен / не запущен' <<<"$(menu_summary)" || fail 'stopped summary missing'
status_output="$(stack_status 2>&1 || true)"
grep -q 'Остановлены: 5' <<<"$status_output" || fail 'normal stops counted as failures'
[[ "$status_output" != *'Требуют внимания сервисов'* ]] || fail 'normal stops shown as container errors'
TEST_SUMMARY_STATE=running/starting
grep -q 'ожидание: 5' <<<"$(menu_summary)" || fail 'starting services not counted'
TEST_SUMMARY_STATE=running/healthy TEST_XRAY_ENABLED=1
grep -q 'Xray: Включён · работает' <<<"$(menu_summary)" || fail 'enabled Xray missing'

printf 'archive\n' >"$BACKUP_ROOT/bedolaga_manual_older.tar.gz"
printf 'checksum\n' >"$BACKUP_ROOT/bedolaga_manual_older.tar.gz.sha256"
touch -d '2026-10-01 01:02:00' "$BACKUP_ROOT/bedolaga_manual_older.tar.gz"
printf 'incomplete\n' >"$BACKUP_ROOT/bedolaga_manual_newer.tar.gz"
touch -d '2026-10-01 02:03:00' "$BACKUP_ROOT/bedolaga_manual_newer.tar.gz"
[[ "$(menu_last_backup)" == '01.10.2026 01:02' ]] || fail 'incomplete backup was displayed as latest'

main_output="$(menu_draw_main)"
[[ "$(grep -cE '\[ [1-6]\]' <<<"$main_output")" == 6 ]] || fail 'main menu must have six categories'
[[ "$(wc -l <<<"$main_output")" -le 22 ]] || fail 'main menu is too tall at 80 columns'

if [[ "${1:-}" == --preview ]]; then
  UI_EMOJI_ENABLED=1 UI_UNICODE_ENABLED=1
  for BEDOLAGA_UI_WIDTH in 80 40; do
    ui_refresh_geometry
    printf '\n--- Preview: %s columns (fixture data) ---\n' "$UI_WIDTH"
    menu_draw_main
  done
  exit 0
fi

TEST_COMMAND_ARGS=()
TEST_CONFIRM=1
TEST_INPUTS=()
TEST_INPUT_INDEX=0
TEST_COMMAND_RESULT=0
menu_command() { TEST_COMMAND_ARGS=("$@"); return "$TEST_COMMAND_RESULT"; }
confirm() { [[ "$TEST_CONFIRM" == 1 ]]; }
read_tty() {
  local input="${TEST_INPUTS[$TEST_INPUT_INDEX]:-}"
  ((TEST_INPUT_INDEX += 1))
  printf -v "$1" '%s' "$input"
}
menu_submenu_action settings 1
[[ "${TEST_COMMAND_ARGS[*]}" == 'config bot' ]] || fail 'Bot settings dispatch wrong'
menu_submenu_action settings 4
[[ "${TEST_COMMAND_ARGS[*]}" == 'config paths' ]] || fail 'config paths dispatch wrong'
menu_submenu_action backups 4
[[ "${TEST_COMMAND_ARGS[*]}" == 'schedule status' ]] || fail 'schedule dispatch wrong'
menu_submenu_action updates 3
[[ "${TEST_COMMAND_ARGS[*]}" == 'update bot' ]] || fail 'Bot update dispatch wrong'
TEST_COMMAND_RESULT=1
if menu_submenu_action settings 5; then
  fail 'failed wizard was reported as success'
fi
[[ "${TEST_COMMAND_ARGS[*]}" == 'config wizard' ]] || fail 'failed wizard applied configuration'
TEST_COMMAND_RESULT=0
TEST_CONFIRM=0 TEST_COMMAND_ARGS=()
menu_submenu_action services 3
[[ "${#TEST_COMMAND_ARGS[@]}" == 0 ]] || fail 'cancelled stop still invoked CLI'
menu_submenu_action settings 6
[[ "${#TEST_COMMAND_ARGS[@]}" == 0 ]] || fail 'cancelled apply still invoked CLI'
TEST_INPUTS=("$BACKUP_ROOT/archive with spaces.tar.gz") TEST_INPUT_INDEX=0
menu_submenu_action backups 3 >/dev/null
[[ "${TEST_COMMAND_ARGS[0]}" == restore && "${#TEST_COMMAND_ARGS[@]}" == 2 && "${TEST_COMMAND_ARGS[1]}" == "${TEST_INPUTS[0]}" ]] || fail 'restore path was split'
TEST_INPUTS=('') TEST_INPUT_INDEX=0
menu_submenu backups >/dev/null
[[ "$TEST_INPUT_INDEX" == 1 ]] || fail 'back navigation requested an extra Enter'
TEST_INPUTS=(1 '' 0) TEST_INPUT_INDEX=0
menu_submenu services >/dev/null
[[ "${TEST_COMMAND_ARGS[*]}" == status && "$TEST_INPUT_INDEX" == 3 ]] || fail 'submenu navigation wrong'
TEST_INPUTS=(b) TEST_INPUT_INDEX=0 TEST_COMMAND_ARGS=()
menu_service_action restart >/dev/null
[[ "${#TEST_COMMAND_ARGS[@]}" == 0 ]] || fail 'cancelled service selection invoked CLI'

printf 'Menu tests passed.\n'
