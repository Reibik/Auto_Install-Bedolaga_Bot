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

printf 'Lifecycle tests passed.\n'
