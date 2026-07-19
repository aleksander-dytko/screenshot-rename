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

result=$(resolve_final_name "$SCREENSHOTS_DIR" "no-collision" "png" "20260710-143022")
assert_eq "resolve_final_name no collision" "no-collision.png" "$result"

touch "$SCREENSHOTS_DIR/has-collision.png"
result=$(resolve_final_name "$SCREENSHOTS_DIR" "has-collision" "png" "20260710-143022")
assert_eq "resolve_final_name with collision" "has-collision-20260710-143022.png" "$result"

FAKE_CLAUDE="$TEST_TMP/fake-claude"
cat > "$FAKE_CLAUDE" <<'EOF'
#!/usr/bin/env bash
echo "operate-incident-view-timeline"
EOF
chmod +x "$FAKE_CLAUDE"

result=$(CLAUDE_BIN="$FAKE_CLAUDE" get_caption "$SCREENSHOTS_DIR/does-not-matter.png")
assert_eq "get_caption returns CLI stdout" "operate-incident-view-timeline" "$result"

FAKE_CLAUDE_FAIL="$TEST_TMP/fake-claude-fail"
cat > "$FAKE_CLAUDE_FAIL" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$FAKE_CLAUDE_FAIL"

if CLAUDE_BIN="$FAKE_CLAUDE_FAIL" get_caption "$SCREENSHOTS_DIR/does-not-matter.png" >/dev/null 2>&1; then
  echo "FAIL: get_caption should propagate CLI failure exit code"
  FAILS=$((FAILS + 1))
else
  echo "PASS: get_caption propagates CLI failure exit code"
fi

# Success path
rm -f "$ATTEMPTS_FILE"
touch "$SCREENSHOTS_DIR/SCR-20260710-abcd.png"
touch -t 202607101430.22 "$SCREENSHOTS_DIR/SCR-20260710-abcd.png"
CLAUDE_BIN="$FAKE_CLAUDE" process_screenshot "$SCREENSHOTS_DIR" "SCR-20260710-abcd.png"
if [ -f "$SCREENSHOTS_DIR/operate-incident-view-timeline.png" ]; then
  echo "PASS: process_screenshot renames on success"
else
  echo "FAIL: process_screenshot renames on success"
  FAILS=$((FAILS + 1))
fi

# Failure path: file untouched, attempt count increments
touch "$SCREENSHOTS_DIR/SCR-20260711-wxyz.png"
CLAUDE_BIN="$FAKE_CLAUDE_FAIL" process_screenshot "$SCREENSHOTS_DIR" "SCR-20260711-wxyz.png" || true
if [ -f "$SCREENSHOTS_DIR/SCR-20260711-wxyz.png" ]; then
  echo "PASS: process_screenshot leaves file untouched on CLI failure"
else
  echo "FAIL: process_screenshot leaves file untouched on CLI failure"
  FAILS=$((FAILS + 1))
fi
result=$(get_attempt_count "SCR-20260711-wxyz.png")
assert_eq "process_screenshot increments attempt count on failure" "1" "$result"

# Give-up path: 3rd failure stops retrying (count stays at 3, no crash)
CLAUDE_BIN="$FAKE_CLAUDE_FAIL" process_screenshot "$SCREENSHOTS_DIR" "SCR-20260711-wxyz.png" || true
CLAUDE_BIN="$FAKE_CLAUDE_FAIL" process_screenshot "$SCREENSHOTS_DIR" "SCR-20260711-wxyz.png" || true
CLAUDE_BIN="$FAKE_CLAUDE_FAIL" process_screenshot "$SCREENSHOTS_DIR" "SCR-20260711-wxyz.png" || true
result=$(get_attempt_count "SCR-20260711-wxyz.png")
assert_eq "process_screenshot stops incrementing past 3 attempts" "3" "$result"

# Rename failure path: mv fails due to permission denied
# Create file in SCREENSHOTS_DIR, then make directory read-only so mv fails
rm -f "$ATTEMPTS_FILE"
touch "$SCREENSHOTS_DIR/SCR-20260712-mvfail.png"
touch -t 202607121430.22 "$SCREENSHOTS_DIR/SCR-20260712-mvfail.png"

# Make directory read-only to force mv failure
chmod 555 "$SCREENSHOTS_DIR"

CLAUDE_BIN="$FAKE_CLAUDE" process_screenshot "$SCREENSHOTS_DIR" "SCR-20260712-mvfail.png" || true

# Restore write permission for cleanup
chmod 755 "$SCREENSHOTS_DIR"

# Verify: original file still exists under original name
if [ -f "$SCREENSHOTS_DIR/SCR-20260712-mvfail.png" ]; then
  echo "PASS: process_screenshot leaves file untouched when mv fails"
else
  echo "FAIL: process_screenshot leaves file untouched when mv fails"
  FAILS=$((FAILS + 1))
fi

# Verify: attempt count incremented
result=$(get_attempt_count "SCR-20260712-mvfail.png")
assert_eq "process_screenshot increments attempt on mv failure" "1" "$result"

# Verify: log contains FAIL entry
if grep -q "FAIL SCR-20260712-mvfail.png (rename failed, attempt 1)" "$LOG_FILE"; then
  echo "PASS: process_screenshot logs FAIL when mv fails"
else
  echo "FAIL: process_screenshot logs FAIL when mv fails"
  FAILS=$((FAILS + 1))
fi

echo "--- $FAILS failure(s) ---"
[ "$FAILS" -eq 0 ]
