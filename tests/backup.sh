#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
export BEDOLAGA_INSTALL_ROOT="$TEST_ROOT/opt"
export BEDOLAGA_CONFIG_ROOT="$TEST_ROOT/config"
export BEDOLAGA_DATA_ROOT="$TEST_ROOT/data"
export BEDOLAGA_LIB_ROOT="$PROJECT_ROOT"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/common.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/env.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/backup.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_root() { :; }
with_lock() { :; }
backup_copy_xray_data() { :; }
load_stack_env() { POSTGRES_USER='test'; POSTGRES_DB='test'; }
compose() {
  if [[ "$1" == ps ]]; then
    printf 'postgres\n'
  elif [[ "$1" == exec ]]; then
    [[ "$failure" != dump ]] || return 1
    printf 'fixture database dump\n'
  else
    return 1
  fi
}
cp() { [[ "$failure" != copy ]] || return 1; command cp "$@"; }
tar() { [[ "$failure" != tar ]] || return 1; command tar "$@"; }
sha256sum() { [[ "$failure" != checksum ]] || return 1; command sha256sum "$@"; }

ensure_runtime_dirs
printf 'test\n' >"$STACK_ENV"
mkdir -p "$DATA_ROOT/bot"
printf 'fixture\n' >"$DATA_ROOT/bot/file"

for failure in copy dump tar checksum; do
  # Conditional invocation deliberately disables errexit inside the function.
  if backup_create preupdate >"$TEST_ROOT/output" 2>/dev/null; then
    fail "$failure failure was reported as backup success"
  fi
  if backup_run preupdate >/dev/null 2>&1; then
    fail "backup command ignored $failure failure"
  fi
  [[ ! -s "$TEST_ROOT/output" ]] || fail "failed backup printed an archive path"
  [[ -z "$(find "$BACKUP_ROOT" -type f -print -quit)" ]] || fail "incomplete archive remained after $failure failure"
  [[ -z "$(find "$DATA_ROOT" -maxdepth 1 -name 'backup-stage.*' -print -quit)" ]] || fail "staging remained after $failure failure"
done
failure=none
archive="$(backup_create preupdate)" || fail "valid backup failed"
[[ -s "$archive" && -s "${archive}.sha256" ]] || fail "valid backup files are missing"
(cd "$BACKUP_ROOT" && command sha256sum -c "$(basename "${archive}.sha256")") >/dev/null || fail "checksum does not match"
command tar -tzf "$archive" | grep -q database.dump || fail "database dump is missing"
printf 'Backup tests passed.\n'
