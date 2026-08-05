#!/usr/bin/env bash

doctor_check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf '  %b✓%b %s\n' "$C_GREEN" "$C_RESET" "$label"
    return 0
  fi
  printf '  %b✗%b %s\n' "$C_RED" "$C_RESET" "$label"
  return 1
}

check_https_url() {
  curl -fsS --max-time 15 -o /dev/null "$1"
}

check_remnawave_reachable() {
  local url
  url="$(dotenv_get "$BOT_ENV" REMNAWAVE_API_URL)"
  local code
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$url" || true)"
  [[ "$code" != 000 && -n "$code" ]]
}

check_telegram_webhook() {
  local token expected actual
  [[ -n "${WEBHOOK_DOMAIN:-}" && -f "$BOT_ENV" ]] || return 1
  token="$(dotenv_get "$BOT_ENV" BOT_TOKEN)"
  expected="https://${WEBHOOK_DOMAIN}/webhook"
  actual="$(curl -fsS --max-time 10 "https://api.telegram.org/bot${token}/getWebhookInfo" 2>/dev/null | jq -r '.result.url // empty')"
  [[ "$actual" == "$expected" ]]
}

check_cors_configuration() {
  local expected cabinet_origins api_origins
  [[ -n "${CABINET_DOMAIN:-}" && -f "$BOT_ENV" ]] || return 1
  expected="https://${CABINET_DOMAIN}"
  cabinet_origins="$(dotenv_get "$BOT_ENV" CABINET_ALLOWED_ORIGINS)"
  api_origins="$(dotenv_get "$BOT_ENV" WEB_API_ALLOWED_ORIGINS)"
  [[ "$cabinet_origins" == "$expected" && "$api_origins" == "$expected" ]]
}

doctor() {
  require_root
  local failures=0 webhook_domain cabinet_domain
  printf '%bДиагностика Bedolaga%b\n\n' "$C_BOLD" "$C_RESET"
  doctor_check "Docker daemon" docker info || ((failures += 1))
  doctor_check "Docker Compose v2" docker compose version || ((failures += 1))
  doctor_check "Файл конфигурации Stack" test -s "$STACK_ENV" || ((failures += 1))
  doctor_check "Файл конфигурации Bot" test -s "$BOT_ENV" || ((failures += 1))
  doctor_check "Caddyfile" test -s "$CADDY_FILE" || ((failures += 1))
  doctor_check "Docker Compose config" validate_configuration || ((failures += 1))

  if load_stack_env; then
    webhook_domain="${WEBHOOK_DOMAIN:-}"
    cabinet_domain="${CABINET_DOMAIN:-}"
    if [[ -n "$webhook_domain" ]]; then
      doctor_check "DNS webhook: $webhook_domain" dns_ipv4 "$webhook_domain" || ((failures += 1))
    fi
    if [[ -n "$cabinet_domain" ]]; then
      doctor_check "DNS Cabinet: $cabinet_domain" dns_ipv4 "$cabinet_domain" || ((failures += 1))
    fi
  fi

  local service
  for service in postgres redis bot cabinet caddy; do
    doctor_check "Контейнер $service: $(service_state "$service" 2>/dev/null || true)" service_state "$service" || ((failures += 1))
  done

  if [[ -n "${webhook_domain:-}" ]]; then
    doctor_check "HTTPS webhook" check_https_url "https://${webhook_domain}/health" || ((failures += 1))
  fi
  if [[ -n "${cabinet_domain:-}" ]]; then
    doctor_check "HTTPS Cabinet" check_https_url "https://${cabinet_domain}/" || ((failures += 1))
    doctor_check "Маршрут Cabinet API" check_https_url "https://${cabinet_domain}/api/health" || ((failures += 1))
  fi
  doctor_check "Telegram webhook зарегистрирован" check_telegram_webhook || ((failures += 1))
  doctor_check "CORS соответствует домену Cabinet" check_cors_configuration || ((failures += 1))
  doctor_check "Доступность Remnawave URL" check_remnawave_reachable || ((failures += 1))

  printf '\n'
  if [[ "$failures" -eq 0 ]]; then
    success "Проблем не обнаружено."
    return 0
  fi
  error "Обнаружено проблем: $failures"
  printf 'Подробные логи: bedolaga logs <bot|cabinet|caddy>\n'
  return 1
}
