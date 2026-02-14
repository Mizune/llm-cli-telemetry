#!/usr/bin/env bats
# Tests for scripts/shell-integration.sh
#
# Shell-integration functions use inline prefix env-var assignments before
# `command <tool>`, which bats' `command` shim doesn't propagate.
# We therefore run each function inside a plain `bash -c` subprocess.

setup() {
  load helpers/setup
  load helpers/mocks
  setup_test_home
  create_all_mocks

  # Defaults (exported so they propagate to bash -c subprocesses)
  export LLM_CLI_TELEMETRY_ENDPOINT="http://localhost:4317"
  export LLM_CLI_TELEMETRY_PROTOCOL="grpc"
  unset LLM_CLI_TELEMETRY_DISABLED 2>/dev/null || true
  unset LLM_CLI_TELEMETRY_HEADERS 2>/dev/null || true
  unset LLM_CLI_TELEMETRY_USER_ATTRS 2>/dev/null || true
  unset LLM_CLI_TELEMETRY_LOG_PROMPTS 2>/dev/null || true
  unset LLM_CLI_TELEMETRY_LOG_TOOL_DETAILS 2>/dev/null || true
}

teardown() {
  teardown_test_home
}

# Helper: run a shell-integration function in a clean bash subprocess.
# Exported LLM_CLI_TELEMETRY_* vars are inherited automatically.
_run_cli() {
  local func="$1"; shift
  bash -c '
    export PATH="'"${TEST_TMPDIR}/mock-bin"':${PATH}"
    source "'"${BATS_TEST_PROJECT_DIR}/scripts/shell-integration.sh"'"
    '"${func}"' "$@"
  ' _ "$@" 2>&1
}

# ===========================================================================
# claude()
# ===========================================================================

@test "claude: sets CLAUDE_CODE_ENABLE_TELEMETRY=1" {
  result=$(_run_cli claude)
  [[ "$result" == *"CLAUDE_CODE_ENABLE_TELEMETRY=1"* ]]
}

@test "claude: sets OTEL_METRICS_EXPORTER=otlp" {
  result=$(_run_cli claude)
  [[ "$result" == *"OTEL_METRICS_EXPORTER=otlp"* ]]
}

@test "claude: sets OTEL_LOGS_EXPORTER=otlp" {
  result=$(_run_cli claude)
  [[ "$result" == *"OTEL_LOGS_EXPORTER=otlp"* ]]
}

@test "claude: converts http protocol to http/protobuf" {
  export LLM_CLI_TELEMETRY_PROTOCOL="http"
  result=$(_run_cli claude)
  [[ "$result" == *"OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf"* ]]
}

@test "claude: keeps grpc protocol as-is" {
  export LLM_CLI_TELEMETRY_PROTOCOL="grpc"
  result=$(_run_cli claude)
  [[ "$result" == *"OTEL_EXPORTER_OTLP_PROTOCOL=grpc"* ]]
}

@test "claude: passes endpoint from LLM_CLI_TELEMETRY_ENDPOINT" {
  export LLM_CLI_TELEMETRY_ENDPOINT="https://custom.endpoint:4317"
  result=$(_run_cli claude)
  [[ "$result" == *"OTEL_EXPORTER_OTLP_ENDPOINT=https://custom.endpoint:4317"* ]]
}

@test "claude: sets OTEL_RESOURCE_ATTRIBUTES with cli_tool=claude-code" {
  result=$(_run_cli claude)
  [[ "$result" == *"OTEL_RESOURCE_ATTRIBUTES=cli_tool=claude-code"* ]]
}

@test "claude: appends user attributes to OTEL_RESOURCE_ATTRIBUTES" {
  export LLM_CLI_TELEMETRY_USER_ATTRS="user.email=a@b.com,user.team=eng"
  result=$(_run_cli claude)
  [[ "$result" == *"OTEL_RESOURCE_ATTRIBUTES=cli_tool=claude-code,user.email=a@b.com,user.team=eng"* ]]
}

@test "claude: passes OTEL_EXPORTER_OTLP_HEADERS" {
  export LLM_CLI_TELEMETRY_HEADERS="Authorization=Basic abc123"
  result=$(_run_cli claude)
  [[ "$result" == *"OTEL_EXPORTER_OTLP_HEADERS=Authorization=Basic abc123"* ]]
}

@test "claude: disabled mode bypasses telemetry" {
  export LLM_CLI_TELEMETRY_DISABLED=1
  result=$(_run_cli claude)
  [[ "$result" != *"OTEL_METRICS_EXPORTER=otlp"* ]]
  [[ "$result" != *"OTEL_LOGS_EXPORTER=otlp"* ]]
}

# ===========================================================================
# codex()
# ===========================================================================

@test "codex: sets OTEL_RESOURCE_ATTRIBUTES with cli_tool=codex-cli" {
  result=$(_run_cli codex)
  [[ "$result" == *"OTEL_RESOURCE_ATTRIBUTES=cli_tool=codex-cli"* ]]
}

@test "codex: does not set OTEL_METRICS_EXPORTER" {
  result=$(_run_cli codex)
  [[ "$result" != *"OTEL_METRICS_EXPORTER=otlp"* ]]
}

@test "codex: does not set OTEL_LOGS_EXPORTER" {
  result=$(_run_cli codex)
  [[ "$result" != *"OTEL_LOGS_EXPORTER=otlp"* ]]
}

@test "codex: appends user attributes to OTEL_RESOURCE_ATTRIBUTES" {
  export LLM_CLI_TELEMETRY_USER_ATTRS="user.email=x@y.com"
  result=$(_run_cli codex)
  [[ "$result" == *"OTEL_RESOURCE_ATTRIBUTES=cli_tool=codex-cli,user.email=x@y.com"* ]]
}

@test "codex: disabled mode bypasses telemetry" {
  export LLM_CLI_TELEMETRY_DISABLED=1
  result=$(_run_cli codex)
  [[ "$result" != *"cli_tool=codex-cli"* ]]
}

# ===========================================================================
# gemini()
# ===========================================================================

@test "gemini: sets GEMINI_TELEMETRY_ENABLED=true" {
  result=$(_run_cli gemini)
  [[ "$result" == *"GEMINI_TELEMETRY_ENABLED=true"* ]]
}

@test "gemini: sets GEMINI_TELEMETRY_OTLP_ENDPOINT" {
  export LLM_CLI_TELEMETRY_ENDPOINT="https://otel.test:4317"
  result=$(_run_cli gemini)
  [[ "$result" == *"GEMINI_TELEMETRY_OTLP_ENDPOINT=https://otel.test:4317"* ]]
}

@test "gemini: sets GEMINI_TELEMETRY_OTLP_PROTOCOL" {
  export LLM_CLI_TELEMETRY_PROTOCOL="http"
  result=$(_run_cli gemini)
  [[ "$result" == *"GEMINI_TELEMETRY_OTLP_PROTOCOL=http"* ]]
}

@test "gemini: sets OTEL_RESOURCE_ATTRIBUTES with cli_tool=gemini-cli" {
  result=$(_run_cli gemini)
  [[ "$result" == *"OTEL_RESOURCE_ATTRIBUTES=cli_tool=gemini-cli"* ]]
}

@test "gemini: passes OTEL_EXPORTER_OTLP_HEADERS" {
  export LLM_CLI_TELEMETRY_HEADERS="Authorization=Bearer tok"
  result=$(_run_cli gemini)
  [[ "$result" == *"OTEL_EXPORTER_OTLP_HEADERS=Authorization=Bearer tok"* ]]
}

@test "gemini: disabled mode bypasses telemetry" {
  export LLM_CLI_TELEMETRY_DISABLED=1
  result=$(_run_cli gemini)
  [[ "$result" != *"GEMINI_TELEMETRY_ENABLED"* ]]
  [[ "$result" != *"cli_tool=gemini-cli"* ]]
}
