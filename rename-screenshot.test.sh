#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

export SCREENSHOTS_DIR
export ATTEMPTS_FILE
export LOG_FILE
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT
SCREENSHOTS_DIR="$TEST_TMP/screenshots"
ATTEMPTS_FILE="$TEST_TMP/attempts.json"
LOG_FILE="$TEST_TMP/test.log"
mkdir -p "$SCREENSHOTS_DIR"

# shellcheck source=rename-screenshot.sh
source "$SCRIPT_DIR/rename-screenshot.sh"
set +e

FAILS=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (expected '$expected', got '$actual')"
    FAILS=$((FAILS + 1))
  fi
}

echo "--- rename-screenshot.sh test suite ---"

result=$(sanitize_caption "Operate Incident View -- Process Instance Timeline!!")
assert_eq "sanitize_caption basic punctuation+case" "operate-incident-view-process-instance-timeline" "$result"

result=$(sanitize_caption "")
assert_eq "sanitize_caption empty input" "" "$result"

result=$(sanitize_caption "   ...   ")
assert_eq "sanitize_caption only punctuation" "" "$result"

long_input=$(printf 'word%.0s ' {1..30})
result=$(sanitize_caption "$long_input")
result_len=${#result}
if [ "$result_len" -le 60 ] && [[ "$result" != *- ]]; then
  echo "PASS: sanitize_caption caps length and has no trailing hyphen"
else
  echo "FAIL: sanitize_caption length cap (len=$result_len, result='$result')"
  FAILS=$((FAILS + 1))
fi

touch -t 202607101430.22 "$TEST_TMP/timestamp-test.png"
result=$(get_capture_timestamp "$TEST_TMP/timestamp-test.png")
assert_eq "get_capture_timestamp reads mtime" "20260710-143022" "$result"

if is_shottr_screenshot "SCR-20260710-abcd.png"; then
  echo "PASS: is_shottr_screenshot true for raw Shottr name"
else
  echo "FAIL: is_shottr_screenshot true for raw Shottr name"
  FAILS=$((FAILS + 1))
fi

if is_shottr_screenshot "operate-incident-view.png"; then
  echo "FAIL: is_shottr_screenshot false for already-renamed file"
  FAILS=$((FAILS + 1))
else
  echo "PASS: is_shottr_screenshot false for already-renamed file"
fi

if is_shottr_screenshot "random-notes.txt"; then
  echo "FAIL: is_shottr_screenshot false for unrelated file"
  FAILS=$((FAILS + 1))
else
  echo "PASS: is_shottr_screenshot false for unrelated file"
fi

rm -f "$ATTEMPTS_FILE"
result=$(get_attempt_count "SCR-20260710-abcd.png")
assert_eq "get_attempt_count starts at 0" "0" "$result"

increment_attempt "SCR-20260710-abcd.png"
increment_attempt "SCR-20260710-abcd.png"
increment_attempt "SCR-20260710-abcd.png"
result=$(get_attempt_count "SCR-20260710-abcd.png")
assert_eq "increment_attempt three times" "3" "$result"

clear_attempt "SCR-20260710-abcd.png"
result=$(get_attempt_count "SCR-20260710-abcd.png")
assert_eq "clear_attempt resets to 0" "0" "$result"

echo "--- $FAILS failure(s) ---"
[ "$FAILS" -eq 0 ]
