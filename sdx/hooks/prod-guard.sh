#!/usr/bin/env bash
# SDX prod-guard (REQ-PROD-1): block shell commands matching prod-guard.conf patterns.
# PreToolUse hook on Bash tool.
# Blocks via JSON permissionDecision:"deny" on stdout, exit 0. NOT exit 2.
set -uo pipefail

proj="${CLAUDE_PROJECT_DIR:-.}"

# deny() — emit JSON block decision and exit 0.
deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}' \
    "$(printf '%s' "$1" | jq -Rs .)"
  exit 0
}

# Load per-project pattern config; no file = no protection (opt-in enforcement).
# This check needs no jq, so it MUST run before the jq check (A2): on a project
# without configured protection, a missing jq must not turn into blocking every
# Bash command. Fail-closed applies only where protection is actually configured.
conf="$proj/.claude/sdx/prod-guard.conf"
[ -f "$conf" ] || exit 0

# Determine whether the conf declares any active pattern (non-empty, non-comment).
# An empty or comment-only conf = "no protection by agreement" -> no-op.
has_pattern=0
while IFS= read -r pat; do
  [ -z "$pat" ] && continue
  case "$pat" in \#*) continue ;; esac
  has_pattern=1; break
done < "$conf"
[ "$has_pattern" -eq 0 ] && exit 0

# Protection is configured -> from here we must be able to parse the command.
# Fail-closed (R-1/FND-1): this layer's only job is to keep the agent out of prod.
# If jq is missing we cannot parse the command -> block rather than silently pass.
# NB: deny() itself relies on jq to escape its reason, so emit a static, already
# valid JSON string here (the reason text contains no characters needing escaping).
if ! command -v jq >/dev/null 2>&1; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"SDX prod-guard: jq недоступен при сконфигурированной защите — блокирую команду из осторожности (fail-closed). Установите jq."}}'
  exit 0
fi

# Extract the shell command from the hook input JSON.
cmd="$(cat | jq -r '.tool_input.command // empty')"
[ -z "$cmd" ] && exit 0   # no command in input -> nothing to gate

# Check each non-empty, non-comment line as an extended regex pattern.
while IFS= read -r pat; do
  [ -z "$pat" ] && continue
  case "$pat" in \#*) continue ;; esac
  if printf '%s' "$cmd" | grep -Eiq -- "$pat"; then
    deny "SDX prod-guard: команда совпала с прод-паттерном (/$pat/) и заблокирована. Прод-деплой — только явное действие человека, не агента. При осознанном деплое снимите блок вручную."
  fi
done < "$conf"

exit 0
