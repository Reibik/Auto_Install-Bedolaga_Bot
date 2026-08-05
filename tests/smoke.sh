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
source "$PROJECT_ROOT/lib/config.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_equal() { [[ "$1" == "$2" ]] || fail "expected '$2', got '$1'"; }

ensure_runtime_dirs
touch "$STACK_ENV" "$BOT_ENV"
dotenv_set "$STACK_ENV" SIMPLE "value"
dotenv_set "$STACK_ENV" WITH_SPACES "VPN Cabinet"
dotenv_set "$STACK_ENV" WITH_QUOTES 'A "quoted" value'
assert_equal "$(dotenv_get "$STACK_ENV" SIMPLE)" "value"
assert_equal "$(dotenv_get "$STACK_ENV" WITH_SPACES)" "VPN Cabinet"
assert_equal "$(dotenv_get "$STACK_ENV" WITH_QUOTES)" 'A "quoted" value'
payload="\$(touch $TEST_ROOT/must-not-exist)"
dotenv_set "$STACK_ENV" INERT_COMMAND "$payload"
load_stack_env
assert_equal "$INERT_COMMAND" "$payload"
[[ ! -e "$TEST_ROOT/must-not-exist" ]] || fail "stack.env executed shell code"

defaults="$TEST_ROOT/defaults.env"
printf 'SIMPLE=overwritten\nNEW_DEFAULT=added\n' >"$defaults"
dotenv_merge_missing "$STACK_ENV" "$defaults"
assert_equal "$(dotenv_get "$STACK_ENV" SIMPLE)" "value"
assert_equal "$(dotenv_get "$STACK_ENV" NEW_DEFAULT)" "added"

validate_domain "cabinet.example.com" || fail "valid domain rejected"
! validate_domain "https://cabinet.example.com" || fail "invalid domain accepted"
validate_https_url "https://panel.example.com/api" || fail "valid URL rejected"
validate_bot_token "1234567:abcdefghijklmnopqrstuvwxyz_123456" || fail "valid token rejected"
validate_admin_ids "123,456" || fail "valid admin IDs rejected"
! validate_admin_ids "123,abc" || fail "invalid admin IDs accepted"
validate_api_key "abcDEF_123.456-xyz" || fail "valid API key rejected"
# shellcheck disable=SC2016
! validate_api_key '$(unsafe)' || fail "unsafe API key accepted"
validate_app_name "My VPN" || fail "valid app name rejected"
# shellcheck disable=SC2016
! validate_app_name '$(touch /tmp/unsafe)' || fail "unsafe app name accepted"
safe_realpath_under "$DATA_ROOT/backups/test.tar.gz" "$DATA_ROOT" || fail "safe child rejected"
! safe_realpath_under "/etc/passwd" "$DATA_ROOT" || fail "unsafe path accepted"

dotenv_set "$STACK_ENV" ACME_EMAIL "admin@example.com"
dotenv_set "$STACK_ENV" WEBHOOK_DOMAIN "hooks.example.com"
dotenv_set "$STACK_ENV" CABINET_DOMAIN "cabinet.example.com"
render_caddyfile
grep -q 'hooks.example.com' "$CADDY_FILE" || fail "webhook domain not rendered"
grep -q 'cabinet.example.com' "$CADDY_FILE" || fail "cabinet domain not rendered"
! grep -q '@@' "$CADDY_FILE" || fail "template placeholder remains"

printf 'Smoke tests passed.\n'
