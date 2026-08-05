<div align="center">

# 🚀 Bedolaga Auto Installer

### Установка и управление Bedolaga Bot + Cabinet одной командой

[![CI](https://img.shields.io/github/actions/workflow/status/Reibik/Auto_Install-Bedolaga_Bot/ci.yml?branch=main&style=for-the-badge&logo=githubactions&logoColor=white&label=CI)](https://github.com/Reibik/Auto_Install-Bedolaga_Bot/actions/workflows/ci.yml)
[![Security](https://img.shields.io/github/actions/workflow/status/Reibik/Auto_Install-Bedolaga_Bot/security.yml?branch=main&style=for-the-badge&logo=githubactions&logoColor=white&label=Security)](https://github.com/Reibik/Auto_Install-Bedolaga_Bot/actions/workflows/security.yml)
[![License](https://img.shields.io/github/license/Reibik/Auto_Install-Bedolaga_Bot?style=for-the-badge&color=7c3aed)](LICENSE)
[![Shell](https://img.shields.io/badge/Shell-Bash-22c55e?style=for-the-badge&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)

**Автоматическая установка · HTTPS · Обновления · Откат · Бэкапы · Диагностика**

[Быстрый старт](#quick-start) · [Возможности](#features) · [Управление](#management) · [Архитектура](#architecture) · [Поддержка](#support)

</div>

![Пример работы установщика Bedolaga Manager](docs/assets/bedolaga-installer.png)

> [!NOTE]
> **Bedolaga Manager** разворачивает [Bedolaga Bot](https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot), [Bedolaga Cabinet](https://github.com/BEDOLAGA-DEV/bedolaga-cabinet), PostgreSQL, Redis и Caddy, а затем управляет всем стеком через единую команду `bedolaga`.

---

<a id="features"></a>
## ✨ Возможности

| | Возможность | Что получает пользователь |
|:--:|---|---|
| ⚡ | **Установка одной командой** | Проверка сервера, установка зависимостей и запуск всего стека |
| 🧙 | **Интерактивный мастер** | Пошаговая настройка Telegram, Remnawave, доменов и брендинга |
| 🔐 | **Безопасные секреты** | Локальная генерация паролей, JWT и webhook/API secrets через OpenSSL |
| 🌐 | **Автоматический HTTPS** | Caddy получает и продлевает TLS-сертификаты для Bot и Cabinet |
| 🔄 | **Контролируемые обновления** | Бэкап перед обновлением, health checks и автоматический откат при ошибке |
| 💾 | **Резервные копии** | PostgreSQL, конфигурация и данные с SHA-256 проверкой целостности |
| 🩺 | **Встроенная диагностика** | Проверка DNS, HTTPS, API, Docker Compose и состояния контейнеров |
| 🛡️ | **Безопасная сеть** | Наружу открыты только веб-порты, PostgreSQL и Redis изолированы |

---

<a id="quick-start"></a>
## 🚀 Быстрый старт

Запустите на **чистом сервере** от имени `root`:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Reibik/Auto_Install-Bedolaga_Bot/main/install.sh)
```

Установщик проверит систему, задаст вопросы по конфигурации, развернёт сервисы и проверит их работоспособность. После завершения откройте главное меню:

```bash
bedolaga
```

<details>
<summary><strong>📋 Требования к серверу и подготовка</strong></summary>

### Сервер

- Ubuntu 22.04 / 24.04 или Debian 12;
- минимум 1 GB RAM и 4 GB свободного места;
- рекомендуется 2 GB RAM и 10 GB свободного места;
- свободные входящие порты `80` и `443`;
- доступ пользователя `root`.

### Что подготовить заранее

- два домена с A-записями на IP сервера: для webhook и Cabinet;
- токен Telegram-бота;
- Telegram ID администратора или администраторов;
- URL и API key работающей Remnawave Panel;
- email для выпуска Let's Encrypt сертификатов.

</details>

> [!IMPORTANT]
> Установщик **не разворачивает Remnawave Panel**. Она должна быть установлена заранее и доступна по API.

### Что спросит мастер

1. Telegram Bot Token и ID администраторов.
2. URL и API key Remnawave.
3. Домены Telegram webhook и Cabinet.
4. Email для Let's Encrypt.
5. Название проекта, короткий логотип и часовой пояс.

Username бота определяется автоматически через Telegram API. Пароли PostgreSQL, JWT и служебные секреты генерируются локально.

> [!TIP]
> При вводе Telegram Bot Token и API key символы намеренно не отображаются. Вставьте значение через `Ctrl+Shift+V` или правую кнопку мыши и нажмите `Enter` — после успешного чтения установщик покажет подтверждение.

---

<a id="management"></a>
## 🎛️ Управление

Запустите интерактивное меню без аргументов:

```bash
bedolaga
```

Или используйте отдельные команды:

| Команда | Назначение |
|---|---|
| `bedolaga status` | Состояние контейнеров и текущие версии |
| `bedolaga start` | Запустить весь стек |
| `bedolaga stop` | Остановить весь стек |
| `bedolaga restart [service]` | Перезапустить стек или отдельный сервис |
| `bedolaga logs [service]` | Открыть логи сервиса |
| `bedolaga doctor` | Проверить DNS, HTTPS, API и контейнеры |
| `bedolaga config wizard` | Повторно запустить мастер настройки |
| `bedolaga apply` | Применить `.env`, Caddy и branding |
| `bedolaga versions` | Сравнить локальные и доступные версии |
| `bedolaga update [all\|bot\|cabinet]` | Обновить весь проект или компонент |
| `bedolaga rollback` | Откатить последнее обновление приложений |
| `bedolaga backup` | Создать резервную копию |
| `bedolaga backup-list` | Показать доступные копии |
| `bedolaga restore <archive>` | Восстановить выбранную копию |
| `bedolaga schedule enable` | Включить ежедневные автобэкапы |
| `bedolaga firewall enable` | Настроить UFW для SSH, HTTP и HTTPS |
| `bedolaga self-update` | Обновить Bedolaga Manager |

Доступные сервисы для `logs` и `restart`: `bot`, `cabinet`, `caddy`, `postgres`, `redis`.

> [!TIP]
> После изменения конфигурации используйте `bedolaga apply`. Обычный `restart` не перечитывает переменные окружения уже созданного контейнера.

---

<a id="architecture"></a>
## 🏗️ Архитектура

```mermaid
flowchart TD
    Internet([🌍 Internet :80 / :443]) --> Caddy[🔐 Caddy + automatic HTTPS]
    Caddy -->|cabinet.example.com| Cabinet[🖥️ Bedolaga Cabinet]
    Caddy -->|/api/*| BotAPI[🤖 Bot API]
    Caddy -->|hooks.example.com| Webhook[📨 Telegram Webhook]
    Cabinet --> BotAPI
    Webhook --> BotAPI
    BotAPI --> PostgreSQL[(🐘 PostgreSQL)]
    BotAPI --> Redis[(⚡ Redis)]
    BotAPI --> Remnawave[☁️ Remnawave API]
```

- наружу публикуются только `80/TCP`, `443/TCP` и `443/UDP`;
- PostgreSQL и Redis находятся во внутренней Docker-сети;
- Bot и Cabinet не публикуют host-порты напрямую;
- Caddy автоматически получает и продлевает TLS-сертификаты;
- управляемые Docker-ресурсы получают label `dev.reibik.bedolaga.managed=true`.

Подробнее: [документация по архитектуре](docs/ARCHITECTURE.md).

---

## 🔄 Обновления и откат

Команда `bedolaga update` выполняет безопасный цикл обновления:

1. Проверяет отсутствие локальных изменений в upstream checkout.
2. Получает новые версии Bot и Cabinet.
3. Создаёт дамп PostgreSQL и бэкап конфигурации.
4. Собирает новые Docker-образы до перезапуска сервисов.
5. Запускает стек и ожидает успешные health checks.
6. При ошибке автоматически возвращает предыдущие версии приложений.

Ручной откат:

```bash
bedolaga rollback
```

> [!WARNING]
> Откат версии приложения не отменяет миграции базы данных. Перед каждым обновлением создаётся полный бэкап; при несовместимости схемы используйте `bedolaga restore`.

---

## 💾 Резервные копии

В архив входят:

- дамп PostgreSQL в custom format;
- `stack.env`, `bot.env` и Caddyfile;
- постоянные данные, uploads и локали Bot;
- версии Manager, Bot и Cabinet;
- SHA-256 checksum для проверки целостности.

Автобэкап запускается systemd timer примерно в `03:00`. По умолчанию хранятся семь автоматических архивов; ручные и аварийные копии автоматически не удаляются.

---

## 🔒 Безопасность

- конфигурационные каталоги создаются с правами `700`;
- файлы с секретами создаются с правами `600`;
- секреты не передаются сторонним генераторам;
- база данных и Redis недоступны напрямую из интернета;
- UFW учитывает текущий SSH-порт перед применением правил;
- CI проверяет ShellCheck, распространённые форматы секретов и опасные shell-паттерны.

Инструкции по ответственному раскрытию уязвимостей находятся в [SECURITY.md](SECURITY.md).

---

<details>
<summary><strong>📁 Расположение файлов на сервере</strong></summary>

```text
/usr/local/bin/bedolaga                 CLI
/usr/local/lib/bedolaga-manager/        код менеджера
/opt/bedolaga/compose.yaml              управляемый Docker Compose
/opt/bedolaga/sources/bot/              исходный код Bot
/opt/bedolaga/sources/cabinet/          исходный код Cabinet
/etc/bedolaga/stack.env                 параметры Compose
/etc/bedolaga/bot.env                   конфигурация Bot
/etc/bedolaga/Caddyfile                 reverse proxy
/var/lib/bedolaga/bot/                  постоянные данные Bot
/var/lib/bedolaga/backups/              резервные копии
/var/lib/bedolaga/state/                состояние обновлений
```

Логотип сообщений можно заменить в `/var/lib/bedolaga/bot/vpn_logo.png` — upstream checkout останется чистым.

</details>

<details>
<summary><strong>🗑️ Безопасное удаление</strong></summary>

Удалить сервисы, сохранив данные и резервные копии:

```bash
bedolaga uninstall
```

Полностью удалить контейнеры, volumes, конфигурацию и бэкапы:

```bash
bedolaga uninstall --purge-data
```

Полное удаление необратимо и потребует ввода фразы `PURGE-BEDOLAGA`.

</details>

---

## 🧪 Разработка

```bash
bash -n bedolaga install.sh tests/*.sh lib/*.sh
shellcheck -x bedolaga install.sh tests/*.sh lib/*.sh
bash tests/smoke.sh
bash tests/lifecycle.sh
```

CI дополнительно проверяет итоговый Docker Compose и запускает тесты в чистых контейнерах Ubuntu 22.04, Ubuntu 24.04 и Debian 12.

Рекомендации для участников: [CONTRIBUTING.md](CONTRIBUTING.md).

---

<a id="support"></a>
## 💰 Поддержка

Если проект оказался полезным, можете поддержать разработку:

| Сеть | Адрес |
|---|---|
| **TON** | `UQBoEJvftr-Lz4xZoXSDRlJQbaRC_nZoMhvbi9ufeiMNLTOb` |
| **USDT TRC20** | `TRu92kG4LZ7nmubW3o31x19WagejmNt9PC` |
| **BTC** | `bc1qy82xy9sqp2kq4rvqjqrvfdl9k0s7hvy7pk3rnt` |

> [!CAUTION]
> Перед отправкой проверьте адрес и выбранную сеть. Криптовалютные переводы необратимы.

Спасибо за поддержку проекта! 💜

---

## 🤝 Связанные проекты

- [BEDOLAGA-DEV / remnawave-bedolaga-telegram-bot](https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot)
- [BEDOLAGA-DEV / bedolaga-cabinet](https://github.com/BEDOLAGA-DEV/bedolaga-cabinet)
- [Документация Bedolaga](https://bedolagadev.mintlify.app/introduction)

---

## 📄 Лицензия

Bedolaga Auto Installer распространяется по лицензии [MIT](LICENSE). Bedolaga Bot и Bedolaga Cabinet распространяются их авторами на условиях собственных лицензий.

<div align="center">

**Сделано с заботой о простой и безопасной установке** 💜

⭐ Если проект полезен — поставьте звезду репозиторию

</div>
