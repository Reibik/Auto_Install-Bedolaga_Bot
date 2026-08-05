#!/usr/bin/env bash

install_stack() {
  require_root
  with_lock
  preflight
  prepare_sources
  initialize_env_files
  copy_compose_template
  configuration_wizard

  local dns_ok=1
  load_stack_env
  check_domain_dns "$WEBHOOK_DOMAIN" || dns_ok=0
  check_domain_dns "$CABINET_DOMAIN" || dns_ok=0
  if [[ "$dns_ok" -eq 0 ]]; then
    confirm "DNS ещё не готов. Продолжить сборку и запуск?" || {
      success "Конфигурация сохранена. После настройки DNS выполните: bedolaga start"
      return 0
    }
  fi

  validate_configuration || die "Сгенерированная конфигурация некорректна."
  compose_up_or_diagnose -d --build --remove-orphans || return 1
  if wait_for_health 300; then
    success "Bedolaga установлен."
    printf '\n  Cabinet: https://%s\n  Webhook: https://%s/webhook\n\n' "$CABINET_DOMAIN" "$WEBHOOK_DOMAIN"
    printf 'Добавьте домен %s в BotFather → Bot Settings → Domain.\n\n' "$CABINET_DOMAIN"
    backup_schedule enable || warn "Не удалось включить ежедневный бэкап. Это можно сделать: bedolaga schedule enable"
    doctor || true
  else
    error "Контейнеры созданы, но не все health checks пройдены."
    compose ps
    printf '\nЗапустите диагностику: bedolaga doctor\n'
    return 1
  fi
}

uninstall_stack() {
  require_root
  local purge="${1:-}"
  if [[ "$purge" == "--purge-data" ]]; then
    confirm_phrase "Будут удалены контейнеры, база, конфигурация и бэкапы." "PURGE-BEDOLAGA" || die "Отменено."
  else
    confirm "Удалить контейнеры и программу, сохранив конфигурацию, данные и бэкапы?" || die "Отменено."
  fi
  with_lock
  if [[ -f "$COMPOSE_FILE" && -f "$STACK_ENV" ]]; then
    if [[ "$purge" == "--purge-data" ]]; then
      compose down --remove-orphans --volumes
    else
      compose down --remove-orphans
    fi
  fi
  systemctl disable --now bedolaga-backup.timer >/dev/null 2>&1 || true
  safe_realpath_child "$INSTALL_ROOT" /opt || die "Небезопасный INSTALL_ROOT: $INSTALL_ROOT"
  rm -rf -- "$INSTALL_ROOT"
  rm -f -- /usr/local/bin/bedolaga
  rm -rf -- /usr/local/lib/bedolaga-manager /usr/local/lib/bedolaga-manager.previous
  if [[ "$purge" == "--purge-data" ]]; then
    safe_realpath_child "$CONFIG_ROOT" /etc || die "Небезопасный CONFIG_ROOT: $CONFIG_ROOT"
    safe_realpath_child "$DATA_ROOT" /var/lib || die "Небезопасный DATA_ROOT: $DATA_ROOT"
    rm -rf -- "$CONFIG_ROOT" "$DATA_ROOT"
    success "Bedolaga и все управляемые данные удалены без возможности восстановления."
  else
    success "Программа удалена. Конфигурация: $CONFIG_ROOT, данные: $DATA_ROOT"
  fi
}
