#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

export BEDOLAGA_INSTALL_ROOT="$TEST_ROOT/opt/bedolaga"
export BEDOLAGA_CONFIG_ROOT="$TEST_ROOT/etc/bedolaga"
export BEDOLAGA_DATA_ROOT="$TEST_ROOT/var/lib/bedolaga"
export BEDOLAGA_LIB_ROOT="$PROJECT_ROOT"
test_origin="$TEST_ROOT/status-origin.git"
if command -v cygpath >/dev/null 2>&1; then
  test_origin="$(cygpath -m "$test_origin")"
fi
export XRAY_STATUS_REPOSITORY="$test_origin"

# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/common.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/env.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/update.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/xray.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

origin="$XRAY_STATUS_REPOSITORY"
seed="$TEST_ROOT/status-seed"
managed="$XRAY_STATUS_SOURCE_DIR"
git init --bare -q "$origin"
git init -q -b go-build "$seed"
git -C "$seed" config user.name "Bedolaga Tests"
git -C "$seed" config user.email "tests@example.com"
git -C "$seed" config core.autocrlf false
printf 'v1\n' >"$seed/version.txt"
git -C "$seed" add version.txt
git -C "$seed" commit -qm initial
git -C "$seed" remote add origin "$origin"
git -C "$seed" push -q -u origin go-build
git --git-dir="$origin" symbolic-ref HEAD refs/heads/go-build
mkdir -p "$SOURCE_ROOT"
git -c core.autocrlf=false clone -q --branch go-build --single-branch "$origin" "$managed"
git -C "$managed" checkout -q --detach HEAD

ensure_runtime_dirs
touch "$STACK_ENV"
dotenv_set "$STACK_ENV" XRAY_MONITORING_ENABLED true
dotenv_set "$STACK_ENV" XRAY_STATUS_SOURCE_DIR "$XRAY_STATUS_SOURCE_DIR"
dotenv_set "$STACK_ENV" XRAY_STATUS_REF go-build
dotenv_set "$STACK_ENV" XRAY_STATUS_VERSION go-build-test
dotenv_set "$STACK_ENV" XRAY_CHECKER_IMAGE kutovoys/xray-checker:latest

status_before="$(git -C "$managed" rev-parse HEAD)"
printf 'v2\n' >"$seed/version.txt"
git -C "$seed" commit -qam second
git -C "$seed" push -q

compose_log="$TEST_ROOT/compose.log"
docker_log="$TEST_ROOT/docker.log"
up_calls=0
require_root() { :; }
with_lock() { :; }
wait_for_services() { return 0; }
backup_create() { printf '%s\n' "$TEST_ROOT/preupdate.tar.gz"; }
docker() {
  printf '%s\n' "$*" >>"$docker_log"
  if [[ "$*" == "image inspect kutovoys/xray-checker:latest --format {{.Id}}" ]]; then
    printf 'sha256:checker-old\n'
  fi
}
compose() {
  printf '%s\n' "$*" >>"$compose_log"
  case "$*" in
    'pull xray-checker' | 'build xray-statuspage') return 0 ;;
    'up -d --force-recreate xray-statuspage xray-checker')
      ((up_calls += 1))
      [[ "$up_calls" -gt 1 ]]
      ;;
    'logs --tail=120 xray-statuspage xray-checker') return 0 ;;
    *) fail "unexpected compose call: $*" ;;
  esac
}

if xray_update >/dev/null 2>&1; then
  fail "failed Xray update unexpectedly succeeded"
fi
[[ "$(git -C "$managed" rev-parse HEAD)" == "$status_before" ]] || fail "Status Page commit was not rolled back"
grep -q '^image tag sha256:checker-old kutovoys/xray-checker:latest$' "$docker_log" || fail "Checker image was not rolled back"
[[ "$(grep -c '^build xray-statuspage$' "$compose_log")" -eq 2 ]] || fail "previous Status Page image was not rebuilt"
[[ "$up_calls" -eq 2 ]] || fail "rollback services were not started"

printf 'Xray lifecycle tests passed.\n'
