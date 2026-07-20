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
# stages strictly after <target> (exclusive) up to and including the current stage as
# outdated; the target's own artifact is left untouched (it becomes the thing being
# revisited, not something stale).
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

  # Step 2: target must be active in the CURRENT track.
  if ! printf '%s\n' "$stages" | grep -qx "$target"; then
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
    [ "$i" -gt "$idx_current" ] && break
    row="$(matrix_row "$track" "$s")"
    artifact="${row%%|*}"
    [ "$artifact" = "-" ] && continue
    path="$sdir/$artifact"
    mark_outdated "$path" "$target"
  done <<< "$stages"
}

# retrack <sid> <target>
# Called AFTER retrack.md has already edited `track` directly via Edit (legitimate,
# REQ-DENY-2) — reads the already-updated track and the still-unchanged stage. Only
# checks "target is active in the (new) track"; no forward-gate (this is not an advance).
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

  local stages
  stages="$(matrix_stages "$track")"
  if ! printf '%s\n' "$stages" | grep -qx "$target"; then
    echo "SDX sdx-stage: этап '$target' не активен в треке '$track' — проверь целевой этап /sdx:retrack." >&2
    exit 1
  fi

  # Idempotent no-op (REQ-STAGE-4 applies to backtrack/retrack alike, see DESIGN.md
  # "Обработка ошибок" — "target == current для backtrack/retrack").
  if [ "$target" = "$stage" ]; then
    echo "OK no-op $stage"
    return 0
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
