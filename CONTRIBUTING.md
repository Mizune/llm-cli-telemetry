# Contributing

Thank you for your interest in contributing to llm-cli-telemetry!

## Prerequisites

- **Bash** 4.0+ (macOS ships Bash 3; install via `brew install bash`)
- **Docker** & **Docker Compose** (for local mode)
- **yq** (`brew install yq` / `apt install yq`) - for `generate.sh`
- **jq** (`brew install jq` / `apt install jq`) - for Gemini config
- **bats-core** (`brew install bats-core`) - for running tests
- **ShellCheck** (`brew install shellcheck`) - for linting

## Development Setup

```bash
git clone https://github.com/<your-username>/llm-cli-telemetry.git
cd llm-cli-telemetry

# Copy config templates
cp .env.example .env
cp telemetry.example.yaml telemetry.yaml

# Run the setup wizard
./setup.sh
```

## Running Tests

```bash
# All tests
make test

# bats-core tests only (101 tests)
make test-bats

# Legacy integration tests only
make test-legacy

# Lint shell scripts
shellcheck -x -S warning scripts/*.sh setup.sh start.sh stop.sh status.sh uninstall.sh
```

All tests must pass before submitting a PR.

## Project Structure

| Directory | Description |
|-----------|-------------|
| `scripts/` | Core shell scripts (lib, install, uninstall, generate, shell-integration) |
| `tests/` | bats-core tests and legacy integration tests |
| `tests/helpers/` | Shared test setup, fixtures, and mock utilities |
| `tests/fixtures/` | Test fixture files (YAML, TOML, JSON) |
| `otel-collector/` | OTEL Collector config (auto-generated) |
| `grafana/` | Grafana provisioning and dashboards |

## Making Changes

1. **Fork** the repository and create a feature branch
2. **Write tests first** for new functionality (see `tests/*.bats`)
3. **Make your changes** following the existing code style
4. **Run tests** and **ShellCheck** to verify
5. **Commit** with a descriptive message (see below)
6. **Open a Pull Request** against `main`

## Code Style

- Use `set -euo pipefail` at the top of executable scripts
- Use `local` for function-scoped variables
- Quote all variable expansions: `"${var}"`
- Use `info`, `warn`, `error` functions from `lib.sh` for output
- Keep functions focused (one responsibility each)

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/) format:

```
type: short description

Optional longer description.
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `ci`

Examples:
- `feat: add support for custom OTEL headers`
- `fix: handle missing .setup-mode gracefully`
- `test: add shell-integration tests for disabled mode`
- `docs: update environment variable reference`

## Reporting Issues

- Use the **Bug Report** template for bugs
- Use the **Feature Request** template for enhancements
- Include steps to reproduce, expected vs. actual behavior, and your environment (OS, shell, Docker version)
