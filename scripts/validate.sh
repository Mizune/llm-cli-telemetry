#!/usr/bin/env bash
# Validate all services are running and healthy
set -euo pipefail

echo "=== Validating Services ==="

FAILED=0

check_service() {
  local name="$1"
  local url="$2"
  if curl -sf "${url}" > /dev/null 2>&1; then
    echo "${name} is healthy"
  else
    echo "${name} is unhealthy (${url})"
    FAILED=1
  fi
}

check_service "OTEL Collector" "http://localhost:13133/"
check_service "Prometheus"     "http://localhost:9090/-/healthy"
check_service "Loki"           "http://localhost:3100/ready"
check_service "Tempo"          "http://localhost:3200/ready"
check_service "Grafana"        "http://localhost:3001/api/health"

echo ""
if [[ "${FAILED}" -eq 0 ]]; then
  echo "=== All services healthy ==="
else
  echo "=== Some services are unhealthy ==="
  exit 1
fi
