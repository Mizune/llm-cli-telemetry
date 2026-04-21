#!/usr/bin/env bash
# Start the local telemetry stack (Docker Compose).
# Automatically regenerates collector config from telemetry.yaml.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/scripts/lib.sh"

MODE=$(read_setup_mode)

if [[ -z "${MODE}" ]]; then
  info "No setup detected. Running setup in local mode..."
  "${SCRIPT_DIR}/setup.sh" --mode local
  MODE=$(read_setup_mode)
fi

if [[ "${MODE}" != "local" ]]; then
  warn "Setup mode is '${MODE}' - the local Docker stack is not needed."
  warn "Telemetry is sent directly to: $(read_setup_endpoint)"
  warn ""
  warn "To switch to local mode, run: ./setup.sh"
  exit 1
fi

# Auto-generate collector config if telemetry.yaml exists
if [[ -f "${PROJECT_DIR}/telemetry.yaml" ]]; then
  "${SCRIPT_DIR}/scripts/generate.sh"
fi

cd "${PROJECT_DIR}"

# Copy .env.example to .env if not present
if [[ ! -f ".env" ]] && [[ -f ".env.example" ]]; then
  info "Creating .env from .env.example ..."
  cp ".env.example" ".env"
fi

docker compose up -d

echo ""
info "Waiting for services to become healthy..."
sleep 10

# Health check
echo ""
echo "=== Service Status ==="
docker compose ps
echo ""
echo "=== Health Checks ==="
echo -n "OTEL Collector: "; curl -sf http://localhost:13133/ > /dev/null 2>&1 && echo "OK" || echo "UNHEALTHY"
echo -n "Prometheus:     "; curl -sf http://localhost:9090/-/healthy > /dev/null 2>&1 && echo "OK" || echo "UNHEALTHY"
echo -n "Loki:           "; curl -sf http://localhost:3100/ready > /dev/null 2>&1 && echo "OK" || echo "UNHEALTHY"
echo -n "Tempo:          "; curl -sf http://localhost:3200/ready > /dev/null 2>&1 && echo "OK" || echo "UNHEALTHY"
echo -n "Grafana:        "; curl -sf http://localhost:3001/api/health > /dev/null 2>&1 && echo "OK" || echo "UNHEALTHY"
