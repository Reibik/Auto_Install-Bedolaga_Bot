#!/usr/bin/env bash

assert_clean_repo() {
  local directory="$1"
  local title="$2"
  [[ -d "$directory/.git" ]] || die "$title не установлен: $directory"
  if [[ -n "$(git -C "$directory" status --porcelain)" ]]; then
    die "$title содержит локальные изменения. Обновление остановлено, файлы не затронуты."
  fi
}

remote_commit() {
  local directory="$1"
  local ref="$2"
  git -C "$directory" fetch --quiet origin "$ref" || return 1
  git -C "$directory" rev-parse --verify 'FETCH_HEAD^{commit}'
}

write_update_state() {
  local bot_before="$1" cabinet_before="$2" bot_after="$3" cabinet_after="$4" backup="$5"
  mkdir -p "$STATE_ROOT" || return 1
  {
    printf 'UPDATED_AT=%q\n' "$(date --iso-8601=seconds)"
    printf 'BOT_BEFORE=%q\n' "$bot_before"
    printf 'CABINET_BEFORE=%q\n' "$cabinet_before"
    printf 'BOT_AFTER=%q\n' "$bot_after"
    printf 'CABINET_AFTER=%q\n' "$cabinet_after"
    printf 'BACKUP=%q\n' "$backup"
  } >"$UPDATE_STATE" || return 1
  chmod 600 "$UPDATE_STATE"
}

checkout_commit() {
  local directory="$1"
  local commit="$2"
  git -C "$directory" checkout --quiet --detach "$commit"
}

restore_previous_components() {
  local bot_commit="$1"
  local cabinet_commit="$2"
  local backup="$3"
  checkout_commit "$BOT_SOURCE_DIR" "$bot_commit" || return 1
  checkout_commit "$CABINET_SOURCE_DIR" "$cabinet_commit" || return 1
  if compose up -d --build --remove-orphans && wait_for_health 300; then
    warn "Предыдущая версия приложений восстановлена. Бэкап: $backup"
    return 0
  fi
  warn "Автооткат не восстановил здоровье сервисов. Используйте бэкап: $backup"
  return 1
}

update_components() {
  require_root
  local component="${1:-all}"
  case "$component" in all | bot | cabinet) ;; *) die "Использование: bedolaga update [all|bot|cabinet]" ;; esac
  with_lock
  load_stack_env || return 1
  assert_clean_repo "$BOT_SOURCE_DIR" "Bot"
  assert_clean_repo "$CABINET_SOURCE_DIR" "Cabinet"

  local bot_before cabinet_before bot_after cabinet_after backup
  bot_before="$(git_commit "$BOT_SOURCE_DIR")"
  cabinet_before="$(git_commit "$CABINET_SOURCE_DIR")"
  bot_after="$bot_before"
  cabinet_after="$cabinet_before"
  if [[ "$component" == all || "$component" == bot ]]; then
    bot_after="$(remote_commit "$BOT_SOURCE_DIR" "${BOT_REF:-main}")" || return 1
  fi
  if [[ "$component" == all || "$component" == cabinet ]]; then
    cabinet_after="$(remote_commit "$CABINET_SOURCE_DIR" "${CABINET_REF:-main}")" || return 1
  fi

  if [[ "$bot_before" == "$bot_after" && "$cabinet_before" == "$cabinet_after" ]]; then
    success "Уже установлены актуальные версии."
    return 0
  fi

  backup="$(backup_create preupdate | tail -n 1)" || {
    error "Обновление отменено: резервная копия не создана."
    return 1
  }
  [[ -n "$backup" ]] || { error "Обновление отменено: не получен путь резервной копии."; return 1; }
  write_update_state "$bot_before" "$cabinet_before" "$bot_after" "$cabinet_after" "$backup" || return 1
  info "Обновляю исходники в detached режиме."
  if ! { { [[ "$bot_before" == "$bot_after" ]] || checkout_commit "$BOT_SOURCE_DIR" "$bot_after"; } &&
    { [[ "$cabinet_before" == "$cabinet_after" ]] || checkout_commit "$CABINET_SOURCE_DIR" "$cabinet_after"; } &&
    dotenv_merge_missing "$BOT_ENV" "$BOT_SOURCE_DIR/.env.example" && sanitize_bot_env && sync_bot_assets; }; then
    error "Подготовка обновления не удалась. Возвращаю исходники."
    checkout_commit "$BOT_SOURCE_DIR" "$bot_before" || true
    checkout_commit "$CABINET_SOURCE_DIR" "$cabinet_before" || true
    return 1
  fi

  local -a build_services
  if [[ "$component" == all ]]; then
    build_services=(bot cabinet)
  else
    build_services=("$component")
  fi
  if ! compose build "${build_services[@]}"; then
    error "Сборка не удалась. Возвращаю исходники."
    checkout_commit "$BOT_SOURCE_DIR" "$bot_before"
    checkout_commit "$CABINET_SOURCE_DIR" "$cabinet_before"
    return 1
  fi
  if ! compose up -d --remove-orphans; then
    error "Docker Compose не смог запустить обновлённые сервисы. Возвращаю предыдущую версию приложений."
    restore_previous_components "$bot_before" "$cabinet_before" "$backup" || true
    return 1
  fi
  if wait_for_health 300; then
    success "Обновление установлено. Bot ${bot_before:0:8}→${bot_after:0:8}, Cabinet ${cabinet_before:0:8}→${cabinet_after:0:8}."
    return 0
  fi

  error "Health checks не пройдены. Автоматически возвращаю предыдущую версию приложения."
  restore_previous_components "$bot_before" "$cabinet_before" "$backup" || true
  return 1
}

rollback_last_update() {
  require_root
  [[ -f "$UPDATE_STATE" ]] || die "Нет сохранённого состояния обновления."
  confirm "Вернуть предыдущие версии Bot и Cabinet?" || die "Отменено."
  with_lock
  local BOT_BEFORE='' CABINET_BEFORE='' BACKUP=''
  # shellcheck disable=SC1090
  source "$UPDATE_STATE"
  : "${BOT_BEFORE:?}" "${CABINET_BEFORE:?}"
  assert_clean_repo "$BOT_SOURCE_DIR" "Bot"
  assert_clean_repo "$CABINET_SOURCE_DIR" "Cabinet"
  checkout_commit "$BOT_SOURCE_DIR" "$BOT_BEFORE"
  checkout_commit "$CABINET_SOURCE_DIR" "$CABINET_BEFORE"
  compose up -d --build --remove-orphans
  wait_for_health 300 || die "Откат выполнен, но сервисы не прошли health checks. Бэкап перед обновлением: ${BACKUP:-unknown}"
  success "Приложения возвращены на Bot ${BOT_BEFORE:0:8}, Cabinet ${CABINET_BEFORE:0:8}."
  warn "Схема базы данных автоматически не откатывалась. При несовместимости используйте: bedolaga restore ${BACKUP:-<backup>}"
}

manager_latest_release_tag() {
  local final_url tag
  final_url="$(curl -fsSL --retry 1 --connect-timeout 4 --max-time 10 \
    -o /dev/null -w '%{url_effective}' \
    "https://github.com/${BEDOLAGA_REPOSITORY}/releases/latest" 2>/dev/null)" || return 1
  final_url="${final_url%%\?*}"
  [[ "$final_url" == "https://github.com/${BEDOLAGA_REPOSITORY}/releases/tag/"* ]] || return 1
  tag="${final_url##*/}"
  [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  printf '%s\n' "$tag"
}

manager_version_is_newer() {
  local candidate="$1" current="$2" highest
  [[ "$candidate" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  [[ "$current" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  [[ "$candidate" != "$current" ]] || return 1
  highest="$(printf '%s\n%s\n' "$current" "$candidate" | LC_ALL=C sort -V | tail -n 1)"
  [[ "$highest" == "$candidate" ]]
}

manager_release_notes() {
  local tag="$1" version="${1#v}" changelog line note found=0 count=0
  changelog="$(curl -fsSL --retry 1 --connect-timeout 4 --max-time 10 \
    "https://raw.githubusercontent.com/${BEDOLAGA_REPOSITORY}/${tag}/CHANGELOG.md" 2>/dev/null)" || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    if [[ "$found" -eq 0 ]]; then
      if [[ "$line" == "## $version" || "$line" == "## $version "* ]]; then
        found=1
      fi
      continue
    fi
    [[ "$line" == '## '* ]] && break
    [[ "$line" == '- '* ]] || continue
    note="$(printf '%s' "${line#- }" | LC_ALL=C tr -d '\000-\010\013-\037\177')"
    printf '%s\n' "${note:0:180}"
    ((count += 1))
    [[ "$count" -ge 3 ]] && break
  done <<<"$changelog"
  [[ "$count" -gt 0 ]]
}

manager_update_check_due() {
  case "${BEDOLAGA_AUTO_UPDATE:-1}" in
    0 | false | no | off) return 1 ;;
  esac
  [[ "${BEDOLAGA_SKIP_UPDATE_CHECK:-0}" != 1 ]] || return 1
  local interval="${BEDOLAGA_UPDATE_CHECK_INTERVAL:-3600}" now checked_at
  [[ "$interval" =~ ^[0-9]{1,6}$ ]] || interval=3600
  interval=$((10#$interval))
  [[ "$interval" -gt 0 && -f "$MANAGER_UPDATE_CHECK_STATE" ]] || return 0
  checked_at="$(stat -c '%Y' "$MANAGER_UPDATE_CHECK_STATE" 2>/dev/null || printf '0')"
  now="$(date +%s)"
  ((checked_at > now || now - checked_at >= interval))
}

manager_record_update_check() {
  local result="${1:-unknown}"
  ensure_runtime_dirs || return 1
  printf '%s\n' "$result" >"$MANAGER_UPDATE_CHECK_STATE" || return 1
  chmod 600 "$MANAGER_UPDATE_CHECK_STATE"
}

manager_install_release() (
  # Subshell closes the operation lock and temporary files on every return path.
  local tag="$1" installer temporary_root checksum_line checksum archive_name archive_url
  [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { error "Некорректный тег Manager: $tag"; return 1; }
  command_exists flock || { error "Для безопасного обновления нужен flock (util-linux)."; return 1; }
  with_lock
  temporary_root="$(mktemp -d)" || return 1
  trap 'rm -rf -- "$temporary_root"' EXIT
  installer="$temporary_root/install.sh"
  archive_name="bedolaga-manager-${tag}.tar.gz"
  archive_url="https://github.com/${BEDOLAGA_REPOSITORY}/releases/download/${tag}/${archive_name}"
  info "Загружаю и проверяю Bedolaga Manager $tag."
  if ! curl -fsSL --retry 3 --connect-timeout 15 --max-time 60 \
    "https://raw.githubusercontent.com/${BEDOLAGA_REPOSITORY}/${tag}/install.sh" -o "$installer"; then
    error "Не удалось загрузить установщик $tag. Текущая версия не изменена."
    return 1
  fi
  if ! grep -q '^#!/usr/bin/env bash' "$installer" || ! bash -n "$installer"; then
    error "Загружен некорректный install.sh. Текущая версия не изменена."
    return 1
  fi
  if ! curl -fsSL --retry 2 --connect-timeout 10 --max-time 30 \
    "${archive_url}.sha256" -o "$temporary_root/checksum"; then
    error "Не удалось получить SHA-256 релиза. Обновление отменено."
    return 1
  fi
  checksum_line="$(cat "$temporary_root/checksum")"
  if [[ ! "$checksum_line" =~ ^([a-fA-F0-9]{64})[[:blank:]]+\*?([^[:space:]]+)$ ]] ||
    [[ "${BASH_REMATCH[2]}" != "$archive_name" ]]; then
    error "Некорректная контрольная сумма релиза. Обновление отменено."
    return 1
  fi
  checksum="${BASH_REMATCH[1]}"
  if ! BEDOLAGA_REF="$tag" BEDOLAGA_NO_WIZARD=1 \
    BEDOLAGA_ARCHIVE_URL="$archive_url" BEDOLAGA_ARCHIVE_SHA256="$checksum" \
    BEDOLAGA_EXPECTED_VERSION="${tag#v}" bash "$installer" --no-wizard; then
    error "Обновление $tag не установлено. Manager сохранил предыдущую версию."
    return 1
  fi
  success "Bedolaga Manager обновлён: v${BEDOLAGA_VERSION} → ${tag}."
)

manager_show_release() {
  local tag="$1" version="${1#v}"
  local -a notes=()
  mapfile -t notes < <(manager_release_notes "$tag" || true)
  if [[ "${#notes[@]}" -eq 0 ]]; then
    notes=("Улучшения стабильности, интерфейса и управления проектом.")
  fi
  ui_manager_update "$BEDOLAGA_VERSION" "$version" "${notes[@]}"
}

manager_auto_update() {
  manager_update_check_due || return 0
  info "Проверяю стабильные обновления Bedolaga Manager..."
  local tag version
  if ! tag="$(manager_latest_release_tag)"; then
    manager_record_update_check unavailable || true
    warn "Не удалось проверить обновления. Продолжаю запуск текущей версии v${BEDOLAGA_VERSION}."
    return 0
  fi
  version="${tag#v}"
  if ! manager_version_is_newer "$version" "$BEDOLAGA_VERSION"; then
    manager_record_update_check "$tag" || true
    return 0
  fi
  manager_show_release "$tag"
  if manager_install_release "$tag"; then
    manager_record_update_check "$tag" || true
    return 10
  fi
  return 1
}

self_update() {
  require_root
  [[ "$#" -le 1 ]] || die "Использование: bedolaga self-update [vX.Y.Z]"
  local tag="${1:-}" version
  if [[ -z "$tag" ]]; then
    info "Проверяю последний стабильный GitHub Release."
    tag="$(manager_latest_release_tag)" || die "Не удалось определить последнюю стабильную версию."
  fi
  [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Некорректная версия: $tag"
  version="${tag#v}"
  if ! manager_version_is_newer "$version" "$BEDOLAGA_VERSION"; then
    success "Уже установлена актуальная версия Bedolaga Manager v${BEDOLAGA_VERSION}."
    manager_record_update_check "$tag"
    return 0
  fi
  manager_show_release "$tag"
  manager_install_release "$tag" || return 1
  manager_record_update_check "$tag"
}
