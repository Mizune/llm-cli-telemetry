#!/usr/bin/env bash
# Check the status of llm-cli-telemetry.
# Shows mode-appropriate health information.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/scripts/lib.sh"

MODE=$(read_setup_mode)
ENDPOINT=$(read_setup_endpoint)
PROTOCOL=$(read_setup_protocol)

echo "=== llm-cli-telemetry Status ==="
echo ""

# Setup mode
if [[ -z "${MODE}" ]]; then
  warn "No setup detected. Run ./setup.sh first."
  exit 1
fi

echo "Mode:     ${MODE}"
echo "Endpoint: ${ENDPOINT}"
echo "Protocol: ${PROTOCOL}"
echo ""

# Shell function check
echo "=== Shell Functions ==="
for tool in claude codex gemini; do
  if type "${tool}" 2>/dev/null | head -1 | grep -q "function"; then
    echo "  ${tool}: function (telemetry active)"
  elif command -v "${tool}" &>/dev/null; then
    echo "  ${tool}: binary (telemetry NOT active - run: source ~/.zshrc)"
  else
    echo "  ${tool}: not installed"
  fi
done
echo ""

# Mode-specific checks
if [[ "${MODE}" == "local" ]]; then
  echo "=== Docker Services ==="
  cd "${PROJECT_DIR}"
  docker compose ps 2>/dev/null || warn "Docker Compose not available or stack not running"
  echo ""

  echo "=== Health Checks ==="
  echo -n "OTEL Collector: "; curl -sf http://localhost:13133/ > /dev/null 2>&1 && echo "OK" || echo "UNHEALTHY"
  echo -n "Prometheus:     "; curl -sf http://localhost:9090/-/healthy > /dev/null 2>&1 && echo "OK" || echo "UNHEALTHY"
  echo -n "Loki:           "; curl -sf http://localhost:3100/ready > /dev/null 2>&1 && echo "OK" || echo "UNHEALTHY"
  echo -n "Tempo:          "; curl -sf http://localhost:3200/ready > /dev/null 2>&1 && echo "OK" || echo "UNHEALTHY"
  echo -n "Grafana:        "; curl -sf http://localhost:3001/api/health > /dev/null 2>&1 && echo "OK" || echo "UNHEALTHY"

elif [[ "${MODE}" == "remote" ]]; then
  echo "=== Remote Endpoint ==="
  echo "Telemetry is sent to: ${ENDPOINT}"
  echo "No local Docker services are used in remote mode."
fi
