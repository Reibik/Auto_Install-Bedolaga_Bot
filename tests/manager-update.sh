#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

export BEDOLAGA_INSTALL_ROOT="$TEST_ROOT/opt/bedolaga"
export BEDOLAGA_CONFIG_ROOT="$TEST_ROOT/etc/bedolaga"
export BEDOLAGA_DATA_ROOT="$TEST_ROOT/var/lib/bedolaga"
export BEDOLAGA_LIB_ROOT="$PROJECT_ROOT"
export BEDOLAGA_UPDATE_CHECK_INTERVAL=0
export NO_COLOR=1
export BEDOLAGA_EMOJI=0
export LANG=C

# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/common.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/ui.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/env.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/update.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

manager_version_is_newer 1.10.0 1.9.0 || fail "semantic minor version comparison failed"
manager_version_is_newer 2.0.0 1.99.99 || fail "semantic major version comparison failed"
! manager_version_is_newer 1.3.0 1.3.0 || fail "equal version was treated as newer"
! manager_version_is_newer 1.2.9 1.3.0 || fail "older version was treated as newer"
! manager_version_is_newer latest 1.3.0 || fail "invalid version was accepted"

curl() {
  local argument
  for argument in "$@"; do
    case "$argument" in
      *'/releases/latest')
        printf '%s\n' 'https://github.com/Reibik/Auto_Install-Bedolaga_Bot/releases/tag/v1.3.1'
        return 0
        ;;
      *'/v1.3.1/CHANGELOG.md')
        cat <<'EOF'
# Changelog

## 1.3.1 — 2026-08-07

- Первое понятное изменение.
- Второе понятное изменение.
- Третье понятное изменение.
- Этот пункт не должен отображаться.

## 1.3.0 — 2026-08-07

- Предыдущая версия.
EOF
        return 0
        ;;
    esac
  done
  return 1
}

[[ "$(manager_latest_release_tag)" == v1.3.1 ]] || fail "latest stable release tag was not detected"
mapfile -t release_notes < <(manager_release_notes v1.3.1)
[[ "${#release_notes[@]}" -eq 3 ]] || fail "release notes were not limited to three items"
[[ "${release_notes[0]}" == 'Первое понятное изменение.' ]] || fail "first release note is incorrect"
[[ "${release_notes[2]}" == 'Третье понятное изменение.' ]] || fail "third release note is incorrect"

manager_update_check_due || fail "zero interval did not force an update check"
BEDOLAGA_AUTO_UPDATE=0
if manager_update_check_due; then
  fail "BEDOLAGA_AUTO_UPDATE=0 did not disable update checks"
fi
BEDOLAGA_AUTO_UPDATE=1

notice_file="$TEST_ROOT/notice"
install_file="$TEST_ROOT/install"
ui_manager_update() {
  printf '%s\n' "$@" >"$notice_file"
}
manager_install_release() {
  printf '%s\n' "$1" >"$install_file"
}

update_status=0
manager_auto_update || update_status=$?
[[ "$update_status" -eq 10 ]] || fail "automatic update did not signal a process restart"
[[ "$(cat "$install_file")" == v1.3.1 ]] || fail "automatic update selected the wrong tag"
grep -q '^1.3.0$' "$notice_file" || fail "current version is missing from update notice"
grep -q '^1.3.1$' "$notice_file" || fail "new version is missing from update notice"
[[ "$(cat "$MANAGER_UPDATE_CHECK_STATE")" == v1.3.1 ]] || fail "update check state was not recorded"

printf 'Manager update tests passed.\n'
