# Changelog

Все заметные изменения проекта документируются в этом файле.

## 1.0.0 — 2026-08-05

- Полностью заменён монолитный повреждённый скрипт модульным Bedolaga Manager.
- Добавлен one-line bootstrap и постоянная команда `bedolaga`.
- Добавлена идемпотентная установка Bot, Cabinet, PostgreSQL, Redis и Caddy.
- Добавлен интерактивный мастер с валидацией и локальной генерацией секретов.
- Закрыты host-порты Bot, Cabinet, PostgreSQL и Redis.
- Добавлены health checks, `doctor`, статусы и логи.
- Добавлены pre-update backup, безопасные detached checkout и rollback.
- Добавлены целевые бэкапы, SHA-256, restore и systemd timer.
- Добавлены ShellCheck, smoke-тесты и Compose-проверка в CI.
