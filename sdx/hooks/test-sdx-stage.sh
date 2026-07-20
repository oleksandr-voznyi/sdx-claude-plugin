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

# ---- Scenario 16: retrack — track already updated to standard, target=Change active -> stage changes ----
echo "[16] retrack: track already updated to standard, target=Change active -> stage changes without forward-gate"
setup_sdx_repo "t16" "standard" "Discovery"
# change_note.md deliberately absent — retrack has no forward-gate.
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

# ---- Scenario 20: retrack — target == current stage -> exit 0 no-op, file untouched (REQ-STAGE-4/W-4) ----
echo "[20] retrack: target == current stage -> exit 0 no-op, file untouched"
setup_sdx_repo "t20r" "full" "Execution"
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

# ---- Scenario 21: no jq in $PATH -> any mutating subcommand exits 2, file untouched ----
echo "[21] no jq in \$PATH -> exit 2, file untouched"
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

# ---- Scenario 22: write_stage atomicity — no leftover temp files, original stays valid JSON ----
echo "[22] write_stage atomicity: broken jq (no jq) leaves no temp files, original stays valid+unchanged"
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

# ---- Scenario 23: sanity cross-check — ALL THREE tracks, order-sensitive (W-5) ----
# Previously this only checked the 'full' row, as an unordered SET (both sorted before
# comparison) — a swap of two stages in either document, or a drift in 'patch'/'standard',
# would go undetected. Now checks all three tracks in the exact row order (no sorting), so
# reordering is caught too. NOTE: protocol.md's chain cells may carry trailing parenthetical
# annotations on a stage name (e.g. "Discovery (лёгкий, инлайн)", "Verification (лёгкая,
# обязательная — ADR-014)") — stripped before comparison, they annotate, not rename, the
# stage. Split on the literal " → " string via sed/awk (NOT `tr '→' '\n'`): `tr` treats its
# argument byte-by-byte, and "→" (U+2192, bytes E2 86 92) shares its lead byte with "—"
# (U+2014, bytes E2 80 94) used inside the patch-row annotation — byte-wise `tr` corrupts
# that annotation text. sed/awk match the multi-byte separator as a whole string, so they
# don't have this problem.
echo "[23] sanity: SDX_STAGE_MATRIX matches sdx/protocol.md's track table for full/standard/patch, in order"
proto="$SCRIPT_DIR/../protocol.md"
sanity_all_ok=1
sanity_detail=""
for track in full standard patch; do
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
  pass "protocol.md matches SDX_STAGE_MATRIX for full/standard/patch, order included"
else
  fail "Expected matching ordered stage chains for all 3 tracks" "$sanity_detail"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "ALL PASSED"
  exit 0
else
  exit 1
fi
