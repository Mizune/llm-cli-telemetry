#!/usr/bin/env bash
# Shell integration for llm-cli-telemetry
# Source this file from your shell RC to transparently collect telemetry.
# Set LLM_CLI_TELEMETRY_DISABLED=1 to bypass telemetry for any command.

claude() {
  if [[ -n "${LLM_CLI_TELEMETRY_DISABLED:-}" ]]; then
    command claude "$@"
    return
  fi

  local protocol="${LLM_CLI_TELEMETRY_PROTOCOL:-grpc}"
  [[ "${protocol}" == "http" ]] && protocol="http/protobuf"

  CLAUDE_CODE_ENABLE_TELEMETRY=1 \
  OTEL_METRICS_EXPORTER=otlp \
  OTEL_LOGS_EXPORTER=otlp \
  OTEL_EXPORTER_OTLP_PROTOCOL="${protocol}" \
  OTEL_EXPORTER_OTLP_ENDPOINT="${LLM_CLI_TELEMETRY_ENDPOINT:-http://localhost:4317}" \
  OTEL_EXPORTER_OTLP_HEADERS="${LLM_CLI_TELEMETRY_HEADERS:-}" \
  OTEL_RESOURCE_ATTRIBUTES="cli_tool=claude-code${LLM_CLI_TELEMETRY_USER_ATTRS:+,$LLM_CLI_TELEMETRY_USER_ATTRS}" \
  OTEL_LOG_USER_PROMPTS="${LLM_CLI_TELEMETRY_LOG_PROMPTS:-0}" \
  OTEL_LOG_TOOL_DETAILS="${LLM_CLI_TELEMETRY_LOG_TOOL_DETAILS:-0}" \
  command claude "$@"
}

codex() {
  if [[ -n "${LLM_CLI_TELEMETRY_DISABLED:-}" ]]; then
    command codex "$@"
    return
  fi

  # Codex reads exporter settings from ~/.codex/config.toml [otel] section.
  # Only OTEL_RESOURCE_ATTRIBUTES is read from env (via SDK EnvResourceDetector).
  OTEL_RESOURCE_ATTRIBUTES="cli_tool=codex-cli${LLM_CLI_TELEMETRY_USER_ATTRS:+,$LLM_CLI_TELEMETRY_USER_ATTRS}" \
  command codex "$@"
}

gemini() {
  if [[ -n "${LLM_CLI_TELEMETRY_DISABLED:-}" ]]; then
    command gemini "$@"
    return
  fi

  GEMINI_TELEMETRY_ENABLED=true \
  GEMINI_TELEMETRY_TARGET=local \
  GEMINI_TELEMETRY_OTLP_ENDPOINT="${LLM_CLI_TELEMETRY_ENDPOINT:-http://localhost:4317}" \
  GEMINI_TELEMETRY_OTLP_PROTOCOL="${LLM_CLI_TELEMETRY_PROTOCOL:-grpc}" \
  OTEL_EXPORTER_OTLP_HEADERS="${LLM_CLI_TELEMETRY_HEADERS:-}" \
  OTEL_RESOURCE_ATTRIBUTES="cli_tool=gemini-cli${LLM_CLI_TELEMETRY_USER_ATTRS:+,$LLM_CLI_TELEMETRY_USER_ATTRS}" \
  command gemini "$@"
}
