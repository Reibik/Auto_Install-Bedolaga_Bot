#!/bin/bash

# === ЦВЕТА И СТИЛИ ===
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# === ПЕРЕМЕННЫЕ ПРОЕКТА ===
BASE_DIR="/root"
BOT_REPO="https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot.git"
CABINET_REPO="https://github.com/BEDOLAGA-DEV/bedolaga-cabinet.git"

BOT_VER_TXT=""
CAB_VER_TXT=""

# Твоя ссылка на автообновление
SCRIPT_URL="https://raw.githubusercontent.com/Reibik/Auto_Install-Bedolaga_Bot/main/st_village.sh"

# === УТИЛИТЫ ===
log() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"; }
pause() { echo -ne "\n${YELLOW}Нажмите Enter для продолжения...${NC}"; read; }

# === РЕЖИМ УСТАНОВКИ (AUTO-DEPLOY) ===
install_project() {
    clear
    echo -e "${PURPLE}====================================================${NC}"
    echo -e "${CYAN}${BOLD} 🚀 ST VILLAGE | МАСТЕР УСТАНОВКИ ПРОЕКТА 🚀 ${NC}"
    echo -e "${PURPLE}====================================================${NC}"
    echo -e "${YELLOW}Папки проекта не найдены. Начинаем первичное развертывание...${NC}\n"

    log "Проверка системных зависимостей для Ubuntu..."
    if ! command -v git &> /dev/null; then
        apt-get update && apt-get install -y git
    fi
    if ! command -v docker &> /dev/null; then
        curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh
    fi

    log "Скачивание Бота из GitHub..."
    git clone "$BOT_REPO" "$BASE_DIR/bot"
    
    log "Скачивание Кабинета из GitHub..."
    git clone "$CABINET_REPO" "$BASE_DIR/cabinet"

    log "Настройка веб-сервера Caddy..."
    mkdir -p "$BASE_DIR/caddy"
    
    cat <<EOF > "$BASE_DIR/caddy/Caddyfile"
bot.yourdomain.com {
    reverse_proxy bot:8000
}

cabinet.yourdomain.com {
    handle_path /api/* {
        reverse_proxy bot:8000
    }
    @websockets {
        path */ws
    }
    reverse_proxy @websockets bot:8000
    reverse_proxy cabinet:3020
}
EOF

    cat <<EOF > "$BASE_DIR/caddy/docker-compose.yml"
services:
  caddy:
    image: caddy:alpine
    container_name: st_village_caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    networks:
      - bot_bot_network

networks:
  bot_bot_network:
    external: true

volumes:
  caddy_data:
  caddy_config:
EOF

    log "Создание базовых конфигураций..."
    [ ! -f "$BASE_DIR/bot/.env" ] && cp "$BASE_DIR/bot/.env.example" "$BASE_DIR/bot/.env" 2>/dev/null || touch "$BASE_DIR/bot/.env"
    [ ! -f "$BASE_DIR/cabinet/.env" ] && cp "$BASE_DIR/cabinet/.env.example" "$BASE_DIR/cabinet/.env" 2>/dev/null || touch "$BASE_DIR/cabinet/.env"

    echo -e "\n${GREEN}[✅] Проект ST VILLAGE успешно загружен на сервер!${NC}"
    echo -e "${YELLOW}ВАЖНО: Перед запуском обязательно заполните файлы .env и Caddyfile.${NC}"
    pause
}

# === ИНФО-БЛОК ВЕРСИЙ ===
check_versions() {
    echo -e "${CYAN}[🔄] Проверка обновлений на GitHub...${NC}"
    
    if [ -d "$BASE_DIR/bot/.git" ]; then
        cd "$BASE_DIR/bot" || return
        git fetch origin main -q 2>/dev/null
        local local_bot=$(git rev-parse --short HEAD 2>/dev/null)
        local remote_bot=$(git rev-parse --short origin/main 2>/dev/null)
        if [ "$local_bot" == "$remote_bot" ]; then
            BOT_VER_TXT="${GREEN}${local_bot} (Актуально)${NC}"
        else
            BOT_VER_TXT="${YELLOW}${local_bot} ➔ Доступна: ${remote_bot}${NC} ${RED}[Обновите!]${NC}"
        fi
    else
        BOT_VER_TXT="${RED}Не установлен${NC}"
    fi

    if [ -d "$BASE_DIR/cabinet/.git" ]; then
        cd "$BASE_DIR/cabinet" || return
        git fetch origin main -q 2>/dev/null
        local local_cab=$(git rev-parse --short HEAD 2>/dev/null)
        local remote_cab=$(git rev-parse --short origin/main 2>/dev/null)
        if [ "$local_cab" == "$remote_cab" ]; then
            CAB_VER_TXT="${GREEN}${local_cab} (Актуально)${NC}"
        else
            CAB_VER_TXT="${YELLOW}${local_cab} ➔ Доступна: ${remote_cab}${NC} ${RED}[Обновите!]${NC}"
        fi
    else
        CAB_VER_TXT="${RED}Не установлен${NC}"
    fi
}

# === СБОР СИСТЕМНОЙ ИНФОРМАЦИИ ===
get_system_info() {
    OS_NAME=$(grep PRETTY_NAME /etc/os-release | cut -d '"' -f 2)
    UPTIME=$(uptime -p | sed 's/up //')
    RAM=$(free -m | awk 'NR==2{printf "%s / %s MB (%.1f%%)", $3,$2,$3*100/$2 }')
    DISK=$(df -h / | awk '$NF=="/"{printf "%s / %s (%s)", $3,$2,$5}')
    
    if command -v docker &> /dev/null; then
        DOCKER_RUNNING=$(docker ps -q 2>/dev/null | wc -l)
        DOCKER_TOTAL=$(docker ps -a -q 2>/dev/null | wc -l)
        if [ "$DOCKER_RUNNING" -eq "$DOCKER_TOTAL" ] && [ "$DOCKER_TOTAL" -ne 0 ]; then
            DOCKER_STAT="${GREEN}Запущено $DOCKER_RUNNING из $DOCKER_TOTAL${NC}"
        elif [ "$DOCKER_TOTAL" -eq 0 ]; then
            DOCKER_STAT="${YELLOW}Контейнеры не созданы${NC}"
        else
            DOCKER_STAT="${RED}Запущено $DOCKER_RUNNING из $DOCKER_TOTAL (Есть ошибки!)${NC}"
        fi
    else
        DOCKER_STAT="${RED}Docker не установлен${NC}"
    fi
}

# === АВТО-ОБНОВЛЕНИЕ КОМПОНЕНТОВ ===
update_component() {
    local component=$1
    local name_ru=$2

    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${BOLD}[⚙️] ОБНОВЛЕНИЕ: ${name_ru^^}${NC}"
    echo -e "${CYAN}========================================${NC}"
    
    cd "$BASE_DIR/$component" || return
    local old_commit=$(git rev-parse --short HEAD 2>/dev/null)
    log "${YELLOW}Текущая версия: ${old_commit}${NC}"

    git reset --hard HEAD >/dev/null 2>&1
    git clean -fd >/dev/null 2>&1
    git pull origin main >/dev/null 2>&1
    
    local new_commit=$(git rev-parse --short HEAD 2>/dev/null)
    if [ "$old_commit" == "$new_commit" ]; then
        log "${GREEN}Обновлений нет. Установлена последняя версия!${NC}"
        pause; return
    fi

    log "${YELLOW}Пересборка контейнера '${component}'...${NC}"
    cd "$BASE_DIR" || return
    local start_time=$(date +%s)
    docker compose up -d --build "$component"
    local elapsed=$(($(date +%s) - start_time))

    echo -e "\n${GREEN}[✅] ${name_ru} успешно обновлен! (Заняло: ${elapsed} сек.)${NC}"
    pause
}

# === САМООБНОВЛЕНИЕ СКРИПТА ===
update_self() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${BOLD}[🔄] ОБНОВЛЕНИЕ ПАНЕЛИ УПРАВЛЕНИЯ${NC}"
    echo -e "${CYAN}========================================${NC}"
    
    log "${YELLOW}Скачивание новой версии скрипта с GitHub...${NC}"
    wget -qO "$0.tmp" "$SCRIPT_URL"
    
    if [ $? -eq 0 ] && grep -q "#!/bin/bash" "$0.tmp"; then
        sed -i 's/\r$//' "$0.tmp"
        mv "$0.tmp" "$0"
        chmod +x "$0"
        echo -e "${GREEN}[✅] Скрипт успешно обновлен! Перезапуск интерфейса...${NC}"
        sleep 2
        exec "$0"
    else
        echo -e "${RED}[❌] Ошибка скачивания. Проверьте ссылку SCRIPT_URL в коде скрипта.${NC}"
        rm -f "$0.tmp" 2>/dev/null
        pause
    fi
}

# === МЕНЮ НАСТРОЕК (РЕДАКТОР) ===
config_menu() {
    while true; do
        clear
        echo -e "${CYAN}========================================${NC}"
        echo -e "${BOLD}⚙️ НАСТРОЙКИ ПРОЕКТА (.env / Caddy)${NC}"
        echo -e "${CYAN}========================================${NC}"
        echo -e "${GREEN}1.${NC} 🤖 Настройки Бота (.env)"
        echo -e "${GREEN}2.${NC} 🖥 Настройки Кабинета (.env)"
        echo -e "${BLUE}3.${NC} 🌐 Настройки Caddy (Caddyfile)"
        echo -e "${RED}0.${NC} ⬅️ Назад"
        echo -ne "\n${YELLOW}Выберите файл ➤ ${NC}"
        read conf_choice

        case $conf_choice in
            1) nano "$BASE_DIR/bot/.env" ;;
            2) nano "$BASE_DIR/cabinet/.env" ;;
            3) nano "$BASE_DIR/caddy/Caddyfile"
               echo -ne "${YELLOW}Перезагрузить Caddy для применения? (y/n): ${NC}"
               read ans; if [ "$ans" == "y" ]; then cd "$BASE_DIR/caddy" && docker compose restart caddy; fi ;;
            0) return ;;
        esac
    done
}

# === СТАРТ СКРИПТА (ТОЧКА ВХОДА) ===
if [ ! -d "$BASE_DIR/bot" ] || [ ! -d "$BASE_DIR/cabinet" ]; then
    install_project
fi

check_versions

while true; do
    get_system_info # Обновляем системную информацию перед каждым показом меню
    
    clear
    echo -e "${PURPLE}====================================================${NC}"
    echo -e "${CYAN}${BOLD} 🚀 ST VILLAGE | ПАНЕЛЬ УПРАВЛЕНИЯ v12.0 🚀 ${NC}"
    echo -e "${PURPLE}====================================================${NC}"
    echo -e "📂 Ядро проекта:   ${GREEN}$BASE_DIR${NC}"
    echo -e "${PURPLE}----------------------------------------------------${NC}"
    echo -e "${BOLD}🖥 СТАТУС СЕРВЕРА (${OS_NAME}):${NC}"
    echo -e "⏱ Uptime (Время работы): ${CYAN}${UPTIME}${NC}"
    echo -e "💾 RAM (Память):         ${CYAN}${RAM}${NC}"
    echo -e "💽 SSD (Накопитель):     ${CYAN}${DISK}${NC}"
    echo -e "🐳 Docker контейнеры:    ${DOCKER_STAT}"
    echo -e "${PURPLE}----------------------------------------------------${NC}"
    echo -e "${BOLD}📊 ВЕРСИИ КОМПОНЕНТОВ:${NC}"
    echo -e "🤖 Бот:     $BOT_VER_TXT"
    echo -e "🖥 Кабинет: $CAB_VER_TXT"
    echo -e "${PURPLE}----------------------------------------------------${NC}\n"
    
    echo -e "${GREEN}1.${NC} 🔄 Обновить Бота"
    echo -e "${GREEN}2.${NC} 🔄 Обновить Кабинет"
    echo -e "${BLUE}3.${NC} ▶️ Запустить проект (Bot + Cabinet + Caddy)"
    echo -e "${RED}4.${NC} 🛑 Остановить проект"
    echo -e "${CYAN}5.${NC} ⚙️ Редактор конфигураций (.env / Caddyfile)"
    echo -e "${YELLOW}6.${NC} 📋 Просмотр логов"
    echo -e "${PURPLE}7.${NC} 🔄 Обновить статусы (Сервер + GitHub)"
    echo -e "${BOLD}8.${NC} 📦 Обновить панель управления (Скрипт)"
    echo -e "${RED}0.${NC} ❌ Выход"
    
    echo -ne "\n${YELLOW}Выберите команду ➤ ${NC}"
    read choice

    case $choice in
        1) update_component "bot" "Бота"; check_versions ;;
        2) update_component "cabinet" "Кабинета"; check_versions ;;
        3) 
            cd "$BASE_DIR/bot" && docker compose up -d
            cd "$BASE_DIR/cabinet" && docker compose up -d
            cd "$BASE_DIR/caddy" && docker compose up -d
            echo -e "${GREEN}[✅] Проект успешно запущен!${NC}"; pause ;;
        4) 
            cd "$BASE_DIR/bot" && docker compose stop
            cd "$BASE_DIR/cabinet" && docker compose stop
            cd "$BASE_DIR/caddy" && docker compose stop
            echo -e "${RED}[🛑] Проект остановлен!${NC}"; pause ;;
        5) config_menu ;;
        6) 
            echo -e "${CYAN}Чьи логи смотрим? (1 - Бот, 2 - Кабинет, 3 - Caddy)${NC}"
            read l_choice
            case $l_choice in
                1) cd "$BASE_DIR/bot" && docker compose logs -f --tail=50 ;;
                2) cd "$BASE_DIR/cabinet" && docker compose logs -f --tail=50 ;;
                3) cd "$BASE_DIR/caddy" && docker compose logs -f --tail=50 ;;
            esac
            ;;
        7) check_versions ;;
        8) update_self ;;
        0) clear; echo -e "${GREEN}Успешной работы ST VILLAGE!${NC}\n"; exit 0 ;;
        *) echo -e "${RED}Неизвестная команда.${NC}"; sleep 1 ;;
    esac
done
