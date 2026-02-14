#!/usr/bin/env bash
# Shared utilities for llm-cli-telemetry scripts.
# Source this file at the top of any script:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "${SCRIPT_DIR}/lib.sh"

# --- Common variables ---
# Derive PROJECT_DIR from this file's own location (always scripts/../).
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP_MODE_FILE="${PROJECT_DIR}/.setup-mode"
# shellcheck disable=SC2034  # Used by scripts that source this file
MARKER_BEGIN="# >>> llm-cli-telemetry >>>"
# shellcheck disable=SC2034
MARKER_END="# <<< llm-cli-telemetry <<<"

# --- Log functions ---
info()  { echo "[info] $*"; }
warn()  { echo "[warn] $*" >&2; }
error() { echo "[error] $*" >&2; exit 1; }

# --- .setup-mode readers/writer ---
# File format: mode|protocol|endpoint[|headers]
# Examples:
#   local|grpc|http://localhost:4317
#   remote|http|https://otlp-gateway-prod-us-central-0.grafana.net/otlp|Authorization=Basic dXNlcjprZXk=

read_setup_mode() {
  if [[ ! -f "${SETUP_MODE_FILE}" ]]; then
    echo ""
    return
  fi
  cut -d'|' -f1 "${SETUP_MODE_FILE}"
}

read_setup_protocol() {
  if [[ ! -f "${SETUP_MODE_FILE}" ]]; then
    echo ""
    return
  fi
  cut -d'|' -f2 "${SETUP_MODE_FILE}"
}

read_setup_endpoint() {
  if [[ ! -f "${SETUP_MODE_FILE}" ]]; then
    echo ""
    return
  fi
  cut -d'|' -f3 "${SETUP_MODE_FILE}"
}

read_setup_headers() {
  if [[ ! -f "${SETUP_MODE_FILE}" ]]; then
    echo ""
    return
  fi
  cut -d'|' -f4- "${SETUP_MODE_FILE}"
}

write_setup_mode() {
  local mode="$1"
  local protocol="$2"
  local endpoint="$3"
  local headers="${4:-}"
  echo "${mode}|${protocol}|${endpoint}|${headers}" > "${SETUP_MODE_FILE}"
}

# --- Portable utilities ---

# Remove trailing blank lines from a file.
# macOS sed requires '' after -i, GNU sed does not.
strip_trailing_blank_lines() {
  local file="$1"
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' -e :a -e '/^\n*$/{$d;N;ba' -e '}' "${file}"
  else
    sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "${file}"
  fi
}
