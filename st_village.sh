#!/usr/bin/env bash

# ====================================================
# ST VILLAGE | ПАНЕЛЬ УПРАВЛЕНИЯ v14.0
# Исправленная версия для Bedolaga Bot + Cabinet + Caddy
# ====================================================

set -u
export LC_ALL=C

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

PANEL_VERSION="14.0"

BASE_DIR="/root"
BOT_DIR="$BASE_DIR/bot"
CABINET_DIR="$BASE_DIR/cabinet"
CADDY_DIR="$BASE_DIR/caddy"
BACKUP_DIR="$BASE_DIR/backups"

BOT_REPO="https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot.git"
CABINET_REPO="https://github.com/BEDOLAGA-DEV/bedolaga-cabinet.git"
SCRIPT_URL="https://raw.githubusercontent.com/Reibik/Auto_Install-Bedolaga_Bot/main/st_village.sh"

BOT_COMPOSE_FILE="$BOT_DIR/docker-compose.local.yml"
CABINET_COMPOSE_FILE="$CABINET_DIR/docker-compose.yml"
CABINET_OVERRIDE_FILE="$CABINET_DIR/docker-compose.override.yml"
CADDY_COMPOSE_FILE="$CADDY_DIR/docker-compose.yml"

BOT_VER_TXT=""
CAB_VER_TXT=""
OS_NAME=""
UPTIME=""
RAM=""
DISK=""
DOCKER_STAT=""

log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $*"
}

ok() {
    echo -e "${GREEN}[✓]${NC} $*"
}

err() {
    echo -e "${RED}[✗]${NC} $*" >&2
}

pause() {
    echo
    read -r -p "$(echo -e "${YELLOW}Нажмите Enter для продолжения...${NC}")"
}

confirm() {
    local prompt="${1:-Продолжить?}"
    local answer
    read -r -p "$(echo -e "${YELLOW}${prompt} [y/N]: ${NC}")" answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        err "Запустите скрипт от root."
        exit 1
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

run_cmd() {
    "$@"
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        err "Команда завершилась с ошибкой ($rc): $*"
    fi
    return $rc
}

compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        docker compose "$@"
    elif command_exists docker-compose; then
        docker-compose "$@"
    else
        err "Docker Compose не найден."
        return 1
    fi
}

dc_bot() {
    compose_cmd -f "$BOT_COMPOSE_FILE" "$@"
}

dc_cabinet() {
    compose_cmd -f "$CABINET_COMPOSE_FILE" -f "$CABINET_OVERRIDE_FILE" "$@"
}

dc_caddy() {
    compose_cmd -f "$CADDY_COMPOSE_FILE" "$@"
}

ensure_line_endings() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    sed -i 's/\r$//' "$file"
}

ensure_dirs() {
    mkdir -p "$BASE_DIR" "$BOT_DIR" "$CABINET_DIR" "$CADDY_DIR" "$BACKUP_DIR"
}

ensure_dependencies() {
    log "Проверка системных зависимостей..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y git curl wget nano tar ca-certificates gnupg lsb-release unzip >/dev/null 2>&1 || {
        err "Не удалось установить базовые зависимости."
        return 1
    }

    if ! command_exists docker; then
        log "Docker не найден. Устанавливаю Docker..."
        curl -fsSL https://get.docker.com -o /tmp/get-docker.sh || return 1
        sh /tmp/get-docker.sh >/dev/null 2>&1 || return 1
        rm -f /tmp/get-docker.sh
    fi

    if ! docker compose version >/dev/null 2>&1 && ! command_exists docker-compose; then
        log "Пробую установить docker compose plugin..."
        apt-get install -y docker-compose-plugin >/dev/null 2>&1 || true
    fi

    systemctl enable docker >/dev/null 2>&1 || true
    systemctl start docker >/dev/null 2>&1 || true

    if ! docker info >/dev/null 2>&1; then
        err "Docker установлен, но демон недоступен."
        return 1
    fi

    return 0
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

    cat > "$CADDY_DIR/Caddyfile" <<'EOF'
# ЗАМЕНИТЕ ДОМЕНЫ НА СВОИ ПЕРЕД ПУБЛИЧНЫМ ЗАПУСКОМ

bot.example.com {
    encode gzip zstd
    reverse_proxy remnawave_bot:8080
}

cabinet.example.com {
    encode gzip zstd

    # API кабинета -> backend бота
    handle /api/* {
        uri strip_prefix /api
        reverse_proxy remnawave_bot:8080
    }

    # Frontend кабинета -> nginx внутри контейнера
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
    if [[ ! -f "$BOT_DIR/.env" ]]; then
        if [[ -f "$BOT_DIR/.env.example" ]]; then
            cp "$BOT_DIR/.env.example" "$BOT_DIR/.env"
        else
            : > "$BOT_DIR/.env"
        fi
    fi

    if [[ ! -f "$CABINET_DIR/.env" ]]; then
        if [[ -f "$CABINET_DIR/.env.example" ]]; then
            cp "$CABINET_DIR/.env.example" "$CABINET_DIR/.env"
        else
            : > "$CABINET_DIR/.env"
        fi
    fi
}

install_project() {
    clear
    echo -e "${PURPLE}====================================================${NC}"
    echo -e "${CYAN}${BOLD} 🚀 ST VILLAGE | МАСТЕР УСТАНОВКИ ПРОЕКТА 🚀 ${NC}"
    echo -e "${PURPLE}====================================================${NC}"
    echo -e "${YELLOW}Начинаем первичное развертывание...${NC}\n"

    ensure_dirs || return 1
    ensure_dependencies || return 1

    if [[ ! -d "$BOT_DIR/.git" ]]; then
        log "Клонирую Bedolaga Bot..."
        rm -rf "$BOT_DIR"
        git clone "$BOT_REPO" "$BOT_DIR" || return 1
    else
        log "Bedolaga Bot уже существует, пропускаю клонирование."
    fi

    if [[ ! -d "$CABINET_DIR/.git" ]]; then
        log "Клонирую Bedolaga Cabinet..."
        rm -rf "$CABINET_DIR"
        git clone "$CABINET_REPO" "$CABINET_DIR" || return 1
    else
        log "Bedolaga Cabinet уже существует, пропускаю клонирование."
    fi

    ensure_line_endings "$BOT_DIR/docker-compose.local.yml"
    ensure_line_endings "$CABINET_DIR/docker-compose.yml"
    ensure_line_endings "$BOT_DIR/.env.example"
    ensure_line_endings "$CABINET_DIR/.env.example"

    write_cabinet_override
    write_default_caddy_files
    prepare_env_files

    ok "Файлы проекта подготовлены."
    echo
    echo -e "${YELLOW}Что нужно сделать дальше:${NC}"
    echo -e "  1) Заполнить ${CYAN}$BOT_DIR/.env${NC}"
    echo -e "  2) Заполнить ${CYAN}$CABINET_DIR/.env${NC}"
    echo -e "  3) Изменить домены в ${CYAN}$CADDY_DIR/Caddyfile${NC}"
    echo -e "  4) После этого выбрать запуск проекта в главном меню"
    pause
}

check_versions() {
    BOT_VER_TXT="${RED}Не установлен${NC}"
    CAB_VER_TXT="${RED}Не установлен${NC}"

    if [[ -d "$BOT_DIR/.git" ]]; then
        cd "$BOT_DIR" || true
        git fetch origin main -q >/dev/null 2>&1 || true
        local local_bot remote_bot
        local_bot=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        remote_bot=$(git rev-parse --short origin/main 2>/dev/null || echo "")
        if [[ -n "$remote_bot" && "$local_bot" != "$remote_bot" ]]; then
            BOT_VER_TXT="${YELLOW}${local_bot} ➜ Доступна: ${remote_bot}${NC} ${RED}[Обновите]${NC}"
        else
            BOT_VER_TXT="${GREEN}${local_bot} (Актуально)${NC}"
        fi
    fi

    if [[ -d "$CABINET_DIR/.git" ]]; then
        cd "$CABINET_DIR" || true
        git fetch origin main -q >/dev/null 2>&1 || true
        local local_cab remote_cab
        local_cab=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        remote_cab=$(git rev-parse --short origin/main 2>/dev/null || echo "")
        if [[ -n "$remote_cab" && "$local_cab" != "$remote_cab" ]]; then
            CAB_VER_TXT="${YELLOW}${local_cab} ➜ Доступна: ${remote_cab}${NC} ${RED}[Обновите]${NC}"
        else
            CAB_VER_TXT="${GREEN}${local_cab} (Актуально)${NC}"
        fi
    fi

    cd "$BASE_DIR" >/dev/null 2>&1 || true
}

get_system_info() {
    OS_NAME=$(grep PRETTY_NAME /etc/os-release | cut -d '"' -f 2 2>/dev/null)
    UPTIME=$(uptime -p 2>/dev/null | sed 's/^up //')
    RAM=$(free -m | awk 'NR==2 {printf "%s / %s MB (%.1f%%)", $3,$2,($3*100)/$2}')
    DISK=$(df -h / | awk '$NF=="/" {printf "%s / %s (%s)", $3,$2,$5}')

    if command_exists docker; then
        local running total
        running=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
        total=$(docker ps -a -q 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$total" == "0" ]]; then
            DOCKER_STAT="${YELLOW}Контейнеры не созданы${NC}"
        elif [[ "$running" == "$total" ]]; then
            DOCKER_STAT="${GREEN}Запущено $running из $total${NC}"
        else
            DOCKER_STAT="${RED}Запущено $running из $total${NC}"
        fi
    else
        DOCKER_STAT="${RED}Docker не установлен${NC}"
    fi
}

backup_project() {
    mkdir -p "$BACKUP_DIR"
    local prefix="${1:-manual}"
    local ts archive size
    ts=$(date +"%Y-%m-%d_%H-%M-%S")
    archive="$BACKUP_DIR/backup_${prefix}_${ts}.tar.gz"

    tar \
      --exclude='./bot/.venv' \
      --exclude='./bot/__pycache__' \
      --exclude='./cabinet/node_modules' \
      --exclude='./cabinet/.svelte-kit' \
      --exclude='./backups' \
      --exclude='./.git' \
      -czf "$archive" -C "$BASE_DIR" . || return 1

    size=$(du -sh "$archive" | awk '{print $1}')
    ok "Бэкап создан: $archive ($size)"
}

cron_backup_rotate() {
    ls -tp "$BACKUP_DIR"/backup_auto_*.tar.gz 2>/dev/null | grep -v '/$' | tail -n +8 | xargs -r rm -f --
}

if [[ "${1:-}" == "cron_backup" ]]; then
    require_root
    mkdir -p "$BACKUP_DIR"
    backup_project "auto" && cron_backup_rotate
    exit 0
fi

ensure_network_available() {
    if docker network inspect remnawave-network >/dev/null 2>&1; then
        return 0
    fi

    warn "Сеть remnawave-network не найдена."
    warn "Обычно она создается автоматически вместе с ботом."
    return 1
}

validate_project_files() {
    local ok_flag=0

    [[ -f "$BOT_COMPOSE_FILE" ]] || { err "Не найден $BOT_COMPOSE_FILE"; ok_flag=1; }
    [[ -f "$CABINET_COMPOSE_FILE" ]] || { err "Не найден $CABINET_COMPOSE_FILE"; ok_flag=1; }
    [[ -f "$CABINET_OVERRIDE_FILE" ]] || write_cabinet_override
    [[ -f "$CADDY_COMPOSE_FILE" ]] || write_default_caddy_files
    [[ -f "$CADDY_DIR/Caddyfile" ]] || write_default_caddy_files

    return $ok_flag
}

start_project() {
    validate_project_files || { pause; return 1; }
    ensure_dependencies || { pause; return 1; }

    log "Запускаю Bedolaga Bot..."
    dc_bot up -d --build || { err "Не удалось запустить Bot."; pause; return 1; }

    ensure_network_available || {
        err "После запуска бота сеть remnawave-network так и не появилась."
        pause
        return 1
    }

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
        cabinet) dc_cabinet up -d --build ;;
        caddy) dc_caddy up -d --force-recreate ;;
        *) err "Неизвестный компонент: $component"; return 1 ;;
    esac
}

update_component() {
    local component="$1"
    local title="$2"
    local target_dir old_commit new_commit

    case "$component" in
        bot) target_dir="$BOT_DIR" ;;
        cabinet) target_dir="$CABINET_DIR" ;;
        *) err "Неизвестный компонент: $component"; pause; return 1 ;;
    esac

    [[ -d "$target_dir/.git" ]] || { err "Компонент не установлен: $title"; pause; return 1; }

    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${BOLD}[⚙️] ОБНОВЛЕНИЕ: ${title}${NC}"
    echo -e "${CYAN}========================================${NC}"

    cd "$target_dir" || { pause; return 1; }

    old_commit=$(git rev-parse --short HEAD 2>/dev/null || echo "")
    [[ -n "$old_commit" ]] || { err "Не удалось определить текущий commit."; pause; return 1; }

    echo "$old_commit" > "$target_dir/.last_commit"
    log "Текущая версия: $old_commit"

    git fetch origin main >/dev/null 2>&1 || { err "Не удалось получить обновления."; pause; return 1; }
    git reset --hard origin/main >/dev/null 2>&1 || { err "Не удалось обновить код."; pause; return 1; }

    new_commit=$(git rev-parse --short HEAD 2>/dev/null || echo "")
    if [[ "$old_commit" == "$new_commit" ]]; then
        ok "Обновлений нет. Установлена последняя версия."
        pause
        return 0
    fi

    ensure_line_endings "$target_dir/docker-compose.local.yml"
    ensure_line_endings "$target_dir/docker-compose.yml"

    if [[ "$component" == "cabinet" ]]; then
        write_cabinet_override
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
        *) err "Неизвестный компонент: $component"; pause; return 1 ;;
    esac

    [[ -f "$target_dir/.last_commit" ]] || { err "Нет сохраненной версии для отката: $title"; pause; return 1; }
    last_commit=$(cat "$target_dir/.last_commit")

    [[ -n "$last_commit" ]] || { err "Файл .last_commit пустой."; pause; return 1; }

    cd "$target_dir" || { pause; return 1; }
    git fetch origin main >/dev/null 2>&1 || true
    git reset --hard "$last_commit" >/dev/null 2>&1 || { err "Не удалось откатить $title."; pause; return 1; }

    if [[ "$component" == "cabinet" ]]; then
        write_cabinet_override
    fi

    rebuild_component "$component" || { pause; return 1; }
    ok "${title} откатен на commit ${last_commit}"
    pause
}

update_self() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${BOLD}[🔄] ОБНОВЛЕНИЕ ПАНЕЛИ УПРАВЛЕНИЯ${NC}"
    echo -e "${CYAN}========================================${NC}"

    local tmp
    tmp="$(mktemp)"
    if curl -fsSL "$SCRIPT_URL" -o "$tmp"; then
        ensure_line_endings "$tmp"
        if grep -qE '^#!/usr/bin/env bash|^#!/bin/bash' "$tmp"; then
            install -m 755 "$tmp" "$0"
            rm -f "$tmp"
            ok "Панель обновлена. Перезапускаю..."
            sleep 1
            exec "$0"
        fi
    fi

    rm -f "$tmp"
    err "Не удалось обновить панель."
    pause
}

config_menu() {
    while true; do
        clear
        echo -e "${CYAN}========================================${NC}"
        echo -e "${BOLD}⚙️ НАСТРОЙКИ ПРОЕКТА${NC}"
        echo -e "${CYAN}========================================${NC}"
        echo -e "${GREEN}1.${NC} 🤖 Открыть .env бота"
        echo -e "${GREEN}2.${NC} 🖥 Открыть .env кабинета"
        echo -e "${BLUE}3.${NC} 🌐 Открыть Caddyfile"
        echo -e "${BLUE}4.${NC} 🧩 Пересоздать docker-compose.override.yml для cabinet"
        echo -e "${RED}0.${NC} ⬅️ Назад"
        echo -ne "\n${YELLOW}Выберите действие ➤ ${NC}"
        read -r conf_choice

        case "$conf_choice" in
            1) nano "$BOT_DIR/.env" ;;
            2) nano "$CABINET_DIR/.env" ;;
            3)
                nano "$CADDY_DIR/Caddyfile"
                if confirm "Перезагрузить Caddy сейчас?"; then
                    dc_caddy up -d --force-recreate
                fi
                ;;
            4)
                write_cabinet_override
                ok "Файл $CABINET_OVERRIDE_FILE пересоздан."
                pause
                ;;
            0) return ;;
            *) warn "Неизвестная команда."; sleep 1 ;;
        esac
    done
}

show_logs_menu() {
    clear
    echo -e "${CYAN}Чьи логи открыть?${NC}"
    echo -e "${GREEN}1.${NC} Бот"
    echo -e "${GREEN}2.${NC} Кабинет"
    echo -e "${GREEN}3.${NC} Caddy"
    echo -e "${RED}0.${NC} Назад"
    echo -ne "\n${YELLOW}Выберите действие ➤ ${NC}"
    read -r choice

    case "$choice" in
        1) dc_bot logs -f --tail=100 ;;
        2) dc_cabinet logs -f --tail=100 ;;
        3) dc_caddy logs -f --tail=100 ;;
        0) return ;;
        *) warn "Неизвестная команда."; sleep 1 ;;
    esac
}

system_security_menu() {
    while true; do
        clear
        echo -e "${CYAN}========================================${NC}"
        echo -e "${BOLD}🛡 СИСТЕМА И БЕЗОПАСНОСТЬ${NC}"
        echo -e "${CYAN}========================================${NC}"
        echo -e "${BLUE}[Резервное копирование]${NC}"
        echo -e "${GREEN}1.${NC} 💾 Создать ручной бэкап сейчас"
        echo -e "${GREEN}2.${NC} ⏱ Включить ежедневный авто-бэкап (03:00)"
        echo -e "${RED}3.${NC} 🛑 Отключить авто-бэкап"
        echo -e "${BLUE}[Откат]${NC}"
        echo -e "${YELLOW}4.${NC} ⏪ Откатить Бота"
        echo -e "${YELLOW}5.${NC} ⏪ Откатить Кабинет"
        echo -e "${BLUE}[Обслуживание]${NC}"
        echo -e "${CYAN}6.${NC} 🧹 Очистить Docker от мусора"
        echo -e "${RED}0.${NC} ⬅️ Назад"
        echo -ne "\n${YELLOW}Выберите действие ➤ ${NC}"
        read -r sys_choice

        case "$sys_choice" in
            1)
                backup_project "manual" || err "Не удалось создать бэкап."
                pause
                ;;
            2)
                (crontab -l 2>/dev/null | grep -Fv "$0 cron_backup"; echo "0 3 * * * $0 cron_backup") | crontab -
                ok "Ежедневный авто-бэкап включен."
                pause
                ;;
            3)
                crontab -l 2>/dev/null | grep -Fv "$0 cron_backup" | crontab -
                ok "Авто-бэкап отключен."
                pause
                ;;
            4) rollback_component "bot" "Бот" ;;
            5) rollback_component "cabinet" "Кабинет" ;;
            6)
                docker system prune -af --volumes
                ok "Очистка завершена."
                pause
                ;;
            0) return ;;
            *) warn "Неизвестная команда."; sleep 1 ;;
        esac
    done
}

main_menu() {
    while true; do
        get_system_info
        check_versions

        clear
        echo -e "${PURPLE}====================================================${NC}"
        echo -e "${CYAN}${BOLD} 🚀 ST VILLAGE | ПАНЕЛЬ УПРАВЛЕНИЯ v${PANEL_VERSION} 🚀 ${NC}"
        echo -e "${PURPLE}====================================================${NC}"
        echo -e "📂 Ядро проекта:   ${GREEN}$BASE_DIR${NC}"
        echo -e "${PURPLE}----------------------------------------------------${NC}"
        echo -e "${BOLD}🖥 СТАТУС СЕРВЕРА:${NC}"
        echo -e "🧩 ОС:                   ${CYAN}${OS_NAME}${NC}"
        echo -e "⏱ Uptime:               ${CYAN}${UPTIME}${NC}"
        echo -e "💾 RAM:                  ${CYAN}${RAM}${NC}"
        echo -e "💽 SSD:                  ${CYAN}${DISK}${NC}"
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

        echo -ne "\n${YELLOW}Выберите команду ➤ ${NC}"
        read -r choice

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
                echo -e "${GREEN}Успешной работы ST VILLAGE!${NC}\n"
                exit 0
                ;;
            *) warn "Неизвестная команда."; sleep 1 ;;
        esac
    done
}

require_root
ensure_line_endings "$0"
ensure_dirs

if [[ ! -d "$BOT_DIR/.git" || ! -d "$CABINET_DIR/.git" ]]; then
    install_project
fi

main_menu
