#!/usr/bin/env bash

detect_os() {
  [[ -r /etc/os-release ]] || die "Не удалось определить операционную систему."
  # shellcheck disable=SC1091
  source /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_VERSION="${VERSION_ID:-unknown}"
  OS_PRETTY="${PRETTY_NAME:-$OS_ID $OS_VERSION}"
}

check_supported_os() {
  detect_os
  case "$OS_ID:$OS_VERSION" in
    ubuntu:22.04 | ubuntu:24.04 | debian:12*) return 0 ;;
    *) die "Поддерживаются Ubuntu 22.04/24.04 и Debian 12. Обнаружено: $OS_PRETTY" ;;
  esac
}

check_architecture() {
  local architecture
  architecture="$(uname -m)"
  case "$architecture" in
    x86_64 | amd64 | aarch64 | arm64) ;;
    *) die "Неподдерживаемая архитектура: $architecture" ;;
  esac
}

resource_preflight() {
  local memory_mb disk_mb cpu_count
  memory_mb="$(awk '/MemTotal/ {print int($2 / 1024)}' /proc/meminfo)"
  disk_mb="$(df -Pm "$INSTALL_ROOT" 2>/dev/null | awk 'NR==2 {print $4}' || true)"
  if [[ -z "$disk_mb" ]]; then
    disk_mb="$(df -Pm / | awk 'NR==2 {print $4}')"
  fi
  cpu_count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1')"
  info "Ресурсы: CPU ${cpu_count}, RAM ${memory_mb} MB, свободно ${disk_mb} MB."
  ((memory_mb >= 1024)) || warn "RAM меньше 1 GB. Для Bot + Cabinet рекомендуется создать swap."
  ((memory_mb >= 512)) || die "Недостаточно RAM: требуется минимум 512 MB."
  ((disk_mb >= 4096)) || die "Недостаточно места: требуется минимум 4 GB свободного диска."
}

apt_install_dependencies() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y ca-certificates curl git jq openssl tar gzip coreutils findutils util-linux dnsutils nano
}

install_docker() {
  if command_exists docker && docker compose version >/dev/null 2>&1; then
    success "Docker и Compose v2 уже установлены."
    return 0
  fi

  info "Устанавливаю Docker Engine и Compose v2."
  if apt-get install -y docker.io docker-compose-v2 >/dev/null 2>&1; then
    :
  elif apt-get install -y docker.io docker-compose-plugin >/dev/null 2>&1; then
    :
  else
    local installer
    installer="$(mktemp)"
    curl -fsSL https://get.docker.com -o "$installer"
    grep -q 'Docker' "$installer" || { rm -f "$installer"; die "Получен некорректный установщик Docker."; }
    sh "$installer"
    rm -f "$installer"
  fi
  systemctl enable --now docker >/dev/null 2>&1 || true
  docker info >/dev/null 2>&1 || die "Docker установлен, но daemon недоступен."
  docker compose version >/dev/null 2>&1 || die "Docker Compose v2 не найден."
}

port_owner() {
  local port="$1"
  if command_exists ss; then
    ss -H -ltnp "sport = :$port" 2>/dev/null || true
  fi
}

check_public_ports() {
  local port owner managed_container
  for port in 80 443; do
    owner="$(port_owner "$port")"
    managed_container="$(docker ps --filter "publish=$port" --format '{{.Names}}' 2>/dev/null | grep -E '^bedolaga-caddy-[0-9]+$' || true)"
    if [[ -n "$owner" && -z "$managed_container" ]]; then
      warn "Порт $port уже занят: $owner"
      confirm "Продолжить несмотря на занятый порт $port?" || return 1
    fi
  done
}

public_ipv4() {
  curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true
}

dns_ipv4() {
  local domain="$1"
  getent ahostsv4 "$domain" 2>/dev/null | awk 'NR==1 {print $1}'
}

check_domain_dns() {
  local domain="$1"
  local server_ip dns_ip
  server_ip="$(public_ipv4)"
  dns_ip="$(dns_ipv4 "$domain")"
  if [[ -z "$dns_ip" ]]; then
    warn "DNS A-запись для $domain пока не найдена. Caddy не сможет получить сертификат."
    return 1
  fi
  if [[ -n "$server_ip" && "$dns_ip" != "$server_ip" ]]; then
    warn "$domain указывает на $dns_ip, а IP сервера — $server_ip."
    return 1
  fi
  success "DNS $domain → $dns_ip"
}

preflight() {
  require_root
  check_supported_os
  check_architecture
  ensure_runtime_dirs
  resource_preflight
  apt_install_dependencies
  install_docker
  check_public_ports
}

service_state() {
  local service="$1"
  local container_id state health exit_code details
  if ! container_id="$(compose ps -a -q "$service" 2>/dev/null)"; then
    printf 'unavailable/unknown\n'
    return 1
  fi
  if [[ -z "$container_id" ]]; then
    printf 'not-created\n'
    return 1
  fi
  if ! details="$(docker inspect -f '{{.State.Status}}/{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}/{{.State.ExitCode}}' "$container_id" 2>/dev/null)"; then
    printf 'unavailable/unknown\n'
    return 1
  fi
  IFS=/ read -r state health exit_code <<<"$details"
  if [[ "$state" == exited ]]; then
    printf 'exited/%s\n' "${exit_code:-unknown}"
    return 1
  fi
  printf '%s/%s\n' "$state" "$health"
  [[ "$state" == running && "$health" != unhealthy ]]
}

wait_for_services() {
  local timeout="${1:-240}"
  shift || true
  local started service state all_healthy
  local -a services=("$@")
  [[ "${#services[@]}" -gt 0 ]] || return 0
  started="$(date +%s)"
  while true; do
    all_healthy=1
    for service in "${services[@]}"; do
      state="$(service_state "$service" 2>/dev/null || true)"
      if [[ "$state" != running/healthy && "$state" != running/none ]]; then
        all_healthy=0
      fi
    done
    [[ "$all_healthy" -eq 1 ]] && return 0
    if (( $(date +%s) - started >= timeout )); then
      return 1
    fi
    sleep 5
  done
}

wait_for_health() {
  local timeout="${1:-240}"
  local -a services=()
  mapfile -t services < <(managed_services)
  wait_for_services "$timeout" "${services[@]}"
}
