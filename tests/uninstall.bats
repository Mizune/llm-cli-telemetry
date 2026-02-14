#!/usr/bin/env bats
# Tests for scripts/uninstall.sh

setup() {
  load helpers/setup
  load helpers/fixtures
  load helpers/mocks
  setup_test_home
  create_all_mocks      # codex/gemini on PATH for detection

  load_uninstall_functions

  # Redirect .setup-mode to temp dir
  SETUP_MODE_FILE="${TEST_TMPDIR}/.setup-mode"
}

teardown() {
  teardown_test_home
}

# ===========================================================================
# remove_shell_rc
# ===========================================================================

@test "remove_shell_rc: removes marker block from .zshrc" {
  cat >> "${HOME}/.zshrc" << 'EOF'

# >>> llm-cli-telemetry >>>
source /path/to/shell-integration.sh
export LLM_CLI_TELEMETRY_ENDPOINT="http://localhost:4317"
# <<< llm-cli-telemetry <<<
EOF

  remove_shell_rc

  ! grep -q '>>> llm-cli-telemetry >>>' "${HOME}/.zshrc"
  ! grep -q 'shell-integration.sh' "${HOME}/.zshrc"
}

@test "remove_shell_rc: preserves content outside markers" {
  cat >> "${HOME}/.zshrc" << 'EOF'

# >>> llm-cli-telemetry >>>
source /path/to/shell-integration.sh
# <<< llm-cli-telemetry <<<
EOF

  remove_shell_rc

  grep -q 'existing zshrc content' "${HOME}/.zshrc"
}

@test "remove_shell_rc: handles .bashrc" {
  echo "# bash content" > "${HOME}/.bashrc"
  cat >> "${HOME}/.bashrc" << 'EOF'
# >>> llm-cli-telemetry >>>
source /path/to/shell-integration.sh
# <<< llm-cli-telemetry <<<
EOF

  remove_shell_rc

  grep -q 'bash content' "${HOME}/.bashrc"
  ! grep -q 'llm-cli-telemetry' "${HOME}/.bashrc"
}

@test "remove_shell_rc: no error when RC file missing" {
  rm -f "${HOME}/.zshrc" "${HOME}/.bashrc"
  # Should not fail
  remove_shell_rc
}

# ===========================================================================
# restore_codex
# ===========================================================================

@test "restore_codex: restores from .bak" {
  mkdir -p "${HOME}/.codex"
  echo '[otel]' > "${HOME}/.codex/config.toml"
  cp "${FIXTURES_DIR}/codex-config-existing.toml" "${HOME}/.codex/config.toml.bak"

  restore_codex

  ! [ -f "${HOME}/.codex/config.toml.bak" ]
  grep -q 'max_entries' "${HOME}/.codex/config.toml"
  ! grep -q '\[otel\]' "${HOME}/.codex/config.toml"
}

@test "restore_codex: warns when no .bak but [otel] present" {
  mkdir -p "${HOME}/.codex"
  echo -e '[otel]\nendpoint = "http://localhost:4317"' > "${HOME}/.codex/config.toml"

  output=$(restore_codex 2>&1)
  [[ "$output" == *"no backup found"* ]]
}

@test "restore_codex: no error when config missing" {
  # No .codex dir at all
  restore_codex
}

# ===========================================================================
# restore_gemini
# ===========================================================================

@test "restore_gemini: restores from .bak" {
  mkdir -p "${HOME}/.gemini"
  echo '{"telemetry":{"enabled":true}}' > "${HOME}/.gemini/settings.json"
  cp "${FIXTURES_DIR}/gemini-settings-existing.json" "${HOME}/.gemini/settings.json.bak"

  restore_gemini

  ! [ -f "${HOME}/.gemini/settings.json.bak" ]
  grep -q '"theme"' "${HOME}/.gemini/settings.json"
}

@test "restore_gemini: removes telemetry with jq when no .bak" {
  if ! command -v jq &>/dev/null; then
    skip "jq not installed"
  fi

  mkdir -p "${HOME}/.gemini"
  cat > "${HOME}/.gemini/settings.json" << 'JSON'
{
  "model": "gemini-2.0-flash",
  "telemetry": {
    "enabled": true
  }
}
JSON

  restore_gemini

  local config="${HOME}/.gemini/settings.json"
  jq -e '.model == "gemini-2.0-flash"' "$config" >/dev/null
  ! jq -e '.telemetry' "$config" >/dev/null 2>&1 || \
    [ "$(jq '.telemetry' "$config")" = "null" ]
}

@test "restore_gemini: warns when jq missing and no .bak" {
  mkdir -p "${HOME}/.gemini"
  echo '{"telemetry":{"enabled":true}}' > "${HOME}/.gemini/settings.json"

  # Build a minimal PATH with symlinks to needed tools but NOT jq
  local safe_bin="${TEST_TMPDIR}/safe-bin"
  mkdir -p "${safe_bin}"
  for tool in grep mv cat; do
    local real_path
    real_path=$(command -v "${tool}" 2>/dev/null || true)
    if [[ -n "${real_path}" ]]; then
      ln -sf "${real_path}" "${safe_bin}/${tool}"
    fi
  done

  # Write a test script so we fully control PATH in the subprocess
  cat > "${TEST_TMPDIR}/test_nojq.sh" << SCRIPT
#!/bin/bash
export PATH="${safe_bin}"
export HOME="${HOME}"
source "${BATS_TEST_PROJECT_DIR}/scripts/lib.sh"
SETUP_MODE_FILE="${TEST_TMPDIR}/.setup-mode"
$(sed \
  -e '/^set -euo pipefail$/d' \
  -e '/^SCRIPT_DIR=/d' \
  -e '/^source.*lib\.sh/d' \
  -e '/^main "\$@"$/d' \
  "${BATS_TEST_PROJECT_DIR}/scripts/uninstall.sh")
restore_gemini
SCRIPT
  chmod +x "${TEST_TMPDIR}/test_nojq.sh"

  run "${TEST_TMPDIR}/test_nojq.sh"
  [[ "$output" == *"jq not found"* ]]
}

# ===========================================================================
# remove_setup_mode
# ===========================================================================

@test "remove_setup_mode: deletes .setup-mode" {
  write_setup_mode "local" "grpc" "http://localhost:4317" ""
  [ -f "${SETUP_MODE_FILE}" ]

  remove_setup_mode

  ! [ -f "${SETUP_MODE_FILE}" ]
}

@test "remove_setup_mode: no error when .setup-mode missing" {
  rm -f "${SETUP_MODE_FILE}"
  remove_setup_mode
}
