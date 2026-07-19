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

get_capture_timestamp() {
  local file="$1"
  stat -f "%Sm" -t "%Y%m%d-%H%M%S" "$file"
}

is_shottr_screenshot() {
  local name
  name=$(basename "$1")
  [[ "$name" =~ ^SCR-[0-9]{8}-[a-zA-Z]{4}\.(png|jpg|jpeg)$ ]]
}

ensure_attempts_file() {
  mkdir -p "$(dirname "$ATTEMPTS_FILE")"
  [ -f "$ATTEMPTS_FILE" ] || echo '{}' > "$ATTEMPTS_FILE"
}

get_attempt_count() {
  local name="$1"
  ensure_attempts_file
  jq -r --arg k "$name" '.[$k] // 0' "$ATTEMPTS_FILE"
}

increment_attempt() {
  local name="$1"
  ensure_attempts_file
  local tmp
  tmp=$(mktemp)
  jq --arg k "$name" '.[$k] = ((.[$k] // 0) + 1)' "$ATTEMPTS_FILE" > "$tmp" && mv "$tmp" "$ATTEMPTS_FILE"
}

clear_attempt() {
  local name="$1"
  ensure_attempts_file
  local tmp
  tmp=$(mktemp)
  jq --arg k "$name" 'del(.[$k])' "$ATTEMPTS_FILE" > "$tmp" && mv "$tmp" "$ATTEMPTS_FILE"
}

# Only run main when executed directly, not when sourced by the test harness
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
