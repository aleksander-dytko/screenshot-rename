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

resolve_final_name() {
  local dir="$1" base="$2" ext="$3" timestamp="$4"
  local candidate="$dir/$base.$ext"
  if [ ! -e "$candidate" ]; then
    printf '%s' "$base.$ext"
    return
  fi
  printf '%s' "$base-$timestamp.$ext"
}

get_caption() {
  local file="$1"
  local prompt="Generate a short descriptive filename slug (lowercase words separated by hyphens, no extension, max 8 words) for what is shown in this screenshot, and respond with ONLY the slug and no other text: ${file}"
  "${CLAUDE_BIN:-claude}" -p "$prompt" --model claude-haiku-4-5 --output-format text --max-turns 3
}

process_screenshot() {
  local dir="$1" filename="$2"
  local filepath="$dir/$filename"

  local attempts
  attempts=$(get_attempt_count "$filename")
  if [ "$attempts" -ge 3 ]; then
    log_line "GIVEUP $filename (3 failed attempts, needs manual look)"
    return 0
  fi

  local raw_caption
  if ! raw_caption=$(get_caption "$filepath" 2>>"$LOG_FILE"); then
    increment_attempt "$filename"
    log_line "FAIL $filename (claude call failed, attempt $((attempts + 1)))"
    return 1
  fi

  local slug
  slug=$(sanitize_caption "$raw_caption")
  if [ -z "$slug" ]; then
    increment_attempt "$filename"
    log_line "FAIL $filename (caption sanitized to empty, attempt $((attempts + 1)))"
    return 1
  fi

  local ext="${filename##*.}"
  ext=$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')
  local timestamp
  timestamp=$(get_capture_timestamp "$filepath")
  local final_name
  final_name=$(resolve_final_name "$dir" "$slug" "$ext" "$timestamp")

  if ! mv "$filepath" "$dir/$final_name"; then
    increment_attempt "$filename"
    log_line "FAIL $filename (rename failed, attempt $((attempts + 1)))"
    return 1
  fi
  clear_attempt "$filename"
  log_line "OK $filename -> $final_name"
}

main() {
  mkdir -p "$SCREENSHOTS_DIR"
  local f name
  for f in "$SCREENSHOTS_DIR"/*; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    if is_shottr_screenshot "$name"; then
      process_screenshot "$SCREENSHOTS_DIR" "$name" || true
    fi
  done
}

# Only run main when executed directly, not when sourced by the test harness
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
