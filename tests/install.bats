#!/usr/bin/env bats
# Tests for scripts/install.sh

setup() {
  load helpers/setup
  load helpers/fixtures
  load helpers/mocks
  setup_test_home
  create_all_mocks      # Puts claude/codex/gemini on PATH

  load_install_functions

  # Reset parsed-argument globals
  ARG_MODE="" ARG_ENDPOINT="" ARG_PROTOCOL=""
  ARG_INSTANCE_ID="" ARG_API_KEY="" ARG_AUTH_HEADER=""
  ARG_LOG_PROMPTS="" ARG_LOG_TOOL_DETAILS="" ARG_USER_EMAIL=""

  # Reset runtime-state globals
  MODE="" ENDPOINT="" PROTOCOL="" HEADERS=""
  LOG_PROMPTS="false" LOG_TOOL_DETAILS="false" USER_EMAIL=""
}

teardown() {
  teardown_test_home
}

# ===========================================================================
# validate_email
# ===========================================================================

@test "validate_email: accepts valid email" {
  validate_email "user@example.com"
}

@test "validate_email: accepts dots and plus" {
  validate_email "first.last+tag@sub.example.com"
}

@test "validate_email: rejects missing @" {
  run validate_email "noatsign"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid email"* ]]
}

@test "validate_email: rejects missing domain" {
  run validate_email "user@"
  [ "$status" -eq 1 ]
}

@test "validate_email: rejects missing TLD" {
  run validate_email "user@domain"
  [ "$status" -eq 1 ]
}

@test "validate_email: rejects empty string" {
  run validate_email ""
  [ "$status" -eq 1 ]
}

# ===========================================================================
# parse_args
# ===========================================================================

@test "parse_args: --mode sets ARG_MODE" {
  parse_args --mode remote
  [ "$ARG_MODE" = "remote" ]
}

@test "parse_args: --endpoint sets ARG_ENDPOINT" {
  parse_args --endpoint "https://otel.test:4317"
  [ "$ARG_ENDPOINT" = "https://otel.test:4317" ]
}

@test "parse_args: --protocol sets ARG_PROTOCOL" {
  parse_args --protocol http
  [ "$ARG_PROTOCOL" = "http" ]
}

@test "parse_args: --instance-id sets ARG_INSTANCE_ID" {
  parse_args --instance-id "123456"
  [ "$ARG_INSTANCE_ID" = "123456" ]
}

@test "parse_args: --api-key sets ARG_API_KEY" {
  parse_args --api-key "glc_test"
  [ "$ARG_API_KEY" = "glc_test" ]
}

@test "parse_args: --auth-header sets ARG_AUTH_HEADER" {
  parse_args --auth-header "Authorization: Bearer tok"
  [ "$ARG_AUTH_HEADER" = "Authorization: Bearer tok" ]
}

@test "parse_args: --log-prompts sets ARG_LOG_PROMPTS" {
  parse_args --log-prompts
  [ "$ARG_LOG_PROMPTS" = "true" ]
}

@test "parse_args: --log-tool-details sets ARG_LOG_TOOL_DETAILS" {
  parse_args --log-tool-details
  [ "$ARG_LOG_TOOL_DETAILS" = "true" ]
}

@test "parse_args: --user-email sets ARG_USER_EMAIL" {
  parse_args --user-email "a@b.com"
  [ "$ARG_USER_EMAIL" = "a@b.com" ]
}

@test "parse_args: unknown flag causes error" {
  run parse_args --unknown
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option"* ]]
}

@test "parse_args: --help calls show_usage and exits 0" {
  run parse_args --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

# ===========================================================================
# configure_codex
# ===========================================================================

@test "configure_codex: creates [otel] section with grpc" {
  ENDPOINT="http://localhost:4317"
  PROTOCOL="grpc"
  MODE="local"
  LOG_PROMPTS="false"
  mkdir -p "${HOME}/.codex"

  configure_codex

  local config="${HOME}/.codex/config.toml"
  [ -f "$config" ]
  grep -q '\[otel\]' "$config"
  grep -q 'otlp-grpc' "$config"
  grep -q 'http://localhost:4317' "$config"
}

@test "configure_codex: creates [otel] section with http (signal-specific paths)" {
  ENDPOINT="https://otel.test:4318"
  PROTOCOL="http"
  MODE="remote"
  LOG_PROMPTS="true"
  mkdir -p "${HOME}/.codex"

  configure_codex

  local config="${HOME}/.codex/config.toml"
  grep -q 'otlp-http' "$config"
  grep -q 'https://otel.test:4318/v1/logs' "$config"
  grep -q 'https://otel.test:4318/v1/traces' "$config"
  grep -q 'log_user_prompt = true' "$config"
}

@test "configure_codex: backs up existing config" {
  ENDPOINT="http://localhost:4317"
  PROTOCOL="grpc"
  MODE="local"
  LOG_PROMPTS="false"
  mkdir -p "${HOME}/.codex"
  cp "${FIXTURES_DIR}/codex-config-existing.toml" "${HOME}/.codex/config.toml"

  configure_codex

  [ -f "${HOME}/.codex/config.toml.bak" ]
  grep -q 'max_entries' "${HOME}/.codex/config.toml.bak"
}

@test "configure_codex: idempotent re-run replaces [otel] section" {
  ENDPOINT="http://localhost:4317"
  PROTOCOL="grpc"
  MODE="local"
  LOG_PROMPTS="false"
  mkdir -p "${HOME}/.codex"

  # First run
  configure_codex

  # Second run with different endpoint
  ENDPOINT="https://new.endpoint:4317"
  configure_codex

  local config="${HOME}/.codex/config.toml"
  local otel_count
  otel_count=$(grep -c '^\[otel\]' "$config")
  [ "$otel_count" -eq 1 ]
  grep -q 'https://new.endpoint:4317' "$config"
}

# ===========================================================================
# configure_gemini
# ===========================================================================

@test "configure_gemini: creates new settings.json" {
  ENDPOINT="http://localhost:4317"
  PROTOCOL="grpc"
  LOG_PROMPTS="false"
  mkdir -p "${HOME}/.gemini"

  configure_gemini

  local config="${HOME}/.gemini/settings.json"
  [ -f "$config" ]
  grep -q '"telemetry"' "$config"
  grep -q '"enabled": true' "$config"
  grep -q 'http://localhost:4317' "$config"
}

@test "configure_gemini: backs up existing config" {
  ENDPOINT="http://localhost:4317"
  PROTOCOL="grpc"
  LOG_PROMPTS="false"
  mkdir -p "${HOME}/.gemini"
  cp "${FIXTURES_DIR}/gemini-settings-existing.json" "${HOME}/.gemini/settings.json"

  configure_gemini

  [ -f "${HOME}/.gemini/settings.json.bak" ]
  grep -q '"theme"' "${HOME}/.gemini/settings.json.bak"
}

@test "configure_gemini: updates existing config with jq" {
  if ! command -v jq &>/dev/null; then
    skip "jq not installed"
  fi

  ENDPOINT="https://otel.test:4318"
  PROTOCOL="http"
  LOG_PROMPTS="true"
  mkdir -p "${HOME}/.gemini"
  cp "${FIXTURES_DIR}/gemini-settings-existing.json" "${HOME}/.gemini/settings.json"

  configure_gemini

  local config="${HOME}/.gemini/settings.json"
  # Original keys preserved
  jq -e '.theme == "dark"' "$config" >/dev/null
  # Telemetry added
  jq -e '.telemetry.enabled == true' "$config" >/dev/null
  jq -e '.telemetry.otlpEndpoint == "https://otel.test:4318"' "$config" >/dev/null
  jq -e '.telemetry.otlpProtocol == "http"' "$config" >/dev/null
  jq -e '.telemetry.logPrompts == true' "$config" >/dev/null
}

# ===========================================================================
# install_shell_rc
# ===========================================================================

@test "install_shell_rc: inserts marker block" {
  MODE="local" ENDPOINT="http://localhost:4317" PROTOCOL="grpc"
  HEADERS="" LOG_PROMPTS="false" LOG_TOOL_DETAILS="false" USER_EMAIL=""
  export SHELL="/bin/zsh"

  install_shell_rc

  grep -q '>>> llm-cli-telemetry >>>' "${HOME}/.zshrc"
  grep -q '<<< llm-cli-telemetry <<<' "${HOME}/.zshrc"
  grep -q 'shell-integration.sh' "${HOME}/.zshrc"
}

@test "install_shell_rc: exports endpoint and protocol" {
  MODE="remote" ENDPOINT="https://otel.test:4318" PROTOCOL="http"
  HEADERS="" LOG_PROMPTS="false" LOG_TOOL_DETAILS="false" USER_EMAIL=""
  export SHELL="/bin/zsh"

  install_shell_rc

  grep -q 'LLM_CLI_TELEMETRY_ENDPOINT="https://otel.test:4318"' "${HOME}/.zshrc"
  grep -q 'LLM_CLI_TELEMETRY_PROTOCOL="http"' "${HOME}/.zshrc"
}

@test "install_shell_rc: exports headers when provided" {
  MODE="remote" ENDPOINT="https://otel.test:4318" PROTOCOL="http"
  HEADERS="Authorization=Bearer tok" LOG_PROMPTS="false" LOG_TOOL_DETAILS="false" USER_EMAIL=""
  export SHELL="/bin/zsh"

  install_shell_rc

  grep -q 'LLM_CLI_TELEMETRY_HEADERS="Authorization=Bearer tok"' "${HOME}/.zshrc"
}

@test "install_shell_rc: exports user attributes" {
  MODE="local" ENDPOINT="http://localhost:4317" PROTOCOL="grpc"
  HEADERS="" LOG_PROMPTS="false" LOG_TOOL_DETAILS="false"
  USER_EMAIL="dev@test.com"
  export SHELL="/bin/zsh"

  install_shell_rc

  grep -q 'LLM_CLI_TELEMETRY_USER_ATTRS=.*user.email=dev@test.com' "${HOME}/.zshrc"
}
