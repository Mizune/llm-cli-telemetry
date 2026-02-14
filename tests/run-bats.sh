#!/usr/bin/env bash
# Run all bats tests.
# Usage: ./tests/run-bats.sh [bats-args...]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v bats &>/dev/null; then
  echo "Error: bats-core not installed."
  echo "  macOS:  brew install bats-core"
  echo "  Linux:  see https://bats-core.readthedocs.io/en/stable/installation.html"
  exit 1
fi

bats "${SCRIPT_DIR}"/*.bats "$@"
