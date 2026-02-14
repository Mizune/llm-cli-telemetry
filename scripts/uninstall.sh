#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

# --- Remove shell RC integration ---
remove_shell_rc() {
  for rc_file in "${HOME}/.zshrc" "${HOME}/.bashrc"; do
    if [[ ! -f "${rc_file}" ]]; then
      continue
    fi

    if ! grep -q "${MARKER_BEGIN}" "${rc_file}" 2>/dev/null; then
      continue
    fi

    local tmp
    tmp=$(mktemp)
    # Remove everything between markers (inclusive)
    awk -v begin="${MARKER_BEGIN}" -v end="${MARKER_END}" '
      $0 == begin { skip=1; next }
      $0 == end   { skip=0; next }
      !skip
    ' "${rc_file}" > "${tmp}"

    # Remove trailing blank lines left by marker removal
    strip_trailing_blank_lines "${tmp}"

    mv "${tmp}" "${rc_file}"
    info "Removed shell integration from ${rc_file}"
  done
}

# --- Restore Codex config ---
restore_codex() {
  local config="${HOME}/.codex/config.toml"
  local backup="${config}.bak"

  if [[ -f "${backup}" ]]; then
    mv "${backup}" "${config}"
    info "Restored Codex config from ${backup}"
  elif [[ -f "${config}" ]] && grep -q '\[otel\]' "${config}" 2>/dev/null; then
    warn "Codex config has [otel] section but no backup found"
    warn "Manually remove the [otel] section from ${config}"
  fi
}

# --- Restore Gemini config ---
restore_gemini() {
  local config="${HOME}/.gemini/settings.json"
  local backup="${config}.bak"

  if [[ -f "${backup}" ]]; then
    mv "${backup}" "${config}"
    info "Restored Gemini config from ${backup}"
  elif [[ -f "${config}" ]] && grep -q '"telemetry"' "${config}" 2>/dev/null; then
    if command -v jq &>/dev/null; then
      local tmp
      tmp=$(mktemp)
      jq 'del(.telemetry)' "${config}" > "${tmp}" && mv "${tmp}" "${config}"
      info "Removed telemetry section from ${config}"
    else
      warn "jq not found; manually remove 'telemetry' from ${config}"
    fi
  fi
}

# --- Remove .setup-mode ---
remove_setup_mode() {
  if [[ -f "${SETUP_MODE_FILE}" ]]; then
    rm "${SETUP_MODE_FILE}"
    info "Removed .setup-mode"
  fi
}

# --- Main ---
main() {
  info "Uninstalling llm-cli-telemetry..."
  echo ""

  remove_shell_rc
  restore_codex
  restore_gemini
  remove_setup_mode

  echo ""
  info "Uninstall complete!"
  info "Open a new terminal for changes to take effect."
  info ""
  info "Note: telemetry.yaml and docker-compose.override.yml were not removed."
  info "Run './stop.sh --clean' to also remove Docker volumes."
}

main "$@"
