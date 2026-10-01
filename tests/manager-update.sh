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
        printf '%s\n' "${TEST_RELEASE_URL:-https://github.com/Reibik/Auto_Install-Bedolaga_Bot/releases/tag/v9.0.0}"
        return 0
        ;;
      *'/v9.0.0/CHANGELOG.md')
        cat <<'EOF'
# Changelog

## 9.0.0 — 2026-10-01

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

[[ "$(manager_latest_release_tag)" == v9.0.0 ]] || fail "latest stable release tag was not detected"
TEST_RELEASE_URL='https://example.com/releases/tag/v9.0.0'
! manager_latest_release_tag || fail "redirect to another host was accepted"
TEST_RELEASE_URL='https://github.com/Reibik/Auto_Install-Bedolaga_Bot/releases/tag/v9.0.0-beta'
! manager_latest_release_tag || fail "prerelease tag was accepted"
unset TEST_RELEASE_URL
mapfile -t release_notes < <(manager_release_notes v9.0.0)
[[ "${#release_notes[@]}" -eq 3 ]] || fail "release notes were not limited to three items"
[[ "${release_notes[0]}" == 'Первое понятное изменение.' ]] || fail "first release note is incorrect"
[[ "${release_notes[2]}" == 'Третье понятное изменение.' ]] || fail "third release note is incorrect"

manager_update_check_due || fail "zero interval did not force an update check"
BEDOLAGA_AUTO_UPDATE=0
if manager_update_check_due; then
  fail "BEDOLAGA_AUTO_UPDATE=0 did not disable update checks"
fi
BEDOLAGA_AUTO_UPDATE=1

# Exercise the actual installer path: checksum, environment pinning, cleanup,
# lock failure and installer failure. No system installation is performed.
export TEST_INSTALL_LOG="$TEST_ROOT/installed-release"
export TEST_INSTALL_FAIL=0
lock_log="$TEST_ROOT/locks"
curl_log="$TEST_ROOT/downloads"
flock() { printf '%s\n' "$*" >>"$lock_log"; [[ "${TEST_LOCK_FAIL:-0}" == 0 ]]; }
curl() {
  local output='' url='' argument
  while [[ "$#" -gt 0 ]]; do
    argument="$1"
    shift
    case "$argument" in
      -o) output="$1"; shift ;;
      https://*) url="$argument" ;;
    esac
  done
  printf '%s\n' "$url" >>"$curl_log"
  case "$url" in
    *'/v9.0.0/install.sh')
      cat >"$output" <<'EOF'
#!/usr/bin/env bash
[[ "$BEDOLAGA_REF" == v9.0.0 && "$BEDOLAGA_EXPECTED_VERSION" == 9.0.0 ]] || exit 1
[[ "$BEDOLAGA_ARCHIVE_URL" == https://github.com/Reibik/Auto_Install-Bedolaga_Bot/releases/download/v9.0.0/bedolaga-manager-v9.0.0.tar.gz ]] || exit 1
[[ "$BEDOLAGA_ARCHIVE_SHA256" == aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ]] || exit 1
[[ "$BEDOLAGA_NO_WIZARD" == 1 && "$1" == --no-wizard ]] || exit 1
[[ "$TEST_INSTALL_FAIL" == 0 ]] || exit 1
printf '%s\n' "$BEDOLAGA_REF" >"$TEST_INSTALL_LOG"
EOF
      ;;
    *'.sha256')
      printf '%s\n' "${TEST_CHECKSUM:-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  bedolaga-manager-v9.0.0.tar.gz}" >"$output"
      ;;
    *) return 1 ;;
  esac
}
export BEDOLAGA_ARCHIVE_URL='https://example.com/wrong.tar.gz'
export BEDOLAGA_ARCHIVE_SHA256='invalid'
manager_install_release v9.0.0 >/dev/null || fail "valid release installation failed"
[[ "$(cat "$TEST_INSTALL_LOG")" == v9.0.0 ]] || fail "installer did not receive the pinned tag"
[[ "$(wc -l <"$lock_log")" -eq 1 ]] || fail "installation did not acquire a lock"
rm -f "$TEST_INSTALL_LOG"
TEST_CHECKSUM='invalid'
! manager_install_release v9.0.0 >/dev/null 2>&1 || fail "invalid checksum accepted"
[[ ! -e "$TEST_INSTALL_LOG" ]] || fail "installer ran without a valid checksum"
unset TEST_CHECKSUM
TEST_INSTALL_FAIL=1
! manager_install_release v9.0.0 >/dev/null 2>&1 || fail "installer failure was ignored"
TEST_INSTALL_FAIL=0
TEST_LOCK_FAIL=1
before_downloads="$(wc -l <"$curl_log")"
! manager_install_release v9.0.0 >/dev/null 2>&1 || fail "update proceeded while locked"
[[ "$(wc -l <"$curl_log")" -eq "$before_downloads" ]] || fail "locked update started a download"
unset TEST_LOCK_FAIL

notice_file="$TEST_ROOT/notice"
install_file="$TEST_ROOT/install"
ui_manager_update() {
  printf '%s\n' "$@" >"$notice_file"
}
manager_install_release() {
  printf '%s\n' "$1" >"$install_file"
}
manager_latest_release_tag() { printf '%s\n' v9.0.0; }
manager_release_notes() { printf '%s\n' 'Regression test notes'; }

update_status=0
manager_auto_update || update_status=$?
[[ "$update_status" -eq 10 ]] || fail "automatic update did not signal a process restart"
[[ "$(cat "$install_file")" == v9.0.0 ]] || fail "automatic update selected the wrong tag"
grep -q "^${BEDOLAGA_VERSION}$" "$notice_file" || fail "current version is missing from update notice"
grep -q '^9.0.0$' "$notice_file" || fail "new version is missing from update notice"
[[ "$(cat "$MANAGER_UPDATE_CHECK_STATE")" == v9.0.0 ]] || fail "update check state was not recorded"

BEDOLAGA_UPDATE_CHECK_INTERVAL=003600
! manager_update_check_due || fail "recent check did not suppress network access"
BEDOLAGA_SKIP_UPDATE_CHECK=1
! manager_update_check_due || fail "restart check suppression failed"
unset BEDOLAGA_SKIP_UPDATE_CHECK
BEDOLAGA_UPDATE_CHECK_INTERVAL=0
manager_latest_release_tag() { return 1; }
manager_auto_update >/dev/null 2>&1 || fail "network failure blocked startup"
[[ "$(cat "$MANAGER_UPDATE_CHECK_STATE")" == unavailable ]] || fail "failed check was not cached"
manager_latest_release_tag() { printf 'v9.0.0\n'; }
manager_install_release() { return 1; }
require_root() { :; }
! self_update v9.0.0 >/dev/null 2>&1 || fail "manual update ignored installation failure"
[[ "$(cat "$MANAGER_UPDATE_CHECK_STATE")" == unavailable ]] || fail "failed installation was marked successful"

printf 'Manager update tests passed.\n'
