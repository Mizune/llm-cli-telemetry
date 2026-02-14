#!/usr/bin/env bash
# Mock command generators for bats tests.
# Usage: load helpers/mocks

# ---------------------------------------------------------------------------
# create_mock_command <name>
# Create a mock CLI command that prints its own environment to stdout.
# The mock is placed in TEST_TMPDIR/mock-bin and prepended to PATH.
# ---------------------------------------------------------------------------
create_mock_command() {
  local name="$1"
  local mock_dir="${TEST_TMPDIR}/mock-bin"
  mkdir -p "${mock_dir}"

  cat > "${mock_dir}/${name}" << 'SCRIPT'
#!/usr/bin/env bash
env | sort
SCRIPT
  chmod +x "${mock_dir}/${name}"
}

# ---------------------------------------------------------------------------
# create_all_mocks
# Create mock commands for claude, codex, and gemini, then prepend to PATH.
# ---------------------------------------------------------------------------
create_all_mocks() {
  for tool in claude codex gemini; do
    create_mock_command "${tool}"
  done
  export PATH="${TEST_TMPDIR}/mock-bin:${PATH}"
}

# ---------------------------------------------------------------------------
# create_mock_yq
# Create a mock yq that always fails (for testing yq-not-found paths).
# ---------------------------------------------------------------------------
create_mock_yq_missing() {
  local mock_dir="${TEST_TMPDIR}/mock-bin-noyq"
  mkdir -p "${mock_dir}"

  # Shadow real yq with one that always fails
  cat > "${mock_dir}/yq" << 'SCRIPT'
#!/usr/bin/env bash
exit 1
SCRIPT
  chmod +x "${mock_dir}/yq"
  export PATH="${mock_dir}:${PATH}"
}
