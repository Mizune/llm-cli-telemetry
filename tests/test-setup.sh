#!/usr/bin/env bash
# Automated tests for llm-cli-telemetry setup scripts.
# Uses a temporary HOME directory to avoid modifying real configs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# --- Test framework ---
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILURES=""

pass() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo "  PASS: $1"
}

fail() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILURES="${FAILURES}\n  FAIL: $1"
  echo "  FAIL: $1"
}

assert_file_exists() {
  if [[ -f "$1" ]]; then
    pass "$2"
  else
    fail "$2 (file not found: $1)"
  fi
}

assert_file_not_exists() {
  if [[ ! -f "$1" ]]; then
    pass "$2"
  else
    fail "$2 (file exists but should not: $1)"
  fi
}

assert_file_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then
    pass "$3"
  else
    fail "$3 (pattern '$2' not found in $1)"
  fi
}

assert_file_not_contains() {
  if ! grep -q "$2" "$1" 2>/dev/null; then
    pass "$3"
  else
    fail "$3 (pattern '$2' found in $1 but should not be)"
  fi
}

assert_equals() {
  if [[ "$1" == "$2" ]]; then
    pass "$3"
  else
    fail "$3 (expected '$2', got '$1')"
  fi
}

# --- Test environment setup ---
ORIGINAL_HOME="${HOME}"
ORIGINAL_SHELL="${SHELL}"
TEST_TMPDIR=""

setup_test_env() {
  TEST_TMPDIR=$(mktemp -d)
  export HOME="${TEST_TMPDIR}"
  export SHELL="/bin/zsh"

  # Copy Docker config so `docker compose version` works with modified HOME
  if [[ -d "${ORIGINAL_HOME}/.docker" ]]; then
    cp -r "${ORIGINAL_HOME}/.docker" "${HOME}/.docker"
  fi
  # Rancher Desktop uses .rd for Docker socket config
  if [[ -d "${ORIGINAL_HOME}/.rd" ]]; then
    ln -s "${ORIGINAL_HOME}/.rd" "${HOME}/.rd"
  fi

  # Create .zshrc
  echo "# existing zshrc content" > "${HOME}/.zshrc"

  # Clean project state
  rm -f "${PROJECT_DIR}/.setup-mode"
  rm -f "${PROJECT_DIR}/telemetry.yaml"
}

teardown_test_env() {
  export HOME="${ORIGINAL_HOME}"
  export SHELL="${ORIGINAL_SHELL}"

  # Clean project state
  rm -f "${PROJECT_DIR}/.setup-mode"
  rm -f "${PROJECT_DIR}/telemetry.yaml"

  if [[ -n "${TEST_TMPDIR}" ]] && [[ -d "${TEST_TMPDIR}" ]]; then
    rm -rf "${TEST_TMPDIR}"
  fi
  TEST_TMPDIR=""
}

# ==============================================================================
# Test: lib.sh functions
# ==============================================================================
test_lib_functions() {
  echo ""
  echo "=== Test: lib.sh functions ==="
  setup_test_env

  # Source lib.sh
  SCRIPT_DIR="${PROJECT_DIR}/scripts"
  source "${SCRIPT_DIR}/lib.sh"

  # Test write and read
  write_setup_mode "local" "grpc" "http://localhost:4317" ""
  assert_file_exists "${PROJECT_DIR}/.setup-mode" ".setup-mode created"

  local mode
  mode=$(read_setup_mode)
  assert_equals "${mode}" "local" "read_setup_mode returns 'local'"

  local protocol
  protocol=$(read_setup_protocol)
  assert_equals "${protocol}" "grpc" "read_setup_protocol returns 'grpc'"

  local endpoint
  endpoint=$(read_setup_endpoint)
  assert_equals "${endpoint}" "http://localhost:4317" "read_setup_endpoint returns correct URL"

  # Test with headers
  write_setup_mode "remote" "http" "https://example.com/otlp" "Authorization=Basic abc123"

  mode=$(read_setup_mode)
  assert_equals "${mode}" "remote" "read_setup_mode returns 'remote'"

  local headers
  headers=$(read_setup_headers)
  assert_equals "${headers}" "Authorization=Basic abc123" "read_setup_headers returns correct value"

  # Test when no .setup-mode exists
  rm -f "${PROJECT_DIR}/.setup-mode"
  mode=$(read_setup_mode)
  assert_equals "${mode}" "" "read_setup_mode returns empty when file missing"

  teardown_test_env
}

# ==============================================================================
# Test: Headless local mode
# ==============================================================================
test_headless_local() {
  echo ""
  echo "=== Test: Headless local mode ==="
  setup_test_env

  # Run setup in headless local mode
  "${PROJECT_DIR}/scripts/install.sh" --mode local > /dev/null 2>&1

  # Verify .setup-mode
  assert_file_exists "${PROJECT_DIR}/.setup-mode" ".setup-mode created"
  assert_file_contains "${PROJECT_DIR}/.setup-mode" "^local|" ".setup-mode starts with 'local'"
  assert_file_contains "${PROJECT_DIR}/.setup-mode" "grpc" ".setup-mode contains grpc protocol"
  assert_file_contains "${PROJECT_DIR}/.setup-mode" "localhost:4317" ".setup-mode contains localhost endpoint"

  # Verify telemetry.yaml
  assert_file_exists "${PROJECT_DIR}/telemetry.yaml" "telemetry.yaml created"
  assert_file_contains "${PROJECT_DIR}/telemetry.yaml" "log_prompts: false" "telemetry.yaml has log_prompts: false"
  assert_file_contains "${PROJECT_DIR}/telemetry.yaml" "local_logs:" "telemetry.yaml has local_logs section (full template)"

  # Verify shell RC
  assert_file_contains "${HOME}/.zshrc" "llm-cli-telemetry" "Shell integration added to .zshrc"
  assert_file_contains "${HOME}/.zshrc" "shell-integration.sh" ".zshrc sources shell-integration.sh"
  assert_file_contains "${HOME}/.zshrc" "LLM_CLI_TELEMETRY_ENDPOINT" ".zshrc exports ENDPOINT"
  assert_file_contains "${HOME}/.zshrc" "LLM_CLI_TELEMETRY_PROTOCOL" ".zshrc exports PROTOCOL"
  assert_file_contains "${HOME}/.zshrc" "localhost:4317" ".zshrc has localhost endpoint"

  teardown_test_env
}

# ==============================================================================
# Test: Headless local mode with log options
# ==============================================================================
test_headless_local_with_options() {
  echo ""
  echo "=== Test: Headless local mode with --log-prompts --log-tool-details ==="
  setup_test_env

  "${PROJECT_DIR}/scripts/install.sh" --mode local --log-prompts --log-tool-details > /dev/null 2>&1

  # Verify telemetry.yaml has log options enabled
  assert_file_contains "${PROJECT_DIR}/telemetry.yaml" "log_prompts: true" "log_prompts enabled in telemetry.yaml"
  assert_file_contains "${PROJECT_DIR}/telemetry.yaml" "log_tool_details: true" "log_tool_details enabled in telemetry.yaml"

  # Verify shell RC has log env vars
  assert_file_contains "${HOME}/.zshrc" "LLM_CLI_TELEMETRY_LOG_PROMPTS=1" ".zshrc exports LOG_PROMPTS=1"
  assert_file_contains "${HOME}/.zshrc" "LLM_CLI_TELEMETRY_LOG_TOOL_DETAILS=1" ".zshrc exports LOG_TOOL_DETAILS=1"

  teardown_test_env
}

# ==============================================================================
# Test: Headless remote mode
# ==============================================================================
test_headless_remote() {
  echo ""
  echo "=== Test: Headless remote mode ==="
  setup_test_env

  "${PROJECT_DIR}/scripts/install.sh" --mode remote --endpoint "https://otlp.example.com:4317" --protocol grpc > /dev/null 2>&1

  # Verify .setup-mode
  assert_file_exists "${PROJECT_DIR}/.setup-mode" ".setup-mode created"
  assert_file_contains "${PROJECT_DIR}/.setup-mode" "^remote|" ".setup-mode starts with 'remote'"
  assert_file_contains "${PROJECT_DIR}/.setup-mode" "grpc" ".setup-mode contains grpc"
  assert_file_contains "${PROJECT_DIR}/.setup-mode" "otlp.example.com" ".setup-mode contains remote endpoint"

  # Verify telemetry.yaml is minimal (no local_logs)
  assert_file_exists "${PROJECT_DIR}/telemetry.yaml" "telemetry.yaml created"
  assert_file_not_contains "${PROJECT_DIR}/telemetry.yaml" "local_logs" "telemetry.yaml has NO local_logs section (minimal)"
  assert_file_contains "${PROJECT_DIR}/telemetry.yaml" "enabled: false" "local exporter disabled"

  # Verify shell RC
  assert_file_contains "${HOME}/.zshrc" "otlp.example.com" ".zshrc has remote endpoint"
  assert_file_not_contains "${HOME}/.zshrc" "LLM_CLI_TELEMETRY_HEADERS" ".zshrc has no HEADERS (not provided)"

  teardown_test_env
}

# ==============================================================================
# Test: Headless remote mode with auth header
# ==============================================================================
test_headless_remote_with_auth() {
  echo ""
  echo "=== Test: Headless remote mode with --auth-header ==="
  setup_test_env

  "${PROJECT_DIR}/scripts/install.sh" --mode remote \
    --endpoint "https://otel.example.com:4318" \
    --protocol http \
    --auth-header "Authorization: Bearer my-token-123" > /dev/null 2>&1

  # Verify .setup-mode has headers
  assert_file_contains "${PROJECT_DIR}/.setup-mode" "http" ".setup-mode has http protocol"
  assert_file_contains "${PROJECT_DIR}/.setup-mode" "Authorization=Bearer my-token-123" ".setup-mode has auth header"

  # Verify shell RC has headers
  assert_file_contains "${HOME}/.zshrc" "LLM_CLI_TELEMETRY_HEADERS" ".zshrc exports HEADERS"
  assert_file_contains "${HOME}/.zshrc" "Authorization=Bearer my-token-123" ".zshrc has correct auth header"

  teardown_test_env
}

# ==============================================================================
# Test: Headless remote mode with Grafana Cloud
# ==============================================================================
test_headless_grafana_cloud() {
  echo ""
  echo "=== Test: Headless remote mode with Grafana Cloud ==="
  setup_test_env

  "${PROJECT_DIR}/scripts/install.sh" --mode remote \
    --endpoint "https://otlp-gateway-prod-us-central-0.grafana.net/otlp" \
    --instance-id "123456" \
    --api-key "glc_test_key" > /dev/null 2>&1

  # Verify .setup-mode
  assert_file_contains "${PROJECT_DIR}/.setup-mode" "remote" ".setup-mode is remote"
  assert_file_contains "${PROJECT_DIR}/.setup-mode" "http" "Grafana Cloud defaults to http protocol"
  assert_file_contains "${PROJECT_DIR}/.setup-mode" "Authorization=Basic" ".setup-mode has Basic auth"

  # Verify shell RC
  assert_file_contains "${HOME}/.zshrc" "grafana.net" ".zshrc has Grafana Cloud endpoint"
  assert_file_contains "${HOME}/.zshrc" "LLM_CLI_TELEMETRY_HEADERS" ".zshrc exports auth HEADERS"

  teardown_test_env
}

# ==============================================================================
# Test: Headless remote mode without endpoint fails
# ==============================================================================
test_headless_remote_no_endpoint() {
  echo ""
  echo "=== Test: Headless remote mode without --endpoint fails ==="
  setup_test_env

  if "${PROJECT_DIR}/scripts/install.sh" --mode remote > /dev/null 2>&1; then
    fail "setup.sh --mode remote without --endpoint should fail"
  else
    pass "setup.sh --mode remote without --endpoint exits with error"
  fi

  teardown_test_env
}

# ==============================================================================
# Test: Idempotency - re-run overwrites cleanly
# ==============================================================================
test_idempotency() {
  echo ""
  echo "=== Test: Idempotency ==="
  setup_test_env

  # First run: local
  "${PROJECT_DIR}/scripts/install.sh" --mode local > /dev/null 2>&1

  assert_file_contains "${PROJECT_DIR}/.setup-mode" "^local|" "First run: local mode"

  # Second run: remote (overwrite)
  "${PROJECT_DIR}/scripts/install.sh" --mode remote --endpoint "https://remote.example.com:4317" > /dev/null 2>&1

  assert_file_contains "${PROJECT_DIR}/.setup-mode" "^remote|" "Second run: mode updated to remote"
  assert_file_contains "${PROJECT_DIR}/.setup-mode" "remote.example.com" "Second run: endpoint updated"

  # Verify shell RC is clean (no duplicate blocks)
  local marker_count
  marker_count=$(grep -c ">>> llm-cli-telemetry >>>" "${HOME}/.zshrc" || true)
  assert_equals "${marker_count}" "1" "Only one marker block in .zshrc after re-run"

  # Verify shell RC has new endpoint
  assert_file_contains "${HOME}/.zshrc" "remote.example.com" ".zshrc updated to new endpoint"
  assert_file_not_contains "${HOME}/.zshrc" "localhost:4317" ".zshrc no longer has localhost"

  teardown_test_env
}

# ==============================================================================
# Test: generate.sh mode check
# ==============================================================================
test_generate_mode_check() {
  echo ""
  echo "=== Test: generate.sh mode check ==="
  setup_test_env

  # Set mode to remote
  SCRIPT_DIR="${PROJECT_DIR}/scripts"
  source "${SCRIPT_DIR}/lib.sh"
  write_setup_mode "remote" "http" "https://remote.example.com/otlp" ""

  # generate.sh should skip for remote mode
  local output
  output=$("${PROJECT_DIR}/scripts/generate.sh" 2>&1)
  if echo "${output}" | grep -q "only needed for local mode"; then
    pass "generate.sh skips for remote mode"
  else
    fail "generate.sh should skip for remote mode"
  fi

  # Set mode to local - generate.sh should proceed (may fail due to no telemetry.yaml, that's OK)
  write_setup_mode "local" "grpc" "http://localhost:4317" ""
  output=$("${PROJECT_DIR}/scripts/generate.sh" 2>&1 || true)
  if echo "${output}" | grep -q "only needed for local mode"; then
    fail "generate.sh should NOT skip for local mode"
  else
    pass "generate.sh proceeds for local mode"
  fi

  teardown_test_env
}

# ==============================================================================
# Test: uninstall.sh cleans up .setup-mode
# ==============================================================================
test_uninstall() {
  echo ""
  echo "=== Test: uninstall.sh ==="
  setup_test_env

  # First install
  "${PROJECT_DIR}/scripts/install.sh" --mode local > /dev/null 2>&1
  assert_file_exists "${PROJECT_DIR}/.setup-mode" "Pre-uninstall: .setup-mode exists"
  assert_file_contains "${HOME}/.zshrc" "llm-cli-telemetry" "Pre-uninstall: shell integration present"

  # Uninstall
  "${PROJECT_DIR}/scripts/uninstall.sh" > /dev/null 2>&1

  assert_file_not_exists "${PROJECT_DIR}/.setup-mode" "Post-uninstall: .setup-mode removed"
  assert_file_not_contains "${HOME}/.zshrc" "llm-cli-telemetry" "Post-uninstall: shell integration removed"
  assert_file_contains "${HOME}/.zshrc" "existing zshrc content" "Post-uninstall: original .zshrc content preserved"

  teardown_test_env
}

# ==============================================================================
# Test: start.sh rejects remote mode
# ==============================================================================
test_start_rejects_remote() {
  echo ""
  echo "=== Test: start.sh rejects remote mode ==="
  setup_test_env

  SCRIPT_DIR="${PROJECT_DIR}/scripts"
  source "${SCRIPT_DIR}/lib.sh"
  write_setup_mode "remote" "http" "https://remote.example.com/otlp" ""

  if "${PROJECT_DIR}/start.sh" > /dev/null 2>&1; then
    fail "start.sh should fail for remote mode"
  else
    pass "start.sh exits with error for remote mode"
  fi

  teardown_test_env
}

# ==============================================================================
# Test: shell-integration.sh protocol conversion
# ==============================================================================
test_shell_integration_protocol() {
  echo ""
  echo "=== Test: shell-integration.sh protocol handling ==="

  # Source and verify function exists
  source "${PROJECT_DIR}/scripts/shell-integration.sh"

  if type claude | head -1 | grep -q "function"; then
    pass "claude function is defined"
  else
    fail "claude function not defined"
  fi

  if type codex | head -1 | grep -q "function"; then
    pass "codex function is defined"
  else
    fail "codex function not defined"
  fi

  if type gemini | head -1 | grep -q "function"; then
    pass "gemini function is defined"
  else
    fail "gemini function not defined"
  fi

  # Verify shell-integration.sh file contains protocol conversion logic
  assert_file_contains "${PROJECT_DIR}/scripts/shell-integration.sh" 'LLM_CLI_TELEMETRY_PROTOCOL' "shell-integration.sh references PROTOCOL var"
  assert_file_contains "${PROJECT_DIR}/scripts/shell-integration.sh" 'http/protobuf' "shell-integration.sh converts http to http/protobuf"
  assert_file_contains "${PROJECT_DIR}/scripts/shell-integration.sh" 'LLM_CLI_TELEMETRY_HEADERS' "shell-integration.sh references HEADERS var"
}

# ==============================================================================
# Test: --help flag
# ==============================================================================
test_help_flag() {
  echo ""
  echo "=== Test: --help flag ==="

  local output
  output=$("${PROJECT_DIR}/scripts/install.sh" --help 2>&1)
  if echo "${output}" | grep -q "Usage:"; then
    pass "--help shows usage"
  else
    fail "--help should show usage"
  fi

  if echo "${output}" | grep -q -- "--mode"; then
    pass "--help mentions --mode flag"
  else
    fail "--help should mention --mode"
  fi

  if echo "${output}" | grep -q -- "--endpoint"; then
    pass "--help mentions --endpoint flag"
  else
    fail "--help should mention --endpoint"
  fi
}

# ==============================================================================
# Main
# ==============================================================================

echo "============================================"
echo " llm-cli-telemetry Test Suite"
echo "============================================"

test_lib_functions
test_headless_local
test_headless_local_with_options
test_headless_remote
test_headless_remote_with_auth
test_headless_grafana_cloud
test_headless_remote_no_endpoint
test_idempotency
test_generate_mode_check
test_uninstall
test_start_rejects_remote
test_shell_integration_protocol
test_help_flag

echo ""
echo "============================================"
echo " Results: ${TESTS_PASSED}/${TESTS_RUN} passed, ${TESTS_FAILED} failed"
echo "============================================"

if [[ ${TESTS_FAILED} -gt 0 ]]; then
  echo ""
  echo "Failures:"
  echo -e "${FAILURES}"
  exit 1
fi
