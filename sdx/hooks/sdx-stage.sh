#!/usr/bin/env bash
# SDX sdx-stage (REQ-SCALE-1..9, REQ-FLAG-1..4, REQ-LEGAL-1..4, REQ-COMPAT-1..3, REQ-NAV-1..2):
# the SOLE writer of `.stage` in session_state.json. NOT a hooks.json hook (no PreToolUse
# matcher) — a CLI called by /sdx:* commands via the Bash tool, the same pattern already
# used for archive-verify.sh <id>. Subcommands: init | next.
#
# ADR-020 replaces the former two-dimensional stage matrix with a single, canonical ordered
# table of stage names (SDX_STAGE_TABLE) — one row per stage, no second dimension. Ceremony
# scaling that used to be a choice of matrix ROW is now expressed by two orthogonal boolean
# flags (no_code, no_gates) plus "fold-credit" evidence (change_note.md standing in for a
# planning-stage's own artifact) — see stage_row()/gate_ok() below. The former dedicated
# subcommands for switching profiles/going back are gone: `next --to <stage>` covers the
# sole surviving navigational need (moving back to an earlier, already-visited stage).
#
# By design (DESIGN.md "Обработка ошибок"), this script accepts <sid> as an explicit
# argument and does NOT resolve the git branch itself (symmetric with archive-verify.sh) —
# it has nothing to resolve, the caller already knows which session it is acting on.
# lib/resolve-session.sh is therefore intentionally NOT sourced here.
set -uo pipefail

# jq is required for every subcommand (state is always read/written as JSON). This script
# is fail-CLOSED without jq: it is the sole writer of `stage`, so refusing to touch the
# file when it cannot safely parse/write JSON is the only way to guarantee no silent
# corruption. Checked before subcommand dispatch.
command -v jq >/dev/null 2>&1 || {
  echo "SDX sdx-stage: jq не найден — переход отклонён (fail-closed), файл не изменён. Установите jq." >&2
  exit 2
}

proj="${CLAUDE_PROJECT_DIR:-.}"

# ---------------------------------------------------------------------------------------
# Machine-readable source of truth for the canonical stage order and gate artifacts
# (REQ-SCALE-1). sdx/protocol.md keeps a human-readable projection of the same data,
# verified by a sanity test (REQ-TEST-1) — it is NOT read by this script; this table is
# authoritative.
#
# Row format: stage|artifact|fail_marker|foldable
#   artifact    — path relative to the session directory; "-" = gate not objectively
#                 checkable (the condition stays a prosaic judgement of the orchestrator).
#   fail_marker — "yes": additionally requires absence of "^### \[FAIL\]" in the artifact
#                 (reviewer output format, agents/reviewer.md); "no" — existence+non-empty
#                 only.
#   foldable    — "yes": this stage is ALSO (regardless of its own artifact) satisfied by a
#                 non-empty change_note.md — generalization of the former "Change" stage
#                 special-case (ADR-016, W-6) onto all four "planning" stages. "no" — only
#                 the stage's own artifact counts (for "-" there is no gate at all; for
#                 Verification it must be exactly verification_report.md, never
#                 change_note.md).
# Row order = the canonical stage order (REQ-SCALE-1) — the SAME order cross-checked
# against sdx/protocol.md by the REQ-TEST-1 sanity test.
# ---------------------------------------------------------------------------------------
SDX_STAGE_TABLE='
Discovery|context_report.md|no|yes
Business Spec|SPEC.md|no|yes
Technical Design|DESIGN.md|no|yes
Task Planning|PLAN.md|no|yes
Execution|-|no|no
Documentation|-|no|no
Verification|verification_report.md|yes|no
Deployment|-|no|no
Closeout|-|no|no
'

# ---- table helpers ----------------------------------------------------------------------

# stage_names() -> newline-separated list of the nine canonical stage names, in order.
stage_names() {
  printf '%s\n' "$SDX_STAGE_TABLE" | awk -F'|' '$1{print $1}'
}

# stage_row <stage> -> "artifact|fail_marker|foldable", empty if <stage> is not canonical.
# NOTE: the `$1 &&` guard is required, not cosmetic — SDX_STAGE_TABLE is a heredoc-style
# string starting with a newline, so awk's first record has an empty $1. Without the guard,
# stage_row("") would match that empty leading record instead of correctly returning empty
# (see stage_exists() below for the same asymmetry, which was an actual production bug).
stage_row() {
  printf '%s\n' "$SDX_STAGE_TABLE" | awk -F'|' -v s="$1" '$1 && $1==s{print $2"|"$3"|"$4; exit}'
}

# stage_index <stage> -> 1-based position within the canonical order, empty if not found.
stage_index() {
  printf '%s\n' "$SDX_STAGE_TABLE" | awk -F'|' -v s="$1" '$1{i++; if($1==s){print i; exit}}'
}

# stage_exists <stage> -> exit 0 if <stage> is one of the nine canonical names, exit 1
# otherwise.
# NOTE (bug found by QA at Verification): SDX_STAGE_TABLE is a heredoc-style string that
# starts with a newline, so its first awk record has an empty $1. The old pattern `$1==s`
# was unconditional, so stage_exists("") matched that empty leading record and reported the
# empty string as an existing stage — `next` (forward mode, no --to) would then silently
# "heal" a corrupted/absent `.stage` by treating index 0+1=1 as a valid candidate (Discovery)
# instead of diagnosing REQ-COMPAT-3. The `$1 &&` guard makes this symmetric with
# stage_names()/stage_index() below, which already skip the empty leading record correctly.
stage_exists() {
  printf '%s\n' "$SDX_STAGE_TABLE" | awk -F'|' -v s="$1" '$1 && $1==s{f=1} END{exit !f}'
}

# is_excluded_by_no_code <stage> -> exit 0 if no_code==true excludes <stage> unconditionally
# (REQ-SCALE-4). A fixed set of names, NOT a column of SDX_STAGE_TABLE — see DESIGN.md
# "SDX_STAGE_TABLE" section, alternative 2: keeping this as a table column would
# re-introduce the dimensionality growth this design removes.
is_excluded_by_no_code() {
  case "$1" in
    "Task Planning"|Execution|Documentation|Deployment) return 0 ;;
    *) return 1 ;;
  esac
}

# gate_ok <stage> <sdir> -> exit 0 if <stage>'s own gate is objectively satisfied on disk,
# exit 1 otherwise. Successor of the old stage_artifact_ok: was a special case only for
# "Change"; now generalized via the `foldable` column to any of the four planning stages
# (REQ-SCALE-3, ADR-016 W-6 generalized).
gate_ok() {
  local stage="$1" sdir="$2" row artifact fail_marker foldable path
  row="$(stage_row "$stage")"
  IFS='|' read -r artifact fail_marker foldable <<<"$row"
  [ "$artifact" = "-" ] && return 0
  path="$sdir/$artifact"
  if [ -s "$path" ]; then
    [ "$fail_marker" = "yes" ] && grep -q '^### \[FAIL\]' "$path" && return 1
    return 0
  fi
  [ "$foldable" = "yes" ] && [ -s "$sdir/change_note.md" ] && return 0
  return 1
}

# ---- atomic state mutation (DESIGN.md "Механика записи stage (атомарность)") -----------

# write_stage <new-stage>
# Operates on the global $state (set by the caller before invocation). mktemp is created
# in the SAME directory as $state so `mv` is an atomic rename on the same filesystem — no
# window of partial writes visible to another process/turn. Any failure -> exit 2, temp
# file removed, original untouched.
write_stage() {
  local new="$1" tmp
  tmp="$(mktemp "${state}.XXXXXX")" || {
    echo "SDX sdx-stage: не удалось создать временный файл рядом с $state." >&2
    exit 2
  }
  if ! jq --arg s "$new" '.stage = $s' "$state" > "$tmp"; then
    rm -f "$tmp"
    echo "SDX sdx-stage: jq не смог обновить $state — файл НЕ изменён." >&2
    exit 2
  fi
  mv "$tmp" "$state"
}

# log_line <message>
# Appends a timestamped line to the global $log (session.log), creating it if absent.
# Called immediately after write_stage/state creation so the transition and its log entry
# land in the same script invocation — never a separate round-trip that could desync.
log_line() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$log"
}

# mark_outdated <path> <target-stage>
# HTML-comment banner inserted as the FIRST line of the artifact — the file is never
# renamed/moved/truncated. Idempotent: a file already carrying the banner (checked in the
# first 200 bytes) is left untouched and does not print an OUTDATED line, so repeated
# `next --to` calls (including two different foldable stages pointing at the same
# change_note.md) never duplicate the marker.
mark_outdated() {
  local f="$1" tgt="$2"
  [ -f "$f" ] || return 0
  head -c 200 "$f" | grep -q '<!-- SDX-OUTDATED' && return 0
  local tmp
  tmp="$(mktemp "${f}.XXXXXX")" || return 1
  { printf '<!-- SDX-OUTDATED: устарело откатом /sdx:next --to "%s" (%s). Актуализируйте перед продолжением; история версии — `git log -p -- %s`. -->\n\n' \
      "$tgt" "$(date '+%Y-%m-%d %H:%M:%S')" "$f"
    cat "$f"
  } > "$tmp" && mv "$tmp" "$f"
  echo "OUTDATED: $f"
}

# ---- subcommands --------------------------------------------------------------------------

# init <sid> <type> <stage> <gate_mode> <git_branch> <no_code> <no_gates>
# Sole legitimate creator of session_state.json (REQ-FLAG-1). Refuses to run if the file
# already exists (exit 2 — init is not for re-initialization). Unlike the old
# two-dimensional matrix, there is no "first active stage of a profile" to validate
# against — any of the nine canonical names is a legitimate starting point, subject only
# to the two flag constraints below (REQ-SCALE-9: activity is never declared up front).
cmd_init() {
  if [ "$#" -ne 7 ]; then
    echo "SDX sdx-stage: использование: sdx-stage.sh init <sid> <type> <stage> <gate_mode> <git_branch> <no_code> <no_gates>" >&2
    exit 2
  fi
  local sid="$1" type="$2" stage="$3" gate_mode="$4" git_branch="$5" no_code="$6" no_gates="$7"
  sdir="$proj/.claude/sessions/$sid"
  state="$sdir/session_state.json"
  log="$sdir/session.log"

  # Step 1: no_code/no_gates literals.
  case "$no_code" in
    true|false) ;;
    *) echo "SDX sdx-stage: no_code должен быть 'true' или 'false', получено '$no_code'." >&2; exit 2 ;;
  esac
  case "$no_gates" in
    true|false) ;;
    *) echo "SDX sdx-stage: no_gates должен быть 'true' или 'false', получено '$no_gates'." >&2; exit 2 ;;
  esac

  # Step 2 (REQ-FLAG-3): both flags true is a contradiction, not just a disallowed
  # combination — no_gates is specifically about code ("один промпт без церемонии" with
  # code as output), while no_code excludes code by definition.
  if [ "$no_code" = "true" ] && [ "$no_gates" = "true" ]; then
    echo "SDX sdx-stage: no_code и no_gates не могут оба быть true — предмет no_gates специфичен про код, no_code по определению код исключает." >&2
    exit 2
  fi

  # Step 3: <stage> must be one of the nine canonical names.
  if ! stage_exists "$stage"; then
    echo "SDX sdx-stage: '$stage' не распознан как имя этапа протокола SDX." >&2
    exit 2
  fi

  # Step 4 (REQ-SCALE-5): no_gates==true has exactly one legitimate starting stage.
  if [ "$no_gates" = "true" ] && [ "$stage" != "Execution" ]; then
    echo "SDX sdx-stage: no_gates=true допускает старт исключительно на 'Execution' (получено '$stage')." >&2
    exit 2
  fi

  # Step 5 (REQ-SCALE-4): no_code==true excludes starting on an excluded stage — nothing
  # to execute/plan/deploy without code.
  if [ "$no_code" = "true" ] && is_excluded_by_no_code "$stage"; then
    echo "SDX sdx-stage: no_code=true исключает старт на этапе '$stage' — этап недоступен при no_code." >&2
    exit 2
  fi

  # Step 6: file already exists -> exit 2 (unchanged, as before).
  if [ -f "$state" ]; then
    echo "SDX sdx-stage: session_state.json для сессии '$sid' уже существует — init не предназначен для повторной инициализации." >&2
    exit 2
  fi

  mkdir -p "$sdir"
  if ! jq -n \
        --arg session_id "$sid" --arg type "$type" --arg stage "$stage" \
        --arg gate_mode "$gate_mode" --arg git_branch "$git_branch" \
        --argjson no_code "$no_code" --argjson no_gates "$no_gates" \
        '{session_id:$session_id, type:$type, stage:$stage, gate_mode:$gate_mode, git_branch:$git_branch, no_code:$no_code, no_gates:$no_gates, artifacts:[], history:[]}' \
        > "$state"; then
    rm -f "$state"
    echo "SDX sdx-stage: jq не смог создать $state." >&2
    exit 2
  fi

  log_line "[START] Инициализация сессии $sid"
  echo "OK - -> $stage"
}

# next <sid> [--to <stage>]
# Two modes of one subcommand, distinguished by the presence of --to.
cmd_next() {
  local sid="$1"; shift
  local to_target="" has_to=0
  if [ "${1:-}" = "--to" ]; then
    has_to=1
    if [ "$#" -ne 2 ]; then
      echo "SDX sdx-stage: использование: sdx-stage.sh next <sid> [--to <stage>]" >&2
      exit 2
    fi
    to_target="$2"
  elif [ "$#" -ne 0 ]; then
    echo "SDX sdx-stage: использование: sdx-stage.sh next <sid> [--to <stage>]" >&2
    exit 2
  fi

  sdir="$proj/.claude/sessions/$sid"
  state="$sdir/session_state.json"
  log="$sdir/session.log"

  [ -f "$state" ] || {
    echo "SDX sdx-stage: не найден session_state.json для сессии '$sid' — вызовите /sdx:start или /sdx:import." >&2
    exit 2
  }

  local no_gates no_code stage
  no_gates="$(jq -r '.no_gates // false' "$state" 2>/dev/null || echo 'false')"
  no_code="$(jq -r '.no_code // false' "$state" 2>/dev/null || echo 'false')"
  stage="$(jq -r '.stage // empty' "$state")"

  # ---- Priority 0 (REQ-LEGAL-1) — checked FIRST, before parsing --to or reading anything
  # else. This is the entire mechanism that keeps ADR-018's "no Closeout without
  # legalization" invariant alive without a matrix row to lean on: while no_gates==true,
  # NOTHING below this block ever executes. ----
  if [ "$no_gates" = "true" ]; then
    if [ "$has_to" -eq 1 ] && [ "$to_target" != "Execution" ]; then
      echo "SDX sdx-stage: сессия в режиме «без гейтов» (no_gates) — доступен только этап Execution; выход исключительно через легализацию /sdx:proto." >&2
      exit 1
    fi
    echo "OK no-op Execution"
    return 0
  fi

  # ---- --to mode (REQ-NAV-1, the sole surviving way to move to an earlier stage) ----
  if [ "$has_to" -eq 1 ]; then
    if ! stage_exists "$to_target"; then
      echo "SDX sdx-stage: '$to_target' не распознан как имя этапа протокола SDX. Проверь опечатку." >&2
      exit 1
    fi

    # REQ-SCALE-4 (unconditional exclusion, direction-independent): --to must not be able to
    # land a no_code==true session on an excluded stage just because the move happens to be a
    # backtrack — the exclusion is not a property of direction, it is a property of the
    # target stage. Without this check, `next --to "Execution"` would silently succeed on a
    # no_code session even though `init`/forward `next` both refuse the same stage.
    if [ "$no_code" = "true" ] && is_excluded_by_no_code "$to_target"; then
      echo "SDX sdx-stage: no_code=true исключает этап '$to_target' из активного набора (REQ-SCALE-4) — переход --to на этот этап недоступен." >&2
      exit 1
    fi

    local idx_target idx_current
    idx_target="$(stage_index "$to_target")"
    idx_current="$(stage_index "$stage")"
    if [ -z "$idx_current" ]; then
      echo "SDX sdx-stage: состояние сессии '$sid' использует нераспознанное/устаревшее имя этапа '$stage' — требуется ручная миграция (REQ-COMPAT-3), автоматический переход невозможен." >&2
      exit 2
    fi

    if [ "$idx_target" -gt "$idx_current" ]; then
      echo "SDX sdx-stage: '$to_target' позже текущего этапа '$stage' в каноническом порядке — это не откат. Для движения вперёд используй /sdx:next без аргумента." >&2
      exit 1
    fi

    if [ "$idx_target" -eq "$idx_current" ]; then
      echo "OK no-op $stage"
      return 0
    fi

    write_stage "$to_target"
    log_line "[STAGE_CHANGE] Возврат на этап $to_target"
    echo "OK $stage -> $to_target"

    # Mark every stage strictly after the target, through the end of the canonical order,
    # as outdated — NOT bounded by the departing (current) stage (REQ-NAV-2; the pre-ADR-020
    # REQ-BACKTRACK-2 behaviour is preserved literally under the new requirement id).
    local i s row artifact foldable path
    i=0
    while IFS= read -r s; do
      i=$((i + 1))
      [ "$i" -le "$idx_target" ] && continue
      row="$(stage_row "$s")"
      IFS='|' read -r artifact _fm foldable <<<"$row"
      if [ "$artifact" != "-" ]; then
        path="$sdir/$artifact"
        mark_outdated "$path" "$to_target"
      fi
      if [ "$foldable" = "yes" ]; then
        mark_outdated "$sdir/change_note.md" "$to_target"
      fi
    done < <(stage_names)
    return 0
  fi

  # ---- forward mode (plain next, plus hidden no_code auto-skip) ----
  # REQ-COMPAT-3: an unrecognized/legacy current stage (Change/Update/Prototype) cannot be
  # advanced automatically — diagnose it explicitly (exit 2) instead of letting gate_ok's
  # empty-row lookup produce an undefined result.
  if ! stage_exists "$stage"; then
    echo "SDX sdx-stage: состояние сессии '$sid' использует нераспознанное/устаревшее имя этапа '$stage' — требуется ручная миграция (REQ-COMPAT-3), автоматический переход невозможен." >&2
    exit 2
  fi

  local last
  last="$(stage_names | tail -1)"
  if [ "$stage" = "$last" ]; then
    echo "OK no-op $stage"
    return 0
  fi

  if ! gate_ok "$stage" "$sdir"; then
    local row artifact fail_marker foldable
    row="$(stage_row "$stage")"
    IFS='|' read -r artifact fail_marker foldable <<<"$row"
    if [ "$artifact" != "-" ] && [ -s "$sdir/$artifact" ] && [ "$fail_marker" = "yes" ] \
       && grep -q '^### \[FAIL\]' "$sdir/$artifact"; then
      local fix_stage="Execution"
      [ "$no_code" = "true" ] && fix_stage="Technical Design"
      echo "SDX sdx-stage: гейт не пройден — '$artifact' содержит находки FAIL. Исправь их и вызови /sdx:next --to \"$fix_stage\"." >&2
      exit 1
    fi
    local alt=""
    [ "$foldable" = "yes" ] && alt=" (либо непустой change_note.md)"
    echo "SDX sdx-stage: гейт не пройден — не найден/пуст '$artifact'$alt в .claude/sessions/$sid/. Заверши $stage, затем повтори /sdx:next." >&2
    exit 1
  fi

  local idx candidate
  idx="$(stage_index "$stage")"
  candidate="$(stage_names | sed -n "$((idx + 1))p")"
  while [ "$no_code" = "true" ] && is_excluded_by_no_code "$candidate" && [ "$candidate" != "Closeout" ]; do
    idx=$((idx + 1))
    candidate="$(stage_names | sed -n "$((idx + 1))p")"
  done

  write_stage "$candidate"
  log_line "[STAGE_CHANGE] Переход на этап $candidate"
  echo "OK $stage -> $candidate"
}

# ---- dispatcher ---------------------------------------------------------------------------

sub="${1:-}"
case "$sub" in
  init)
    shift
    cmd_init "$@"
    ;;
  next)
    shift
    if [ "$#" -lt 1 ]; then
      echo "SDX sdx-stage: использование: sdx-stage.sh next <sid> [--to <stage>]" >&2
      exit 2
    fi
    cmd_next "$@"
    ;;
  *)
    echo "SDX sdx-stage: использование: sdx-stage.sh <init|next> <args...>" >&2
    exit 2
    ;;
esac
