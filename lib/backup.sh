#!/usr/bin/env bash

backup_archive_name() {
  local kind="$1"
  local timestamp candidate counter=1
  timestamp="$(date '+%Y%m%d_%H%M%S')"
  candidate="$BACKUP_ROOT/bedolaga_${kind}_${timestamp}.tar.gz"
  while [[ -e "$candidate" || -e "${candidate}.sha256" ]]; do
    candidate="$BACKUP_ROOT/bedolaga_${kind}_${timestamp}_${counter}.tar.gz"
    ((counter += 1))
  done
  printf '%s\n' "$candidate"
}

backup_copy_xray_data() {
  local destination="$1" paused=0 copy_ok=1
  [[ -d "$DATA_ROOT/xray-statuspage" ]] || return 0
  if xray_monitoring_enabled && [[ "$(service_state xray-statuspage 2>/dev/null || true)" == running/* ]]; then
    if compose pause xray-checker xray-statuspage >/dev/null; then
      paused=1
    else
      warn "Не удалось приостановить Xray Monitoring; его SQLite-данные пропущены в этом бэкапе."
      return 0
    fi
  fi
  mkdir -p "$destination"
  cp -a "$DATA_ROOT/xray-statuspage/." "$destination/" || copy_ok=0
  if [[ "$paused" -eq 1 ]]; then
    compose unpause xray-statuspage xray-checker >/dev/null 2>&1 || warn "Не удалось снять паузу с Xray Monitoring. Выполните: bedolaga xray start"
  fi
  if [[ "$copy_ok" -eq 0 ]]; then
    rm -rf -- "$destination"
    warn "Не удалось скопировать данные Xray Status Page; они пропущены в этом бэкапе."
  fi
}

backup_create() {
  require_root
  local kind="${1:-manual}"
  local archive staging database_dump='unavailable'
  ensure_runtime_dirs
  staging="$(mktemp -d "${DATA_ROOT}/backup-stage.XXXXXX")"
  archive="$(backup_archive_name "$kind")"
  mkdir -p "$staging/config" "$staging/app-data"

  info "Создаю резервную копию ($kind)."
  if [[ -f "$STACK_ENV" ]]; then
    cp -a "$CONFIG_ROOT/." "$staging/config/"
  fi
  if [[ -d "$DATA_ROOT/bot" ]]; then
    cp -a "$DATA_ROOT/bot/." "$staging/app-data/"
  fi
  backup_copy_xray_data "$staging/xray-data"

  if compose ps --status running postgres 2>/dev/null | grep -q postgres; then
    load_stack_env
    if compose exec -T postgres pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc >"$staging/database.dump"; then
      database_dump='database.dump'
    else
      rm -f "$staging/database.dump"
      [[ "$kind" != preupdate ]] || { rm -rf -- "$staging"; die "Обновление отменено: PostgreSQL dump не создан."; }
      warn "Не удалось создать PostgreSQL dump. Остальные данные будут сохранены."
    fi
  else
    [[ "$kind" != preupdate ]] || { rm -rf -- "$staging"; die "Обновление отменено: PostgreSQL не запущен."; }
    warn "PostgreSQL не запущен — dump базы не создан."
  fi

  touch "$staging/manifest.env"
  dotenv_set "$staging/manifest.env" CREATED_AT "$(date --iso-8601=seconds)"
  dotenv_set "$staging/manifest.env" KIND "$kind"
  dotenv_set "$staging/manifest.env" MANAGER_VERSION "$BEDOLAGA_VERSION"
  dotenv_set "$staging/manifest.env" BOT_COMMIT "$(git_commit "$BOT_SOURCE_DIR")"
  dotenv_set "$staging/manifest.env" CABINET_COMMIT "$(git_commit "$CABINET_SOURCE_DIR")"
  dotenv_set "$staging/manifest.env" XRAY_STATUS_COMMIT "$(git_commit "$XRAY_STATUS_SOURCE_DIR")"
  dotenv_set "$staging/manifest.env" DATABASE_DUMP "$database_dump"

  tar -C "$staging" -czf "$archive" .
  (cd "$BACKUP_ROOT" && sha256sum "$(basename "$archive")" >"$(basename "${archive}.sha256")")
  rm -rf -- "$staging"
  chmod 600 "$archive" "${archive}.sha256"
  success "Бэкап создан: $archive ($(du -h "$archive" | awk '{print $1}'))"
  printf '%s\n' "$archive"
}

backup_run() {
  require_root
  local kind="${1:-manual}"
  with_lock
  backup_create "$kind"
  [[ "$kind" != automatic ]] || backup_rotate
}

backup_rotate() {
  load_stack_env || true
  local retention="${BACKUP_RETENTION:-7}"
  local -a old_backups=()
  mapfile -t old_backups < <(find "$BACKUP_ROOT" -maxdepth 1 -type f -name 'bedolaga_automatic_*.tar.gz' -printf '%T@ %p\n' 2>/dev/null | sort -rn | tail -n "+$((retention + 1))" | cut -d' ' -f2-)
  local archive
  for archive in "${old_backups[@]}"; do
    safe_realpath_under "$archive" "$BACKUP_ROOT" || continue
    rm -f -- "$archive" "${archive}.sha256"
  done
}

backup_list() {
  require_root
  find "$BACKUP_ROOT" -maxdepth 1 -type f -name 'bedolaga_*.tar.gz' -printf '%TY-%Tm-%Td %TH:%TM  %10s  %f\n' 2>/dev/null | sort -r
}

verify_backup_archive() {
  local archive="$1"
  [[ -f "$archive" ]] || die "Бэкап не найден: $archive"
  safe_realpath_under "$archive" "$BACKUP_ROOT" || die "Разрешено восстанавливать только из $BACKUP_ROOT"
  [[ -f "${archive}.sha256" ]] || die "Не найден checksum: ${archive}.sha256"
  (cd "$(dirname "$archive")" && sha256sum -c "$(basename "${archive}.sha256")") || die "Checksum бэкапа не совпадает."
  if tar -tzf "$archive" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
    die "Архив содержит небезопасные пути."
  fi
  tar -tzf "$archive" | grep -qE '(^|\./)manifest\.env$' || die "В архиве нет manifest.env."
}

backup_restore() {
  require_root
  local archive="${1:-}"
  [[ -n "$archive" ]] || die "Укажите архив: bedolaga restore /var/lib/bedolaga/backups/<file>.tar.gz"
  archive="$(readlink -m "$archive")"
  verify_backup_archive "$archive"
  confirm_phrase "Восстановление перезапишет конфигурацию и базу данных." "RESTORE" || die "Отменено."

  with_lock
  backup_create emergency >/dev/null
  local staging
  staging="$(mktemp -d "${DATA_ROOT}/restore-stage.XXXXXX")"
  tar -xzf "$archive" -C "$staging"
  local database_dump bot_commit cabinet_commit xray_status_commit
  database_dump="$(dotenv_get "$staging/manifest.env" DATABASE_DUMP 2>/dev/null || printf 'unavailable')"
  bot_commit="$(dotenv_get "$staging/manifest.env" BOT_COMMIT 2>/dev/null || true)"
  cabinet_commit="$(dotenv_get "$staging/manifest.env" CABINET_COMMIT 2>/dev/null || true)"
  xray_status_commit="$(dotenv_get "$staging/manifest.env" XRAY_STATUS_COMMIT 2>/dev/null || true)"

  info "Останавливаю прикладные сервисы."
  local -a stop_services=(bot cabinet caddy)
  if xray_monitoring_enabled; then
    stop_services+=(xray-checker xray-statuspage)
  fi
  compose stop "${stop_services[@]}"
  if [[ -d "$staging/config" ]]; then
    cp -a "$staging/config/." "$CONFIG_ROOT/"
    chmod 700 "$CONFIG_ROOT"
    find "$CONFIG_ROOT" -maxdepth 1 -type f -exec chmod 600 {} +
  fi
  if [[ -d "$staging/app-data" ]]; then
    mkdir -p "$DATA_ROOT/bot"
    cp -a "$staging/app-data/." "$DATA_ROOT/bot/"
  fi
  if [[ -d "$staging/xray-data" ]]; then
    mkdir -p "$DATA_ROOT/xray-statuspage"
    cp -a "$staging/xray-data/." "$DATA_ROOT/xray-statuspage/"
  fi
  load_stack_env
  if xray_monitoring_enabled; then
    prepare_xray_status_source
  fi
  compose up -d postgres redis
  local started
  started="$(date +%s)"
  until [[ "$(service_state postgres 2>/dev/null || true)" == running/healthy ]]; do
    (( $(date +%s) - started < 120 )) || die "PostgreSQL не готов к восстановлению."
    sleep 3
  done
  if [[ "$database_dump" == database.dump && -f "$staging/database.dump" ]]; then
    info "Восстанавливаю PostgreSQL."
    compose exec -T postgres pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner <"$staging/database.dump"
    compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v "new_password=$POSTGRES_PASSWORD" \
      -c "ALTER ROLE remnawave_user WITH PASSWORD :'new_password';"
  fi
  if [[ "$bot_commit" =~ ^[0-9a-f]{40}$ ]] && [[ -z "$(git -C "$BOT_SOURCE_DIR" status --porcelain)" ]]; then
    git -C "$BOT_SOURCE_DIR" fetch --quiet origin "$bot_commit" || true
    git -C "$BOT_SOURCE_DIR" cat-file -e "${bot_commit}^{commit}" 2>/dev/null && checkout_commit "$BOT_SOURCE_DIR" "$bot_commit"
  fi
  if [[ "$cabinet_commit" =~ ^[0-9a-f]{40}$ ]] && [[ -z "$(git -C "$CABINET_SOURCE_DIR" status --porcelain)" ]]; then
    git -C "$CABINET_SOURCE_DIR" fetch --quiet origin "$cabinet_commit" || true
    git -C "$CABINET_SOURCE_DIR" cat-file -e "${cabinet_commit}^{commit}" 2>/dev/null && checkout_commit "$CABINET_SOURCE_DIR" "$cabinet_commit"
  fi
  if [[ "$xray_status_commit" =~ ^[0-9a-f]{40}$ && -d "$XRAY_STATUS_SOURCE_DIR/.git" ]] && \
    [[ -z "$(git -C "$XRAY_STATUS_SOURCE_DIR" status --porcelain)" ]]; then
    git -C "$XRAY_STATUS_SOURCE_DIR" fetch --quiet origin "$xray_status_commit" || true
    git -C "$XRAY_STATUS_SOURCE_DIR" cat-file -e "${xray_status_commit}^{commit}" 2>/dev/null && \
      checkout_commit "$XRAY_STATUS_SOURCE_DIR" "$xray_status_commit"
  fi
  rm -rf -- "$staging"
  compose up -d --build
  wait_for_health 300 || die "Восстановление завершено, но health checks не пройдены. Запустите bedolaga doctor."
  success "Восстановление завершено."
}

backup_schedule() {
  require_root
  local action="${1:-status}"
  case "$action" in
    enable)
      install -m 644 "$(template_dir)/bedolaga-backup.service" /etc/systemd/system/bedolaga-backup.service
      install -m 644 "$(template_dir)/bedolaga-backup.timer" /etc/systemd/system/bedolaga-backup.timer
      systemctl daemon-reload
      systemctl enable --now bedolaga-backup.timer
      success "Ежедневный бэкап включён (около 03:00)."
      ;;
    disable)
      systemctl disable --now bedolaga-backup.timer
      success "Автоматический бэкап отключён."
      ;;
    status) systemctl status bedolaga-backup.timer --no-pager ;;
    *) die "Использование: bedolaga schedule [enable|disable|status]" ;;
  esac
}
