#!/bin/bash

# Цвета для вывода
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
NC="\033[0m" # Без цвета

# Заголовок
function print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}        УСТАНОВКА BEDOLAGA BOT          ${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Функция для вывода сообщения в зеленом цвете
function print_success() {
    echo -e "${GREEN}$1${NC}"
}

# Функция для вывода сообщения в красном цвете
function print_error() {
    echo -e "${RED}$1${NC}"
}

# Функция для вывода сообщения в желтом цвете
function print_warning() {
    echo -e "${YELLOW}$1${NC}"
}

# Функция для вывода сообщения в синем цвете
function print_info() {
    echo -e "${BLUE}$1${NC}"
}

# Функция для установки зависимостей
function install_dependencies() {
    print_info "Установка зависимостей..."
    sudo apt update
    sudo apt install -y docker.io docker-compose caddy git
    print_success "Зависимости успешно установлены."
}

# Функция для клонирования репозиториев
function clone_repositories() {
    print_info "Клонирование репозиториев..."
    git clone https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot.git
    git clone https://github.com/BEDOLAGA-DEV/bedolaga-cabinet.git
    print_success "Репозитории успешно клонированы."
}

# Функция для генерации файлов .env
function generate_env_files() {
    print_info "Генерация файлов .env..."
    # Пример .env для бота
    cat <<EOF > remnawave-bedolaga-telegram-bot/.env
BOT_TOKEN=ваш_токен_бота
DB_HOST=localhost
DB_PORT=5432
DB_USER=ваш_пользователь_БД
DB_PASSWORD=ваш_пароль_БД
EOF

    # Пример .env для кабинета
    cat <<EOF > bedolaga-cabinet/.env
APP_ENV=production
APP_KEY=ваш_ключ_приложения
DB_HOST=localhost
DB_PORT=5432
DB_USER=ваш_пользователь_БД
DB_PASSWORD=ваш_пароль_БД
EOF

    print_success "Файлы .env успешно сгенерированы."
}

# Функция для настройки Caddy
function configure_caddy() {
    print_info "Настройка Caddy..."
    cat <<EOF > Caddyfile
{
    email ваш-email@example.com
}

bot.example.com {
    reverse_proxy localhost:3000
}

cabinet.example.com {
    reverse_proxy localhost:8000
}
EOF
    sudo mv Caddyfile /etc/caddy/Caddyfile
    sudo systemctl restart caddy
    print_success "Caddy успешно настроен."
}

# Функция для запуска сервисов
function start_services() {
    print_info "Запуск сервисов..."
    # Пример команд Docker Compose
    (cd remnawave-bedolaga-telegram-bot && docker-compose up -d)
    (cd bedolaga-cabinet && docker-compose up -d)
    print_success "Сервисы успешно запущены."
}

# Функция для отображения меню
function display_menu() {
    while true; do
        echo -e "\n${BLUE}========================================${NC}"
        echo -e "${GREEN}        МЕНЮ УСТАНОВКИ BEDOLAGA          ${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo "1. Установить зависимости"
        echo "2. Клонировать репозитории"
        echo "3. Сгенерировать файлы .env"
        echo "4. Настроить Caddy"
        echo "5. Запустить сервисы"
        echo "6. Выйти"
        read -p "Выберите опцию: " choice

        case $choice in
            1) install_dependencies ;;
            2) clone_repositories ;;
            3) generate_env_files ;;
            4) configure_caddy ;;
            5) start_services ;;
            6) break ;;
            *) print_error "Неверный выбор. Попробуйте снова." ;;
        esac
    done
}

# Основной блок выполнения скрипта
print_header
if [[ $1 == "--auto" ]]; then
    print_info "Запуск в режиме автоматической установки..."
    install_dependencies
    clone_repositories
    generate_env_files
    configure_caddy
    start_services
    print_success "Автоматическая установка успешно завершена."
else
    display_menu
fi