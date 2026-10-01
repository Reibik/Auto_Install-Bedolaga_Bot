#!/usr/bin/env bash

menu_command() {
  bash "$BEDOLAGA_LIB_ROOT/bedolaga" "$@"
}

menu_pause() {
  local answer=''
  read_tty answer "\n${C_CYAN}Enter — продолжить${C_RESET} "
  : "$answer"
}

menu_last_backup() {
  local entry archive
  local -a entries=()
  [[ -d "$BACKUP_ROOT" ]] || { printf 'Пока нет\n'; return; }
  mapfile -t entries < <(find "$BACKUP_ROOT" -maxdepth 1 -type f -name 'bedolaga_*.tar.gz' -printf '%T@ %p\n' 2>/dev/null | sort -rn)
  for entry in "${entries[@]}"; do
    archive="${entry#* }"
    if [[ -s "$archive" && -s "${archive}.sha256" ]]; then
      date -r "$archive" '+%d.%m.%Y %H:%M'
      return
    fi
  done
  printf 'Пока нет\n'
}

menu_draw_main() {
  ui_banner 'Bot + Cabinet · управление'
  ui_section 'Обзор'
  menu_summary
  ui_section 'Действия'
  ui_menu_item 1 docker 'Сервисы'
  ui_menu_item 2 update 'Обновления'
  ui_menu_item 3 config 'Настройки'
  ui_menu_item 4 backup 'Резервные копии'
  ui_menu_item 5 doctor 'Диагностика'
  ui_menu_item 6 status 'Xray Monitoring'
  ui_menu_item 0 exit 'Выход'
}

menu_draw_submenu() {
  local section="$1"
  case "$section" in
    services)
      ui_banner 'Сервисы'
      ui_menu_item 1 status 'Статус и версии'
      ui_menu_item 2 start 'Запустить стек'
      ui_menu_item 3 stop 'Остановить стек'
      ui_menu_item 4 restart 'Перезапустить сервис'
      ui_menu_item 5 logs 'Логи сервиса'
      if [[ ! -f "$COMPOSE_FILE" || ! -f "$STACK_ENV" ]]; then
        ui_menu_item 6 deploy 'Установить проект'
      fi
      ;;
    updates)
      ui_banner 'Обновления'
      ui_menu_item 1 status 'Проверить версии приложений'
      ui_menu_item 2 deploy 'Обновить все приложения'
      ui_menu_item 3 bot 'Обновить только Bot'
      ui_menu_item 4 globe 'Обновить только Cabinet'
      ui_menu_item 5 sparkle 'Обновить Manager'
      ui_danger_item 6 rollback 'Откатить приложения'
      ui_hint 'Manager и приложения обновляются отдельно.'
      ;;
    settings)
      ui_banner 'Настройки'
      ui_menu_item 1 config 'Переменные Bot'
      ui_menu_item 2 config 'Параметры стека'
      ui_menu_item 3 globe 'Настройки Caddy / HTTPS'
      ui_menu_item 4 archives 'Пути конфигурационных файлов'
      ui_menu_item 5 config 'Мастер настройки'
      ui_menu_item 6 deploy 'Применить изменения'
      ui_hint 'После редактирования выберите «Применить изменения».'
      ;;
    backups)
      ui_banner 'Резервные копии'
      ui_key_value backup 'Последний архив' "$(menu_last_backup)"
      ui_menu_item 1 backup 'Создать бэкап'
      ui_menu_item 2 archives 'Список архивов'
      ui_danger_item 3 rollback 'Восстановить из архива'
      ui_menu_item 4 status 'Статус ежедневных бэкапов'
      ui_menu_item 5 start 'Включить ежедневные бэкапы'
      ui_menu_item 6 stop 'Отключить ежедневные бэкапы'
      ui_hint 'Восстановление заменяет настройки и данные базы.'
      ;;
    diagnostics)
      ui_banner 'Диагностика'
      menu_host_summary
      ui_menu_item 1 doctor 'Полная диагностика'
      ui_menu_item 2 status 'Состояние контейнеров'
      ui_menu_item 3 logs 'Просмотр логов'
      ;;
  esac
  ui_menu_item 0 exit 'Назад'
}

menu_service_action() {
  local action="$1" service=''
  if menu_choose_service service; then
    if [[ -n "$service" ]]; then
      menu_command "$action" "$service"
    else
      menu_command "$action"
    fi
  fi
}

menu_submenu_action() {
  local section="$1" choice="$2" archive=''
  case "$section:$choice" in
    services:1 | diagnostics:2) menu_command status ;;
    services:2) menu_command start ;;
    services:3)
      confirm 'Остановить все сервисы? Данные сохранятся.' || return 0
      menu_command stop
      ;;
    services:4) menu_service_action restart ;;
    services:5 | diagnostics:3) menu_service_action logs ;;
    services:6)
      [[ ! -f "$COMPOSE_FILE" || ! -f "$STACK_ENV" ]] || { warn 'Проект уже установлен.'; return 1; }
      menu_command install
      ;;
    updates:1) menu_command versions ;;
    updates:2 | updates:3 | updates:4)
      confirm 'Обновить приложения с бэкапом и перезапуском выбранных компонентов?' || return 0
      case "$choice" in
        2) menu_command update all ;;
        3) menu_command update bot ;;
        4) menu_command update cabinet ;;
      esac
      ;;
    updates:5) menu_command self-update ;;
    updates:6) menu_command rollback ;;
    settings:1) menu_command config bot ;;
    settings:2) menu_command config stack ;;
    settings:3) menu_command config caddy ;;
    settings:4) menu_command config paths ;;
    settings:5)
      menu_command config wizard || return 1
      if confirm 'Применить сохранённые настройки сейчас?'; then
        menu_command apply
      fi
      ;;
    settings:6)
      confirm 'Применить настройки? Контейнеры будут пересозданы.' || return 0
      menu_command apply
      ;;
    backups:1) menu_command backup ;;
    backups:2) menu_command backup-list ;;
    backups:3)
      menu_command backup-list || return 1
      ui_hint 'Укажите полный путь к архиву. Enter — отмена.'
      read_tty archive "${C_CYAN}Путь к архиву: ${C_RESET}"
      [[ -n "$archive" ]] || return 0
      # CLI verifies the path and checksum, then requires the RESTORE phrase.
      menu_command restore "$archive"
      ;;
    backups:4) menu_command schedule status ;;
    backups:5) menu_command schedule enable ;;
    backups:6)
      confirm 'Отключить ежедневные бэкапы? Существующие архивы сохранятся.' || return 0
      menu_command schedule disable
      ;;
    diagnostics:1) menu_command doctor ;;
    *) warn 'Неизвестный пункт.'; return 1 ;;
  esac
}

menu_submenu() {
  local section="$1" choice='' result=0
  while true; do
    ui_clear
    menu_draw_submenu "$section"
    read_tty choice "\n${C_CYAN}Действие [0 — назад]: ${C_RESET}"
    case "$choice" in
      0 | '') return 0 ;;
    esac
    result=0
    menu_submenu_action "$section" "$choice" || result=$?
    if [[ "$result" -ne 0 ]]; then
      case "$section:$choice" in
        services:1 | diagnostics:1 | diagnostics:2 | backups:4)
          ui_hint 'Проверка требует внимания. Подробности — выше.'
          ;;
        *) ui_hint 'Операция не завершена. Подробности — выше.' ;;
      esac
    fi
    menu_pause
    if [[ "$section:$choice" == updates:5 && "$result" -eq 0 ]]; then
      # Reload updated function definitions, rather than continue the old menu.
      exec env BEDOLAGA_SKIP_UPDATE_CHECK=1 bash "$BEDOLAGA_LIB_ROOT/bedolaga" menu
    fi
  done
}
