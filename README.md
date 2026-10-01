<div align="center">

# 🚀 Bedolaga Auto Installer

### Bedolaga Bot + Cabinet + Xray Checker + Status Page одной командой

[![CI](https://img.shields.io/github/actions/workflow/status/Reibik/Auto_Install-Bedolaga_Bot/ci.yml?branch=main&style=for-the-badge&logo=githubactions&logoColor=white&label=CI)](https://github.com/Reibik/Auto_Install-Bedolaga_Bot/actions/workflows/ci.yml)
[![Security](https://img.shields.io/github/actions/workflow/status/Reibik/Auto_Install-Bedolaga_Bot/security.yml?branch=main&style=for-the-badge&logo=githubactions&logoColor=white&label=Security)](https://github.com/Reibik/Auto_Install-Bedolaga_Bot/actions/workflows/security.yml)
[![License](https://img.shields.io/github/license/Reibik/Auto_Install-Bedolaga_Bot?style=for-the-badge&color=7c3aed)](LICENSE)
[![Shell](https://img.shields.io/badge/Shell-Bash-22c55e?style=for-the-badge&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Release](https://img.shields.io/github/v/release/Reibik/Auto_Install-Bedolaga_Bot?style=for-the-badge&logo=github&color=06b6d4)](https://github.com/Reibik/Auto_Install-Bedolaga_Bot/releases/latest)

**Автоматическая установка · Xray Monitoring · HTTPS · Обновления · Бэкапы · Диагностика**

[Что нового](#whats-new) · [Быстрый старт](#quick-start) · [Обновление](#upgrade) · [Управление](#management) · [Поддержка](#support)

</div>

![Bedolaga Manager — Bot, Cabinet, Xray Checker и Status Page](docs/assets/bedolaga-stack-preview.png)

> [!NOTE]
> **Bedolaga Manager** разворачивает [Bedolaga Bot](https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot), [Bedolaga Cabinet](https://github.com/BEDOLAGA-DEV/bedolaga-cabinet), PostgreSQL, Redis и Caddy. По желанию тот же мастер устанавливает [Xray Checker](https://github.com/kutovoys/xray-checker) и [Xray Checker Status Page](https://github.com/Mrvibecodic/xray-checker-statuspage/tree/go-build).

---

<a id="whats-new"></a>
## 🎛️ Что нового в v1.4.0

**Новое компактное меню теперь в стабильном релизе.** Шесть понятных разделов, полезный обзор и удобная работа даже в узкой web-консоли. Команды CLI и конфигурация существующих установок сохраняются.

| Изменение | Что это значит для вас |
|---|---|
| 🧭 Шесть разделов с подменю | Сервисы, обновления, настройки, бэкапы, диагностика и Xray — без длинного списка действий |
| 📊 Полезный обзор | Состояние Bot / Cabinet, готовность стека, включение Xray и дата последнего архива |
| 📐 Адаптивное оформление | Баннеры и подписи подстраиваются под терминалы шириной 20–80 колонок |
| 🩺 Точные статусы | Штатная остановка, код завершения, пауза и недоступный Docker отображаются отдельно |

📖 [Описание релиза v1.4.0](https://github.com/Reibik/Auto_Install-Bedolaga_Bot/releases/tag/v1.4.0) · [Полный список изменений](CHANGELOG.md)

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
| 📡 | **Опциональный Xray Monitoring** | Проверка прокси, публичная Status Page и отдельный Telegram-бот управления |

---

<a id="quick-start"></a>
## 🚀 Быстрый старт

Запустите на **чистом сервере** от имени `root`:

```bash
BEDOLAGA_REF=v1.4.0 BEDOLAGA_EXPECTED_VERSION=1.4.0 bash <(curl -fsSL https://raw.githubusercontent.com/Reibik/Auto_Install-Bedolaga_Bot/v1.4.0/install.sh)
```

Команда устанавливает **конкретный стабильный релиз v1.4.0 с новым меню**, а не текущее содержимое ветки `main`. Установщик проверит систему, задаст вопросы по конфигурации, развернёт сервисы и проверит их работоспособность. После завершения откройте главное меню:

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
- для опционального Xray Monitoring: ещё один домен и URL VPN-подписки.

</details>

> [!IMPORTANT]
> Установщик **не разворачивает Remnawave Panel**. Она должна быть установлена заранее и доступна по API.

### Что спросит мастер

1. Telegram Bot Token и ID администраторов.
2. URL и API key Remnawave.
3. Домены Telegram webhook и Cabinet.
4. Email для Let's Encrypt.
5. Название проекта, короткий логотип и часовой пояс.
6. Нужно ли установить Xray Checker + Status Page.

Если включить Xray Monitoring, мастер дополнительно запросит отдельный домен, URL одной или нескольких подписок, интервал проверок и, по желанию, токен **отдельного** Telegram-бота Status Page. Использовать токен основного Bedolaga Bot нельзя: основной бот работает через webhook, а Status Page использует собственный Telegram control plane.

Username бота определяется автоматически через Telegram API. Пароли PostgreSQL, JWT и служебные секреты генерируются локально.

> [!TIP]
> Перед вводом Telegram Bot Token мастер предложит два режима: **скрытый** для обычного SSH и **видимый** для web-консолей, блокирующих вставку в скрытые поля. Если в скрытом режиме значение не было получено, переключиться на видимый можно без перезапуска установки. Секреты не записываются в лог или историю команд.

---

<a id="upgrade"></a>
## 🔄 Уже установлено? Обновитесь без переустановки

На сервере от имени `root` выполните:

```bash
bedolaga version
bedolaga self-update
bedolaga version
bedolaga status
```

После обновления до этого релиза команда `bedolaga version` покажет `Bedolaga Manager 1.4.0`. Если уже выпущен более новый стабильный релиз, `self-update` установит его. Для перехода именно на v1.4.0 из более ранней версии используйте `bedolaga self-update v1.4.0`. Затем запустите `bedolaga`, чтобы открыть новое меню.

> [!TIP]
> При включённом автообновлении новый интерфейс придёт при следующем открытии `bedolaga`, когда истечёт часовой кэш проверки и будет доступен GitHub. Чтобы получить его сразу, выполните `bedolaga self-update`. Если автообновление отключено или установлена версия без этой функции, используйте ручное обновление.

| Что хотите обновить | Команда | Что изменится |
|---|---|---|
| 🎛️ Установщик и меню управления | `bedolaga self-update` | Только код Manager; контейнеры приложений не пересоздаются |
| 🤖 Bot и Cabinet, а также включённый Xray Monitoring | `bedolaga update all` | Компоненты приложений; перед обновлением создаются резервные копии |
| 📡 Только Xray Monitoring | `bedolaga xray update` | Checker и Status Page, если модуль настроен |

> [!IMPORTANT]
> Обновление Manager **не требует повторного мастера настройки**, не удаляет `.env` и не заменяет том PostgreSQL. Не запускайте новую установку на работающем сервере вместо `self-update`.

> [!NOTE]
> Стек сохраняет PostgreSQL 15 и существующий том базы данных. Переход на PostgreSQL 18 требует отдельной миграции и не выполняется автоматически. Подробнее — в [документации по архитектуре](docs/ARCHITECTURE.md#модель-обновления).

---

<a id="management"></a>
## 🎛️ Управление

Запустите интерактивное меню без аргументов:

```bash
bedolaga
```

Меню автоматически использует цвета, эмодзи и Unicode-разделители в совместимом интерактивном терминале. Для минимального ASCII-вывода:

```bash
NO_COLOR=1 BEDOLAGA_EMOJI=0 bedolaga
```

Эмодзи можно принудительно включить через `BEDOLAGA_EMOJI=1`.

### 🧭 Компактное меню управления

> [!NOTE]
> Новое меню входит в **стабильный Release v1.4.0**. Оно доступно при новой установке и после `bedolaga self-update`; обновление Manager не пересоздаёт контейнеры Bot и Cabinet.

Главный экран показывает состояние Bot и Cabinet, общую готовность стека, включение Xray и дату последнего архива с файлом SHA-256. Дата архива не заменяет проверку его целостности или пробное восстановление.

Действия сгруппированы в шесть разделов:

| Раздел | Что внутри |
|---|---|
| 🐳 **Сервисы** | Статус, запуск, остановка, перезапуск и логи выбранного сервиса |
| ⬆️ **Обновления** | Проверка версий, обновление всех приложений или отдельно Bot / Cabinet, обновление Manager и откат |
| ⚙️ **Настройки** | Редактирование Bot, стека и Caddy, пути файлов, мастер и применение изменений |
| 💾 **Резервные копии** | Создание, список, восстановление и управление ежедневными бэкапами |
| 🩺 **Диагностика** | ОС и Docker, полная проверка проекта, статусы и логи |
| 📊 **Xray Monitoring** | Отдельное меню Checker и Status Page |

`0` возвращает на уровень выше; в главном меню — завершает работу. При выборе сервиса `0` означает «все сервисы», а `b` — отмену. В подменю Enter без номера возвращает назад. Восстановление из архива по-прежнему требует явной фразы `RESTORE`.

Оформление подстраивается под ширину терминала в диапазоне 20–80 колонок. Подписи и длинные адреса переносятся без разрыва UTF-8 символов. При изменении размера окна ширина обновляется при следующем показе меню. Ширину можно задать вручную:

```bash
BEDOLAGA_UI_WIDTH=40 bedolaga
```

Зелёный означает готовность, жёлтый — ожидание или предупреждение, красный — ошибку либо опасное действие. Любое состояние также подписано текстом: штатная остановка с кодом `0`, ненулевой код завершения, пауза, перезапуск и недоступность Docker различаются.

### ✨ Автообновление Manager

При открытии меню командой `bedolaga` Manager проверяет последний **стабильный GitHub Release**. Если доступна новая версия, перед установкой показываются:

- текущая и новая версии;
- понятное направление обновления, например `v1.3.1 → v1.4.0`;
- три главных изменения из changelog нового релиза.

Обновление выполняется автоматически из опубликованного релизного архива конкретного тега. Manager проверяет SHA-256, версию внутри архива, Bash-синтаксис и пробный запуск до замены рабочей установки. Блокировки защищают от одновременных обновлений; при ошибке рабочая версия сохраняется. Недоступность GitHub не блокирует открытие меню.

Чтобы не задерживать каждый запуск, результат проверки кэшируется на один час; при недоступном GitHub меню продолжает работать. Ручная команда `self-update` не ждёт окончания этого интервала. Отключить автообновление для конкретного запуска:

```bash
BEDOLAGA_AUTO_UPDATE=0 bedolaga
```

Ручная проверка и обновление до последнего стабильного релиза:

```bash
bedolaga self-update
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
| `bedolaga config bot` | Открыть конфигурацию Bot в редакторе |
| `bedolaga config stack` | Открыть системные параметры Compose |
| `bedolaga config paths` | Показать расположение всех файлов конфигурации |
| `bedolaga apply` | Применить `.env`, Caddy и branding |
| `bedolaga versions` | Сравнить локальные и доступные версии |
| `bedolaga update [all\|bot\|cabinet\|xray]` | Обновить весь проект или компонент |
| `bedolaga xray` | Открыть красивое меню Xray Monitoring |
| `bedolaga xray install` | Установить или перенастроить Xray Checker + Status Page |
| `bedolaga xray status` | Показать состояние, домен, интервал и используемые образы |
| `bedolaga xray logs [checker\|statuspage]` | Открыть логи модуля |
| `bedolaga xray update` | Обновить Checker и исходники Status Page с автоматическим откатом |
| `bedolaga xray disable` | Отключить модуль с сохранением настроек и данных |
| `bedolaga xray remove --purge-data` | Полностью удалить модуль и его данные |
| `bedolaga rollback` | Откатить последнее обновление приложений |
| `bedolaga backup` | Создать резервную копию |
| `bedolaga backup-list` | Показать доступные копии |
| `bedolaga restore <archive>` | Восстановить выбранную копию |
| `bedolaga schedule enable` | Включить ежедневные автобэкапы |
| `bedolaga firewall enable` | Настроить UFW для SSH, HTTP и HTTPS |
| `bedolaga self-update [vX.Y.Z]` | Обновить Manager до последней или указанной стабильной версии |

Доступные сервисы для `logs` и `restart`: `bot`, `cabinet`, `caddy`, `postgres`, `redis`, а при включённом модуле — `xray-statuspage` и `xray-checker`.

### 📁 Где находятся `.env` и настройки?

Конфигурация основного бота хранится в **`/etc/bedolaga/bot.env`**, а параметры Docker Compose и доменов — в **`/etc/bedolaga/stack.env`**. Это рабочие файлы Manager; редактировать `.env.example` в исходниках для настройки сервера не нужно.

```bash
bedolaga config paths    # показать все пути
bedolaga config bot      # открыть настройки бота
bedolaga config stack    # открыть параметры стека
bedolaga apply           # применить сохранённые изменения
```

> [!WARNING]
> `.env` содержит токены и пароли. Не публикуйте его и не прикладывайте к issues или скриншотам без удаления секретов.

<details>
<summary><strong>📡 Как устроен Xray Monitoring</strong></summary>

- модуль выключен по умолчанию и никак не влияет на Bot/Cabinet;
- Xray Checker получает подписки через внутренний endpoint Status Page;
- оба сервиса используют общее изолированное сетевое пространство, необходимое upstream-проекту для связи через `localhost`;
- порты `2112`, `8080`, `8081` и диапазон Xray не публикуются на host;
- пользователи открывают Status Page только по отдельному HTTPS-домену через Caddy;
- Status Page собирается из официальной ветки `go-build`, поэтому установка работает на AMD64 и ARM64;
- база, ключ шифрования и настройки Status Page хранятся в `/var/lib/bedolaga/xray-statuspage` и входят в бэкапы Manager.

Для уже работающей установки сначала обновите Manager, затем запустите:

```bash
bedolaga self-update
bedolaga xray install
```

</details>

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
    Caddy -->|status.example.com| StatusPage[📊 Xray Status Page]
    StatusPage <-->|localhost| Checker[📡 Xray Checker]
    Checker --> Subscriptions[🔗 VPN subscriptions]
```

- наружу публикуются только `80/TCP`, `443/TCP` и `443/UDP`;
- PostgreSQL и Redis находятся во внутренней Docker-сети;
- Bot и Cabinet не публикуют host-порты напрямую;
- опциональные Xray Checker и Status Page также не публикуют host-порты;
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

Если Xray Monitoring включён, `bedolaga update all` также создаёт бэкап, обновляет официальный image Checker и detached checkout ветки `go-build`. При неудачной сборке или health check Manager возвращает предыдущий commit Status Page и прежний image Checker.

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
- база, настройки и зашифрованные подписки Xray Status Page;
- версии Manager, Bot и Cabinet;
- SHA-256 checksum для проверки целостности.

Автобэкап запускается systemd timer примерно в `03:00`. По умолчанию хранятся семь автоматических архивов; ручные и аварийные копии автоматически не удаляются.

В v1.3.1 ошибка копирования данных, создания PostgreSQL dump перед обновлением, упаковки или расчёта checksum возвращает ошибку. Незавершённый архив и временный каталог очищаются; обновление приложений не продолжается с таким бэкапом.

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
/opt/bedolaga/sources/xray-statuspage/  ветка go-build опциональной Status Page
/etc/bedolaga/stack.env                 параметры Compose
/etc/bedolaga/bot.env                   конфигурация Bot
/etc/bedolaga/Caddyfile                 reverse proxy
/var/lib/bedolaga/bot/                  постоянные данные Bot
/var/lib/bedolaga/xray-statuspage/      данные опциональной Status Page
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
for script in bedolaga install.sh tests/*.sh lib/*.sh; do bash -n "$script"; done
shellcheck -x bedolaga install.sh tests/*.sh lib/*.sh
bash tests/smoke.sh
bash tests/lifecycle.sh
bash tests/xray.sh
bash tests/ui.sh
bash tests/menu.sh
bash tests/manager-update.sh
bash tests/installer.sh
bash tests/backup.sh
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
- [kutovoys / xray-checker](https://github.com/kutovoys/xray-checker)
- [Mrvibecodic / xray-checker-statuspage (go-build)](https://github.com/Mrvibecodic/xray-checker-statuspage/tree/go-build)

---

## 📄 Лицензия

Bedolaga Auto Installer распространяется по лицензии [MIT](LICENSE). Устанавливаемые upstream-сервисы распространяются их авторами на условиях собственных лицензий.

<div align="center">

**Сделано с заботой о простой и безопасной установке** 💜

⭐ Если проект полезен — поставьте звезду репозиторию

</div>
