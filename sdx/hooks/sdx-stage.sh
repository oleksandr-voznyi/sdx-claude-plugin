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
doc|Discovery|-|no
doc|Update|change_note.md|no
doc|Verification|verification_report.md|yes
doc|Closeout|-|no
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

# stage_artifact_ok <stage> <artifact> <fail_marker> <sdir> -> exit 0 if <stage>'s OWN gate
# is objectively satisfied on disk, exit 1 otherwise. This is the SAME existence+non-empty
# (+ absent-FAIL-marker where applicable) criteria cmd_next applies to the departing
# stage's artifact (REQ-STAGE-2) — reused here by cmd_retrack's artifact-floor guard
# (REQ-RETRACK-2, rewritten per F-1) to check a whole CHAIN of preceding stages, not just
# one departing stage.
#
# Special case: `Change` (patch/standard) is a merged stage — protocol.md "Change ...
# объединённый этап" — with no single artifact of its own. Two different kinds of evidence
# both count as "Change done", by construction:
#   - `change_note.md` non-empty: the native patch/standard artifact, OR
#   - `SPEC.md` AND `DESIGN.md` both non-empty: the equivalent full-track evidence. This is
#     not a weakening — retrack.md step 3 ALREADY promotes change_note.md into exactly
#     these two files, unconditionally, before ever calling this script when escalating
#     FROM Change; symmetrically, a full-track session that reached (or passed) its own
#     Business Spec + Technical Design gates has done strictly MORE than a Change stage
#     would ever require, so denying it credit for that work when deescalating INTO
#     standard/patch would be pure ceremony, not safety (W-6 fix).
stage_artifact_ok() {
  local stage="$1" artifact="$2" fail_marker="$3" sdir="$4"
  if [ "$stage" = "Change" ]; then
    [ -s "$sdir/change_note.md" ] && return 0
    [ -s "$sdir/SPEC.md" ] && [ -s "$sdir/DESIGN.md" ] && return 0
    return 1
  fi
  [ "$artifact" = "-" ] && return 0
  local path="$sdir/$artifact"
  [ -s "$path" ] || return 1
  if [ "$fail_marker" = "yes" ] && grep -q '^### \[FAIL\]' "$path"; then
    return 1
  fi
  return 0
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
      # Этап исправления зависит от трека: у кодовых треков это Execution, у doc-трека
      # (где Execution не активен) — предыдущий активный этап, т.е. Update.
      local fix_stage
      fix_stage="Execution"
      if ! printf '%s\n' "$stages" | grep -qx 'Execution'; then
        fix_stage="$(printf '%s\n' "$stages" | sed -n "$(( $(matrix_index "$track" "$stage") - 1 ))p")"
      fi
      echo "SDX sdx-stage: гейт не пройден — '$artifact' содержит находки FAIL. Исправь их и вызови /sdx:backtrack --to $fix_stage." >&2
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
# must be marked too, otherwise a reader (human or agent) mistakes stale content for
# current. The banner is a signal only: a marked artifact still counts as gate evidence
# for both `next` and `retrack` — see "Границы доказательности" in sdx/protocol.md. The
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
# REQ-DENY-2) — reads the already-updated track and the still-unchanged stage. Checks, IN
# THIS ORDER (F-1 fix — order matters, see step 3's docstring for why the guard must
# precede the no-op check): (1) target is a recognized protocol stage name at all (union of
# tracks) — F-3; (2) target is active in the (new) track; (3) artifact-floor guard
# (REQ-RETRACK-2, rewritten per F-1 — see below); (4) idempotent no-op.
#
# REQ-RETRACK-1 ("без повторной проверки forward гейт-артефактов уходящего этапа") still
# holds: the guard below never checks the DEPARTING stage's own artifact, nor `target`'s
# own artifact — only the artifacts of stages that PRECEDE `target` in the new track's row
# order. It also never re-derives a position from `stage`/the old track the way the
# previous rank-based version did — see stage_artifact_ok's docstring for the rationale
# (F-1: a self-reported position cannot be trusted as proof of progress; only artifacts on
# disk can).
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

  # Step 3: artifact-floor guard (REQ-RETRACK-2, rewritten — F-1 fix). Deliberately runs
  # BEFORE the idempotent no-op check below: F-1's sub-finding showed that a target whose
  # STAGE NAME happens to equal the current `stage` value, but whose TRACK actually just
  # changed (e.g. patch/Execution -> full/Execution — see scenario [26]), used to reach the
  # old no-op branch and skip the guard entirely. Running the guard unconditionally closes
  # that hole without needing to know whether the track literally changed.
  #
  # The rule is no longer positional (a rank derived from WHERE `stage` self-reports being)
  # — it is evidence-based: `target` is reachable iff EVERY stage of the (new) track that
  # PRECEDES it in row order (matrix_index < idx_target) already has its own gate
  # objectively satisfied on disk (stage_artifact_ok — same criteria cmd_next applies to a
  # single departing stage, REQ-STAGE-2). `stage`/the old track are never consulted for
  # this — a track's own FIRST active stage always has an empty preceding chain, so
  # entering a track at its own starting point remains unconditionally allowed; landing
  # further requires the SAME artifacts /sdx:next would have required to get there for
  # real. This is deliberately NOT bounded by "current progress" as a position, precisely
  # because that position is exactly what F-1 showed cannot be trusted (a ratchet: two
  # legitimate-looking retrack calls could inflate it without a single gate ever passing).
  local idx_target
  idx_target="$(matrix_index "$track" "$target")"
  local i=0 s row artifact fail_marker missing_stage="" missing_artifact=""
  while IFS= read -r s; do
    i=$((i + 1))
    [ "$i" -ge "$idx_target" ] && break
    row="$(matrix_row "$track" "$s")"
    artifact="${row%%|*}"
    fail_marker="${row##*|}"
    if ! stage_artifact_ok "$s" "$artifact" "$fail_marker" "$sdir"; then
      missing_stage="$s"
      missing_artifact="$artifact"
      break
    fi
  done <<< "$stages"

  if [ -n "$missing_stage" ]; then
    if [ "$missing_stage" = "Change" ]; then
      echo "SDX sdx-stage: '$target' недостижим — этап '$missing_stage' трека '$track' не подтверждён (нет ни change_note.md, ни пары SPEC.md+DESIGN.md в .claude/sessions/$sid/). retrack не продвигает вперёд мимо непройденного гейта — выбери менее продвинутый активный этап нового трека либо заверши '$missing_stage', затем продвинься штатно через /sdx:next." >&2
    else
      echo "SDX sdx-stage: '$target' недостижим — этап '$missing_stage' трека '$track' не подтверждён (не найден/пуст '$missing_artifact' в .claude/sessions/$sid/, либо остались находки FAIL). retrack не продвигает вперёд мимо непройденного гейта — выбери менее продвинутый активный этап нового трека либо заверши '$missing_stage' (артефакт '$missing_artifact'), затем продвинься штатно через /sdx:next." >&2
    fi
    exit 1
  fi

  # Step 4: idempotent no-op (REQ-STAGE-4 applies to backtrack/retrack alike, see
  # DESIGN.md "Обработка ошибок" — "target == current для backtrack/retrack"). Safe here,
  # AFTER the guard: reaching this point already proves every stage preceding `target` has
  # a satisfied gate, so a no-op never hides an unearned position.
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
