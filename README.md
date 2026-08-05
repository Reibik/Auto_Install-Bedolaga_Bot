# Bedolaga Auto Installer

Безопасный установщик и менеджер для полного стека
[Bedolaga Bot](https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot) +
[Bedolaga Cabinet](https://github.com/BEDOLAGA-DEV/bedolaga-cabinet) + PostgreSQL + Redis + Caddy.

Одна команда устанавливает системные зависимости, задаёт вопросы по конфигурации, собирает контейнеры, получает HTTPS-сертификаты и проверяет здоровье сервисов. После установки всё управляется командой `bedolaga`.

## Быстрый старт

Перед запуском подготовьте:

- чистый сервер Ubuntu 22.04/24.04 или Debian 12;
- минимум 1 GB RAM и 4 GB свободного места, рекомендуется 2 GB RAM и 10 GB;
- свободные входящие порты 80 и 443;
- root-доступ;
- два домена с A-записями на IP сервера;
- токен Telegram-бота и Telegram ID администратора;
- URL и API key уже работающей Remnawave Panel.

Запуск:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Reibik/Auto_Install-Bedolaga_Bot/main/install.sh)
```

Установка зафиксированного релиза:

```bash
BEDOLAGA_REF=v1.0.0 bash <(curl -fsSL https://raw.githubusercontent.com/Reibik/Auto_Install-Bedolaga_Bot/main/install.sh)
```

Установщик спросит:

1. Telegram Bot Token.
2. Telegram ID администраторов.
3. URL и API key Remnawave.
4. Домен Telegram webhook.
5. Домен Cabinet.
6. Email для Let's Encrypt.
7. Название, короткий логотип и часовой пояс.

Username бота определяется автоматически через Telegram API. Пароли PostgreSQL, JWT и webhook/API secrets генерируются локально через OpenSSL.

> Установщик не разворачивает саму Remnawave Panel. Она является обязательной внешней зависимостью Bedolaga Bot.

## Команды

```bash
bedolaga                         # интерактивное меню
bedolaga status                  # контейнеры и текущие commit
bedolaga start
bedolaga stop
bedolaga restart [service]
bedolaga apply                   # применить .env, Caddy и branding
bedolaga logs [service]
bedolaga doctor                  # DNS, HTTPS, Compose, API, health checks
bedolaga config wizard           # повторный мастер настройки
bedolaga config bot              # полный .env Bedolaga Bot
bedolaga config stack            # параметры стека и branding
bedolaga config caddy
bedolaga versions                # сравнить локальные и origin commit
bedolaga update [all|bot|cabinet]
bedolaga rollback
bedolaga backup
bedolaga backup-list
bedolaga restore <archive>
bedolaga schedule enable         # ежедневный systemd timer
bedolaga firewall enable         # UFW: текущий SSH-порт + 80/443
bedolaga self-update
```

Сервисы для `logs` и `restart`: `bot`, `cabinet`, `caddy`, `postgres`, `redis`.
После изменения конфигурации используйте `bedolaga apply`: обычный `restart` не перечитывает переменные окружения контейнера.

## Архитектура

```text
Internet :80/:443
        │
      Caddy ───── cabinet.example.com ── Cabinet
        │                  └── /api/* ── Bot API
        └──── hooks.example.com ──────── Bot webhook
                                             │
                                   PostgreSQL + Redis
                                             │
                                      Remnawave API
```

- Наружу публикуются только 80/TCP, 443/TCP и 443/UDP.
- PostgreSQL и Redis находятся в изолированной внутренней Docker-сети.
- Cabinet и Bot не публикуют host-порты.
- Caddy автоматически получает и продлевает TLS-сертификаты.
- Все Docker-ресурсы имеют label `dev.reibik.bedolaga.managed=true`.

Подробнее: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Файлы на сервере

```text
/usr/local/bin/bedolaga                 CLI
/usr/local/lib/bedolaga-manager/        код менеджера
/opt/bedolaga/compose.yaml              управляемый Compose
/opt/bedolaga/sources/bot/              checkout Bot
/opt/bedolaga/sources/cabinet/          checkout Cabinet
/etc/bedolaga/stack.env                 параметры Compose
/etc/bedolaga/bot.env                   полный .env Bot
/etc/bedolaga/Caddyfile                 reverse proxy
/var/lib/bedolaga/bot/                  постоянные данные Bot
/var/lib/bedolaga/backups/              резервные копии
/var/lib/bedolaga/state/                состояние обновлений
```

Секретные файлы создаются с правами `600`, каталоги конфигурации — `700`.
Логотип сообщений можно заменить в `/var/lib/bedolaga/bot/vpn_logo.png`; upstream checkout при этом останется чистым.

## Обновления и откат

`bedolaga update`:

1. Отказывается работать при локальных изменениях upstream checkout.
2. Получает новые commit из настроенной ветки.
3. Создаёт PostgreSQL dump и бэкап конфигурации.
4. Переключает checkout в detached mode без `git reset --hard`.
5. Собирает новые образы до перезапуска.
6. Запускает сервисы и ждёт health checks.
7. При ошибке автоматически возвращает предыдущие commit приложения.

Ручной откат:

```bash
bedolaga rollback
```

Откат приложения не откатывает миграции базы автоматически. Перед каждым обновлением сохраняется полный бэкап; при несовместимой схеме используйте `bedolaga restore`.

## Резервные копии

В архив входят:

- PostgreSQL dump в custom format;
- `stack.env`, `bot.env` и Caddyfile;
- постоянные данные, uploads и локали Bot;
- commit Bot/Cabinet и версия Manager;
- SHA-256 checksum.

Автобэкап выполняется systemd timer около 03:00. По умолчанию хранится семь автоматических архивов. Ручные и emergency-бэкапы автоматически не удаляются.

## Безопасное удаление

Сохранить данные и бэкапы:

```bash
bedolaga uninstall
```

Необратимо удалить контейнеры, volumes, конфигурацию и бэкапы:

```bash
bedolaga uninstall --purge-data
```

Полное удаление требует ввода фразы `PURGE-BEDOLAGA`.

## Разработка

```bash
bash -n bedolaga install.sh tests/*.sh lib/*.sh
shellcheck -x bedolaga install.sh tests/*.sh lib/*.sh
bash tests/smoke.sh
bash tests/lifecycle.sh
```

CI дополнительно проверяет итоговый Compose через `docker compose config`.
Матрица совместимости запускает тесты в чистых контейнерах Ubuntu 22.04, Ubuntu 24.04 и Debian 12.

## Лицензия

[MIT](LICENSE). Bedolaga Bot и Bedolaga Cabinet распространяются их авторами на условиях собственных лицензий.
