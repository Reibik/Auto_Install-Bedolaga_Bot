# Изображения для README

[← Главная страница](../../README.md)

## Обложка

`bedolaga-hero-v2.png` — новая концептуальная иллюстрация, созданная встроенным imagegen 3 октября 2026 года. Это не скриншот Cabinet или Status Page. Версия не встроена в картинку, чтобы обложка не устаревала с каждым релизом. Предыдущие изображения сохранены для истории.

### Финальный prompt

```text
Use case: stylized-concept. Asset type: wide GitHub README hero illustration for the open-source Bedolaga Auto Installer. Create a beautiful premium modern product banner on a midnight navy background, restrained cyan and violet accents inspired by the existing tech presentation. Subject: an elegant interconnected stack of a Telegram-style bot represented by an original robot/chat icon, a cabinet browser panel and two monitoring panels representing Xray Checker and Xray Checker Status Page, connected to a compact server hub. These are decorative conceptual illustrations, not real screenshots; no fabricated stats or product claims. Composition: landscape 16:9, strong visual hierarchy, generous margins, balanced large typography and polished 3D glass/metal device illustration, crisp readable at README width, controlled lighting, subtle depth, no dense cyberpunk clutter. Text verbatim: large 'BEDOLAGA'; subtitle 'Bot + Cabinet'; smaller labels 'Xray Checker' and 'Xray Checker Status Page'. Render these four phrases exactly and no other text. Do not embed version numbers, commands or secrets. No unrelated company logos, no watermark. A cohesive sophisticated developer-tool visual, not a collage.
```

## Образец меню

`bedolaga-menu.svg` — детерминированное оформление настоящего вывода `bash tests/menu.sh --preview`, а не AI-макет интерфейса. Все состояния сервисов и дата архива — тестовые данные. Скрипт не обращается к рабочему Docker или серверу.

Пересоздать после изменения меню или версии (нужны Node.js и Bash с Unix-утилитами):

```bash
node scripts/render-menu-preview.mjs
node scripts/render-menu-preview.mjs --check
```

На Windows укажите Git Bash в PowerShell:

```powershell
$env:BEDOLAGA_PREVIEW_BASH = 'C:/Program Files/Git/usr/bin/bash.exe'
node scripts/render-menu-preview.mjs
node scripts/render-menu-preview.mjs --check
```

Результат записывается только в `docs/assets/bedolaga-menu.svg`. Сохраняйте его вместе с правками интерфейса. После функциональных изменений также обновляйте README и руководство, включая закреплённую команду установки при выпуске стабильной версии.
