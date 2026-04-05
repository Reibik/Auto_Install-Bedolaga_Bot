# 🚀 ST Village v19.0 — Release Notes

## Рефакторинг: -21% кода, 0% потерь функциональности

Версия 19.0 — масштабный рефакторинг скрипта `st_village.sh`. Размер уменьшен с **2313 до 1819 строк** (-494 строки, -21.4%) за счёт выделения 13 хелпер-функций и удаления дублированного кода. Все фичи v18.0 полностью сохранены.

---

## ✨ Что нового

### 13 хелпер-функций

| Функция | Назначение |
|---------|-----------|
| `_container_state()` | Получение состояния Docker-контейнера |
| `_state_icon()` | Иконка статуса (🟢/🔴/🟡) |
| `_get_ver_txt()` | Проверка git-версий (режимы `full`/`fast`) |
| `_resolve_domain()` | DNS-резолвер для валидации доменов |
| `_menu_header()` | Единая шапка меню |
| `_menu_choice()` | Единый промпт выбора пункта |
| `_cron_toggle()` | Универсальный enable/disable для cron-задач |
| `_ssl_days_left()` | Проверка срока SSL-сертификата |
| `_compose_stop_all()` | Остановка всех сервисов |
| `_compose_down_all()` | Удаление всех сервисов |
| `_prompt_env()` | Промпт для env wizard |
| `_flag_status()` | Отображение on/off статуса флагов |
| `_ensure_env()` | Инициализация `.env` из `.env.example` |

### Объединённые функции

- `check_ports()` + `check_ports_before_install()` → единая `check_ports()` с параметром `mode`

### Удалённый dead code

- `press_any_key_to_continue()` — был алиасом для `pause()`
- 6 отдельных cron toggle функций → заменены на `_cron_toggle()`

---

## 📊 Статистика

| Метрика | Значение |
|---------|---------|
| **Строк до** | 2313 |
| **Строк после** | 1819 |
| **Сокращение** | -494 строки (-21.4%) |
| **Новых хелперов** | 13 |
| **Удалено функций** | 8 (dead code + дубликаты) |

---

## 🔄 Обновление с v18.0

```bash
./st_village.sh
# Меню → 12 (Самообновление скрипта)
```

Все конфигурации и данные сохраняются при обновлении.

---

## 📥 Чистая установка

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Reibik/Auto_Install-Bedolaga_Bot/main/st_village.sh)
```

---

## 📚 Документация

- [README](README.md) — основная документация
- [CHANGELOG](CHANGELOG.md) — полная история изменений
- [CONTRIBUTING](CONTRIBUTING.md) — руководство по участию
- [SECURITY](SECURITY.md) — политика безопасности

---

## 📎 Связанные проекты

- [Bedolaga Telegram Bot](https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot) — Backend бота
- [Bedolaga Cabinet](https://github.com/BEDOLAGA-DEV/bedolaga-cabinet) — Web-кабинет
- [Remnawave](https://github.com/remnawave/backend) — VPN-панель
- [Документация Bedolaga](https://docs.bedolagam.ru/) — Полная документация
- [Telegram-чат](https://t.me/+wTdMtSWq8YdmZmVi) — Чат поддержки

---

**Полный список изменений:** [CHANGELOG.md](CHANGELOG.md)

**Дата релиза:** 5 апреля 2026
**Автор:** [@Reibik](https://github.com/Reibik)
