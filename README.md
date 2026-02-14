# llm-cli-telemetry

[![CI](https://github.com/Mizune/llm-cli-telemetry/actions/workflows/test.yml/badge.svg)](https://github.com/Mizune/llm-cli-telemetry/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![OpenTelemetry](https://img.shields.io/badge/OpenTelemetry-enabled-blue.svg)](https://opentelemetry.io/)

Collect and visualize telemetry from **Claude Code**, **OpenAI Codex CLI**, and **Google Gemini CLI** using OpenTelemetry, Prometheus, Loki, Tempo, and Grafana.

> **Disclaimer:** This is an independent, community-driven project and is not affiliated with, endorsed by, or sponsored by Anthropic, OpenAI, or Google.

## Architecture

```
  Claude Code          Codex CLI           Gemini CLI
  (shell function)     (shell function)    (shell function)
       |  OTLP/gRPC         |  OTLP/gRPC       |  OTLP/gRPC
       +--------------------+-+-----------------+
                             |
               OpenTelemetry Collector (:4317/:4318)
               [batch, resource, deltatocumulative]
               [filelog receivers for local logs]
                    |          |          |
              metrics      traces       logs
                 |            |           |
            Prometheus    Tempo        Loki
             (:9090)     (:3200)     (:3100)
                 |            |           |
                 +------+-----+-----------+
                        |
                    Grafana (:3000)
                  5 pre-built dashboards
```

## Quick Start

### Local Stack

Run the full observability stack locally with Docker.

```bash
# 1. Setup (select "Local Stack")
./setup.sh

# 2. Reload shell
source ~/.zshrc   # or: source ~/.bashrc

# 3. Copy environment variables (optional, auto-copied on start)
cp .env.example .env

# 4. Start the stack
./start.sh

# 5. Open Grafana
open http://localhost:3001  # admin / admin

# 6. Use CLI tools normally - telemetry is automatic
claude "What is 2+2?"
```

### Remote Export

Send telemetry directly to a remote OTLP endpoint (no Docker needed).

```bash
# 1. Setup (select "Remote Export", enter endpoint)
./setup.sh

# 2. Reload shell
source ~/.zshrc   # or: source ~/.bashrc

# 3. Done! No Docker needed - use CLI tools normally
claude "What is 2+2?"
```

### Headless / CI Setup

```bash
# Local stack (non-interactive)
./setup.sh --mode local

# Grafana Cloud (non-interactive)
./setup.sh --mode remote \
  --endpoint https://otlp-gateway-prod-us-central-0.grafana.net/otlp \
  --instance-id 123456 --api-key glc_xxx

# Other OTLP endpoint (non-interactive)
./setup.sh --mode remote --endpoint https://otel.example.com:4317 --protocol grpc

# With user identification
./setup.sh --mode remote --endpoint https://... --user-email you@example.com
```

## Prerequisites

### Local Stack Mode
- [Docker](https://docs.docker.com/get-docker/) and Docker Compose v2
- [yq](https://github.com/mikefarah/yq) - YAML processor for config generation
  - macOS: `brew install yq`
  - Linux: `sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && sudo chmod +x /usr/local/bin/yq`

### Remote Export Mode
- Nothing! Just shell functions.
- Optional: [jq](https://jqlang.github.io/jq/) for Gemini CLI config (`brew install jq`)

### Both Modes
- At least one of:
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`npm install -g @anthropic-ai/claude-code`)
  - [Codex CLI](https://github.com/openai/codex) (`npm install -g @openai/codex`)
  - [Gemini CLI](https://github.com/google-gemini/gemini-cli) (`npm install -g @google/gemini-cli`)

## How It Works

`./setup.sh` performs the following setup:

1. **Mode selection** - choose between local Docker stack or remote OTLP export
2. **Prerequisites check** - verifies Docker/yq (local) or jq (remote, optional)
3. **CLI tool auto-detection** - detects which of claude/codex/gemini are installed
4. **Privacy preferences** - asks about prompt/tool detail logging
5. **User identification** - optional email address (added as `user.email` resource attribute)
6. **Config initialization** - creates `telemetry.yaml` (full template for local, minimal for remote)
7. **Codex CLI configuration** - adds an `[otel]` section to `~/.codex/config.toml` for exporter settings (backs up existing config to `.bak`). Codex uses its own OTEL SDK and ignores standard `OTEL_EXPORTER_*` env vars; resource attributes (`cli_tool`, `user.email`) are injected via `OTEL_RESOURCE_ATTRIBUTES` in the shell wrapper.
8. **Gemini CLI configuration** - adds a `telemetry` section to `~/.gemini/settings.json` (backs up existing config to `.bak`)
9. **Shell function registration** - adds a marker-wrapped block to `~/.zshrc` (or `~/.bashrc`) that sources shell functions wrapping each CLI tool. These functions set the necessary OTEL environment variables before calling the real binary.

After installation, CLI tools are used normally. Telemetry collection is completely transparent:

```bash
# Telemetry is collected automatically
claude "explain this code"

# Disable for a single command
LLM_CLI_TELEMETRY_DISABLED=1 claude "private task"

# Enable prompt logging (privacy-sensitive)
LLM_CLI_TELEMETRY_LOG_PROMPTS=1 claude "hello"
```

## Collected Data

Each CLI tool emits different telemetry via OTEL. Here is a summary:

| | Claude Code | Codex CLI | Gemini CLI |
|---|---|---|---|
| **Metrics** | token usage, cost, sessions, lines of code, commits, PRs, code edits, active time (8 types) | feature state, approvals, tool calls, conversation turns, shell snapshots (5 types) | agent runs, plan executions, startup duration, token usage, operation duration (5 types) |
| **Logs/Events** | prompts, tool results, API requests/errors, tool decisions | session starts, API requests, SSE events, prompts, tool decisions/results | 40+ event types (tool execution, file operations, API calls, model routing, etc.) |
| **Traces** | - | conversation execution spans | - |

### Local Log Collection (optional, local mode only)

In addition to the OTEL data above, you can optionally collect data from CLI tools' local log files on disk. This provides extra data not available through OTEL, such as:

- **Claude Code** (`~/.claude/metrics/`): conversation history, tool execution diffs, context window consumption %
- **Codex CLI** (`~/.codex/`): full session data, prompt history, Git metadata (commits, branches, repo URLs)
- **Gemini CLI**: no local log files available

Enable in `telemetry.yaml`:

```yaml
local_logs:
  claude_code:
    enabled: true
    collect:
      - history      # Conversation history (history.jsonl)
      - tool_debug   # Tool execution logs + diffs (post-tool-debug.log)
      - context      # Context window consumption % (current.json)
  codex_cli:
    enabled: true
    collect:
      - sessions     # Full session data (sessions/**/*.jsonl)
      - history      # Prompt history (history.jsonl)
```

See [docs/telemetry-data-reference.md](docs/telemetry-data-reference.md) for the complete data reference.

## Configuration

Edit `telemetry.yaml` to customize behavior, then restart with `./start.sh` (config is auto-regenerated on startup).

### Data Collection

```yaml
collection:
  log_prompts: false       # Include prompt content in logs
  log_tool_details: false  # Include tool execution details
```

### Export Destinations

```yaml
exporters:
  local:
    enabled: true          # Local Prometheus/Loki/Tempo stack
  grafana_cloud:
    enabled: false
    endpoint: "https://otlp-gateway-prod-us-central-0.grafana.net/otlp"
    instance_id: "123456"
    api_key: "glc_xxx..."
  otlp_http:
    enabled: false
    endpoint: "https://otel.example.com:4318"
```

### User Identification

During `./setup.sh`, you'll be prompted for an email address (optional). This is added as a `user.email` resource attribute to all telemetry data (metrics, logs, and traces). You can also set it via `--user-email` in headless mode.

To change later, edit `telemetry.yaml`:

```yaml
user:
  email: "you@example.com"
  team: "backend-team"
```

After editing, re-run `./setup.sh` to update the shell integration export.

### Custom Metrics

Define log-to-metric conversions using the OTEL Collector count connector:

```yaml
custom_metrics:
  - name: codex_events_total
    description: "Count of Codex CLI log events"
    attributes:
      - key: event_name
        default_value: "unknown"
```

## Environment Variables

Shell functions respect the following environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `LLM_CLI_TELEMETRY_DISABLED` | (unset) | Set to `1` to bypass telemetry for a single command |
| `LLM_CLI_TELEMETRY_ENDPOINT` | `http://localhost:4317` | OTLP endpoint |
| `LLM_CLI_TELEMETRY_PROTOCOL` | `grpc` | OTLP protocol (`grpc` or `http`) |
| `LLM_CLI_TELEMETRY_HEADERS` | (unset) | OTLP headers (e.g. `Authorization=Basic xxx`) |
| `LLM_CLI_TELEMETRY_LOG_PROMPTS` | `0` | Set to `1` to include prompt content in logs |
| `LLM_CLI_TELEMETRY_LOG_TOOL_DETAILS` | `0` | Set to `1` to include tool execution details |
| `LLM_CLI_TELEMETRY_USER_ATTRS` | (auto-set by setup) | Additional OTEL resource attributes (e.g. `user.email=you@example.com,user.team=backend`) |

`LLM_CLI_TELEMETRY_USER_ATTRS` is automatically set in your shell RC by `./setup.sh` based on `telemetry.yaml`. You can also override it manually to add custom resource attributes:

```bash
export LLM_CLI_TELEMETRY_USER_ATTRS="user.email=you@example.com,user.team=backend,custom.project=myapp"
```

These attributes are applied to all signals (metrics, logs, traces) via `OTEL_RESOURCE_ATTRIBUTES`.

> **Note:** Codex CLI reads exporter settings (endpoint, protocol) from `~/.codex/config.toml`, not from `LLM_CLI_TELEMETRY_ENDPOINT`/`LLM_CLI_TELEMETRY_PROTOCOL`. To change the Codex endpoint, edit `~/.codex/config.toml` or re-run `./setup.sh`. Resource attributes (`cli_tool`, `user.email`) are still injected via the shell wrapper's `OTEL_RESOURCE_ATTRIBUTES`.

## Privacy

- **Prompts are NOT logged by default.** Set `collection.log_prompts: true` in `telemetry.yaml` or use `LLM_CLI_TELEMETRY_LOG_PROMPTS=1` per-command.
- **Tool details are NOT logged by default.** Set `collection.log_tool_details: true` or use `LLM_CLI_TELEMETRY_LOG_TOOL_DETAILS=1`.
- **Local log files** are mounted read-only (`:ro`) into the collector container.
  - Claude Code: only `~/.claude/metrics/` is mounted (not the parent directory which may contain auth data).
  - Codex CLI: `~/.codex/` is mounted (sessions and history only; `auth.json` is not read by the collector).

## Dashboards

| Dashboard | Description |
|-----------|-------------|
| **LLM Telemetry Overview** | Aggregate metrics across all tools: session counts, total tokens, error rates, recent events |
| **Claude Code** | Detailed Claude Code metrics: token breakdown (input/output/cache), tool executions, API latency, cost estimate |
| **Codex CLI** | Codex CLI metrics: conversations, token usage, stream latency, trace waterfall |
| **Gemini CLI** | Gemini CLI metrics: sessions, token usage, operation duration, trace waterfall |
| **Tool Comparison** | Side-by-side comparison: token usage, latency distribution, error rates, input/output ratio |

## Commands

```bash
./setup.sh       # Interactive setup (local stack or remote export)
./start.sh       # Start local Docker stack (auto-regenerates collector config)
./stop.sh        # Stop all Docker services
./stop.sh --clean  # Stop and remove all Docker volumes
./status.sh      # Check service health (mode-aware)
./uninstall.sh   # Remove shell integration + restore CLI tool configs
```

## Service Ports

| Service | Port | Protocol |
|---------|------|----------|
| OTEL Collector | 4317 | OTLP gRPC |
| OTEL Collector | 4318 | OTLP HTTP |
| OTEL Collector | 13133 | Health check |
| Prometheus | 9090 | HTTP |
| Loki | 3100 | HTTP |
| Tempo | 3200 | HTTP |
| Grafana | 3001 (host) -> 3000 (container) | HTTP |

## Project Structure

```
llm-cli-telemetry/
├── setup.sh                         # Entry point: interactive setup
├── start.sh                         # Start local Docker stack
├── stop.sh                          # Stop Docker services (--clean for volumes)
├── status.sh                        # Mode-aware health check
├── uninstall.sh                     # Remove integration + restore configs
├── docker-compose.yml               # Service definitions
├── docker-compose.override.yml      # Generated: local log volume mounts
├── .env.example                     # Environment variables template (cp to .env)
├── .setup-mode                      # Generated: setup state (mode|protocol|endpoint)
├── telemetry.example.yaml           # Configuration template
├── telemetry.yaml                   # Your config (gitignored)
├── otel-collector/
│   └── collector-config.yaml        # Generated: OTEL Collector pipeline config
├── prometheus/
│   └── prometheus.yml               # Prometheus config
├── loki/
│   └── loki-config.yaml             # Loki storage config
├── tempo/
│   └── tempo-config.yaml            # Tempo trace storage config
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/
│   │   │   └── datasources.yaml
│   │   └── dashboards/
│   │       └── dashboards.yaml
│   └── dashboards/
│       ├── overview.json
│       ├── claude-code.json
│       ├── codex-cli.json
│       ├── gemini-cli.json
│       └── comparison.json
├── scripts/
│   ├── lib.sh                       # Shared utilities (logging, mode readers)
│   ├── shell-integration.sh         # Shell functions (sourced by RC)
│   ├── install.sh                   # Install: interactive setup + CLI configs
│   ├── uninstall.sh                 # Uninstall: restore everything
│   ├── generate.sh                  # Generate collector config from YAML
│   └── validate.sh                  # Health validation
└── docs/
    └── telemetry-data-reference.md  # Complete data reference per tool
```

## Troubleshooting

### Services not starting

```bash
docker compose logs otel-collector
docker compose logs loki
./status.sh
```

### No data in Grafana

1. Verify OTEL Collector health: `curl -s http://localhost:13133/ | jq .`
2. Check Prometheus metrics: `curl -s 'http://localhost:9090/api/v1/query?query=up' | jq .`
3. Check Loki logs: `curl -s 'http://localhost:3100/loki/api/v1/labels' | jq .`
4. Verify shell integration: `type claude` should show "claude is a function"

### Shell integration not working

```bash
# Check if function is loaded
type claude

# If it shows a file path instead of a function, re-source:
source ~/.zshrc   # or: source ~/.bashrc

# Or reinstall:
./setup.sh && source ~/.zshrc
```

### Port conflicts

If ports are already in use, stop conflicting services or modify port mappings in `docker-compose.yml`.

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, testing, and guidelines.

## License

This project is licensed under the [MIT License](LICENSE).
