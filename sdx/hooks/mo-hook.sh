#!/usr/bin/env bash
# SDX mo-hook (FEAT-015, REQ-MO-HOOK-1..10): PreToolUse wrapper around the vendored sim-kit hook
# sdx/mo/devagent_hook.py (second PEP of the meta-orchestrator, MO, "exec_paths" write check).
#
# Contract: ALWAYS exit 0. A block is JSON permissionDecision:"deny" on stdout (like prod-guard.sh).
# The sim-kit hook blocks with exit 2 + reason on stderr; this wrapper translates that into the JSON
# deny and never returns exit 2 itself. stderr carries at most one line.
#
# Activation: ONLY the file $CLAUDE_PROJECT_DIR/.mesh/endpoint.yaml (not a branch, not .claude/sdx).
# Without it: no output, no jq, no python (check order: endpoint.yaml -> mode -> jq/python3/hook file -> exit code).
#
# Failure policy (differs from prod-guard on purpose): mode "notice" fails open with one stderr line,
# mode "deny" fails closed. PyYAML is NOT pre-checked: the sim-kit hook turns its absence into the same
# policy by itself. No "-o pipefail": no exit code that the logic relies on is taken from a pipe; stdin is
# read once and handed to the hook as a here-string.
# Portable: bash 3.2 builtins + cat/jq/python3 only (BUG-010).
# The "# MO-..." tags on lines are anchors for the mutation runs in test-mo-hook.sh.
set -u

proj="${CLAUDE_PROJECT_DIR:-.}"
[ -f "$proj/.mesh/endpoint.yaml" ] || exit 0   # MO-EARLY-EXIT

if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  plugin_root="$CLAUDE_PLUGIN_ROOT"
else
  case "${BASH_SOURCE[0]}" in */*) here="${BASH_SOURCE[0]%/*}" ;; *) here="." ;; esac
  plugin_root="$(cd "$here/../.." && pwd)"
fi
hook="$plugin_root/sdx/mo/devagent_hook.py"

# --- Mode: same rule as devagent_hook.py raw_mode() (re.search ^\s*on_write\s*:\s*['"]?(\w+), re.M), lowercased.
# Whole file is matched as one string so that \s spanning a newline ("on_write:\n  deny") behaves like Python.
mode_re='(^|'$'\n'')[[:space:]]*on_write[[:space:]]*:[[:space:]]*['"'"'"]?([[:alnum:]_]+)'   # MO-MODE
mode=notice
if text="$(cat "$proj/.mesh/endpoint.yaml" 2>/dev/null)" && [[ $text =~ $mode_re ]]; then
  case "${BASH_REMATCH[2]}" in [dD][eE][nN][yY]) mode=deny ;; esac
fi

# deny_json <reason> — JSON block decision on stdout, exit 0. Needs jq (checked before any caller).
deny_json() {
  local r
  r="$(printf '%s' "$1" | jq -Rs . 2>/dev/null)" || r='"SDX mo-hook: блок (причина не сериализована)"'
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}' "$r"
  exit 0   # MO-RC2
}

# cannot_check <why> — the target of a write cannot be verified: policy by mode.
cannot_check() {
  if [ "$mode" = deny ]; then   # MO-FAILOPEN
    deny_json "SDX mo-hook: PEP не может проверить цель записи — $1. Режим deny: запись остановлена (fail-closed)."
  else
    printf 'SDX mo-hook: %s — проверка exec_paths пропущена (режим notice)\n' "$1" >&2
    exit 0
  fi
}

# --- Input and dependencies. stdin is read exactly once.
input="$(cat)"
if ! command -v jq >/dev/null 2>&1; then
  if [ "$mode" = deny ]; then
    # Static, already valid JSON: the serializer (jq) is the missing piece.
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"SDX mo-hook: jq недоступен при наличии .mesh/endpoint.yaml (режим deny) — блокирую из осторожности (fail-closed). Установите jq."}}'
  else
    printf 'SDX mo-hook: jq не найден — проверка записи в exec_paths пропущена (режим notice). Установите jq.\n' >&2
  fi
  exit 0
fi

tool="$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null)" || cannot_check "вход хука не разобран"

# --- Mailbox guard (REQ-MO-HOOK-8): Write-family tools must not write .mesh/endpoint.yaml / cursors.json.
# Lexical normalisation only (no symlink resolution of the file path itself): a named best-effort limit.
norm_path() {   # absolute path -> collapsed ("//", "/./", "/../"); builtins only
  local p="$1" seg res="" IFS=/
  set -f
  for seg in $p; do
    case "$seg" in
      ""|.) ;;
      ..) res="${res%/*}" ;;
      *) res="$res/$seg" ;;
    esac
  done
  printf '%s' "${res:-/}"
}

is_mailbox_file() {   # $1 = file path from the tool input, $2 = cwd from the tool input
  local fp="$1" base proj_abs proj_phys d f
  proj_abs="$(cd "$proj" 2>/dev/null && pwd)" || return 1
  proj_phys="$(cd "$proj" 2>/dev/null && pwd -P)" || return 1
  case "$2" in /*) base="$2" ;; *) base="$proj_abs" ;; esac
  case "$fp" in /*) ;; *) fp="$base/$fp" ;; esac; fp="$(norm_path "$fp")"   # MO-NORM
  for d in "$proj_abs" "$proj_phys"; do
    for f in endpoint.yaml cursors.json; do
      [ "$fp" = "$d/.mesh/$f" ] && return 0
    done
  done
  return 1
}

case "$tool" in
  Write|Edit|MultiEdit|NotebookEdit)
    fp="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input" 2>/dev/null)"
    cwd0="$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)"
    [ -n "$fp" ] && is_mailbox_file "$fp" "$cwd0" && deny_json "SDX mo-hook: .mesh/endpoint.yaml и .mesh/cursors.json пишет узел МО, не dev-agent (MO-INTEROP §0). Запись остановлена."   # MO-GUARD
    ;;
esac

# --- Run the sim-kit hook.
command -v python3 >/dev/null 2>&1 || cannot_check "python3 не найден"
[ -f "$hook" ] || cannot_check "хук sim-kit не найден ($hook)"   # MO-HOOKFILE (python3 exits 2 on a missing script: it would pass for a block)
err="$(PYTHONDONTWRITEBYTECODE=1 CLAUDE_PROJECT_DIR="$proj" MESH_ENDPOINT_DIR="$proj" python3 "$hook" 2>&1 >/dev/null <<<"$input")"; rc=$?   # MO-BYTECODE MO-STDIN

# --- Translate the exit code.
case "$rc" in
  0)
    [ -n "$err" ] && printf '%s\n' "$err" >&2
    exit 0 ;;
  2)
    deny_json "${err:-SDX mo-hook: хук sim-kit завершился кодом 2 без причины}" ;;   # MO-TRANSLATE
  *)
    nl=$'\n'
    last="${err##*"$nl"}"
    cannot_check "хук sim-kit завершился кодом $rc: ${last:0:200}" ;;
esac
