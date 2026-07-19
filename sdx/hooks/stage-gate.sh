#!/usr/bin/env bash
# SDX stage-gate (REQ-GATE-1): freeze code writes until the Execution gate.
# PreToolUse hook for Write|Edit|MultiEdit.
# Blocks via JSON permissionDecision:"deny" on stdout, exit 0. NOT exit 2.
set -uo pipefail

input="$(cat)"
proj="${CLAUDE_PROJECT_DIR:-.}"

# deny() — emit JSON block decision to stdout and exit 0.
# $1 = reason string (Russian); jq -Rs . escapes it into a valid JSON string.
deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}' \
    "$(printf '%s' "$1" | jq -Rs .)"
  exit 0
}

# Extract the target file path from the hook input JSON.
target="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
[ -z "$target" ] && exit 0   # no file path in input -> nothing to gate

# Determine active SDX session from the git branch name (invariant: branch = sdx/<id>).
branch="$(git -C "$proj" branch --show-current 2>/dev/null || true)"
case "$branch" in
  sdx/*) sid="${branch#sdx/}" ;;
  *)     exit 0 ;;   # not an SDX branch -> gate is transparent
esac

# Load current stage from session state; missing file or empty stage -> no-op.
state="$proj/.claude/sessions/${sid}/session_state.json"
[ -f "$state" ] || exit 0
stage="$(jq -r '.stage // empty' "$state" 2>/dev/null || echo '')"
[ -z "$stage" ] && exit 0

# Code writes are legitimate during Execution and Deployment stages.
case "$stage" in
  Execution|Deployment) exit 0 ;;
esac

# Compute a project-relative path for allow-list matching.
rel="${target#"$proj"/}"

# During Verification the qa agent writes integration tests (its declared role,
# see /sdx:verify step 2). Test directories are open on Verification; code (non-test)
# stays frozen — fixes for FAIL findings go back via /sdx:backtrack --to Execution.
# Co-located tests (e.g. Go foo_test.go next to source) are NOT covered here by
# design — use the per-project stage-gate.allow for those.
if [ "$stage" = "Verification" ]; then
  case "$rel" in
    tests/*|test/*|spec/*|*/tests/*|*/test/*|*/spec/*) exit 0 ;;
  esac
fi

# Always-allowed paths: docs artifacts, framework config, any markdown file.
case "$rel" in
  docs/*|.claude/*|*.md) exit 0 ;;
esac

# Optional per-project allowlist: one shell glob per line, '#' comments ignored.
allow="$proj/.claude/sdx/stage-gate.allow"
if [ -f "$allow" ]; then
  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    case "$pat" in \#*) continue ;; esac
    # shellcheck disable=SC2254  — intentional glob from config file
    case "$rel" in $pat) exit 0 ;; esac
  done < "$allow"
fi

deny "SDX stage-gate: запись в код ($rel) заблокирована — стадия '$stage', код заморожен до гейта Execution. Артефакты планирования пишите в docs/ или каталог сессии; иначе пройдите /sdx:next до Execution."
