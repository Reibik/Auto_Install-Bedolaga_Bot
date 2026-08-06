#!/usr/bin/env bash

xray_resource_preflight() {
  local memory_swap_mb disk_mb
  memory_swap_mb="$(awk '/^(MemTotal|SwapTotal):/ {total += $2} END {print int(total / 1024)}' /proc/meminfo)"
  disk_mb="$(df -Pm "$INSTALL_ROOT" 2>/dev/null | awk 'NR==2 {print $4}' || true)"
  [[ -n "$disk_mb" ]] || disk_mb="$(df -Pm / | awk 'NR==2 {print $4}')"
  if ((memory_swap_mb < 1024)); then
    warn "Для сборки Status Page доступно меньше 1 GB RAM + swap (${memory_swap_mb} MB)."
    confirm "Продолжить? Сборка может завершиться из-за нехватки памяти." || die "Установка Xray Monitoring отменена."
  fi
  ((disk_mb >= 2048)) || die "Для Xray Monitoring требуется минимум 2 GB свободного диска."
}

prepare_xray_status_source() {
  local ref="${XRAY_STATUS_REF:-go-build}"
  local origin_url
  mkdir -p "$SOURCE_ROOT"
  if [[ -d "$XRAY_STATUS_SOURCE_DIR/.git" ]]; then
    origin_url="$(git -C "$XRAY_STATUS_SOURCE_DIR" remote get-url origin 2>/dev/null || true)"
    [[ "$origin_url" == "$XRAY_STATUS_REPOSITORY" ]] || \
      die "Origin Xray Status Page не совпадает с управляемым upstream: $origin_url"
    success "Xray Status Page уже загружен: $(git_short_commit "$XRAY_STATUS_SOURCE_DIR")"
    return 0
  fi
  if [[ -e "$XRAY_STATUS_SOURCE_DIR" ]] && [[ -n "$(find "$XRAY_STATUS_SOURCE_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    die "$XRAY_STATUS_SOURCE_DIR существует и не является управляемым Git-репозиторием."
  fi
  rmdir "$XRAY_STATUS_SOURCE_DIR" 2>/dev/null || true
  info "Клонирую Xray Status Page (ветка $ref)."
  git clone --filter=blob:none --single-branch --branch "$ref" "$XRAY_STATUS_REPOSITORY" "$XRAY_STATUS_SOURCE_DIR"
  git -C "$XRAY_STATUS_SOURCE_DIR" checkout --quiet --detach HEAD
  dotenv_set "$STACK_ENV" XRAY_STATUS_VERSION "go-build-$(git_short_commit "$XRAY_STATUS_SOURCE_DIR")"
}

xray_configuration_wizard() {
  local reuse_input_mode="${1:-}"
  local current domain subscription interval title status_token='' status_admin_ids main_token status_username

  [[ -f "$STACK_ENV" && -f "$BOT_ENV" ]] || die "Сначала установите основной стек: bedolaga install"
  [[ "$reuse_input_mode" == --reuse-input-mode ]] || configure_secret_input_mode
  load_stack_env || die "Не удалось загрузить $STACK_ENV"

  printf '\n'
  ui_banner 'Xray Checker + Status Page'
  ui_section 'Опциональный мониторинг серверов'
  ui_hint 'Нужен отдельный домен. Технические порты останутся внутри Docker-сети.'

  current="$(dotenv_get "$STACK_ENV" XRAY_STATUS_DOMAIN 2>/dev/null || true)"
  [[ -n "$current" ]] || current="status.${CABINET_DOMAIN}"
  prompt_value domain "Домен Status Page, без https://" "$current" validate_domain
  [[ "$domain" != "$WEBHOOK_DOMAIN" && "$domain" != "$CABINET_DOMAIN" ]] || \
    die "Status Page, Webhook и Cabinet должны использовать разные домены."

  current="$(dotenv_get "$STACK_ENV" XRAY_SUBSCRIPTION_URL 2>/dev/null || true)"
  prompt_value subscription "URL подписки (несколько — через запятую)" "$current" validate_https_url_list 1
  current="$(dotenv_get "$STACK_ENV" XRAY_CHECK_INTERVAL 2>/dev/null || printf '300')"
  prompt_value interval "Интервал проверки, секунд (30–86400)" "$current" validate_check_interval
  current="$(dotenv_get "$STACK_ENV" XRAY_STATUS_TITLE 2>/dev/null || true)"
  [[ -n "$current" ]] || current="${VITE_APP_NAME:-VPN} — статус серверов"
  prompt_value title "Заголовок Status Page" "$current" validate_app_name

  status_token="$(dotenv_get "$STACK_ENV" XRAY_STATUS_BOT_TOKEN 2>/dev/null || true)"
  if [[ -n "$status_token" ]]; then
    if confirm "Изменить токен отдельного Telegram-бота Status Page?"; then
      prompt_value status_token "Status Page Bot Token" '' validate_bot_token 1
    fi
  elif confirm "Подключить отдельного Telegram-бота для управления Status Page?"; then
    prompt_value status_token "Status Page Bot Token" '' validate_bot_token 1
  fi

  main_token="$(dotenv_get "$BOT_ENV" BOT_TOKEN 2>/dev/null || true)"
  [[ -z "$status_token" || "$status_token" != "$main_token" ]] || \
    die "Для Status Page нужен отдельный Bot Token: основной Bot уже использует webhook."
  if [[ -n "$status_token" ]]; then
    status_username="$(verify_telegram_token "$status_token" || true)"
    if [[ -n "$status_username" ]]; then
      success "Status Page Bot Token действителен: @${status_username}"
    else
      warn "Не удалось проверить Status Page Bot Token через Telegram API."
    fi
  fi
  status_admin_ids="$(dotenv_get "$STACK_ENV" XRAY_STATUS_ADMIN_IDS 2>/dev/null || true)"
  [[ -n "$status_admin_ids" ]] || status_admin_ids="$(dotenv_get "$BOT_ENV" ADMIN_IDS 2>/dev/null || true)"
  if [[ -n "$status_token" ]]; then
    current="$status_admin_ids"
    prompt_value status_admin_ids "Telegram ID администраторов Status Page" "$current" validate_admin_ids
  else
    status_admin_ids=''
    info "Status Page будет работать без Telegram-бота; подписка сохранена в защищённом stack.env."
  fi

  dotenv_set "$STACK_ENV" XRAY_MONITORING_ENABLED true
  dotenv_set "$STACK_ENV" XRAY_STATUS_DOMAIN "$domain"
  dotenv_set "$STACK_ENV" XRAY_SUBSCRIPTION_URL "$subscription"
  dotenv_set "$STACK_ENV" XRAY_CHECK_INTERVAL "$interval"
  dotenv_set "$STACK_ENV" XRAY_STATUS_TITLE "$title"
  dotenv_set "$STACK_ENV" XRAY_STATUS_BOT_TOKEN "$status_token"
  dotenv_set "$STACK_ENV" XRAY_STATUS_ADMIN_IDS "$status_admin_ids"
  dotenv_set "$STACK_ENV" XRAY_CHECKER_IMAGE "kutovoys/xray-checker:latest"
  dotenv_set "$STACK_ENV" XRAY_STATUS_SOURCE_DIR "$XRAY_STATUS_SOURCE_DIR"
  dotenv_set "$STACK_ENV" XRAY_STATUS_REF "go-build"
  dotenv_set "$STACK_ENV" XRAY_STATUS_VERSION "go-build"
  chmod 600 "$STACK_ENV"
  render_caddyfile
  validate_configuration || die "Конфигурация Xray Monitoring не прошла проверку."
  success "Xray Monitoring настроен: https://${domain}"
}

xray_offer_during_install() {
  if xray_monitoring_enabled; then
    info "Xray Monitoring уже настроен и останется включённым."
    return 0
  fi
  dotenv_set "$STACK_ENV" XRAY_MONITORING_ENABLED false
  if confirm "Установить дополнительно Xray Checker + Status Page?"; then
    xray_resource_preflight
    xray_configuration_wizard --reuse-input-mode
    prepare_xray_status_source
  else
    render_caddyfile
    info "Xray Monitoring пропущен. Его можно установить позже: bedolaga xray install"
  fi
}

xray_reload_caddy() {
  if compose ps --status running caddy 2>/dev/null | grep -q caddy; then
    compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile
  else
    compose up -d caddy
  fi
}

xray_install() {
  require_root
  with_lock
  xray_resource_preflight
  copy_compose_template
  xray_configuration_wizard
  prepare_xray_status_source
  mkdir -p "$DATA_ROOT/xray-statuspage"
  chmod 700 "$DATA_ROOT/xray-statuspage"

  load_stack_env
  if ! check_domain_dns "$XRAY_STATUS_DOMAIN"; then
    confirm "DNS Status Page ещё не готов. Продолжить запуск?" || {
      success "Настройки сохранены. После настройки DNS выполните: bedolaga xray start"
      return 0
    }
  fi

  info "Загружаю Xray Checker и собираю Status Page из официальной ветки go-build."
  compose pull xray-checker
  compose build xray-statuspage
  compose up -d xray-statuspage xray-checker
  xray_reload_caddy
  if wait_for_services 300 xray-statuspage xray-checker; then
    success "Xray Monitoring установлен: https://${XRAY_STATUS_DOMAIN}"
    ui_hint 'Управление: bedolaga xray status | logs | update'
    return 0
  fi
  error "Xray Monitoring запущен, но не прошёл health checks."
  compose ps xray-statuspage xray-checker || true
  compose logs --tail=120 xray-statuspage xray-checker || true
  return 1
}

xray_start() {
  require_root
  xray_monitoring_enabled || die "Xray Monitoring не настроен. Выполните: bedolaga xray install"
  with_lock
  prepare_xray_status_source
  render_caddyfile
  validate_configuration || die "Конфигурация не прошла проверку."
  compose up -d --build xray-statuspage xray-checker
  xray_reload_caddy
  wait_for_services 300 xray-statuspage xray-checker || die "Сервисы не прошли health checks. Запустите: bedolaga xray logs"
  success "Xray Monitoring запущен."
}

xray_status() {
  require_root
  ui_banner 'Xray Checker + Status Page'
  if ! xray_monitoring_enabled; then
    ui_key_value stopped 'Модуль' 'Не установлен'
    ui_hint 'Установка: bedolaga xray install'
    return 1
  fi
  local failures=0 state service
  load_stack_env
  ui_section 'Состояние сервисов'
  for service in xray-statuspage xray-checker; do
    state="$(service_state "$service" 2>/dev/null || true)"
    ui_service_row "$service" "$state"
    [[ "$state" == running/healthy || "$state" == running/none ]] || ((failures += 1))
  done
  ui_section 'Конфигурация'
  ui_key_value globe 'Status Page' "https://${XRAY_STATUS_DOMAIN}"
  ui_key_value update 'Интервал' "${XRAY_CHECK_INTERVAL} сек."
  ui_key_value package 'Checker image' "$XRAY_CHECKER_IMAGE"
  ui_key_value package 'Status commit' "$(git_short_commit "$XRAY_STATUS_SOURCE_DIR")"
  [[ "$failures" -eq 0 ]]
}

xray_logs() {
  require_root
  xray_monitoring_enabled || die "Xray Monitoring не установлен."
  local target="${1:-all}"
  case "$target" in
    all) compose logs -f --tail=150 xray-statuspage xray-checker ;;
    checker | xray-checker) compose logs -f --tail=150 xray-checker ;;
    status | statuspage | xray-statuspage) compose logs -f --tail=150 xray-statuspage ;;
    *) die "Использование: bedolaga xray logs [all|checker|statuspage]" ;;
  esac
}

xray_update() {
  require_root
  xray_monitoring_enabled || die "Xray Monitoring не установлен."
  with_lock
  load_stack_env
  prepare_xray_status_source
  assert_clean_repo "$XRAY_STATUS_SOURCE_DIR" "Xray Status Page"
  local status_before status_after checker_before backup
  status_before="$(git_commit "$XRAY_STATUS_SOURCE_DIR")"
  status_after="$(remote_commit "$XRAY_STATUS_SOURCE_DIR" "${XRAY_STATUS_REF:-go-build}")"
  checker_before="$(docker image inspect "$XRAY_CHECKER_IMAGE" --format '{{.Id}}' 2>/dev/null || true)"
  backup="$(backup_create preupdate | tail -n 1)"
  info "Проверяю новый образ Xray Checker и commit Status Page."
  compose pull xray-checker
  [[ "$status_before" == "$status_after" ]] || checkout_commit "$XRAY_STATUS_SOURCE_DIR" "$status_after"
  dotenv_set "$STACK_ENV" XRAY_STATUS_VERSION "go-build-${status_after:0:8}"
  load_stack_env
  if ! compose build xray-statuspage; then
    checkout_commit "$XRAY_STATUS_SOURCE_DIR" "$status_before"
    dotenv_set "$STACK_ENV" XRAY_STATUS_VERSION "go-build-${status_before:0:8}"
    load_stack_env
    [[ -z "$checker_before" ]] || docker image tag "$checker_before" "$XRAY_CHECKER_IMAGE"
    error "Status Page не собрался; предыдущий commit восстановлен."
    return 1
  fi
  if compose up -d --force-recreate xray-statuspage xray-checker && \
    wait_for_services 300 xray-statuspage xray-checker; then
    success "Xray Checker и Status Page обновлены (${status_before:0:8} → ${status_after:0:8}) и работают. Бэкап: $backup"
    return 0
  fi
  error "После обновления сервисы не прошли health checks. Возвращаю предыдущую сборку."
  compose logs --tail=120 xray-statuspage xray-checker || true
  checkout_commit "$XRAY_STATUS_SOURCE_DIR" "$status_before"
  dotenv_set "$STACK_ENV" XRAY_STATUS_VERSION "go-build-${status_before:0:8}"
  load_stack_env
  [[ -z "$checker_before" ]] || docker image tag "$checker_before" "$XRAY_CHECKER_IMAGE"
  if ! compose build xray-statuspage || \
    ! compose up -d --force-recreate xray-statuspage xray-checker || \
    ! wait_for_services 300 xray-statuspage xray-checker; then
    warn "Автооткат Xray Monitoring также не прошёл health checks."
  fi
  warn "База Status Page автоматически не откатывалась. Резервная копия перед обновлением: $backup"
  return 1
}

xray_disable_now() {
  local service
  local -a container_ids=()
  for service in xray-checker xray-statuspage; do
    mapfile -t container_ids < <(docker ps -aq \
      --filter label=com.docker.compose.project=bedolaga \
      --filter "label=com.docker.compose.service=${service}")
    [[ "${#container_ids[@]}" -eq 0 ]] || docker container rm -f "${container_ids[@]}"
  done
  dotenv_set "$STACK_ENV" XRAY_MONITORING_ENABLED false
  render_caddyfile
  xray_reload_caddy
}

xray_disable() {
  require_root
  xray_monitoring_enabled || { info "Xray Monitoring уже отключён."; return 0; }
  confirm "Отключить Xray Checker и Status Page, сохранив настройки и данные?" || die "Отменено."
  with_lock
  xray_disable_now
  success "Xray Monitoring отключён. Данные сохранены в $DATA_ROOT/xray-statuspage"
}

xray_remove() {
  require_root
  local mode="${1:-}"
  case "$mode" in '' | --purge-data) ;; *) die "Использование: bedolaga xray remove [--purge-data]" ;; esac
  if [[ "$mode" == --purge-data ]]; then
    confirm_phrase "Будут удалены база Status Page, настройки и сохранённые подписки." "PURGE-XRAY" || die "Отменено."
  else
    confirm "Удалить контейнеры Xray Monitoring, сохранив данные?" || die "Отменено."
  fi
  with_lock
  if xray_monitoring_enabled; then
    xray_disable_now
  fi
  if [[ "$mode" == --purge-data ]]; then
    safe_realpath_child "$DATA_ROOT/xray-statuspage" "$DATA_ROOT" || die "Небезопасный путь данных Xray Monitoring."
    rm -rf -- "$DATA_ROOT/xray-statuspage"
    safe_realpath_child "$XRAY_STATUS_SOURCE_DIR" "$SOURCE_ROOT" || die "Небезопасный путь исходников Xray Status Page."
    rm -rf -- "$XRAY_STATUS_SOURCE_DIR"
    docker image rm bedolaga/xray-checker-statuspage:local >/dev/null 2>&1 || true
    local key
    for key in XRAY_STATUS_DOMAIN XRAY_SUBSCRIPTION_URL XRAY_CHECK_INTERVAL XRAY_STATUS_TITLE \
      XRAY_STATUS_BOT_TOKEN XRAY_STATUS_ADMIN_IDS XRAY_CHECKER_IMAGE XRAY_STATUS_SOURCE_DIR \
      XRAY_STATUS_REF XRAY_STATUS_VERSION; do
      dotenv_unset "$STACK_ENV" "$key"
    done
    success "Xray Monitoring и его постоянные данные удалены."
  else
    success "Контейнеры удалены; настройки и данные сохранены."
  fi
}

xray_menu() {
  local choice=''
  while true; do
    ui_clear
    ui_banner 'Xray Checker + Status Page'
    printf '\n'
    if xray_monitoring_enabled; then
      ui_menu_item 1 status 'Статус'
      ui_menu_item 2 start 'Запустить / применить настройки'
      ui_menu_item 3 logs 'Логи'
      ui_menu_item 4 update 'Обновить образы'
      ui_menu_item 5 config 'Перенастроить'
      ui_menu_item 6 stop 'Отключить с сохранением данных'
      ui_menu_item 7 error 'Удалить полностью'
    else
      ui_menu_item 1 deploy 'Установить модуль'
    fi
    ui_separator
    ui_menu_item 0 exit 'Назад'
    read_tty choice "\n${C_CYAN}Выберите действие › ${C_RESET}"
    if xray_monitoring_enabled; then
      case "$choice" in
        1) xray_status || true ;;
        2) xray_start || true ;;
        3) xray_logs || true ;;
        4) xray_update || true ;;
        5) xray_configuration_wizard || true ;;
        6) xray_disable || true ;;
        7) xray_remove --purge-data || true ;;
        0) return 0 ;;
        *) warn "Неизвестный пункт." ;;
      esac
    else
      case "$choice" in
        1) xray_install || true ;;
        0) return 0 ;;
        *) warn "Неизвестный пункт." ;;
      esac
    fi
    read_tty choice "\n${C_CYAN}Нажмите Enter для продолжения...${C_RESET}"
  done
}

xray_manage() {
  local action="${1:-menu}"
  [[ $# -eq 0 ]] || shift
  case "$action" in
    menu) xray_menu ;;
    install | configure) xray_install "$@" ;;
    start | apply) xray_start ;;
    status) xray_status ;;
    logs) xray_logs "$@" ;;
    update) xray_update ;;
    disable | stop) xray_disable ;;
    remove) xray_remove "$@" ;;
    *) die "Использование: bedolaga xray [install|start|status|logs|update|disable|remove]" ;;
  esac
}
