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
# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/security.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/backup.sh"

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

no_newline="$TEST_ROOT/no-newline.env"
printf 'EXISTING=value' >"$no_newline"
dotenv_merge_missing "$no_newline" "$defaults"
assert_equal "$(dotenv_get "$no_newline" EXISTING)" "value"
assert_equal "$(dotenv_get "$no_newline" NEW_DEFAULT)" "added"

dotenv_set "$BOT_ENV" ADMIN_REPORTS_TOPIC_ID '# ID топика для отчетов'
dotenv_set "$BOT_ENV" MULENPAY_SHOP_ID '<ID магазина>'
dotenv_set "$BOT_ENV" FREEKASSA_SHOP_ID ''
dotenv_set "$BOT_ENV" LOG_ROTATION_TOPIC_ID '-100123'
sanitize_bot_env
! grep -q '^ADMIN_REPORTS_TOPIC_ID=' "$BOT_ENV" || fail "comment placeholder was not removed"
! grep -q '^MULENPAY_SHOP_ID=' "$BOT_ENV" || fail "text placeholder was not removed"
! grep -q '^FREEKASSA_SHOP_ID=' "$BOT_ENV" || fail "empty optional integer was not removed"
assert_equal "$(dotenv_get "$BOT_ENV" LOG_ROTATION_TOPIC_ID)" '-100123'
dotenv_unset "$BOT_ENV" LOG_ROTATION_TOPIC_ID
! grep -q '^LOG_ROTATION_TOPIC_ID=' "$BOT_ENV" || fail "dotenv_unset did not remove key"

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
if [[ -f /usr/share/zoneinfo/UTC ]]; then
  validate_timezone "UTC" || fail "UTC timezone rejected"
fi
# shellcheck disable=SC2016
! validate_app_name '$(touch /tmp/unsafe)' || fail "unsafe app name accepted"

curl_args="$TEST_ROOT/curl-args"
curl_config="$TEST_ROOT/curl-config"
curl() {
  printf '%s\n' "$*" >"$curl_args"
  cat >"$curl_config"
  printf '%s\n' '{"ok":true,"result":{"username":"test_bot"}}'
}
telegram_response="$(telegram_api_request '1234567:abcdefghijklmnopqrstuvwxyz_123456' getMe)"
[[ "$telegram_response" == *'"username":"test_bot"'* ]] || fail "Telegram API response was lost"
! grep -q '1234567:' "$curl_args" || fail "Telegram token leaked into curl arguments"
grep -q '1234567:' "$curl_config" || fail "Telegram request URL was not passed through curl config"
safe_realpath_under "$DATA_ROOT/backups/test.tar.gz" "$DATA_ROOT" || fail "safe child rejected"
! safe_realpath_under "/etc/passwd" "$DATA_ROOT" || fail "unsafe path accepted"

command_exists() {
  [[ "$1" != sshd ]] && command -v "$1" >/dev/null 2>&1
}
SSH_CONNECTION='192.0.2.1 50000 192.0.2.2 2222'
assert_equal "$(detect_ssh_port)" '2222'
SSH_CONNECTION='192.0.2.1 50000 192.0.2.2 70000'
assert_equal "$(detect_ssh_port)" '22'
unset SSH_CONNECTION

first_backup="$(backup_archive_name manual)"
touch "$first_backup"
second_backup="$(backup_archive_name manual)"
[[ "$first_backup" != "$second_backup" ]] || fail "backup name collision was not avoided"

dotenv_set "$STACK_ENV" ACME_EMAIL "admin@example.com"
dotenv_set "$STACK_ENV" WEBHOOK_DOMAIN "hooks.example.com"
dotenv_set "$STACK_ENV" CABINET_DOMAIN "cabinet.example.com"
dotenv_set "$STACK_ENV" VITE_TELEGRAM_BOT_USERNAME "test_bot"
render_caddyfile
grep -q 'hooks.example.com' "$CADDY_FILE" || fail "webhook domain not rendered"
grep -q 'cabinet.example.com' "$CADDY_FILE" || fail "cabinet domain not rendered"
! grep -q '@@' "$CADDY_FILE" || fail "template placeholder remains"
validate_stack_values || fail "valid stack values rejected"
dotenv_set "$STACK_ENV" CABINET_DOMAIN "hooks.example.com"
if validate_stack_values >/dev/null 2>&1; then
  fail "identical webhook and Cabinet domains accepted"
fi
dotenv_set "$STACK_ENV" CABINET_DOMAIN "cabinet.example.com"

dotenv_set "$BOT_ENV" BOT_TOKEN "1234567:abcdefghijklmnopqrstuvwxyz_123456"
dotenv_set "$BOT_ENV" ADMIN_IDS "123,456"
dotenv_set "$BOT_ENV" REMNAWAVE_API_URL "https://panel.example.com"
dotenv_set "$BOT_ENV" REMNAWAVE_API_KEY "abcDEF_123.456-xyz"
validate_bot_values || fail "valid Bot values rejected"
dotenv_set "$BOT_ENV" ADMIN_IDS "123,unsafe"
if validate_bot_values >/dev/null 2>&1; then
  fail "invalid ADMIN_IDS accepted"
fi

# Проверяем передачу введённого значения из функций чтения в переменную вызывающего кода.
# util-linux script создаёт настоящий псевдотерминал, включая скрытый режим read -s.
if command_exists script; then
  export BEDOLAGA_TEST_PROJECT_ROOT="$PROJECT_ROOT"
  tty_probe="$TEST_ROOT/tty-probe.sh"
  cat >"$tty_probe" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
export BEDOLAGA_LIB_ROOT="$BEDOLAGA_TEST_PROJECT_ROOT"
# shellcheck disable=SC1091
source "$BEDOLAGA_TEST_PROJECT_ROOT/lib/common.sh"
value=''
read_tty value ''
printf 'VISIBLE_RESULT=%s\n' "$value"
value=''
read_secret_tty value ''
printf 'SECRET_RESULT=%s\n' "$value"
EOF
  chmod 700 "$tty_probe"
  tty_output="$(printf 'visible-input\nsecret-input\n' | script -qec "bash '$tty_probe'" /dev/null | tr -d '\r')"
  grep -q '^VISIBLE_RESULT=visible-input$' <<<"$tty_output" || fail "read_tty lost caller value"
  grep -q '^SECRET_RESULT=secret-input$' <<<"$tty_output" || fail "read_secret_tty lost caller value"
fi

printf 'Smoke tests passed.\n'
