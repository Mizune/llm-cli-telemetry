#!/usr/bin/env bash
# Fixture file helpers for bats tests.
# Usage: load helpers/fixtures

FIXTURES_DIR="${BATS_TEST_DIRNAME}/fixtures"

# ---------------------------------------------------------------------------
# use_fixture <fixture_name> [target_path]
# Copy a fixture file to the specified target (default: PROJECT_DIR/telemetry.yaml).
# ---------------------------------------------------------------------------
use_fixture() {
  local fixture_name="$1"
  local target="${2:-${BATS_TEST_PROJECT_DIR}/telemetry.yaml}"
  cp "${FIXTURES_DIR}/${fixture_name}" "${target}"
}

# ---------------------------------------------------------------------------
# use_fixture_to_tmp <fixture_name> [filename]
# Copy a fixture into TEST_TMPDIR and echo the resulting path.
# ---------------------------------------------------------------------------
use_fixture_to_tmp() {
  local fixture_name="$1"
  local filename="${2:-${fixture_name}}"
  local target="${TEST_TMPDIR}/${filename}"
  cp "${FIXTURES_DIR}/${fixture_name}" "${target}"
  echo "${target}"
}
