# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it responsibly.

**Do not open a public GitHub issue for security vulnerabilities.**

Instead, please email the maintainer directly or use [GitHub's private vulnerability reporting](https://github.com/Mizune/llm-cli-telemetry/security/advisories/new).

## Scope

This project collects and forwards telemetry data from CLI tools. Security concerns may include:

- Unintended exposure of sensitive data (prompts, API keys, tokens)
- Insecure OTLP endpoint configurations
- Shell injection via environment variables or config files

## Supported Versions

Only the latest version on the `main` branch is supported with security updates.
