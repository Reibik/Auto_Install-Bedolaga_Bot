#!/usr/bin/env bash

dotenv_get() {
  local file="$1"
  local key="$2"
  [[ -f "$file" ]] || return 1
  local line
  line="$(grep -E "^${key}=" "$file" | tail -n 1 || true)"
  [[ -n "$line" ]] || return 1
  line="${line#*=}"
  if [[ "$line" == \"*\" && "$line" == *\" ]]; then
    line="${line:1:${#line}-2}"
    line="${line//\\\"/\"}"
    line="${line//\\\\/\\}"
  elif [[ "$line" == \'*\' && "$line" == *\' ]]; then
    line="${line:1:${#line}-2}"
  fi
  printf '%s\n' "$line"
}

dotenv_escape() {
  local value="$1"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || return 1
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

dotenv_set() {
  local file="$1"
  local key="$2"
  local value="$3"
  [[ "$key" =~ ^[A-Z][A-Z0-9_]*$ ]] || die "Некорректное имя переменной: $key"
  local escaped temporary found=0 line
  escaped="$(dotenv_escape "$value")" || die "Значение $key содержит перевод строки."
  mkdir -p "$(dirname "$file")"
  temporary="$(mktemp "${file}.XXXXXX")"
  if [[ -f "$file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" == "$key="* ]]; then
        if [[ "$found" -eq 0 ]]; then
          printf '%s=%s\n' "$key" "$escaped" >>"$temporary"
          found=1
        fi
      else
        printf '%s\n' "$line" >>"$temporary"
      fi
    done <"$file"
  fi
  if [[ "$found" -eq 0 ]]; then
    printf '%s=%s\n' "$key" "$escaped" >>"$temporary"
  fi
  chmod 600 "$temporary"
  mv -f "$temporary" "$file"
}

dotenv_unset() {
  local file="$1"
  local key="$2"
  [[ -f "$file" ]] || return 0
  [[ "$key" =~ ^[A-Z][A-Z0-9_]*$ ]] || die "Некорректное имя переменной: $key"
  local temporary line
  temporary="$(mktemp "${file}.XXXXXX")"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == "$key="* ]] || printf '%s\n' "$line" >>"$temporary"
  done <"$file"
  chmod 600 "$temporary"
  mv -f "$temporary" "$file"
}

dotenv_require() {
  local file="$1"
  shift
  local key value failed=0
  for key in "$@"; do
    value="$(dotenv_get "$file" "$key" 2>/dev/null || true)"
    if [[ -z "$value" ]]; then
      error "Не заполнена переменная $key в $file"
      failed=1
    fi
  done
  return "$failed"
}

dotenv_merge_missing() {
  local target="$1"
  local defaults="$2"
  [[ -f "$defaults" ]] || return 0
  # Редакторы и сторонние генераторы могут сохранить .env без завершающего LF.
  # Перед добавлением первой новой переменной отделяем её от последней строки.
  if [[ -s "$target" && -n "$(tail -c 1 "$target")" ]]; then
    printf '\n' >>"$target"
  fi
  local line key
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[A-Z][A-Z0-9_]*= ]] || continue
    key="${line%%=*}"
    if ! grep -qE "^${key}=" "$target" 2>/dev/null; then
      printf '%s\n' "$line" >>"$target"
    fi
  done <"$defaults"
  chmod 600 "$target"
}

redacted_env() {
  local file="$1"
  sed -E 's/^([A-Z0-9_]*(TOKEN|SECRET|PASSWORD|API_KEY)[A-Z0-9_]*)=.*/\1="***"/' "$file"
}
