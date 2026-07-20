#!/usr/bin/env bash
# Unit tests for sdx-stage.sh (REQ-STAGE-1..5, REQ-BACKTRACK-1..2, REQ-RETRACK-1,
# REQ-CLOSEOUT-ENTRY-1). Runs self-contained: creates temporary git repos, exercises the
# CLI, cleans up. Usage: bash sdx/hooks/test-sdx-stage.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/sdx-stage.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# Global temp dir for each test; cleaned up by cleanup().
TMPPROJ=""

# setup_sdx_repo <sid> <track> <stage>
#   Creates a temp "project" dir (no real git repo needed — sdx-stage.sh takes sid
#   explicitly and never resolves a branch) with .claude/sessions/<sid>/session_state.json.
setup_sdx_repo() {
  local sid="$1" track="$2" stage="$3"
  TMPPROJ="$(mktemp -d)"
  mkdir -p "$TMPPROJ/.claude/sessions/$sid"
  jq -n --arg session_id "$sid" --arg type "full" --arg track "$track" --arg stage "$stage" \
    '{session_id:$session_id, type:$type, track:$track, stage:$stage, gate_mode:"interactive", git_branch:("sdx/"+$session_id), artifacts:[], history:[]}' \
    > "$TMPPROJ/.claude/sessions/$sid/session_state.json"
}

cleanup() {
  [ -n "$TMPPROJ" ] && rm -rf "$TMPPROJ"
  TMPPROJ=""
}

# run_stage <args...>
#   Invokes the CLI with CLAUDE_PROJECT_DIR set to TMPPROJ. Not stdin JSON — this is a
#   plain CLI, unlike the PreToolUse hooks.
run_stage() {
  CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$SCRIPT" "$@"
}

state_file() {
  printf '%s' "$TMPPROJ/.claude/sessions/$1/session_state.json"
}

log_file() {
  printf '%s' "$TMPPROJ/.claude/sessions/$1/session.log"
}

# seed_gate_artifacts <sid> <track> [stop-before-stage]
#   Writes a minimally-valid (non-empty) gate artifact for every stage of <track> that
#   PRECEDES [stop-before-stage] in matrix row order (the whole track if omitted) — read
#   directly from SDX_STAGE_MATRIX inside sdx-stage.sh via grep (same no-sourcing,
#   read-the-script approach as the sanity scenarios near the end of this file), so
#   fixtures can never silently drift from the real matrix. Mirrors what a session that
#   legitimately progressed via /sdx:next through those stages would actually have on disk.
#   Needed under the artifact-floor retrack rule (F-1 fix, REQ-RETRACK-2 rewritten): a
#   fixture claiming to already be AT a given stage must be backed by real preceding
#   evidence, or retrack (even a same-stage no-op call) now correctly refuses it.
seed_gate_artifacts() {
  local sid="$1" track="$2" stop="${3:-}" sdir
  sdir="$TMPPROJ/.claude/sessions/$sid"
  local rows _trk name artifact _fm
  rows="$(grep -E "^${track}\|" "$SCRIPT")"
  while IFS='|' read -r _trk name artifact _fm; do
    [ -z "$name" ] && continue
    [ -n "$stop" ] && [ "$name" = "$stop" ] && break
    if [ "$name" = "Change" ]; then
      printf 'change note\n' > "$sdir/change_note.md"
    elif [ "$artifact" != "-" ]; then
      printf 'placeholder content\n' > "$sdir/$artifact"
    fi
  done <<< "$rows"
}

echo "=== test-sdx-stage.sh ==="
echo ""

# ---- Scenario 1: init creates state + [START] log line, exit 0 ----
echo "[1] init creates session_state.json + [START] log line"
TMPPROJ="$(mktemp -d)"
out="$(run_stage init "t1" "full" "full" "Discovery" "interactive" "sdx/t1")"
ec=$?
sf="$(state_file t1)"
lf="$(log_file t1)"
if [ "$ec" -eq 0 ] && [ -f "$sf" ] && [ -f "$lf" ] \
   && [ "$(jq -r '.stage' "$sf")" = "Discovery" ] \
   && grep -q '\[START\]' "$lf" \
   && printf '%s' "$out" | grep -q '^OK - ->'; then
  pass "state+log created, exit 0, stdout OK - ->"
else
  fail "Expected state+log created" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 2: repeated init on existing file -> exit 2, file untouched ----
echo "[2] repeated init on existing file -> exit 2, file byte-for-byte unchanged"
TMPPROJ="$(mktemp -d)"
run_stage init "t2" "full" "full" "Discovery" "interactive" "sdx/t2" > /dev/null
sf="$(state_file t2)"
before="$(cat "$sf")"
before_sum="$(md5sum "$sf" | cut -d' ' -f1)"
out="$(run_stage init "t2" "full" "full" "Discovery" "interactive" "sdx/t2" 2>&1 1>/dev/null)"
ec=$?
after_sum="$(md5sum "$sf" | cut -d' ' -f1)"
if [ "$ec" -eq 2 ] && [ "$before_sum" = "$after_sum" ]; then
  pass "exit 2, file unchanged"
else
  fail "Expected exit 2 + unchanged file" "ec=$ec before=$before_sum after=$after_sum stderr=$out"
fi
cleanup

# ---- Scenario 3: next — gate passed -> stage advances, [STAGE_CHANGE] logged ----
echo "[3] next: gate passed (context_report.md present+non-empty) -> Discovery -> Business Spec"
setup_sdx_repo "t3" "full" "Discovery"
printf 'notes\n' > "$TMPPROJ/.claude/sessions/t3/context_report.md"
out="$(run_stage next "t3")"
ec=$?
sf="$(state_file t3)"
lf="$(log_file t3)"
if [ "$ec" -eq 0 ] && [ "$(jq -r '.stage' "$sf")" = "Business Spec" ] \
   && grep -q '\[STAGE_CHANGE\]' "$lf" \
   && [ "$out" = "OK Discovery -> Business Spec" ]; then
  pass "stage advanced, logged, stdout OK Discovery -> Business Spec"
else
  fail "Expected advance to Business Spec" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 4: next — gate NOT passed (artifact missing) -> exit 1, stage unchanged ----
echo "[4] next: gate not passed (missing artifact) -> exit 1, stage unchanged, stderr names artifact+command"
setup_sdx_repo "t4" "full" "Discovery"
out="$(run_stage next "t4" 2>&1 1>/dev/null)"
ec=$?
sf="$(state_file t4)"
if [ "$ec" -eq 1 ] && [ "$(jq -r '.stage' "$sf")" = "Discovery" ] \
   && printf '%s' "$out" | grep -q "context_report.md" \
   && printf '%s' "$out" | grep -q "/sdx:next"; then
  pass "exit 1, stage unchanged, stderr names artifact+/sdx:next"
else
  fail "Expected gate rejection" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 5: next — verification_report.md has FAIL marker -> exit 1 ----
echo "[5] next: verification_report.md contains ### [FAIL] -> exit 1, points to backtrack"
setup_sdx_repo "t5" "full" "Verification"
printf '### [FAIL] [Correctness] something broken\n' > "$TMPPROJ/.claude/sessions/t5/verification_report.md"
out="$(run_stage next "t5" 2>&1 1>/dev/null)"
ec=$?
sf="$(state_file t5)"
if [ "$ec" -eq 1 ] && [ "$(jq -r '.stage' "$sf")" = "Verification" ] \
   && printf '%s' "$out" | grep -q "FAIL" \
   && printf '%s' "$out" | grep -q "backtrack --to Execution"; then
  pass "exit 1, mentions FAIL + backtrack --to Execution"
else
  fail "Expected FAIL-marker rejection" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 6: next — Verification -> Closeout on patch track, same gate as full's Deployment ----
echo "[6] next: patch track Verification -> Closeout (unified gate, no track branching)"
setup_sdx_repo "t6" "patch" "Verification"
printf 'PASS\n' > "$TMPPROJ/.claude/sessions/t6/verification_report.md"
out="$(run_stage next "t6")"
ec=$?
sf="$(state_file t6)"
if [ "$ec" -eq 0 ] && [ "$(jq -r '.stage' "$sf")" = "Closeout" ] \
   && [ "$out" = "OK Verification -> Closeout" ]; then
  pass "patch: Verification -> Closeout"
else
  fail "Expected patch Verification -> Closeout" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 7: next — current stage is terminal Closeout -> exit 0 no-op ----
echo "[7] next: current stage Closeout (terminal) -> exit 0 no-op"
setup_sdx_repo "t7" "full" "Closeout"
sf="$(state_file t7)"
before_sum="$(md5sum "$sf" | cut -d' ' -f1)"
out="$(run_stage next "t7")"
ec=$?
after_sum="$(md5sum "$sf" | cut -d' ' -f1)"
if [ "$ec" -eq 0 ] && [ "$out" = "OK no-op Closeout" ] && [ "$before_sum" = "$after_sum" ]; then
  pass "no-op on terminal Closeout, file untouched"
else
  fail "Expected no-op on Closeout" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 8: backtrack — target active + not later than current -> stage changes, no gate check ----
echo "[8] backtrack: target active, not later than current -> stage changes without gate check"
setup_sdx_repo "t8" "full" "Task Planning"
# Deliberately no PLAN.md/DESIGN.md artifacts present — the departing stage's gate is
# not checked by backtrack.
out="$(run_stage backtrack "t8" "Technical Design")"
ec=$?
sf="$(state_file t8)"
if [ "$ec" -eq 0 ] && [ "$(jq -r '.stage' "$sf")" = "Technical Design" ]; then
  pass "backtrack succeeds despite missing gate artifacts"
else
  fail "Expected backtrack to Technical Design" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 9: backtrack — target == current stage -> exit 0 no-op, file untouched ----
echo "[9] backtrack: target == current -> exit 0 no-op, file untouched (mtime/content)"
setup_sdx_repo "t9" "full" "Execution"
sf="$(state_file t9)"
before_sum="$(md5sum "$sf" | cut -d' ' -f1)"
out="$(run_stage backtrack "t9" "Execution")"
ec=$?
after_sum="$(md5sum "$sf" | cut -d' ' -f1)"
if [ "$ec" -eq 0 ] && [ "$out" = "OK no-op Execution" ] && [ "$before_sum" = "$after_sum" ]; then
  pass "no-op, file untouched"
else
  fail "Expected no-op on same-stage backtrack" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 10: backtrack — target not active in current track -> exit 1, retrack hint ----
echo "[10] backtrack: target not active in track -> exit 1, points to /sdx:retrack"
setup_sdx_repo "t10" "patch" "Execution"
out="$(run_stage backtrack "t10" "Technical Design" 2>&1 1>/dev/null)"
ec=$?
if [ "$ec" -eq 1 ] && printf '%s' "$out" | grep -q "/sdx:retrack"; then
  pass "exit 1, mentions /sdx:retrack"
else
  fail "Expected retrack hint" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 11: backtrack — target later than current -> exit 1, /sdx:next hint ----
echo "[11] backtrack: target later than current -> exit 1, points to /sdx:next"
setup_sdx_repo "t11" "full" "Discovery"
out="$(run_stage backtrack "t11" "Task Planning" 2>&1 1>/dev/null)"
ec=$?
if [ "$ec" -eq 1 ] && printf '%s' "$out" | grep -q "/sdx:next"; then
  pass "exit 1, mentions /sdx:next"
else
  fail "Expected /sdx:next hint" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 12: backtrack — unrecognized stage name (typo) -> exit 1 ----
echo "[12] backtrack: unrecognized stage name (typo) -> exit 1, 'не распознан'"
setup_sdx_repo "t12" "full" "Execution"
out="$(run_stage backtrack "t12" "Discoveryy" 2>&1 1>/dev/null)"
ec=$?
if [ "$ec" -eq 1 ] && printf '%s' "$out" | grep -q "не распознан"; then
  pass "exit 1, 'не распознан'"
else
  fail "Expected unrecognized-name rejection" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 13: backtrack — outdated marking (Task Planning -> Technical Design) ----
echo "[13] backtrack: full Task Planning -> Technical Design marks PLAN.md, not DESIGN.md"
setup_sdx_repo "t13" "full" "Task Planning"
printf '# Plan\n' > "$TMPPROJ/.claude/sessions/t13/PLAN.md"
printf '# Design\n' > "$TMPPROJ/.claude/sessions/t13/DESIGN.md"
out="$(run_stage backtrack "t13" "Technical Design")"
ec=$?
plan_first_line="$(head -1 "$TMPPROJ/.claude/sessions/t13/PLAN.md")"
design_first_line="$(head -1 "$TMPPROJ/.claude/sessions/t13/DESIGN.md")"
if [ "$ec" -eq 0 ] \
   && printf '%s' "$plan_first_line" | grep -q 'SDX-OUTDATED' \
   && [ "$design_first_line" = "# Design" ] \
   && printf '%s' "$out" | grep -q "OUTDATED: .*PLAN.md"; then
  pass "PLAN.md banner-marked, DESIGN.md (target's own artifact) untouched, OUTDATED: printed"
else
  fail "Expected PLAN.md marked, DESIGN.md not" "ec=$ec out='$out' plan1='$plan_first_line' design1='$design_first_line'"
fi
cleanup

# ---- Scenario 14: backtrack — repeated marking does not duplicate the banner ----
echo "[14] backtrack: repeated outdated marking of the same file does not duplicate the banner"
setup_sdx_repo "t14" "full" "Task Planning"
printf '# Plan\n' > "$TMPPROJ/.claude/sessions/t14/PLAN.md"
printf '# Design\n' > "$TMPPROJ/.claude/sessions/t14/DESIGN.md"
run_stage backtrack "t14" "Technical Design" > /dev/null   # marks PLAN.md (Task Planning is in range)
# Simulate the session having advanced forward again (e.g. via /sdx:next) back to
# Task Planning, so a second backtrack to the same target re-covers PLAN.md's stage —
# this is direct fixture setup (jq), not a call through sdx-stage.sh (test-only shortcut).
jq '.stage = "Task Planning"' "$TMPPROJ/.claude/sessions/t14/session_state.json" > "$TMPPROJ/.claude/sessions/t14/session_state.json.tmp" \
  && mv "$TMPPROJ/.claude/sessions/t14/session_state.json.tmp" "$TMPPROJ/.claude/sessions/t14/session_state.json"
out2="$(run_stage backtrack "t14" "Technical Design")"
banner_count="$(grep -c 'SDX-OUTDATED' "$TMPPROJ/.claude/sessions/t14/PLAN.md")"
if [ "$banner_count" -eq 1 ] && ! printf '%s' "$out2" | grep -q "OUTDATED: .*PLAN.md"; then
  pass "banner not duplicated (count=1), second call does not re-report OUTDATED for PLAN.md"
else
  fail "Expected exactly one banner, no repeated OUTDATED line" "count=$banner_count out2='$out2'"
fi
cleanup

# ---- Scenario 15: backtrack — outdated marking is NOT bounded by the current stage (W-1) ----
# Reproduces the exact verification_report.md scenario: current stage is Task Planning,
# but a leftover verification_report.md from a previous cycle (stage index 7, i.e. AFTER
# the current stage index 4) already sits on disk. REQ-BACKTRACK-2 sets no upper bound —
# every stage strictly after the target must be covered, regardless of where "current" is.
echo "[15] backtrack: outdated marking covers stages strictly after target with NO upper bound at current stage (W-1)"
setup_sdx_repo "t15b" "full" "Task Planning"
printf '# Design\n' > "$TMPPROJ/.claude/sessions/t15b/DESIGN.md"
printf '# Plan\n' > "$TMPPROJ/.claude/sessions/t15b/PLAN.md"
printf 'leftover report\n' > "$TMPPROJ/.claude/sessions/t15b/verification_report.md"
out="$(run_stage backtrack "t15b" "Business Spec")"
ec=$?
design_first_line="$(head -1 "$TMPPROJ/.claude/sessions/t15b/DESIGN.md")"
plan_first_line="$(head -1 "$TMPPROJ/.claude/sessions/t15b/PLAN.md")"
report_first_line="$(head -1 "$TMPPROJ/.claude/sessions/t15b/verification_report.md")"
if [ "$ec" -eq 0 ] \
   && printf '%s' "$design_first_line" | grep -q 'SDX-OUTDATED' \
   && printf '%s' "$plan_first_line" | grep -q 'SDX-OUTDATED' \
   && printf '%s' "$report_first_line" | grep -q 'SDX-OUTDATED' \
   && printf '%s' "$out" | grep -q "OUTDATED: .*verification_report.md"; then
  pass "DESIGN.md, PLAN.md AND leftover verification_report.md (past idx_current) all marked outdated"
else
  fail "Expected ALL stages after target marked, including ones past current stage" \
    "ec=$ec out='$out' design1='$design_first_line' plan1='$plan_first_line' report1='$report_first_line'"
fi
cleanup

# ---- Scenario 16: retrack — deescalation full "Technical Design" -> standard, track already
#      updated, target=Change (the natural landing point) -> stage changes without forward-gate ----
# `stage` still carries the OLD track's value at call time (DESIGN.md "reads the
# already-updated track and the still-unchanged stage") — this fixture reproduces exactly
# that: `track` is already "standard" (as retrack.md step 4.2's Edit would have left it),
# `stage` is still "Technical Design" (the full-track value, not yet touched). Under the
# rewritten artifact-floor rule (REQ-RETRACK-2, F-1 fix) `Change`'s only PRECEDING stage in
# standard's own row order is `Discovery`, whose artifact is "-" (not objectively
# checkable) — an empty preceding chain, so this succeeds without change_note.md present,
# same observable result as before but for a different reason (evidence, not a rank tie):
# retrack still has no forward-GATE-artifact check on `target` ITSELF (REQ-RETRACK-1).
echo "[16] retrack: deescalation full 'Technical Design' -> standard, target=Change (tied rank) -> stage changes without forward-gate"
setup_sdx_repo "t16" "standard" "Technical Design"
out="$(run_stage retrack "t16" "Change")"
ec=$?
sf="$(state_file t16)"
if [ "$ec" -eq 0 ] && [ "$(jq -r '.stage' "$sf")" = "Change" ]; then
  pass "retrack succeeds without change_note.md present"
else
  fail "Expected retrack to Change" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 17: retrack — target not active in (updated) new track -> exit 1 ----
echo "[17] retrack: target not active in new track -> exit 1"
setup_sdx_repo "t17" "patch" "Execution"
out="$(run_stage retrack "t17" "Technical Design" 2>&1 1>/dev/null)"
ec=$?
sf="$(state_file t17)"
if [ "$ec" -eq 1 ] && [ "$(jq -r '.stage' "$sf")" = "Execution" ]; then
  pass "exit 1, stage unchanged"
else
  fail "Expected retrack rejection" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 18: retrack — unrecognized stage name (typo) -> exit 1, 'не распознан', file untouched (F-3/W-4) ----
echo "[18] retrack: unrecognized stage name (typo) -> exit 1, 'не распознан', file untouched"
setup_sdx_repo "t18r" "full" "Execution"
sf="$(state_file t18r)"
before_sum="$(md5sum "$sf" | cut -d' ' -f1)"
out="$(run_stage retrack "t18r" "Discoveryy" 2>&1 1>/dev/null)"
ec=$?
after_sum="$(md5sum "$sf" | cut -d' ' -f1)"
if [ "$ec" -eq 1 ] && printf '%s' "$out" | grep -q "не распознан" && [ "$before_sum" = "$after_sum" ]; then
  pass "exit 1, 'не распознан', file untouched"
else
  fail "Expected unrecognized-name rejection with unchanged file" "ec=$ec out='$out' before=$before_sum after=$after_sum"
fi
cleanup

# ---- Scenario 19: retrack — regex-metacharacter target is NOT falsely matched as an active stage (F-3 core repro) ----
# `retrack <sid> '.*'` used to succeed (rc=0) and write the literal string ".*" into
# `stage` because the old code fed $target straight into `grep -qx` (no -F) with no prior
# "is this a real stage name at all" check. It must be rejected as unrecognized, and the
# state file must stay byte-for-byte unchanged.
echo "[19] retrack: regex-metacharacter target ('.*') treated literally, not as a pattern -> exit 1, file untouched"
setup_sdx_repo "t19r" "full" "Execution"
sf="$(state_file t19r)"
before_sum="$(md5sum "$sf" | cut -d' ' -f1)"
out="$(run_stage retrack "t19r" ".*" 2>&1 1>/dev/null)"
ec=$?
after_sum="$(md5sum "$sf" | cut -d' ' -f1)"
if [ "$ec" -eq 1 ] && printf '%s' "$out" | grep -q "не распознан" \
   && [ "$before_sum" = "$after_sum" ] \
   && [ "$(jq -r '.stage' "$sf")" != ".*" ]; then
  pass "'.*' rejected as unrecognized, state file untouched (stage still 'Execution')"
else
  fail "Expected '.*' to be rejected without corrupting state" "ec=$ec out='$out' before=$before_sum after=$after_sum stage=$(jq -r '.stage' "$sf" 2>/dev/null)"
fi
cleanup

# ---- Scenario 20: retrack — target == current stage, WITH real preceding evidence on disk
#      -> exit 0 no-op, file untouched (REQ-STAGE-4/W-4) ----
# The artifact-floor guard now runs BEFORE the no-op check (F-1 fix — see scenario [26] for
# the regression this closes), so a same-stage no-op must ALSO clear the guard: the fixture
# seeds real preceding artifacts (context_report.md/SPEC.md/DESIGN.md/PLAN.md), exactly
# what a session that really reached Execution via /sdx:next would have on disk.
echo "[20] retrack: target == current stage, with real preceding evidence -> exit 0 no-op, file untouched"
setup_sdx_repo "t20r" "full" "Execution"
seed_gate_artifacts "t20r" "full" "Execution"
sf="$(state_file t20r)"
before_sum="$(md5sum "$sf" | cut -d' ' -f1)"
out="$(run_stage retrack "t20r" "Execution")"
ec=$?
after_sum="$(md5sum "$sf" | cut -d' ' -f1)"
if [ "$ec" -eq 0 ] && [ "$out" = "OK no-op Execution" ] && [ "$before_sum" = "$after_sum" ]; then
  pass "no-op, file untouched"
else
  fail "Expected no-op on same-stage retrack" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 21: retrack — forward-skip guard (REQ-RETRACK-2, WARN-4 regression repro) ----
# Exact reproduction of the verification_report.md WARN-4 finding: track `full`, stage
# `Discovery`, zero artifacts anywhere, `track` field is UNCHANGED (retrack called directly,
# the same shape as calling it without ever having gone through retrack.md's step 4.2 Edit).
# Before REQ-RETRACK-2 this returned rc=0 and wrote `stage=Closeout`, skipping every gate in
# the track. Symmetric to backtrack's own "target later than current" guard (scenario 11).
# Under the rewritten artifact-floor rule (F-1 fix) the rejection reason changed (Closeout's
# preceding chain starts failing at Discovery itself, the very first stage — no artifact
# anywhere) but the observable outcome is unchanged: exit 1, file untouched.
echo "[21] retrack: forward-skip guard blocks same-track jump straight to Closeout (WARN-4 regression)"
setup_sdx_repo "t21r" "full" "Discovery"
sf="$(state_file t21r)"
before_sum="$(md5sum "$sf" | cut -d' ' -f1)"
out="$(run_stage retrack "t21r" "Closeout" 2>&1 1>/dev/null)"
ec=$?
after_sum="$(md5sum "$sf" | cut -d' ' -f1)"
if [ "$ec" -eq 1 ] && [ "$before_sum" = "$after_sum" ] \
   && printf '%s' "$out" | grep -q "/sdx:next"; then
  pass "exit 1, file untouched, stderr points to /sdx:next"
else
  fail "Expected forward-skip rejection (WARN-4)" "ec=$ec out='$out' before=$before_sum after=$after_sum"
fi
cleanup

# ---- Scenario 22: retrack — forward-skip guard also fires across an ACTUAL track change ----
# Same exploit shape as scenario 21, but this time `track` really did change (standard, as
# retrack.md's step 4.2 would leave it) — confirms the guard is not merely a same-track
# special case tacked onto the old checks.
echo "[22] retrack: forward-skip guard also blocks a jump straight to Closeout after a real track change"
setup_sdx_repo "t22r" "standard" "Discovery"
sf="$(state_file t22r)"
before_sum="$(md5sum "$sf" | cut -d' ' -f1)"
out="$(run_stage retrack "t22r" "Closeout" 2>&1 1>/dev/null)"
ec=$?
after_sum="$(md5sum "$sf" | cut -d' ' -f1)"
if [ "$ec" -eq 1 ] && [ "$before_sum" = "$after_sum" ]; then
  pass "exit 1, file untouched"
else
  fail "Expected forward-skip rejection across a real track change" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 23: retrack — escalating from Change now needs REAL preceding evidence, not
#      just a rank tie (F-1 fix, REQ-RETRACK-2 rewritten) ----
# `stage=Change` (leftover from before retrack.md's track Edit — the fixture reproduces the
# same "track already updated, stage not yet touched" shape as scenario 16). Landing on
# `Technical Design` needs Discovery+Business Spec's OWN artifacts to already exist (exactly
# what retrack.md step 3's unconditional promotion of change_note.md into SPEC.md would have
# produced for Business Spec — Discovery's context_report.md is seeded here too, standing in
# for a real Discovery having been done). Landing on `Task Planning` additionally needs
# Technical Design's OWN artifact (DESIGN.md) — deliberately absent in the second case, so
# it must stay rejected even though Business Spec's evidence is present.
echo "[23] retrack: escalating from Change to Technical Design needs Discovery+Business Spec evidence; Task Planning additionally needs Technical Design's own"
setup_sdx_repo "t23a" "full" "Change"
printf 'notes\n' > "$TMPPROJ/.claude/sessions/t23a/context_report.md"
printf '# Spec\n' > "$TMPPROJ/.claude/sessions/t23a/SPEC.md"
out="$(run_stage retrack "t23a" "Technical Design")"
ec=$?
sf="$(state_file t23a)"
ok1=0
[ "$ec" -eq 0 ] && [ "$(jq -r '.stage' "$sf")" = "Technical Design" ] && ok1=1
cleanup

setup_sdx_repo "t23b" "full" "Change"
printf 'notes\n' > "$TMPPROJ/.claude/sessions/t23b/context_report.md"
printf '# Spec\n' > "$TMPPROJ/.claude/sessions/t23b/SPEC.md"
# Deliberately no DESIGN.md — Technical Design's own gate is unmet.
out2="$(run_stage retrack "t23b" "Task Planning" 2>&1 1>/dev/null)"
ec2=$?
sf2="$(state_file t23b)"
ok2=0
[ "$ec2" -eq 1 ] && [ "$(jq -r '.stage' "$sf2")" = "Change" ] && ok2=1
cleanup
if [ "$ok1" -eq 1 ] && [ "$ok2" -eq 1 ]; then
  pass "Technical Design reachable with Discovery+Business Spec evidence, Task Planning rejected without Technical Design's own"
else
  fail "Expected evidence-gated escalation from Change" "ec=$ec out='$out' ec2=$ec2 out2='$out2'"
fi

# ---- Scenario 24: retrack — deescalation clamps to the new track's OWN first active stage ----
# `patch` has no Discovery/Business Spec/.../Task Planning at all — its lifecycle starts at
# Execution BY DESIGN, not because anything was skipped. Landing there must stay allowed:
# under the rewritten artifact-floor rule (F-1 fix) Execution is patch's FIRST active stage,
# so its preceding chain is empty — always reachable, no evidence required. Landing any
# FURTHER (Verification) must still be rejected: Verification's preceding chain includes
# Execution's own `change_note.md`, which this zero-artifact fixture never created.
echo "[24] retrack: deescalation to patch clamps ceiling to patch's own first stage (Execution), not beyond"
setup_sdx_repo "t24a" "patch" "Discovery"
out="$(run_stage retrack "t24a" "Execution")"
ec=$?
sf="$(state_file t24a)"
ok1=0
[ "$ec" -eq 0 ] && [ "$(jq -r '.stage' "$sf")" = "Execution" ] && ok1=1
cleanup
setup_sdx_repo "t24b" "patch" "Discovery"
out2="$(run_stage retrack "t24b" "Verification" 2>&1 1>/dev/null)"
ec2=$?
sf2="$(state_file t24b)"
ok2=0
[ "$ec2" -eq 1 ] && [ "$(jq -r '.stage' "$sf2")" = "Discovery" ] && ok2=1
cleanup
if [ "$ok1" -eq 1 ] && [ "$ok2" -eq 1 ]; then
  pass "clamped to patch's own first stage (Execution), Verification still rejected"
else
  fail "Expected clamp to track's own first active stage" "ec=$ec out='$out' ec2=$ec2 out2='$out2'"
fi

# ---- Scenario 25: retrack + retrack — F-1 EXACT ratchet regression (verification_report.md,
#      3rd-pass fresh-eyes finding). Reproduces the report's repro verbatim: full/Discovery,
#      ZERO artifacts anywhere -> retrack into patch (clamp to Execution, patch's own first
#      stage — always allowed) -> retrack BACK to full targeting increasingly advanced
#      stages. Under the OLD rank-based rule the second hop succeeded (the clamp position
#      itself counted as "накопленный прогресс"); under the NEW artifact-floor rule it must
#      be rejected every time — no Discovery/Business Spec/Technical Design artifact was ever
#      created, only a `retrack` round-trip, which proves nothing on its own ----
echo "[25] retrack+retrack: full/Discovery (zero artifacts) -> patch Execution (clamp, OK) -> full Task Planning / same-named Execution MUST both stay rejected (F-1 ratchet regression)"
setup_sdx_repo "t25" "full" "Discovery"
sf25="$(state_file t25)"

# Hop 1: deescalate to patch (retrack.md step 4.2's `track` Edit simulated directly — a
# legitimate direct path, REQ-DENY-2 does not guard `track`). Landing on patch's own first
# stage is always allowed — this hop is correct both before and after the fix.
jq '.track = "patch"' "$sf25" > "$sf25.tmp" && mv "$sf25.tmp" "$sf25"
out1="$(run_stage retrack "t25" "Execution")"
ec1=$?
hop1_ok=0
[ "$ec1" -eq 0 ] && [ "$(jq -r '.stage' "$sf25")" = "Execution" ] && hop1_ok=1

# Hop 2: escalate BACK to full (track Edit simulated again). Old buggy behaviour: this
# succeeded (the rank of `stage=Execution` let it reach Task Planning, or Verification via
# two /sdx:next afterwards). New rule: Task Planning's preceding chain (Discovery, Business
# Spec, Technical Design) has NO artifact on disk anywhere -> must be rejected.
jq '.track = "full"' "$sf25" > "$sf25.tmp" && mv "$sf25.tmp" "$sf25"
out2="$(run_stage retrack "t25" "Task Planning" 2>&1 1>/dev/null)"
ec2=$?
stage_after_hop2="$(jq -r '.stage' "$sf25")"
hop2_rejected=0
[ "$ec2" -eq 1 ] && [ "$stage_after_hop2" = "Execution" ] && hop2_rejected=1

# Same probe, but target=Execution itself — the "soputstvuyushchee"/shorter-path
# sub-finding of F-1: same stage NAME as current, only the track differs. Must ALSO be
# rejected (full/Execution's own preceding chain is unmet), not silently treated as a
# no-op — this is exactly what scenario [26] below isolates on its own.
out3="$(run_stage retrack "t25" "Execution" 2>&1 1>/dev/null)"
ec3=$?
stage_after_hop3="$(jq -r '.stage' "$sf25")"
hop3_rejected=0
[ "$ec3" -eq 1 ] && [ "$stage_after_hop3" = "Execution" ] && hop3_rejected=1

cleanup
if [ "$hop1_ok" -eq 1 ] && [ "$hop2_rejected" -eq 1 ] && [ "$hop3_rejected" -eq 1 ]; then
  pass "clamp-in hop succeeds, but re-escalation to Task Planning AND to same-named Execution both stay rejected without evidence"
else
  fail "Expected the ratchet to stay closed across both hops" "ec1=$ec1 ec2=$ec2 out2='$out2' ec3=$ec3 out3='$out3'"
fi

# ---- Scenario 26: retrack — no-op-order bypass regression (F-1 sub-finding: "проверка
#      no-op стоит ДО guard-а ... второй, ещё более короткий путь того же обхода"). A target
#      whose STAGE NAME coincides with the current `stage` value, but whose TRACK just
#      changed, must NOT be treated as a free no-op — the guard (step 3) now runs BEFORE the
#      no-op check (step 4) precisely to close this ----
echo "[26] retrack: patch/Execution (zero artifacts) -> track changed to full, target='Execution' (same name) MUST be rejected, not treated as no-op"
setup_sdx_repo "t26" "patch" "Execution"
sf26="$(state_file t26)"
jq '.track = "full"' "$sf26" > "$sf26.tmp" && mv "$sf26.tmp" "$sf26"
before_sum="$(md5sum "$sf26" | cut -d' ' -f1)"
out="$(run_stage retrack "t26" "Execution" 2>&1 1>/dev/null)"
ec=$?
after_sum="$(md5sum "$sf26" | cut -d' ' -f1)"
if [ "$ec" -eq 1 ] && [ "$before_sum" = "$after_sum" ] && printf '%s' "$out" | grep -q "retrack"; then
  pass "same-named target across a track change is rejected, not silently accepted as no-op"
else
  fail "Expected the no-op shortcut to NOT bypass the guard" "ec=$ec out='$out' before=$before_sum after=$after_sum"
fi
cleanup

# ---- Scenario 27: retrack+retrack composition (W-5) — a genuine round trip (full -> patch
#      -> full) where REAL evidence for Discovery/Business Spec/Technical Design already
#      exists on disk must still be allowed to land back on Task Planning (this is NOT the
#      F-1 ratchet: the artifacts are real, created before either retrack call, not
#      conjured by the calls themselves — proves the fix is not a dead end), but reaching
#      one stage FURTHER (Documentation, whose preceding chain additionally needs Task
#      Planning's own PLAN.md) must still be rejected ----
echo "[27] retrack+retrack: full (real Discovery/Spec/Design evidence) -> patch -> full round-trip still reaches Task Planning, but not Documentation without PLAN.md"
setup_sdx_repo "t27" "full" "Task Planning"
seed_gate_artifacts "t27" "full" "Task Planning"   # context_report.md, SPEC.md, DESIGN.md — real, pre-existing evidence; PLAN.md deliberately absent
sf27="$(state_file t27)"

jq '.track = "patch"' "$sf27" > "$sf27.tmp" && mv "$sf27.tmp" "$sf27"
out1="$(run_stage retrack "t27" "Execution")"
ec1=$?
hop1_ok=0
[ "$ec1" -eq 0 ] && [ "$(jq -r '.stage' "$sf27")" = "Execution" ] && hop1_ok=1

jq '.track = "full"' "$sf27" > "$sf27.tmp" && mv "$sf27.tmp" "$sf27"
out2="$(run_stage retrack "t27" "Task Planning")"
ec2=$?
hop2_ok=0
[ "$ec2" -eq 0 ] && [ "$(jq -r '.stage' "$sf27")" = "Task Planning" ] && hop2_ok=1

out3="$(run_stage retrack "t27" "Documentation" 2>&1 1>/dev/null)"
ec3=$?
hop3_rejected=0
[ "$ec3" -eq 1 ] && [ "$(jq -r '.stage' "$sf27")" = "Task Planning" ] && hop3_rejected=1

cleanup
if [ "$hop1_ok" -eq 1 ] && [ "$hop2_ok" -eq 1 ] && [ "$hop3_rejected" -eq 1 ]; then
  pass "real pre-existing evidence survives a track round-trip (no dead end); Documentation still needs PLAN.md"
else
  fail "Expected round-trip to preserve real evidence but not manufacture PLAN.md's" "ec1=$ec1 ec2=$ec2 out2='$out2' ec3=$ec3 out3='$out3'"
fi

# ---- Scenario 28: retrack + backtrack + next composition (W-5) — verifies no chain of
#      legitimate single-step moves lands `stage` on a target whose preceding chain lacks
#      evidence, even when a `backtrack` marks an artifact outdated along the way (outdated
#      banners do NOT empty the file — see scenario [29] for why that is intentional, not a
#      new gap) ----
echo "[28] retrack+backtrack+next: backtrack (outdated-marks DESIGN.md) then retrack to standard/Change (OK, empty preceding chain) then next requires change_note.md (rejected)"
setup_sdx_repo "t28" "full" "Task Planning"
seed_gate_artifacts "t28" "full" "Task Planning"   # context_report.md, SPEC.md, DESIGN.md present; PLAN.md deliberately absent
out_bt="$(run_stage backtrack "t28" "Business Spec")"
ec_bt=$?
sf28="$(state_file t28)"
bt_ok=0
[ "$ec_bt" -eq 0 ] && [ "$(jq -r '.stage' "$sf28")" = "Business Spec" ] && bt_ok=1

jq '.track = "standard"' "$sf28" > "$sf28.tmp" && mv "$sf28.tmp" "$sf28"
out_rt="$(run_stage retrack "t28" "Change")"
ec_rt=$?
rt_ok=0
[ "$ec_rt" -eq 0 ] && [ "$(jq -r '.stage' "$sf28")" = "Change" ] && rt_ok=1

out_next="$(run_stage next "t28" 2>&1 1>/dev/null)"
ec_next=$?
next_rejected=0
[ "$ec_next" -eq 1 ] && [ "$(jq -r '.stage' "$sf28")" = "Change" ] && printf '%s' "$out_next" | grep -q "change_note.md" && next_rejected=1

cleanup
if [ "$bt_ok" -eq 1 ] && [ "$rt_ok" -eq 1 ] && [ "$next_rejected" -eq 1 ]; then
  pass "backtrack->retrack->next chain still requires change_note.md to leave Change, no free pass"
else
  fail "Expected the 3-step chain to still require real evidence to advance" "ec_bt=$ec_bt ec_rt=$ec_rt out_rt='$out_rt' ec_next=$ec_next out_next='$out_next'"
fi

# ---- Scenario 29: retrack — an outdated-marked (banner-prepended) artifact still counts as
#      satisfied preceding evidence. Intentional: mark_outdated only PREPENDS a banner, never
#      truncates the file (REQ-BACKTRACK-2) — the same forward gate in cmd_next already
#      tolerates this (it only checks existence+non-empty), so the artifact-floor guard in
#      cmd_retrack stays consistent with it rather than inventing a stricter standard ----
echo "[29] retrack: an outdated-marked artifact still counts as satisfied preceding evidence"
setup_sdx_repo "t29" "full" "Task Planning"
seed_gate_artifacts "t29" "full" "Task Planning"   # context_report.md, SPEC.md, DESIGN.md
run_stage backtrack "t29" "Business Spec" > /dev/null   # marks DESIGN.md outdated (banner prepended, content preserved)
sf29="$(state_file t29)"
design_first_line="$(head -1 "$TMPPROJ/.claude/sessions/t29/DESIGN.md")"
out="$(run_stage retrack "t29" "Task Planning")"
ec=$?
if printf '%s' "$design_first_line" | grep -q "SDX-OUTDATED" \
   && [ "$ec" -eq 0 ] && [ "$(jq -r '.stage' "$sf29")" = "Task Planning" ]; then
  pass "DESIGN.md carries the outdated banner yet still counts as Technical Design's evidence"
else
  fail "Expected outdated banner not to invalidate preceding evidence" "ec=$ec out='$out' design1='$design_first_line'"
fi
cleanup

# ---- Scenario 30: retrack — W-6 real-world repro fixed: full/Deployment -> standard,
#      target=Closeout. Standard's `Change` has no artifact of its own that a full-track
#      session would ever produce (it never writes change_note.md) — under
#      stage_artifact_ok's documented equivalence, SPEC.md+DESIGN.md (full's real evidence)
#      stand in for it. Sub-case (b): a FAIL marker in verification_report.md still blocks
#      the chain, same as it would for a native standard-track session ----
echo "[30] retrack: full/Deployment -> standard, target=Closeout — W-6 fixed via SPEC.md+DESIGN.md standing in for Change; FAIL marker still blocks"
setup_sdx_repo "t30a" "full" "Deployment"
printf '# Spec\n' > "$TMPPROJ/.claude/sessions/t30a/SPEC.md"
printf '# Design\n' > "$TMPPROJ/.claude/sessions/t30a/DESIGN.md"
printf 'PASS\n' > "$TMPPROJ/.claude/sessions/t30a/verification_report.md"
sf30a="$(state_file t30a)"
jq '.track = "standard"' "$sf30a" > "$sf30a.tmp" && mv "$sf30a.tmp" "$sf30a"
out="$(run_stage retrack "t30a" "Closeout")"
ec=$?
ok_a=0
[ "$ec" -eq 0 ] && [ "$(jq -r '.stage' "$sf30a")" = "Closeout" ] && ok_a=1
cleanup

setup_sdx_repo "t30b" "full" "Deployment"
printf '# Spec\n' > "$TMPPROJ/.claude/sessions/t30b/SPEC.md"
printf '# Design\n' > "$TMPPROJ/.claude/sessions/t30b/DESIGN.md"
printf '### [FAIL] [Correctness] still broken\n' > "$TMPPROJ/.claude/sessions/t30b/verification_report.md"
sf30b="$(state_file t30b)"
jq '.track = "standard"' "$sf30b" > "$sf30b.tmp" && mv "$sf30b.tmp" "$sf30b"
out2="$(run_stage retrack "t30b" "Closeout" 2>&1 1>/dev/null)"
ec2=$?
ok_b=0
[ "$ec2" -eq 1 ] && [ "$(jq -r '.stage' "$sf30b")" != "Closeout" ] && ok_b=1
cleanup

if [ "$ok_a" -eq 1 ] && [ "$ok_b" -eq 1 ]; then
  pass "SPEC.md+DESIGN.md let Deployment deescalate straight to Closeout; a FAIL marker still blocks it"
else
  fail "Expected W-6 fixed with FAIL marker still enforced" "ec=$ec out='$out' ec2=$ec2 out2='$out2'"
fi

# ---- Scenario 31: retrack — Change equivalence, the OTHER branch: change_note.md ALONE
#      (no SPEC.md/DESIGN.md) also satisfies Change — the native patch/standard evidence,
#      symmetric to scenario [30]'s full-track evidence ----
echo "[31] retrack: change_note.md alone (no SPEC.md/DESIGN.md) also satisfies Change, Closeout reachable"
setup_sdx_repo "t31" "standard" "Execution"
printf 'change note\n' > "$TMPPROJ/.claude/sessions/t31/change_note.md"
printf 'PASS\n' > "$TMPPROJ/.claude/sessions/t31/verification_report.md"
out="$(run_stage retrack "t31" "Closeout")"
ec=$?
sf="$(state_file t31)"
if [ "$ec" -eq 0 ] && [ "$(jq -r '.stage' "$sf")" = "Closeout" ]; then
  pass "change_note.md alone (native evidence) also satisfies Change"
else
  fail "Expected change_note.md alone to satisfy Change" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 32: no jq in $PATH -> any mutating subcommand exits 2, file untouched ----
echo "[32] no jq in \$PATH -> exit 2, file untouched"
setup_sdx_repo "t17" "full" "Discovery"
printf 'notes\n' > "$TMPPROJ/.claude/sessions/t17/context_report.md"
sf="$(state_file t17)"
before_sum="$(md5sum "$sf" | cut -d' ' -f1)"
NOJQDIR="$(mktemp -d)"
# Build a minimal PATH containing only the essentials (no jq) — link bash/coreutils dir.
for bin in bash sh mktemp cat mv rm grep sed awk head tail printf md5sum dirname; do
  p="$(command -v "$bin" 2>/dev/null || true)"
  [ -n "$p" ] && ln -sf "$p" "$NOJQDIR/$bin" 2>/dev/null
done
out="$(CLAUDE_PROJECT_DIR="$TMPPROJ" PATH="$NOJQDIR" bash "$SCRIPT" next "t17" 2>&1 1>/dev/null)"
ec=$?
after_sum="$(md5sum "$sf" | cut -d' ' -f1)"
rm -rf "$NOJQDIR"
if [ "$ec" -eq 2 ] && [ "$before_sum" = "$after_sum" ] && printf '%s' "$out" | grep -q "jq не найден"; then
  pass "exit 2, file untouched, 'jq не найден' message"
else
  fail "Expected fail-closed without jq" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 33: write_stage atomicity — no leftover temp files, original stays valid JSON ----
echo "[33] write_stage atomicity: broken jq (no jq) leaves no temp files, original stays valid+unchanged"
setup_sdx_repo "t18" "full" "Discovery"
printf 'notes\n' > "$TMPPROJ/.claude/sessions/t18/context_report.md"
sf="$(state_file t18)"
sdir="$(dirname "$sf")"
NOJQDIR="$(mktemp -d)"
for bin in bash sh mktemp cat mv rm grep sed awk head tail printf md5sum dirname; do
  p="$(command -v "$bin" 2>/dev/null || true)"
  [ -n "$p" ] && ln -sf "$p" "$NOJQDIR/$bin" 2>/dev/null
done
CLAUDE_PROJECT_DIR="$TMPPROJ" PATH="$NOJQDIR" bash "$SCRIPT" next "t18" > /dev/null 2>&1
rm -rf "$NOJQDIR"
leftover="$(find "$sdir" -maxdepth 1 -name 'session_state.json.*' 2>/dev/null | wc -l | tr -d ' ')"
if jq -e . "$sf" > /dev/null 2>&1 && [ "$(jq -r '.stage' "$sf")" = "Discovery" ] && [ "$leftover" -eq 0 ]; then
  pass "original remains valid JSON with prior stage, no *.XXXXXX leftovers"
else
  fail "Expected valid untouched original + no temp leftovers" "leftover=$leftover stage=$(jq -r '.stage' "$sf" 2>/dev/null)"
fi
cleanup

# ---- Scenario 34: sanity cross-check — ALL FIVE tracks, order-sensitive (W-5) ----
# Previously this only checked the 'full' row, as an unordered SET (both sorted before
# comparison) — a swap of two stages in either document, or a drift in 'patch'/'standard',
# would go undetected. Now checks all five tracks in the exact row order (no sorting), so
# reordering is caught too. NOTE: protocol.md's chain cells may carry trailing parenthetical
# annotations on a stage name (e.g. "Discovery (лёгкий, инлайн)", "Verification (лёгкая,
# обязательная — ADR-014)") — stripped before comparison, they annotate, not rename, the
# stage. Split on the literal " → " string via sed/awk (NOT `tr '→' '\n'`): `tr` treats its
# argument byte-by-byte, and "→" (U+2192, bytes E2 86 92) shares its lead byte with "—"
# (U+2014, bytes E2 80 94) used inside the patch-row annotation — byte-wise `tr` corrupts
# that annotation text. sed/awk match the multi-byte separator as a whole string, so they
# don't have this problem.
echo "[34] sanity: SDX_STAGE_MATRIX matches sdx/protocol.md's track table for full/standard/patch/doc/vibe, in order"
proto="$SCRIPT_DIR/../protocol.md"
sanity_all_ok=1
sanity_detail=""
for track in full standard patch doc vibe; do
  proto_row="$(grep "^| \*\*$track\*\*" "$proto")"
  proto_chain="$(printf '%s' "$proto_row" | awk -F'|' '{print $4}')"
  proto_stages="$(printf '%s\n' "$proto_chain" \
    | sed 's/ → /\n/g' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | sed -E 's/[[:space:]]*\([^()]*\)[[:space:]]*$//' \
    | grep -v '^$')"
  matrix_stages_this="$(grep -E "^${track}\|" "$SCRIPT" | cut -d'|' -f2)"
  if [ -z "$proto_stages" ] || [ "$proto_stages" != "$matrix_stages_this" ]; then
    sanity_all_ok=0
    sanity_detail="$sanity_detail track=$track proto=[$(printf '%s' "$proto_stages" | tr '\n' ',')] matrix=[$(printf '%s' "$matrix_stages_this" | tr '\n' ',')];"
  fi
done
if [ "$sanity_all_ok" -eq 1 ]; then
  pass "protocol.md matches SDX_STAGE_MATRIX for full/standard/patch/doc/vibe, order included"
else
  fail "Expected matching ordered stage chains for all 5 tracks" "$sanity_detail"
fi

# ---- Scenario 35: sanity — SDX_CANON_ORDER (the old rank-based ceiling, F-1's root cause)
#      is gone from the script, not just unused. cmd_retrack no longer derives ANY ceiling
#      from a self-reported `stage` position (canon_rank/SDX_CANON_ORDER) — REQ-RETRACK-2's
#      guard is entirely evidence-based now (stage_artifact_ok walking matrix_row/
#      matrix_index). This guards against the dead code silently creeping back in a future
#      edit and being (re-)wired into the guard by accident ----
echo "[35] sanity: SDX_CANON_ORDER / canon_rank dead code fully removed from sdx-stage.sh"
if ! grep -q 'SDX_CANON_ORDER' "$SCRIPT" && ! grep -q 'canon_rank' "$SCRIPT"; then
  pass "no remaining reference to SDX_CANON_ORDER or canon_rank"
else
  fail "Expected the old rank-based mechanism to be fully removed" "$(grep -n 'SDX_CANON_ORDER\|canon_rank' "$SCRIPT")"
fi

# ---- Scenario 36: init — track=doc, stage=Discovery (first active stage) -> success (T-3a) ----
echo "[36] init: track=doc, stage=Discovery (first active stage) -> success"
TMPPROJ="$(mktemp -d)"
out="$(run_stage init "t36" "grooming" "doc" "Discovery" "interactive" "sdx/t36")"
ec=$?
sf="$(state_file t36)"
if [ "$ec" -eq 0 ] && [ -f "$sf" ] && [ "$(jq -r '.stage' "$sf")" = "Discovery" ] \
   && [ "$(jq -r '.track' "$sf")" = "doc" ]; then
  pass "doc track initialized at Discovery, exit 0"
else
  fail "Expected doc/Discovery init to succeed" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 37: init — track=doc, stage=Update (NOT the first active stage) -> exit 2 (T-3b) ----
echo "[37] init: track=doc, stage=Update (not first active stage) -> exit 2"
TMPPROJ="$(mktemp -d)"
out="$(run_stage init "t37" "grooming" "doc" "Update" "interactive" "sdx/t37" 2>&1 1>/dev/null)"
ec=$?
sf="$(state_file t37)"
if [ "$ec" -eq 2 ] && [ ! -f "$sf" ]; then
  pass "exit 2, no state file created for non-first stage"
else
  fail "Expected init rejection for non-first stage" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 38: next — doc: Discovery -> Update, no gate (artifact "-") -> always success (T-4) ----
echo "[38] next: doc Discovery -> Update, no gate artifact -> always success"
setup_sdx_repo "t38" "doc" "Discovery"
out="$(run_stage next "t38")"
ec=$?
sf="$(state_file t38)"
if [ "$ec" -eq 0 ] && [ "$(jq -r '.stage' "$sf")" = "Update" ] \
   && [ "$out" = "OK Discovery -> Update" ]; then
  pass "doc: Discovery -> Update without a gate artifact"
else
  fail "Expected doc Discovery -> Update to succeed unconditionally" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 39: next — doc: Update -> Verification, empty/missing change_note.md -> exit 1 (T-4) ----
echo "[39] next: doc Update -> Verification, missing change_note.md -> exit 1, stderr names change_note.md"
setup_sdx_repo "t39" "doc" "Update"
out="$(run_stage next "t39" 2>&1 1>/dev/null)"
ec=$?
sf="$(state_file t39)"
if [ "$ec" -eq 1 ] && [ "$(jq -r '.stage' "$sf")" = "Update" ] \
   && printf '%s' "$out" | grep -q "change_note.md"; then
  pass "exit 1, stage unchanged, stderr names change_note.md"
else
  fail "Expected doc Update gate rejection" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 40: next — doc: Update -> Verification, non-empty change_note.md -> exit 0 (T-4) ----
echo "[40] next: doc Update -> Verification, non-empty change_note.md -> exit 0"
setup_sdx_repo "t40" "doc" "Update"
printf 'change note\n' > "$TMPPROJ/.claude/sessions/t40/change_note.md"
out="$(run_stage next "t40")"
ec=$?
sf="$(state_file t40)"
if [ "$ec" -eq 0 ] && [ "$(jq -r '.stage' "$sf")" = "Verification" ] \
   && [ "$out" = "OK Update -> Verification" ]; then
  pass "doc: Update -> Verification with non-empty change_note.md"
else
  fail "Expected doc Update -> Verification to succeed" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 41: next — doc: Verification -> Closeout, verification_report.md has [FAIL] -> exit 1 (T-4) ----
echo "[41] next: doc Verification -> Closeout, verification_report.md contains ### [FAIL] -> exit 1, points to Update (not Execution)"
setup_sdx_repo "t41" "doc" "Verification"
printf '### [FAIL] [Correctness] something broken\n' > "$TMPPROJ/.claude/sessions/t41/verification_report.md"
out="$(run_stage next "t41" 2>&1 1>/dev/null)"
ec=$?
sf="$(state_file t41)"
# Remediation hint must name a stage that is ACTIVE in the track: doc has no Execution,
# so pointing there would hand the user a second error from /sdx:backtrack.
if [ "$ec" -eq 1 ] && [ "$(jq -r '.stage' "$sf")" = "Verification" ] \
   && printf '%s' "$out" | grep -q "FAIL" \
   && printf '%s' "$out" | grep -q "backtrack --to Update" \
   && ! printf '%s' "$out" | grep -q "Execution"; then
  pass "exit 1, FAIL marker blocks doc Verification -> Closeout, hint names Update"
else
  fail "Expected doc Verification FAIL-marker rejection pointing at Update" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 42: next — doc: Verification -> Closeout, clean verification_report.md -> exit 0 (T-4) ----
echo "[42] next: doc Verification -> Closeout, clean verification_report.md -> exit 0"
setup_sdx_repo "t42" "doc" "Verification"
printf 'PASS\n' > "$TMPPROJ/.claude/sessions/t42/verification_report.md"
out="$(run_stage next "t42")"
ec=$?
sf="$(state_file t42)"
if [ "$ec" -eq 0 ] && [ "$(jq -r '.stage' "$sf")" = "Closeout" ] \
   && [ "$out" = "OK Verification -> Closeout" ]; then
  pass "doc: Verification -> Closeout with clean report"
else
  fail "Expected doc Verification -> Closeout to succeed" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 43: next — doc: stage=Closeout (terminal) -> exit 0 no-op (T-4) ----
echo "[43] next: doc stage=Closeout (terminal) -> exit 0 no-op"
setup_sdx_repo "t43" "doc" "Closeout"
sf="$(state_file t43)"
before_sum="$(md5sum "$sf" | cut -d' ' -f1)"
out="$(run_stage next "t43")"
ec=$?
after_sum="$(md5sum "$sf" | cut -d' ' -f1)"
if [ "$ec" -eq 0 ] && [ "$out" = "OK no-op Closeout" ] && [ "$before_sum" = "$after_sum" ]; then
  pass "doc: no-op on terminal Closeout, file untouched"
else
  fail "Expected doc no-op on Closeout" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 44: backtrack — doc: --to Discovery from Closeout marks BOTH artifacts
#      (change_note.md AND verification_report.md, if both exist) without an upper bound at
#      the current stage (T-5, mirrors [15]/W-1 but for the 4-stage doc track) ----
echo "[44] backtrack: doc --to Discovery from Closeout marks change_note.md AND verification_report.md"
setup_sdx_repo "t44" "doc" "Closeout"
printf 'change note\n' > "$TMPPROJ/.claude/sessions/t44/change_note.md"
printf 'report\n' > "$TMPPROJ/.claude/sessions/t44/verification_report.md"
out="$(run_stage backtrack "t44" "Discovery")"
ec=$?
sf="$(state_file t44)"
change_first_line="$(head -1 "$TMPPROJ/.claude/sessions/t44/change_note.md")"
report_first_line="$(head -1 "$TMPPROJ/.claude/sessions/t44/verification_report.md")"
if [ "$ec" -eq 0 ] && [ "$(jq -r '.stage' "$sf")" = "Discovery" ] \
   && printf '%s' "$change_first_line" | grep -q 'SDX-OUTDATED' \
   && printf '%s' "$report_first_line" | grep -q 'SDX-OUTDATED'; then
  pass "both change_note.md and verification_report.md marked outdated"
else
  fail "Expected both doc artifacts marked outdated" "ec=$ec out='$out' change1='$change_first_line' report1='$report_first_line'"
fi
cleanup

# ---- Scenario 45: retrack — escalation doc -> standard, target=Change, non-empty
#      change_note.md accumulated on doc|Update -> exit 0 landing on Change, AND the SAME
#      file (never rewritten) is then accepted by `next` as Change's own gate artifact ->
#      exit 0 into Execution (file-name coincidence transfers the artifact for free, not
#      merely "Change's predecessor chain happens to be trivially empty") (T-6a) ----
#      NOTE: retrack's forward-skip guard only proves the chain of stages PRECEDING the
#      target (here: standard|Discovery, artifact "-", trivially satisfied) — it does not
#      itself consume change_note.md. Asserting only the retrack exit code would pass even
#      if the file were absent (regression: this scenario was green with the
#      `printf ... > change_note.md` line removed). The follow-up `next` call is the part
#      that actually depends on the pre-existing file — it fails with a missing/empty
#      change_note.md, and only succeeds because the doc-Update file transferred for free.
echo "[45] retrack: escalation doc -> standard, target=Change, change_note.md from doc|Update transfers for free and is then consumed by next"
setup_sdx_repo "t45" "standard" "Update"
printf 'accumulated during doc Update\n' > "$TMPPROJ/.claude/sessions/t45/change_note.md"
out="$(run_stage retrack "t45" "Change")"
ec=$?
sf="$(state_file t45)"
retrack_ok=0
[ "$ec" -eq 0 ] && [ "$(jq -r '.stage' "$sf")" = "Change" ] && retrack_ok=1

out_next="$(run_stage next "t45")"
ec_next=$?
next_ok=0
[ "$ec_next" -eq 0 ] && [ "$(jq -r '.stage' "$sf")" = "Execution" ] && next_ok=1

if [ "$retrack_ok" -eq 1 ] && [ "$next_ok" -eq 1 ]; then
  pass "doc's change_note.md satisfies standard's Change gate via filename coincidence (retrack lands on Change, next consumes the same file into Execution)"
else
  fail "Expected doc -> standard escalation to Change, then next to Execution, to both succeed" "ec=$ec out='$out' ec_next=$ec_next out_next='$out_next'"
fi
cleanup

# ---- Scenario 46: retrack — escalation doc -> full, target=Business Spec, WITHOUT
#      context_report.md on disk -> exit 1 (forward-skip guard: full's Discovery is not
#      trivial, unlike standard's) (T-6b) ----
echo "[46] retrack: escalation doc -> full, target=Business Spec, no context_report.md -> exit 1"
setup_sdx_repo "t46" "full" "Update"
out="$(run_stage retrack "t46" "Business Spec" 2>&1 1>/dev/null)"
ec=$?
sf="$(state_file t46)"
if [ "$ec" -eq 1 ] && [ "$(jq -r '.stage' "$sf")" != "Business Spec" ]; then
  pass "forward-skip guard blocks doc -> full jump to Business Spec without context_report.md"
else
  fail "Expected doc -> full escalation to Business Spec to be rejected" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 47: retrack — doc -> full, target=Discovery (full's own first active
#      stage) -> exit 0 unconditionally (safe fallback) (T-6c) ----
echo "[47] retrack: doc -> full, target=Discovery (full's own first active stage) -> exit 0"
setup_sdx_repo "t47" "full" "Update"
out="$(run_stage retrack "t47" "Discovery")"
ec=$?
sf="$(state_file t47)"
if [ "$ec" -eq 0 ] && [ "$(jq -r '.stage' "$sf")" = "Discovery" ]; then
  pass "doc -> full lands unconditionally on full's own first active stage"
else
  fail "Expected doc -> full escalation to Discovery to succeed unconditionally" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 48: fix_stage fallback when a FAIL-marked stage is a track's OWN first
#      active stage — a case unreachable with the real SDX_STAGE_MATRIX (Verification is
#      never first) but a real edge case in the `matrix_index - 1` arithmetic
#      (`sed -n "0p"` on a hypothetical track would silently print nothing, producing an
#      empty "/sdx:backtrack --to " remediation hint). Exercised against a PATCHED copy of
#      the script with one synthetic track appended to SDX_STAGE_MATRIX, rather than the
#      real matrix, specifically because the real matrix cannot reach this branch.
echo "[48] next: fix_stage fallback when the FAIL-marked stage is the track's own first active stage"
SCRIPT_T48="$(mktemp)"
# Verification must NOT also be the track's LAST stage, or cmd_next's no-op
# short-circuit ("$stage" = "$last") fires before the gate/FAIL check ever runs — so the
# synthetic track needs a stage after Verification too (mirrors every real track, where
# Verification is always followed by Closeout).
sed 's/^doc|Closeout|-|no$/doc|Closeout|-|no\nzzztest|Verification|verification_report.md|yes\nzzztest|Closeout|-|no/' "$SCRIPT" > "$SCRIPT_T48"
chmod +x "$SCRIPT_T48"
if ! grep -q '^zzztest|Verification|verification_report.md|yes$' "$SCRIPT_T48"; then
  fail "Expected synthetic track row to be injected into patched script copy" "sed did not match — script format changed?"
else
  setup_sdx_repo "t48" "zzztest" "Verification"
  printf '### [FAIL] synthetic finding\n' > "$TMPPROJ/.claude/sessions/t48/verification_report.md"
  out48="$(CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$SCRIPT_T48" next "t48" 2>&1 1>/dev/null)"
  ec48=$?
  sf48="$(state_file t48)"
  if [ "$ec48" -eq 1 ] && [ "$(jq -r '.stage' "$sf48")" = "Verification" ] \
     && printf '%s' "$out48" | grep -q 'backtrack --to Verification' \
     && ! printf '%s' "$out48" | grep -q 'backtrack --to $'; then
    pass "fix_stage falls back to the track's own first active stage instead of an empty hint"
  else
    fail "Expected non-empty fix_stage fallback naming 'Verification'" "ec48=$ec48 out48='$out48'"
  fi
  cleanup
fi
rm -f "$SCRIPT_T48"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "ALL PASSED"
  exit 0
else
  exit 1
fi
