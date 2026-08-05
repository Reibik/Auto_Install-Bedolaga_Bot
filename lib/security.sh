#!/usr/bin/env bash

detect_ssh_port() {
  local port=''
  if command_exists sshd; then
    port="$(sshd -T 2>/dev/null | awk '$1 == "port" {print $2; exit}' || true)"
  fi
  if [[ -z "$port" && -n "${SSH_CONNECTION:-}" ]]; then
    port="$(awk '{print $4}' <<<"$SSH_CONNECTION")"
  fi
  [[ "$port" =~ ^[0-9]{1,5}$ ]] || port=22
  printf '%s\n' "$port"
}
firewall_manage() {
  require_root
  local action="${1:-status}"
  local ssh_port
  ssh_port="$(detect_ssh_port)"
  case "$action" in
    status)
      if command_exists ufw; then
        ufw status verbose
      else
        warn "UFW не установлен."
      fi
      ;;
    enable)
      apt-get update -y
      apt-get install -y ufw
      info "Сначала разрешаю текущий SSH-порт $ssh_port, затем HTTP/HTTPS."
      ufw allow "${ssh_port}/tcp" comment 'SSH'
      ufw allow 80/tcp comment 'Bedolaga HTTP'
      ufw allow 443/tcp comment 'Bedolaga HTTPS'
      ufw allow 443/udp comment 'Bedolaga HTTP3'
      ufw status numbered
      confirm "Включить UFW с показанными правилами?" || die "Отменено. Правила добавлены, но UFW не включён."
      ufw --force enable
      success "UFW включён. SSH-порт $ssh_port разрешён."
      ;;
    disable)
      confirm_phrase "Отключение UFW снизит защиту сервера." "DISABLE-UFW" || die "Отменено."
      ufw disable
      success "UFW отключён."
      ;;
    *) die "Использование: bedolaga firewall [enable|disable|status]" ;;
  esac
}
