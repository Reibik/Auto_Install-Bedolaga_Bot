# 🚀 Скрипт авто-установки Bedolaga Bot и Cabinet

Этот скрипт предназначен для автоматической установки и настройки двух приложений:

1. [Bedolaga Telegram Bot](https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot)
2. [Bedolaga Cabinet](https://github.com/BEDOLAGA-DEV/bedolaga-cabinet)

---

## 🌟 Возможности

- ✅ Установка всех необходимых зависимостей (Docker, Docker Compose, Caddy, Git).
- ✅ Клонирование репозиториев.
- ✅ Генерация файлов `.env` с подсказками.
- ✅ Настройка SSL с помощью Caddy.
- ✅ Запуск сервисов через Docker Compose.
- ✅ Интерактивное меню для управления процессом установки.
- ✅ Автоматический режим установки (без взаимодействия с пользователем).

---

## ⚙️ Требования

- 🖥️ **Операционная система**: Ubuntu 20.04 или выше.
- 🔑 **Права доступа**: Права суперпользователя (sudo).

---

## 📥 Установка

### 1. Скачайте скрипт
```bash
curl -O https://example.com/install-bedolaga.sh
chmod +x install-bedolaga.sh
```

### 2. Запустите скрипт

#### Интерактивный режим
```bash
./install-bedolaga.sh
```

#### Автоматический режим
```bash
./install-bedolaga.sh --auto
```

---

## 🛠️ Использование

### Интерактивное меню
После запуска скрипта в интерактивном режиме вы увидите меню:

1. Установить зависимости
2. Клонировать репозитории
3. Сгенерировать файлы `.env`
4. Настроить Caddy
5. Запустить сервисы
6. Выйти

Выберите нужный пункт, чтобы выполнить соответствующее действие.

### Автоматический режим
В автоматическом режиме скрипт выполнит все шаги установки последовательно без необходимости взаимодействия с пользователем.

---

## 📄 Пример файлов `.env`

### Для бота
```env
BOT_TOKEN=ваш_токен_бота
DB_HOST=localhost
DB_PORT=5432
DB_USER=ваш_пользователь_БД
DB_PASSWORD=ваш_пароль_БД
```

### Для кабинета
```env
APP_ENV=production
APP_KEY=ваш_ключ_приложения
DB_HOST=localhost
DB_PORT=5432
DB_USER=ваш_пользователь_БД
DB_PASSWORD=ваш_пароль_БД
```

---

## 🌐 Настройка Caddy

Caddy автоматически настроит SSL для следующих доменов:

- `bot.example.com` для бота.
- `cabinet.example.com` для кабинета.

> ⚠️ **Важно**: Убедитесь, что вы заменили `example.com` на ваш реальный домен в файле `Caddyfile`.

---

## 📊 Логи и управление

### Просмотр логов
```bash
docker-compose logs -f
```

### Остановка сервисов
```bash
docker-compose down
```

### Перезапуск сервисов
```bash
docker-compose restart
```

---

## 🤝 Поддержка

Если у вас возникли вопросы или проблемы, создайте issue в соответствующем репозитории:

- [Bedolaga Telegram Bot](https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot/issues)
- [Bedolaga Cabinet](https://github.com/BEDOLAGA-DEV/bedolaga-cabinet/issues)

---

## 📜 Лицензия

Этот проект распространяется под лицензией **MIT**.