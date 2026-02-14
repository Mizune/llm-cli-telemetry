#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

# --- Parsed arguments (set by parse_args) ---
ARG_MODE=""
ARG_ENDPOINT=""
ARG_PROTOCOL=""
ARG_INSTANCE_ID=""
ARG_API_KEY=""
ARG_AUTH_HEADER=""
ARG_LOG_PROMPTS=""
ARG_LOG_TOOL_DETAILS=""
ARG_USER_EMAIL=""

# --- Runtime state ---
MODE=""          # "local" or "remote"
ENDPOINT=""      # OTLP endpoint URL
PROTOCOL=""      # "grpc" or "http"
HEADERS=""       # OTLP headers (e.g. "Authorization=Basic xxx")
LOG_PROMPTS="false"
LOG_TOOL_DETAILS="false"
USER_EMAIL=""

# ==============================================================================
# Argument Parsing
# ==============================================================================

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode)
        ARG_MODE="$2"; shift 2 ;;
      --endpoint)
        ARG_ENDPOINT="$2"; shift 2 ;;
      --protocol)
        ARG_PROTOCOL="$2"; shift 2 ;;
      --instance-id)
        ARG_INSTANCE_ID="$2"; shift 2 ;;
      --api-key)
        ARG_API_KEY="$2"; shift 2 ;;
      --auth-header)
        ARG_AUTH_HEADER="$2"; shift 2 ;;
      --log-prompts)
        ARG_LOG_PROMPTS="true"; shift ;;
      --log-tool-details)
        ARG_LOG_TOOL_DETAILS="true"; shift ;;
      --user-email)
        ARG_USER_EMAIL="$2"; shift 2 ;;
      --help|-h)
        show_usage; exit 0 ;;
      *)
        error "Unknown option: $1 (use --help for usage)" ;;
    esac
  done
}

show_usage() {
  cat << 'EOF'
Usage: ./setup.sh [OPTIONS]

Interactive setup for llm-cli-telemetry.
Without options, runs in interactive mode with menus.

Options:
  --mode <local|remote>      Setup mode (skip interactive selection)
  --endpoint <url>           OTLP endpoint (required for remote mode)
  --protocol <grpc|http>     OTLP protocol (default: grpc for local, http for remote)
  --instance-id <id>         Grafana Cloud instance ID
  --api-key <key>            Grafana Cloud API key
  --auth-header <header>     Auth header (e.g. "Authorization: Bearer token")
  --log-prompts              Enable prompt content logging
  --log-tool-details         Enable tool execution detail logging
  --user-email <email>       User email (added as user.email resource attribute)
  --help, -h                 Show this help

Examples:
  ./setup.sh                                          # Interactive mode
  ./setup.sh --mode local                             # Local stack (non-interactive)
  ./setup.sh --mode remote --endpoint https://...     # Remote OTLP (non-interactive)
  ./setup.sh --mode remote --endpoint https://otlp-gateway-prod-us-central-0.grafana.net/otlp \
    --instance-id 123456 --api-key glc_xxx            # Grafana Cloud (non-interactive)
  ./setup.sh --mode remote --endpoint https://... \
    --user-email you@example.com                      # With user identification
EOF
}

# ==============================================================================
# Banner & UI Helpers
# ==============================================================================

show_banner() {
  echo ""
  echo "llm-cli-telemetry Setup"
  echo "========================"
  echo ""
}

prompt_choice() {
  local prompt="$1"
  local default="$2"
  local result
  read -rp "${prompt} [${default}]: " result
  echo "${result:-${default}}"
}

prompt_yn() {
  local prompt="$1"
  local default="${2:-N}"
  local result
  read -rp "${prompt} [y/N]: " result
  result="${result:-${default}}"
  [[ "${result}" =~ ^[Yy] ]]
}

validate_email() {
  local email="$1"
  if [[ ! "${email}" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    error "Invalid email format: ${email}"
  fi
}

# ==============================================================================
# Existing Setup Detection
# ==============================================================================

detect_existing_setup() {
  if [[ ! -f "${SETUP_MODE_FILE}" ]]; then
    return
  fi

  local existing_mode
  existing_mode=$(read_setup_mode)
  local existing_endpoint
  existing_endpoint=$(read_setup_endpoint)

  # In headless mode, just overwrite
  if [[ -n "${ARG_MODE}" ]]; then
    info "Overwriting existing setup (${existing_mode})..."
    return
  fi

  echo "Existing setup detected: ${existing_mode} (${existing_endpoint})"
  echo ""
  echo "  1) Reconfigure from scratch"
  echo "  2) Keep current mode, re-apply configs"
  echo "  3) Cancel"
  echo ""

  local choice
  read -rp "> [1-3]: " choice

  case "${choice}" in
    1)
      info "Starting fresh configuration..."
      ;;
    2)
      MODE="${existing_mode}"
      PROTOCOL=$(read_setup_protocol)
      ENDPOINT="${existing_endpoint}"
      HEADERS=$(read_setup_headers)
      info "Keeping ${MODE} mode, re-applying configs..."
      ;;
    3)
      info "Cancelled."
      exit 0
      ;;
    *)
      error "Invalid choice: ${choice}"
      ;;
  esac
}

# ==============================================================================
# Mode Selection
# ==============================================================================

select_mode() {
  # Already set by detect_existing_setup (re-apply) or headless mode
  if [[ -n "${MODE}" ]]; then
    return
  fi

  # Headless mode
  if [[ -n "${ARG_MODE}" ]]; then
    case "${ARG_MODE}" in
      local)
        MODE="local"
        PROTOCOL="${ARG_PROTOCOL:-grpc}"
        ENDPOINT="${ARG_ENDPOINT:-http://localhost:4317}"
        ;;
      remote)
        MODE="remote"
        if [[ -z "${ARG_ENDPOINT}" ]]; then
          error "--endpoint is required for remote mode"
        fi
        ENDPOINT="${ARG_ENDPOINT}"
        PROTOCOL="${ARG_PROTOCOL:-http}"

        # Grafana Cloud auto-config
        if [[ -n "${ARG_INSTANCE_ID}" ]] && [[ -n "${ARG_API_KEY}" ]]; then
          local basic_auth
          basic_auth=$(printf '%s:%s' "${ARG_INSTANCE_ID}" "${ARG_API_KEY}" | base64)
          HEADERS="Authorization=Basic ${basic_auth}"
        elif [[ -n "${ARG_AUTH_HEADER}" ]]; then
          # Convert "Authorization: Bearer token" to "Authorization=Bearer token"
          HEADERS="${ARG_AUTH_HEADER/: /=}"
        fi
        ;;
      *)
        error "Invalid mode: ${ARG_MODE}. Use 'local' or 'remote'."
        ;;
    esac
    return
  fi

  # Interactive mode
  echo "Select setup mode:"
  echo ""
  echo "  1) Local Stack    - Run Prometheus/Loki/Tempo/Grafana via Docker"
  echo "                      Best for: local development, full visibility"
  echo "                      Requires: Docker, Docker Compose, yq"
  echo ""
  echo "  2) Remote Export  - Send telemetry to a remote OTLP endpoint"
  echo "                      Best for: teams, existing infrastructure, cloud"
  echo "                      Requires: nothing (just shell functions)"
  echo ""

  local choice
  read -rp "> [1-2]: " choice

  case "${choice}" in
    1)
      MODE="local"
      PROTOCOL="grpc"
      ENDPOINT="http://localhost:4317"
      ;;
    2)
      MODE="remote"
      select_remote_endpoint
      ;;
    *)
      error "Invalid choice: ${choice}"
      ;;
  esac
}

select_remote_endpoint() {
  echo ""
  echo "Select remote endpoint type:"
  echo ""
  echo "  1) Grafana Cloud"
  echo "  2) Other OTLP endpoint"
  echo ""

  local choice
  read -rp "> [1-2]: " choice

  case "${choice}" in
    1) configure_grafana_cloud ;;
    2) configure_other_otlp ;;
    *) error "Invalid choice: ${choice}" ;;
  esac
}

configure_grafana_cloud() {
  echo ""
  echo "Grafana Cloud Configuration"
  echo "----------------------------"
  echo "Find these values at: grafana.com > My Account > Grafana Cloud > OpenTelemetry"
  echo ""

  local endpoint
  read -rp "OTLP endpoint URL: " endpoint
  if [[ -z "${endpoint}" ]]; then
    error "Endpoint is required"
  fi

  local instance_id
  read -rp "Instance ID: " instance_id
  if [[ -z "${instance_id}" ]]; then
    error "Instance ID is required"
  fi

  local api_key
  read -rsp "API key (input hidden): " api_key
  echo ""
  if [[ -z "${api_key}" ]]; then
    error "API key is required"
  fi

  ENDPOINT="${endpoint}"
  PROTOCOL="http"

  local basic_auth
  basic_auth=$(printf '%s:%s' "${instance_id}" "${api_key}" | base64)
  HEADERS="Authorization=Basic ${basic_auth}"
}

configure_other_otlp() {
  echo ""
  echo "OTLP Endpoint Configuration"
  echo "----------------------------"
  echo ""

  local endpoint
  read -rp "OTLP endpoint URL: " endpoint
  if [[ -z "${endpoint}" ]]; then
    error "Endpoint is required"
  fi

  echo ""
  echo "Protocol:"
  echo "  1) gRPC (default for most OTLP endpoints)"
  echo "  2) HTTP (http/protobuf)"
  echo ""

  local proto_choice
  read -rp "> [1-2] (default: 1): " proto_choice

  case "${proto_choice}" in
    2)    PROTOCOL="http" ;;
    ""|1) PROTOCOL="grpc" ;;
    *)    error "Invalid choice: ${proto_choice}" ;;
  esac

  echo ""
  local auth_header
  read -rp "Authorization header (optional, e.g. 'Authorization: Bearer token'): " auth_header

  ENDPOINT="${endpoint}"
  if [[ -n "${auth_header}" ]]; then
    HEADERS="${auth_header/: /=}"
  fi
}

# ==============================================================================
# Prerequisites Check
# ==============================================================================

check_prerequisites() {
  info "Checking prerequisites..."

  if [[ "${MODE}" == "local" ]]; then
    local missing=0

    if ! command -v docker &>/dev/null; then
      warn "Docker is not installed. Install: https://docs.docker.com/get-docker/"
      missing=$((missing + 1))
    fi

    if ! docker compose version &>/dev/null 2>&1; then
      warn "Docker Compose v2 is not available."
      missing=$((missing + 1))
    fi

    if ! command -v yq &>/dev/null; then
      warn "yq is not installed. Install: brew install yq"
      missing=$((missing + 1))
    fi

    if [[ ${missing} -gt 0 ]]; then
      error "Missing ${missing} prerequisite(s) for local mode. Install them and re-run."
    fi

    info "  Docker, Docker Compose, yq: OK"

  elif [[ "${MODE}" == "remote" ]]; then
    if ! command -v jq &>/dev/null; then
      warn "jq is not installed (optional, used for Gemini CLI config). Install: brew install jq"
    fi
  fi
}

# ==============================================================================
# Preferences
# ==============================================================================

collect_preferences() {
  # Headless flags
  if [[ -n "${ARG_LOG_PROMPTS}" ]]; then
    LOG_PROMPTS="${ARG_LOG_PROMPTS}"
  fi
  if [[ -n "${ARG_LOG_TOOL_DETAILS}" ]]; then
    LOG_TOOL_DETAILS="${ARG_LOG_TOOL_DETAILS}"
  fi
  if [[ -n "${ARG_USER_EMAIL}" ]]; then
    validate_email "${ARG_USER_EMAIL}"
    USER_EMAIL="${ARG_USER_EMAIL}"
  fi

  # Skip interactive if headless
  if [[ -n "${ARG_MODE}" ]]; then
    return
  fi

  echo ""
  echo "Privacy Settings"
  echo "-----------------"
  if prompt_yn "Include prompt content in logs?"; then
    LOG_PROMPTS="true"
  fi
  if prompt_yn "Include tool execution details in logs?"; then
    LOG_TOOL_DETAILS="true"
  fi

  info ""
  info "User Identification (added as resource attribute to all telemetry data)"
  read -rp "  Email address (optional, press Enter to skip): " USER_EMAIL
  if [[ -n "${USER_EMAIL}" ]]; then
    validate_email "${USER_EMAIL}"
  fi
}

# ==============================================================================
# CLI Tool Detection
# ==============================================================================

detect_tools() {
  info "Detecting CLI tools..."
  local found=0
  for tool in claude codex gemini; do
    if command -v "$tool" &>/dev/null; then
      info "  Found: $tool ($(command -v "$tool"))"
      found=$((found + 1))
    else
      info "  Not found: $tool"
    fi
  done
  if [[ $found -eq 0 ]]; then
    warn "No CLI tools found. Install at least one of: claude, codex, gemini"
  fi
}

# ==============================================================================
# Config Generation
# ==============================================================================

init_config() {
  if [[ "${MODE}" == "local" ]]; then
    # Full template for local mode
    if [[ ! -f "${PROJECT_DIR}/telemetry.yaml" ]]; then
      cp "${PROJECT_DIR}/telemetry.example.yaml" "${PROJECT_DIR}/telemetry.yaml"
      info "Created telemetry.yaml from template"
    else
      info "telemetry.yaml already exists"
    fi

    # Ensure local exporter is enabled and apply log preferences
    if command -v yq &>/dev/null && [[ -f "${PROJECT_DIR}/telemetry.yaml" ]]; then
      yq -i ".exporters.local.enabled = true" "${PROJECT_DIR}/telemetry.yaml"
      yq -i ".resource_attributes.\"deployment.environment\" = \"local\"" "${PROJECT_DIR}/telemetry.yaml"
      yq -i ".collection.log_prompts = ${LOG_PROMPTS}" "${PROJECT_DIR}/telemetry.yaml"
      yq -i ".collection.log_tool_details = ${LOG_TOOL_DETAILS}" "${PROJECT_DIR}/telemetry.yaml"
      if [[ -n "${USER_EMAIL}" ]]; then
        USER_EMAIL="${USER_EMAIL}" yq -i '.user.email = env(USER_EMAIL)' "${PROJECT_DIR}/telemetry.yaml"
      fi
    fi

  elif [[ "${MODE}" == "remote" ]]; then
    # Build user section conditionally
    local user_block=""
    if [[ -n "${USER_EMAIL}" ]]; then
      user_block=$'\nuser:\n  email: "'"${USER_EMAIL}"'"'
    fi

    # Minimal config for remote mode (no local_logs section)
    cat > "${PROJECT_DIR}/telemetry.yaml" << YAML
# llm-cli-telemetry configuration (remote mode)
# Regenerated by ./setup.sh

collection:
  log_prompts: ${LOG_PROMPTS}
  log_tool_details: ${LOG_TOOL_DETAILS}

exporters:
  local:
    enabled: false
${user_block}

resource_attributes:
  deployment.environment: remote
YAML
    info "Created minimal telemetry.yaml for remote mode"
  fi
}

# ==============================================================================
# CLI Tool Configuration
# ==============================================================================

configure_codex() {
  if ! command -v codex &>/dev/null; then
    return
  fi

  local config_dir="${HOME}/.codex"
  local config="${config_dir}/config.toml"

  mkdir -p "${config_dir}"

  # Backup existing config
  if [[ -f "${config}" ]] && [[ ! -f "${config}.bak" ]]; then
    cp "${config}" "${config}.bak"
    info "Backed up Codex config to ${config}.bak"
  fi

  # Remove existing [otel*] sections if present (for reconfiguration)
  if [[ -f "${config}" ]] && grep -q '\[otel' "${config}" 2>/dev/null; then
    local tmp
    tmp=$(mktemp)
    awk '/^\[otel/{skip=1; next} /^\[/{skip=0} !skip' "${config}" > "${tmp}"
    # Remove trailing blank lines
    strip_trailing_blank_lines "${tmp}"
    mv "${tmp}" "${config}"
  fi

  local codex_endpoint="${ENDPOINT}"
  local codex_log_prompts="${LOG_PROMPTS}"
  local codex_exporter="otlp-grpc"
  local codex_log_endpoint="${codex_endpoint}"
  local codex_trace_endpoint="${codex_endpoint}"
  if [[ "${PROTOCOL}" == "http" ]]; then
    codex_exporter="otlp-http"
    # otlp-http requires signal-specific paths in the endpoint
    codex_log_endpoint="${codex_endpoint}/v1/logs"
    codex_trace_endpoint="${codex_endpoint}/v1/traces"
  fi

  local codex_environment="${MODE}"

  cat >> "${config}" << TOML

[otel]
environment = "${codex_environment}"
log_user_prompt = ${codex_log_prompts}

[otel.exporter."${codex_exporter}"]
endpoint = "${codex_log_endpoint}"
protocol = "binary"

[otel.trace_exporter."${codex_exporter}"]
endpoint = "${codex_trace_endpoint}"
protocol = "binary"
TOML
  info "Configured Codex CLI [otel] section (endpoint: ${codex_endpoint}, exporter: ${codex_exporter})"
}

configure_gemini() {
  if ! command -v gemini &>/dev/null; then
    return
  fi

  local config_dir="${HOME}/.gemini"
  local config="${config_dir}/settings.json"

  mkdir -p "${config_dir}"

  local gemini_endpoint="${ENDPOINT}"
  local gemini_log_prompts="${LOG_PROMPTS}"
  local gemini_protocol="${PROTOCOL}"

  if [[ -f "${config}" ]]; then
    # Backup existing config
    if [[ ! -f "${config}.bak" ]]; then
      cp "${config}" "${config}.bak"
      info "Backed up Gemini config to ${config}.bak"
    fi

    # Update or add telemetry section
    if command -v jq &>/dev/null; then
      local tmp
      tmp=$(mktemp)
      jq --arg endpoint "${gemini_endpoint}" \
         --arg protocol "${gemini_protocol}" \
         --argjson logPrompts "${gemini_log_prompts}" \
         '. + {
           "telemetry": {
             "enabled": true,
             "target": "local",
             "otlpEndpoint": $endpoint,
             "otlpProtocol": $protocol,
             "logPrompts": $logPrompts
           }
         }' "${config}" > "${tmp}" && mv "${tmp}" "${config}"
    else
      warn "jq not found; skipping Gemini settings.json update"
      return
    fi
  else
    # Create new config
    cat > "${config}" << JSON
{
  "telemetry": {
    "enabled": true,
    "target": "local",
    "otlpEndpoint": "${gemini_endpoint}",
    "otlpProtocol": "${gemini_protocol}",
    "logPrompts": ${gemini_log_prompts}
  }
}
JSON
  fi
  info "Configured Gemini CLI telemetry (endpoint: ${gemini_endpoint}, protocol: ${gemini_protocol})"
}

# ==============================================================================
# Shell RC Integration
# ==============================================================================

install_shell_rc() {
  local shell_rc=""
  if [[ -n "${ZSH_VERSION:-}" ]] || [[ "${SHELL:-}" == *zsh* ]]; then
    shell_rc="${HOME}/.zshrc"
  elif [[ -n "${BASH_VERSION:-}" ]] || [[ "${SHELL:-}" == *bash* ]]; then
    shell_rc="${HOME}/.bashrc"
  fi

  if [[ -z "${shell_rc}" ]]; then
    warn "Could not detect shell RC file. Manually add:"
    warn "  source ${PROJECT_DIR}/scripts/shell-integration.sh"
    return
  fi

  # Remove existing block first (for reconfiguration)
  if [[ -f "${shell_rc}" ]] && grep -q "${MARKER_BEGIN}" "${shell_rc}" 2>/dev/null; then
    local tmp
    tmp=$(mktemp)
    awk -v begin="${MARKER_BEGIN}" -v end="${MARKER_END}" '
      $0 == begin { skip=1; next }
      $0 == end   { skip=0; next }
      !skip
    ' "${shell_rc}" > "${tmp}"
    strip_trailing_blank_lines "${tmp}"
    mv "${tmp}" "${shell_rc}"
  fi

  # Build export block
  local exports=""
  exports+="export LLM_CLI_TELEMETRY_ENDPOINT=\"${ENDPOINT}\"\n"
  exports+="export LLM_CLI_TELEMETRY_PROTOCOL=\"${PROTOCOL}\"\n"

  if [[ -n "${HEADERS}" ]]; then
    exports+="export LLM_CLI_TELEMETRY_HEADERS=\"${HEADERS}\"\n"
  fi

  if [[ "${LOG_PROMPTS}" == "true" ]]; then
    exports+="export LLM_CLI_TELEMETRY_LOG_PROMPTS=1\n"
  fi

  if [[ "${LOG_TOOL_DETAILS}" == "true" ]]; then
    exports+="export LLM_CLI_TELEMETRY_LOG_TOOL_DETAILS=1\n"
  fi

  # User attributes (email, team, custom resource attributes)
  local user_attrs=""
  if [[ -n "${USER_EMAIL}" ]]; then
    user_attrs="user.email=${USER_EMAIL}"
  fi
  # Append custom resource attributes from telemetry.yaml (if yq available)
  if [[ -f "${PROJECT_DIR}/telemetry.yaml" ]] && command -v yq &>/dev/null; then
    local user_team
    user_team=$(yq '.user.team // ""' "${PROJECT_DIR}/telemetry.yaml" 2>/dev/null || true)
    if [[ -n "${user_team}" ]]; then
      user_attrs="${user_attrs:+${user_attrs},}user.team=${user_team}"
    fi
    local custom_attrs
    custom_attrs=$(yq -o=props '.resource_attributes // {}' "${PROJECT_DIR}/telemetry.yaml" 2>/dev/null | \
      while IFS= read -r line; do
        if [[ -n "${line}" ]]; then
          local rkey="${line%% =*}"
          local rval="${line##*= }"
          echo -n "${rkey}=${rval},"
        fi
      done || true)
    custom_attrs="${custom_attrs%,}"
    if [[ -n "${custom_attrs}" ]]; then
      user_attrs="${user_attrs:+${user_attrs},}${custom_attrs}"
    fi
  fi
  if [[ -n "${user_attrs}" ]]; then
    exports+="export LLM_CLI_TELEMETRY_USER_ATTRS=\"${user_attrs}\"\n"
  fi

  cat >> "${shell_rc}" << SHELL

${MARKER_BEGIN}
# llm-cli-telemetry - transparent telemetry collection
# Remove this block or run: ./uninstall.sh
source "${PROJECT_DIR}/scripts/shell-integration.sh"
$(echo -e "${exports}")
${MARKER_END}
SHELL
  info "Added shell integration to ${shell_rc}"
}

# ==============================================================================
# User Attributes (local mode with yq)
# ==============================================================================

generate_user_attrs() {
  # User attributes are now auto-exported by install_shell_rc().
  # This function only displays a summary for informational purposes.
  if [[ ! -f "${PROJECT_DIR}/telemetry.yaml" ]] || ! command -v yq &>/dev/null; then
    return
  fi

  local attrs=""
  local user_email
  user_email=$(yq '.user.email // ""' "${PROJECT_DIR}/telemetry.yaml" 2>/dev/null || true)
  local user_team
  user_team=$(yq '.user.team // ""' "${PROJECT_DIR}/telemetry.yaml" 2>/dev/null || true)

  if [[ -n "${user_email}" ]]; then
    attrs="user.email=${user_email}"
  fi
  if [[ -n "${user_team}" ]]; then
    attrs="${attrs:+${attrs},}user.team=${user_team}"
  fi

  if [[ -n "${attrs}" ]]; then
    info "User attributes: ${attrs}"
  fi
}

# ==============================================================================
# Next Steps
# ==============================================================================

show_next_steps() {
  echo ""
  info "Installation complete!"
  echo ""

  if [[ "${MODE}" == "local" ]]; then
    info "Next steps:"
    info "  1. source ~/.zshrc  (or open a new terminal)"
    info "  2. ./start.sh       (start the telemetry stack)"
    info "  3. open http://localhost:3001  (Grafana: admin / admin)"
    info "  4. claude / codex / gemini  (use normally - telemetry is automatic)"
    info ""
    info "To customize: edit telemetry.yaml, then run: ./start.sh (config auto-regenerates)"

  elif [[ "${MODE}" == "remote" ]]; then
    info "Next steps:"
    info "  1. source ~/.zshrc  (or open a new terminal)"
    info "  2. claude / codex / gemini  (use normally - telemetry is automatic)"
    info "  3. Check your OTLP endpoint for incoming data"
    info ""
    info "No Docker needed! Telemetry is sent directly to: ${ENDPOINT}"
  fi

  info ""
  info "To disable temporarily: LLM_CLI_TELEMETRY_DISABLED=1 claude ..."
  info "To reconfigure: ./setup.sh"
  info "To uninstall: ./uninstall.sh"
}

# ==============================================================================
# Main
# ==============================================================================

main() {
  parse_args "$@"
  show_banner
  detect_existing_setup
  select_mode
  check_prerequisites

  echo ""
  detect_tools
  echo ""

  collect_preferences
  init_config
  write_setup_mode "${MODE}" "${PROTOCOL}" "${ENDPOINT}" "${HEADERS}"
  configure_codex
  configure_gemini
  install_shell_rc
  generate_user_attrs

  show_next_steps
}

main "$@"
