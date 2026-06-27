#!/usr/bin/env bash
# Unit tests for prod-guard.sh (REQ-PROD-1).
# Runs self-contained: creates temporary directories, exercises the hook, cleans up.
# Usage: bash .claude/sdx/hooks/test-prod-guard.sh
# NOTE: prod-guard does not use git, so no git repo setup is needed.
#       CLAUDE_PROJECT_DIR must prefix the bash invocation (not printf) in pipelines.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/prod-guard.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

TMPPROJ=""

setup_proj() {
  TMPPROJ="$(mktemp -d)"
  mkdir -p "$TMPPROJ/.claude/sdx"
}

cleanup() {
  [ -n "$TMPPROJ" ] && rm -rf "$TMPPROJ"
  TMPPROJ=""
}

# run_hook <command-string>
#   Pipe a hook JSON event (with the given command) to prod-guard.sh.
#   Sets RUN_OUT (stdout) and RUN_EC (exit code).
RUN_OUT=""
RUN_EC=0
run_hook() {
  local cmd="$1"
  RUN_EC=0
  RUN_OUT="$(printf '{"tool_input":{"command":"%s"}}' "$cmd" \
             | CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK")" || RUN_EC=$?
}

echo "=== test-prod-guard.sh ==="
echo ""

# ---- Scenario 1: no prod-guard.conf -> no-op ----
echo "[1] No prod-guard.conf -> no-op (exit 0, stdout empty)"
setup_proj
# No conf file created; only .claude/sdx/ dir exists (without conf).
run_hook "deploy production"
if [ "$RUN_EC" -eq 0 ] && [ -z "$RUN_OUT" ]; then
  pass "exit 0, stdout empty"
else
  fail "Expected exit 0 + empty stdout" "ec=$RUN_EC out='$RUN_OUT'"
fi
cleanup

# ---- Scenario 2: empty prod-guard.conf (comments only) -> no-op ----
echo "[2] prod-guard.conf with comments only -> no-op"
setup_proj
printf '# no active patterns\n# ssh.*prod\n' > "$TMPPROJ/.claude/sdx/prod-guard.conf"
run_hook "deploy production"
if [ "$RUN_EC" -eq 0 ] && [ -z "$RUN_OUT" ]; then
  pass "exit 0, stdout empty (comment-only conf)"
else
  fail "Expected exit 0 + empty stdout" "ec=$RUN_EC out='$RUN_OUT'"
fi
cleanup

# ---- Scenario 3: command matches pattern -> deny ----
echo "[3] Command matching pattern -> permissionDecision:deny (exit 0)"
setup_proj
printf 'deploy.*(prod|production)\n' > "$TMPPROJ/.claude/sdx/prod-guard.conf"
run_hook "deploy.sh production"
if [ "$RUN_EC" -eq 0 ] && printf '%s' "$RUN_OUT" | grep -q '"permissionDecision":"deny"'; then
  pass "stdout contains permissionDecision:deny, exit 0"
else
  fail "Expected deny JSON + exit 0" "ec=$RUN_EC out=$RUN_OUT"
fi
# Verify the deny output is valid JSON.
if printf '%s' "$RUN_OUT" | jq . >/dev/null 2>&1; then
  pass "deny output is valid JSON"
else
  fail "deny output is not valid JSON" "out=$RUN_OUT"
fi
cleanup

# ---- Scenario 4: command does not match pattern -> no-op ----
echo "[4] Command not matching pattern -> no-op (exit 0, stdout empty)"
setup_proj
printf 'deploy.*(prod|production)\n' > "$TMPPROJ/.claude/sdx/prod-guard.conf"
run_hook "ls -la"
if [ "$RUN_EC" -eq 0 ] && [ -z "$RUN_OUT" ]; then
  pass "exit 0, stdout empty"
else
  fail "Expected exit 0 + empty stdout" "ec=$RUN_EC out='$RUN_OUT'"
fi
cleanup

# ---- Scenario 5: jq missing -> fail-closed deny (R-1/FND-1) ----
echo "[5] jq absent from PATH -> fail-closed permissionDecision:deny"
setup_proj
printf 'deploy.*(prod|production)\n' > "$TMPPROJ/.claude/sdx/prod-guard.conf"
# Build a PATH dir with the tools the hook needs EXCEPT jq.
NOJQ_BIN="$(mktemp -d)"
for t in bash cat grep printf; do
  src="$(command -v "$t" 2>/dev/null)" && ln -s "$src" "$NOJQ_BIN/$t" 2>/dev/null || true
done
RUN_EC=0
RUN_OUT="$(printf '{"tool_input":{"command":"deploy.sh production"}}' \
           | PATH="$NOJQ_BIN" CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK")" || RUN_EC=$?
rm -rf "$NOJQ_BIN"
if [ "$RUN_EC" -eq 0 ] && printf '%s' "$RUN_OUT" | grep -q '"permissionDecision":"deny"'; then
  pass "deny emitted with jq absent (fail-closed)"
else
  fail "Expected fail-closed deny" "ec=$RUN_EC out=$RUN_OUT"
fi
# The emitted JSON must still be valid (validated with the outer, available jq).
if printf '%s' "$RUN_OUT" | jq . >/dev/null 2>&1; then
  pass "fail-closed deny output is valid JSON"
else
  fail "fail-closed deny output is not valid JSON" "out=$RUN_OUT"
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
