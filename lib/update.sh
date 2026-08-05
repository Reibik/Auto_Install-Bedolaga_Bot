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
  git -C "$directory" fetch --quiet origin "$ref"
  git -C "$directory" rev-parse "origin/$ref"
}

write_update_state() {
  local bot_before="$1" cabinet_before="$2" bot_after="$3" cabinet_after="$4" backup="$5"
  mkdir -p "$STATE_ROOT"
  {
    printf 'UPDATED_AT=%q\n' "$(date --iso-8601=seconds)"
    printf 'BOT_BEFORE=%q\n' "$bot_before"
    printf 'CABINET_BEFORE=%q\n' "$cabinet_before"
    printf 'BOT_AFTER=%q\n' "$bot_after"
    printf 'CABINET_AFTER=%q\n' "$cabinet_after"
    printf 'BACKUP=%q\n' "$backup"
  } >"$UPDATE_STATE"
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
  checkout_commit "$BOT_SOURCE_DIR" "$bot_commit"
  checkout_commit "$CABINET_SOURCE_DIR" "$cabinet_commit"
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
  load_stack_env
  assert_clean_repo "$BOT_SOURCE_DIR" "Bot"
  assert_clean_repo "$CABINET_SOURCE_DIR" "Cabinet"

  local bot_before cabinet_before bot_after cabinet_after backup
  bot_before="$(git_commit "$BOT_SOURCE_DIR")"
  cabinet_before="$(git_commit "$CABINET_SOURCE_DIR")"
  bot_after="$bot_before"
  cabinet_after="$cabinet_before"
  [[ "$component" == all || "$component" == bot ]] && bot_after="$(remote_commit "$BOT_SOURCE_DIR" "${BOT_REF:-main}")"
  [[ "$component" == all || "$component" == cabinet ]] && cabinet_after="$(remote_commit "$CABINET_SOURCE_DIR" "${CABINET_REF:-main}")"

  if [[ "$bot_before" == "$bot_after" && "$cabinet_before" == "$cabinet_after" ]]; then
    success "Уже установлены актуальные версии."
    return 0
  fi

  backup="$(backup_create preupdate | tail -n 1)"
  write_update_state "$bot_before" "$cabinet_before" "$bot_after" "$cabinet_after" "$backup"
  info "Обновляю исходники в detached режиме."
  [[ "$bot_before" == "$bot_after" ]] || checkout_commit "$BOT_SOURCE_DIR" "$bot_after"
  [[ "$cabinet_before" == "$cabinet_after" ]] || checkout_commit "$CABINET_SOURCE_DIR" "$cabinet_after"
  dotenv_merge_missing "$BOT_ENV" "$BOT_SOURCE_DIR/.env.example"
  sanitize_bot_env
  sync_bot_assets

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

self_update() {
  require_root
  local installer
  installer="$(mktemp)"
  info "Загружаю актуальный Bedolaga Manager."
  curl -fsSL --retry 3 --connect-timeout 15 \
    "https://raw.githubusercontent.com/${BEDOLAGA_REPOSITORY}/main/install.sh" -o "$installer"
  grep -q '^#!/usr/bin/env bash' "$installer" || { rm -f "$installer"; die "Загружен некорректный install.sh"; }
  chmod 700 "$installer"
  BEDOLAGA_NO_WIZARD=1 bash "$installer"
  rm -f "$installer"
  success "Bedolaga Manager обновлён."
}
