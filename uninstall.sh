#!/usr/bin/env bash
# Entry point for llm-cli-telemetry uninstall.
# Delegates to scripts/uninstall.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/scripts/uninstall.sh" "$@"
