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
source "$PROJECT_ROOT/lib/system.sh"

check_supported_os
check_architecture
ensure_runtime_dirs
[[ -d "$CONFIG_ROOT" && -d "$STATE_ROOT" ]]
[[ "$(stat -c '%a' "$CONFIG_ROOT")" == 700 ]]
printf 'Platform test passed: %s (%s)\n' "$OS_PRETTY" "$(uname -m)"
