#!/usr/bin/env bash
# Unit tests for stop-gate.sh (REQ-GATE-2).
# Runs self-contained: creates temporary git repos, exercises the hook, cleans up.
# Usage: bash .claude/sdx/hooks/test-stop-gate.sh
# NOTE: stop-gate reads no stdin; CLAUDE_PROJECT_DIR must prefix the bash invocation.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/stop-gate.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

TMPPROJ=""

# setup_stop_repo <branch-name> <stage>
setup_stop_repo() {
  local branch="$1"
  local stage="$2"
  TMPPROJ="$(mktemp -d)"
  git -C "$TMPPROJ" init -q
  git -C "$TMPPROJ" config user.email "test@test.com"
  git -C "$TMPPROJ" config user.name "Test"
  git -C "$TMPPROJ" commit -q --allow-empty -m "init"
  git -C "$TMPPROJ" branch -M main 2>/dev/null || true

  case "$branch" in
    sdx/*)
      local sid="${branch#sdx/}"
      git -C "$TMPPROJ" checkout -q -b "$branch"
      mkdir -p "$TMPPROJ/.claude/sessions/$sid"
      printf '{"stage":"%s"}' "$stage" > "$TMPPROJ/.claude/sessions/$sid/session_state.json"
      ;;
  esac
}

cleanup() {
  [ -n "$TMPPROJ" ] && rm -rf "$TMPPROJ"
  TMPPROJ=""
}

# run_hook [args...]
#   Invoke stop-gate with CLAUDE_PROJECT_DIR set to TMPPROJ.
#   Returns the exit code in $RUN_EC.
RUN_EC=0
run_hook() {
  RUN_EC=0
  CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK" "$@" >/dev/null 2>/dev/null || RUN_EC=$?
}

echo "=== test-stop-gate.sh ==="
echo ""

# ---- Scenario 1: no-op without test command (meta-project) ----
echo "[1] No-op when no verify-cmd.sh and no autodetect (meta-project)"
setup_stop_repo "sdx/test-stop" "Execution"
# No verify-cmd.sh, no composer.json, package.json, phpunit.xml
run_hook
if [ "$RUN_EC" -eq 0 ]; then
  pass "exit 0 (no-op without test command)"
else
  fail "Expected exit 0" "got exit $RUN_EC"
fi
cleanup

# ---- Scenario 2: transparent outside Execution/Verification ----
echo "[2] Transparent outside Execution/Verification (stage=Task Planning)"
setup_stop_repo "sdx/test-stop" "Task Planning"
run_hook
if [ "$RUN_EC" -eq 0 ]; then
  pass "exit 0 (stage outside enforcement scope)"
else
  fail "Expected exit 0" "got exit $RUN_EC"
fi
cleanup

# ---- Scenario 3: transparent outside SDX branch ----
echo "[3] Transparent outside SDX branch (on main)"
setup_stop_repo "main" ""
run_hook
if [ "$RUN_EC" -eq 0 ]; then
  pass "exit 0 (not an SDX branch)"
else
  fail "Expected exit 0" "got exit $RUN_EC"
fi
cleanup

# ---- Scenario 4: loop-guard releases after 3 red attempts ----
echo "[4] Loop-guard: first 3 runs exit 2, 4th run exit 0"
setup_stop_repo "sdx/test-stop" "Execution"
# Create a verify command that always fails.
mkdir -p "$TMPPROJ/.claude/sdx"
printf '#!/bin/bash\nexit 1\n' > "$TMPPROJ/.claude/sdx/verify-cmd.sh"
chmod +x "$TMPPROJ/.claude/sdx/verify-cmd.sh"

ec1=0; ec2=0; ec3=0; ec4=0
CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK" >/dev/null 2>/dev/null || ec1=$?
CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK" >/dev/null 2>/dev/null || ec2=$?
CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK" >/dev/null 2>/dev/null || ec3=$?
CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK" >/dev/null 2>/dev/null || ec4=$?

if [ "$ec1" -eq 2 ] && [ "$ec2" -eq 2 ] && [ "$ec3" -eq 2 ] && [ "$ec4" -eq 0 ]; then
  pass "runs 1-3 exit 2, run 4 exit 0 (loop-guard fired)"
else
  fail "Loop-guard timing" "ec1=$ec1 ec2=$ec2 ec3=$ec3 ec4=$ec4 (expected 2,2,2,0)"
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
