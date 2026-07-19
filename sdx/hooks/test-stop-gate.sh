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

# ---- Scenario 5: green run -> exit 0 and loop-guard counter reset ----
echo "[5] Green verify run exits 0 and clears the loop-guard counter"
setup_stop_repo "sdx/test-stop" "Verification"
mkdir -p "$TMPPROJ/.claude/sdx"
# A verify command that passes.
printf '#!/bin/bash\nexit 0\n' > "$TMPPROJ/.claude/sdx/verify-cmd.sh"
chmod +x "$TMPPROJ/.claude/sdx/verify-cmd.sh"
# Pre-seed a stale loop-guard counter to prove the green run clears it.
guard_file="$TMPPROJ/.claude/sessions/test-stop/.stopgate.count"
echo 2 > "$guard_file"
run_hook
if [ "$RUN_EC" -eq 0 ] && [ ! -f "$guard_file" ]; then
  pass "exit 0 on green run and counter file removed"
else
  fail "Green path" "exit=$RUN_EC, counter present=$([ -f "$guard_file" ] && echo yes || echo no)"
fi
cleanup

# ---- Scenario 6: hung runner is killed by timeout and treated as red (R-2/FND-2) ----
echo "[6] Hung verify runner -> timeout -> exit 2 (treated as red)"
setup_stop_repo "sdx/test-stop" "Execution"
mkdir -p "$TMPPROJ/.claude/sdx"
# A verify command that hangs far longer than the timeout.
printf '#!/bin/bash\nsleep 30\n' > "$TMPPROJ/.claude/sdx/verify-cmd.sh"
chmod +x "$TMPPROJ/.claude/sdx/verify-cmd.sh"
RUN_EC=0
SDX_VERIFY_TIMEOUT=1 CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK" >/dev/null 2>/dev/null || RUN_EC=$?
if [ "$RUN_EC" -eq 2 ]; then
  pass "exit 2 after timeout (hung runner does not pass)"
else
  fail "Expected exit 2 from timeout" "got exit $RUN_EC"
fi
cleanup

# ---- Scenario 7: .stopgate.* files stay invisible to `git status` under the new
#                   targeted .gitignore (REQ-SESS-2, косвенная зависимость от T3) ----
echo "[7] .stopgate.count/.stopgate.out do not appear in 'git status --porcelain' (targeted .gitignore)"
setup_stop_repo "sdx/test-stop" "Execution"
# Install the ACTUAL targeted .gitignore (ADR-009, T3) — no widescale ignore of
# .claude/sessions/, only the stopgate ephemera pattern.
cat > "$TMPPROJ/.gitignore" <<'EOF'
.sdx/worktrees/
.claude/sessions/*/.stopgate.*
.sdx/bundles/
.claude/settings.local.json
EOF
git -C "$TMPPROJ" add .gitignore
git -C "$TMPPROJ" commit -q -m "add targeted .gitignore"
mkdir -p "$TMPPROJ/.claude/sdx"
# A verify command that always fails -> stop-gate writes .stopgate.count/.stopgate.out.
printf '#!/bin/bash\nexit 1\n' > "$TMPPROJ/.claude/sdx/verify-cmd.sh"
chmod +x "$TMPPROJ/.claude/sdx/verify-cmd.sh"
run_hook
status_output="$(git -C "$TMPPROJ" status --porcelain)"
if [ -f "$TMPPROJ/.claude/sessions/test-stop/.stopgate.count" ] \
   && [ -f "$TMPPROJ/.claude/sessions/test-stop/.stopgate.out" ]; then
  pass "stopgate scratch files were created"
else
  fail "Expected .stopgate.count and .stopgate.out to exist" ""
fi
if printf '%s' "$status_output" | grep -q "stopgate"; then
  fail "stopgate scratch files leaked into git status --porcelain" "status='$status_output'"
else
  pass "git status --porcelain does not mention .stopgate.* (ignored by targeted .gitignore)"
fi
cleanup

# ---- Scenario 8: green-run cache — unchanged tree short-circuits the next Stop (A4) ----
echo "[8] Green-run cache: unchanged tree -> second Stop is a no-op (verify not re-run)"
setup_stop_repo "sdx/test-stop" "Execution"
mkdir -p "$TMPPROJ/.claude/sdx"
runcount_file="$TMPPROJ/.claude/sdx/runcount"
# A verify command that appends a marker line each time it actually executes, then passes.
cat > "$TMPPROJ/.claude/sdx/verify-cmd.sh" <<EOF
#!/bin/bash
echo run >> "$runcount_file"
exit 0
EOF
chmod +x "$TMPPROJ/.claude/sdx/verify-cmd.sh"
run_hook
first_ec="$RUN_EC"
first_runs="$(wc -l < "$runcount_file" 2>/dev/null || echo 0)"
run_hook
second_ec="$RUN_EC"
second_runs="$(wc -l < "$runcount_file" 2>/dev/null || echo 0)"
if [ "$first_ec" -eq 0 ] && [ "$second_ec" -eq 0 ] && [ "$first_runs" -eq 1 ] && [ "$second_runs" -eq 1 ]; then
  pass "second Stop on unchanged tree is a cache-hit no-op (verify ran once)"
else
  fail "Cache-hit expected" "first_ec=$first_ec second_ec=$second_ec first_runs=$first_runs second_runs=$second_runs"
fi
cleanup

# ---- Scenario 9: green-run cache — changed tree invalidates the cache (A4) ----
echo "[9] Green-run cache: changed tree -> next Stop re-runs verify"
setup_stop_repo "sdx/test-stop" "Execution"
mkdir -p "$TMPPROJ/.claude/sdx"
runcount_file="$TMPPROJ/.claude/sdx/runcount"
cat > "$TMPPROJ/.claude/sdx/verify-cmd.sh" <<EOF
#!/bin/bash
echo run >> "$runcount_file"
exit 0
EOF
chmod +x "$TMPPROJ/.claude/sdx/verify-cmd.sh"
run_hook
first_ec="$RUN_EC"
# Mutate the working tree so the fingerprint changes.
echo "change" > "$TMPPROJ/some-file.txt"
run_hook
second_ec="$RUN_EC"
second_runs="$(wc -l < "$runcount_file" 2>/dev/null || echo 0)"
if [ "$first_ec" -eq 0 ] && [ "$second_ec" -eq 0 ] && [ "$second_runs" -eq 2 ]; then
  pass "changed tree invalidates cache (verify re-ran)"
else
  fail "Cache invalidation expected" "first_ec=$first_ec second_ec=$second_ec second_runs=$second_runs"
fi
cleanup

# ---- Scenario 10: SDX_STOP_GATE=1 bypasses the cache; green force still updates .stopgate.ok (A4) ----
echo "[10] SDX_STOP_GATE=1: cache bypassed on read, but green force still writes .stopgate.ok"
setup_stop_repo "sdx/test-stop" "Execution"
mkdir -p "$TMPPROJ/.claude/sdx"
runcount_file="$TMPPROJ/.claude/sdx/runcount"
cat > "$TMPPROJ/.claude/sdx/verify-cmd.sh" <<EOF
#!/bin/bash
echo run >> "$runcount_file"
exit 0
EOF
chmod +x "$TMPPROJ/.claude/sdx/verify-cmd.sh"
okfile="$TMPPROJ/.claude/sessions/test-stop/.stopgate.ok"
# First green run (normal) seeds the cache.
run_hook
# Forced run on the SAME unchanged tree must bypass the cache and re-run verify.
SDX_STOP_GATE=1 CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK" >/dev/null 2>/dev/null || true
forced_runs="$(wc -l < "$runcount_file" 2>/dev/null || echo 0)"
if [ "$forced_runs" -eq 2 ] && [ -f "$okfile" ]; then
  pass "forced run bypassed cache (verify re-ran) and .stopgate.ok still present"
else
  fail "Forced bypass" "forced_runs=$forced_runs (expected 2), okfile present=$([ -f "$okfile" ] && echo yes || echo no)"
fi
cleanup

# ---- Scenario 11: red run does NOT write .stopgate.ok (A4) ----
echo "[11] Red verify run leaves no .stopgate.ok cache entry"
setup_stop_repo "sdx/test-stop" "Execution"
mkdir -p "$TMPPROJ/.claude/sdx"
printf '#!/bin/bash\nexit 1\n' > "$TMPPROJ/.claude/sdx/verify-cmd.sh"
chmod +x "$TMPPROJ/.claude/sdx/verify-cmd.sh"
okfile="$TMPPROJ/.claude/sessions/test-stop/.stopgate.ok"
run_hook
if [ "$RUN_EC" -eq 2 ] && [ ! -f "$okfile" ]; then
  pass "red run exits 2 and writes no .stopgate.ok"
else
  fail "Red-run cache" "exit=$RUN_EC (expected 2), okfile present=$([ -f "$okfile" ] && echo yes || echo no)"
fi
cleanup

# ---- Scenario 12: cache-hit does NOT touch the loop-guard counter (A4) ----
echo "[12] Cache-hit on unchanged tree leaves the loop-guard counter untouched"
setup_stop_repo "sdx/test-stop" "Execution"
mkdir -p "$TMPPROJ/.claude/sdx"
printf '#!/bin/bash\nexit 0\n' > "$TMPPROJ/.claude/sdx/verify-cmd.sh"
chmod +x "$TMPPROJ/.claude/sdx/verify-cmd.sh"
guard_file="$TMPPROJ/.claude/sessions/test-stop/.stopgate.count"
# First green run seeds the cache and clears any counter.
run_hook
# Second Stop on the unchanged tree is a cache-hit BEFORE the guard increment,
# so no counter file must be created.
run_hook
if [ "$RUN_EC" -eq 0 ] && [ ! -f "$guard_file" ]; then
  pass "cache-hit short-circuits before loop-guard (no counter file created)"
else
  fail "Cache-hit vs loop-guard" "exit=$RUN_EC, counter present=$([ -f "$guard_file" ] && echo yes || echo no)"
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
