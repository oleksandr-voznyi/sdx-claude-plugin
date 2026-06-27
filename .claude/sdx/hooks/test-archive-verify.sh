#!/usr/bin/env bash
# Unit tests for archive-verify.sh (REQ-CLOSEOUT-1).
# Runs self-contained: creates temporary git repos, exercises the script, cleans up.
# Usage: bash .claude/sdx/hooks/test-archive-verify.sh
# NOTE: CLAUDE_PROJECT_DIR must be exported or inlined with the bash invocation.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/archive-verify.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

TMPPROJ=""
SID="test-sid"

# setup_clean_repo: init git repo with main branch; .gitignore covers sessions dir
# so that the session directory does not dirty the working tree.
setup_clean_repo() {
  TMPPROJ="$(mktemp -d)"
  git -C "$TMPPROJ" init -q
  git -C "$TMPPROJ" config user.email "test@test.com"
  git -C "$TMPPROJ" config user.name "Test"
  # Ignore .claude/sessions/ so session dirs are invisible to git status.
  printf '.claude/sessions/\n' > "$TMPPROJ/.gitignore"
  git -C "$TMPPROJ" add .gitignore
  git -C "$TMPPROJ" commit -q -m "init"
  git -C "$TMPPROJ" branch -M main 2>/dev/null || true
}

cleanup() {
  [ -n "$TMPPROJ" ] && rm -rf "$TMPPROJ"
  TMPPROJ=""
}

echo "=== test-archive-verify.sh ==="
echo ""

# ---- Scenario 1: abort on dirty working tree ----
echo "[1] Abort on dirty working tree (invariant 1)"
setup_clean_repo
# Session dir (gitignored -> clean) plus an untracked file that is NOT ignored.
mkdir -p "$TMPPROJ/.claude/sessions/$SID"
printf 'dirty\n' > "$TMPPROJ/dirty.txt"

stderr_file="$(mktemp)"
ec=0
CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK" "$SID" >/dev/null 2>"$stderr_file" || ec=$?
stderr_content="$(cat "$stderr_file")"
rm -f "$stderr_file"

if [ "$ec" -eq 1 ] && printf '%s' "$stderr_content" | grep -q "\[FAIL\]"; then
  pass "exit 1, stderr contains [FAIL]"
else
  fail "Expected exit 1 + [FAIL] in stderr" "ec=$ec stderr='$stderr_content'"
fi
# Session dir must NOT have been deleted (abort before destructive actions).
if [ -d "$TMPPROJ/.claude/sessions/$SID" ]; then
  pass "session dir preserved (no premature deletion)"
else
  fail "Session dir was deleted despite FAIL" ""
fi
cleanup

# ---- Scenario 2: abort on unmerged branch ----
echo "[2] Abort on unmerged branch (invariant 5)"
setup_clean_repo
# Create branch sdx/test-sid with a commit; do NOT merge into main.
git -C "$TMPPROJ" checkout -q -b "sdx/$SID"
git -C "$TMPPROJ" commit -q --allow-empty -m "feature work"
git -C "$TMPPROJ" checkout -q main
# Session dir (gitignored -> clean tree on main).
mkdir -p "$TMPPROJ/.claude/sessions/$SID"

stderr_file="$(mktemp)"
ec=0
CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK" "$SID" >/dev/null 2>"$stderr_file" || ec=$?
stderr_content="$(cat "$stderr_file")"
rm -f "$stderr_file"

if [ "$ec" -eq 1 ] && printf '%s' "$stderr_content" | grep -q "\[FAIL\]"; then
  pass "exit 1, stderr contains [FAIL]"
else
  fail "Expected exit 1 + [FAIL] in stderr" "ec=$ec stderr='$stderr_content'"
fi
# Session dir must NOT have been deleted.
if [ -d "$TMPPROJ/.claude/sessions/$SID" ]; then
  pass "session dir preserved (no premature deletion)"
else
  fail "Session dir was deleted despite FAIL" ""
fi
cleanup

# ---- Scenario 3: success when all invariants satisfied ----
echo "[3] Success: clean tree, branch merged into main -> [OK], session dir deleted"
setup_clean_repo
# Create sdx/test-sid branch, add a commit, merge into main.
git -C "$TMPPROJ" checkout -q -b "sdx/$SID"
git -C "$TMPPROJ" commit -q --allow-empty -m "feature work"
git -C "$TMPPROJ" checkout -q main
git -C "$TMPPROJ" merge -q --no-ff "sdx/$SID" -m "Merge sdx/$SID"
# Session dir (gitignored -> clean tree).
mkdir -p "$TMPPROJ/.claude/sessions/$SID"

stdout_file="$(mktemp)"
ec=0
CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK" "$SID" >"$stdout_file" 2>/dev/null || ec=$?
stdout_content="$(cat "$stdout_file")"
rm -f "$stdout_file"

if [ "$ec" -eq 0 ] && printf '%s' "$stdout_content" | grep -q "\[OK\]"; then
  pass "exit 0, stdout contains [OK]"
else
  fail "Expected exit 0 + [OK] in stdout" "ec=$ec stdout='$stdout_content'"
fi
if [ ! -d "$TMPPROJ/.claude/sessions/$SID" ]; then
  pass "session dir deleted"
else
  fail "Session dir was NOT deleted" ""
fi
if ! git -C "$TMPPROJ" branch | grep -q "sdx/$SID"; then
  pass "branch sdx/$SID deleted"
else
  fail "Branch sdx/$SID was NOT deleted" ""
fi
cleanup

# ---- Scenario 4: branch absent -> fail-closed, no deletion (R-5/FND-5a) ----
echo "[4] Branch absent -> [FAIL], session dir preserved (merge unprovable)"
setup_clean_repo
# No sdx/test-sid branch created at all; clean tree on main.
mkdir -p "$TMPPROJ/.claude/sessions/$SID"

stderr_file="$(mktemp)"
ec=0
CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK" "$SID" >/dev/null 2>"$stderr_file" || ec=$?
stderr_content="$(cat "$stderr_file")"
rm -f "$stderr_file"

if [ "$ec" -eq 1 ] && printf '%s' "$stderr_content" | grep -q "\[FAIL\]"; then
  pass "exit 1, stderr contains [FAIL] (branch absent)"
else
  fail "Expected exit 1 + [FAIL] in stderr" "ec=$ec stderr='$stderr_content'"
fi
if [ -d "$TMPPROJ/.claude/sessions/$SID" ]; then
  pass "session dir preserved (no deletion without proof of merge)"
else
  fail "Session dir was deleted despite absent branch" ""
fi
cleanup

# ---- Scenario 5: branch-absent override allows deletion (R-5) ----
echo "[5] Branch absent + SDX_ARCHIVE_NO_BRANCH_OK=1 -> [OK], session dir deleted"
setup_clean_repo
mkdir -p "$TMPPROJ/.claude/sessions/$SID"

stdout_file="$(mktemp)"
ec=0
SDX_ARCHIVE_NO_BRANCH_OK=1 CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK" "$SID" >"$stdout_file" 2>/dev/null || ec=$?
stdout_content="$(cat "$stdout_file")"
rm -f "$stdout_file"

if [ "$ec" -eq 0 ] && printf '%s' "$stdout_content" | grep -q "\[OK\]" && [ ! -d "$TMPPROJ/.claude/sessions/$SID" ]; then
  pass "override deletes session dir"
else
  fail "Expected [OK] + dir deleted under override" "ec=$ec stdout='$stdout_content'"
fi
cleanup

# ---- Scenario 6: anchored match ignores suffix branches (R-5/FND-5b) ----
echo "[6] Unmerged sdx/<id> + merged sdx/<id>-suffix -> [FAIL] (grep -qx anchored)"
setup_clean_repo
# Unmerged target branch.
git -C "$TMPPROJ" checkout -q -b "sdx/$SID"
git -C "$TMPPROJ" commit -q --allow-empty -m "unmerged target"
git -C "$TMPPROJ" checkout -q main
# A *merged* decoy branch whose name has sdx/<id> as a prefix.
git -C "$TMPPROJ" checkout -q -b "sdx/${SID}-decoy"
git -C "$TMPPROJ" commit -q --allow-empty -m "decoy work"
git -C "$TMPPROJ" checkout -q main
git -C "$TMPPROJ" merge -q --no-ff "sdx/${SID}-decoy" -m "Merge decoy"
mkdir -p "$TMPPROJ/.claude/sessions/$SID"

stderr_file="$(mktemp)"
ec=0
CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK" "$SID" >/dev/null 2>"$stderr_file" || ec=$?
stderr_content="$(cat "$stderr_file")"
rm -f "$stderr_file"

if [ "$ec" -eq 1 ] && printf '%s' "$stderr_content" | grep -q "не слита"; then
  pass "unmerged target not masked by merged suffix branch"
else
  fail "Expected [FAIL] 'не слита' for unmerged target" "ec=$ec stderr='$stderr_content'"
fi
if [ -d "$TMPPROJ/.claude/sessions/$SID" ]; then
  pass "session dir preserved"
else
  fail "Session dir was deleted despite unmerged target" ""
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
