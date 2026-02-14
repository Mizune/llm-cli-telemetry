#!/usr/bin/env bash
# Shared setup/teardown for bats tests.
# Usage: load helpers/setup

# Save originals (evaluated once when loaded)
_ORIG_HOME="${HOME}"
_ORIG_SHELL="${SHELL:-/bin/bash}"
_ORIG_PATH="${PATH}"

# Project root (tests/../)
BATS_TEST_PROJECT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

# ---------------------------------------------------------------------------
# setup_test_home - create isolated HOME with .zshrc
# ---------------------------------------------------------------------------
setup_test_home() {
  TEST_TMPDIR="$(mktemp -d)"
  export HOME="${TEST_TMPDIR}"
  export SHELL="/bin/zsh"

  # Copy Docker config so `docker compose version` works
  if [[ -d "${_ORIG_HOME}/.docker" ]]; then
    cp -r "${_ORIG_HOME}/.docker" "${HOME}/.docker" 2>/dev/null || true
  fi
  if [[ -d "${_ORIG_HOME}/.rd" ]]; then
    ln -s "${_ORIG_HOME}/.rd" "${HOME}/.rd" 2>/dev/null || true
  fi

  # Seed a minimal .zshrc
  echo "# existing zshrc content" > "${HOME}/.zshrc"
}

# ---------------------------------------------------------------------------
# teardown_test_home - restore HOME, clean temp and project artefacts
# ---------------------------------------------------------------------------
teardown_test_home() {
  export HOME="${_ORIG_HOME}"
  export SHELL="${_ORIG_SHELL}"
  export PATH="${_ORIG_PATH}"

  # Remove project-level artefacts that tests may have created
  rm -f "${BATS_TEST_PROJECT_DIR}/.setup-mode"

  # Only remove telemetry.yaml if it was created by a test (not the user's copy)
  # Tests that create telemetry.yaml should clean it up themselves or rely on this
  if [[ -n "${TEST_TMPDIR:-}" ]] && [[ -d "${TEST_TMPDIR}" ]]; then
    rm -rf "${TEST_TMPDIR}"
  fi
}

# ---------------------------------------------------------------------------
# load_install_functions - source install.sh without executing main
# ---------------------------------------------------------------------------
load_install_functions() {
  source "${BATS_TEST_PROJECT_DIR}/scripts/lib.sh"

  # Strip set -euo pipefail, SCRIPT_DIR, source lib.sh, and main "$@" call
  local install_src
  install_src=$(sed \
    -e '/^set -euo pipefail$/d' \
    -e '/^SCRIPT_DIR=/d' \
    -e '/^source.*lib\.sh/d' \
    -e '/^main "\$@"$/d' \
    "${BATS_TEST_PROJECT_DIR}/scripts/install.sh")
  eval "${install_src}"
}

# ---------------------------------------------------------------------------
# load_generate_functions - source generate.sh without executing main
# ---------------------------------------------------------------------------
load_generate_functions() {
  source "${BATS_TEST_PROJECT_DIR}/scripts/lib.sh"

  local gen_src
  gen_src=$(sed \
    -e '/^set -euo pipefail$/d' \
    -e '/^SCRIPT_DIR=/d' \
    -e '/^source.*lib\.sh/d' \
    -e '/^main "\$@"$/d' \
    "${BATS_TEST_PROJECT_DIR}/scripts/generate.sh")
  eval "${gen_src}"
}

# ---------------------------------------------------------------------------
# load_uninstall_functions - source uninstall.sh without executing main
# ---------------------------------------------------------------------------
load_uninstall_functions() {
  source "${BATS_TEST_PROJECT_DIR}/scripts/lib.sh"

  local uninst_src
  uninst_src=$(sed \
    -e '/^set -euo pipefail$/d' \
    -e '/^SCRIPT_DIR=/d' \
    -e '/^source.*lib\.sh/d' \
    -e '/^main "\$@"$/d' \
    "${BATS_TEST_PROJECT_DIR}/scripts/uninstall.sh")
  eval "${uninst_src}"
}
