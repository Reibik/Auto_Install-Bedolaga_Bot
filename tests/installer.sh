#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Exercise the real bootstrap in an isolated directory. Only its fixed /usr/local
# prefix and root check are adapted; downloads and flock are simulated.
# shellcheck disable=SC2016
sed -e "s|/usr/local|$TEST_ROOT/usr/local|g" \
  -e 's/${EUID:-$(id -u)}/0/g' "$PROJECT_ROOT/install.sh" >"$TEST_ROOT/install.sh"
manager_home="$TEST_ROOT/usr/local/lib/bedolaga-manager"
previous="$TEST_ROOT/usr/local/lib/bedolaga-manager.previous"
command_path="$TEST_ROOT/usr/local/bin/bedolaga"
mkdir -p "$TEST_ROOT/usr/local/bin" "$manager_home" "$previous"
printf 'working installation\n' >"$manager_home/marker"
printf 'previous installation\n' >"$previous/marker"

source_root="$TEST_ROOT/fixture/manager"
mkdir -p "$source_root/lib" "$source_root/templates"
cat >"$source_root/bedolaga" <<'EOF'
#!/usr/bin/env bash
printf 'Bedolaga Manager 9.0.0\n'
EOF
cp "$source_root/bedolaga" "$source_root/install.sh"
printf '#!/usr/bin/env bash\n' >"$source_root/lib/common.sh"
cp "$source_root/lib/common.sh" "$source_root/lib/ui.sh"
cp "$source_root/lib/common.sh" "$source_root/lib/xray.sh"
touch "$source_root/templates/compose.yaml" "$source_root/templates/Caddyfile.xray.tmpl"
export TEST_ARCHIVE="$TEST_ROOT/manager.tar.gz"
tar -C "$TEST_ROOT/fixture" -czf "$TEST_ARCHIVE" manager
cp "$TEST_ARCHIVE" "$TEST_ROOT/valid.tar.gz"
export BEDOLAGA_ARCHIVE_SHA256
BEDOLAGA_ARCHIVE_SHA256="$(sha256sum "$TEST_ARCHIVE" | cut -d' ' -f1)"
export BEDOLAGA_MANAGER_HOME="$manager_home" BEDOLAGA_COMMAND_PATH="$command_path"
export BEDOLAGA_EXPECTED_VERSION=9.0.0 BEDOLAGA_NO_WIZARD=1
export TEST_LOCK_FAIL=0

curl() {
  local output=''
  while [[ "$#" -gt 0 ]]; do
    if [[ "$1" == -o ]]; then output="$2"; shift; fi
    shift
  done
  cp "$TEST_ARCHIVE" "$output"
}
flock() { [[ "$TEST_LOCK_FAIL" == 0 ]]; }
export -f curl flock

TEST_LOCK_FAIL=1
! bash "$TEST_ROOT/install.sh" --no-wizard >/dev/null 2>&1 || fail "installer ignored held lock"
[[ -f "$manager_home/marker" && -f "$previous/marker" ]] || fail "lock failure changed installations"
TEST_LOCK_FAIL=0

BEDOLAGA_EXPECTED_VERSION=9.0.1
! bash "$TEST_ROOT/install.sh" --no-wizard >/dev/null 2>&1 || fail "wrong archive version was accepted"
[[ -f "$manager_home/marker" && -f "$previous/marker" ]] || fail "version failure changed installations"
BEDOLAGA_EXPECTED_VERSION=9.0.0

correct_checksum="$BEDOLAGA_ARCHIVE_SHA256"
BEDOLAGA_ARCHIVE_SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
! bash "$TEST_ROOT/install.sh" --no-wizard >/dev/null 2>&1 || fail "corrupt archive checksum was accepted"
[[ -f "$manager_home/marker" && -f "$previous/marker" ]] || fail "checksum failure changed installations"
BEDOLAGA_ARCHIVE_SHA256="$correct_checksum"

# Checking only the entrypoint would miss syntax errors in library files.
printf 'if true; then\n' >"$source_root/lib/xray.sh"
tar -C "$TEST_ROOT/fixture" -czf "$TEST_ARCHIVE" manager
BEDOLAGA_ARCHIVE_SHA256="$(sha256sum "$TEST_ARCHIVE" | cut -d' ' -f1)"
! bash "$TEST_ROOT/install.sh" --no-wizard >/dev/null 2>&1 || fail "library syntax error was accepted"
[[ -f "$manager_home/marker" && -f "$previous/marker" ]] || fail "syntax failure changed installations"
cp "$source_root/lib/common.sh" "$source_root/lib/xray.sh"

# A syntactically valid program that cannot start must never replace Manager.
cp "$source_root/bedolaga" "$TEST_ROOT/valid-bedolaga"
printf '#!/usr/bin/env bash\nexit 1\n' >"$source_root/bedolaga"
tar -C "$TEST_ROOT/fixture" -czf "$TEST_ARCHIVE" manager
BEDOLAGA_ARCHIVE_SHA256="$(sha256sum "$TEST_ARCHIVE" | cut -d' ' -f1)"
! bash "$TEST_ROOT/install.sh" --no-wizard >/dev/null 2>&1 || fail "unbootable Manager was accepted"
[[ -f "$manager_home/marker" && -f "$previous/marker" ]] || fail "startup failure changed installations"
cp "$TEST_ROOT/valid-bedolaga" "$source_root/bedolaga"

tar -C "$TEST_ROOT/fixture" --transform='s|^manager|..|' -czf "$TEST_ARCHIVE" manager
BEDOLAGA_ARCHIVE_SHA256="$(sha256sum "$TEST_ARCHIVE" | cut -d' ' -f1)"
! bash "$TEST_ROOT/install.sh" --no-wizard >/dev/null 2>&1 || fail "archive path traversal was accepted"
[[ -f "$manager_home/marker" && -f "$previous/marker" ]] || fail "unsafe archive changed installations"
cp "$TEST_ROOT/valid.tar.gz" "$TEST_ARCHIVE"
BEDOLAGA_ARCHIVE_SHA256="$correct_checksum"

bash "$TEST_ROOT/install.sh" --no-wizard >/dev/null || fail "valid installer failed"
[[ -f "$previous/marker" && ! -f "$manager_home/marker" ]] || fail "working installation was not preserved as previous"
[[ "$(bash "$command_path" version)" == 'Bedolaga Manager 9.0.0' ]] || fail "command did not run the installed version"
[[ -z "$(find "$TEST_ROOT/usr/local/lib" -maxdepth 1 -name '.bedolaga-manager.new.*' -print -quit)" ]] || fail "staging directory leaked"

printf 'Installer tests passed.\n'
