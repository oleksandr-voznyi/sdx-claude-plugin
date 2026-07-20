#!/usr/bin/env bash
# Unit tests for stage-write-guard.sh (REQ-DENY-1..4).
# Runs self-contained: creates temporary git repos, exercises the hook, cleans up.
# Style mirrors test-stage-gate.sh (JSON on stdin via run_hook).
# Usage: bash sdx/hooks/test-stage-write-guard.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/stage-write-guard.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# Global temp dir for each test; cleaned up by cleanup().
TMPPROJ=""

# setup_sdx_repo <branch-name> <stage>
#   Creates a temp git repo on the given branch. If <stage> is non-empty, also
#   creates .claude/sessions/<sid>/session_state.json with that stage. If <stage>
#   is empty, no session_state.json is created (used by the "creation" scenario).
setup_sdx_repo() {
  local branch="$1"
  local stage="$2"
  TMPPROJ="$(mktemp -d)"
  git -C "$TMPPROJ" init -q
  git -C "$TMPPROJ" config user.email "test@test.com"
  git -C "$TMPPROJ" config user.name "Test"
  git -C "$TMPPROJ" commit -q --allow-empty -m "init"
  # Ensure branch is called 'main' regardless of system default.
  git -C "$TMPPROJ" branch -M main 2>/dev/null || true

  case "$branch" in
    sdx/*)
      local sid="${branch#sdx/}"
      git -C "$TMPPROJ" checkout -q -b "$branch"
      mkdir -p "$TMPPROJ/.claude/sessions/$sid"
      if [ -n "$stage" ]; then
        printf '{"stage":"%s"}' "$stage" > "$TMPPROJ/.claude/sessions/$sid/session_state.json"
      fi
      ;;
    *)
      # Stay on default (main) branch; no session state created.
      ;;
  esac
}

cleanup() {
  [ -n "$TMPPROJ" ] && rm -rf "$TMPPROJ"
  TMPPROJ=""
}

# run_hook <json-stdin>
#   Pipe json to the hook with CLAUDE_PROJECT_DIR set to TMPPROJ.
run_hook() {
  printf '%s' "$1" | CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK"
}

# run_hook_nojq <json-stdin> <stderr-file>
#   Same, but with a PATH that has every tool the hook needs EXCEPT jq (mirrors
#   the NOJQ_BIN pattern already used by test-prod-guard.sh scenario 5/6/7).
#   Uses `type -P` (not `command -v`) to resolve real binaries: some sandboxed
#   shells define a `grep` shell function shadowing /usr/bin/grep, which would
#   otherwise produce a broken self-referential symlink here.
#   NOTE: writes stderr to the caller-supplied <stderr-file> rather than setting
#   a variable, because callers invoke this via `out="$(run_hook_nojq ...)"` —
#   command substitution runs the function in a subshell, so any variable it
#   sets is invisible to the caller once the subshell exits; a file survives.
run_hook_nojq() {
  local NOJQ_BIN
  NOJQ_BIN="$(mktemp -d)"
  for t in bash cat grep sed head printf git dirname mkdir rm; do
    src="$(type -P "$t" 2>/dev/null)" && ln -s "$src" "$NOJQ_BIN/$t" 2>/dev/null || true
  done
  printf '%s' "$1" | PATH="$NOJQ_BIN" CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK" 2>"$2"
  rm -rf "$NOJQ_BIN"
}

echo "=== test-stage-write-guard.sh ==="
echo ""

STATE_REL=".claude/sessions/test-swg/session_state.json"

# ---- Scenario 1: Edit changes "stage" -> deny ----
echo "[1] Edit changes \"stage\" value -> deny"
setup_sdx_repo "sdx/test-swg" "Execution"
NEW_STRING='{"stage":"Documentation"}'
out="$(run_hook "$(jq -cn --arg fp "$TMPPROJ/$STATE_REL" --arg ns "$NEW_STRING" '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"{\"stage\":\"Execution\"}",new_string:$ns}}')")"
ec=$?
if [ "$ec" -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then
  pass "deny JSON, exit 0"
else
  fail "Expected deny JSON + exit 0" "ec=$ec out=$out"
fi
cleanup

# ---- Scenario 2: Write with full content, .stage differs -> deny ----
echo "[2] Write with changed .stage -> deny"
setup_sdx_repo "sdx/test-swg" "Execution"
CONTENT='{"session_id":"test-swg","stage":"Documentation","track":"full"}'
out="$(run_hook "$(jq -cn --arg fp "$TMPPROJ/$STATE_REL" --arg c "$CONTENT" '{tool_name:"Write",tool_input:{file_path:$fp,content:$c}}')")"
ec=$?
if [ "$ec" -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then
  pass "deny JSON, exit 0"
else
  fail "Expected deny JSON + exit 0" "ec=$ec out=$out"
fi
cleanup

# ---- Scenario 3: Edit/Write touching only track/gate_mode/artifacts/history -> pass ----
echo "[3a] Edit changing only 'track' -> pass"
setup_sdx_repo "sdx/test-swg" "Execution"
out="$(run_hook "$(jq -cn --arg fp "$TMPPROJ/$STATE_REL" '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"\"track\":\"full\"",new_string:"\"track\":\"standard\""}}')")"
ec=$?
if [ "$ec" -eq 0 ] && [ -z "$out" ]; then
  pass "stdout empty, exit 0"
else
  fail "Expected empty stdout + exit 0" "ec=$ec out='$out'"
fi
cleanup

echo "[3b] Write changing content but .stage unchanged -> pass"
setup_sdx_repo "sdx/test-swg" "Execution"
CONTENT='{"session_id":"test-swg","stage":"Execution","track":"full","gate_mode":"auto","artifacts":["DESIGN.md"],"history":[]}'
out="$(run_hook "$(jq -cn --arg fp "$TMPPROJ/$STATE_REL" --arg c "$CONTENT" '{tool_name:"Write",tool_input:{file_path:$fp,content:$c}}')")"
ec=$?
if [ "$ec" -eq 0 ] && [ -z "$out" ]; then
  pass "stdout empty, exit 0"
else
  fail "Expected empty stdout + exit 0" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 4: Write creating a not-yet-existing session_state.json -> pass (carve-out) ----
echo "[4] Write creating session_state.json that does not exist yet -> pass (REQ-DENY-2)"
setup_sdx_repo "sdx/test-swg" ""   # no session_state.json created
CONTENT='{"session_id":"test-swg","stage":"Discovery","track":"full","gate_mode":"interactive","artifacts":[],"history":[]}'
out="$(run_hook "$(jq -cn --arg fp "$TMPPROJ/$STATE_REL" --arg c "$CONTENT" '{tool_name:"Write",tool_input:{file_path:$fp,content:$c}}')")"
ec=$?
if [ "$ec" -eq 0 ] && [ -z "$out" ]; then
  pass "stdout empty, exit 0 (creation not blocked)"
else
  fail "Expected empty stdout + exit 0" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 5: outside sdx/* branch (on main) -> pass ----
echo "[5] Edit changing 'stage' outside SDX branch (on main) -> pass"
setup_sdx_repo "main" ""
out="$(run_hook "$(jq -cn --arg fp "$TMPPROJ/$STATE_REL" '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"a",new_string:"{\"stage\":\"Documentation\"}"}}')")"
ec=$?
if [ "$ec" -eq 0 ] && [ -z "$out" ]; then
  pass "stdout empty, exit 0 (not an SDX branch)"
else
  fail "Expected empty stdout + exit 0" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 6: session_state.json at a DIFFERENT path -> pass (exact-path match) ----
echo "[6] session_state.json at a different path (docs/session_state.json) -> pass"
setup_sdx_repo "sdx/test-swg" "Execution"
out="$(run_hook "$(jq -cn --arg fp "$TMPPROJ/docs/session_state.json" '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"a",new_string:"{\"stage\":\"Documentation\"}"}}')")"
ec=$?
if [ "$ec" -eq 0 ] && [ -z "$out" ]; then
  pass "stdout empty, exit 0 (path matched by basename only, not full path)"
else
  fail "Expected empty stdout + exit 0" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 7: MultiEdit, one edit's new_string contains "stage": -> deny for whole batch ----
echo "[7] MultiEdit — one of several edits touches \"stage\": -> deny whole batch"
setup_sdx_repo "sdx/test-swg" "Execution"
INPUT="$(jq -cn --arg fp "$TMPPROJ/$STATE_REL" '
  {tool_name:"MultiEdit",tool_input:{file_path:$fp,edits:[
    {old_string:"\"track\":\"full\"",new_string:"\"track\":\"standard\""},
    {old_string:"\"stage\":\"Execution\"",new_string:"\"stage\":\"Documentation\""}
  ]}}')"
out="$(run_hook "$INPUT")"
ec=$?
if [ "$ec" -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then
  pass "deny JSON, exit 0 (whole MultiEdit batch blocked)"
else
  fail "Expected deny JSON + exit 0" "ec=$ec out=$out"
fi
cleanup

# ---- Scenario 8: jq missing, operation actually edits stage of an existing session ----
echo "[8] jq absent from PATH, real stage edit -> pass (exit 0) + stderr warning, NOT deny (REQ-DENY-4)"
setup_sdx_repo "sdx/test-swg" "Execution"
INPUT="$(jq -cn --arg fp "$TMPPROJ/$STATE_REL" '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"a",new_string:"{\"stage\":\"Documentation\"}"}}')"
STDERR_FILE="$(mktemp)"
out="$(run_hook_nojq "$INPUT" "$STDERR_FILE")"
ec=$?
RUN_STDERR="$(cat "$STDERR_FILE" 2>/dev/null || true)"
rm -f "$STDERR_FILE"
if [ "$ec" -eq 0 ] && [ -z "$out" ] && printf '%s' "$RUN_STDERR" | grep -qi "jq"; then
  pass "exit 0, no deny JSON, stderr warns about missing jq (fail-open)"
else
  fail "Expected exit 0 + empty stdout + jq warning on stderr" "ec=$ec out='$out' stderr='$RUN_STDERR'"
fi
cleanup

# ---- Scenario 9: Edit touching a "stage" mention that is NOT the actual stage key ----
# Documented, accepted false positive (DESIGN.md "Deny-хук stage-write-guard.sh" ->
# "Ложноположительные случаи": pure whitespace reformatting around the real
# `"stage": "Execution"` key/value, without changing the value, still matches the
# key-only regex and is blocked as a contract, not a bug — see DESIGN.md.
echo "[9] Edit reformats whitespace around \"stage\" without changing its value -> deny (documented false positive, not a bug — see DESIGN.md)"
setup_sdx_repo "sdx/test-swg" "Execution"
INPUT="$(jq -cn --arg fp "$TMPPROJ/$STATE_REL" '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"\"stage\":\"Execution\"","new_string":"\"stage\" :  \"Execution\""}}')"
out="$(run_hook "$INPUT")"
ec=$?
if [ "$ec" -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then
  pass "deny JSON, exit 0 (accepted false positive per DESIGN.md)"
else
  fail "Expected deny JSON + exit 0" "ec=$ec out=$out"
fi
cleanup

# ---- Scenario 10: Windows backslash path -> guard still fires (BUG-006 pattern) ----
echo "[10] Backslash (Windows-style) path to session_state.json -> deny same as forward-slash"
setup_sdx_repo "sdx/test-swg" "Execution"
winpath="$(printf '%s' "$TMPPROJ/$STATE_REL" | tr '/' '\\')"
INPUT="$(jq -cn --arg fp "$winpath" '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"a",new_string:"{\"stage\":\"Documentation\"}"}}')"
out="$(run_hook "$INPUT")"
ec=$?
if [ "$ec" -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then
  pass "deny JSON, exit 0 (backslash path normalized before matching)"
else
  fail "Expected deny JSON + exit 0" "ec=$ec out=$out"
fi
cleanup

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "ALL PASSED"
  exit 0
else
  exit 1
fi
