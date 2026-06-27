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

# Loop-guard: after 3 consecutive red runs, hand control back to the human.
# Counter is incremented on every gate invocation (green run clears it below).
guard="$proj/.claude/sessions/${sid}/.stopgate.count"
n=$(( $(cat "$guard" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$guard"
if [ "$n" -gt 3 ]; then
  echo "SDX stop-gate: тесты всё ещё красные после $((n-1)) попыток — нужно вмешательство человека." >&2
  rm -f "$guard"
  exit 0
fi

# Resolve the verify command.
# Priority: per-project executable script, then common project manager autodetect.
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

# No known test command -> no-op (required behaviour for SDX meta-project, ADR-4).
[ -z "$cmd" ] && exit 0

# Run the verify command; capture output for tail on failure.
if ( cd "$proj" && eval "$cmd" >/tmp/sdx-stopgate.out 2>&1 ); then
  rm -f "$guard"   # green run: reset loop-guard counter
  exit 0
else
  echo "SDX stop-gate: тест-прогон ('$cmd') красный — ход не завершён. Исправьте и повторите. Хвост:" >&2
  tail -20 /tmp/sdx-stopgate.out >&2
  exit 2
fi
