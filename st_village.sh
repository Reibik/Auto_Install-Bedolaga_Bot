#!/usr/bin/env bash

# ====================================================
# ST VILLAGE | ПАНЕЛЬ УПРАВЛЕНИЯ v15.0
# Stable Edition for Bedolaga Bot + Cabinet + Caddy
# ====================================================

set -Eeuo pipefail
export LC_ALL=C

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

PANEL_VERSION="15.0"

BASE_DIR="/root"
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

BOT_VER_TXT=""
CAB_VER_TXT=""
OS_NAME=""
UPTIME_TXT=""
RAM_TXT=""
DISK_TXT=""
DOCKER_STAT=""
SCRIPT_PATH=""
TTY_READY=0

log() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $*"; }
ok() { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err() { echo -e "${RED}[✗]${NC} $*" >&2; }

die() {
    err "$*"
    exit 1
}

require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        die "Запусти скрипт от root."
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

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

init_tty() {
    if [[ "${1:-}" == "cron_backup" ]]; then
        return 0
    fi

    if exec 3</dev/tty 4>/dev/tty; then
        TTY_READY=1
        return 0
    fi

    if [[ -t 0 ]]; then
        exec 3<&0 4>&1
        TTY_READY=1
        return 0
    fi

    die "Нет доступа к интерактивному терминалу. Запусти скрипт из обычной SSH-сессии."
}

read_tty() {
    local __var_name="$1"
    local __prompt="${2:-}"
    local __value=""

    if [[ "$TTY_READY" -ne 1 ]]; then
        die "Интерактивный ввод недоступен."
    fi

    printf "%b" "$__prompt" >&4
    IFS= read -r __value <&3 || __value=""
    printf -v "$__var_name" '%s' "$__value"
}

pause() {
    if [[ "$TTY_READY" -eq 1 ]]; then
        printf "\n%b" "${YELLOW}Нажми Enter для продолжения...${NC}" >&4
        local _
        IFS= read -r _ <&3 || true
    fi
}

confirm() {
    local prompt="${1:-Продолжить?}"
    local answer
    read_tty answer "\n${YELLOW}${prompt} [y/N]: ${NC}"
    [[ "$answer" =~ ^[Yy]$ ]]
}

press_any_key_to_continue() {
    pause
}

ensure_dirs() {
    mkdir -p "$BASE_DIR" "$BOT_DIR" "$CABINET_DIR" "$CADDY_DIR" "$BACKUP_DIR"
}

compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        docker compose "$@"
    elif command_exists docker-compose; then
        docker-compose "$@"
    else
        die "Docker Compose не найден."
    fi
}

dc_bot() {
    compose_cmd -f "$BOT_COMPOSE_FILE" "$@"
}

dc_cabinet() {
    if [[ -f "$CABINET_OVERRIDE_FILE" ]]; then
        compose_cmd -f "$CABINET_COMPOSE_FILE" -f "$CABINET_OVERRIDE_FILE" "$@"
    else
        compose_cmd -f "$CABINET_COMPOSE_FILE" "$@"
    fi
}

dc_caddy() {
    compose_cmd -f "$CADDY_COMPOSE_FILE" "$@"
}

ensure_dependencies() {
    log "Проверяю системные зависимости..."
    export DEBIAN_FRONTEND=noninteractive

    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y \
        git curl wget nano tar ca-certificates gnupg lsb-release \
        unzip apt-transport-https software-properties-common \
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
    if [[ ! -f "${BOT_DIR}/.env" ]]; then
        if [[ -f "${BOT_DIR}/.env.example" ]]; then
            cp "${BOT_DIR}/.env.example" "${BOT_DIR}/.env"
        else
            touch "${BOT_DIR}/.env"
        fi
    fi

    if [[ ! -f "${CABINET_DIR}/.env" ]]; then
        if [[ -f "${CABINET_DIR}/.env.example" ]]; then
            cp "${CABINET_DIR}/.env.example" "${CABINET_DIR}/.env"
        else
            touch "${CABINET_DIR}/.env"
        fi
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
    local repo_url="$1"
    local target_dir="$2"
    local title="$3"

    if [[ -d "${target_dir}/.git" ]]; then
        log "${title} уже существует."
        return 0
    fi

    rm -rf "$target_dir"
    log "Клонирую ${title}..."
    git clone "$repo_url" "$target_dir" >/dev/null 2>&1 || die "Не удалось клонировать ${title}."
}

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
    echo
}

install_project() {
    clear
    echo -e "${PURPLE}====================================================${NC}"
    echo -e "${CYAN}${BOLD} 🚀 ST VILLAGE | МАСТЕР УСТАНОВКИ v${PANEL_VERSION} 🚀 ${NC}"
    echo -e "${PURPLE}====================================================${NC}"
    echo -e "${YELLOW}Запускаю первичное развертывание проекта...${NC}\n"

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
    if docker network inspect remnawave-network >/dev/null 2>&1; then
        return 0
    fi

    log "Сеть remnawave-network не найдена. Создаю..."
    docker network create remnawave-network >/dev/null 2>&1 || {
        err "Не удалось создать сеть remnawave-network."
        return 1
    }
    ok "Сеть remnawave-network создана."
}

check_versions() {
    BOT_VER_TXT="${RED}Не установлен${NC}"
    CAB_VER_TXT="${RED}Не установлен${NC}"

    if [[ -d "${BOT_DIR}/.git" ]]; then
        (
            cd "$BOT_DIR"
            git fetch origin main -q >/dev/null 2>&1 || true
            local_bot="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
            remote_bot="$(git rev-parse --short origin/main 2>/dev/null || echo '')"
            if [[ -n "$remote_bot" && "$local_bot" != "$remote_bot" ]]; then
                BOT_VER_TXT="${YELLOW}${local_bot} ➜ доступна ${remote_bot}${NC} ${RED}[обновить]${NC}"
            else
                BOT_VER_TXT="${GREEN}${local_bot} (Актуально)${NC}"
            fi
            printf '%s' "$BOT_VER_TXT" > /tmp/stv_bot_ver.$$
        )
        BOT_VER_TXT="$(cat /tmp/stv_bot_ver.$$ 2>/dev/null || printf '%s' "$BOT_VER_TXT")"
        rm -f /tmp/stv_bot_ver.$$
    fi

    if [[ -d "${CABINET_DIR}/.git" ]]; then
        (
            cd "$CABINET_DIR"
            git fetch origin main -q >/dev/null 2>&1 || true
            local_cab="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
            remote_cab="$(git rev-parse --short origin/main 2>/dev/null || echo '')"
            if [[ -n "$remote_cab" && "$local_cab" != "$remote_cab" ]]; then
                CAB_VER_TXT="${YELLOW}${local_cab} ➜ доступна ${remote_cab}${NC} ${RED}[обновить]${NC}"
            else
                CAB_VER_TXT="${GREEN}${local_cab} (Актуально)${NC}"
            fi
            printf '%s' "$CAB_VER_TXT" > /tmp/stv_cab_ver.$$
        )
        CAB_VER_TXT="$(cat /tmp/stv_cab_ver.$$ 2>/dev/null || printf '%s' "$CAB_VER_TXT")"
        rm -f /tmp/stv_cab_ver.$$
    fi
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

start_project() {
    validate_project_files || { pause; return 1; }
    ensure_dependencies
    normalize_project_files

    if grep -qE '^BOT_TOKEN=$' "${BOT_DIR}/.env" 2>/dev/null; then
        warn "BOT_TOKEN не заполнен в ${BOT_DIR}/.env"
        if ! confirm "Запустить всё равно?"; then
            return 1
        fi
    fi

    if grep -qE '^WEB_API_ENABLED=false' "${BOT_DIR}/.env" 2>/dev/null; then
        warn "WEB_API_ENABLED=false — веб-сервер отключен, кабинет не будет работать!"
        warn "Установите WEB_API_ENABLED=true в ${BOT_DIR}/.env"
        if ! confirm "Запустить всё равно?"; then
            return 1
        fi
    fi

    if grep -qE '^CABINET_ENABLED=false' "${BOT_DIR}/.env" 2>/dev/null; then
        warn "CABINET_ENABLED=false — Cabinet API отключен, кабинет не будет работать!"
        warn "Установите CABINET_ENABLED=true в ${BOT_DIR}/.env"
        if ! confirm "Запустить всё равно?"; then
            return 1
        fi
    fi

    log "Запускаю Bedolaga Bot..."
    dc_bot up -d --build || { err "Не удалось запустить Bot."; pause; return 1; }

    ensure_bot_network || { err "После запуска бота сеть remnawave-network не появилась."; pause; return 1; }

    log "Запускаю Bedolaga Cabinet..."
    dc_cabinet up -d --build || { err "Не удалось запустить Cabinet."; pause; return 1; }

    log "Запускаю Caddy..."
    dc_caddy up -d || { err "Не удалось запустить Caddy."; pause; return 1; }

    ok "Проект успешно запущен."
    pause
}

stop_project() {
    [[ -f "$CADDY_COMPOSE_FILE" ]] && dc_caddy stop >/dev/null 2>&1 || true
    [[ -f "$CABINET_COMPOSE_FILE" ]] && dc_cabinet stop >/dev/null 2>&1 || true
    [[ -f "$BOT_COMPOSE_FILE" ]] && dc_bot stop >/dev/null 2>&1 || true
    ok "Проект остановлен."
    pause
}

rebuild_component() {
    local component="$1"
    case "$component" in
        bot) dc_bot up -d --build ;;
        cabinet)
            write_cabinet_override
            dc_cabinet up -d --build
            ;;
        caddy) dc_caddy up -d --force-recreate ;;
        *) err "Неизвестный компонент: ${component}"; return 1 ;;
    esac
}

update_component() {
    local component="$1"
    local title="$2"
    local target_dir old_commit new_commit

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
        ok "Обновлений нет. Уже установлена последняя версия."
        pause
        return 0
    fi

    rebuild_component "$component" || { pause; return 1; }
    ok "${title} обновлен: ${old_commit} → ${new_commit}"
    pause
}

rollback_component() {
    local component="$1"
    local title="$2"
    local target_dir last_commit

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

backup_project() {
    mkdir -p "$BACKUP_DIR"
    local prefix="${1:-manual}"
    local ts archive size
    ts="$(date +"%Y-%m-%d_%H-%M-%S")"
    archive="${BACKUP_DIR}/backup_${prefix}_${ts}.tar.gz"

    tar \
        --exclude='./bot/.venv' \
        --exclude='./bot/__pycache__' \
        --exclude='./bot/node_modules' \
        --exclude='./cabinet/node_modules' \
        --exclude='./cabinet/.svelte-kit' \
        --exclude='./cabinet/dist' \
        --exclude='./backups' \
        --exclude='./.git' \
        -czf "$archive" -C "$BASE_DIR" . || return 1

    size="$(du -sh "$archive" | awk '{print $1}')"
    ok "Бэкап создан: ${archive} (${size})"
}

rotate_auto_backups() {
    ls -tp "${BACKUP_DIR}"/backup_auto_*.tar.gz 2>/dev/null | grep -v '/$' | tail -n +8 | xargs -r rm -f --
}

enable_auto_backup() {
    { crontab -l 2>/dev/null | grep -Fv "${DEFAULT_INSTALL_PATH} cron_backup" || true; \
      echo "0 3 * * * ${DEFAULT_INSTALL_PATH} cron_backup"; } | crontab -
}

disable_auto_backup() {
    local current=""
    current="$(crontab -l 2>/dev/null | grep -Fv "${DEFAULT_INSTALL_PATH} cron_backup" || true)"
    if [[ -n "$current" ]]; then
        printf '%s\n' "$current" | crontab -
    else
        crontab -r >/dev/null 2>&1 || true
    fi
}

persist_self_if_needed() {
    if [[ "$SCRIPT_PATH" == "$DEFAULT_INSTALL_PATH" && -f "$DEFAULT_INSTALL_PATH" ]]; then
        return 0
    fi

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
        rm -f "$tmp"
        err "Скачанный файл не похож на shell-скрипт."
        pause
        return 1
    fi

    install -m 755 "$tmp" "$DEFAULT_INSTALL_PATH"
    rm -f "$tmp"

    ok "Панель обновлена. Перезапускаю..."
    sleep 1
    exec "$DEFAULT_INSTALL_PATH"
}

config_menu() {
    while true; do
        clear
        echo -e "${CYAN}========================================${NC}"
        echo -e "${BOLD}⚙️ РЕДАКТОР КОНФИГУРАЦИЙ${NC}"
        echo -e "${CYAN}========================================${NC}"
        echo -e "${GREEN}1.${NC} 🤖 Открыть .env бота"
        echo -e "${GREEN}2.${NC} 🖥 Открыть .env кабинета"
        echo -e "${BLUE}3.${NC} 🌐 Открыть Caddyfile"
        echo -e "${BLUE}4.${NC} 🧩 Пересоздать docker-compose.override.yml"
        echo -e "${RED}0.${NC} ⬅️ Назад"

        local conf_choice
        read_tty conf_choice "\n${YELLOW}Выберите действие ➤ ${NC}"

        case "$conf_choice" in
            1) nano "${BOT_DIR}/.env" ;;
            2) nano "${CABINET_DIR}/.env" ;;
            3)
                nano "$CADDYFILE"
                if confirm "Перезагрузить Caddy сейчас?"; then
                    dc_caddy up -d --force-recreate >/dev/null 2>&1 || true
                fi
                ;;
            4)
                write_cabinet_override
                ok "Файл ${CABINET_OVERRIDE_FILE} пересоздан."
                pause
                ;;
            0) return ;;
            *) warn "Неизвестная команда."; sleep 1 ;;
        esac
    done
}

show_logs_menu() {
    while true; do
        clear
        echo -e "${CYAN}========================================${NC}"
        echo -e "${BOLD}📋 ПРОСМОТР ЛОГОВ${NC}"
        echo -e "${CYAN}========================================${NC}"
        echo -e "${GREEN}1.${NC} Бот"
        echo -e "${GREEN}2.${NC} Кабинет"
        echo -e "${GREEN}3.${NC} Caddy"
        echo -e "${RED}0.${NC} Назад"

        local choice
        read_tty choice "\n${YELLOW}Выберите действие ➤ ${NC}"

        case "$choice" in
            1) dc_bot logs -f --tail=100 ;;
            2) dc_cabinet logs -f --tail=100 ;;
            3) dc_caddy logs -f --tail=100 ;;
            0) return ;;
            *) warn "Неизвестная команда."; sleep 1 ;;
        esac
    done
}

system_security_menu() {
    while true; do
        clear
        echo -e "${CYAN}========================================${NC}"
        echo -e "${BOLD}🛡 СИСТЕМА И БЕЗОПАСНОСТЬ${NC}"
        echo -e "${CYAN}========================================${NC}"
        echo -e "${BLUE}[Резервное копирование]${NC}"
        echo -e "${GREEN}1.${NC} 💾 Создать ручной бэкап"
        echo -e "${GREEN}2.${NC} ⏱ Включить ежедневный авто-бэкап (03:00)"
        echo -e "${RED}3.${NC} 🛑 Отключить авто-бэкап"
        echo -e "${BLUE}[Откат]${NC}"
        echo -e "${YELLOW}4.${NC} ⏪ Откатить Бота"
        echo -e "${YELLOW}5.${NC} ⏪ Откатить Кабинет"
        echo -e "${BLUE}[Обслуживание]${NC}"
        echo -e "${CYAN}6.${NC} 🧹 Очистить Docker от мусора"
        echo -e "${RED}0.${NC} ⬅️ Назад"

        local sys_choice
        read_tty sys_choice "\n${YELLOW}Выберите действие ➤ ${NC}"

        case "$sys_choice" in
            1)
                backup_project "manual" || err "Не удалось создать бэкап."
                pause
                ;;
            2)
                persist_self_if_needed || warn "Не удалось сохранить панель в ${DEFAULT_INSTALL_PATH}, но cron всё равно будет использовать этот путь."
                enable_auto_backup
                ok "Ежедневный авто-бэкап включен."
                pause
                ;;
            3)
                disable_auto_backup
                ok "Авто-бэкап отключен."
                pause
                ;;
            4) rollback_component "bot" "Бот" ;;
            5) rollback_component "cabinet" "Кабинет" ;;
            6)
                if confirm "Это удалит ВСЕ неиспользуемые Docker-образы, контейнеры и тома. Продолжить?"; then
                    docker system prune -af --volumes || true
                    ok "Очистка завершена."
                fi
                pause
                ;;
            0) return ;;
            *) warn "Неизвестная команда."; sleep 1 ;;
        esac
    done
}

show_dashboard() {
    get_system_info
    check_versions

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
    echo -e "${PURPLE}----------------------------------------------------${NC}\n"

    echo -e "${GREEN}1.${NC} 🔄 Обновить Бота"
    echo -e "${GREEN}2.${NC} 🔄 Обновить Кабинет"
    echo -e "${BLUE}3.${NC} ▶️ Запустить проект (Bot + Cabinet + Caddy)"
    echo -e "${RED}4.${NC} 🛑 Остановить проект"
    echo -e "${CYAN}5.${NC} ⚙️ Редактор конфигураций"
    echo -e "${YELLOW}6.${NC} 📋 Просмотр логов"
    echo -e "${PURPLE}7.${NC} 🛡 Система и безопасность"
    echo -e "${YELLOW}8.${NC} 🔄 Обновить статусы"
    echo -e "${BOLD}9.${NC} 📦 Обновить панель"
    echo -e "${RED}0.${NC} ❌ Выход"
}

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
            5) config_menu ;;
            6) show_logs_menu ;;
            7) system_security_menu ;;
            8) ;;
            9) update_self ;;
            0)
                clear
                echo -e "${GREEN}Успешной работы в ST VILLAGE!${NC}\n"
                exit 0
                ;;
            *) warn "Неизвестная команда."; sleep 1 ;;
        esac
    done
}

run_cron_backup() {
    require_root
    resolve_script_path
    mkdir -p "$BACKUP_DIR"
    backup_project "auto" && rotate_auto_backups
}

main() {
    require_root
    resolve_script_path

    if [[ "${1:-}" == "cron_backup" ]]; then
        run_cron_backup
        exit 0
    fi

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
