#!/usr/bin/env bash
# SDX stop-gate (REQ-GATE-2): deterministic test floor under Verification.
# Stop hook. exit 2 + stderr blocks turn-end until the verify command is green.
set -uo pipefail

proj="${CLAUDE_PROJECT_DIR:-.}"

# Determine active SDX session from the git branch name.
branch="$(git -C "$proj" branch --show-current 2>/dev/null || true)"
case "$branch" in
  sdx/*) sid="${branch#sdx/}" ;;
  *)     exit 0 ;;   # not an SDX branch -> transparent
esac

# Load current stage; missing state file -> no-op.
state="$proj/.claude/sessions/${sid}/session_state.json"
[ -f "$state" ] || exit 0
stage="$(jq -r '.stage // empty' "$state" 2>/dev/null || echo '')"

# Enforce only in Execution/Verification, unless forced by SDX_STOP_GATE=1 (headless/Phase 4).
if [ "${SDX_STOP_GATE:-0}" != "1" ]; then
  case "$stage" in
    Execution|Verification) ;;   # fall through to enforcement
    *) exit 0 ;;                 # other stages -> transparent
  esac
fi

# Resolve the verify command BEFORE touching the loop-guard counter.
# Priority: per-project executable script, then common project manager autodetect.
# Doing this first keeps the no-op path (no test command) from mutating the
# counter and emitting a spurious "human intervention" message every 4th turn.
cmd=""
if [ -x "$proj/.claude/sdx/verify-cmd.sh" ]; then
  cmd="$proj/.claude/sdx/verify-cmd.sh"
elif [ -f "$proj/composer.json" ] && grep -q '"test"' "$proj/composer.json"; then
  cmd="composer test"
elif [ -f "$proj/package.json" ] && grep -q '"test"' "$proj/package.json"; then
  cmd="npm test --silent"
elif [ -f "$proj/phpunit.xml" ] || [ -f "$proj/phpunit.xml.dist" ]; then
  cmd="./vendor/bin/phpunit"
fi

# No known test command -> no-op (required behaviour for projects without a test command, ADR-4).
[ -z "$cmd" ] && exit 0

# Green-run cache (A4): if the working tree's fingerprint matches the last known-green
# fingerprint, skip re-running verify entirely. Fingerprint = HEAD commit + hash of the
# porcelain status (covers both committed and uncommitted changes). Bypassed by
# SDX_STOP_GATE=1 (forced/headless runs must always be honest).
okfile="$proj/.claude/sessions/${sid}/.stopgate.ok"
if [ "${SDX_STOP_GATE:-0}" != "1" ]; then
  head_rev="$(git -C "$proj" rev-parse HEAD 2>/dev/null || true)"
  tree_status="$(git -C "$proj" status --porcelain 2>/dev/null || true)"
  fingerprint="${head_rev}:$(printf '%s' "$tree_status" | md5sum | cut -d' ' -f1)"
  if [ -f "$okfile" ] && [ "$(cat "$okfile" 2>/dev/null)" = "$fingerprint" ]; then
    exit 0   # cache hit: tree unchanged since the last green run
  fi
fi

# Loop-guard: after 3 consecutive red runs, hand control back to the human.
# Counter is incremented only once a real verify command exists (green run clears it below).
guard="$proj/.claude/sessions/${sid}/.stopgate.count"
n=$(( $(cat "$guard" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$guard"
if [ "$n" -gt 3 ]; then
  echo "SDX stop-gate: тесты всё ещё красные после $((n-1)) попыток — нужно вмешательство человека." >&2
  rm -f "$guard"
  exit 0
fi

# Per-session temp file (R-3/FND-3): worktree-safe, avoids cross-session clobber.
outfile="$proj/.claude/sessions/${sid}/.stopgate.out"

# Run the verify command under a timeout (R-2/FND-2): a hung/watch-mode runner must
# not block turn-end indefinitely. timeout's non-zero rc is treated as red (block);
# the loop-guard above still returns control to the human after 3 attempts.
if ( cd "$proj" && timeout "${SDX_VERIFY_TIMEOUT:-180}" bash -c "$cmd" >"$outfile" 2>&1 ); then
  rm -f "$guard"   # green run: reset loop-guard counter
  # Cache the tree fingerprint at the moment verify went green (A4), so the next
  # Stop on an unchanged tree can skip re-running verify. Recompute post-run to
  # capture the tree exactly as it stood for this (successful) verification.
  green_head_rev="$(git -C "$proj" rev-parse HEAD 2>/dev/null || true)"
  green_tree_status="$(git -C "$proj" status --porcelain 2>/dev/null || true)"
  printf '%s' "${green_head_rev}:$(printf '%s' "$green_tree_status" | md5sum | cut -d' ' -f1)" > "$okfile"
  exit 0
else
  echo "SDX stop-gate: тест-прогон ('$cmd') красный — ход не завершён. Исправьте и повторите. Хвост:" >&2
  tail -20 "$outfile" >&2
  exit 2
fi
