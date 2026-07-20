#!/usr/bin/env bash
# Integration test: sdx-stage.sh (the sole `stage` writer) and stage-write-guard.sh (the
# deny half) exercised together, end-to-end, as the six /sdx:* commands would drive them.
# The unit suites (test-sdx-stage.sh, test-stage-write-guard.sh) already cover every
# subcommand/branch in isolation with purpose-built fixtures; this suite instead walks ONE
# continuous session through a realistic sequence — init -> next (x N, creating each gate
# artifact along the way) -> a rejected next (missing artifact) -> backtrack (+ outdated
# banner) -> retrack (track switch) -> next (x N on the new track) -> Closeout -> a direct
# Edit still denied on the state the walk produced — to catch integration-level regressions
# (e.g. a subcommand reading a field the previous subcommand left in an unexpected shape)
# that isolated unit fixtures cannot.
# Self-contained: creates its own temp git repo + session, cleans up via trap, no network/
# timing dependencies. Picked up automatically by verify-cmd.sh's test-*.sh glob.
# Usage: bash sdx/hooks/test-integration-stage-lifecycle.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_SCRIPT="$SCRIPT_DIR/sdx-stage.sh"
GUARD_HOOK="$SCRIPT_DIR/stage-write-guard.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

TMPPROJ=""
cleanup() { [ -n "$TMPPROJ" ] && rm -rf "$TMPPROJ"; TMPPROJ=""; }
trap cleanup EXIT

SID="it-lifecycle"
BRANCH="sdx/$SID"

# A real (temp) git repo, checked out on the sdx/<sid> branch, is required so that
# stage-write-guard.sh's resolve_sid() (branch -> sid) can find the session in step 13 —
# sdx-stage.sh itself never resolves a branch (sid is always an explicit argument, by
# design — DESIGN.md "Обработка ошибок").
TMPPROJ="$(mktemp -d)"
git -C "$TMPPROJ" init -q
git -C "$TMPPROJ" config user.email "test@test.com"
git -C "$TMPPROJ" config user.name "Test"
git -C "$TMPPROJ" commit -q --allow-empty -m "init"
git -C "$TMPPROJ" branch -M main 2>/dev/null || true
git -C "$TMPPROJ" checkout -q -b "$BRANCH"

SDIR="$TMPPROJ/.claude/sessions/$SID"
STATE="$SDIR/session_state.json"
LOG="$SDIR/session.log"

run_stage() { CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$STAGE_SCRIPT" "$@"; }
cur_stage() { jq -r '.stage' "$STATE"; }
cur_track() { jq -r '.track' "$STATE"; }

echo "=== test-integration-stage-lifecycle.sh ==="
echo ""

# ---- 1: init (full track) ----
echo "[1] init: full-track session starts at Discovery, seeds session.log"
out="$(run_stage init "$SID" "full" "full" "Discovery" "interactive" "$BRANCH")"
ec=$?
if [ "$ec" -eq 0 ] && [ -f "$STATE" ] && [ "$(cur_stage)" = "Discovery" ] && grep -q '\[START\]' "$LOG"; then
  pass "session_state.json + session.log created, stage=Discovery"
else
  fail "Expected initialized session at Discovery" "ec=$ec out='$out'"
fi

# ---- 2-4: next through Business Spec / Technical Design / Task Planning, creating each
# gate artifact right before the transition that requires it (mirrors how /sdx:next is
# actually invoked — the orchestrator finishes an artifact, THEN calls next). ----
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

# ---- 5: rejected next — PLAN.md deliberately not created yet ----
echo "[5] next: Task Planning -> rejected (PLAN.md missing), stage unchanged, message names artifact+command"
out="$(run_stage next "$SID" 2>&1 1>/dev/null)"; ec=$?
if [ "$ec" -eq 1 ] && [ "$(cur_stage)" = "Task Planning" ] \
   && printf '%s' "$out" | grep -q "PLAN.md" && printf '%s' "$out" | grep -q "/sdx:next"; then
  pass "rejected, stage unchanged, message names PLAN.md + /sdx:next"
else
  fail "Expected rejection naming PLAN.md" "ec=$ec out='$out'"
fi

echo "[6] next: Task Planning -> Execution (PLAN.md now present)"
printf '# PLAN\n' > "$SDIR/PLAN.md"
out="$(run_stage next "$SID")"; ec=$?
if [ "$ec" -eq 0 ] && [ "$(cur_stage)" = "Execution" ]; then
  pass "advanced to Execution"
else
  fail "Expected Execution" "ec=$ec out='$out'"
fi

# ---- 7: backtrack Execution -> Technical Design; PLAN.md (strictly after target) gets the
# outdated banner, DESIGN.md (the target stage's own artifact) does not (REQ-BACKTRACK-2). ----
echo "[7] backtrack: Execution -> Technical Design; marks PLAN.md outdated, leaves DESIGN.md untouched"
out="$(run_stage backtrack "$SID" "Technical Design")"; ec=$?
plan_first="$(head -1 "$SDIR/PLAN.md")"
design_first="$(head -1 "$SDIR/DESIGN.md")"
if [ "$ec" -eq 0 ] && [ "$(cur_stage)" = "Technical Design" ] \
   && printf '%s' "$plan_first" | grep -q '<!-- SDX-OUTDATED' \
   && [ "$design_first" = "# DESIGN" ] \
   && printf '%s' "$out" | grep -q "OUTDATED: .*PLAN.md"; then
  pass "backtrack succeeded, PLAN.md banner-marked, DESIGN.md (target's own artifact) untouched"
else
  fail "Expected backtrack + outdated marking" "ec=$ec out='$out' plan1='$plan_first' design1='$design_first'"
fi

# ---- 8: retrack full -> standard, target=Change. Per DESIGN.md "Развилка: кто вычисляет
# цель retrack", retrack.md computes the target prosaically and edits `track` DIRECTLY via
# Edit BEFORE calling the retrack subcommand — that direct field edit is legitimate
# (REQ-DENY-2, not `stage`) and is simulated here the same way (plain jq rewrite of the
# fixture), not via the guarded Write/Edit/MultiEdit tools. ----
echo "[8] retrack: track full -> standard, target=Change (mimics retrack.md's own direct 'track' edit, then the subcommand)"
jq '.track = "standard"' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
out="$(run_stage retrack "$SID" "Change")"; ec=$?
if [ "$ec" -eq 0 ] && [ "$(cur_track)" = "standard" ] && [ "$(cur_stage)" = "Change" ]; then
  pass "retracked to standard track, stage=Change, no forward-gate re-check"
else
  fail "Expected retrack to Change on standard track" "ec=$ec out='$out'"
fi

# ---- 9-11: next across the NEW (standard) track through to Closeout ----
echo "[9] next: Change -> Execution (change_note.md present)"
printf '# Change note\n' > "$SDIR/change_note.md"
out="$(run_stage next "$SID")"; ec=$?
if [ "$ec" -eq 0 ] && [ "$(cur_stage)" = "Execution" ]; then
  pass "advanced to Execution (standard track)"
else
  fail "Expected Execution on standard track" "ec=$ec out='$out'"
fi

echo "[10] next: Execution -> Verification (no objectively checkable gate artifact for Execution)"
out="$(run_stage next "$SID")"; ec=$?
if [ "$ec" -eq 0 ] && [ "$(cur_stage)" = "Verification" ]; then
  pass "advanced to Verification"
else
  fail "Expected Verification" "ec=$ec out='$out'"
fi

echo "[11] next: Verification -> Closeout (verification_report.md present, no FAIL marker)"
printf 'PASS\n' > "$SDIR/verification_report.md"
out="$(run_stage next "$SID")"; ec=$?
if [ "$ec" -eq 0 ] && [ "$(cur_stage)" = "Closeout" ] && [ "$out" = "OK Verification -> Closeout" ]; then
  pass "reached Closeout (this is the same code path /sdx:archive's entry gate calls, REQ-CLOSEOUT-ENTRY-1)"
else
  fail "Expected Closeout" "ec=$ec out='$out'"
fi

echo "[12] next: Closeout is terminal -> exit 0 no-op, file byte-for-byte unchanged"
before_sum="$(md5sum "$STATE" | cut -d' ' -f1)"
out="$(run_stage next "$SID")"; ec=$?
after_sum="$(md5sum "$STATE" | cut -d' ' -f1)"
if [ "$ec" -eq 0 ] && [ "$out" = "OK no-op Closeout" ] && [ "$before_sum" = "$after_sum" ]; then
  pass "terminal no-op at Closeout, file untouched"
else
  fail "Expected terminal no-op" "ec=$ec out='$out'"
fi

# ---- 13: stage-write-guard.sh still denies a direct Edit of `stage` on the state THIS
# walk produced — the hook-side half of REQ-DENY-1, exercised against a real, non-fixture
# session_state.json (not the hook suite's synthetic minimal `{"stage":"..."}` fixture).
# old_string/new_string use the actual `jq`-pretty-print spacing (space after `:`) that
# sdx-stage.sh's writer produces — post F-2 fix (verification_report.md), the guard
# applies Edit's old_string/new_string to the REAL on-disk bytes and compares the parsed
# `.stage` value, rather than regexing the fragment for a bare `"stage"` key mention; an
# old_string that doesn't literally occur in the file (as the previous no-space literal
# didn't) is now correctly treated as "the real Edit call would fail on its own, nothing
# to gate" (pass) instead of "deny" — see sdx/hooks/test-stage-write-guard.sh scenario 13
# for that pass-path covered directly. This scenario is about the deny path, so its
# literal must match the real file. ----
echo "[13] stage-write-guard: direct Edit of 'stage' on the walk's own session_state.json is still denied"
INPUT="$(jq -cn --arg fp "$STATE" '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"\"stage\": \"Closeout\"",new_string:"\"stage\": \"Discovery\""}}')"
out="$(printf '%s' "$INPUT" | CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$GUARD_HOOK")"
ec=$?
if [ "$ec" -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"deny"' && [ "$(cur_stage)" = "Closeout" ]; then
  pass "direct stage Edit denied, sdx-stage.sh remains the sole writer, stage unchanged"
else
  fail "Expected deny on direct Edit of stage" "ec=$ec out=$out"
fi


# ---- 14-19: a SECOND, independent session on the `vibe` track (proto session type,
# ADR-018) — the sole legalization route out of a track that has no `Closeout` row of its
# own (DESIGN.md "Решение 1"/"Решение 3"). Reuses the SAME temp repo/branch as steps 1-13
# (sdx-stage.sh never resolves branch -> sid on init/next/retrack, only the guard hook
# does, and the guard isn't exercised in this block) but a fresh sid, since SID's own
# session_state.json is already sitting at Closeout from step 12. ----
SID2="it-lifecycle-vibe"
SDIR2="$TMPPROJ/.claude/sessions/$SID2"
STATE2="$SDIR2/session_state.json"
cur_stage2() { jq -r '.stage' "$STATE2"; }
cur_track2() { jq -r '.track' "$STATE2"; }

# ---- 14: init on Prototype, the only active stage of vibe (REQ-VIBE-1/2) ----
echo "[14] init: vibe-track session (type=proto) starts at Prototype"
out="$(run_stage init "$SID2" "proto" "vibe" "Prototype" "interactive" "$BRANCH")"
ec=$?
if [ "$ec" -eq 0 ] && [ -f "$STATE2" ] && [ "$(cur_stage2)" = "Prototype" ] && [ "$(cur_track2)" = "vibe" ]; then
  pass "vibe session created, stage=Prototype, track=vibe"
else
  fail "Expected vibe session at Prototype" "ec=$ec out='$out'"
fi

# ---- 15: next on Prototype is a permanent no-op — Closeout is unreachable because the
# vibe row in SDX_STAGE_MATRIX has no successor (Решение 1: enforcement by data shape, not
# a code branch), not because of any special-cased check. Byte-for-byte untouched file,
# mirroring the genuine terminal no-op at Closeout in scenario [12]. ----
echo "[15] next: Prototype -> OK no-op Prototype, vibe never reaches Closeout on its own, file untouched"
before_sum2="$(md5sum "$STATE2" | cut -d' ' -f1)"
out="$(run_stage next "$SID2")"; ec=$?
after_sum2="$(md5sum "$STATE2" | cut -d' ' -f1)"
if [ "$ec" -eq 0 ] && [ "$out" = "OK no-op Prototype" ] && [ "$before_sum2" = "$after_sum2" ]; then
  pass "terminal no-op at Prototype, file untouched (vibe has no Closeout row)"
else
  fail "Expected terminal no-op at Prototype" "ec=$ec out='$out'"
fi

# ---- 16: legalization (Решение 3) — the ONLY way out of vibe is /sdx:retrack. The track
# switch is a direct field edit performed by retrack.md itself BEFORE calling the
# subcommand (mirrors scenario [8]'s full->standard edit). Reaching Execution on the new
# (standard) track requires proof that spec-after reverse-engineering actually happened:
# first attempted with track already switched but no change_note.md yet (rejected, code 1,
# message names the unmet Change gate — "пропустить легализацию нельзя"), then retried
# after creating it (accepted, code 0, stage=Execution). ----
echo "[16] retrack: vibe -> standard legalization rejected without change_note.md, accepted once it exists"
jq '.track = "standard"' "$STATE2" > "$STATE2.tmp" && mv "$STATE2.tmp" "$STATE2"
out1="$(run_stage retrack "$SID2" "Execution" 2>&1 1>/dev/null)"; ec1=$?
printf '# Change note (reverse-engineered from the accepted prototype)\n' > "$SDIR2/change_note.md"
out2="$(run_stage retrack "$SID2" "Execution")"; ec2=$?
if [ "$ec1" -eq 1 ] && printf '%s' "$out1" | grep -q "Change" \
   && [ "$ec2" -eq 0 ] && [ "$(cur_track2)" = "standard" ] && [ "$(cur_stage2)" = "Execution" ]; then
  pass "legalization rejected without spec-after proof, then accepted once change_note.md exists"
else
  fail "Expected reject-then-accept legalization sequence" "ec1=$ec1 out1='$out1' ec2=$ec2 out2='$out2'"
fi

# ---- 17: next across the legalized (standard) track, same as scenario [10] ----
echo "[17] next: Execution -> Verification (no objectively checkable gate artifact for Execution)"
out="$(run_stage next "$SID2")"; ec=$?
if [ "$ec" -eq 0 ] && [ "$(cur_stage2)" = "Verification" ]; then
  pass "advanced to Verification"
else
  fail "Expected Verification" "ec=$ec out='$out'"
fi

# ---- 18: same as scenario [11], on the legalized session ----
echo "[18] next: Verification -> Closeout (verification_report.md present, no FAIL marker)"
printf 'PASS\n' > "$SDIR2/verification_report.md"
out="$(run_stage next "$SID2")"; ec=$?
if [ "$ec" -eq 0 ] && [ "$(cur_stage2)" = "Closeout" ] && [ "$out" = "OK Verification -> Closeout" ]; then
  pass "legalized vibe session reaches Closeout via the standard track's own gate chain"
else
  fail "Expected Closeout" "ec=$ec out='$out'"
fi

# ---- 19: terminal no-op at Closeout — UNLIKE vibe itself (scenario [15]), a legalized
# session has a real Closeout row, so this is a genuine terminal, not an escape hatch. ----
echo "[19] next: Closeout is terminal -> OK no-op Closeout (legalized session has a normal terminal, unlike vibe)"
before_sum2="$(md5sum "$STATE2" | cut -d' ' -f1)"
out="$(run_stage next "$SID2")"; ec=$?
after_sum2="$(md5sum "$STATE2" | cut -d' ' -f1)"
if [ "$ec" -eq 0 ] && [ "$out" = "OK no-op Closeout" ] && [ "$before_sum2" = "$after_sum2" ]; then
  pass "terminal no-op at Closeout on the legalized (standard) track, file untouched"
else
  fail "Expected terminal no-op at Closeout" "ec=$ec out='$out'"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "ALL PASSED"
  exit 0
else
  exit 1
fi
