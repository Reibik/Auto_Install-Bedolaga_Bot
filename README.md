# 🚀 ST Village — Auto Install Bedolaga Bot

<img width="960" height="1115" alt="image" src="https://github.com/user-attachments/assets/9297d01e-8762-4856-863a-72ddadfaa277" />

Интерактивный bash-скрипт для автоматической установки и управления **[Bedolaga Telegram Bot](https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot)** + **[Bedolaga Cabinet](https://github.com/BEDOLAGA-DEV/bedolaga-cabinet)** + **Caddy** (reverse proxy с автоматическим SSL).

## 📋 Что делает скрипт

- Устанавливает Docker и все системные зависимости
- Клонирует репозитории бота и кабинета
- Генерирует конфигурации Caddy и docker-compose override
- Предоставляет интерактивную панель управления для всех операций

## ⚡ Быстрый старт

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Reibik/Auto_Install-Bedolaga_Bot/main/st_village.sh)
```

Или вручную:

```bash
curl -fsSL https://raw.githubusercontent.com/Reibik/Auto_Install-Bedolaga_Bot/main/st_village.sh -o /root/st_village.sh
chmod +x /root/st_village.sh
./st_village.sh
```

> **Требуется root.** Скрипт проверяет права при запуске.

## 📌 Требования

| Компонент | Минимум |
|-----------|---------|
| ОС | Ubuntu 20.04+ / Debian 11+ |
| RAM | 1 GB |
| Диск | 5 GB свободно |
| Права | root |
| Сеть | Открытые порты 80 и 443 |
| Домены | 2 домена (для бота и кабинета), направленные A-записью на IP сервера |

Docker и Docker Compose устанавливаются автоматически, если не обнаружены.

## 🏗 Архитектура

```
Браузер → Caddy (80/443, auto-SSL)
              ├─ bot.example.com     → remnawave_bot:8080      (Backend API)
              └─ cabinet.example.com
                    ├─ /api/*        → remnawave_bot:8080      (Cabinet API, strip /api)
                    └─ /*            → cabinet_frontend:80      (React SPA)
```

Все контейнеры объединены в Docker-сеть `remnawave-network`.

### Структура файлов на сервере

```
/root/
├── bot/                        # Bedolaga Bot (клон репозитория)
│   ├── docker-compose.local.yml
│   └── .env
├── cabinet/                    # Bedolaga Cabinet (клон репозитория)
│   ├── docker-compose.yml
│   ├── docker-compose.override.yml  # Автогенерируется скриптом
│   └── .env
├── caddy/                      # Caddy reverse proxy
│   ├── docker-compose.yml          # Автогенерируется скриптом
│   └── Caddyfile                   # Автогенерируется скриптом
├── backups/                    # Резервные копии
└── st_village.sh               # Этот скрипт
```

## 🔧 Настройка после установки

После первого запуска скрипт клонирует репозитории и покажет инструкции. Необходимо заполнить 3 файла:

### 1. Конфигурация бота — `/root/bot/.env`

Обязательные переменные:

| Переменная | Описание |
|------------|----------|
| `BOT_TOKEN` | Токен бота от [@BotFather](https://t.me/BotFather) |
| `ADMIN_IDS` | Telegram ID администратора |
| `WEB_API_ENABLED=true` | Включить веб-сервер (обязательно для кабинета) |
| `CABINET_ENABLED=true` | Включить Cabinet API |
| `CABINET_ALLOWED_ORIGINS` | Домен кабинета, например `https://cabinet.example.com` |
| `CABINET_JWT_SECRET` | Секрет для JWT (`openssl rand -hex 32`) |
| `REMNAWAVE_API_URL` | URL панели Remnawave |
| `REMNAWAVE_API_KEY` | API ключ панели Remnawave |

Полный список переменных — в файле `.env.example` в репозитории бота.

### 2. Конфигурация кабинета — `/root/cabinet/.env`

| Переменная | Описание |
|------------|----------|
| `VITE_TELEGRAM_BOT_USERNAME` | Username бота без `@` |
| `VITE_API_URL` | Путь к API (по умолчанию `/api`) |
| `VITE_APP_NAME` | Название в шапке (по умолчанию `Cabinet`) |

### 3. Домены в Caddyfile — `/root/caddy/Caddyfile`

Замените `bot.example.com` и `cabinet.example.com` на ваши реальные домены:

```caddyfile
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
```

> Caddy автоматически получает и обновляет SSL-сертификаты от Let's Encrypt.

### Запуск

После заполнения конфигов выберите **пункт 3** в главном меню панели.

## 🖥 Панель управления
*<img width="484" height="562" alt="image" src="https://github.com/user-attachments/assets/09837048-c7f4-46bd-a1d8-5b104866dcce" />*
```
🚀 ST VILLAGE | ПАНЕЛЬ УПРАВЛЕНИЯ v15.0

🖥 СТАТУС СЕРВЕРА:
  ОС, Uptime, RAM, SSD, Docker

📊 ВЕРСИИ КОМПОНЕНТОВ:
  Бот: abc1234 (Актуально)
  Кабинет: def5678 ➜ доступна ghi9012 [обновить]

1. 🔄 Обновить Бота
2. 🔄 Обновить Кабинет
3. ▶️  Запустить проект (Bot + Cabinet + Caddy)
4. 🛑 Остановить проект
5. ⚙️  Редактор конфигураций
6. 📋 Просмотр логов
7. 🛡  Система и безопасность
8. 🔄 Обновить статусы
9. 📦 Обновить панель
0. ❌ Выход
```

### Возможности

| Функция | Описание |
|---------|----------|
| **Установка** | Автоматическое клонирование, подготовка `.env`, генерация Caddy-конфигов |
| **Запуск / Остановка** | Запуск и остановка всех трёх сервисов одной командой |
| **Обновление** | Обновление бота и кабинета до последней версии из `main` с автопересборкой |
| **Откат** | Откат бота или кабинета на предыдущий commit |
| **Конфигурации** | Редактирование `.env` бота, `.env` кабинета, Caddyfile через `nano` |
| **Логи** | Просмотр логов любого компонента в реальном времени |
| **Бэкапы** | Ручные и автоматические (ежедневные) бэкапы с ротацией |
| **Очистка Docker** | Удаление неиспользуемых образов, контейнеров и томов |
| **Самообновление** | Обновление самого скрипта панели |

## 💾 Автоматические бэкапы

Включение через меню **7 → 2**. Cron-задача запускается в 03:00 ежедневно:

```
0 3 * * * /root/st_village.sh cron_backup
```

- Бэкапы хранятся в `/root/backups/`
- Хранится до 7 последних авто-бэкапов (ротация)
- Из бэкапа исключаются `.venv`, `__pycache__`, `node_modules`, `.git`

## 🛠 Ручной запуск бэкапа

```bash
./st_village.sh
# Меню → 7 → 1
```

## 🔄 Обновление компонентов

При обновлении бота или кабинета скрипт:

1. Сохраняет текущий commit в `.last_commit`
2. Делает `git fetch` + `git reset --hard origin/main`
3. Пересобирает Docker-образы (`docker compose up -d --build`)

При необходимости — откат через меню **7 → 4/5**.

## ❓ FAQ

### Скрипт падает с ошибкой «Нет доступа к интерактивному терминалу»

Запускайте из обычной SSH-сессии, а не через `cron` или `nohup`.

### Caddy не получает сертификат

- Убедитесь, что порты 80 и 443 открыты
- Домены указывают на IP вашего сервера (A-запись)
- Не используйте `example.com` — замените на реальные домены

### Кабинет показывает ошибку CORS

Добавьте домен кабинета в `CABINET_ALLOWED_ORIGINS` в `/root/bot/.env` и перезапустите бот.

### 502 Bad Gateway

1. Проверьте, что бот запущен: `docker ps`
2. Проверьте, что все контейнеры в одной сети: `docker network inspect remnawave-network`

### Как полностью переустановить

```bash
cd /root
docker compose -f bot/docker-compose.local.yml down -v
docker compose -f cabinet/docker-compose.yml down -v
docker compose -f caddy/docker-compose.yml down -v
rm -rf bot cabinet caddy
./st_village.sh
```

## 📎 Связанные проекты

- [Bedolaga Telegram Bot](https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot) — Backend бота
- [Bedolaga Cabinet](https://github.com/BEDOLAGA-DEV/bedolaga-cabinet) — Web-кабинет
- [Remnawave](https://github.com/remnawave/backend) — VPN-панель
- [Документация Bedolaga](https://docs.bedolagam.ru/) — Полная документация
- [Telegram-чат](https://t.me/+wTdMtSWq8YdmZmVi) — Чат поддержки

## 🤝 Поддержка
Подкинуть на хлебушек:
* TON: UQBoEJvftr-Lz4xZoXSDRlJQbaRC_nZoMhvbi9ufeiMNLTOb
* USDT TRC20: TRu92kG4LZ7nmubW3o31x19WagejmNt9PC
* BTC: bc1qy82xy9sqp2kq4rvqjqrvfdl9k0s7hvy7pk3rnt

## 📄 Лицензия

Этот проект распространяется под лицензией **MIT**.
