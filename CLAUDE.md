# llm-cli-telemetry

## Project Overview

Telemetry collection stack for **Claude Code**, **Codex CLI**, and **Gemini CLI** via shell function wrappers. Supports two modes: **local** (Docker Compose stack with Prometheus/Loki/Tempo/Grafana) and **remote** (direct OTLP export to any endpoint, no Docker required). Data flows through OTEL Collector or directly to remote endpoints.

## Architecture

- Shell functions wrap `claude`/`codex`/`gemini` commands, injecting OTEL env vars transparently
- `telemetry.yaml` drives all configuration; `scripts/generate.sh` produces collector config and compose overrides (local mode only)
- Data collection: automatic OTEL export + optional local log file ingestion via filelog receiver
- Env var prefix: `LLM_CLI_TELEMETRY_*`
- `.setup-mode` file stores current mode/protocol/endpoint/headers (pipe-delimited)

## Key Files

| File | Purpose |
|------|---------|
| `setup.sh` | Entry point: interactive setup (calls scripts/install.sh) |
| `start.sh` | Start local Docker stack with auto-generate |
| `stop.sh` | Stop Docker services (--clean for volumes) |
| `status.sh` | Mode-aware health check |
| `uninstall.sh` | Entry point: remove integration (calls scripts/uninstall.sh) |
| `scripts/lib.sh` | Shared utilities: logging, .setup-mode readers, common variables |
| `scripts/shell-integration.sh` | Shell functions (claude/codex/gemini) with OTEL env vars |
| `scripts/install.sh` | Interactive setup: mode selection, prerequisites, CLI configs |
| `scripts/uninstall.sh` | Remove shell integration, restore configs from .bak |
| `scripts/generate.sh` | `telemetry.yaml` -> collector-config.yaml + docker-compose.override.yml |
| `.env.example` | Environment variables template (Grafana creds, OTEL endpoint) |
| `.setup-mode` | Generated: setup state (mode\|protocol\|endpoint\|headers) |
| `telemetry.example.yaml` | User config template (copied to telemetry.yaml on install) |
| `otel-collector/collector-config.yaml` | Generated OTEL Collector pipeline config |
| `docker-compose.yml` | Service definitions (collector, prometheus, loki, tempo, grafana) |

## Commands

```bash
./setup.sh       # Interactive setup (local stack or remote export)
./setup.sh --mode local                          # Headless: local stack
./setup.sh --mode remote --endpoint https://...  # Headless: remote export
./start.sh       # Start local Docker stack (auto-regenerates config)
./stop.sh        # Stop services
./stop.sh --clean  # Stop and remove volumes
./status.sh      # Mode-aware health check
./uninstall.sh   # Remove integration, restore configs
```

## Port Map

| Service | Port |
|---------|------|
| OTEL Collector | 4317 (gRPC), 4318 (HTTP), 13133 (health) |
| Prometheus | 9090 |
| Loki | 3100 |
| Tempo | 3200 |
| Grafana | 3001 (host) -> 3000 (container) |

## Technical Notes

- **OTEL Collector image** (`otel/opentelemetry-collector-contrib`) is distroless: no shell, wget, or curl. Healthcheck is disabled in compose; use `./status.sh` (external curl) instead.
- **Prometheus** uses remote-write receiver (`--web.enable-remote-write-receiver`), not scrape configs.
- **Grafana datasource UIDs**: `prometheus`, `loki`, `tempo` (hardcoded in provisioning).
- **`cli_tool` resource attribute** differentiates tools across all signals. Values: `claude-code`, `codex-cli`, `gemini-cli`.
- **yq** (`brew install yq`) is required for `generate.sh` (local mode only). It outputs `key = value` (spaces around `=`) in props mode.
- **Codex CLI** OTEL is configured via `~/.codex/config.toml` `[otel]` section (set by install.sh).
- **Gemini CLI** uses `GEMINI_API_KEY` (not `GOOGLE_API_KEY`). Telemetry is enabled via `GEMINI_TELEMETRY_*` env vars.
- **`.setup-mode`** is a pipe-delimited state file: `mode|protocol|endpoint|headers`. Read by `scripts/lib.sh` functions.
- **Remote mode** requires no Docker/yq; only shell functions and optional jq (for Gemini config).

## Shell Integration Markers

install.sh adds a marker-wrapped block to `~/.zshrc` (or `~/.bashrc`):

```
# >>> llm-cli-telemetry >>>
source /path/to/scripts/shell-integration.sh
export LLM_CLI_TELEMETRY_ENDPOINT="http://localhost:4317"
export LLM_CLI_TELEMETRY_PROTOCOL="grpc"
# <<< llm-cli-telemetry <<<
```

uninstall.sh removes everything between these markers.

## Development Workflow

1. Edit `telemetry.example.yaml` for config schema changes
2. Edit `scripts/generate.sh` for collector config generation logic
3. Edit `scripts/shell-integration.sh` for env var changes
4. Test: `./setup.sh --mode local && ./start.sh`
5. Verify: `./status.sh` then check Grafana at http://localhost:3001
