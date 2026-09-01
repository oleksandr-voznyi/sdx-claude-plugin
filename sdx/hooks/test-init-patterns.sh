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

echo "[1] Every pattern in the repo .gitignore is also in the canonical list of /sdx:init"
if [ -z "$patterns" ]; then
  fail "no patterns read from .gitignore" "$GITIGNORE unreadable or empty"
else
  # Documented exception. `.sdx/worktrees/` belongs to the session-as-worktree model cancelled
  # by ADR-012. It stays in THIS repo's .gitignore as a safety net: a leftover worktree directory
  # from that era still exists here, and commands/reconcile.md classifies such leftovers as a
  # finding that is never auto-removed (they may hold uncommitted work). A project initialised
  # today never had worktrees, so /sdx:init deploying the pattern would be cargo cult. The
  # asymmetry is intentional and only in this direction.
  exceptions=".sdx/worktrees/"

  missing=""
  n=0
  skipped=0
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    case " $exceptions " in *" $p "*) skipped=$((skipped + 1)); continue ;; esac
    n=$((n + 1))
    grep -qF -- "$p" "$INIT_MD" || missing="${missing:+$missing }$p"
  done <<< "$patterns"
  if [ -z "$missing" ]; then
    pass "all $n pattern(s) present in commands/init.md ($skipped documented exception(s) skipped)"
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

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "ALL PASSED"
  exit 0
else
  exit 1
fi
