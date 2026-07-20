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
# coarse grep/sed extraction of just that one field.
#
# This is a deliberate deviation from DESIGN.md's "Резолюция сессии и цели" pseudocode,
# which shows a single bare `jq -r '.tool_input.file_path // empty'` with no fallback —
# i.e. DESIGN implicitly assumes jq is always present for this step. Reusing that
# pseudocode literally here would mean: no jq -> `jq: command not found` on stderr,
# empty $target, `[ -z "$target" ] && exit 0` fires -> the hook silently no-ops for
# EVERY Write/Edit/MultiEdit, including ones that genuinely target an existing
# session's session_state.json. That collapses this hook's "jq missing" branch below
# (the one required by REQ-DENY-4 to print a loud fail-open warning) into dead code: it
# would never run, because we'd already have bailed out one step earlier for lack of a
# target. The grep/sed fallback exists ONLY to keep that ordering optimization working
# (stay silent for operations that don't touch $state at all, jq present or not) while
# still reaching the REQ-DENY-4 warning exactly when the operation DOES target $state.
#
# Known, accepted weaker spot of this fallback (verification_report.md finding W-6):
# unlike `jq -r`, the grep/sed extraction does not decode JSON string escapes. A
# Windows-style file_path arrives JSON-escaped (each real "\" is written as two
# characters, `\\`, in the raw request text). `jq -r` unescapes that back to a single
# "\" before we hand it to the `target="${target//\\//}"` normalizer below, which then
# yields a single "/". The grep/sed path instead captures the still-escaped two-character
# sequence verbatim, so the same normalizer turns each real backslash into TWO
# forward slashes instead of one — the resulting $target no longer exact-matches
# $state, and the hook silently no-ops for that specific combination (Windows path +
# no jq). This is strictly a fail-open gap (REQ-DENY-4's own contract already accepts
# fail-open without jq), not a new safety hole introduced by the fallback — it is
# documented here rather than in DESIGN.md because it only affects the already-degraded
# no-jq path, not the primary detection logic.
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

# normalize_path <path> — collapse "/./" segments and duplicate slashes so a
# semantically-identical path spelled differently still exact-matches $state
# (verification_report.md WARN-3). Applied to both sides so $state itself (built
# from $proj, which callers could also hand us with such segments) is covered too.
# Deliberately NOT a full canonicalizer: it does not resolve ".." and does not turn
# a relative path into an absolute one (that would require guessing a cwd this
# hook has no reliable way to know). Left as a documented, accepted gap — the
# Write/Edit/MultiEdit tool contract requires file_path to already be absolute, so
# a genuinely relative $target is considered practically unreachable in practice.
normalize_path() {
  local p="$1"
  while [[ "$p" == *"/./"* ]]; do p="${p//\/.\//\/}"; done
  while [[ "$p" == *"//"* ]]; do p="${p//\/\//\/}"; done
  printf '%s' "$p"
}
target="$(normalize_path "$target")"
state="$(normalize_path "$state")"

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

# is_valid_json <content>
#   True (exit 0) iff <content> is a well-formed JSON document — INCLUDING the scalar
#   documents `null` and `false` (verification_report.md finding W-4 part 1).
#
#   Deliberately NOT `jq -e .`: with `-e`, jq's exit status reports the TRUTHINESS of the
#   last emitted value (0 = neither null nor false, 1 = null or false, 4 = no output,
#   5 = parse error), not whether parsing succeeded. That conflates "this content is
#   broken JSON" with "this content is the well-formed JSON value null/false" — a state
#   file containing literally `null` was misclassified as corrupted and fell into the
#   recovery carve-outs below, silently waiving the `stage` check for that write/edit.
#
#   Also deliberately NOT bare `jq .`/`jq empty` on the raw content: jq treats a
#   completely empty (zero-byte) or whitespace-only input as trivially valid (there is no
#   document to reject, so the filter just never runs and exits 0) — a truncated/empty
#   session_state.json would then be misclassified as "not corrupted" and become subject
#   to the full stage-value comparison instead of the recovery carve-out. An empty file
#   is NOT itself a well-formed JSON document (RFC 8259 requires at least one value), and
#   this hook already treated it as corrupted before this fix (`jq -e .` on empty input
#   exits 4, i.e. non-zero) — that classification is preserved here explicitly rather
#   than left to jq's no-input special case, so this decision doesn't silently flip if
#   the parsing primitive underneath ever changes again.
#
#   Scope note (this is the "how narrow is the carve-out" half of W-4): jq is fed via a
#   piped stdin here, never via argv/ENVIRON, so this check cannot fail the way
#   literal_replace's awk call can (WARN-1, ARG_MAX/E2BIG) — its only two outcomes are
#   "well-formed JSON" and "not" (empty content counted as "not", per above). It cannot
#   return a third "tool failed, can't tell" outcome the way literal_replace can, so
#   there is no ambiguous case here that needs a tool_failure_deny()-style fallback.
is_valid_json() {
  local content="$1" stripped
  stripped="$(printf '%s' "$content" | tr -d '[:space:]')"
  [ -z "$stripped" ] && return 1
  printf '%s' "$content" | jq empty >/dev/null 2>&1
}

# --- Edit/MultiEdit detection (post F-2 fix) ---------------------------------------
# Superseded mechanism (DESIGN.md "Edit/MultiEdit (огрублённый путь)"): regex-match the
# literal key pattern `"stage"[[:space:]]*:` inside the *fragment* (new_string), never
# looking at the file itself. verification_report.md finding F-2 showed this has a
# realistic false negative: a fully ordinary `Edit(old_string:"\"Execution\"",
# new_string:"\"Closeout\"")` changes the value without the key substring ever
# appearing in either string, and sailed through undetected — exactly the kind of
# accidental bypass REQ-DENY-1 exists to close.
#
# Fix: for Edit/MultiEdit we now APPLY the edit(s) to the real current file content
# (read once as `$state`'s bytes) and compare the PARSED `.stage` value before vs.
# after — the same precise technique `Write` already uses, just derived from a
# simulated post-edit document instead of a supplied whole one. Matching by parsed
# value, not by any textual pattern, is the only way to be robust regardless of which
# substring the edit happens to touch (DESIGN's "уникальность значения `stage` в
# плоском файле" observation only helps a substring-matching approach; it says nothing
# about the KEY being present in the touched fragment, which is what F-2 exploited).
#
# literal_replace <content> <search> <replace> <all>
#   Emulates the Edit tool's own substitution semantics: a plain (non-regex) substring
#   replacement of `search` with `replace` inside `content` — the FIRST occurrence only
#   unless <all> is "1" (mirrors `tool_input.replace_all`), in which case every
#   occurrence is replaced, left to right, non-overlapping. Prints the resulting
#   content on stdout and exits 0 if `search` was found at least once; if `search` was
#   never found (or is empty), prints nothing and exits 1 — the same situation in which
#   the REAL Edit tool call would itself fail before writing anything, so the caller
#   must treat "not found" as "nothing to gate", not as "deny".
#   Implemented via awk (not bash `${var//search/replace}`) because that bash construct
#   treats `search` as a glob pattern (`*`, `?`, `[` are special), which would silently
#   misbehave on JSON fragments containing those characters; awk's index()/substr() do
#   a byte-for-byte literal search with no such reinterpretation.
#   Exit-code contract (verification_report.md WARN-1): the awk BEGIN block above never
#   itself exits with anything other than 0 (found) or 1 (not found/empty search) — those
#   are the only two `exit` statements it contains. `$content` is passed through an
#   ENVIRON variable, and on Linux a single env string longer than ~128 KiB (or a total
#   argv+envp over ARG_MAX) makes the `awk` *process itself* fail to start — a TOOL
#   failure (typically exit 126, "Argument list too long" on stderr), not a search
#   result. Because that failure happens before awk's own code runs at all, it can never
#   produce 0 or 1 — so any exit code the caller sees OTHER than 0 or 1 is unambiguously
#   "the tool could not compute an answer", never "search wasn't found". Callers MUST
#   treat that third case as "cannot prove `stage` didn't change" -> deny (same stance
#   already taken for unparseable JSON), not silently fall through to "nothing to gate".
literal_replace() {
  SWG_CONTENT="$1" SWG_SEARCH="$2" SWG_REPLACE="$3" SWG_ALL="$4" awk '
    BEGIN {
      content = ENVIRON["SWG_CONTENT"]
      search  = ENVIRON["SWG_SEARCH"]
      replace = ENVIRON["SWG_REPLACE"]
      all     = ENVIRON["SWG_ALL"]
      if (search == "") { exit 1 }
      slen = length(search)
      pos = 1
      out = ""
      found = 0
      while (1) {
        rest = substr(content, pos)
        idx = index(rest, search)
        if (idx == 0) { out = out rest; break }
        found = 1
        out = out substr(rest, 1, idx - 1) replace
        pos = pos + idx - 1 + slen
        if (all != "1") { out = out substr(content, pos); break }
      }
      if (!found) { exit 1 }
      printf "%s", out
      exit 0
    }
  '
}

# check_stage_change <content_before> <content_after>
#   Parses `.stage` out of both blobs (jq) and denies iff the value actually changed.
#   Recovery carve-out (verification_report.md WARN-2 fix): checked FIRST, unconditionally
#   on `before` alone. If `content_before` was already NOT well-formed JSON (the state
#   file was corrupt before this operation even ran — see is_valid_json() above for the
#   precise, narrow definition of "corrupt" this uses), we do NOT block, regardless of
#   what `content_after` looks like — this hook's job is to guard legitimate `stage`
#   transitions of a well-formed file, not to arbitrate recovery of an already-broken
#   one, and blocking here (even when `after` happens to be a valid repair) would remove
#   the only remaining way (Edit/Write) to fix it — the same self-defeating trap
#   REQ-DENY-4 already rejected for the no-jq case. (Previously this carve-out was only
#   reachable when `after` was ALSO unparseable, so the one case anyone actually cares
#   about — before broken, after repaired — fell through to the generic comparison below
#   and got denied; that was the bug.)
#   Past that carve-out: if `content_after` fails to parse as JSON (while `before` DID
#   parse), that is itself suspicious — an edit that turns a well-formed
#   session_state.json into garbage — and we deny defensively: we cannot prove `stage`
#   didn't change, and letting a Write/Edit corrupt the ONE file every SDX transition
#   mechanism depends on is worse than a false-positive block (the same "prove-it-or-block"
#   stance `Write`'s exact path already takes for unparseable new content).
check_stage_change() {
  local before="$1" after="$2" new_stage new_rc
  if ! is_valid_json "$before"; then
    return 0   # was already broken before this operation -> this is the recovery path
  fi
  new_stage="$(printf '%s' "$after" | jq -r '.stage // empty' 2>/dev/null)"
  new_rc=$?
  if [ "$new_rc" -ne 0 ]; then
    deny "SDX stage-write-guard: правка делает session_state.json невалидным JSON — запись заблокирована (не могу доказать, что поле 'stage' не меняется). Пишите валидный JSON или используйте sdx-stage.sh (через /sdx:next, /sdx:backtrack, /sdx:retrack, /sdx:archive)."
  fi
  if [ "$new_stage" != "$old_stage" ]; then
    deny "SDX stage-write-guard: правка поля 'stage' ($old_stage → $new_stage) в обход механизма перехода заблокирована. Используйте /sdx:next, /sdx:backtrack, /sdx:retrack или /sdx:archive — они переводят stage через sdx-stage.sh с проверкой гейта."
  fi
}

# tool_failure_deny <exit-code>
#   Shared deny message for the WARN-1 case: literal_replace's underlying awk process
#   itself failed to run (see literal_replace's exit-code contract comment above) rather
#   than returning a normal found/not-found result. We cannot compute what the edit
#   would have done, so — same "prove-it-or-block" stance as unparseable JSON — deny.
tool_failure_deny() {
  deny "SDX stage-write-guard: не удалось вычислить результат правки (сбой инструмента, код возврата $1) — запись заблокирована (не могу доказать, что поле 'stage' не меняется). Повторите правку меньшего объёма или используйте sdx-stage.sh (через /sdx:next, /sdx:backtrack, /sdx:retrack, /sdx:archive)."
}

case "$tool_name" in
  Write)
    # Recovery carve-out (verification_report.md WARN-2, symmetric with
    # check_stage_change's carve-out below): if the file ON DISK is already not
    # well-formed JSON (see is_valid_json() above for the precise, narrow definition),
    # this Write is the recovery path -> do not block, regardless of what the new
    # content looks like. Checked first, before even parsing the new content.
    if ! is_valid_json "$(cat "$state" 2>/dev/null)"; then
      exit 0
    fi
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
    edit_old="$(printf '%s' "$input" | jq -r '.tool_input.old_string // empty')"
    edit_new="$(printf '%s' "$input" | jq -r '.tool_input.new_string // empty')"
    edit_all="$(printf '%s' "$input" | jq -r 'if (.tool_input.replace_all == true) then "1" else "0" end')"
    content_before="$(cat "$state" 2>/dev/null)"
    content_after="$(literal_replace "$content_before" "$edit_old" "$edit_new" "$edit_all")"
    lr_rc=$?
    if [ "$lr_rc" -eq 0 ]; then
      check_stage_change "$content_before" "$content_after"
    elif [ "$lr_rc" -eq 1 ]; then
      : # old_string not found in the file -> the real Edit call would itself fail
        # before writing anything (REQ-DENY-2's "changes the value" precondition can't
        # even be met) -> nothing to gate, fall through to the trailing `exit 0`.
    else
      # WARN-1: literal_replace's awk process itself failed to run (e.g. E2BIG on a
      # very large session_state.json) -> a tool failure, not a "not found" result.
      tool_failure_deny "$lr_rc"
    fi
    ;;
  MultiEdit)
    # Apply every edit SEQUENTIALLY against a running copy of the file content, exactly
    # as the real MultiEdit tool does (each edit sees the previous edit's result), then
    # compare the parsed `.stage` value once at the end — not per-edit — against the
    # value on disk before any of them ran. A single check_stage_change() call at the
    # end is enough: MultiEdit is atomic at the tool level (all edits apply or none do),
    # so what matters is the net effect on `stage`, symmetric with how `Write` already
    # only cares about the final content, not the intermediate diff.
    content_before="$(cat "$state" 2>/dev/null)"
    content_cur="$content_before"
    edits_count="$(printf '%s' "$input" | jq -r '(.tool_input.edits // []) | length')"
    all_found=1
    me_i=0
    while [ "$me_i" -lt "$edits_count" ]; do
      me_old="$(printf '%s' "$input" | jq -r --argjson i "$me_i" '.tool_input.edits[$i].old_string // empty')"
      me_new="$(printf '%s' "$input" | jq -r --argjson i "$me_i" '.tool_input.edits[$i].new_string // empty')"
      me_all="$(printf '%s' "$input" | jq -r --argjson i "$me_i" 'if (.tool_input.edits[$i].replace_all == true) then "1" else "0" end')"
      me_next="$(literal_replace "$content_cur" "$me_old" "$me_new" "$me_all")"
      lr_rc=$?
      if [ "$lr_rc" -eq 0 ]; then
        content_cur="$me_next"
      elif [ "$lr_rc" -eq 1 ]; then
        # This edit's old_string isn't in the content at this point in the sequence ->
        # the real MultiEdit call would fail atomically right here, so the whole batch
        # never writes anything -> nothing to gate for the entire operation.
        all_found=0
        break
      else
        # WARN-1: tool failure mid-batch -> cannot compute the net effect on `stage`.
        tool_failure_deny "$lr_rc"
      fi
      me_i=$((me_i + 1))
    done
    if [ "$all_found" -eq 1 ] && [ "$edits_count" -gt 0 ]; then
      check_stage_change "$content_before" "$content_cur"
    fi
    ;;
  *)
    exit 0
    ;;
esac

exit 0
