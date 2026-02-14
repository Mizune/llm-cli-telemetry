# Telemetry Data Reference

Complete reference of telemetry data available from each CLI tool.

## OTEL Data (automatic)

Data emitted directly by CLI tools through OpenTelemetry instrumentation. Collected automatically when shell functions are active.

### Claude Code

**Activation**: `CLAUDE_CODE_ENABLE_TELEMETRY=1` + OTEL env vars (set by shell function)
**Enhancement**: `OTEL_LOG_USER_PROMPTS=1`, `OTEL_LOG_TOOL_DETAILS=1`

| Type | Name | Description |
|------|------|-------------|
| Metric | `token_usage` | Token consumption (input/output/cache read/cache write) |
| Metric | `cost_usage` | Estimated cost in USD |
| Metric | `session_count` | Number of sessions started |
| Metric | `lines_of_code` | Lines of code written/modified |
| Metric | `pull_request` | Pull requests created |
| Metric | `commit` | Commits created |
| Metric | `code_edit_tool` | Code edit tool invocations |
| Metric | `active_time` | Active session time |
| Event | `user_prompt` | Full prompt text (requires `OTEL_LOG_USER_PROMPTS=1`) |
| Event | `tool_result` | Tool execution results (requires `OTEL_LOG_TOOL_DETAILS=1`) |
| Event | `api_request` | API call details |
| Event | `api_error` | API error details |
| Event | `tool_decision` | Tool selection decisions |

### Codex CLI

**Activation**: `[otel]` section in `~/.codex/config.toml` (set by `make install`)
**Enhancement**: `log_user_prompt = true` in config

| Type | Name | Description |
|------|------|-------------|
| Metric | `feature.state` | Feature flag states |
| Metric | `approval.requested` | User approval requests |
| Metric | `tool.call` | Tool call counts |
| Metric | `conversation.turn.count` | Conversation turns |
| Metric | `shell_snapshot` | Shell state snapshots |
| Event | `conversation_starts` | Session start events |
| Event | `api_request` | API call details |
| Event | `sse_event` | Server-sent event data |
| Event | `user_prompt` | Prompt text (requires `log_user_prompt = true`) |
| Event | `tool_decision` | Tool selection |
| Event | `tool_result` | Tool execution results |

### Gemini CLI

**Activation**: Telemetry section in `~/.gemini/settings.json` (set by `make install`)
**Enhancement**: `"logPrompts": true` in settings

| Type | Name | Description |
|------|------|-------------|
| Metric | `agent.run.count` | Agent execution count |
| Metric | `plan.execution.count` | Plan execution count |
| Metric | `startup.duration` | CLI startup time |
| Metric | `gen_ai.client.token.usage` | Token usage (GenAI semantic conventions) |
| Metric | `gen_ai.client.operation.duration` | Operation duration |
| Event | (40+ types) | Tool execution, file operations, API calls, model routing, etc. |

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
