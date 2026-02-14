#!/usr/bin/env bash
# Stop the local telemetry stack (Docker Compose).
# Use --clean to also remove volumes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/scripts/lib.sh"

cd "${PROJECT_DIR}"

if [[ "${1:-}" == "--clean" ]]; then
  docker compose down -v
  info "Stopped services and removed volumes."
else
  docker compose down
  info "Stopped services."
fi
