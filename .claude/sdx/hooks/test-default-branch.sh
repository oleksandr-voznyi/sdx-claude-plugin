#!/usr/bin/env bash
# Unit tests for lib/default-branch.sh (REQ-BRANCH-1/2/3/4).
# Runs self-contained: creates temporary git repos, exercises the helper, cleans up.
# Usage: bash .claude/sdx/hooks/test-default-branch.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/lib/default-branch.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

TMPPROJ=""

setup_bare_repo() {
  TMPPROJ="$(mktemp -d)"
  git -C "$TMPPROJ" init -q
  git -C "$TMPPROJ" config user.email "test@test.com"
  git -C "$TMPPROJ" config user.name "Test"
}

cleanup() {
  [ -n "$TMPPROJ" ] && rm -rf "$TMPPROJ"
  TMPPROJ=""
}

echo "=== test-default-branch.sh ==="
echo ""

# ---- Scenario 1: origin/HEAD symbolic ref -> master (authoritative when remote present) ----
echo "[1] origin/HEAD=master -> prints master"
setup_bare_repo
git -C "$TMPPROJ" commit -q --allow-empty -m "init"
git -C "$TMPPROJ" branch -M main 2>/dev/null || true
# Simulate a configured remote-tracking symbolic ref without needing a real remote.
git -C "$TMPPROJ" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/master

out="$(bash "$HOOK" "$TMPPROJ" 2>/dev/null)"
if [ "$out" = "master" ]; then
  pass "prints 'master' from origin/HEAD"
else
  fail "Expected 'master'" "got '$out'"
fi
cleanup

# ---- Scenario 2: no remote, init.defaultBranch=trunk (branch exists) ----
echo "[2] No remote + init.defaultBranch=trunk (branch exists) -> prints trunk"
setup_bare_repo
git -C "$TMPPROJ" config init.defaultBranch trunk
git -C "$TMPPROJ" commit -q --allow-empty -m "init"
git -C "$TMPPROJ" branch -M trunk 2>/dev/null || true

out="$(bash "$HOOK" "$TMPPROJ" 2>/dev/null)"
if [ "$out" = "trunk" ]; then
  pass "prints 'trunk' from init.defaultBranch"
else
  fail "Expected 'trunk'" "got '$out'"
fi
cleanup

# ---- Scenario 3: no remote, only 'main' branch exists (heuristic) ----
echo "[3] No remote, only 'main' branch -> prints main"
setup_bare_repo
git -C "$TMPPROJ" commit -q --allow-empty -m "init"
git -C "$TMPPROJ" branch -M main 2>/dev/null || true

out="$(bash "$HOOK" "$TMPPROJ" 2>/dev/null)"
if [ "$out" = "main" ]; then
  pass "prints 'main' (heuristic on existing local branch)"
else
  fail "Expected 'main'" "got '$out'"
fi
cleanup

# ---- Scenario 4: no remote, only 'master' branch exists (heuristic) ----
echo "[4] No remote, only 'master' branch -> prints master"
setup_bare_repo
git -C "$TMPPROJ" commit -q --allow-empty -m "init"
git -C "$TMPPROJ" branch -M master 2>/dev/null || true

out="$(bash "$HOOK" "$TMPPROJ" 2>/dev/null)"
if [ "$out" = "master" ]; then
  pass "prints 'master' (heuristic on existing local branch)"
else
  fail "Expected 'master'" "got '$out'"
fi
cleanup

# ---- Scenario 5: empty repository (no commits, no branches, no remote, no config) ----
echo "[5] Empty repository (unborn HEAD) -> last-resort 'main'"
setup_bare_repo
# No commits at all -> no refs/heads/* exist yet.

out="$(bash "$HOOK" "$TMPPROJ" 2>/dev/null)"
if [ "$out" = "main" ]; then
  pass "prints last-resort 'main'"
else
  fail "Expected last-resort 'main'" "got '$out'"
fi
cleanup

# ---- Scenario 6: proj_dir defaults to CLAUDE_PROJECT_DIR when no argument passed ----
echo "[6] proj_dir argument optional -> defaults to CLAUDE_PROJECT_DIR"
setup_bare_repo
git -C "$TMPPROJ" commit -q --allow-empty -m "init"
git -C "$TMPPROJ" branch -M main 2>/dev/null || true

out="$(CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK" 2>/dev/null)"
if [ "$out" = "main" ]; then
  pass "resolves via CLAUDE_PROJECT_DIR when proj_dir omitted"
else
  fail "Expected 'main' via CLAUDE_PROJECT_DIR" "got '$out'"
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
