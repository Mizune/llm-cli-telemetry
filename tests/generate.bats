#!/usr/bin/env bats
# Tests for scripts/generate.sh
# Requires yq — tests are skipped if yq is not installed.

setup() {
  load helpers/setup
  load helpers/fixtures
  setup_test_home

  if ! command -v yq &>/dev/null; then
    skip "yq not installed"
  fi

  load_generate_functions

  # Redirect generated files to temp dir
  TELEMETRY_YAML="${TEST_TMPDIR}/telemetry.yaml"
  COLLECTOR_CONFIG="${TEST_TMPDIR}/collector-config.yaml"
  COMPOSE_OVERRIDE="${TEST_TMPDIR}/docker-compose.override.yml"

  # Default: write a local .setup-mode
  SETUP_MODE_FILE="${TEST_TMPDIR}/.setup-mode"
  write_setup_mode "local" "grpc" "http://localhost:4317" ""
}

teardown() {
  teardown_test_home
}

# ===========================================================================
# check_mode
# ===========================================================================

@test "check_mode: exits 0 for remote mode (skip generation)" {
  write_setup_mode "remote" "http" "https://remote.example.com" ""
  run check_mode
  [ "$status" -eq 0 ]
  [[ "$output" == *"only needed for local mode"* ]]
}

@test "check_mode: continues for local mode" {
  write_setup_mode "local" "grpc" "http://localhost:4317" ""
  # check_mode should return without output about skipping
  result=$(check_mode 2>&1 || true)
  [[ "$result" != *"only needed for local mode"* ]]
}

# ===========================================================================
# check_deps
# ===========================================================================

@test "check_deps: fails when telemetry.yaml is missing" {
  rm -f "${TELEMETRY_YAML}"
  run bash -c '
    source "'"${BATS_TEST_PROJECT_DIR}"'/scripts/lib.sh"
    TELEMETRY_YAML="'"${TELEMETRY_YAML}"'"
    check_deps() {
      if [[ ! -f "${TELEMETRY_YAML}" ]]; then
        error "telemetry.yaml not found. Run: ./setup.sh"
      fi
    }
    check_deps 2>&1
  '
  [ "$status" -eq 1 ]
  [[ "$output" == *"telemetry.yaml not found"* ]]
}

# ===========================================================================
# generate_receivers
# ===========================================================================

@test "generate_receivers: always includes otlp receiver" {
  cp "${FIXTURES_DIR}/telemetry-local-minimal.yaml" "${TELEMETRY_YAML}"
  output=$(generate_receivers)
  [[ "$output" == *"otlp:"* ]]
  [[ "$output" == *"0.0.0.0:4317"* ]]
  [[ "$output" == *"0.0.0.0:4318"* ]]
}

@test "generate_receivers: includes filelog when local_logs enabled" {
  cp "${FIXTURES_DIR}/telemetry-local-full.yaml" "${TELEMETRY_YAML}"
  output=$(generate_receivers)
  [[ "$output" == *"filelog/claude_code_history"* ]]
  [[ "$output" == *"filelog/claude_code_tool_debug"* ]]
  [[ "$output" == *"filelog/claude_code_context"* ]]
  [[ "$output" == *"filelog/codex_sessions"* ]]
  [[ "$output" == *"filelog/codex_history"* ]]
}

@test "generate_receivers: no filelog when local_logs disabled" {
  cp "${FIXTURES_DIR}/telemetry-local-minimal.yaml" "${TELEMETRY_YAML}"
  output=$(generate_receivers)
  [[ "$output" != *"filelog/"* ]]
}

# ===========================================================================
# generate_processors
# ===========================================================================

@test "generate_processors: includes batch and deltatocumulative" {
  cp "${FIXTURES_DIR}/telemetry-local-minimal.yaml" "${TELEMETRY_YAML}"
  output=$(generate_processors)
  [[ "$output" == *"batch:"* ]]
  [[ "$output" == *"deltatocumulative:"* ]]
}

@test "generate_processors: includes resource attributes from config" {
  cp "${FIXTURES_DIR}/telemetry-user-attrs.yaml" "${TELEMETRY_YAML}"
  output=$(generate_processors)
  [[ "$output" == *"deployment.environment"* ]]
  [[ "$output" == *"development"* ]]
  [[ "$output" == *"service.version"* ]]
  [[ "$output" == *"1.0.0"* ]]
}

@test "generate_processors: includes user email and team" {
  cp "${FIXTURES_DIR}/telemetry-user-attrs.yaml" "${TELEMETRY_YAML}"
  output=$(generate_processors)
  [[ "$output" == *"user.email"* ]]
  [[ "$output" == *"dev@example.com"* ]]
  [[ "$output" == *"user.team"* ]]
  [[ "$output" == *"platform"* ]]
}

# ===========================================================================
# generate_connectors
# ===========================================================================

@test "generate_connectors: includes count connector with custom_metrics" {
  cp "${FIXTURES_DIR}/telemetry-custom-metrics.yaml" "${TELEMETRY_YAML}"
  output=$(generate_connectors)
  [[ "$output" == *"connectors:"* ]]
  [[ "$output" == *"count:"* ]]
  [[ "$output" == *"codex_events_total:"* ]]
  [[ "$output" == *"event_name"* ]]
}

@test "generate_connectors: empty when no custom_metrics" {
  cp "${FIXTURES_DIR}/telemetry-local-minimal.yaml" "${TELEMETRY_YAML}"
  output=$(generate_connectors)
  [ -z "$output" ]
}

# ===========================================================================
# generate_exporters
# ===========================================================================

@test "generate_exporters: includes local stack exporters" {
  cp "${FIXTURES_DIR}/telemetry-local-minimal.yaml" "${TELEMETRY_YAML}"
  output=$(generate_exporters)
  [[ "$output" == *"prometheusremotewrite:"* ]]
  [[ "$output" == *"otlp/tempo:"* ]]
  [[ "$output" == *"otlphttp/loki:"* ]]
  [[ "$output" == *"debug:"* ]]
}

@test "generate_exporters: includes Grafana Cloud exporter" {
  cp "${FIXTURES_DIR}/telemetry-grafana-cloud.yaml" "${TELEMETRY_YAML}"
  output=$(generate_exporters)
  [[ "$output" == *"otlphttp/grafana_cloud:"* ]]
  [[ "$output" == *"grafana.net"* ]]
}

@test "generate_exporters: includes OTLP HTTP exporter with headers" {
  cp "${FIXTURES_DIR}/telemetry-otlp-http.yaml" "${TELEMETRY_YAML}"
  output=$(generate_exporters)
  [[ "$output" == *"otlphttp/custom:"* ]]
  [[ "$output" == *"otel.example.com"* ]]
  [[ "$output" == *"Authorization"* ]]
  [[ "$output" == *"X-Custom-Header"* ]]
}

@test "generate_exporters: always includes debug exporter" {
  cp "${FIXTURES_DIR}/telemetry-local-minimal.yaml" "${TELEMETRY_YAML}"
  output=$(generate_exporters)
  [[ "$output" == *"debug:"* ]]
}

# ===========================================================================
# generate_service
# ===========================================================================

@test "generate_service: includes metrics, traces, logs pipelines" {
  cp "${FIXTURES_DIR}/telemetry-local-minimal.yaml" "${TELEMETRY_YAML}"
  output=$(generate_service)
  [[ "$output" == *"metrics:"* ]]
  [[ "$output" == *"traces:"* ]]
  [[ "$output" == *"logs:"* ]]
}

@test "generate_service: includes filelog receivers in logs pipeline" {
  cp "${FIXTURES_DIR}/telemetry-local-full.yaml" "${TELEMETRY_YAML}"
  output=$(generate_service)
  [[ "$output" == *"filelog/claude_code_history"* ]]
  [[ "$output" == *"filelog/codex_sessions"* ]]
}

@test "generate_service: includes metrics/derived pipeline with custom_metrics" {
  cp "${FIXTURES_DIR}/telemetry-custom-metrics.yaml" "${TELEMETRY_YAML}"
  output=$(generate_service)
  [[ "$output" == *"metrics/derived:"* ]]
  [[ "$output" == *"count"* ]]
}

@test "generate_service: no metrics/derived without custom_metrics" {
  cp "${FIXTURES_DIR}/telemetry-local-minimal.yaml" "${TELEMETRY_YAML}"
  output=$(generate_service)
  [[ "$output" != *"metrics/derived:"* ]]
}

# ===========================================================================
# generate_compose_override
# ===========================================================================

@test "generate_compose_override: creates override with local_logs volumes" {
  cp "${FIXTURES_DIR}/telemetry-local-full.yaml" "${TELEMETRY_YAML}"
  generate_compose_override
  [ -f "${COMPOSE_OVERRIDE}" ]
  grep -q '.claude/metrics' "${COMPOSE_OVERRIDE}"
  grep -q '.codex' "${COMPOSE_OVERRIDE}"
}

@test "generate_compose_override: no override without local_logs" {
  cp "${FIXTURES_DIR}/telemetry-local-minimal.yaml" "${TELEMETRY_YAML}"
  # Pre-create to verify removal
  echo "old" > "${COMPOSE_OVERRIDE}"
  generate_compose_override
  [ ! -f "${COMPOSE_OVERRIDE}" ]
}
