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

# (assertions added in later tasks go here)

echo "--- $FAILS failure(s) ---"
[ "$FAILS" -eq 0 ]
