#!/usr/bin/env bash
# Integration test: sdx-stage.sh (the sole `stage` writer) exercised end-to-end, as the
# /sdx:* commands would drive it, across several realistic session shapes. The unit suite
# (test-sdx-stage.sh) already covers every subcommand/branch in isolation with
# purpose-built fixtures; this suite instead walks CONTINUOUS sessions through a realistic
# sequence of calls to catch integration-level regressions (e.g. a later call reading a
# field an earlier call left in an unexpected shape) that isolated unit fixtures cannot.
#
# ADR-020: stage-write-guard.sh (formerly exercised here as the "deny" half of the
# integration story, scenario [13] of the old suite) has been removed without replacement
# (REQ-ENF-1) — this suite now covers ONLY sdx-stage.sh's own behaviour.
#
# Self-contained: creates its own temp "project" dir, cleans up via trap, no network/
# timing dependencies. Picked up automatically by verify-cmd.sh's test-*.sh glob.
# Usage: bash sdx/hooks/test-integration-stage-lifecycle.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_SCRIPT="$SCRIPT_DIR/sdx-stage.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

TMPPROJ=""
cleanup() { [ -n "$TMPPROJ" ] && rm -rf "$TMPPROJ"; TMPPROJ=""; }
trap cleanup EXIT

TMPPROJ="$(mktemp -d)"

echo "=== test-integration-stage-lifecycle.sh ==="
echo ""

# =========================================================================================
# Part A [1]-[7]: a single ordinary (no_code=false, no_gates=false) session walked linearly
# through all nine canonical stages via plain `next`, then backward via `next --to`.
# =========================================================================================

SID="it-linear"
SDIR="$TMPPROJ/.claude/sessions/$SID"
STATE="$SDIR/session_state.json"
LOG="$SDIR/session.log"

run_stage() { CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$STAGE_SCRIPT" "$@"; }
cur_stage() { jq -r '.stage' "$STATE"; }

echo "[1] init: ordinary session starts at Discovery, seeds session.log"
out="$(run_stage init "$SID" "feature" "Discovery" "interactive" "sdx/$SID" "false" "false")"
ec=$?
if [ "$ec" -eq 0 ] && [ -f "$STATE" ] && [ "$(cur_stage)" = "Discovery" ] && grep -q '\[START\]' "$LOG"; then
  pass "session_state.json + session.log created, stage=Discovery"
else
  fail "Expected initialized session at Discovery" "ec=$ec out='$out'"
fi

echo "[2] next: Discovery -> Business Spec (context_report.md present+non-empty)"
printf 'discovery notes\n' > "$SDIR/context_report.md"
out="$(run_stage next "$SID")"; ec=$?
if [ "$ec" -eq 0 ] && [ "$(cur_stage)" = "Business Spec" ]; then
  pass "advanced to Business Spec"
else
  fail "Expected Business Spec" "ec=$ec out='$out'"
fi

echo "[3] next: Business Spec -> Technical Design (SPEC.md present)"
printf '# SPEC\n' > "$SDIR/SPEC.md"
out="$(run_stage next "$SID")"; ec=$?
if [ "$ec" -eq 0 ] && [ "$(cur_stage)" = "Technical Design" ]; then
  pass "advanced to Technical Design"
else
  fail "Expected Technical Design" "ec=$ec out='$out'"
fi

echo "[4] next: Technical Design -> Task Planning (DESIGN.md present)"
printf '# DESIGN\n' > "$SDIR/DESIGN.md"
out="$(run_stage next "$SID")"; ec=$?
if [ "$ec" -eq 0 ] && [ "$(cur_stage)" = "Task Planning" ]; then
  pass "advanced to Task Planning"
else
  fail "Expected Task Planning" "ec=$ec out='$out'"
fi

echo "[5] next: Task Planning -> Execution (PLAN.md present)"
printf '# PLAN\n' > "$SDIR/PLAN.md"
out="$(run_stage next "$SID")"; ec=$?
if [ "$ec" -eq 0 ] && [ "$(cur_stage)" = "Execution" ]; then
  pass "advanced to Execution"
else
  fail "Expected Execution" "ec=$ec out='$out'"
fi

echo "[6] next x3: Execution -> Documentation -> Verification -> Closeout (no objectively checkable gate for Execution/Documentation, verification_report.md clean)"
out="$(run_stage next "$SID")"; ec=$?  # Execution -> Documentation
ok1=$([ "$ec" -eq 0 ] && [ "$(cur_stage)" = "Documentation" ] && echo 1 || echo 0)
out="$(run_stage next "$SID")"; ec=$?  # Documentation -> Verification
ok2=$([ "$ec" -eq 0 ] && [ "$(cur_stage)" = "Verification" ] && echo 1 || echo 0)
printf 'PASS\n' > "$SDIR/verification_report.md"
out="$(run_stage next "$SID")"; ec=$?  # Verification -> Deployment
ok3=$([ "$ec" -eq 0 ] && [ "$(cur_stage)" = "Deployment" ] && echo 1 || echo 0)
out="$(run_stage next "$SID")"; ec=$?  # Deployment -> Closeout
ok4=$([ "$ec" -eq 0 ] && [ "$(cur_stage)" = "Closeout" ] && [ "$out" = "OK Deployment -> Closeout" ] && echo 1 || echo 0)
if [ "$ok1" = 1 ] && [ "$ok2" = 1 ] && [ "$ok3" = 1 ] && [ "$ok4" = 1 ]; then
  pass "walked Execution -> Documentation -> Verification -> Deployment -> Closeout"
else
  fail "Expected full walk to Closeout" "ok1=$ok1 ok2=$ok2 ok3=$ok3 ok4=$ok4 last_out='$out'"
fi

echo "[7] next --to: Closeout -> Business Spec backtrack marks all later artifacts outdated except Business Spec's own SPEC.md"
out="$(run_stage next "$SID" --to "Business Spec")"; ec=$?
spec_first="$(head -1 "$SDIR/SPEC.md")"
design_first="$(head -1 "$SDIR/DESIGN.md")"
plan_first="$(head -1 "$SDIR/PLAN.md")"
vr_first="$(head -1 "$SDIR/verification_report.md")"
if [ "$ec" -eq 0 ] && [ "$(cur_stage)" = "Business Spec" ] \
   && [ "$spec_first" = "# SPEC" ] \
   && printf '%s' "$design_first" | grep -q '<!-- SDX-OUTDATED' \
   && printf '%s' "$plan_first" | grep -q '<!-- SDX-OUTDATED' \
   && printf '%s' "$vr_first" | grep -q '<!-- SDX-OUTDATED'; then
  pass "backtrack succeeded, target's own SPEC.md untouched, all later artifacts marked outdated"
else
  fail "Expected backtrack + outdated marking of later artifacts" "ec=$ec out='$out' spec1='$spec_first' design1='$design_first' plan1='$plan_first' vr1='$vr_first'"
fi

# =========================================================================================
# Part B [8]: a small-delta session (no_code=false, no_gates=false) starting on Discovery,
# folding Business Spec/Technical Design/Task Planning into one change_note.md, then
# auto-skipping Task Planning/Execution/Documentation is NOT applicable here (no_code is
# false) — this session instead demonstrates REQ-SCALE-3 fold-credit end-to-end through the
# four planning stages using a single change_note.md, then a normal walk to Closeout.
# =========================================================================================

SID_FOLD="it-fold"
SDIR_FOLD="$TMPPROJ/.claude/sessions/$SID_FOLD"
STATE_FOLD="$SDIR_FOLD/session_state.json"
cur_stage_fold() { jq -r '.stage' "$STATE_FOLD"; }

echo "[8] fold-credit: one change_note.md carries a session through Discovery/Business Spec/Technical Design/Task Planning to Execution, then a normal walk to Closeout"
out="$(run_stage init "$SID_FOLD" "bug" "Discovery" "interactive" "sdx/$SID_FOLD" "false" "false")"
ec0=$?
printf '# change note\n' > "$SDIR_FOLD/change_note.md"
o1="$(run_stage next "$SID_FOLD")"; e1=$?   # Discovery -> Business Spec
o2="$(run_stage next "$SID_FOLD")"; e2=$?   # Business Spec -> Technical Design
o3="$(run_stage next "$SID_FOLD")"; e3=$?   # Technical Design -> Task Planning
o4="$(run_stage next "$SID_FOLD")"; e4=$?   # Task Planning -> Execution
o5="$(run_stage next "$SID_FOLD")"; e5=$?   # Execution -> Documentation
o6="$(run_stage next "$SID_FOLD")"; e6=$?   # Documentation -> Verification
printf 'PASS\n' > "$SDIR_FOLD/verification_report.md"
o7="$(run_stage next "$SID_FOLD")"; e7=$?   # Verification -> Deployment
o8="$(run_stage next "$SID_FOLD")"; e8=$?   # Deployment -> Closeout
if [ "$ec0" -eq 0 ] && [ "$e1" -eq 0 ] && [ "$e2" -eq 0 ] && [ "$e3" -eq 0 ] && [ "$e4" -eq 0 ] \
   && [ "$e5" -eq 0 ] && [ "$e6" -eq 0 ] && [ "$e7" -eq 0 ] && [ "$e8" -eq 0 ] \
   && [ "$(cur_stage_fold)" = "Closeout" ]; then
  pass "single change_note.md carries all four planning gates, session reaches Closeout"
else
  fail "Expected fold-credit walk to Closeout" "ec0=$ec0 e1=$e1 e2=$e2 e3=$e3 e4=$e4 e5=$e5 e6=$e6 e7=$e7 e8=$e8 o8='$o8'"
fi

# =========================================================================================
# Part C [9]: a composite no_code=true path — Discovery, through the four planning stages
# (fold-credited), auto-skipping Task Planning/Execution/Documentation, straight to
# Verification, then Closeout (REQ-SCALE-4 end-to-end).
# =========================================================================================

SID_NC="it-nocode"
SDIR_NC="$TMPPROJ/.claude/sessions/$SID_NC"
STATE_NC="$SDIR_NC/session_state.json"
cur_stage_nc() { jq -r '.stage' "$STATE_NC"; }

echo "[9] no_code=true composite path: Discovery -> (fold) Business Spec -> (fold) Technical Design -> (auto-skip Task Planning/Execution/Documentation) -> Verification -> Closeout"
out0="$(run_stage init "$SID_NC" "grooming" "Discovery" "interactive" "sdx/$SID_NC" "true" "false")"; ec0=$?
printf '# note\n' > "$SDIR_NC/change_note.md"
o1="$(run_stage next "$SID_NC")"; e1=$?   # Discovery -> Business Spec (fold)
o2="$(run_stage next "$SID_NC")"; e2=$?   # Business Spec -> Technical Design (fold)
o3="$(run_stage next "$SID_NC")"; e3=$?   # Technical Design -> Verification (auto-skip Task Planning/Execution/Documentation, fold)
mid_ok=$([ "$(cur_stage_nc)" = "Verification" ] && [ "$o3" = "OK Technical Design -> Verification" ] && echo 1 || echo 0)
printf 'PASS\n' > "$SDIR_NC/verification_report.md"
o4="$(run_stage next "$SID_NC")"; e4=$?   # Verification -> Closeout (Deployment excluded by no_code too)
if [ "$ec0" -eq 0 ] && [ "$e1" -eq 0 ] && [ "$e2" -eq 0 ] && [ "$e3" -eq 0 ] && [ "$mid_ok" = 1 ] \
   && [ "$e4" -eq 0 ] && [ "$(cur_stage_nc)" = "Closeout" ] && [ "$o4" = "OK Verification -> Closeout" ]; then
  pass "no_code composite path reaches Closeout, auto-skipping all four excluded stages"
else
  fail "Expected no_code composite path to Closeout" "ec0=$ec0 e1=$e1 o1='$o1' e2=$e2 o2='$o2' e3=$e3 o3='$o3' mid_ok=$mid_ok e4=$e4 o4='$o4'"
fi

# =========================================================================================
# Part D [10]: a no_gates=true session (proto type, ADR-018 legalization invariant) —
# several consecutive `next` calls stay a stable no-op, the file is never touched.
# =========================================================================================

SID_NG="it-nogates"
SDIR_NG="$TMPPROJ/.claude/sessions/$SID_NG"
STATE_NG="$SDIR_NG/session_state.json"
cur_stage_ng() { jq -r '.stage' "$STATE_NG"; }

echo "[10] no_gates=true: init on Execution, three consecutive next calls all no-op, file byte-for-byte unchanged"
out0="$(run_stage init "$SID_NG" "proto" "Execution" "interactive" "sdx/$SID_NG" "false" "true")"; ec0=$?
sum0="$(md5sum "$STATE_NG" | cut -d' ' -f1)"
o1="$(run_stage next "$SID_NG")"; e1=$?
o2="$(run_stage next "$SID_NG")"; e2=$?
o3="$(run_stage next "$SID_NG")"; e3=$?
sum3="$(md5sum "$STATE_NG" | cut -d' ' -f1)"
if [ "$ec0" -eq 0 ] && [ "$e1" -eq 0 ] && [ "$e2" -eq 0 ] && [ "$e3" -eq 0 ] \
   && [ "$o1" = "OK no-op Execution" ] && [ "$o2" = "OK no-op Execution" ] && [ "$o3" = "OK no-op Execution" ] \
   && [ "$sum0" = "$sum3" ] && [ "$(cur_stage_ng)" = "Execution" ]; then
  pass "no_gates session stays a stable no-op across repeated calls, file never touched"
else
  fail "Expected stable no_gates no-op" "ec0=$ec0 e1=$e1 o1='$o1' e2=$e2 o2='$o2' e3=$e3 o3='$o3'"
fi

# =========================================================================================
# Part E [11]: legalization as a composite scenario — NOT through a dedicated command, but
# through a direct Edit of `no_gates: true -> false` (the legitimate path now that there is
# no deny-hook) followed by ordinary `next` calls through Execution/Verification/Closeout.
# Demonstrates that legalization technically requires nothing from sdx-stage.sh beyond the
# usual `next` contract (commands/proto.md carries the prose part of the procedure).
# =========================================================================================

SID_LEG="it-legalize"
SDIR_LEG="$TMPPROJ/.claude/sessions/$SID_LEG"
STATE_LEG="$SDIR_LEG/session_state.json"
cur_stage_leg() { jq -r '.stage' "$STATE_LEG"; }

echo "[11] legalization: no_gates true->false via direct Edit, then ordinary next carries the session through to Closeout"
run_stage init "$SID_LEG" "proto" "Execution" "interactive" "sdx/$SID_LEG" "false" "true" > /dev/null
# Direct field edit (legitimate — no deny-hook exists after ADR-020/REQ-ENF-1) mimicking
# commands/proto.md's legalization step.
jq '.no_gates = false' "$STATE_LEG" > "$STATE_LEG.tmp" && mv "$STATE_LEG.tmp" "$STATE_LEG"
o1="$(run_stage next "$SID_LEG")"; e1=$?   # Execution -> Documentation
o2="$(run_stage next "$SID_LEG")"; e2=$?   # Documentation -> Verification
printf 'PASS\n' > "$SDIR_LEG/verification_report.md"
o3="$(run_stage next "$SID_LEG")"; e3=$?   # Verification -> Deployment
o4="$(run_stage next "$SID_LEG")"; e4=$?   # Deployment -> Closeout
if [ "$e1" -eq 0 ] && [ "$e2" -eq 0 ] && [ "$e3" -eq 0 ] && [ "$e4" -eq 0 ] \
   && [ "$(cur_stage_leg)" = "Closeout" ] && [ "$(jq -r '.no_gates' "$STATE_LEG")" = "false" ]; then
  pass "legalized session (no_gates flipped by direct Edit) reaches Closeout via ordinary next calls"
else
  fail "Expected legalized session to reach Closeout" "e1=$e1 o1='$o1' e2=$e2 o2='$o2' e3=$e3 o3='$o3' e4=$e4 o4='$o4'"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "ALL PASSED"
  exit 0
else
  exit 1
fi
