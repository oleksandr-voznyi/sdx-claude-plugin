#!/usr/bin/env bash
# Unit tests for lib/resolve-session.sh.
# Runs self-contained: creates temporary git repos, exercises the sourceable
# resolve_sid() function via a subshell, cleans up.
# Usage: bash sdx/hooks/test-resolve-session.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

TMPPROJ=""

# setup_repo <branch-name>
#   Creates a temp git repo, optionally checked out on the given branch.
#   branch="main" keeps the default branch (no checkout needed).
setup_repo() {
  local branch="$1"
  TMPPROJ="$(mktemp -d)"
  git -C "$TMPPROJ" init -q
  git -C "$TMPPROJ" config user.email "test@test.com"
  git -C "$TMPPROJ" config user.name "Test"
  git -C "$TMPPROJ" commit -q --allow-empty -m "init"
  git -C "$TMPPROJ" branch -M main 2>/dev/null || true
  if [ "$branch" != "main" ]; then
    git -C "$TMPPROJ" checkout -q -b "$branch"
  fi
}

cleanup() {
  [ -n "$TMPPROJ" ] && rm -rf "$TMPPROJ"
  TMPPROJ=""
}

# run_resolve <proj>
#   Sources the library in a subshell and calls resolve_sid <proj>.
run_resolve() {
  bash -c '. "$1"/lib/resolve-session.sh; resolve_sid "$2"' _ "$SCRIPT_DIR" "$1"
}

echo "=== test-resolve-session.sh ==="
echo ""

# ---- Scenario 1: branch sdx/test-abc -> prints test-abc ----
echo "[1] Branch sdx/test-abc -> resolve_sid prints test-abc"
setup_repo "sdx/test-abc"
out="$(run_resolve "$TMPPROJ")"
if [ "$out" = "test-abc" ]; then
  pass "prints 'test-abc'"
else
  fail "Expected 'test-abc'" "got '$out'"
fi
cleanup

# ---- Scenario 2: branch main -> prints empty string ----
echo "[2] Branch main -> resolve_sid prints empty string"
setup_repo "main"
out="$(run_resolve "$TMPPROJ")"
if [ -z "$out" ]; then
  pass "prints empty string"
else
  fail "Expected empty string" "got '$out'"
fi
cleanup

# ---- Scenario 3: branch sdx/ (no suffix, edge case) -> prints empty string ----
# Note: git itself rejects "sdx/" as a real branch name (empty ref component,
# see `git check-ref-format`), so this edge case cannot be constructed with a
# real `git checkout -b`. We stub `git` on PATH to report "sdx/" as the current
# branch, isolating resolve_sid's string handling (${branch#sdx/}) from git's
# own ref-name validation.
echo "[3] Branch sdx/ (no suffix) -> resolve_sid prints empty string"
FAKEBIN="$(mktemp -d)"
cat > "$FAKEBIN/git" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-C" ] && [ "$3" = "branch" ] && [ "$4" = "--show-current" ]; then
  printf 'sdx/\n'
  exit 0
fi
exit 0
EOF
chmod +x "$FAKEBIN/git"
out="$(PATH="$FAKEBIN:$PATH" bash -c '. "$1"/lib/resolve-session.sh; resolve_sid "$2"' _ "$SCRIPT_DIR" "/tmp")"
rm -rf "$FAKEBIN"
if [ -z "$out" ]; then
  pass "prints empty string (accepted edge case: \${branch#sdx/} of 'sdx/' is empty, not garbage)"
else
  fail "Expected empty string" "got '$out'"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "ALL PASSED"
  exit 0
else
  exit 1
fi
