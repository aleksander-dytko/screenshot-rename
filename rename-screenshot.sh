#!/usr/bin/env bash
set -euo pipefail

SCREENSHOTS_DIR="${SCREENSHOTS_DIR:-$HOME/Downloads/Screenshots}"
ATTEMPTS_FILE="${ATTEMPTS_FILE:-$HOME/Library/Application Support/screenshot-rename/attempts.json}"
LOG_FILE="${LOG_FILE:-$HOME/Library/Logs/screenshot-rename.log}"

log_line() {
  mkdir -p "$(dirname "$LOG_FILE")"
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
}

sanitize_caption() {
  local raw="$1"
  local s
  s=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')
  s=$(printf '%s' "$s" | sed -E 's/[^a-z0-9]+/-/g')
  s=$(printf '%s' "$s" | sed -E 's/^-+//; s/-+$//')
  s="${s:0:60}"
  s=$(printf '%s' "$s" | sed -E 's/-+$//')
  printf '%s' "$s"
}

# Only run main when executed directly, not when sourced by the test harness
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
