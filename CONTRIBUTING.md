# Руководство по участию в проекте

Спасибо за интерес к проекту **ST Village**! Мы рады любому вкладу.

## Как внести вклад

### 1. Сообщить о баге

- Откройте [Issue](https://github.com/Reibik/Auto_Install-Bedolaga_Bot/issues/new) на GitHub
- Опишите проблему максимально подробно:
  - Версия скрипта (`PANEL_VERSION` в начале файла)
  - ОС и её версия (Ubuntu 22.04, Debian 12, и т.д.)
  - Шаги для воспроизведения
  - Ожидаемое и фактическое поведение
  - Логи ошибок (если есть)

### 2. Предложить улучшение

- Создайте Issue с тегом `enhancement`
- Опишите, что вы хотите улучшить и почему
- Приложите примеры использования, если возможно

### 3. Отправить Pull Request

1. **Fork** репозитория
2. Создайте ветку для вашей задачи:
   ```bash
   git checkout -b feature/my-feature
   # или
   git checkout -b fix/my-bugfix
   ```
3. Внесите изменения
4. Проверьте код (см. ниже)
5. Сделайте коммит с описательным сообщением:
   ```bash
   git commit -m "feat: добавлена проверка свободного места перед установкой"
   ```
6. Отправьте ветку:
   ```bash
   git push origin feature/my-feature
   ```
7. Создайте Pull Request

## Стиль кода

### Bash

- Используйте `#!/usr/bin/env bash` в shebang
- Включайте `set -Eeuo pipefail` в начале скрипта
- Все переменные должны быть в двойных кавычках: `"$var"`, `"${var}"`
- Используйте `[[ ]]` вместо `[ ]` для условий
- Разделяйте `local` объявление и присваивание через `$()`:
  ```bash
  # Правильно:
  local my_var=""
  my_var="$(some_command)"

  # Неправильно:
  local my_var="$(some_command)"
  ```
- Функции именуйте в `snake_case`
- Добавляйте комментарии к сложной логике
- Используйте `die`, `err`, `warn`, `ok`, `log` для вывода сообщений

### Именование коммитов

Используйте [Conventional Commits](https://www.conventionalcommits.org/):

| Префикс    | Назначение                 |
|------------|----------------------------|
| `feat:`    | Новая функциональность     |
| `fix:`     | Исправление бага           |
| `docs:`    | Изменения в документации   |
| `refactor:`| Рефакторинг кода           |
| `test:`    | Добавление тестов          |
| `chore:`   | Прочие изменения           |

## Проверка кода

Перед отправкой PR убедитесь, что:

### ShellCheck

Установите [ShellCheck](https://www.shellcheck.net/) и проверьте скрипт:

```bash
shellcheck st_village.sh
```

Все предупреждения должны быть исправлены или явно подавлены с обоснованием:

```bash
# shellcheck disable=SC2034  # Переменная используется в другой функции
```

### Проверка синтаксиса

```bash
bash -n st_village.sh
```

### Тестирование

- Проверьте изменения на чистой системе Ubuntu 22.04 или Debian 12
- Убедитесь, что установка, обновление и удаление работают корректно
- Проверьте все затронутые пункты меню

## Структура проекта

```
├── st_village.sh               # Основной скрипт панели (v19.0, 1819 строк)
├── .github/
│   └── workflows/
│       ├── check.yml           # ShellCheck + bash syntax
│       └── security.yml        # Security Scan (секреты, permissions)
├── assets/
│   └── panel_preview.svg       # SVG-превью панели
├── docs/
│   └── README.md               # Документация проекта
├── examples/
│   ├── README.md               # Описание примеров
│   ├── bot.env.example         # Пример .env бота
│   ├── cabinet.env.example     # Пример .env кабинета
│   └── Caddyfile.example       # Пример Caddyfile
├── CHANGELOG.md                # История изменений (v16-v19)
├── CONTRIBUTING.md             # Это руководство
├── LICENSE                     # MIT лицензия
├── README.md                   # Главный README
├── RELEASE_NOTES.md            # Заметки о текущем релизе
└── SECURITY.md                 # Политика безопасности
```

## Лицензия

Внося изменения, вы соглашаетесь с тем, что они будут лицензированы под [MIT License](LICENSE).

## Вопросы?

- [Telegram-чат поддержки](https://t.me/+wTdMtSWq8YdmZmVi)
- [GitHub Issues](https://github.com/Reibik/Auto_Install-Bedolaga_Bot/issues)
