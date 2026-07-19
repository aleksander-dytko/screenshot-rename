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

echo "--- $FAILS failure(s) ---"
[ "$FAILS" -eq 0 ]
