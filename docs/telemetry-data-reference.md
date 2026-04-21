# Telemetry Data Reference

Complete reference of telemetry data available from each CLI tool.

## OTEL Data (automatic)

Data emitted directly by CLI tools through OpenTelemetry instrumentation. Collected automatically when shell functions are active.

### Claude Code

**Activation**: `CLAUDE_CODE_ENABLE_TELEMETRY=1` + OTEL env vars (set by shell function)
**Enhancement**: `OTEL_LOG_USER_PROMPTS=1`, `OTEL_LOG_TOOL_DETAILS=1`, `OTEL_LOG_RAW_API_BODIES=1` (v2.1.111+)
**Tracing (beta)**: `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1` + `OTEL_TRACES_EXPORTER=otlp`

| Type | Name | Description | Key Attributes |
|------|------|-------------|----------------|
| Metric | `claude_code.token.usage` | Token consumption | `type` (input/output/cacheRead/cacheCreation), `model` |
| Metric | `claude_code.cost.usage` | Estimated cost in USD | `model` |
| Metric | `claude_code.session.count` | Sessions started | |
| Metric | `claude_code.lines_of_code.count` | Lines of code written/modified | `type` (added/removed) |
| Metric | `claude_code.pull_request.count` | Pull requests created | |
| Metric | `claude_code.commit.count` | Commits created | |
| Metric | `claude_code.code_edit_tool.decision` | Code edit tool invocations | `tool_name`, `decision`, `language` |
| Metric | `claude_code.active_time.total` | Active session time (seconds) | `type` (user/cli) |
| Event | `claude_code.user_prompt` | Full prompt text (requires `OTEL_LOG_USER_PROMPTS=1`) | |
| Event | `claude_code.tool_result` | Tool execution results (requires `OTEL_LOG_TOOL_DETAILS=1`) | |
| Event | `claude_code.api_request` | API call details | |
| Event | `claude_code.api_error` | API error details (terminal, after retries) | |
| Event | `claude_code.api_request_body` | Full API request JSON (requires `OTEL_LOG_RAW_API_BODIES=1`) | |
| Event | `claude_code.api_response_body` | Full API response JSON (requires `OTEL_LOG_RAW_API_BODIES=1`) | |
| Event | `claude_code.tool_decision` | Tool permission accept/reject | |
| Event | `claude_code.plugin_installed` | Plugin installation | |
| Event | `claude_code.skill_activated` | Skill invocation | |

**Prometheus metric names** (dots → underscores, unit suffix appended):
- `claude_code_token_usage_tokens_total`
- `claude_code_cost_usage_USD_total`
- `claude_code_session_count_total`
- `claude_code_lines_of_code_total`
- `claude_code_pull_request_total`
- `claude_code_commit_total`
- `claude_code_code_edit_tool_total`
- `claude_code_active_time_seconds_total`

**Additional env vars**:
- `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE` – defaults to `delta`; collector's `deltatocumulative` processor handles conversion
- `OTEL_METRICS_INCLUDE_SESSION_ID` (default: true), `OTEL_METRICS_INCLUDE_VERSION` (default: false) – cardinality control
- `OTEL_METRIC_EXPORT_INTERVAL` – metrics batch interval (ms, default: 60000)

### Codex CLI

**Activation**: `[otel]` section in `~/.codex/config.toml` (set by `setup.sh`)
**Enhancement**: `log_user_prompt = true` in config
**Service name**: `codex_cli_rs` (interactive CLI) or `codex_exec` (exec mode)

> **Note**: Some names (e.g. `codex.api_request`, `codex.sse_event`) appear as both a metric (counter) and an event (log). The metric tracks counts; the event carries detailed per-call attributes.

| Type | Name | Description |
|------|------|-------------|
| Metric | `codex.tool.call` | Tool call counts |
| Metric | `codex.tool.call.duration_ms` | Tool call duration (histogram) |
| Metric | `codex.api_request` | API call counts (counter) |
| Metric | `codex.api_request.duration_ms` | API call duration (histogram) |
| Metric | `codex.turn.e2e_duration_ms` | Turn end-to-end duration (histogram) |
| Metric | `codex.turn.ttft.duration_ms` | Turn time-to-first-token (histogram) |
| Metric | `codex.turn.ttfm.duration_ms` | Turn time-to-first-message (histogram) |
| Metric | `codex.turn.token_usage` | Turn-level token usage |
| Metric | `codex.turn.tool.call` | Turn-level tool calls |
| Metric | `codex.sse_event` | SSE event counts |
| Metric | `codex.sse_event.duration_ms` | SSE event duration (histogram) |
| Metric | `codex.websocket.request` | WebSocket request counts |
| Metric | `codex.websocket.event` | WebSocket event counts |
| Metric | `codex.hooks.run` | Hook execution count |
| Metric | `codex.hooks.run.duration_ms` | Hook execution duration (histogram) |
| Metric | `codex.plugins.startup_sync` | Plugin startup sync count |
| Metric | `codex.thread.skills.enabled_total` | Skills enabled per thread |
| Metric | `codex.thread.skills.kept_total` | Skills kept per thread |
| Metric | `codex.thread.skills.truncated` | Skills truncated per thread |
| Metric | `codex.startup_prewarm.duration_ms` | Startup prewarm duration (histogram) |
| Event | `codex.conversation_starts` | Session start with model/sandbox config |
| Event | `codex.api_request` | API call with status/duration (log event) |
| Event | `codex.sse_event` | SSE stream events with token counts |
| Event | `codex.websocket_connect` | WebSocket connection events |
| Event | `codex.websocket_request` | WebSocket request events |
| Event | `codex.websocket_event` | WebSocket message events |
| Event | `codex.user_prompt` | User input (redacted by default) |
| Event | `codex.tool_decision` | Tool approval decisions |
| Event | `codex.tool_result` | Tool execution results |

**Prometheus metric names** (dots → underscores):
- `codex_tool_call_total`
- `codex_tool_call_duration_ms_bucket`
- `codex_api_request_total`
- `codex_api_request_duration_ms_bucket`
- `codex_turn_e2e_duration_ms_bucket`
- `codex_turn_ttft_duration_ms_bucket`
- `codex_turn_token_usage_total`
- `codex_hooks_run_total`
- `codex_plugins_startup_sync_total`
- `codex_thread_skills_enabled_total_total` — double `_total` is expected: OTEL metric `codex.thread.skills.enabled_total` already ends in `_total`, then Prometheus appends another `_total` for counters

**Config format** (`~/.codex/config.toml`):
```toml
[otel]
environment = "local"
log_user_prompt = false
metrics_exporter = "otlp-grpc"  # Required for metrics to flow to user collector

[otel.exporter."otlp-grpc"]
endpoint = "http://localhost:4317"
protocol = "binary"

[otel.trace_exporter."otlp-grpc"]
endpoint = "http://localhost:4317"
protocol = "binary"

[otel.metrics_exporter."otlp-grpc"]
endpoint = "http://localhost:4317"
protocol = "binary"
```

> **Important**: Without `metrics_exporter`, Codex defaults to sending metrics to Statsig (OpenAI internal). The `metrics_exporter` field must be explicitly set to route metrics to the user's collector.

### Gemini CLI

**Activation**: Telemetry section in `~/.gemini/settings.json` + `GEMINI_TELEMETRY_*` env vars (set by shell function)
**Enhancement**: `"logPrompts": true` in settings or `GEMINI_TELEMETRY_LOG_PROMPTS=true`

#### GenAI Semantic Convention Metrics

| Type | Name | Description |
|------|------|-------------|
| Metric | `gen_ai.client.token.usage` | Token usage (GenAI semantic conventions) |
| Metric | `gen_ai.client.operation.duration` | Operation duration (histogram, seconds) |

#### Custom Gemini CLI Metrics

| Type | Name | Description |
|------|------|-------------|
| Metric | `gemini_cli.session.count` | Session count |
| Metric | `gemini_cli.agent.run.count` | Agent execution count |
| Metric | `gemini_cli.agent.duration` | Agent execution duration (histogram) |
| Metric | `gemini_cli.agent.turns` | Agent turn count |
| Metric | `gemini_cli.plan.execution.count` | Plan execution count |
| Metric | `gemini_cli.startup.duration` | CLI startup time (histogram) |
| Metric | `gemini_cli.tool.call.count` | Tool call count |
| Metric | `gemini_cli.tool.call.latency` | Tool call latency (histogram) |
| Metric | `gemini_cli.api.request.count` | API request count |
| Metric | `gemini_cli.api.request.latency` | API request latency (histogram) |
| Metric | `gemini_cli.token.usage` | Token usage (custom) |
| Metric | `gemini_cli.file.operation.count` | File operation count |
| Metric | `gemini_cli.lines.changed` | Lines of code changed |
| Metric | `gemini_cli.memory.usage` | Memory usage (gauge) |
| Metric | `gemini_cli.cpu.usage` | CPU usage (gauge) |
| Metric | `gemini_cli.model_routing.latency` | Model routing latency (histogram) |
| Event | `gemini_cli.user_prompt` | User prompt (requires logPrompts) |
| Event | `gemini_cli.tool_call` | Tool execution events |
| Event | `gemini_cli.api_request` | API call events |
| Event | `gemini_cli.api_error` | API error events |
| Event | `gemini_cli.agent.start` | Agent start events |
| Event | `gemini_cli.agent.finish` | Agent finish events |
| Event | `gemini_cli.extension_install` | Extension installation |
| Event | `gemini_cli.extension_uninstall` | Extension removal |
| Event | `gemini_cli.extension_enable` | Extension enabled |
| Event | `gemini_cli.extension_disable` | Extension disabled |

**Prometheus metric names**:
- `gen_ai_client_token_usage_sum`
- `gen_ai_client_operation_duration_seconds_bucket`
- `gemini_cli_session_count_total`
- `gemini_cli_agent_run_count_total`
- `gemini_cli_tool_call_count_total`
- `gemini_cli_tool_call_latency_bucket`
- `gemini_cli_lines_changed_total`
- `gemini_cli_startup_duration_bucket`
- `gemini_cli_plan_execution_count_total`

## Local Log Collection (optional, opt-in)

Additional data collected from CLI tools' local log files on disk. Enable in `telemetry.yaml` under `local_logs`. Requires `make generate` to regenerate the collector config (or just `make up`, which auto-regenerates).

### Claude Code

**Source**: `~/.claude/metrics/` (mounted read-only)

| Log File | Data | Description |
|----------|------|-------------|
| `history.jsonl` | Conversation history | Full conversation with timestamps |
| `post-tool-debug.log` | Tool debug logs | Includes code diffs from tool executions |
| `current.json` | Context state | Context window consumption (used/remaining %) |

### Codex CLI

**Source**: `~/.codex/` (mounted read-only)

| Log File | Data | Description |
|----------|------|-------------|
| `sessions/**/*.jsonl` | Session data | Full session logs with tool calls and results |
| `history.jsonl` | Prompt history | User prompt history |

**Additional data in session files**:
- Code diffs from tool executions
- Git metadata (commit hashes, branch names, repo URLs)
- Full conversation transcripts

### Gemini CLI

Gemini CLI does not maintain significant local log files. All telemetry is collected through OTEL data above.

## Resource Attributes

All telemetry data includes these resource attributes:

| Attribute | Value | Description |
|-----------|-------|-------------|
| `cli_tool` | `claude-code` / `codex-cli` / `gemini-cli` | Tool identifier |
| `deployment.environment` | Configurable | Environment name |
| `user.email` | Configurable | User email address |
| `user.team` | Configurable | Team identifier |
