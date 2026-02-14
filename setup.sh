#!/usr/bin/env bash
# Entry point for llm-cli-telemetry setup.
# Delegates to scripts/install.sh with all arguments.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/scripts/install.sh" "$@"
