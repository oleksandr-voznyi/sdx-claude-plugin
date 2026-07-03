#!/usr/bin/env bash
# Unit tests for stage-gate.sh (REQ-GATE-1).
# Runs self-contained: creates temporary git repos, exercises the hook, cleans up.
# Usage: bash .claude/sdx/hooks/test-stage-gate.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/stage-gate.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# Global temp dir for each test; cleaned up by cleanup().
TMPPROJ=""

# setup_sdx_repo <branch-name> <stage>
#   Creates a temp git repo on the given branch with session_state.json.
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
      printf '{"stage":"%s"}' "$stage" > "$TMPPROJ/.claude/sessions/$sid/session_state.json"
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
#   NOTE: env assignment must prefix the bash invocation (the second cmd in the pipe),
#   not the printf — otherwise the variable is only visible to printf, not bash.
run_hook() {
  printf '%s' "$1" | CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK"
}

echo "=== test-stage-gate.sh ==="
echo ""

# ---- Scenario 1: block code write outside Execution ----
echo "[1] Block code write outside Execution (stage=Task Planning)"
setup_sdx_repo "sdx/test-sg" "Task Planning"
out="$(run_hook "{\"tool_input\":{\"file_path\":\"$TMPPROJ/src/app.js\"}}")"
ec=$?
if [ "$ec" -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then
  pass "stdout contains permissionDecision:deny, exit 0"
else
  fail "Expected deny JSON + exit 0" "ec=$ec out=$out"
fi
cleanup

# ---- Scenario 2: allow .md file outside Execution ----
echo "[2] Allow .md file (docs/PLAN.md) outside Execution"
setup_sdx_repo "sdx/test-sg" "Task Planning"
out="$(run_hook "{\"tool_input\":{\"file_path\":\"$TMPPROJ/docs/PLAN.md\"}}")"
ec=$?
if [ "$ec" -eq 0 ] && [ -z "$out" ]; then
  pass "stdout empty, exit 0"
else
  fail "Expected empty stdout + exit 0" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 3: allow .claude/ file outside Execution ----
echo "[3] Allow .claude/ file (.claude/settings.json) outside Execution"
setup_sdx_repo "sdx/test-sg" "Task Planning"
out="$(run_hook "{\"tool_input\":{\"file_path\":\"$TMPPROJ/.claude/settings.json\"}}")"
ec=$?
if [ "$ec" -eq 0 ] && [ -z "$out" ]; then
  pass "stdout empty, exit 0"
else
  fail "Expected empty stdout + exit 0" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 4: transparent outside SDX branch (main) ----
echo "[4] Transparent outside SDX branch (on main)"
setup_sdx_repo "main" ""
out="$(run_hook "{\"tool_input\":{\"file_path\":\"$TMPPROJ/src/app.js\"}}")"
ec=$?
if [ "$ec" -eq 0 ] && [ -z "$out" ]; then
  pass "stdout empty, exit 0"
else
  fail "Expected empty stdout + exit 0" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 5: allow code write on Execution stage ----
echo "[5] Allow code write when stage=Execution"
setup_sdx_repo "sdx/test-sg" "Execution"
out="$(run_hook "{\"tool_input\":{\"file_path\":\"$TMPPROJ/src/app.js\"}}")"
ec=$?
if [ "$ec" -eq 0 ] && [ -z "$out" ]; then
  pass "stdout empty, exit 0"
else
  fail "Expected empty stdout + exit 0" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 6: stage-gate.allow extends allow-list ----
echo "[6] stage-gate.allow extends allow-list (database/migrations/*)"
setup_sdx_repo "sdx/test-sg" "Task Planning"
mkdir -p "$TMPPROJ/.claude/sdx"
printf '# test allowlist\ndatabase/migrations/*\n' > "$TMPPROJ/.claude/sdx/stage-gate.allow"
out="$(run_hook "{\"tool_input\":{\"file_path\":\"$TMPPROJ/database/migrations/001.sql\"}}")"
ec=$?
if [ "$ec" -eq 0 ] && [ -z "$out" ]; then
  pass "stdout empty, exit 0 (path matched allowlist)"
else
  fail "Expected empty stdout + exit 0" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 7: allow test path on Verification (A1) ----
echo "[7] Allow test path (tests/api.test.js) when stage=Verification"
setup_sdx_repo "sdx/test-sg" "Verification"
out="$(run_hook "{\"tool_input\":{\"file_path\":\"$TMPPROJ/tests/api.test.js\"}}")"
ec=$?
if [ "$ec" -eq 0 ] && [ -z "$out" ]; then
  pass "stdout empty, exit 0 (qa writes integration tests on Verification)"
else
  fail "Expected empty stdout + exit 0" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 8: still block non-test code on Verification (A1 boundary) ----
echo "[8] Block non-test code (src/app.js) when stage=Verification"
setup_sdx_repo "sdx/test-sg" "Verification"
out="$(run_hook "{\"tool_input\":{\"file_path\":\"$TMPPROJ/src/app.js\"}}")"
ec=$?
if [ "$ec" -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then
  pass "deny JSON + exit 0 (code frozen; fixes via /sdx:backtrack --to Execution)"
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
