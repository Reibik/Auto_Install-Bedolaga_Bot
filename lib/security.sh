#!/usr/bin/env bash

detect_ssh_port() {
  local port=''
  if command_exists sshd; then
    port="$(sshd -T 2>/dev/null | awk '$1 == "port" {print $2; exit}' || true)"
  fi
  if [[ -z "$port" && -n "${SSH_CONNECTION:-}" ]]; then
    port="$(awk '{print $4}' <<<"$SSH_CONNECTION")"
  fi
  if [[ ! "$port" =~ ^[0-9]{1,5}$ ]] || ((10#$port < 1 || 10#$port > 65535)); then
    port=22
  fi
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
      info "Будут разрешены SSH (${ssh_port}/tcp), HTTP (80/tcp), HTTPS (443/tcp) и HTTP/3 (443/udp)."
      confirm "Установить правила и включить UFW?" || die "Отменено. Настройки UFW не изменены."
      apt-get update -y
      apt-get install -y ufw
      ufw allow "${ssh_port}/tcp" comment 'SSH'
      ufw allow 80/tcp comment 'Bedolaga HTTP'
      ufw allow 443/tcp comment 'Bedolaga HTTPS'
      ufw allow 443/udp comment 'Bedolaga HTTP3'
      ufw --force enable
      ufw status numbered
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
