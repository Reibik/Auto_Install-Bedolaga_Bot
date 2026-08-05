#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

export BEDOLAGA_INSTALL_ROOT="$TEST_ROOT/opt/bedolaga"
export BEDOLAGA_CONFIG_ROOT="$TEST_ROOT/etc/bedolaga"
export BEDOLAGA_DATA_ROOT="$TEST_ROOT/var/lib/bedolaga"
export BEDOLAGA_LIB_ROOT="$PROJECT_ROOT"

# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/common.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/env.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/update.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

origin="$TEST_ROOT/origin.git"
seed="$TEST_ROOT/seed"
managed="$TEST_ROOT/managed"
git init --bare -q "$origin"
git init -q -b main "$seed"
git -C "$seed" config user.name "Bedolaga Tests"
git -C "$seed" config user.email "tests@example.com"
git -C "$seed" config core.autocrlf false
printf 'v1\n' >"$seed/version.txt"
git -C "$seed" add version.txt
git -C "$seed" commit -qm initial
git -C "$seed" remote add origin "$origin"
git -C "$seed" push -q -u origin main
git --git-dir="$origin" symbolic-ref HEAD refs/heads/main
git -c core.autocrlf=false clone -q "$origin" "$managed"
git -C "$managed" config core.autocrlf false

first="$(git -C "$managed" rev-parse HEAD)"
assert_clean_repo "$managed" Test
[[ "$(remote_commit "$managed" main)" == "$first" ]] || fail "wrong initial remote commit"

printf 'v2\n' >"$seed/version.txt"
git -C "$seed" commit -qam second
git -C "$seed" push -q
second="$(remote_commit "$managed" main)"
[[ "$first" != "$second" ]] || fail "remote update not detected"
checkout_commit "$managed" "$second"
[[ "$(git -C "$managed" rev-parse HEAD)" == "$second" ]] || fail "checkout failed"

printf 'dirty\n' >>"$managed/version.txt"
if (assert_clean_repo "$managed" Test >/dev/null 2>&1); then
  fail "dirty checkout accepted"
fi

# Обновление должно возвращать оба checkout на предыдущие commit, если
# Docker Compose не смог запустить уже собранную новую версию.
bot_managed="$TEST_ROOT/bot-managed"
cabinet_managed="$TEST_ROOT/cabinet-managed"
git -c core.autocrlf=false clone -q "$origin" "$bot_managed"
git -c core.autocrlf=false clone -q "$origin" "$cabinet_managed"
bot_before="$(git -C "$bot_managed" rev-parse HEAD)"
cabinet_before="$(git -C "$cabinet_managed" rev-parse HEAD)"
printf 'v3\n' >"$seed/version.txt"
git -C "$seed" commit -qam third
git -C "$seed" push -q

BOT_SOURCE_DIR="$bot_managed"
CABINET_SOURCE_DIR="$cabinet_managed"
BOT_ENV="$TEST_ROOT/bot.env"
compose_log="$TEST_ROOT/compose.log"
require_root() { :; }
with_lock() { :; }
load_stack_env() { BOT_REF=main; CABINET_REF=main; }
backup_create() { printf '%s\n' "$TEST_ROOT/preupdate.tar.gz"; }
dotenv_merge_missing() { :; }
sanitize_bot_env() { :; }
sync_bot_assets() { :; }
wait_for_health() { return 0; }
compose() {
  printf '%s\n' "$*" >>"$compose_log"
  case "$*" in
    'build bot cabinet') return 0 ;;
    'up -d --remove-orphans') return 1 ;;
    'up -d --build --remove-orphans') return 0 ;;
    *) fail "unexpected compose call: $*" ;;
  esac
}

if update_components all >/dev/null 2>&1; then
  fail "update unexpectedly succeeded after compose up failure"
fi
[[ "$(git -C "$BOT_SOURCE_DIR" rev-parse HEAD)" == "$bot_before" ]] || fail "Bot was not rolled back"
[[ "$(git -C "$CABINET_SOURCE_DIR" rev-parse HEAD)" == "$cabinet_before" ]] || fail "Cabinet was not rolled back"
grep -q '^up -d --build --remove-orphans$' "$compose_log" || fail "previous images were not rebuilt"

printf 'Lifecycle tests passed.\n'
