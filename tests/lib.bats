#!/usr/bin/env bats
# Tests for scripts/lib.sh

setup() {
  load helpers/setup
  setup_test_home

  source "${BATS_TEST_PROJECT_DIR}/scripts/lib.sh"

  # Redirect .setup-mode to temp dir so tests don't touch the real project
  SETUP_MODE_FILE="${TEST_TMPDIR}/.setup-mode"
}

teardown() {
  teardown_test_home
}

# ===========================================================================
# Log functions
# ===========================================================================

@test "info outputs to stdout with [info] prefix" {
  result=$(info "hello world")
  [ "$result" = "[info] hello world" ]
}

@test "warn outputs to stderr with [warn] prefix" {
  result=$(warn "danger" 2>&1)
  [ "$result" = "[warn] danger" ]
}

@test "error outputs to stderr with [error] prefix and exits 1" {
  run bash -c 'source "'"${BATS_TEST_PROJECT_DIR}"'/scripts/lib.sh"; error "fatal" 2>&1'
  [ "$status" -eq 1 ]
  [ "$output" = "[error] fatal" ]
}

# ===========================================================================
# write_setup_mode / read_setup_mode roundtrip
# ===========================================================================

@test "write_setup_mode creates .setup-mode file" {
  write_setup_mode "local" "grpc" "http://localhost:4317" ""
  [ -f "${SETUP_MODE_FILE}" ]
}

@test "read_setup_mode returns mode" {
  write_setup_mode "local" "grpc" "http://localhost:4317" ""
  result=$(read_setup_mode)
  [ "$result" = "local" ]
}

@test "read_setup_protocol returns protocol" {
  write_setup_mode "local" "grpc" "http://localhost:4317" ""
  result=$(read_setup_protocol)
  [ "$result" = "grpc" ]
}

@test "read_setup_endpoint returns endpoint" {
  write_setup_mode "local" "grpc" "http://localhost:4317" ""
  result=$(read_setup_endpoint)
  [ "$result" = "http://localhost:4317" ]
}

@test "read_setup_headers returns headers" {
  write_setup_mode "remote" "http" "https://example.com/otlp" "Authorization=Basic abc123"
  result=$(read_setup_headers)
  [ "$result" = "Authorization=Basic abc123" ]
}

@test "write/read roundtrip for local mode" {
  write_setup_mode "local" "grpc" "http://localhost:4317" ""
  [ "$(read_setup_mode)" = "local" ]
  [ "$(read_setup_protocol)" = "grpc" ]
  [ "$(read_setup_endpoint)" = "http://localhost:4317" ]
  [ "$(read_setup_headers)" = "" ]
}

@test "write/read roundtrip for remote mode with headers" {
  write_setup_mode "remote" "http" "https://otlp-gw.grafana.net/otlp" "Authorization=Basic dXNlcjprZXk="
  [ "$(read_setup_mode)" = "remote" ]
  [ "$(read_setup_protocol)" = "http" ]
  [ "$(read_setup_endpoint)" = "https://otlp-gw.grafana.net/otlp" ]
  [ "$(read_setup_headers)" = "Authorization=Basic dXNlcjprZXk=" ]
}

@test "read_setup_headers handles multiple pipes in header value" {
  # Pipe inside the header value (e.g. base64 with | characters)
  write_setup_mode "remote" "http" "https://example.com" "Key=val|extra|more"
  result=$(read_setup_headers)
  [ "$result" = "Key=val|extra|more" ]
}

# ===========================================================================
# Missing .setup-mode
# ===========================================================================

@test "read_setup_mode returns empty when .setup-mode missing" {
  rm -f "${SETUP_MODE_FILE}"
  result=$(read_setup_mode)
  [ "$result" = "" ]
}

@test "read_setup_protocol returns empty when .setup-mode missing" {
  rm -f "${SETUP_MODE_FILE}"
  result=$(read_setup_protocol)
  [ "$result" = "" ]
}

@test "read_setup_endpoint returns empty when .setup-mode missing" {
  rm -f "${SETUP_MODE_FILE}"
  result=$(read_setup_endpoint)
  [ "$result" = "" ]
}

@test "read_setup_headers returns empty when .setup-mode missing" {
  rm -f "${SETUP_MODE_FILE}"
  result=$(read_setup_headers)
  [ "$result" = "" ]
}

# ===========================================================================
# strip_trailing_blank_lines
# ===========================================================================

@test "strip_trailing_blank_lines removes trailing blanks" {
  local f="${TEST_TMPDIR}/trail.txt"
  printf 'line1\nline2\n\n\n\n' > "$f"
  strip_trailing_blank_lines "$f"
  # File should end with line2 and no trailing blanks
  local content
  content=$(cat "$f")
  [ "$content" = "$(printf 'line1\nline2')" ]
}

@test "strip_trailing_blank_lines leaves non-trailing blanks intact" {
  local f="${TEST_TMPDIR}/mid.txt"
  printf 'line1\n\nline3\n\n' > "$f"
  strip_trailing_blank_lines "$f"
  local content
  content=$(cat "$f")
  [ "$content" = "$(printf 'line1\n\nline3')" ]
}

# ===========================================================================
# Common variables
# ===========================================================================

@test "PROJECT_DIR points to repository root" {
  [ -f "${PROJECT_DIR}/setup.sh" ]
}

@test "SETUP_MODE_FILE is PROJECT_DIR/.setup-mode (before override)" {
  # Re-source to get the original value
  local orig_smf
  orig_smf=$(bash -c 'source "'"${BATS_TEST_PROJECT_DIR}"'/scripts/lib.sh"; echo "$SETUP_MODE_FILE"')
  [ "$orig_smf" = "${BATS_TEST_PROJECT_DIR}/.setup-mode" ]
}
