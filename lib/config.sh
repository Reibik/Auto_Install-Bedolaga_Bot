#!/usr/bin/env bash

validate_domain() {
  local domain="$1"
  [[ "$domain" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

validate_https_url() {
  local value="$1"
  [[ "$value" =~ ^https://[^[:space:]/]+(/[^[:space:]]*)?$ ]]
}

validate_bot_token() {
  [[ "$1" =~ ^[0-9]{6,}:[A-Za-z0-9_-]{20,}$ ]]
}

validate_admin_ids() {
  [[ "$1" =~ ^[0-9]+(,[0-9]+)*$ ]]
}

validate_username() {
  [[ "$1" =~ ^[A-Za-z0-9_]{5,32}$ ]]
}

validate_api_key() {
  [[ ${#1} -ge 8 && ${#1} -le 4096 && "$1" =~ ^[A-Za-z0-9._~+/-]+$ ]]
}

prompt_value() {
  local variable_name="$1"
  local label="$2"
  local default_value="${3:-}"
  local validator="${4:-}"
  local secret="${5:-0}"
  local value=''
  while true; do
    local suffix=''
    if [[ -n "$default_value" ]]; then
      if [[ "$secret" -eq 1 ]]; then
        suffix=" [Enter — оставить текущее]"
      else
        suffix=" [$default_value]"
      fi
    fi
    if [[ "$secret" -eq 1 ]]; then
      if [[ "${BEDOLAGA_VISIBLE_SECRET_INPUT:-0}" == "1" ]]; then
        read_tty value "${C_CYAN}${label}${suffix} [ВИДИМЫЙ ВВОД]: ${C_RESET}"
      else
        read_secret_tty value "${C_CYAN}${label}${suffix}: ${C_RESET}"
      fi
    else
      read_tty value "${C_CYAN}${label}${suffix}: ${C_RESET}"
    fi
    [[ -n "$value" ]] || value="$default_value"
    if [[ -z "$value" ]]; then
      if [[ "$secret" -eq 1 && "${BEDOLAGA_VISIBLE_SECRET_INPUT:-0}" != "1" ]]; then
        warn "Скрытый ввод не получил значение. Некоторые web-консоли блокируют вставку при отключённом отображении символов."
        if confirm "Переключиться на видимый ввод для секретов в текущем мастере?"; then
          BEDOLAGA_VISIBLE_SECRET_INPUT=1
          warn "Видимый ввод включён. Секрет будет отображаться на экране, но не попадёт в лог или историю команд."
          continue
        fi
      fi
      warn "Значение обязательно."
      continue
    fi
    if [[ -n "$validator" ]] && ! "$validator" "$value"; then
      warn "Некорректное значение. Попробуйте ещё раз."
      continue
    fi
    if [[ "$secret" -eq 1 ]]; then
      printf '%b\n' "${C_GREEN}$(ui_icon success)${C_RESET} Секретное значение принято." >/dev/tty
    fi
    printf -v "$variable_name" '%s' "$value"
    return 0
  done
}

configure_secret_input_mode() {
  local choice=''
  tty_available || die "Для мастера конфигурации требуется интерактивная SSH- или web-консоль."
  while true; do
    cat >/dev/tty <<'EOF'

Режим ввода Telegram Bot Token и API key:
  1. Скрытый — символы не отображаются (рекомендуется для SSH)
  2. Видимый — для web-консолей, которые блокируют вставку в скрытые поля
EOF
    read_tty choice "${C_CYAN}Выберите режим [1]: ${C_RESET}"
    case "$choice" in
      '' | 1)
        BEDOLAGA_VISIBLE_SECRET_INPUT=0
        return 0
        ;;
      2)
        BEDOLAGA_VISIBLE_SECRET_INPUT=1
        warn "Видимый ввод включён. Секреты будут видны на экране, но не попадут в лог или историю команд."
        return 0
        ;;
      *) warn "Введите 1 или 2." ;;
    esac
  done
}

telegram_api_request() {
  local token="$1"
  local method="$2"
  validate_bot_token "$token" || return 1
  [[ "$method" =~ ^[A-Za-z][A-Za-z0-9]*$ ]] || return 1
  # Передаём URL через stdin-конфиг curl: Bot Token не появляется в argv и ps.
  printf 'url = "https://api.telegram.org/bot%s/%s"\n' "$token" "$method" |
    curl -fsS --max-time 10 --config -
}

telegram_bot_username() {
  local token="$1"
  telegram_api_request "$token" getMe 2>/dev/null |
    jq -r 'if .ok == true then .result.username else empty end' 2>/dev/null || true
}

verify_telegram_token() {
  local token="$1"
  local username
  username="$(telegram_bot_username "$token")"
  [[ -n "$username" ]] || return 1
  printf '%s\n' "$username"
}

clone_managed_repo() {
  local url="$1"
  local target="$2"
  local title="$3"
  if [[ -d "$target/.git" ]]; then
    success "$title уже загружен."
    return 0
  fi
  if [[ -e "$target" ]] && [[ -n "$(find "$target" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    die "$target существует и не является управляемым Git-репозиторием."
  fi
  rmdir "$target" 2>/dev/null || true
  info "Клонирую $title."
  git clone --filter=blob:none "$url" "$target"
}

prepare_sources() {
  mkdir -p "$SOURCE_ROOT"
  clone_managed_repo "$BOT_REPOSITORY" "$BOT_SOURCE_DIR" "Bedolaga Bot"
  clone_managed_repo "$CABINET_REPOSITORY" "$CABINET_SOURCE_DIR" "Bedolaga Cabinet"
  mkdir -p "$DATA_ROOT/bot/logs" "$DATA_ROOT/bot/data" "$DATA_ROOT/bot/uploads"
  if [[ -d "$BOT_SOURCE_DIR/locales" ]]; then
    mkdir -p "$DATA_ROOT/bot/locales"
    cp -an "$BOT_SOURCE_DIR/locales/." "$DATA_ROOT/bot/locales/"
  fi
  if [[ ! -f "$DATA_ROOT/bot/vpn_logo.png" && -f "$BOT_SOURCE_DIR/vpn_logo.png" ]]; then
    cp -a "$BOT_SOURCE_DIR/vpn_logo.png" "$DATA_ROOT/bot/vpn_logo.png"
  fi
  chown -R 1000:1000 "$DATA_ROOT/bot" 2>/dev/null || true
}

sync_bot_assets() {
  mkdir -p "$DATA_ROOT/bot/locales"
  if [[ -d "$BOT_SOURCE_DIR/locales" ]]; then
    cp -an "$BOT_SOURCE_DIR/locales/." "$DATA_ROOT/bot/locales/"
  fi
  if [[ ! -f "$DATA_ROOT/bot/vpn_logo.png" && -f "$BOT_SOURCE_DIR/vpn_logo.png" ]]; then
    cp -a "$BOT_SOURCE_DIR/vpn_logo.png" "$DATA_ROOT/bot/vpn_logo.png"
  fi
  chown -R 1000:1000 "$DATA_ROOT/bot" 2>/dev/null || true
}

initialize_env_files() {
  if [[ ! -f "$BOT_ENV" ]]; then
    cp "$BOT_SOURCE_DIR/.env.example" "$BOT_ENV"
    chmod 600 "$BOT_ENV"
  fi
  if [[ ! -f "$STACK_ENV" ]]; then
    touch "$STACK_ENV"
    chmod 600 "$STACK_ENV"
  fi
  dotenv_merge_missing "$BOT_ENV" "$BOT_SOURCE_DIR/.env.example"
  sanitize_bot_env
}

sanitize_bot_env() {
  [[ -f "$BOT_ENV" ]] || return 0
  local key value removed=0
  local -a optional_integer_keys=(
    ADMIN_REPORTS_TOPIC_ID
    MULENPAY_SHOP_ID
    FREEKASSA_SHOP_ID
    FREEKASSA_PAYMENT_SYSTEM_ID
    KASSA_AI_SHOP_ID
    SEVERPAY_MID
    APPLE_IAP_APP_APPLE_ID
    LOG_ROTATION_TOPIC_ID
  )
  for key in "${optional_integer_keys[@]}"; do
    grep -qE "^${key}=" "$BOT_ENV" 2>/dev/null || continue
    value="$(dotenv_get "$BOT_ENV" "$key" 2>/dev/null || true)"
    if [[ ! "$value" =~ ^-?[0-9]+$ ]]; then
      dotenv_unset "$BOT_ENV" "$key"
      ((removed += 1))
    fi
  done
  if [[ "$removed" -gt 0 ]]; then
    success "Удалены несовместимые placeholder-значения опциональных числовых параметров Bot: $removed."
  fi
}

write_required_configuration() {
  local bot_token="$1" admin_ids="$2" bot_username="$3" remnawave_url="$4" remnawave_key="$5"
  local webhook_domain="$6" cabinet_domain="$7" acme_email="$8" app_name="$9" app_logo="${10}" timezone="${11}"
  local postgres_password webhook_secret api_token cabinet_secret

  postgres_password="$(dotenv_get "$STACK_ENV" POSTGRES_PASSWORD 2>/dev/null || true)"
  webhook_secret="$(dotenv_get "$BOT_ENV" WEBHOOK_SECRET_TOKEN 2>/dev/null || true)"
  api_token="$(dotenv_get "$BOT_ENV" WEB_API_DEFAULT_TOKEN 2>/dev/null || true)"
  cabinet_secret="$(dotenv_get "$BOT_ENV" CABINET_JWT_SECRET 2>/dev/null || true)"
  [[ -n "$postgres_password" ]] || postgres_password="$(random_hex 32)"
  [[ -n "$webhook_secret" ]] || webhook_secret="$(random_hex 32)"
  [[ -n "$api_token" ]] || api_token="$(random_hex 32)"
  [[ -n "$cabinet_secret" ]] || cabinet_secret="$(random_hex 32)"

  dotenv_set "$STACK_ENV" BOT_SOURCE_DIR "$BOT_SOURCE_DIR"
  dotenv_set "$STACK_ENV" CABINET_SOURCE_DIR "$CABINET_SOURCE_DIR"
  dotenv_set "$STACK_ENV" CONFIG_ROOT "$CONFIG_ROOT"
  dotenv_set "$STACK_ENV" DATA_ROOT "$DATA_ROOT"
  dotenv_set "$STACK_ENV" BOT_ENV "$BOT_ENV"
  dotenv_set "$STACK_ENV" POSTGRES_DB "remnawave_bot"
  dotenv_set "$STACK_ENV" POSTGRES_USER "remnawave_user"
  dotenv_set "$STACK_ENV" POSTGRES_PASSWORD "$postgres_password"
  dotenv_set "$STACK_ENV" VITE_API_URL "/api"
  dotenv_set "$STACK_ENV" VITE_TELEGRAM_BOT_USERNAME "$bot_username"
  dotenv_set "$STACK_ENV" VITE_APP_NAME "$app_name"
  dotenv_set "$STACK_ENV" VITE_APP_LOGO "$app_logo"
  dotenv_set "$STACK_ENV" WEBHOOK_DOMAIN "$webhook_domain"
  dotenv_set "$STACK_ENV" CABINET_DOMAIN "$cabinet_domain"
  dotenv_set "$STACK_ENV" ACME_EMAIL "$acme_email"
  dotenv_set "$STACK_ENV" TZ "$timezone"
  dotenv_set "$STACK_ENV" BOT_REF "main"
  dotenv_set "$STACK_ENV" CABINET_REF "main"
  dotenv_set "$STACK_ENV" BACKUP_RETENTION "7"

  dotenv_set "$BOT_ENV" BOT_TOKEN "$bot_token"
  dotenv_set "$BOT_ENV" BOT_USERNAME "$bot_username"
  dotenv_set "$BOT_ENV" ADMIN_IDS "$admin_ids"
  dotenv_set "$BOT_ENV" BOT_RUN_MODE "webhook"
  dotenv_set "$BOT_ENV" WEBHOOK_URL "https://${webhook_domain}"
  dotenv_set "$BOT_ENV" WEBHOOK_PATH "/webhook"
  dotenv_set "$BOT_ENV" WEBHOOK_SECRET_TOKEN "$webhook_secret"
  dotenv_set "$BOT_ENV" WEBHOOK_DROP_PENDING_UPDATES "true"
  dotenv_set "$BOT_ENV" WEB_API_ENABLED "true"
  dotenv_set "$BOT_ENV" WEB_API_HOST "0.0.0.0"
  dotenv_set "$BOT_ENV" WEB_API_PORT "8080"
  dotenv_set "$BOT_ENV" WEB_API_ALLOWED_ORIGINS "https://${cabinet_domain}"
  dotenv_set "$BOT_ENV" WEB_API_DEFAULT_TOKEN "$api_token"
  dotenv_set "$BOT_ENV" REMNAWAVE_API_URL "$remnawave_url"
  dotenv_set "$BOT_ENV" REMNAWAVE_API_KEY "$remnawave_key"
  dotenv_set "$BOT_ENV" POSTGRES_DB "remnawave_bot"
  dotenv_set "$BOT_ENV" POSTGRES_USER "remnawave_user"
  dotenv_set "$BOT_ENV" POSTGRES_PASSWORD "$postgres_password"
  dotenv_set "$BOT_ENV" CABINET_ENABLED "true"
  dotenv_set "$BOT_ENV" CABINET_EMAIL_AUTH_ENABLED "false"
  dotenv_set "$BOT_ENV" CABINET_URL "https://${cabinet_domain}"
  dotenv_set "$BOT_ENV" CABINET_ALLOWED_ORIGINS "https://${cabinet_domain}"
  dotenv_set "$BOT_ENV" CABINET_JWT_SECRET "$cabinet_secret"
  chmod 600 "$STACK_ENV" "$BOT_ENV"
}

render_caddyfile() {
  load_stack_env || die "Не удалось загрузить $STACK_ENV"
  local template
  : "${ACME_EMAIL:?}" "${WEBHOOK_DOMAIN:?}" "${CABINET_DOMAIN:?}"
  template="$(template_dir)/Caddyfile.tmpl"
  [[ -f "$template" ]] || die "Не найден шаблон $template"
  sed \
    -e "s|@@ACME_EMAIL@@|${ACME_EMAIL}|g" \
    -e "s|@@WEBHOOK_DOMAIN@@|${WEBHOOK_DOMAIN}|g" \
    -e "s|@@CABINET_DOMAIN@@|${CABINET_DOMAIN}|g" \
    "$template" >"${CADDY_FILE}.tmp"
  chmod 600 "${CADDY_FILE}.tmp"
  mv -f "${CADDY_FILE}.tmp" "$CADDY_FILE"
}

copy_compose_template() {
  local template
  template="$(template_dir)/compose.yaml"
  [[ -f "$template" ]] || die "Не найден шаблон $template"
  install -m 644 "$template" "$COMPOSE_FILE"
}

configuration_wizard() {
  local current token admin_ids username detected_username remnawave_url remnawave_key
  local webhook_domain cabinet_domain email app_name app_logo timezone

  printf '\n'
  ui_banner 'Мастер конфигурации'
  ui_section 'Основные параметры'
  sanitize_bot_env
  configure_secret_input_mode
  current="$(dotenv_get "$BOT_ENV" BOT_TOKEN 2>/dev/null || true)"
  prompt_value token "Telegram Bot Token" "$current" validate_bot_token 1
  detected_username="$(verify_telegram_token "$token" || true)"
  if [[ -n "$detected_username" ]]; then
    success "Telegram Bot Token действителен: @$detected_username"
    username="$detected_username"
  else
    warn "Не удалось проверить токен через Telegram API."
    current="$(dotenv_get "$STACK_ENV" VITE_TELEGRAM_BOT_USERNAME 2>/dev/null || true)"
    prompt_value username "Username бота без @" "$current" validate_username
  fi

  current="$(dotenv_get "$BOT_ENV" ADMIN_IDS 2>/dev/null || true)"
  prompt_value admin_ids "Telegram ID администраторов через запятую" "$current" validate_admin_ids
  current="$(dotenv_get "$BOT_ENV" REMNAWAVE_API_URL 2>/dev/null || true)"
  prompt_value remnawave_url "URL Remnawave Panel" "$current" validate_https_url
  current="$(dotenv_get "$BOT_ENV" REMNAWAVE_API_KEY 2>/dev/null || true)"
  prompt_value remnawave_key "API key Remnawave" "$current" validate_api_key 1
  current="$(dotenv_get "$STACK_ENV" WEBHOOK_DOMAIN 2>/dev/null || true)"
  prompt_value webhook_domain "Домен webhook, без https://" "$current" validate_domain
  current="$(dotenv_get "$STACK_ENV" CABINET_DOMAIN 2>/dev/null || true)"
  prompt_value cabinet_domain "Домен Cabinet, без https://" "$current" validate_domain
  [[ "$webhook_domain" != "$cabinet_domain" ]] || die "Webhook и Cabinet должны использовать разные домены."
  current="$(dotenv_get "$STACK_ENV" ACME_EMAIL 2>/dev/null || true)"
  prompt_value email "Email для Let's Encrypt" "$current" 'validate_email'
  current="$(dotenv_get "$STACK_ENV" VITE_APP_NAME 2>/dev/null || printf 'VPN Cabinet')"
  prompt_value app_name "Название сервиса" "$current" validate_app_name
  current="$(dotenv_get "$STACK_ENV" VITE_APP_LOGO 2>/dev/null || printf 'V')"
  prompt_value app_logo "Короткий логотип (1–2 символа)" "$current" validate_logo
  current="$(dotenv_get "$STACK_ENV" TZ 2>/dev/null || printf 'Europe/Moscow')"
  prompt_value timezone "Часовой пояс" "$current" validate_timezone

  write_required_configuration "$token" "$admin_ids" "$username" "$remnawave_url" "$remnawave_key" \
    "$webhook_domain" "$cabinet_domain" "$email" "$app_name" "$app_logo" "$timezone"
  render_caddyfile
  success "Конфигурация сохранена."
  info "Для применения к работающему стеку выполните: bedolaga apply"
}

validate_email() { [[ "$1" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,63}$ ]]; }
validate_logo() { [[ ${#1} -ge 1 && ${#1} -le 2 ]] && validate_app_name "$1"; }
validate_app_name() {
  [[ ${#1} -ge 1 && ${#1} -le 64 ]] || return 1
  case "$1" in
    *'$'* | *'`'* | *'"'* | *"'"* | *\\*) return 1 ;;
    *) return 0 ;;
  esac
}
validate_timezone() { [[ "$1" =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$ && -f "/usr/share/zoneinfo/$1" ]]; }

validate_stack_values() {
  load_stack_env || { error "Не удалось загрузить $STACK_ENV"; return 1; }
  validate_domain "${WEBHOOK_DOMAIN:-}" || { error "Некорректный WEBHOOK_DOMAIN."; return 1; }
  validate_domain "${CABINET_DOMAIN:-}" || { error "Некорректный CABINET_DOMAIN."; return 1; }
  [[ "$WEBHOOK_DOMAIN" != "$CABINET_DOMAIN" ]] || { error "Webhook и Cabinet должны использовать разные домены."; return 1; }
  validate_email "${ACME_EMAIL:-}" || { error "Некорректный ACME_EMAIL."; return 1; }
  validate_username "${VITE_TELEGRAM_BOT_USERNAME:-}" || { error "Некорректный VITE_TELEGRAM_BOT_USERNAME."; return 1; }
  [[ -z "${VITE_APP_NAME:-}" ]] || validate_app_name "$VITE_APP_NAME" || { error "Некорректный VITE_APP_NAME."; return 1; }
  [[ -z "${VITE_APP_LOGO:-}" ]] || validate_logo "$VITE_APP_LOGO" || { error "Некорректный VITE_APP_LOGO."; return 1; }
  [[ -z "${TZ:-}" ]] || validate_timezone "$TZ" || { error "Некорректный TZ."; return 1; }
}

validate_bot_values() {
  local token admin_ids remnawave_url remnawave_key
  token="$(dotenv_get "$BOT_ENV" BOT_TOKEN 2>/dev/null || true)"
  admin_ids="$(dotenv_get "$BOT_ENV" ADMIN_IDS 2>/dev/null || true)"
  remnawave_url="$(dotenv_get "$BOT_ENV" REMNAWAVE_API_URL 2>/dev/null || true)"
  remnawave_key="$(dotenv_get "$BOT_ENV" REMNAWAVE_API_KEY 2>/dev/null || true)"
  validate_bot_token "$token" || { error "Некорректный BOT_TOKEN."; return 1; }
  validate_admin_ids "$admin_ids" || { error "Некорректный ADMIN_IDS."; return 1; }
  validate_https_url "$remnawave_url" || { error "Некорректный REMNAWAVE_API_URL."; return 1; }
  validate_api_key "$remnawave_key" || { error "Некорректный REMNAWAVE_API_KEY."; return 1; }
}

validate_managed_paths() {
  local configured_bot configured_cabinet configured_config configured_data configured_bot_env configured_db configured_user
  configured_bot="$(dotenv_get "$STACK_ENV" BOT_SOURCE_DIR 2>/dev/null || true)"
  configured_cabinet="$(dotenv_get "$STACK_ENV" CABINET_SOURCE_DIR 2>/dev/null || true)"
  configured_config="$(dotenv_get "$STACK_ENV" CONFIG_ROOT 2>/dev/null || true)"
  configured_data="$(dotenv_get "$STACK_ENV" DATA_ROOT 2>/dev/null || true)"
  configured_bot_env="$(dotenv_get "$STACK_ENV" BOT_ENV 2>/dev/null || true)"
  configured_db="$(dotenv_get "$STACK_ENV" POSTGRES_DB 2>/dev/null || true)"
  configured_user="$(dotenv_get "$STACK_ENV" POSTGRES_USER 2>/dev/null || true)"
  [[ "$configured_bot" == "$BOT_SOURCE_DIR" ]] || { error "BOT_SOURCE_DIR должен быть $BOT_SOURCE_DIR"; return 1; }
  [[ "$configured_cabinet" == "$CABINET_SOURCE_DIR" ]] || { error "CABINET_SOURCE_DIR должен быть $CABINET_SOURCE_DIR"; return 1; }
  [[ "$configured_config" == "$CONFIG_ROOT" ]] || { error "CONFIG_ROOT должен быть $CONFIG_ROOT"; return 1; }
  [[ "$configured_data" == "$DATA_ROOT" ]] || { error "DATA_ROOT должен быть $DATA_ROOT"; return 1; }
  [[ "$configured_bot_env" == "$BOT_ENV" ]] || { error "BOT_ENV должен быть $BOT_ENV"; return 1; }
  [[ "$configured_db" == remnawave_bot ]] || { error "POSTGRES_DB должен быть remnawave_bot"; return 1; }
  [[ "$configured_user" == remnawave_user ]] || { error "POSTGRES_USER должен быть remnawave_user"; return 1; }
}

validate_configuration() {
  dotenv_require "$STACK_ENV" BOT_SOURCE_DIR CABINET_SOURCE_DIR CONFIG_ROOT DATA_ROOT BOT_ENV POSTGRES_PASSWORD \
    VITE_TELEGRAM_BOT_USERNAME WEBHOOK_DOMAIN CABINET_DOMAIN ACME_EMAIL || return 1
  dotenv_require "$BOT_ENV" BOT_TOKEN ADMIN_IDS WEBHOOK_URL WEBHOOK_SECRET_TOKEN WEB_API_DEFAULT_TOKEN \
    REMNAWAVE_API_URL REMNAWAVE_API_KEY CABINET_JWT_SECRET || return 1
  validate_stack_values || return 1
  validate_bot_values || return 1
  validate_managed_paths || return 1
  docker compose --project-name bedolaga --env-file "$STACK_ENV" -f "$COMPOSE_FILE" config --quiet
}
