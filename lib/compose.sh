#!/usr/bin/env bash

compose_up_or_diagnose() {
  if compose up "$@"; then
    return 0
  fi
  error "Docker Compose не смог запустить стек. Статусы и последние логи:"
  compose ps || true
  compose logs --tail=100 bot cabinet caddy postgres redis || true
  return 1
}

stack_start() {
  require_root
  with_lock
  sanitize_bot_env
  validate_configuration || die "Конфигурация не прошла проверку."
  info "Запускаю Bedolaga."
  compose_up_or_diagnose -d --remove-orphans || return 1
  info "Ожидаю готовность сервисов."
  if wait_for_health 300; then
    success "Все сервисы запущены и прошли health checks."
    return 0
  fi
  error "Не все сервисы стали healthy."
  compose ps || true
  compose logs --tail=100 bot cabinet caddy || true
  return 1
}

stack_apply() {
  require_root
  with_lock
  sanitize_bot_env
  validate_configuration || die "Конфигурация не прошла проверку."
  info "Применяю конфигурацию и пересобираю компоненты, которым нужны build-time параметры."
  compose_up_or_diagnose -d --build --force-recreate --remove-orphans || return 1
  wait_for_health 300 || die "Конфигурация применена, но health checks не пройдены. Запустите bedolaga doctor."
  success "Конфигурация применена."
}

stack_stop() {
  require_root
  with_lock
  compose stop
  success "Сервисы остановлены. Данные сохранены."
}

stack_restart() {
  require_root
  with_lock
  compose restart "$@"
  if wait_for_health 180; then
    success "Перезапуск завершён, сервисы работают нормально."
  else
    warn "После перезапуска не все сервисы healthy. Запустите bedolaga doctor."
    return 1
  fi
}

stack_status() {
  require_root
  if [[ ! -f "$COMPOSE_FILE" || ! -f "$STACK_ENV" ]]; then
    warn "Bedolaga ещё не установлен."
    return 1
  fi
  local service state failures=0
  ui_banner 'Состояние и версии компонентов'
  ui_section 'Состояние сервисов'
  for service in postgres redis bot cabinet caddy; do
    state="$(service_state "$service" 2>/dev/null || true)"
    ui_service_row "$service" "$state"
    [[ "$state" == running/healthy || "$state" == running/none ]] || ((failures += 1))
  done
  ui_section 'Версии'
  ui_key_value package 'Manager' "v${BEDOLAGA_VERSION}"
  ui_key_value package 'Bot commit' "$(git_short_commit "$BOT_SOURCE_DIR")"
  ui_key_value package 'Cabinet commit' "$(git_short_commit "$CABINET_SOURCE_DIR")"
  printf '\n'
  if [[ "$failures" -eq 0 ]]; then
    success "Все компоненты работают нормально."
    return 0
  fi
  error "Требуют внимания сервисов: $failures."
  ui_hint "Запустите диагностику: bedolaga doctor"
  return 1
}

stack_logs() {
  require_root
  local service="${1:-}"
  ui_banner 'Журнал сервисов · Ctrl+C для выхода'
  printf '\n'
  if [[ -n "$service" ]]; then
    case "$service" in
      bot | cabinet | caddy | postgres | redis) ;;
      *) die "Неизвестный сервис: $service" ;;
    esac
    compose logs -f --tail=150 "$service"
  else
    compose logs -f --tail=150
  fi
}

stack_versions() {
  require_root
  load_stack_env || true
  local bot_current cabinet_current bot_remote cabinet_remote
  bot_current="$(git_commit "$BOT_SOURCE_DIR")"
  cabinet_current="$(git_commit "$CABINET_SOURCE_DIR")"
  git -C "$BOT_SOURCE_DIR" fetch -q origin "${BOT_REF:-main}"
  git -C "$CABINET_SOURCE_DIR" fetch -q origin "${CABINET_REF:-main}"
  bot_remote="$(git -C "$BOT_SOURCE_DIR" rev-parse "origin/${BOT_REF:-main}")"
  cabinet_remote="$(git -C "$CABINET_SOURCE_DIR" rev-parse "origin/${CABINET_REF:-main}")"
  ui_banner 'Проверка обновлений'
  ui_section 'Доступные версии'
  printf '  %-10s %-14s %-14s %s\n' 'Компонент' 'Текущая' 'Доступная' 'Статус'
  printf '  %-10s %.12s   %.12s   %s\n' 'Bot' "$bot_current" "$bot_remote" "$([[ "$bot_current" == "$bot_remote" ]] && printf '%s актуально' "$(ui_icon success)" || printf '%s доступно' "$(ui_icon update)")"
  printf '  %-10s %.12s   %.12s   %s\n' 'Cabinet' "$cabinet_current" "$cabinet_remote" "$([[ "$cabinet_current" == "$cabinet_remote" ]] && printf '%s актуально' "$(ui_icon success)" || printf '%s доступно' "$(ui_icon update)")"
  if [[ "$bot_current" == "$bot_remote" && "$cabinet_current" == "$cabinet_remote" ]]; then
    success "Установлены актуальные версии."
  else
    ui_hint "Для обновления выполните: bedolaga update all"
  fi
}

config_edit() {
  require_root
  local target="${1:-bot}"
  local file editor
  case "$target" in
    bot) file="$BOT_ENV" ;;
    stack) file="$STACK_ENV" ;;
    caddy) file="$CADDY_FILE" ;;
    wizard) configuration_wizard; validate_configuration; return ;;
    paths)
      ui_banner 'Файлы конфигурации'
      ui_key_value config 'Bot env' "$BOT_ENV"
      ui_key_value config 'Stack env' "$STACK_ENV"
      ui_key_value config 'Caddyfile' "$CADDY_FILE"
      ui_hint 'Редактирование: bedolaga config <bot|stack|caddy>'
      return
      ;;
    *) die "Использование: bedolaga config [bot|stack|caddy|wizard|paths]" ;;
  esac
  editor="${EDITOR:-nano}"
  command_exists "$editor" || editor="nano"
  "$editor" "$file"
  chmod 600 "$file"
  if [[ "$target" == stack ]]; then
    validate_stack_values || die "Некорректные значения в $STACK_ENV"
    render_caddyfile
  fi
  validate_configuration || die "После редактирования конфигурация некорректна. Исправьте файл: $file"
  success "Конфигурация корректна. Для применения выполните bedolaga apply."
}
