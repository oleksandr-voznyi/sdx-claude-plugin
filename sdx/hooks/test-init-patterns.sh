#!/usr/bin/env bash
# Static guard: every gitignore pattern this framework relies on must appear BOTH in the
# meta-project's own .gitignore AND in the canonical list that /sdx:init deploys into a
# consumer project (commands/init.md).
#
# Why this suite exists. The two lists drifted apart once already: the self-test cache pattern
# (.claude/sdx/.cache/, FEAT-014) was added here by hand and forgotten in init.md. In a freshly
# initialised consumer project that omission is not cosmetic — the SessionStart hook writes an
# untracked file, and archive-verify.sh checks invariant 1 with `git status --porcelain`, so
# EVERY /sdx:archive would have failed. The dogfood repo stayed green precisely because its own
# .gitignore was edited manually, which is exactly the blind spot this suite removes.
#
# Deliberately static, like test-hook-wiring.sh: it compares two texts, runs no hooks.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GITIGNORE="$ROOT/.gitignore"
INIT_MD="$ROOT/commands/init.md"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

echo "=== test-init-patterns.sh ==="
echo ""

# Patterns of the framework itself, not of this checkout: lines that are neither blank nor a
# comment. `.claude/settings.local.json` is intentionally in both lists and needs no special case.
patterns="$(grep -vE '^\s*(#|$)' "$GITIGNORE" 2>/dev/null)"

# Documented exception. `.sdx/worktrees/` belongs to the session-as-worktree model cancelled by
# ADR-012. The path still exists in this checkout as an EMPTY directory (no files under it —
# checked while writing this suite), which is exactly the residue commands/reconcile.md
# classifies as a finding that is never auto-removed. Keeping the pattern here costs nothing and
# keeps any future leftover out of git; a project initialised today never had worktrees, so
# /sdx:init deploying it would be cargo cult. The asymmetry is intentional and only in this
# direction. If the directory is ever removed, drop this exception with it.
exceptions=".sdx/worktrees/"

# missing_patterns <init-file> — prints the patterns absent from <init-file>, one per line.
# Extracted so scenario [3] can run the very same comparison against a deliberately damaged
# copy: a guard whose own logic is never exercised against a failing input proves nothing.
missing_patterns() {
  local init_file="$1" p
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    case " $exceptions " in *" $p "*) continue ;; esac
    grep -qF -- "$p" "$init_file" || printf '%s\n' "$p"
  done <<< "$patterns"
}

echo "[1] Every pattern in the repo .gitignore is also in the canonical list of /sdx:init"
if [ -z "$patterns" ]; then
  fail "no patterns read from .gitignore" "$GITIGNORE unreadable or empty"
else
  # Same helper the red-side scenario [3] exercises — one comparison, two inputs.
  missing="$(missing_patterns "$INIT_MD" | tr '\n' ' ')"
  skipped="$(printf '%s\n' "$exceptions" | grep -c . || true)"
  total="$(printf '%s\n' "$patterns" | grep -c . || true)"
  n=$((total - skipped))   # проверено = всего минус документированные исключения
  if [ -z "$missing" ]; then
    pass "all $n checked pattern(s) present in commands/init.md ($total total, $skipped documented exception(s) skipped)"
  else
    fail "pattern(s) missing from commands/init.md" "$missing"
  fi
fi

# The reverse direction is deliberately NOT asserted: init.md may legitimately carry a pattern
# this repo does not need (a consumer-only path). Drift that direction is harmless; the direction
# that breaks consumers is the one guarded above.

echo "[2] The self-test cache pattern specifically is in both lists (regression pin, FEAT-014)"
inb=0
grep -qF -- '.claude/sdx/.cache/' "$GITIGNORE" && inb=$((inb + 1))
grep -qF -- '.claude/sdx/.cache/' "$INIT_MD" && inb=$((inb + 1))
if [ "$inb" -eq 2 ]; then
  pass ".claude/sdx/.cache/ present in .gitignore and in commands/init.md"
else
  fail "self-test cache pattern missing from one of the lists" "found in $inb of 2"
fi

echo "[3] The comparison itself discriminates: a damaged canonical list is reported"
scratch="$(mktemp)"
grep -vF -- '.claude/sdx/.cache/' "$INIT_MD" > "$scratch"
dmg="$(missing_patterns "$scratch")"
rm -f "$scratch"
case "$dmg" in
  *".claude/sdx/.cache/"*) pass "removing .cache/ from a copy of init.md is reported as missing" ;;
  *) fail "comparison did not report the removed pattern" "got: '$dmg' — the guard would not have caught the real defect it was written for" ;;
esac

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "ALL PASSED"
  exit 0
else
  exit 1
fi
