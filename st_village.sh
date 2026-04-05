#!/usr/bin/env bash

# === ST VILLAGE | ПАНЕЛЬ УПРАВЛЕНИЯ v19.0 ===
# Enhanced Edition for Bedolaga Bot + Cabinet + Caddy

set -Eeuo pipefail
export LC_ALL=C

# === COLORS ===
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; PURPLE='\033[0;35m'; BLUE='\033[0;34m'
BOLD='\033[1m'; NC='\033[0m'

# === CONFIGURATION ===
PANEL_VERSION="19.0"

BASE_DIR="${ST_VILLAGE_BASE_DIR:-/root}"
BOT_DIR="${BASE_DIR}/bot"
CABINET_DIR="${BASE_DIR}/cabinet"
CADDY_DIR="${BASE_DIR}/caddy"
BACKUP_DIR="${BASE_DIR}/backups"

BOT_REPO="https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot.git"
CABINET_REPO="https://github.com/BEDOLAGA-DEV/bedolaga-cabinet.git"

SCRIPT_URL="https://raw.githubusercontent.com/Reibik/Auto_Install-Bedolaga_Bot/main/st_village.sh"
DEFAULT_INSTALL_PATH="/root/st_village.sh"

BOT_COMPOSE_FILE="${BOT_DIR}/docker-compose.local.yml"
CABINET_COMPOSE_FILE="${CABINET_DIR}/docker-compose.yml"
CABINET_OVERRIDE_FILE="${CABINET_DIR}/docker-compose.override.yml"
CADDY_COMPOSE_FILE="${CADDY_DIR}/docker-compose.yml"
CADDYFILE="${CADDY_DIR}/Caddyfile"

HTTP_PORT="${ST_VILLAGE_HTTP_PORT:-80}"
HTTPS_PORT="${ST_VILLAGE_HTTPS_PORT:-443}"

NOTIFY_FLAG="${BASE_DIR}/.notify_enabled"
WATCHDOG_FLAG="${BASE_DIR}/.watchdog_enabled"
HEALTHCHECK_FLAG="${BASE_DIR}/.healthcheck_enabled"

LOG_FILE="${BASE_DIR}/st_village.log"
LOG_MAX_SIZE=10485760  # 10 MB

VERSION_CACHE_FILE="/tmp/stv_version_cache"
VERSION_CACHE_TTL=300  # 5 минут

BOT_VER_TXT="" CAB_VER_TXT=""
BOT_HEALTH="" CAB_HEALTH="" CADDY_HEALTH=""
OS_NAME="" UPTIME_TXT="" RAM_TXT="" DISK_TXT="" DOCKER_STAT=""
SCRIPT_PATH="" TTY_READY=0 STV_BACKUP_LIST_TMP=""

# === LOGGING ===

_log_to_file() {
    local msg="$1"
    [[ -n "${LOG_FILE:-}" ]] || return 0
    if [[ -f "$LOG_FILE" ]]; then
        local fsize=0
        fsize="$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)"
        if [[ "$fsize" -gt "$LOG_MAX_SIZE" ]]; then
            mv -f "$LOG_FILE" "${LOG_FILE}.old" 2>/dev/null || true
        fi
    fi
    printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

log()  { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $*"; _log_to_file "INFO: $*"; }
ok()   { echo -e "${GREEN}[✓]${NC} $*"; _log_to_file "OK: $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; _log_to_file "WARN: $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; _log_to_file "ERROR: $*"; }
die()  { err "$*"; exit 1; }

# === CORE HELPERS ===

_flag_status() { [[ -f "$1" ]] && printf '%b' "${GREEN}ВКЛ${NC}" || printf '%b' "${RED}ВЫКЛ${NC}"; }

_menu_header() {
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${BOLD}${1}${NC}"
    echo -e "${CYAN}========================================${NC}"
}

_menu_choice() {
    local __var="$1"
    read_tty "$__var" "\n${YELLOW}Выберите действие ➤ ${NC}"
}

_container_state() {
    # Возвращает: "true", "false" или "" (не создан)
    local name="$1"
    docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null || true
}

_state_icon() {
    # $1=state, $2=style: "dot" (⬤) или "circle" (🟢)
    local state="$1" style="${2:-circle}"
    if [[ "$style" == "dot" ]]; then
        case "$state" in
            true)  printf '%b' "${GREEN}⬤ Работает${NC}" ;;
            false) printf '%b' "${RED}⬤ Не запущен${NC}" ;;
            *)     printf '%b' "${RED}⬤ Не запущен${NC}" ;;
        esac
    else
        case "$state" in
            true)  printf '%b' "${GREEN}🟢 Работает${NC}" ;;
            false) printf '%b' "${RED}🔴 Остановлен${NC}" ;;
            *)     printf '%b' "${YELLOW}⚫ Не создан${NC}" ;;
        esac
    fi
}

_resolve_domain() {
    # Резолвит домен в IP. Возвращает IP или пустую строку.
    local domain="$1" resolved=""
    if command_exists dig; then
        resolved="$(dig +short "$domain" A 2>/dev/null | head -1 || true)"
    fi
    if [[ -z "$resolved" ]]; then
        resolved="$(getent ahosts "$domain" 2>/dev/null | awk 'NR==1{print $1}' || true)"
    fi
    echo "$resolved"
}

_ssl_days_left() {
    # Возвращает кол-во дней до истечения SSL или -1 при ошибке.
    local domain="$1"
    local expiry=""
    expiry="$(echo | openssl s_client -connect "${domain}:443" -servername "$domain" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d '=' -f 2 || true)"
    if [[ -n "$expiry" ]]; then
        local expiry_epoch=0 now_epoch=0
        expiry_epoch="$(date -d "$expiry" +%s 2>/dev/null || echo 0)"
        now_epoch="$(date +%s)"
        if [[ "$expiry_epoch" -gt 0 ]]; then
            echo "$(( (expiry_epoch - now_epoch) / 86400 ))"
            return 0
        fi
    fi
    echo "-1"
}

_compose_stop_all() {
    [[ -f "$CADDY_COMPOSE_FILE" ]] && dc_caddy stop >/dev/null 2>&1 || true
    [[ -f "$CABINET_COMPOSE_FILE" ]] && dc_cabinet stop >/dev/null 2>&1 || true
    [[ -f "$BOT_COMPOSE_FILE" ]] && dc_bot stop >/dev/null 2>&1 || true
}

_compose_down_all() {
    [[ -f "$CADDY_COMPOSE_FILE" ]] && dc_caddy down -v >/dev/null 2>&1 || true
    [[ -f "$CABINET_COMPOSE_FILE" ]] && dc_cabinet down -v >/dev/null 2>&1 || true
    [[ -f "$BOT_COMPOSE_FILE" ]] && dc_bot down -v >/dev/null 2>&1 || true
}

_prompt_env() {
    # $1=env_file, $2=key, $3=label, $4=default_display (optional)
    local env_file="$1" key="$2" label="$3" dflt="${4:-}"
    local current="" val="" display=""
    current="$(read_env_value "$env_file" "$key")"
    display="${current:-${dflt:-не задан}}"
    read_tty val "  ${GREEN}${label}${NC} [${display}]: "
    if [[ -n "$val" ]]; then
        set_env_value "$env_file" "$key" "$val"
    fi
    echo "$val"
}

_ensure_env() {
    # $1=dir — создаёт .env из .env.example если не существует
    local dir="$1"
    if [[ ! -f "${dir}/.env" ]]; then
        if [[ -f "${dir}/.env.example" ]]; then
            cp "${dir}/.env.example" "${dir}/.env"
        else
            touch "${dir}/.env"
        fi
    fi
}

_cron_toggle() {
    # $1=keyword (cron_healthcheck|cron_watchdog|cron_backup)
    # $2=schedule (*/10 * * * *|*/5 * * * *|0 3 * * *)
    # $3=flag_file
    # $4=enable|disable
    local keyword="$1" schedule="$2" flag="$3" action="$4"
    if [[ "$action" == "enable" ]]; then
        persist_self_if_needed || warn "Не удалось сохранить панель в ${DEFAULT_INSTALL_PATH}"
        local cron_line="${schedule} ${DEFAULT_INSTALL_PATH} ${keyword}"
        (crontab -l 2>/dev/null | grep -v "$keyword"; echo "$cron_line") | crontab -
        touch "$flag"
        _log_to_file "Cron ${keyword} enabled"
    else
        crontab -l 2>/dev/null | grep -v "$keyword" | crontab - 2>/dev/null || true
        rm -f "$flag"
        _log_to_file "Cron ${keyword} disabled"
    fi
}

_get_ver_txt() {
    # $1=dir, $2=mode: "full" (git fetch) или "fast" (local only)
    local dir="$1" mode="${2:-fast}"
    if [[ ! -d "${dir}/.git" ]]; then
        printf '%b' "${RED}Не установлен${NC}"
        return 0
    fi
    local local_hash=""
    local_hash="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    if [[ "$mode" == "full" ]]; then
        git -C "$dir" fetch origin main -q >/dev/null 2>&1 || true
        local remote_hash=""
        remote_hash="$(git -C "$dir" rev-parse --short origin/main 2>/dev/null || echo '')"
        if [[ -n "$remote_hash" && "$local_hash" != "$remote_hash" ]]; then
            printf '%b' "${YELLOW}${local_hash} ➜ доступна ${remote_hash}${NC} ${RED}[обновить]${NC}"
        else
            printf '%b' "${GREEN}${local_hash} (Актуально)${NC}"
        fi
    else
        printf '%b' "${GREEN}${local_hash}${NC}"
    fi
}

# === CORE UTILITIES ===

require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        die "Запусти скрипт от root."
    fi
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

resolve_script_path() {
    if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
        SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
    elif [[ -f "$0" ]]; then
        SCRIPT_PATH="$(readlink -f "$0")"
    else
        SCRIPT_PATH="${DEFAULT_INSTALL_PATH}"
    fi
}

ensure_unix_file() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    sed -i 's/\r$//' "$file"
}

get_server_ip() {
    curl -4s --connect-timeout 5 ifconfig.me 2>/dev/null \
        || curl -4s --connect-timeout 5 api.ipify.org 2>/dev/null \
        || ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' \
        || echo "unknown"
}

generate_secret() {
    openssl rand -hex 32 2>/dev/null \
        || head -c 32 /dev/urandom | xxd -p 2>/dev/null \
        || date +%s%N | sha256sum | head -c 64
}

read_env_value() {
    local env_file="$1" key="$2"
    [[ -f "$env_file" ]] || return 0
    local line=""
    line="$(grep -E "^${key}=" "$env_file" 2>/dev/null || true)"
    [[ -n "$line" ]] || return 0
    echo "$line" | cut -d '=' -f 2- | sed "s/^[\"']//;s/[\"']$//"
}

set_env_value() {
    local env_file="$1" key="$2" value="$3"
    if grep -qE "^${key}=" "$env_file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$env_file"
    else
        echo "${key}=${value}" >> "$env_file"
    fi
}

parse_caddyfile_domains() {
    [[ -f "$CADDYFILE" ]] || return 0
    grep -E '^[a-zA-Z0-9].*\{' "$CADDYFILE" 2>/dev/null | awk '{print $1}' | grep -vE '^#' | sort -u || true
}

send_telegram_notification() {
    local message="${1:-}"
    [[ -f "$NOTIFY_FLAG" ]] || return 0
    local bot_token="" admin_ids=""
    bot_token="$(read_env_value "${BOT_DIR}/.env" "BOT_TOKEN")"
    admin_ids="$(read_env_value "${BOT_DIR}/.env" "ADMIN_IDS")"
    [[ -n "$bot_token" && -n "$admin_ids" ]] || return 0
    local admin_id
    while IFS=',' read -ra ADDR; do
        for admin_id in "${ADDR[@]}"; do
            admin_id="${admin_id// /}"
            [[ -n "$admin_id" ]] || continue
            curl -sf -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
                -d "chat_id=${admin_id}" \
                -d "text=🏘 ST Village: ${message}" \
                -d "parse_mode=HTML" \
                >/dev/null 2>&1 || true
        done
    done <<< "$admin_ids"
}

# === TTY ===

init_tty() {
    if [[ "${1:-}" == "cron_backup" || "${1:-}" == "cron_healthcheck" || "${1:-}" == "cron_watchdog" ]]; then
        return 0
    fi
    if exec 3</dev/tty 4>/dev/tty; then
        TTY_READY=1; return 0
    fi
    if [[ -t 0 ]]; then
        exec 3<&0 4>&1; TTY_READY=1; return 0
    fi
    die "Нет доступа к интерактивному терминалу. Запусти скрипт из обычной SSH-сессии."
}

read_tty() {
    local __var_name="$1" __prompt="${2:-}" __value=""
    [[ "$TTY_READY" -eq 1 ]] || die "Интерактивный ввод недоступен."
    printf "%b" "$__prompt" >&4
    IFS= read -r __value <&3 || __value=""
    printf -v "$__var_name" '%s' "$__value"
}

pause() {
    if [[ "$TTY_READY" -eq 1 ]]; then
        printf "\n%b" "${YELLOW}Нажми Enter для продолжения...${NC}" >&4
        local _; IFS= read -r _ <&3 || true
    fi
}

confirm() {
    local prompt="${1:-Продолжить?}" answer
    read_tty answer "\n${YELLOW}${prompt} [y/N]: ${NC}"
    [[ "$answer" =~ ^[Yy]$ ]]
}

# === DOCKER HELPERS ===

ensure_dirs() { mkdir -p "$BASE_DIR" "$BOT_DIR" "$CABINET_DIR" "$CADDY_DIR" "$BACKUP_DIR"; }

compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        docker compose "$@"
    elif command_exists docker-compose; then
        docker-compose "$@"
    else
        die "Docker Compose не найден."
    fi
}

dc_bot()     { compose_cmd -f "$BOT_COMPOSE_FILE" "$@"; }
dc_cabinet() {
    if [[ -f "$CABINET_OVERRIDE_FILE" ]]; then
        compose_cmd -f "$CABINET_COMPOSE_FILE" -f "$CABINET_OVERRIDE_FILE" "$@"
    else
        compose_cmd -f "$CABINET_COMPOSE_FILE" "$@"
    fi
}
dc_caddy()   { compose_cmd -f "$CADDY_COMPOSE_FILE" "$@"; }

# === DEPENDENCIES ===

ensure_dependencies() {
    log "Проверяю системные зависимости..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y \
        git curl wget nano tar ca-certificates gnupg lsb-release \
        unzip apt-transport-https software-properties-common dnsutils \
        >/dev/null 2>&1 || die "Не удалось установить базовые зависимости."

    if ! command_exists docker; then
        log "Docker не найден. Устанавливаю..."
        curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
        sh /tmp/get-docker.sh >/dev/null 2>&1 || die "Не удалось установить Docker."
        rm -f /tmp/get-docker.sh
    fi
    if ! docker compose version >/dev/null 2>&1 && ! command_exists docker-compose; then
        apt-get install -y docker-compose-plugin >/dev/null 2>&1 || true
    fi
    systemctl enable docker >/dev/null 2>&1 || true
    systemctl restart docker >/dev/null 2>&1 || true
    docker info >/dev/null 2>&1 || die "Docker установлен, но демон Docker недоступен."
}

# === FILE GENERATION ===

write_cabinet_override() {
    cat > "$CABINET_OVERRIDE_FILE" <<'EOF'
services:
  cabinet-frontend:
    networks:
      - remnawave-network

networks:
  remnawave-network:
    external: true
    name: remnawave-network
EOF
}

write_default_caddy_files() {
    mkdir -p "$CADDY_DIR"
    cat > "$CADDYFILE" <<'EOF'
# Укажи свои реальные домены перед публичным запуском.

bot.example.com {
    encode gzip zstd
    reverse_proxy remnawave_bot:8080
}

cabinet.example.com {
    encode gzip zstd

    handle /api/* {
        uri strip_prefix /api
        reverse_proxy remnawave_bot:8080
    }

    handle {
        reverse_proxy cabinet_frontend:80
    }
}
EOF

    cat > "$CADDY_COMPOSE_FILE" <<'EOF'
services:
  caddy:
    image: caddy:2-alpine
    container_name: st_village_caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    networks:
      - remnawave-network

networks:
  remnawave-network:
    external: true
    name: remnawave-network

volumes:
  caddy_data:
  caddy_config:
EOF
}

prepare_env_files() {
    _ensure_env "$BOT_DIR"
    _ensure_env "$CABINET_DIR"
    local jwt=""
    jwt="$(read_env_value "${BOT_DIR}/.env" "CABINET_JWT_SECRET")"
    if [[ -z "$jwt" ]]; then
        set_env_value "${BOT_DIR}/.env" "CABINET_JWT_SECRET" "$(generate_secret)"
    fi
}

normalize_project_files() {
    ensure_unix_file "$BOT_COMPOSE_FILE"
    ensure_unix_file "$CABINET_COMPOSE_FILE"
    ensure_unix_file "${BOT_DIR}/.env.example"
    ensure_unix_file "${CABINET_DIR}/.env.example"
    ensure_unix_file "$CADDYFILE"
    ensure_unix_file "$CADDY_COMPOSE_FILE"
    write_cabinet_override
}

clone_or_update_repo() {
    local repo_url="$1" target_dir="$2" title="$3"
    if [[ -d "${target_dir}/.git" ]]; then
        log "${title} уже существует."; return 0
    fi
    rm -rf "$target_dir"
    log "Клонирую ${title}..."
    git clone "$repo_url" "$target_dir" >/dev/null 2>&1 || die "Не удалось клонировать ${title}."
}

# === INSTALL & SETUP ===

show_post_install_steps() {
    echo
    echo -e "${YELLOW}Что нужно сделать дальше:${NC}"
    echo -e "  1) Заполнить ${CYAN}${BOT_DIR}/.env${NC}"
    echo -e "     ${YELLOW}Обязательно:${NC} ${GREEN}BOT_TOKEN${NC} — токен бота от @BotFather"
    echo -e "     ${YELLOW}Обязательно:${NC} ${GREEN}ADMIN_IDS${NC} — ваш Telegram ID"
    echo -e "     ${YELLOW}Обязательно:${NC} ${GREEN}WEB_API_ENABLED=true${NC} — включить веб-сервер"
    echo -e "     ${YELLOW}Обязательно:${NC} ${GREEN}CABINET_ENABLED=true${NC} — включить Cabinet API"
    echo -e "     ${YELLOW}Обязательно:${NC} ${GREEN}CABINET_ALLOWED_ORIGINS${NC} — домен кабинета (https://cabinet.ваш-домен.com)"
    echo -e "     ${YELLOW}Обязательно:${NC} ${GREEN}REMNAWAVE_API_URL${NC} — URL панели Remnawave"
    echo -e "     ${YELLOW}Обязательно:${NC} ${GREEN}REMNAWAVE_API_KEY${NC} — API ключ панели Remnawave"
    echo -e "  2) Заполнить ${CYAN}${CABINET_DIR}/.env${NC}"
    echo -e "     ${YELLOW}Обязательно:${NC} ${GREEN}VITE_TELEGRAM_BOT_USERNAME${NC} — username бота (без @)"
    echo -e "  3) Заменить домены в ${CYAN}${CADDYFILE}${NC}"
    echo -e "     Заменить ${RED}bot.example.com${NC} и ${RED}cabinet.example.com${NC} на ваши реальные домены"
    echo -e "  4) Затем выбрать ${BOLD}запуск проекта${NC} в главном меню"
    echo -e "\n  ${GREEN}Подсказка:${NC} Используйте '⚙️ Редактор конфигураций → Мастер настройки' для удобной настройки"
    echo
}

install_project() {
    _menu_header " 🚀 ST VILLAGE | МАСТЕР УСТАНОВКИ v${PANEL_VERSION} 🚀 "
    echo -e "${YELLOW}Запускаю первичное развертывание проекта...${NC}\n"

    if ! check_ports "install"; then
        err "Установка отменена из-за конфликтов портов."; pause; return 1
    fi

    ensure_dirs
    ensure_dependencies
    clone_or_update_repo "$BOT_REPO" "$BOT_DIR" "Bedolaga Bot"
    clone_or_update_repo "$CABINET_REPO" "$CABINET_DIR" "Bedolaga Cabinet"
    prepare_env_files
    write_default_caddy_files
    normalize_project_files

    ok "Файлы проекта подготовлены."
    show_post_install_steps
    pause
}

# === PROJECT VALIDATION & NETWORK ===

validate_project_files() {
    local failed=0
    [[ -f "$BOT_COMPOSE_FILE" ]] || { err "Не найден ${BOT_COMPOSE_FILE}"; failed=1; }
    [[ -f "$CABINET_COMPOSE_FILE" ]] || { err "Не найден ${CABINET_COMPOSE_FILE}"; failed=1; }
    [[ -f "$CABINET_OVERRIDE_FILE" ]] || write_cabinet_override
    [[ -f "$CADDY_COMPOSE_FILE" ]] || write_default_caddy_files
    [[ -f "$CADDYFILE" ]] || write_default_caddy_files
    return "$failed"
}

ensure_bot_network() {
    docker network inspect remnawave-network >/dev/null 2>&1 && return 0
    log "Сеть remnawave-network не найдена. Создаю..."
    docker network create remnawave-network >/dev/null 2>&1 || { err "Не удалось создать сеть remnawave-network."; return 1; }
    ok "Сеть remnawave-network создана."
}

# === VERSION CHECK & SYSTEM INFO ===

check_versions() {
    BOT_VER_TXT="$(_get_ver_txt "$BOT_DIR" "full")"
    CAB_VER_TXT="$(_get_ver_txt "$CABINET_DIR" "full")"
    printf '%s\n%s\n%s' "$BOT_VER_TXT" "$CAB_VER_TXT" "$(date +%s)" > "$VERSION_CACHE_FILE" 2>/dev/null || true
}

check_versions_cached() {
    if [[ -f "$VERSION_CACHE_FILE" ]]; then
        local cache_time=0 now=0
        cache_time="$(sed -n '3p' "$VERSION_CACHE_FILE" 2>/dev/null || echo 0)"
        now="$(date +%s)"
        if [[ $((now - cache_time)) -lt "$VERSION_CACHE_TTL" ]]; then
            BOT_VER_TXT="$(sed -n '1p' "$VERSION_CACHE_FILE" 2>/dev/null || true)"
            CAB_VER_TXT="$(sed -n '2p' "$VERSION_CACHE_FILE" 2>/dev/null || true)"
            return 0
        fi
    fi
    BOT_VER_TXT="$(_get_ver_txt "$BOT_DIR" "fast")"
    CAB_VER_TXT="$(_get_ver_txt "$CABINET_DIR" "fast")"
}

get_system_info() {
    OS_NAME="$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d '"' -f 2 || echo unknown)"
    UPTIME_TXT="$(uptime -p 2>/dev/null | sed 's/^up //' || echo unknown)"
    RAM_TXT="$(free -m | awk 'NR==2 {printf "%s / %s MB (%.1f%%)", $3, $2, ($3*100)/$2}')"
    DISK_TXT="$(df -h / | awk '$NF=="/" {printf "%s / %s (%s)", $3, $2, $5}')"

    if command_exists docker; then
        local running total
        running="$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')"
        total="$(docker ps -a -q 2>/dev/null | wc -l | tr -d ' ')"
        if [[ "$total" == "0" ]]; then
            DOCKER_STAT="${YELLOW}Контейнеры не созданы${NC}"
        elif [[ "$running" == "$total" ]]; then
            DOCKER_STAT="${GREEN}Запущено ${running} из ${total}${NC}"
        else
            DOCKER_STAT="${RED}Запущено ${running} из ${total}${NC}"
        fi
    else
        DOCKER_STAT="${RED}Docker не установлен${NC}"
    fi
}

check_health_quick() {
    command_exists docker || { BOT_HEALTH="${RED}⬤ Не запущен${NC}"; CAB_HEALTH="$BOT_HEALTH"; CADDY_HEALTH="$BOT_HEALTH"; return 0; }

    local state=""
    state="$(_container_state remnawave_bot)"
    BOT_HEALTH="$(_state_icon "$state" "dot")"

    state="$(_container_state cabinet_frontend)"
    [[ -n "$state" ]] || state="$(_container_state cabinet-frontend)"
    CAB_HEALTH="$(_state_icon "$state" "dot")"

    state="$(_container_state st_village_caddy)"
    CADDY_HEALTH="$(_state_icon "$state" "dot")"
}

# === .ENV VALIDATION ===

validate_env_files() {
    local warnings=0
    local bot_env="${BOT_DIR}/.env" cab_env="${CABINET_DIR}/.env"

    if [[ -f "$bot_env" ]]; then
        local val=""
        for key in BOT_TOKEN ADMIN_IDS REMNAWAVE_API_URL REMNAWAVE_API_KEY; do
            val="$(read_env_value "$bot_env" "$key")"
            [[ -n "$val" ]] || { warn "${key} не задан в ${bot_env}"; warnings=$((warnings + 1)); }
        done
        val="$(read_env_value "$bot_env" "WEB_API_ENABLED")"
        [[ "$val" == "true" ]] || { warn "WEB_API_ENABLED != true — веб-сервер отключен"; warnings=$((warnings + 1)); }
        val="$(read_env_value "$bot_env" "CABINET_ENABLED")"
        [[ "$val" == "true" ]] || { warn "CABINET_ENABLED != true — Cabinet API отключен"; warnings=$((warnings + 1)); }
    else
        warn "Файл ${bot_env} не найден"; warnings=$((warnings + 1))
    fi

    if [[ -f "$cab_env" ]]; then
        local vite_user=""
        vite_user="$(read_env_value "$cab_env" "VITE_TELEGRAM_BOT_USERNAME")"
        [[ -n "$vite_user" ]] || { warn "VITE_TELEGRAM_BOT_USERNAME не задан в ${cab_env}"; warnings=$((warnings + 1)); }
    fi

    if [[ "$warnings" -gt 0 ]]; then
        warn "Найдено предупреждений: ${warnings}"
    else
        ok "Конфигурация выглядит корректно."
    fi
    return 0
}

# === .ENV WIZARDS ===

env_wizard_bot() {
    _menu_header "🧙 МАСТЕР НАСТРОЙКИ БОТА"
    echo -e "${YELLOW}Введите значения. Enter — оставить текущее.${NC}\n"

    local bot_env="${BOT_DIR}/.env"
    [[ -f "$bot_env" ]] || { err "Файл ${bot_env} не найден. Сначала установите проект."; pause; return 1; }

    local val=""

    # BOT_TOKEN — с валидацией
    local current="" display=""
    current="$(read_env_value "$bot_env" "BOT_TOKEN")"
    display="${current:-не задан}"
    read_tty val "  ${GREEN}BOT_TOKEN${NC} [${display}]: "
    if [[ -n "$val" ]]; then
        if [[ ! "$val" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
            warn "Формат токена не похож на валидный (ожидается: 123456:ABC-DEF...)"
            if ! confirm "Сохранить всё равно?"; then val=""; fi
        fi
        [[ -n "$val" ]] && set_env_value "$bot_env" "BOT_TOKEN" "$val"
    fi

    # ADMIN_IDS — с валидацией
    current="$(read_env_value "$bot_env" "ADMIN_IDS")"
    display="${current:-не задан}"
    read_tty val "  ${GREEN}ADMIN_IDS${NC} (через запятую) [${display}]: "
    if [[ -n "$val" ]]; then
        if [[ ! "$val" =~ ^[0-9,\ ]+$ ]]; then
            warn "ADMIN_IDS должен содержать только цифры и запятые"
        else
            set_env_value "$bot_env" "ADMIN_IDS" "$val"
        fi
    fi

    # Простые поля
    _prompt_env "$bot_env" "WEB_API_ENABLED" "WEB_API_ENABLED" "false" >/dev/null
    _prompt_env "$bot_env" "CABINET_ENABLED" "CABINET_ENABLED" "false" >/dev/null
    _prompt_env "$bot_env" "CABINET_ALLOWED_ORIGINS" "CABINET_ALLOWED_ORIGINS (https://cabinet.domain.com)" >/dev/null

    # CABINET_JWT_SECRET — специальная логика
    current="$(read_env_value "$bot_env" "CABINET_JWT_SECRET")"
    if [[ -z "$current" ]]; then
        local generated=""
        generated="$(generate_secret)"
        echo -e "  ${YELLOW}CABINET_JWT_SECRET не задан. Сгенерирован: ${GREEN}${generated}${NC}"
        if confirm "Использовать сгенерированный секрет?"; then
            set_env_value "$bot_env" "CABINET_JWT_SECRET" "$generated"
        else
            read_tty val "  ${GREEN}CABINET_JWT_SECRET${NC}: "
            [[ -n "$val" ]] && set_env_value "$bot_env" "CABINET_JWT_SECRET" "$val"
        fi
    else
        display="${current:0:8}..."
        read_tty val "  ${GREEN}CABINET_JWT_SECRET${NC} [${display}]: "
        [[ -n "$val" ]] && set_env_value "$bot_env" "CABINET_JWT_SECRET" "$val"
    fi

    _prompt_env "$bot_env" "REMNAWAVE_API_URL" "REMNAWAVE_API_URL" >/dev/null
    _prompt_env "$bot_env" "REMNAWAVE_API_KEY" "REMNAWAVE_API_KEY" >/dev/null

    echo
    ok "Настройки бота сохранены."
    pause
}

env_wizard_cabinet() {
    _menu_header "🧙 МАСТЕР НАСТРОЙКИ КАБИНЕТА"
    echo -e "${YELLOW}Введите значения. Enter — оставить текущее.${NC}\n"

    local cab_env="${CABINET_DIR}/.env"
    [[ -f "$cab_env" ]] || { err "Файл ${cab_env} не найден. Сначала установите проект."; pause; return 1; }

    local val=""

    # VITE_TELEGRAM_BOT_USERNAME — с валидацией
    local current="" display=""
    current="$(read_env_value "$cab_env" "VITE_TELEGRAM_BOT_USERNAME")"
    display="${current:-не задан}"
    read_tty val "  ${GREEN}VITE_TELEGRAM_BOT_USERNAME${NC} (без @) [${display}]: "
    if [[ -n "$val" ]]; then
        val="${val#@}"
        if [[ "$val" =~ [[:space:]] ]]; then
            warn "Username не должен содержать пробелов"
        else
            set_env_value "$cab_env" "VITE_TELEGRAM_BOT_USERNAME" "$val"
        fi
    fi

    _prompt_env "$cab_env" "VITE_API_URL" "VITE_API_URL" "/api" >/dev/null
    _prompt_env "$cab_env" "VITE_APP_NAME" "VITE_APP_NAME" "Cabinet" >/dev/null

    echo
    ok "Настройки кабинета сохранены."
    pause
}

domain_wizard() {
    _menu_header "🌐 МАСТЕР НАСТРОЙКИ ДОМЕНОВ"
    [[ -f "$CADDYFILE" ]] || { err "Caddyfile не найден. Сначала установите проект."; pause; return 1; }

    local bot_domain="" cab_domain=""
    echo -e "${YELLOW}Текущие домены в Caddyfile:${NC}"
    local domains=""
    domains="$(parse_caddyfile_domains)"
    if [[ -n "$domains" ]]; then
        while IFS= read -r d; do echo -e "  • ${CYAN}${d}${NC}"; done <<< "$domains"
    else
        echo -e "  ${RED}Домены не найдены${NC}"
    fi
    echo

    read_tty bot_domain "  ${GREEN}Домен для бота${NC} (например bot.mydomain.com): "
    read_tty cab_domain "  ${GREEN}Домен для кабинета${NC} (например cabinet.mydomain.com): "

    if [[ -z "$bot_domain" && -z "$cab_domain" ]]; then
        warn "Домены не указаны. Ничего не изменено."; pause; return 0
    fi

    if [[ -n "$bot_domain" ]]; then
        sed -i "s|bot\.example\.com|${bot_domain}|g" "$CADDYFILE"
        ok "Домен бота: ${bot_domain}"
    fi
    if [[ -n "$cab_domain" ]]; then
        sed -i "s|cabinet\.example\.com|${cab_domain}|g" "$CADDYFILE"
        ok "Домен кабинета: ${cab_domain}"
        if [[ -f "${BOT_DIR}/.env" ]]; then
            set_env_value "${BOT_DIR}/.env" "CABINET_ALLOWED_ORIGINS" "https://${cab_domain}"
            ok "CABINET_ALLOWED_ORIGINS обновлен: https://${cab_domain}"
        fi
    fi

    if [[ -n "$bot_domain" || -n "$cab_domain" ]]; then
        if confirm "Перезагрузить Caddy сейчас?"; then
            dc_caddy up -d --force-recreate >/dev/null 2>&1 && ok "Caddy перезагружен." || warn "Не удалось перезагрузить Caddy."
        fi
    fi
    pause
}

# === DIAGNOSTICS ===

verify_domains_resolve() {
    local domains="" server_ip="" all_ok=0
    domains="$(parse_caddyfile_domains 2>/dev/null || true)"
    [[ -n "$domains" ]] || return 0
    server_ip="$(get_server_ip)"
    [[ "$server_ip" != "unknown" ]] || return 0

    while IFS= read -r domain; do
        [[ -n "$domain" ]] || continue
        local resolved=""
        resolved="$(_resolve_domain "$domain")"
        if [[ -z "$resolved" ]]; then
            warn "Домен ${domain} не резолвится! DNS не настроен."; all_ok=1
        elif [[ "$resolved" != "$server_ip" ]]; then
            warn "Домен ${domain} → ${resolved} (ожидался ${server_ip})"; all_ok=1
        fi
    done <<< "$domains"

    if [[ "$all_ok" -ne 0 ]]; then
        echo
        warn "DNS настроен некорректно. Caddy не сможет получить SSL-сертификаты!"
        echo -e "  ${YELLOW}Убедитесь, что A-записи доменов указывают на ${CYAN}${server_ip}${NC}"
        echo -e "  ${YELLOW}После изменения DNS подождите 5-10 минут для распространения.${NC}"
        echo
        if ! confirm "Продолжить запуск несмотря на проблемы DNS?"; then return 1; fi
    fi
    return 0
}

check_dns() {
    echo -e "\n${BOLD}🌐 ПРОВЕРКА DNS${NC}"
    echo -e "${CYAN}----------------------------------------${NC}"
    local server_ip=""
    server_ip="$(get_server_ip)"
    echo -e "IP сервера: ${CYAN}${server_ip}${NC}\n"

    local domains=""
    domains="$(parse_caddyfile_domains)"
    if [[ -z "$domains" ]]; then warn "Не удалось извлечь домены из Caddyfile."; return 0; fi

    while IFS= read -r domain; do
        [[ -n "$domain" ]] || continue
        local resolved=""
        resolved="$(_resolve_domain "$domain")"
        if [[ -z "$resolved" ]]; then
            echo -e "  ${RED}✗${NC} ${domain} — ${RED}не резолвится${NC}"
        elif [[ "$resolved" == "$server_ip" ]]; then
            echo -e "  ${GREEN}✓${NC} ${domain} → ${resolved} ${GREEN}(совпадает)${NC}"
        else
            echo -e "  ${YELLOW}!${NC} ${domain} → ${resolved} ${YELLOW}(ожидался ${server_ip})${NC}"
        fi
    done <<< "$domains"
}

check_ports() {
    # $1: "install" — расширенный режим с рекомендациями, иначе обычный
    local mode="${1:-normal}"
    echo -e "\n${BOLD}🔌 ПРОВЕРКА ПОРТОВ${NC}"
    echo -e "${CYAN}----------------------------------------${NC}"

    local port_info="" has_conflicts=0 conflicts=()

    for port in "${HTTP_PORT}" "${HTTPS_PORT}"; do
        port_info="$(ss -tlnp 2>/dev/null | grep ":${port} " || true)"
        if [[ -z "$port_info" ]]; then
            echo -e "  Порт ${CYAN}${port}${NC}: ${GREEN}свободен${NC}"
        elif echo "$port_info" | grep -qi "caddy"; then
            echo -e "  Порт ${CYAN}${port}${NC}: ${GREEN}Caddy${NC}"
        else
            local proc=""
            proc="$(echo "$port_info" | grep -oP 'users:\(\("\K[^"]+' || echo "неизвестный процесс")"
            echo -e "  Порт ${CYAN}${port}${NC}: ${RED}занят (${proc})${NC}"
            has_conflicts=1
            conflicts+=("$port:$proc")
        fi
    done

    if [[ "$mode" == "install" && ${#conflicts[@]} -gt 0 ]]; then
        echo
        warn "Обнаружены конфликты портов!"
        echo -e "${YELLOW}Следующие порты заняты другими процессами:${NC}"
        for conflict in "${conflicts[@]}"; do echo -e "  - ${conflict}"; done
        echo
        echo -e "${YELLOW}Рекомендации:${NC}"
        echo -e "  1. Остановите конфликтующие сервисы"
        echo -e "  2. Или используйте другие порты через переменные окружения:"
        echo -e "     ${CYAN}ST_VILLAGE_HTTP_PORT=8080 ST_VILLAGE_HTTPS_PORT=8443 ./st_village.sh${NC}"
        echo
        if ! confirm "Продолжить установку несмотря на конфликты?"; then return 1; fi
    fi

    return "$has_conflicts"
}

health_check_full() {
    _menu_header "🏥 ПОЛНАЯ ДИАГНОСТИКА СЕРВИСОВ"
    command_exists docker || { err "Docker не установлен."; pause; return 1; }

    echo -e "\n${BOLD}🐳 СОСТОЯНИЕ КОНТЕЙНЕРОВ${NC}"
    echo -e "${CYAN}----------------------------------------${NC}"

    local state=""
    state="$(_container_state remnawave_bot)"
    echo -e "  Bedolaga Bot:     $(_state_icon "$state")"

    state="$(_container_state cabinet_frontend)"
    [[ -n "$state" ]] || state="$(_container_state cabinet-frontend)"
    echo -e "  Cabinet Frontend: $(_state_icon "$state")"

    state="$(_container_state st_village_caddy)"
    echo -e "  Caddy:            $(_state_icon "$state")"

    # HTTP checks on domains
    echo -e "\n${BOLD}🌐 HTTP-ПРОВЕРКИ${NC}"
    echo -e "${CYAN}----------------------------------------${NC}"

    local domains="" http_code=""
    domains="$(parse_caddyfile_domains)"
    if [[ -n "$domains" ]]; then
        while IFS= read -r domain; do
            [[ -n "$domain" ]] || continue
            http_code="$(curl -sf -o /dev/null -w '%{http_code}' --connect-timeout 5 "https://${domain}/" 2>/dev/null || echo "000")"
            if [[ "${http_code:-000}" != "000" ]]; then
                echo -e "  https://${domain}: ${GREEN}${http_code}${NC}"
            else
                echo -e "  https://${domain}: ${RED}недоступен${NC}"
            fi
        done <<< "$domains"
    else
        warn "Домены не настроены в Caddyfile."
    fi

    check_dns
    check_ports
    pause
}

check_ssl_certs() {
    echo -e "\n${BOLD}🔒 SSL-СЕРТИФИКАТЫ${NC}"
    echo -e "${CYAN}----------------------------------------${NC}"

    local domains=""
    domains="$(parse_caddyfile_domains)"
    if [[ -z "$domains" ]]; then warn "Не удалось извлечь домены из Caddyfile."; return 0; fi

    while IFS= read -r domain; do
        [[ -n "$domain" ]] || continue
        local days_left=""
        days_left="$(_ssl_days_left "$domain")"
        if [[ "$days_left" -ge 0 ]]; then
            local expiry=""
            expiry="$(echo | openssl s_client -connect "${domain}:443" -servername "$domain" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d '=' -f 2 || true)"
            if [[ "$days_left" -lt 7 ]]; then
                echo -e "  ${domain}: ${RED}${expiry} (осталось ${days_left} дн.)${NC}"
            elif [[ "$days_left" -lt 30 ]]; then
                echo -e "  ${domain}: ${YELLOW}${expiry} (осталось ${days_left} дн.)${NC}"
            else
                echo -e "  ${domain}: ${GREEN}${expiry} (осталось ${days_left} дн.)${NC}"
            fi
        else
            echo -e "  ${domain}: ${RED}не удалось проверить${NC}"
        fi
    done <<< "$domains"
}

show_container_stats() {
    echo -e "\n${BOLD}📊 РЕСУРСЫ КОНТЕЙНЕРОВ${NC}"
    echo -e "${CYAN}----------------------------------------${NC}"
    command_exists docker || { err "Docker не установлен."; return 0; }
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" 2>/dev/null \
        | grep -E "^(NAME|remnawave_bot|cabinet|st_village_caddy)" || warn "Нет запущенных контейнеров проекта."
}

# === START / STOP / RESTART ===

start_project() {
    validate_project_files || { pause; return 1; }
    ensure_dependencies
    normalize_project_files

    echo -e "\n${BOLD}📋 Проверка конфигурации:${NC}"
    validate_env_files
    echo
    check_ports
    echo

    log "Запускаю Bedolaga Bot..."
    dc_bot up -d --build || { err "Не удалось запустить Bot."; pause; return 1; }
    ensure_bot_network || { err "После запуска бота сеть remnawave-network не появилась."; pause; return 1; }

    log "Запускаю Bedolaga Cabinet..."
    dc_cabinet up -d --build || { err "Не удалось запустить Cabinet."; pause; return 1; }

    verify_domains_resolve || { pause; return 1; }

    log "Запускаю Caddy..."
    dc_caddy up -d || { err "Не удалось запустить Caddy."; pause; return 1; }

    ok "Проект успешно запущен."
    send_telegram_notification "✅ Проект запущен"
    pause
}

stop_project() {
    _compose_stop_all
    ok "Проект остановлен."
    pause
}

restart_component() {
    local component="$1" title="$2"
    case "$component" in
        bot)     log "Перезапуск бота..."; dc_bot restart || { err "Не удалось перезапустить бот."; return 1; } ;;
        cabinet) log "Перезапуск кабинета..."; dc_cabinet restart || { err "Не удалось перезапустить кабинет."; return 1; } ;;
        caddy)   log "Перезапуск Caddy..."; dc_caddy restart || { err "Не удалось перезапустить Caddy."; return 1; } ;;
        all)
            log "Перезапуск всех компонентов..."
            dc_bot restart || warn "Не удалось перезапустить бот."
            dc_cabinet restart || warn "Не удалось перезапустить кабинет."
            dc_caddy restart || warn "Не удалось перезапустить Caddy."
            ;;
        *) err "Неизвестный компонент: ${component}"; return 1 ;;
    esac
    ok "${title} перезапущен."
}

rebuild_component() {
    local component="$1"
    case "$component" in
        bot) dc_bot up -d --build ;;
        cabinet) write_cabinet_override; dc_cabinet up -d --build ;;
        caddy) dc_caddy up -d --force-recreate ;;
        *) err "Неизвестный компонент: ${component}"; return 1 ;;
    esac
}

# === UPDATE & ROLLBACK ===

update_component() {
    local component="$1" title="$2" target_dir old_commit new_commit

    case "$component" in
        bot) target_dir="$BOT_DIR" ;;
        cabinet) target_dir="$CABINET_DIR" ;;
        *) err "Неизвестный компонент: ${component}"; pause; return 1 ;;
    esac

    [[ -d "${target_dir}/.git" ]] || { err "${title} не установлен."; pause; return 1; }

    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${BOLD}[🔄] ОБНОВЛЕНИЕ: ${title}${NC}"
    echo -e "${CYAN}========================================${NC}"

    old_commit="$(git -C "$target_dir" rev-parse --short HEAD 2>/dev/null || true)"
    [[ -n "$old_commit" ]] || { err "Не удалось определить текущий commit."; pause; return 1; }

    printf '%s\n' "$old_commit" > "${target_dir}/.last_commit"
    log "Текущая версия: ${old_commit}"

    git -C "$target_dir" fetch origin main >/dev/null 2>&1 || { err "Не удалось получить обновления."; pause; return 1; }
    git -C "$target_dir" reset --hard origin/main >/dev/null 2>&1 || { err "Не удалось обновить код."; pause; return 1; }

    new_commit="$(git -C "$target_dir" rev-parse --short HEAD 2>/dev/null || true)"
    normalize_project_files

    if [[ "$old_commit" == "$new_commit" ]]; then
        ok "Обновлений нет. Уже установлена последняя версия."; pause; return 0
    fi

    rebuild_component "$component" || { pause; return 1; }
    ok "${title} обновлен: ${old_commit} → ${new_commit}"
    send_telegram_notification "🔄 ${title} обновлен: ${old_commit} → ${new_commit}"
    pause
}

rollback_component() {
    local component="$1" title="$2" target_dir last_commit
    case "$component" in
        bot) target_dir="$BOT_DIR" ;;
        cabinet) target_dir="$CABINET_DIR" ;;
        *) err "Неизвестный компонент: ${component}"; pause; return 1 ;;
    esac

    [[ -f "${target_dir}/.last_commit" ]] || { err "Нет сохраненной версии для отката ${title}."; pause; return 1; }
    last_commit="$(tr -d '\r\n' < "${target_dir}/.last_commit")"
    [[ -n "$last_commit" ]] || { err "Файл .last_commit пустой."; pause; return 1; }

    git -C "$target_dir" fetch origin main >/dev/null 2>&1 || true
    git -C "$target_dir" reset --hard "$last_commit" >/dev/null 2>&1 || { err "Не удалось откатить ${title}."; pause; return 1; }

    normalize_project_files
    rebuild_component "$component" || { pause; return 1; }
    ok "${title} откатен на commit ${last_commit}"
    pause
}

# === BACKUP ===

backup_project() {
    mkdir -p "$BACKUP_DIR"
    local prefix="${1:-manual}" ts archive size
    ts="$(date +"%Y-%m-%d_%H-%M-%S")"
    archive="${BACKUP_DIR}/backup_${prefix}_${ts}.tar.gz"

    tar \
        --exclude='./bot/.venv' --exclude='./bot/__pycache__' \
        --exclude='./bot/node_modules' --exclude='./cabinet/node_modules' \
        --exclude='./cabinet/.svelte-kit' --exclude='./cabinet/dist' \
        --exclude='./backups' --exclude='./.git' \
        -czf "$archive" -C "$BASE_DIR" . || return 1

    size="$(du -sh "$archive" | awk '{print $1}')"
    ok "Бэкап создан: ${archive} (${size})"
    send_telegram_notification "💾 Бэкап создан: backup_${prefix}_${ts}.tar.gz (${size})"
}

rotate_auto_backups() {
    ls -tp "${BACKUP_DIR}"/backup_auto_*.tar.gz 2>/dev/null | grep -v '/$' | tail -n +8 | xargs -r rm -f --
}

list_backups() {
    local backups=() i=1
    while IFS= read -r -d '' f; do backups+=("$f"); done < <(find "$BACKUP_DIR" -maxdepth 1 -name "backup_*.tar.gz" -print0 2>/dev/null | sort -z -r)

    if [[ ${#backups[@]} -eq 0 ]]; then warn "Бэкапы не найдены в ${BACKUP_DIR}"; return 1; fi

    echo -e "\n${BOLD}📦 ДОСТУПНЫЕ БЭКАПЫ:${NC}"
    echo -e "${CYAN}----------------------------------------${NC}"
    for f in "${backups[@]}"; do
        local fname="" bsize="" fdate=""
        fname="$(basename "$f")"
        bsize="$(du -sh "$f" 2>/dev/null | awk '{print $1}')"
        fdate="$(stat -c '%y' "$f" 2>/dev/null | cut -d '.' -f 1 || echo "unknown")"
        echo -e "  ${GREEN}${i})${NC} ${fname} ${CYAN}(${bsize}, ${fdate})${NC}"
        i=$((i + 1))
    done
    echo

    STV_BACKUP_LIST_TMP="$(mktemp)"
    printf '%s\n' "${backups[@]}" > "$STV_BACKUP_LIST_TMP"
    return 0
}

restore_backup() {
    list_backups || { pause; return 1; }

    local backups=()
    while IFS= read -r line; do backups+=("$line"); done < "$STV_BACKUP_LIST_TMP"
    rm -f "$STV_BACKUP_LIST_TMP"

    local choice=""
    read_tty choice "  ${YELLOW}Номер бэкапа для восстановления (0 - отмена): ${NC}"
    if [[ "$choice" == "0" || -z "$choice" ]]; then return 0; fi
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt ${#backups[@]} ]]; then
        err "Неверный номер."; pause; return 1
    fi

    local selected="${backups[$((choice - 1))]}" fname=""
    fname="$(basename "$selected")"

    if ! confirm "Восстановить из ${fname}? Текущие файлы будут перезаписаны!"; then return 0; fi

    log "Создаю бэкап текущего состояния перед восстановлением..."
    backup_project "pre_restore" || warn "Не удалось создать бэкап текущего состояния."

    log "Останавливаю сервисы..."
    _compose_stop_all

    log "Распаковываю ${fname}..."
    tar -xzf "$selected" -C "$BASE_DIR" || { err "Не удалось распаковать бэкап."; pause; return 1; }
    normalize_project_files

    ok "Восстановление завершено."
    if confirm "Запустить проект сейчас?"; then start_project; else pause; fi
}

# === MIGRATION ===

export_migration() {
    mkdir -p "$BACKUP_DIR"
    local ts archive
    ts="$(date +"%Y-%m-%d_%H-%M-%S")"
    archive="${BACKUP_DIR}/migration_${ts}.tar.gz"

    local files_to_pack=()
    [[ -f "${BOT_DIR}/.env" ]] && files_to_pack+=("./bot/.env")
    [[ -f "${CABINET_DIR}/.env" ]] && files_to_pack+=("./cabinet/.env")
    [[ -f "$CADDYFILE" ]] && files_to_pack+=("./caddy/Caddyfile")
    [[ -f "$CABINET_OVERRIDE_FILE" ]] && files_to_pack+=("./cabinet/docker-compose.override.yml")
    [[ -f "$CADDY_COMPOSE_FILE" ]] && files_to_pack+=("./caddy/docker-compose.yml")

    if [[ ${#files_to_pack[@]} -eq 0 ]]; then err "Нет файлов для экспорта."; pause; return 1; fi

    tar -czf "$archive" -C "$BASE_DIR" "${files_to_pack[@]}" || { err "Не удалось создать архив миграции."; pause; return 1; }

    local msize=""
    msize="$(du -sh "$archive" | awk '{print $1}')"
    ok "Архив миграции создан: ${archive} (${msize})"
    echo -e "\n${YELLOW}Для переноса на другой сервер:${NC}"
    echo -e "  1) Скопируйте ${CYAN}${archive}${NC} на новый сервер"
    echo -e "  2) Установите панель: ${CYAN}bash <(curl -fsSL ${SCRIPT_URL})${NC}"
    echo -e "  3) Выберите '🛡 Система и безопасность → 🚚 Миграция → Импорт'"
    echo -e "  4) Укажите путь к архиву"
    pause
}

import_migration() {
    local archive_path=""
    read_tty archive_path "  ${YELLOW}Путь к архиву миграции: ${NC}"
    [[ -n "$archive_path" ]] || { warn "Путь не указан."; pause; return 0; }
    [[ -f "$archive_path" ]] || { err "Файл не найден: ${archive_path}"; pause; return 1; }

    if ! confirm "Импортировать конфигурации из $(basename "$archive_path")? Текущие конфиги будут перезаписаны."; then return 0; fi

    ensure_dirs
    if [[ ! -d "${BOT_DIR}/.git" || ! -d "${CABINET_DIR}/.git" ]]; then
        log "Репозитории не найдены. Устанавливаю..."
        ensure_dependencies
        clone_or_update_repo "$BOT_REPO" "$BOT_DIR" "Bedolaga Bot"
        clone_or_update_repo "$CABINET_REPO" "$CABINET_DIR" "Bedolaga Cabinet"
    fi

    log "Распаковываю конфигурации..."
    tar -xzf "$archive_path" -C "$BASE_DIR" || { err "Не удалось распаковать архив."; pause; return 1; }
    normalize_project_files
    ok "Конфигурации импортированы."
    if confirm "Запустить проект сейчас?"; then start_project; else pause; fi
}

# === SECURITY ===

setup_ufw() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${BOLD}🔥 НАСТРОЙКА UFW (ФАЙРВОЛ)${NC}"
    echo -e "${CYAN}========================================${NC}"

    if ! command_exists ufw; then
        log "Устанавливаю UFW..."
        apt-get install -y ufw >/dev/null 2>&1 || { err "Не удалось установить UFW."; pause; return 1; }
    fi

    echo -e "\n${BOLD}Текущий статус:${NC}"
    ufw status 2>/dev/null || echo -e "  ${YELLOW}UFW не настроен${NC}"
    echo

    if ! confirm "Настроить UFW? Будут открыты порты: SSH (22), HTTP (80), HTTPS (443). Остальные входящие будут заблокированы."; then return 0; fi

    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1
    ufw allow ssh >/dev/null 2>&1
    ufw allow 80/tcp >/dev/null 2>&1
    ufw allow 443/tcp >/dev/null 2>&1
    ufw --force enable >/dev/null 2>&1

    ok "UFW настроен и активирован."
    echo -e "\n${BOLD}Статус UFW:${NC}"
    ufw status verbose 2>/dev/null || true
    pause
}

setup_fail2ban() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${BOLD}🛡 УСТАНОВКА FAIL2BAN${NC}"
    echo -e "${CYAN}========================================${NC}"

    if ! command_exists fail2ban-client; then
        log "Устанавливаю Fail2ban..."
        apt-get install -y fail2ban >/dev/null 2>&1 || { err "Не удалось установить Fail2ban."; pause; return 1; }
    fi

    echo -e "\n${BOLD}Текущий статус:${NC}"
    fail2ban-client status 2>/dev/null || echo -e "  ${YELLOW}Fail2ban не настроен${NC}"
    echo

    if ! confirm "Настроить Fail2ban для защиты SSH? (maxretry=5, bantime=1 час)"; then return 0; fi

    cat > /etc/fail2ban/jail.local <<'EOF'
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 3600
findtime = 600
EOF

    systemctl enable fail2ban >/dev/null 2>&1 || true
    systemctl restart fail2ban >/dev/null 2>&1 || { err "Не удалось запустить Fail2ban."; pause; return 1; }

    ok "Fail2ban настроен и запущен."
    echo -e "\n${BOLD}Статус Fail2ban:${NC}"
    fail2ban-client status sshd 2>/dev/null || fail2ban-client status 2>/dev/null || true
    pause
}

# === SWAP MANAGEMENT ===

manage_swap_menu() {
    _menu_header "💿 УПРАВЛЕНИЕ SWAP"

    echo -e "\n${BOLD}Текущее состояние:${NC}"
    local swap_info=""
    swap_info="$(swapon --show 2>/dev/null || true)"
    if [[ -n "$swap_info" ]]; then echo "$swap_info"; else echo -e "  ${YELLOW}Swap не активен${NC}"; fi

    local total_ram=""
    total_ram="$(free -m 2>/dev/null | awk 'NR==2{print $2}' || echo "unknown")"
    echo -e "  RAM: ${CYAN}${total_ram} MB${NC}\n"

    echo -e "${GREEN}1.${NC} Создать swap (2 ГБ)"
    echo -e "${GREEN}2.${NC} Создать swap (4 ГБ)"
    echo -e "${RED}3.${NC} Удалить swap"
    echo -e "${RED}0.${NC} Назад"

    local choice=""
    _menu_choice choice

    case "$choice" in
        1|2)
            local swap_size="2G" swap_count=2048
            if [[ "$choice" == "2" ]]; then swap_size="4G"; swap_count=4096; fi
            if [[ -f /swapfile ]]; then warn "Файл /swapfile уже существует. Удалите сначала (пункт 3)."; pause; return 0; fi

            log "Создаю swap ${swap_size}..."
            fallocate -l "$swap_size" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count="$swap_count" status=progress
            chmod 600 /swapfile
            mkswap /swapfile >/dev/null 2>&1
            swapon /swapfile
            if ! grep -q '/swapfile' /etc/fstab 2>/dev/null; then
                echo '/swapfile none swap sw 0 0' >> /etc/fstab
            fi
            ok "Swap ${swap_size} создан и активирован."
            swapon --show 2>/dev/null || true
            pause
            ;;
        3)
            if [[ ! -f /swapfile ]]; then warn "Файл /swapfile не найден."; pause; return 0; fi
            if confirm "Удалить swap?"; then
                swapoff /swapfile 2>/dev/null || true
                rm -f /swapfile
                sed -i '\|/swapfile|d' /etc/fstab 2>/dev/null || true
                ok "Swap удален."
            fi
            pause
            ;;
        0) return 0 ;;
        *) warn "Неизвестная команда."; sleep 1 ;;
    esac
}

# === FULL UNINSTALL ===

full_uninstall() {
    _menu_header "🗑 ПОЛНОЕ УДАЛЕНИЕ ПРОЕКТА"

    echo -e "${YELLOW}Будут удалены:${NC}"
    echo -e "  • Все контейнеры и Docker-тома проекта"
    echo -e "  • Директории: ${BOT_DIR}, ${CABINET_DIR}, ${CADDY_DIR}"
    echo -e "  • Сеть remnawave-network"
    echo -e "  • Cron-задачи панели"
    echo -e "${GREEN}НЕ будут удалены:${NC}"
    echo -e "  • Бэкапы (${BACKUP_DIR})"
    echo -e "  • Сам скрипт (${DEFAULT_INSTALL_PATH})"
    echo

    if ! confirm "Вы уверены? Это действие НЕОБРАТИМО!"; then return 0; fi
    if ! confirm "ТОЧНО уверены? Введите y ещё раз для подтверждения."; then return 0; fi

    log "Останавливаю и удаляю контейнеры..."
    _compose_down_all

    log "Удаляю сеть..."
    docker network rm remnawave-network >/dev/null 2>&1 || true

    log "Удаляю файлы проекта..."
    rm -rf "$BOT_DIR" "$CABINET_DIR" "$CADDY_DIR"
    rm -f "$NOTIFY_FLAG"

    log "Удаляю cron-задачи..."
    _cron_toggle "cron_backup" "0 3 * * *" "$NOTIFY_FLAG" "disable"
    _cron_toggle "cron_healthcheck" "*/10 * * * *" "$HEALTHCHECK_FLAG" "disable"
    _cron_toggle "cron_watchdog" "*/5 * * * *" "$WATCHDOG_FLAG" "disable"

    ok "Проект полностью удален."
    echo -e "${YELLOW}Бэкапы сохранены в ${BACKUP_DIR}${NC}"
    echo -e "${YELLOW}Скрипт: ${DEFAULT_INSTALL_PATH}${NC}"
    send_telegram_notification "🗑 Проект полностью удален с сервера"
    pause
}

# === NOTIFICATION TOGGLE ===

toggle_notifications() {
    if [[ -f "$NOTIFY_FLAG" ]]; then
        rm -f "$NOTIFY_FLAG"
        ok "Telegram-уведомления отключены."
    else
        local bot_token="" admin_ids=""
        bot_token="$(read_env_value "${BOT_DIR}/.env" "BOT_TOKEN")"
        admin_ids="$(read_env_value "${BOT_DIR}/.env" "ADMIN_IDS")"
        if [[ -z "$bot_token" || -z "$admin_ids" ]]; then
            err "BOT_TOKEN или ADMIN_IDS не задан в ${BOT_DIR}/.env"
            err "Сначала настройте .env бота."
            pause; return 1
        fi
        touch "$NOTIFY_FLAG"
        ok "Telegram-уведомления включены."
        send_telegram_notification "🔔 Уведомления включены. Этот чат будет получать системные уведомления."
    fi
    pause
}

# === SELF-UPDATE ===

persist_self_if_needed() {
    [[ "$SCRIPT_PATH" == "$DEFAULT_INSTALL_PATH" && -f "$DEFAULT_INSTALL_PATH" ]] && return 0
    if [[ ! -f "$DEFAULT_INSTALL_PATH" ]]; then
        warn "Сохраняю рабочую копию панели в ${DEFAULT_INSTALL_PATH}"
        curl -fsSL "$SCRIPT_URL" -o "$DEFAULT_INSTALL_PATH" || return 1
        ensure_unix_file "$DEFAULT_INSTALL_PATH"
        chmod +x "$DEFAULT_INSTALL_PATH"
    fi
}

update_self() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${BOLD}[📦] ОБНОВЛЕНИЕ ПАНЕЛИ${NC}"
    echo -e "${CYAN}========================================${NC}"

    local tmp
    tmp="$(mktemp)"
    curl -fsSL "$SCRIPT_URL" -o "$tmp" || { rm -f "$tmp"; err "Не удалось скачать новую версию панели."; pause; return 1; }
    ensure_unix_file "$tmp"

    if ! grep -qE '^#!/usr/bin/env bash|^#!/bin/bash' "$tmp"; then
        rm -f "$tmp"; err "Скачанный файл не похож на shell-скрипт."; pause; return 1
    fi

    install -m 755 "$tmp" "$DEFAULT_INSTALL_PATH"
    rm -f "$tmp"
    ok "Панель обновлена. Перезапускаю..."
    sleep 1
    exec "$DEFAULT_INSTALL_PATH"
}

# === MENUS ===

config_menu() {
    while true; do
        _menu_header "⚙️ РЕДАКТОР КОНФИГУРАЦИЙ"
        echo -e "${BLUE}[Ручное редактирование]${NC}"
        echo -e "${GREEN}1.${NC} 🤖 Открыть .env бота"
        echo -e "${GREEN}2.${NC} 🖥  Открыть .env кабинета"
        echo -e "${BLUE}3.${NC} 🌐 Открыть Caddyfile"
        echo -e "${BLUE}4.${NC} 🧩 Пересоздать docker-compose.override.yml"
        echo -e "${PURPLE}[Мастера настройки]${NC}"
        echo -e "${YELLOW}5.${NC} 🧙 Мастер настройки бота"
        echo -e "${YELLOW}6.${NC} 🧙 Мастер настройки кабинета"
        echo -e "${YELLOW}7.${NC} 🌐 Мастер настройки доменов"
        echo -e "${CYAN}8.${NC} 📋 Проверить конфигурацию"
        echo -e "${RED}0.${NC} ⬅️ Назад"

        local conf_choice; _menu_choice conf_choice
        case "$conf_choice" in
            1) nano "${BOT_DIR}/.env" ;;
            2) nano "${CABINET_DIR}/.env" ;;
            3) nano "$CADDYFILE"; if confirm "Перезагрузить Caddy сейчас?"; then dc_caddy up -d --force-recreate >/dev/null 2>&1 || true; fi ;;
            4) write_cabinet_override; ok "Файл ${CABINET_OVERRIDE_FILE} пересоздан."; pause ;;
            5) env_wizard_bot ;;
            6) env_wizard_cabinet ;;
            7) domain_wizard ;;
            8) validate_env_files; pause ;;
            0) return ;;
            *) warn "Неизвестная команда."; sleep 1 ;;
        esac
    done
}

show_logs_menu() {
    while true; do
        _menu_header "📋 ПРОСМОТР ЛОГОВ"
        echo -e "${GREEN}1.${NC} Бот"
        echo -e "${GREEN}2.${NC} Кабинет"
        echo -e "${GREEN}3.${NC} Caddy"
        echo -e "${RED}0.${NC} Назад"

        local choice; _menu_choice choice
        case "$choice" in
            1) dc_bot logs -f --tail=100 ;;
            2) dc_cabinet logs -f --tail=100 ;;
            3) dc_caddy logs -f --tail=100 ;;
            0) return ;;
            *) warn "Неизвестная команда."; sleep 1 ;;
        esac
    done
}

restart_menu() {
    while true; do
        _menu_header "🔃 ПЕРЕЗАПУСК КОМПОНЕНТОВ"
        echo -e "${GREEN}1.${NC} 🤖 Перезапуск бота"
        echo -e "${GREEN}2.${NC} 🖥  Перезапуск кабинета"
        echo -e "${BLUE}3.${NC} 🌐 Перезапуск Caddy"
        echo -e "${YELLOW}4.${NC} 🔄 Перезапуск всех"
        echo -e "${RED}0.${NC} ⬅️ Назад"

        local choice; _menu_choice choice
        case "$choice" in
            1) restart_component "bot" "Бот"; pause ;;
            2) restart_component "cabinet" "Кабинет"; pause ;;
            3) restart_component "caddy" "Caddy"; pause ;;
            4) restart_component "all" "Все компоненты"; pause ;;
            0) return ;;
            *) warn "Неизвестная команда."; sleep 1 ;;
        esac
    done
}

diagnostics_menu() {
    while true; do
        _menu_header "🔍 ДИАГНОСТИКА"
        echo -e "${GREEN}1.${NC} 🏥 Полная проверка сервисов"
        echo -e "${GREEN}2.${NC} 🌐 Проверка DNS"
        echo -e "${GREEN}3.${NC} 🔌 Проверка портов"
        echo -e "${BLUE}4.${NC} 🔒 Проверка SSL-сертификатов"
        echo -e "${BLUE}5.${NC} 📊 Ресурсы контейнеров"
        echo -e "${YELLOW}6.${NC} 📋 Проверка конфигурации"
        echo -e "${RED}0.${NC} ⬅️ Назад"

        local choice; _menu_choice choice
        case "$choice" in
            1) health_check_full ;;
            2) check_dns; pause ;;
            3) check_ports; pause ;;
            4) check_ssl_certs; pause ;;
            5) show_container_stats; pause ;;
            6) validate_env_files; pause ;;
            0) return ;;
            *) warn "Неизвестная команда."; sleep 1 ;;
        esac
    done
}

migration_menu() {
    _menu_header "🚚 МИГРАЦИЯ"
    echo -e "${GREEN}1.${NC} 📤 Экспорт конфигурации"
    echo -e "${GREEN}2.${NC} 📥 Импорт конфигурации"
    echo -e "${RED}0.${NC} ⬅️ Назад"

    local choice; _menu_choice choice
    case "$choice" in
        1) export_migration ;;
        2) import_migration ;;
        0) return ;;
        *) warn "Неизвестная команда."; sleep 1 ;;
    esac
}

system_security_menu() {
    while true; do
        _menu_header "🛡 СИСТЕМА И БЕЗОПАСНОСТЬ"

        local notify_status healthcheck_status watchdog_status
        notify_status="$(_flag_status "$NOTIFY_FLAG")"
        healthcheck_status="$(_flag_status "$HEALTHCHECK_FLAG")"
        watchdog_status="$(_flag_status "$WATCHDOG_FLAG")"

        echo -e "${BLUE}[Резервное копирование]${NC}"
        echo -e "${GREEN}1.${NC}  💾 Создать ручной бэкап"
        echo -e "${GREEN}2.${NC}  ⏱  Включить ежедневный авто-бэкап (03:00)"
        echo -e "${RED}3.${NC}  🛑 Отключить авто-бэкап"
        echo -e "${YELLOW}4.${NC}  📥 Восстановить из бэкапа"
        echo -e "${BLUE}[Откат]${NC}"
        echo -e "${YELLOW}5.${NC}  ⏪ Откатить Бота"
        echo -e "${YELLOW}6.${NC}  ⏪ Откатить Кабинет"
        echo -e "${BLUE}[Безопасность]${NC}"
        echo -e "${CYAN}7.${NC}  🔥 Настроить UFW (файрвол)"
        echo -e "${CYAN}8.${NC}  🛡  Установить Fail2ban"
        echo -e "${CYAN}9.${NC}  🔔 Telegram-уведомления [${notify_status}]"
        echo -e "${BLUE}[Мониторинг]${NC}"
        echo -e "${CYAN}10.${NC} 🏥 Health Check (каждые 10 мин.) [${healthcheck_status}]"
        echo -e "${CYAN}11.${NC} 🐕 Watchdog авто-рестарт (каждые 5 мин.) [${watchdog_status}]"
        echo -e "${CYAN}12.${NC} 📄 Просмотр лога панели"
        echo -e "${BLUE}[Обслуживание]${NC}"
        echo -e "${PURPLE}13.${NC} 💿 Управление Swap"
        echo -e "${PURPLE}14.${NC} 🧹 Очистить Docker от мусора"
        echo -e "${PURPLE}15.${NC} 🚚 Миграция"
        echo -e "${RED}16.${NC} 🗑  Полное удаление проекта"
        echo -e "${RED}0.${NC}  ⬅️ Назад"

        local sys_choice; _menu_choice sys_choice
        case "$sys_choice" in
            1) backup_project "manual" || err "Не удалось создать бэкап."; pause ;;
            2)
                persist_self_if_needed || warn "Не удалось сохранить панель в ${DEFAULT_INSTALL_PATH}, но cron всё равно будет использовать этот путь."
                _cron_toggle "cron_backup" "0 3 * * *" "$NOTIFY_FLAG" "enable"
                ok "Ежедневный авто-бэкап включен."; pause
                ;;
            3) _cron_toggle "cron_backup" "0 3 * * *" "$NOTIFY_FLAG" "disable"; ok "Авто-бэкап отключен."; pause ;;
            4) restore_backup ;;
            5) rollback_component "bot" "Бот" ;;
            6) rollback_component "cabinet" "Кабинет" ;;
            7) setup_ufw ;;
            8) setup_fail2ban ;;
            9) toggle_notifications ;;
            10)
                if [[ -f "$HEALTHCHECK_FLAG" ]]; then
                    _cron_toggle "cron_healthcheck" "*/10 * * * *" "$HEALTHCHECK_FLAG" "disable"
                    ok "Health check отключен."
                else
                    _cron_toggle "cron_healthcheck" "*/10 * * * *" "$HEALTHCHECK_FLAG" "enable"
                    ok "Health check включен (каждые 10 минут)."
                fi
                pause
                ;;
            11)
                if [[ -f "$WATCHDOG_FLAG" ]]; then
                    _cron_toggle "cron_watchdog" "*/5 * * * *" "$WATCHDOG_FLAG" "disable"
                    ok "Watchdog отключен."
                else
                    _cron_toggle "cron_watchdog" "*/5 * * * *" "$WATCHDOG_FLAG" "enable"
                    ok "Watchdog включен (каждые 5 минут)."
                fi
                pause
                ;;
            12)
                if [[ -f "$LOG_FILE" ]]; then
                    echo -e "\n${BOLD}📄 ПОСЛЕДНИЕ 50 СТРОК ЛОГА:${NC}"
                    echo -e "${CYAN}----------------------------------------${NC}"
                    tail -50 "$LOG_FILE" 2>/dev/null || warn "Не удалось прочитать лог."
                else
                    warn "Лог-файл ещё не создан: ${LOG_FILE}"
                fi
                pause
                ;;
            13) manage_swap_menu ;;
            14)
                if confirm "Это удалит ВСЕ неиспользуемые Docker-образы, контейнеры и тома. Продолжить?"; then
                    docker system prune -af --volumes || true
                    ok "Очистка завершена."
                fi
                pause
                ;;
            15) migration_menu ;;
            16) full_uninstall ;;
            0) return ;;
            *) warn "Неизвестная команда."; sleep 1 ;;
        esac
    done
}

# === DASHBOARD ===

show_dashboard() {
    get_system_info
    check_versions_cached
    check_health_quick

    clear
    echo -e "${PURPLE}====================================================${NC}"
    echo -e "${CYAN}${BOLD} 🚀 ST VILLAGE | ПАНЕЛЬ УПРАВЛЕНИЯ v${PANEL_VERSION} 🚀 ${NC}"
    echo -e "${PURPLE}====================================================${NC}"
    echo -e "📂 Ядро проекта:   ${GREEN}${BASE_DIR}${NC}"
    echo -e "${PURPLE}----------------------------------------------------${NC}"
    echo -e "${BOLD}🖥 СТАТУС СЕРВЕРА:${NC}"
    echo -e "🧩 ОС:                   ${CYAN}${OS_NAME}${NC}"
    echo -e "⏱ Uptime:               ${CYAN}${UPTIME_TXT}${NC}"
    echo -e "💾 RAM:                  ${CYAN}${RAM_TXT}${NC}"
    echo -e "💽 SSD:                  ${CYAN}${DISK_TXT}${NC}"
    echo -e "🐳 Docker:               ${DOCKER_STAT}"
    echo -e "${PURPLE}----------------------------------------------------${NC}"
    echo -e "${BOLD}📊 ВЕРСИИ КОМПОНЕНТОВ:${NC}"
    echo -e "🤖 Бот:     ${BOT_VER_TXT}"
    echo -e "🖥 Кабинет: ${CAB_VER_TXT}"
    echo -e "${PURPLE}----------------------------------------------------${NC}"
    echo -e "${BOLD}🏥 СОСТОЯНИЕ СЕРВИСОВ:${NC}"
    echo -e "🤖 Бот:     ${BOT_HEALTH}"
    echo -e "🖥 Кабинет: ${CAB_HEALTH}"
    echo -e "🌐 Caddy:   ${CADDY_HEALTH}"
    echo -e "${PURPLE}----------------------------------------------------${NC}\n"

    echo -e "${GREEN}1.${NC}  🔄 Обновить Бота"
    echo -e "${GREEN}2.${NC}  🔄 Обновить Кабинет"
    echo -e "${BLUE}3.${NC}  ▶️  Запустить проект (Bot + Cabinet + Caddy)"
    echo -e "${RED}4.${NC}  🛑 Остановить проект"
    echo -e "${CYAN}5.${NC}  🔃 Перезапуск компонентов"
    echo -e "${YELLOW}6.${NC}  ⚙️  Редактор конфигураций"
    echo -e "${YELLOW}7.${NC}  📋 Просмотр логов"
    echo -e "${BLUE}8.${NC}  🔍 Диагностика"
    echo -e "${PURPLE}9.${NC}  🛡  Система и безопасность"
    echo -e "${YELLOW}10.${NC} 🔄 Обновить статусы"
    echo -e "${CYAN}11.${NC} 🔍 Проверить обновления компонентов"
    echo -e "${BOLD}12.${NC} 📦 Обновить панель"
    echo -e "${RED}0.${NC}  ❌ Выход"
}

# === MAIN MENU ===

main_menu() {
    while true; do
        show_dashboard
        local choice
        read_tty choice "\n${YELLOW}Выберите команду ➤ ${NC}"
        case "$choice" in
            1) update_component "bot" "Бот" ;;
            2) update_component "cabinet" "Кабинет" ;;
            3) start_project ;;
            4) stop_project ;;
            5) restart_menu ;;
            6) config_menu ;;
            7) show_logs_menu ;;
            8) diagnostics_menu ;;
            9) system_security_menu ;;
            10) ;;
            11) log "Проверяю обновления компонентов..."; check_versions; ok "Версии обновлены."; sleep 1 ;;
            12) update_self ;;
            0) clear; echo -e "${GREEN}Успешной работы в ST VILLAGE!${NC}\n"; exit 0 ;;
            *) warn "Неизвестная команда."; sleep 1 ;;
        esac
    done
}

# === CRON HANDLERS ===

run_cron_backup() {
    require_root; resolve_script_path
    mkdir -p "$BACKUP_DIR"
    backup_project "auto" && rotate_auto_backups
}

run_cron_healthcheck() {
    require_root; resolve_script_path
    command_exists docker || exit 0

    local problems=()
    local containers=("remnawave_bot" "cabinet_frontend" "st_village_caddy")
    local labels=("Bot" "Cabinet" "Caddy")
    local i=0
    for cname in "${containers[@]}"; do
        local state=""
        state="$(_container_state "$cname")"
        [[ "$state" == "true" ]] || problems+=("${labels[$i]}: контейнер не работает")
        i=$((i + 1))
    done

    # Проверка HTTP-доступности доменов
    local domains=""
    domains="$(parse_caddyfile_domains 2>/dev/null || true)"
    if [[ -n "$domains" ]]; then
        while IFS= read -r domain; do
            [[ -n "$domain" ]] || continue
            local http_code=""
            http_code="$(curl -sf -o /dev/null -w '%{http_code}' --connect-timeout 10 "https://${domain}/" 2>/dev/null || echo "000")"
            [[ "${http_code:-000}" != "000" ]] || problems+=("HTTPS: ${domain} недоступен")
        done <<< "$domains"

        # Проверка SSL-сертификатов (предупреждение за 7 дней)
        while IFS= read -r domain; do
            [[ -n "$domain" ]] || continue
            local days_left=""
            days_left="$(_ssl_days_left "$domain")"
            if [[ "$days_left" -ge 0 && "$days_left" -lt 7 ]]; then
                problems+=("SSL: ${domain} истекает через ${days_left} дн.")
            fi
        done <<< "$domains"
    fi

    if [[ ${#problems[@]} -gt 0 ]]; then
        local msg="⚠️ Обнаружены проблемы:\n"
        for p in "${problems[@]}"; do msg+="• ${p}\n"; done
        _log_to_file "HEALTHCHECK FAILED: ${problems[*]}"
        send_telegram_notification "$msg"
    else
        _log_to_file "HEALTHCHECK OK: все сервисы работают"
    fi
}

run_cron_watchdog() {
    require_root; resolve_script_path
    command_exists docker || exit 0

    local containers=("remnawave_bot" "cabinet_frontend" "st_village_caddy")
    local labels=("Bot" "Cabinet" "Caddy")
    local restarted=() i=0

    for cname in "${containers[@]}"; do
        local state=""
        state="$(_container_state "$cname")"
        if [[ "$state" == "false" ]]; then
            _log_to_file "WATCHDOG: ${labels[$i]} ($cname) остановлен, перезапускаю..."
            if docker start "$cname" 2>/dev/null; then
                restarted+=("${labels[$i]}")
                _log_to_file "WATCHDOG: ${labels[$i]} успешно перезапущен"
            else
                _log_to_file "WATCHDOG: не удалось перезапустить ${labels[$i]}"
            fi
        fi
        i=$((i + 1))
    done

    if [[ ${#restarted[@]} -gt 0 ]]; then
        local msg="🔄 Watchdog перезапустил:"
        for r in "${restarted[@]}"; do msg+="\n• ${r}"; done
        send_telegram_notification "$msg"
    fi
}

# === MAIN ===

main() {
    require_root
    resolve_script_path

    case "${1:-}" in
        cron_backup)      run_cron_backup; exit 0 ;;
        cron_healthcheck) run_cron_healthcheck; exit 0 ;;
        cron_watchdog)    run_cron_watchdog; exit 0 ;;
    esac

    init_tty "${1:-}"
    ensure_dirs
    ensure_dependencies

    if [[ ! -d "${BOT_DIR}/.git" || ! -d "${CABINET_DIR}/.git" ]]; then
        install_project
    else
        normalize_project_files
    fi

    main_menu
}

main "$@"
