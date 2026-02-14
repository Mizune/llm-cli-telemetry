#!/usr/bin/env bash
# Generate OTEL Collector config and docker-compose.override.yml from telemetry.yaml
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

TELEMETRY_YAML="${PROJECT_DIR}/telemetry.yaml"
COLLECTOR_CONFIG="${PROJECT_DIR}/otel-collector/collector-config.yaml"
COMPOSE_OVERRIDE="${PROJECT_DIR}/docker-compose.override.yml"

# --- Mode check ---
check_mode() {
  local mode
  mode=$(read_setup_mode)

  if [[ -n "${mode}" ]] && [[ "${mode}" != "local" ]]; then
    info "Setup mode is '${mode}' - collector config generation is only needed for local mode."
    info "Skipping."
    exit 0
  fi
}

# --- Validate dependencies ---
check_deps() {
  if ! command -v yq &>/dev/null; then
    error "yq is required. Install: brew install yq"
  fi
  if [[ ! -f "${TELEMETRY_YAML}" ]]; then
    error "telemetry.yaml not found. Run: ./setup.sh"
  fi
}

# --- Read config values ---
cfg() {
  yq "$1" "${TELEMETRY_YAML}" 2>/dev/null || echo "$2"
}

cfg_bool() {
  local val
  val=$(cfg "$1" "${2:-false}")
  [[ "${val}" == "true" ]]
}

# --- Generate receivers section ---
generate_receivers() {
  cat << 'YAML'
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318
YAML

  # Local log collection: filelog receivers
  if cfg_bool '.local_logs.claude_code.enabled'; then
    local claude_collectors
    claude_collectors=$(yq '.local_logs.claude_code.collect[]' "${TELEMETRY_YAML}" 2>/dev/null || true)

    for collector in ${claude_collectors}; do
      case "${collector}" in
        history)
          cat << 'YAML'
  filelog/claude_code_history:
    include:
      - /var/log/claude-code/history.jsonl
    start_at: end
    operators:
      - type: json_parser
        timestamp:
          parse_from: attributes.timestamp
          layout_type: epoch
          layout: s
    resource:
      cli_tool: claude-code
      log_source: history
YAML
          ;;
        tool_debug)
          cat << 'YAML'
  filelog/claude_code_tool_debug:
    include:
      - /var/log/claude-code/post-tool-debug.log
    start_at: end
    multiline:
      line_start_pattern: '^\{'
    operators:
      - type: json_parser
    resource:
      cli_tool: claude-code
      log_source: tool_debug
YAML
          ;;
        context)
          cat << 'YAML'
  filelog/claude_code_context:
    include:
      - /var/log/claude-code/current.json
    start_at: beginning
    poll_interval: 30s
    operators:
      - type: json_parser
    resource:
      cli_tool: claude-code
      log_source: context
YAML
          ;;
      esac
    done
  fi

  if cfg_bool '.local_logs.codex_cli.enabled'; then
    local codex_collectors
    codex_collectors=$(yq '.local_logs.codex_cli.collect[]' "${TELEMETRY_YAML}" 2>/dev/null || true)

    for collector in ${codex_collectors}; do
      case "${collector}" in
        sessions)
          cat << 'YAML'
  filelog/codex_sessions:
    include:
      - /var/log/codex-cli/sessions/**/*.jsonl
    start_at: end
    operators:
      - type: json_parser
    resource:
      cli_tool: codex-cli
      log_source: sessions
YAML
          ;;
        history)
          cat << 'YAML'
  filelog/codex_history:
    include:
      - /var/log/codex-cli/history.jsonl
    start_at: end
    operators:
      - type: json_parser
    resource:
      cli_tool: codex-cli
      log_source: history
YAML
          ;;
      esac
    done
  fi
}

# --- Generate processors section ---
generate_processors() {
  cat << 'YAML'
processors:
  batch:
    timeout: 5s
    send_batch_size: 1024
  deltatocumulative:
YAML

  # Resource processor with user-defined attributes
  echo "  resource:"
  echo "    attributes:"

  # Static resource attributes from telemetry.yaml
  local attrs
  attrs=$(yq -o=props '.resource_attributes // {}' "${TELEMETRY_YAML}" 2>/dev/null || true)
  while IFS= read -r line; do
    if [[ -n "${line}" ]]; then
      local key="${line%% =*}"
      local value="${line##*= }"
      echo "      - key: ${key}"
      echo "        value: ${value}"
      echo "        action: upsert"
    fi
  done <<< "${attrs}"

  # User identification attributes
  local user_email
  user_email=$(cfg '.user.email // ""' "")
  if [[ -n "${user_email}" ]]; then
    echo "      - key: user.email"
    echo "        value: ${user_email}"
    echo "        action: upsert"
  fi

  local user_team
  user_team=$(cfg '.user.team // ""' "")
  if [[ -n "${user_team}" ]]; then
    echo "      - key: user.team"
    echo "        value: ${user_team}"
    echo "        action: upsert"
  fi
}

# --- Generate connectors section ---
generate_connectors() {
  local metrics_count
  metrics_count=$(yq '.custom_metrics | length' "${TELEMETRY_YAML}" 2>/dev/null || echo "0")

  if [[ "${metrics_count}" -eq 0 ]]; then
    return
  fi

  echo "connectors:"
  echo "  count:"
  echo "    logs:"

  local i=0
  while [[ $i -lt ${metrics_count} ]]; do
    local name
    name=$(yq ".custom_metrics[${i}].name" "${TELEMETRY_YAML}")
    local desc
    desc=$(yq ".custom_metrics[${i}].description" "${TELEMETRY_YAML}")
    local attr_count
    attr_count=$(yq ".custom_metrics[${i}].attributes | length" "${TELEMETRY_YAML}" 2>/dev/null || echo "0")

    echo "      ${name}:"
    echo "        description: \"${desc}\""

    if [[ "${attr_count}" -gt 0 ]]; then
      echo "        attributes:"
      local j=0
      while [[ $j -lt ${attr_count} ]]; do
        local attr_key
        attr_key=$(yq ".custom_metrics[${i}].attributes[${j}].key" "${TELEMETRY_YAML}")
        local attr_default
        attr_default=$(yq ".custom_metrics[${i}].attributes[${j}].default_value" "${TELEMETRY_YAML}")
        echo "          - key: ${attr_key}"
        echo "            default_value: \"${attr_default}\""
        j=$((j + 1))
      done
    fi

    i=$((i + 1))
  done
}

# --- Generate exporters section ---
generate_exporters() {
  echo "exporters:"

  # Local stack exporters
  if cfg_bool '.exporters.local.enabled'; then
    cat << 'YAML'
  prometheusremotewrite:
    endpoint: http://prometheus:9090/api/v1/write
    resource_to_telemetry_conversion:
      enabled: true
  otlp/tempo:
    endpoint: tempo:4317
    tls:
      insecure: true
  otlphttp/loki:
    endpoint: http://loki:3100/otlp
    tls:
      insecure: true
YAML
  fi

  # Grafana Cloud exporter
  if cfg_bool '.exporters.grafana_cloud.enabled'; then
    local endpoint
    endpoint=$(cfg '.exporters.grafana_cloud.endpoint' "")
    local instance_id
    instance_id=$(cfg '.exporters.grafana_cloud.instance_id' "")
    local api_key
    api_key=$(cfg '.exporters.grafana_cloud.api_key' "")

    cat << YAML
  otlphttp/grafana_cloud:
    endpoint: ${endpoint}
    headers:
      Authorization: "Basic \$(echo -n '${instance_id}:${api_key}' | base64)"
YAML
  fi

  # Custom OTLP HTTP exporter
  if cfg_bool '.exporters.otlp_http.enabled'; then
    local endpoint
    endpoint=$(cfg '.exporters.otlp_http.endpoint' "")
    local insecure
    insecure=$(cfg '.exporters.otlp_http.insecure' "false")

    echo "  otlphttp/custom:"
    echo "    endpoint: ${endpoint}"

    if [[ "${insecure}" == "true" ]]; then
      echo "    tls:"
      echo "      insecure: true"
    fi

    # Custom headers
    local header_count
    header_count=$(yq '.exporters.otlp_http.headers | length' "${TELEMETRY_YAML}" 2>/dev/null || echo "0")
    if [[ "${header_count}" -gt 0 ]]; then
      echo "    headers:"
      yq -o=props '.exporters.otlp_http.headers // {}' "${TELEMETRY_YAML}" 2>/dev/null | \
        while IFS= read -r line; do
          if [[ -n "${line}" ]]; then
            local hkey="${line%% =*}"
            local hval="${line##*= }"
            echo "      ${hkey}: \"${hval}\""
          fi
        done
    fi
  fi

  # Debug exporter (always included)
  cat << 'YAML'
  debug:
    verbosity: basic
YAML
}

# --- Generate service/pipelines section ---
generate_service() {
  local has_connectors=false
  local metrics_count
  metrics_count=$(yq '.custom_metrics | length' "${TELEMETRY_YAML}" 2>/dev/null || echo "0")
  [[ "${metrics_count}" -gt 0 ]] && has_connectors=true

  # Collect filelog receiver names
  local filelog_receivers=""
  if cfg_bool '.local_logs.claude_code.enabled'; then
    for c in $(yq '.local_logs.claude_code.collect[]' "${TELEMETRY_YAML}" 2>/dev/null || true); do
      case "${c}" in
        history)    filelog_receivers="${filelog_receivers}, filelog/claude_code_history" ;;
        tool_debug) filelog_receivers="${filelog_receivers}, filelog/claude_code_tool_debug" ;;
        context)    filelog_receivers="${filelog_receivers}, filelog/claude_code_context" ;;
      esac
    done
  fi
  if cfg_bool '.local_logs.codex_cli.enabled'; then
    for c in $(yq '.local_logs.codex_cli.collect[]' "${TELEMETRY_YAML}" 2>/dev/null || true); do
      case "${c}" in
        sessions) filelog_receivers="${filelog_receivers}, filelog/codex_sessions" ;;
        history)  filelog_receivers="${filelog_receivers}, filelog/codex_history" ;;
      esac
    done
  fi

  # Build exporter lists
  local metrics_exporters="debug"
  local traces_exporters="debug"
  local logs_exporters="debug"

  if cfg_bool '.exporters.local.enabled'; then
    metrics_exporters="prometheusremotewrite, ${metrics_exporters}"
    traces_exporters="otlp/tempo, ${traces_exporters}"
    logs_exporters="otlphttp/loki, ${logs_exporters}"
  fi

  if cfg_bool '.exporters.grafana_cloud.enabled'; then
    metrics_exporters="otlphttp/grafana_cloud, ${metrics_exporters}"
    traces_exporters="otlphttp/grafana_cloud, ${traces_exporters}"
    logs_exporters="otlphttp/grafana_cloud, ${logs_exporters}"
  fi

  if cfg_bool '.exporters.otlp_http.enabled'; then
    metrics_exporters="otlphttp/custom, ${metrics_exporters}"
    traces_exporters="otlphttp/custom, ${traces_exporters}"
    logs_exporters="otlphttp/custom, ${logs_exporters}"
  fi

  # Add count connector to logs exporters if custom metrics defined
  if ${has_connectors}; then
    logs_exporters="count, ${logs_exporters}"
  fi

  # Log receivers
  local log_receivers="otlp"
  if [[ -n "${filelog_receivers}" ]]; then
    log_receivers="otlp${filelog_receivers}"
  fi

  cat << YAML
service:
  telemetry:
    logs:
      level: info
  extensions: [health_check]
  pipelines:
    metrics:
      receivers: [otlp]
      processors: [deltatocumulative, batch, resource]
      exporters: [${metrics_exporters}]
YAML

  if ${has_connectors}; then
    cat << YAML
    metrics/derived:
      receivers: [count]
      processors: [deltatocumulative, batch]
      exporters: [${metrics_exporters}]
YAML
  fi

  cat << YAML
    traces:
      receivers: [otlp]
      processors: [batch, resource]
      exporters: [${traces_exporters}]
    logs:
      receivers: [${log_receivers}]
      processors: [batch, resource]
      exporters: [${logs_exporters}]
YAML
}

# --- Generate docker-compose.override.yml ---
generate_compose_override() {
  local need_override=false
  local volumes=""

  if cfg_bool '.local_logs.claude_code.enabled'; then
    need_override=true
    volumes="${volumes}      - \${HOME}/.claude/metrics:/var/log/claude-code:ro\n"
  fi

  if cfg_bool '.local_logs.codex_cli.enabled'; then
    need_override=true
    volumes="${volumes}      - \${HOME}/.codex:/var/log/codex-cli:ro\n"
  fi

  if ! ${need_override}; then
    # Remove override file if it exists and no overrides are needed
    if [[ -f "${COMPOSE_OVERRIDE}" ]]; then
      rm "${COMPOSE_OVERRIDE}"
      info "Removed docker-compose.override.yml (no local log collection enabled)"
    fi
    return
  fi

  cat > "${COMPOSE_OVERRIDE}" << YAML
# Auto-generated by scripts/generate.sh - DO NOT EDIT
# Regenerate with: ./start.sh (auto-generates) or scripts/generate.sh
services:
  otel-collector:
    volumes:
      - ./otel-collector/collector-config.yaml:/etc/otelcol-contrib/config.yaml:ro
$(echo -e "${volumes}")
YAML
  info "Generated docker-compose.override.yml"
}

# --- Main ---
main() {
  check_mode
  check_deps

  info "Generating from telemetry.yaml..."

  # Generate collector config
  {
    echo "# Auto-generated by scripts/generate.sh - DO NOT EDIT"
    echo "# Source: telemetry.yaml"
    echo "# Regenerate with: ./start.sh (auto-generates) or scripts/generate.sh"
    echo ""
    echo "extensions:"
    echo "  health_check:"
    echo "    endpoint: 0.0.0.0:13133"
    echo ""
    generate_receivers
    echo ""
    generate_processors
    echo ""
    generate_connectors
    echo ""
    generate_exporters
    echo ""
    generate_service
  } > "${COLLECTOR_CONFIG}"

  info "Generated ${COLLECTOR_CONFIG}"

  generate_compose_override

  info "Done! Run './start.sh' to apply changes."
}

main "$@"
