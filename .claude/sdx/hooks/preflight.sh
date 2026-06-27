#!/usr/bin/env bash
# SDX preflight (R-1): verify hook dependencies once per session (SessionStart hook).
# Without jq, prod-guard fails CLOSED (blocks Bash) and stage-gate degrades to
# fail-OPEN — warn loudly so the operator installs jq before relying on the layer.
set -uo pipefail
if ! command -v jq >/dev/null 2>&1; then
  echo "SDX preflight: jq НЕ найден — prod-guard блокирует команды из осторожности (fail-closed), а stage-gate деградирует в fail-OPEN (заморозка кода отключена). Установите jq перед работой." >&2
  # exit 2   # раскомментировать для жёсткого отказа сессии без jq
fi
exit 0
