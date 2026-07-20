#!/usr/bin/env bash
# SDX sdx-stage (REQ-STAGE-1..5, REQ-BACKTRACK-1..2, REQ-RETRACK-1, REQ-CLOSEOUT-ENTRY-1):
# the SOLE writer of `.stage` in session_state.json. NOT a hooks.json hook (no PreToolUse
# matcher) — a CLI called by /sdx:* commands via the Bash tool, the same pattern already
# used for archive-verify.sh <id>. Subcommands: init | next | backtrack | retrack.
#
# By design (DESIGN.md "Обработка ошибок"), this script accepts <sid> as an explicit
# argument and does NOT resolve the git branch itself (symmetric with archive-verify.sh) —
# it has nothing to resolve, the caller already knows which session it is acting on.
# lib/resolve-session.sh is therefore intentionally NOT sourced here.
set -uo pipefail

# jq is required for every subcommand (state is always read/written as JSON). Unlike
# stage-write-guard.sh (fail-open), this script is fail-CLOSED without jq: it is the sole
# writer of `stage`, so refusing to touch the file when it cannot safely parse/write JSON
# is the only way to guarantee no silent corruption. Checked before subcommand dispatch.
command -v jq >/dev/null 2>&1 || {
  echo "SDX sdx-stage: jq не найден — переход отклонён (fail-closed), файл не изменён. Установите jq." >&2
  exit 2
}

proj="${CLAUDE_PROJECT_DIR:-.}"

# ---------------------------------------------------------------------------------------
# Machine-readable source of truth for "track -> ordered active stages -> gate artifact"
# (REQ-STAGE-3). sdx/protocol.md keeps a human-readable projection of the same data (see
# the footnote added there) — it is NOT read by this script; this matrix is authoritative.
#
# Row format: track|stage|artifact|fail_marker
#   artifact    — path relative to the session directory; "-" = gate not objectively
#                 checkable (the condition stays a prosaic judgement of the orchestrator,
#                 REQ-STAGE-2 "Ограничение").
#   fail_marker — "yes": additionally requires absence of "^### \[FAIL\]" in the artifact
#                 (reviewer output format, agents/reviewer.md); "no" — existence+non-empty
#                 only.
# Row order WITHIN a track = order of active stages (used by next/backtrack/retrack).
# ---------------------------------------------------------------------------------------
SDX_STAGE_MATRIX='
full|Discovery|context_report.md|no
full|Business Spec|SPEC.md|no
full|Technical Design|DESIGN.md|no
full|Task Planning|PLAN.md|no
full|Execution|-|no
full|Documentation|-|no
full|Verification|verification_report.md|yes
full|Deployment|-|no
full|Closeout|-|no
standard|Discovery|-|no
standard|Change|change_note.md|no
standard|Execution|-|no
standard|Verification|verification_report.md|yes
standard|Closeout|-|no
patch|Execution|change_note.md|no
patch|Verification|verification_report.md|yes
patch|Closeout|-|no
'

# ---------------------------------------------------------------------------------------
# Cross-track canonical order (REQ-RETRACK-2, WARN-4 fix). SDX_STAGE_MATRIX above gives
# ordering WITHIN a single track only; it says nothing about how a stage of track A
# compares to a differently-named stage of track B. cmd_retrack needs exactly that: a
# forward-skip guard symmetric to REQ-BACKTRACK-1, but retrack's target and the CURRENT
# stage can legitimately belong to two different tracks' naming (that is the whole point
# of retrack), so a single shared timeline is required.
#
# This is a MERGE of the three tracks' own (already mutually consistent, monotonic) row
# orders into one union sequence, given as explicit `name|rank` pairs (NOT bare positional
# lines — see the `Change` note below for why a plain 1-based line count is not enough).
# Every name here occurs in at least one track of SDX_STAGE_MATRIX; for any two names that
# occur in the SAME track, their rank order here matches that track's own row order
# (verified by test-sdx-stage.sh, which cross-checks this against the matrix the same way
# scenario "[23] sanity" already cross-checks protocol.md against the matrix).
#
# `Change` (standard/patch only) merges full's `Business Spec` + `Technical Design` into
# one stage (protocol.md "Change ... объединённый этап") — it does not correspond to a
# single POINT on this timeline, it spans a RANGE. It is given the SAME rank as `Technical
# Design` (a deliberate TIE, not "one step later" — hence the explicit rank column instead
# of a bare ordered list, where every line would necessarily get a distinct number). Tying
# it to the UPPER end of the range it merges is what makes both directions of retrack
# behave correctly:
#   - Escalating FROM `Change` (patch/standard -> full): by the time cmd_retrack runs,
#     retrack.md step 3 has ALREADY promoted change_note.md into both SPEC.md and
#     DESIGN.md (unconditionally, before step 4 calls this script) — so treating `Change`
#     as "as far along as Technical Design" is not optimistic, the artifacts backing that
#     claim already exist on disk by construction. This allows landing on `Technical
#     Design` (same rank, a lateral move) but NOT `Task Planning` (the next rank up,
#     REQ-STAGE-2's real Technical Design gate was never actually re-checked by retrack —
#     REQ-RETRACK-1 explicitly waives it — so `Task Planning` must be reached via a
#     genuine `/sdx:next` call from `Technical Design` afterwards, which DOES check it).
#   - Deescalating INTO `Change` (full -> standard/patch, from `Business Spec`,
#     `Technical Design` or `Task Planning`): the tie makes `Change` reachable from
#     `Technical Design` (equal rank) and from `Task Planning` (a backward move, always
#     allowed), but NOT from `Business Spec` alone (one rank short) — that case lands on
#     `Discovery` instead and needs one extra, gate-less `/sdx:next` (standard's
#     `Discovery` artifact is "-", so this costs nothing in practice). This is the
#     conservative side of an inherently ambiguous case, not a functional dead end.
# ---------------------------------------------------------------------------------------
SDX_CANON_ORDER='
Discovery|1
Business Spec|2
Technical Design|3
Change|3
Task Planning|4
Execution|5
Documentation|6
Verification|7
Deployment|8
Closeout|9
'

# ---- matrix helpers --------------------------------------------------------------------

# matrix_stages <track> -> newline-separated list of active stage names, in row order.
matrix_stages() {
  printf '%s\n' "$SDX_STAGE_MATRIX" | awk -F'|' -v t="$1" '$1==t{print $2}'
}

# matrix_row <track> <stage> -> "artifact|fail_marker", empty if the pair is not in the matrix.
matrix_row() {
  printf '%s\n' "$SDX_STAGE_MATRIX" | awk -F'|' -v t="$1" -v s="$2" '$1==t && $2==s{print $3"|"$4; exit}'
}

# matrix_index <track> <stage> -> 1-based position of stage within track's row order,
# empty if not found.
matrix_index() {
  printf '%s\n' "$SDX_STAGE_MATRIX" | awk -F'|' -v t="$1" -v s="$2" '$1==t{i++; if($2==s){print i; exit}}'
}

# matrix_stage_exists <stage> -> exit 0 if the stage name occurs in ANY track (union),
# exit 1 otherwise. Used by backtrack step 1 ("имя не распознано" vs "не активен в треке").
matrix_stage_exists() {
  printf '%s\n' "$SDX_STAGE_MATRIX" | awk -F'|' -v s="$1" '$2==s{f=1} END{exit !f}'
}

# canon_rank <stage> -> numeric rank of <stage> per SDX_CANON_ORDER (the cross-track
# timeline; NOT necessarily unique — see the `Change` tie note above), empty if <stage> is
# not a recognized protocol stage name at all. Used ONLY by cmd_retrack's forward-skip
# guard (REQ-RETRACK-2) — matrix_index above already covers WITHIN-track ordering and
# remains the source of truth for next/backtrack.
canon_rank() {
  printf '%s\n' "$SDX_CANON_ORDER" | awk -F'|' -v s="$1" '$1==s{print $2; exit}'
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
# HTML-comment banner inserted as the FIRST line of the artifact (REQ-BACKTRACK-2,
# decision #3 of the plan) — the file is never renamed/moved/truncated. Idempotent: a
# file already carrying the banner (checked in the first 200 bytes) is left untouched and
# does not print an OUTDATED line, so repeated backtracks never duplicate the marker.
mark_outdated() {
  local f="$1" tgt="$2"
  [ -f "$f" ] || return 0
  head -c 200 "$f" | grep -q '<!-- SDX-OUTDATED' && return 0
  local tmp
  tmp="$(mktemp "${f}.XXXXXX")" || return 1
  { printf '<!-- SDX-OUTDATED: устарело откатом /sdx:backtrack --to "%s" (%s). Актуализируйте перед продолжением; история версии — `git log -p -- %s`. -->\n\n' \
      "$tgt" "$(date '+%Y-%m-%d %H:%M:%S')" "$f"
    cat "$f"
  } > "$tmp" && mv "$tmp" "$f"
  echo "OUTDATED: $f"
}

# ---- subcommands ------------------------------------------------------------------------

# init <sid> <type> <track> <stage> <gate_mode> <git_branch>
# Sole legitimate creator of session_state.json (REQ-STAGE-1). Refuses to run if the file
# already exists (exit 2 — init is not for re-initialization) and validates that <stage>
# is the first active stage of <track> per the matrix. Schema is unchanged (REQ-COMPAT-1):
# session_id, type, track, stage, gate_mode, git_branch, artifacts:[], history:[].
cmd_init() {
  if [ "$#" -ne 6 ]; then
    echo "SDX sdx-stage: использование: sdx-stage.sh init <sid> <type> <track> <stage> <gate_mode> <git_branch>" >&2
    exit 2
  fi
  local sid="$1" type="$2" track="$3" stage="$4" gate_mode="$5" git_branch="$6"
  sdir="$proj/.claude/sessions/$sid"
  state="$sdir/session_state.json"
  log="$sdir/session.log"

  if [ -f "$state" ]; then
    echo "SDX sdx-stage: session_state.json для сессии '$sid' уже существует — init не предназначен для повторной инициализации." >&2
    exit 2
  fi

  local first
  first="$(matrix_stages "$track" | head -1)"
  if [ -z "$first" ] || [ "$stage" != "$first" ]; then
    echo "SDX sdx-stage: '$stage' не первый активный этап трека '$track' (ожидался '$first') — init отклонён." >&2
    exit 2
  fi

  mkdir -p "$sdir"
  if ! jq -n \
        --arg session_id "$sid" --arg type "$type" --arg track "$track" \
        --arg stage "$stage" --arg gate_mode "$gate_mode" --arg git_branch "$git_branch" \
        '{session_id:$session_id, type:$type, track:$track, stage:$stage, gate_mode:$gate_mode, git_branch:$git_branch, artifacts:[], history:[]}' \
        > "$state"; then
    rm -f "$state"
    echo "SDX sdx-stage: jq не смог создать $state." >&2
    exit 2
  fi

  log_line "[START] Инициализация сессии $sid (трек: $track)"
  echo "OK - -> $stage"
}

# next <sid>
# Forward transition (REQ-STAGE-2). No explicit target — the matrix is the sole source of
# truth for stage order (REQ-STAGE-3), so the target is always "the next active stage of
# the current track". Gates the DEPARTING (current) stage's artifact before allowing the
# move. Terminal stage (last active stage of the track, i.e. Closeout) -> exit 0 no-op
# (REQ-STAGE-4), nothing written.
cmd_next() {
  local sid="$1"
  sdir="$proj/.claude/sessions/$sid"
  state="$sdir/session_state.json"
  log="$sdir/session.log"

  [ -f "$state" ] || {
    echo "SDX sdx-stage: не найден session_state.json для сессии '$sid' — вызовите /sdx:start или /sdx:import." >&2
    exit 2
  }

  local track stage
  track="$(jq -r '.track // empty' "$state")"
  stage="$(jq -r '.stage // empty' "$state")"

  local stages last
  stages="$(matrix_stages "$track")"
  if [ -z "$stages" ]; then
    echo "SDX sdx-stage: трек '$track' сессии '$sid' не найден в матрице — состояние повреждено." >&2
    exit 2
  fi
  last="$(printf '%s\n' "$stages" | tail -1)"

  if [ "$stage" = "$last" ]; then
    echo "OK no-op $stage"
    return 0
  fi

  local row artifact fail_marker
  row="$(matrix_row "$track" "$stage")"
  if [ -z "$row" ]; then
    echo "SDX sdx-stage: текущий этап '$stage' не найден в треке '$track' матрицы — состояние сессии повреждено." >&2
    exit 2
  fi
  artifact="${row%%|*}"
  fail_marker="${row##*|}"

  if [ "$artifact" != "-" ]; then
    local path="$sdir/$artifact"
    if [ ! -s "$path" ]; then
      echo "SDX sdx-stage: гейт не пройден — не найден/пуст '$artifact' в .claude/sessions/$sid/. Заверши $stage, затем повтори /sdx:next." >&2
      exit 1
    fi
    if [ "$fail_marker" = "yes" ] && grep -q '^### \[FAIL\]' "$path"; then
      echo "SDX sdx-stage: гейт не пройден — '$artifact' содержит находки FAIL. Исправь их и вызови /sdx:backtrack --to Execution." >&2
      exit 1
    fi
  fi

  local idx next_idx new_stage
  idx="$(matrix_index "$track" "$stage")"
  next_idx=$((idx + 1))
  new_stage="$(printf '%s\n' "$stages" | sed -n "${next_idx}p")"

  write_stage "$new_stage"
  log_line "[STAGE_CHANGE] Переход на этап $new_stage"
  echo "OK $stage -> $new_stage"
}

# backtrack <sid> <target>
# Backward transition (REQ-BACKTRACK-1/2). No gate check on the departing stage's
# artifact — going back is always allowed once the target is validated. Marks artifacts of
# ALL stages strictly after <target> (exclusive), through the end of the track's active
# stages, as outdated — NOT bounded by the current stage. REQ-BACKTRACK-2 sets no upper
# bound ("этапы после новой точки"): an artifact from a stage later than "current" can
# legitimately exist on disk (e.g. a leftover verification_report.md from a prior
# Verification cycle while `stage` has since been reset earlier by another backtrack) and
# must be marked too, otherwise a stale artifact silently keeps passing forward gates. The
# target's own artifact is left untouched (it becomes the thing being revisited, not
# something stale).
cmd_backtrack() {
  local sid="$1" target="$2"
  sdir="$proj/.claude/sessions/$sid"
  state="$sdir/session_state.json"
  log="$sdir/session.log"

  [ -f "$state" ] || {
    echo "SDX sdx-stage: не найден session_state.json для сессии '$sid' — вызовите /sdx:start или /sdx:import." >&2
    exit 2
  }

  local track stage
  track="$(jq -r '.track // empty' "$state")"
  stage="$(jq -r '.stage // empty' "$state")"

  # Step 1: target must be a recognized stage name in the protocol at all (union of tracks).
  if ! matrix_stage_exists "$target"; then
    echo "SDX sdx-stage: '$target' не распознан как имя этапа протокола SDX. Проверь опечатку." >&2
    exit 1
  fi

  local stages
  stages="$(matrix_stages "$track")"

  # Step 2: target must be active in the CURRENT track. -F: fixed-string match — $target is
  # user/orchestrator-supplied and MUST NOT be interpreted as a regex (a target containing
  # metacharacters could otherwise false-match an unrelated stage name).
  if ! printf '%s\n' "$stages" | grep -qxF "$target"; then
    echo "SDX sdx-stage: этап '$target' не активен в треке '$track' — нужна смена трека, не откат: /sdx:retrack <track>." >&2
    exit 1
  fi

  # Step 3: no-op if already there (REQ-STAGE-4) — file untouched, not even mtime.
  if [ "$target" = "$stage" ]; then
    echo "OK no-op $stage"
    return 0
  fi

  local idx_target idx_current
  idx_target="$(matrix_index "$track" "$target")"
  idx_current="$(matrix_index "$track" "$stage")"
  if [ -z "$idx_current" ]; then
    echo "SDX sdx-stage: текущий этап '$stage' не найден в треке '$track' матрицы — состояние сессии повреждено." >&2
    exit 2
  fi

  # Step 4: target later than current in track order -> not a backtrack.
  if [ "$idx_target" -gt "$idx_current" ]; then
    echo "SDX sdx-stage: '$target' позже текущего этапа '$stage' в порядке трека — это не откат. Для движения вперёд используй /sdx:next." >&2
    exit 1
  fi

  # Step 5: genuine backward move — write, log, then mark outdated artifacts.
  write_stage "$target"
  log_line "[STAGE_CHANGE] Возврат на этап $target"
  echo "OK $stage -> $target"

  local i s row artifact path
  i=0
  while IFS= read -r s; do
    i=$((i + 1))
    [ "$i" -le "$idx_target" ] && continue
    # No upper bound here on purpose (W-1 fix, REQ-BACKTRACK-2): iterate through every
    # remaining stage of the track, not just up to $idx_current — see docstring above.
    row="$(matrix_row "$track" "$s")"
    artifact="${row%%|*}"
    [ "$artifact" = "-" ] && continue
    path="$sdir/$artifact"
    mark_outdated "$path" "$target"
  done <<< "$stages"
}

# retrack <sid> <target>
# Called AFTER retrack.md has already edited `track` directly via Edit (legitimate,
# REQ-DENY-2) — reads the already-updated track and the still-unchanged stage. Checks, in
# the same two-step order as cmd_backtrack (F-3 fix — a stage name check MUST come first,
# not just "active in this track"; without it a target that is not a real protocol stage
# name at all would only ever be checked against the CURRENT track and, before this fix,
# via an unanchored non-fixed-string grep — see the -F note below): (1) target is a
# recognized protocol stage name at all (union of tracks), (2) target is active in the
# (new) track, (3) idempotent no-op, (4) forward-skip guard (REQ-RETRACK-2, WARN-4 fix —
# see below). No forward-GATE check on artifacts (this remains true, REQ-RETRACK-1): the
# guard below is purely positional (can target be reached AT ALL without going through
# /sdx:next), it never inspects artifacts the way cmd_next does.
cmd_retrack() {
  local sid="$1" target="$2"
  sdir="$proj/.claude/sessions/$sid"
  state="$sdir/session_state.json"
  log="$sdir/session.log"

  [ -f "$state" ] || {
    echo "SDX sdx-stage: не найден session_state.json для сессии '$sid' — вызовите /sdx:start или /sdx:import." >&2
    exit 2
  }

  local track stage
  track="$(jq -r '.track // empty' "$state")"
  stage="$(jq -r '.stage // empty' "$state")"

  # Step 1: target must be a recognized stage name in the protocol at all (union of
  # tracks). Without this step a bogus target (typo, or a regex metacharacter string like
  # ".*") could previously reach write_stage and corrupt `stage` with a value that is not
  # any protocol stage name (F-3).
  if ! matrix_stage_exists "$target"; then
    echo "SDX sdx-stage: '$target' не распознан как имя этапа протокола SDX. Проверь опечатку." >&2
    exit 1
  fi

  local stages
  stages="$(matrix_stages "$track")"

  # Step 2: target must be active in the (new) track. -F: fixed-string match — $target is
  # user/orchestrator-supplied and MUST NOT be interpreted as a regex.
  if ! printf '%s\n' "$stages" | grep -qxF "$target"; then
    echo "SDX sdx-stage: этап '$target' не активен в треке '$track' — проверь целевой этап /sdx:retrack." >&2
    exit 1
  fi

  # Idempotent no-op (REQ-STAGE-4 applies to backtrack/retrack alike, see DESIGN.md
  # "Обработка ошибок" — "target == current для backtrack/retrack").
  if [ "$target" = "$stage" ]; then
    echo "OK no-op $stage"
    return 0
  fi

  # Step 4: forward-skip guard (REQ-RETRACK-2, closes WARN-4 — retrack had no counterpart
  # to REQ-BACKTRACK-1's "not later than current"). `stage`/`target` can belong to two
  # DIFFERENT tracks' own naming, so matrix_index (within-track only) cannot compare them
  # directly — SDX_CANON_ORDER gives the shared cross-track timeline instead.
  #
  # idx_equiv = position, WITHIN THE NEW TRACK, of the LATEST active stage whose canonical
  # rank does not exceed the current stage's canonical rank. That is the furthest point
  # retrack may land on without advancing past a gate that was never actually checked. If
  # the new track's own FIRST active stage already has a higher canonical rank than
  # current (e.g. `patch` has no Discovery/Business Spec/... at all — its lifecycle simply
  # starts later), clamp to that first stage: entering a track at its own starting point is
  # always allowed, entering past it without evidence is not.
  local cur_rank
  cur_rank="$(canon_rank "$stage")"
  if [ -z "$cur_rank" ]; then
    echo "SDX sdx-stage: текущий этап '$stage' не распознан в канонической шкале этапов — состояние сессии повреждено." >&2
    exit 2
  fi
  local idx_equiv=""
  local i=0 s s_rank
  while IFS= read -r s; do
    i=$((i + 1))
    s_rank="$(canon_rank "$s")"
    if [ -n "$s_rank" ] && [ "$s_rank" -le "$cur_rank" ]; then
      idx_equiv="$i"
    fi
  done <<< "$stages"
  [ -z "$idx_equiv" ] && idx_equiv=1

  local idx_target ceiling_stage
  idx_target="$(matrix_index "$track" "$target")"
  if [ "$idx_target" -gt "$idx_equiv" ]; then
    ceiling_stage="$(printf '%s\n' "$stages" | sed -n "${idx_equiv}p")"
    echo "SDX sdx-stage: '$target' дальше по треку '$track', чем позволяет текущий прогресс (этап '$stage', допустимый потолок в новом треке — '$ceiling_stage') — retrack не продвигает вперёд мимо гейта. Выбери менее продвинутый активный этап нового трека, затем продвинься штатно через /sdx:next." >&2
    exit 1
  fi

  write_stage "$target"
  log_line "[STAGE_CHANGE] Переход на этап $target"
  echo "OK $stage -> $target"
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
    if [ "$#" -ne 1 ]; then
      echo "SDX sdx-stage: использование: sdx-stage.sh next <sid>" >&2
      exit 2
    fi
    cmd_next "$@"
    ;;
  backtrack)
    shift
    if [ "$#" -ne 2 ]; then
      echo "SDX sdx-stage: использование: sdx-stage.sh backtrack <sid> <target-stage>" >&2
      exit 2
    fi
    cmd_backtrack "$@"
    ;;
  retrack)
    shift
    if [ "$#" -ne 2 ]; then
      echo "SDX sdx-stage: использование: sdx-stage.sh retrack <sid> <target-stage>" >&2
      exit 2
    fi
    cmd_retrack "$@"
    ;;
  *)
    echo "SDX sdx-stage: использование: sdx-stage.sh <init|next|backtrack|retrack> <args...>" >&2
    exit 2
    ;;
esac
