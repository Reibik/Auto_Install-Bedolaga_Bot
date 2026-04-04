# Документация ST Village

## Содержание

1. [Быстрый старт](quickstart.md)
2. [Установка](installation.md)
3. [Конфигурация](configuration.md)
4. [Диагностика](troubleshooting.md)
5. [FAQ](faq.md)

## Обзор

ST Village — это автоматизированная панель управления для развертывания и управления стеком:
- **Bedolaga Telegram Bot** — backend бота
- **Bedolaga Cabinet** — веб-кабинет пользователя
- **Caddy** — reverse proxy с автоматическим SSL

## Архитектура

```
Internet
    ↓
Caddy (ports 80/443)
    ├─→ bot.example.com → remnawave_bot:8080
    └─→ cabinet.example.com
           ├─→ /api/* → remnawave_bot:8080
           └─→ /* → cabinet_frontend:80
```

## Системные требования

- **ОС**: Ubuntu 20.04+ / Debian 11+
- **RAM**: минимум 1 GB (рекомендуется 2 GB)
- **Диск**: минимум 5 GB свободного места
- **Права**: root доступ
- **Сеть**: открытые порты 80 и 443
- **Домены**: 2 домена с A-записями на IP сервера

## Быстрая установка

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Reibik/Auto_Install-Bedolaga_Bot/main/st_village.sh)
```

## Поддержка

- [GitHub Issues](https://github.com/Reibik/Auto_Install-Bedolaga_Bot/issues)
- [Telegram чат](https://t.me/+wTdMtSWq8YdmZmVi)
- [Документация Bedolaga](https://docs.bedolagam.ru/)
