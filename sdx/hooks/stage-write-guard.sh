#!/usr/bin/env bash
# SDX stage-write-guard (REQ-DENY-1..4): the deny half of the deterministic `stage`
# owner (sdx-stage.sh is the write half — see DESIGN.md "Deny-хук stage-write-guard.sh").
# PreToolUse hook for Write|Edit|MultiEdit — third entry in the shared matcher that
# already carries stage-gate.sh. Blocks via JSON permissionDecision:"deny" on stdout,
# exit 0. NOT exit 2 (same contract as stage-gate.sh/prod-guard.sh).
#
# Structural note (DESIGN.md "Архитектурный обзор"): sdx-stage.sh mutates
# session_state.json via Bash (mktemp/jq/mv), never via Write/Edit/MultiEdit — so the
# legitimate writer is physically outside this hook's matcher, not a special case this
# hook has to recognize and skip.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# TODO(shared refactor, DESIGN.md "Общая библиотека lib/resolve-session.sh"): this hook
# and sdx-stage.sh use the shared resolver from day one; stage-gate.sh/stop-gate.sh still
# inline their own branch resolution (tracked as a separate, non-blocking refactor task).
. "$here/lib/resolve-session.sh"

input="$(cat)"
proj="${CLAUDE_PROJECT_DIR:-.}"
proj="${proj//\\//}"

# deny() — emit JSON block decision to stdout and exit 0. Same jq -Rs escaping pattern
# as stage-gate.sh/prod-guard.sh, copied verbatim (not reinvented).
deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}' \
    "$(printf '%s' "$1" | jq -Rs .)"
  exit 0
}

# Resolve the active SDX session from the branch name (pure bash, no jq needed).
sid="$(resolve_sid "$proj")"
[ -z "$sid" ] && exit 0   # not an SDX branch -> hook is transparent (REQ-DENY-3)

state="$proj/.claude/sessions/${sid}/session_state.json"
state="${state//\\//}"

# Decide the jq-availability path once, up front. jq is the normal way to pull
# `tool_input.file_path` out of the hook's stdin JSON; without it we fall back to a
# coarse grep/sed extraction of just that one field. This is a deliberate deviation
# from the single-line DESIGN pseudocode (which shows a bare `jq -r ...` for target
# extraction): without a jq-independent way to learn *which* file is being written,
# the later "jq missing" branch could never be reached for an operation that actually
# targets an existing session's session_state.json (it would silently no-op instead,
# via `jq: command not found` -> empty target -> early exit, with no warning printed).
# The fallback keeps DESIGN's intended ordering optimization (stay silent for
# operations unrelated to $state, whether or not jq is installed) while still
# guaranteeing the loud fail-open warning fires exactly when REQ-DENY-4 requires it.
if command -v jq >/dev/null 2>&1; then
  HAVE_JQ=1
  target="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
else
  HAVE_JQ=0
  target="$(printf '%s' "$input" \
    | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | head -1 \
    | sed -E 's/^"file_path"[[:space:]]*:[[:space:]]*"//; s/"$//')"
fi
[ -z "$target" ] && exit 0   # no file path in input -> nothing to gate

# Normalize separators (BUG-006 pattern): Windows file_path arrives with backslashes.
target="${target//\\//}"

[ "$target" != "$state" ] && exit 0   # hook is specific to THIS file, exact path match

# Primary creation is not blocked (REQ-DENY-2): no file on disk yet -> this is a
# create, not an edit. Defense-in-depth on top of start.md/import.md already creating
# the file via `sdx-stage.sh init` (a Bash call, entirely outside this hook's matcher).
[ -f "$state" ] || exit 0

# From here the operation demonstrably targets an EXISTING session_state.json of an
# active SDX session -> jq's absence now actually matters (the same ordering
# optimization prod-guard.sh applies to its own conf-existence check: don't pay the
# fail-open-warning noise where it isn't relevant).
if [ "$HAVE_JQ" -eq 0 ]; then
  echo "SDX stage-write-guard: jq недоступен — защита поля 'stage' временно ОТКЛЮЧЕНА (fail-open), правка session_state.json НЕ проверяется. Установите jq." >&2
  exit 0
fi

tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
old_stage="$(jq -r '.stage // empty' "$state" 2>/dev/null)"

# Rough regex for the Edit/MultiEdit path (DESIGN.md "Edit/MultiEdit (огрублённый
# путь)"): key-pattern match only, not a value comparison — a touched fragment need
# not be valid JSON on its own (it can be a partial string inside a larger object).
STAGE_KEY_RE='"stage"[[:space:]]*:'
touches_stage() {   # $1 = new_string fragment
  printf '%s' "$1" | grep -Eq "$STAGE_KEY_RE"
}

case "$tool_name" in
  Write)
    # Exact path (DESIGN.md "Write (точный путь)"): the full new file content is
    # available -> parse and compare .stage precisely.
    content="$(printf '%s' "$input" | jq -r '.tool_input.content // empty')"
    new_stage="$(printf '%s' "$content" | jq -r '.stage // empty' 2>/dev/null)"
    new_stage_rc=$?
    if [ "$new_stage_rc" -ne 0 ]; then
      deny "SDX stage-write-guard: новое содержимое session_state.json не распознано как валидный JSON — запись заблокирована (не могу доказать, что 'stage' не меняется). Пишите валидный JSON или используйте sdx-stage.sh."
    fi
    if [ "$new_stage" != "$old_stage" ]; then
      deny "SDX stage-write-guard: правка поля 'stage' ($old_stage → $new_stage) в обход механизма перехода заблокирована. Используйте /sdx:next, /sdx:backtrack, /sdx:retrack или /sdx:archive — они переводят stage через sdx-stage.sh с проверкой гейта."
    fi
    ;;
  Edit)
    new_string="$(printf '%s' "$input" | jq -r '.tool_input.new_string // empty')"
    if touches_stage "$new_string"; then
      deny "SDX stage-write-guard: правка задевает ключ 'stage' в session_state.json в обход механизма перехода. Используйте /sdx:next, /sdx:backtrack, /sdx:retrack или /sdx:archive — они переводят stage через sdx-stage.sh с проверкой гейта."
    fi
    ;;
  MultiEdit)
    # Any single edit touching `stage` blocks the whole batch (MultiEdit is atomic at
    # the tool level, symmetric with how stage-gate.sh already treats a single
    # file_path — see DESIGN.md "Edit/MultiEdit (огрублённый путь)").
    while IFS= read -r ns; do
      if touches_stage "$ns"; then
        deny "SDX stage-write-guard: одна из правок MultiEdit задевает ключ 'stage' в session_state.json — вся пачка заблокирована в обход механизма перехода. Используйте /sdx:next, /sdx:backtrack, /sdx:retrack или /sdx:archive — они переводят stage через sdx-stage.sh с проверкой гейта."
      fi
    done < <(printf '%s' "$input" | jq -r '.tool_input.edits[]?.new_string // empty')
    ;;
  *)
    exit 0
    ;;
esac

exit 0
