#!/usr/bin/env bash
# Unit tests for sdx-stage.sh (REQ-SCALE-1..9, REQ-FLAG-1..4, REQ-LEGAL-1, REQ-COMPAT-1..3,
# REQ-NAV-1..2). Runs self-contained: creates temporary "project" dirs, exercises the CLI,
# cleans up. Usage: bash sdx/hooks/test-sdx-stage.sh
#
# Scenario 29 (REQ-TEST-1) cross-checks the canonical stage_names() order against the
# human-readable stage-order projection table in sdx/protocol.md — see that scenario below.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# SDX_STAGE_UNDER_TEST: the script under test (set by the mutation runs of [M41]; a copy with lib/ beside it).
SCRIPT="${SDX_STAGE_UNDER_TEST:-$SCRIPT_DIR/sdx-stage.sh}"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# Global temp dir for each test; cleaned up by cleanup().
TMPPROJ=""

# setup_sdx_repo <sid> <stage> [no_code] [no_gates]
#   Creates a temp "project" dir (no real git repo needed — sdx-stage.sh takes sid
#   explicitly and never resolves a branch) with .claude/sessions/<sid>/session_state.json.
setup_sdx_repo() {
  local sid="$1" stage="$2" no_code="${3:-false}" no_gates="${4:-false}"
  TMPPROJ="$(mktemp -d)"
  mkdir -p "$TMPPROJ/.claude/sessions/$sid"
  jq -n --arg session_id "$sid" --arg type "feature" --arg stage "$stage" \
    --argjson no_code "$no_code" --argjson no_gates "$no_gates" \
    '{session_id:$session_id, type:$type, stage:$stage, gate_mode:"interactive", git_branch:("sdx/"+$session_id), no_code:$no_code, no_gates:$no_gates}' \
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
# Mutation re-runs of [M41] set SDX_STAGE_MUT and execute only the FEAT-016 block below.
if [ -z "${SDX_STAGE_MUT:-}" ]; then

# ---- Scenario 1: init creates state + [START] log line, exit 0 ----
echo "[1] init creates session_state.json + [START] log line"
TMPPROJ="$(mktemp -d)"
out="$(run_stage init "t1" "feature" "Discovery" "interactive" "sdx/t1" "false" "false")"
ec=$?
sf="$(state_file t1)"
lf="$(log_file t1)"
if [ "$ec" -eq 0 ] && [ -f "$sf" ] && [ -f "$lf" ] \
   && [ "$(jq -r '.stage' "$sf")" = "Discovery" ] \
   && [ "$(jq -r '.no_code' "$sf")" = "false" ] && [ "$(jq -r '.no_gates' "$sf")" = "false" ] \
   && grep -q '\[START\]' "$lf" \
   && printf '%s' "$out" | grep -q '^OK - ->'; then
  pass "state+log created, no_code/no_gates=false, exit 0, stdout OK - ->"
else
  fail "Expected state+log created" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 2: repeated init on existing file -> exit 2, file untouched ----
echo "[2] repeated init on existing file -> exit 2, file byte-for-byte unchanged"
TMPPROJ="$(mktemp -d)"
run_stage init "t2" "feature" "Discovery" "interactive" "sdx/t2" "false" "false" > /dev/null
sf="$(state_file t2)"
before_sum="$(md5sum "$sf" | cut -d' ' -f1)"
out="$(run_stage init "t2" "feature" "Discovery" "interactive" "sdx/t2" "false" "false" 2>&1 1>/dev/null)"
ec=$?
after_sum="$(md5sum "$sf" | cut -d' ' -f1)"
if [ "$ec" -eq 2 ] && [ "$before_sum" = "$after_sum" ]; then
  pass "exit 2, file unchanged"
else
  fail "Expected exit 2 + unchanged file" "ec=$ec before=$before_sum after=$after_sum stderr=$out"
fi
cleanup

# ---- Scenario 3: next — current stage is terminal Closeout -> exit 0 no-op ----
echo "[3] next: current stage Closeout (terminal) -> exit 0 no-op"
setup_sdx_repo "t3" "Closeout"
sf="$(state_file t3)"
before_sum="$(md5sum "$sf" | cut -d' ' -f1)"
out="$(run_stage next "t3")"
ec=$?
after_sum="$(md5sum "$sf" | cut -d' ' -f1)"
if [ "$ec" -eq 0 ] && [ "$out" = "OK no-op Closeout" ] && [ "$before_sum" = "$after_sum" ]; then
  pass "no-op on terminal Closeout, file untouched"
else
  fail "Expected no-op on Closeout" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 4: no jq in $PATH -> any mutating subcommand exits 2, file untouched ----
echo "[4] no jq in \$PATH -> exit 2, file untouched"
setup_sdx_repo "t4" "Discovery"
printf 'notes\n' > "$TMPPROJ/.claude/sessions/t4/context_report.md"
sf="$(state_file t4)"
before_sum="$(md5sum "$sf" | cut -d' ' -f1)"
NOJQDIR="$(mktemp -d)"
# Build a minimal PATH containing only the essentials (no jq) — link bash/coreutils dir.
for bin in bash sh mktemp cat mv rm grep sed awk head tail printf md5sum dirname; do
  p="$(command -v "$bin" 2>/dev/null || true)"
  [ -n "$p" ] && ln -sf "$p" "$NOJQDIR/$bin" 2>/dev/null
done
out="$(CLAUDE_PROJECT_DIR="$TMPPROJ" PATH="$NOJQDIR" bash "$SCRIPT" next "t4" 2>&1 1>/dev/null)"
ec=$?
after_sum="$(md5sum "$sf" | cut -d' ' -f1)"
rm -rf "$NOJQDIR"
if [ "$ec" -eq 2 ] && [ "$before_sum" = "$after_sum" ] && printf '%s' "$out" | grep -q "jq не найден"; then
  pass "exit 2, file untouched, 'jq не найден' message"
else
  fail "Expected fail-closed without jq" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 5: write_stage atomicity — no leftover temp files, original stays valid JSON ----
echo "[5] write_stage atomicity: broken jq (no jq) leaves no temp files, original stays valid+unchanged"
setup_sdx_repo "t5" "Discovery"
printf 'notes\n' > "$TMPPROJ/.claude/sessions/t5/context_report.md"
sf="$(state_file t5)"
sdir="$(dirname "$sf")"
NOJQDIR="$(mktemp -d)"
for bin in bash sh mktemp cat mv rm grep sed awk head tail printf md5sum dirname; do
  p="$(command -v "$bin" 2>/dev/null || true)"
  [ -n "$p" ] && ln -sf "$p" "$NOJQDIR/$bin" 2>/dev/null
done
CLAUDE_PROJECT_DIR="$TMPPROJ" PATH="$NOJQDIR" bash "$SCRIPT" next "t5" > /dev/null 2>&1
rm -rf "$NOJQDIR"
leftover="$(find "$sdir" -maxdepth 1 -name 'session_state.json.*' 2>/dev/null | wc -l | tr -d ' ')"
if jq -e . "$sf" > /dev/null 2>&1 && [ "$(jq -r '.stage' "$sf")" = "Discovery" ] && [ "$leftover" -eq 0 ]; then
  pass "original remains valid JSON with prior stage, no *.XXXXXX leftovers"
else
  fail "Expected valid untouched original + no temp leftovers" "leftover=$leftover stage=$(jq -r '.stage' "$sf" 2>/dev/null)"
fi
cleanup

# ---- Scenario 6: next — gate passed via the stage's OWN artifact -> stage advances ----
echo "[6] next: gate passed by own artifact (context_report.md) -> Discovery -> Business Spec"
setup_sdx_repo "t6" "Discovery"
printf 'notes\n' > "$TMPPROJ/.claude/sessions/t6/context_report.md"
out="$(run_stage next "t6")"
ec=$?
sf="$(state_file t6)"
lf="$(log_file t6)"
if [ "$ec" -eq 0 ] && [ "$(jq -r '.stage' "$sf")" = "Business Spec" ] \
   && [ "$out" = "OK Discovery -> Business Spec" ] && grep -q '\[STAGE_CHANGE\]' "$lf"; then
  pass "advanced by own artifact"
else
  fail "Expected advance by own artifact" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 7: next — gate passed via change_note.md fold-credit (REQ-SCALE-3, no own
# artifact at all) ----
echo "[7] next: gate passed by change_note.md fold-credit, no own artifact -> Business Spec -> Technical Design"
setup_sdx_repo "t7" "Business Spec"
printf '# note\n' > "$TMPPROJ/.claude/sessions/t7/change_note.md"
out="$(run_stage next "t7")"
ec=$?
sf="$(state_file t7)"
if [ "$ec" -eq 0 ] && [ "$(jq -r '.stage' "$sf")" = "Technical Design" ]; then
  pass "advanced by change_note.md fold-credit"
else
  fail "Expected fold-credit advance" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 8: next — gate NOT passed (no artifact, no change_note.md) -> exit 1 ----
echo "[8] next: gate not passed (neither own artifact nor change_note.md) -> exit 1, stage unchanged, alt hint mentions change_note.md"
setup_sdx_repo "t8" "Technical Design"
out="$(run_stage next "t8" 2>&1 1>/dev/null)"
ec=$?
sf="$(state_file t8)"
if [ "$ec" -eq 1 ] && [ "$(jq -r '.stage' "$sf")" = "Technical Design" ] \
   && printf '%s' "$out" | grep -q "DESIGN.md" && printf '%s' "$out" | grep -q "change_note.md"; then
  pass "rejected, names DESIGN.md and the change_note.md alternative"
else
  fail "Expected rejection naming DESIGN.md + change_note.md alt" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 9: next — verification_report.md has FAIL marker -> exit 1, fix_stage=Execution
# (no_code=false) ----
echo "[9] next: verification_report.md has FAIL marker, no_code=false -> exit 1, hint names Execution"
setup_sdx_repo "t9" "Verification" "false" "false"
printf '### [FAIL] found stuff\n' > "$TMPPROJ/.claude/sessions/t9/verification_report.md"
out="$(run_stage next "t9" 2>&1 1>/dev/null)"
ec=$?
sf="$(state_file t9)"
if [ "$ec" -eq 1 ] && [ "$(jq -r '.stage' "$sf")" = "Verification" ] \
   && printf '%s' "$out" | grep -q 'FAIL' && printf '%s' "$out" | grep -q 'Execution'; then
  pass "rejected, FAIL noted, fix_stage=Execution"
else
  fail "Expected FAIL rejection naming Execution" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 10: same as [9], but no_code=true -> fix_stage=Technical Design (remediation
# branch differs by no_code, per DESIGN.md diagnostic split) ----
echo "[10] next: verification_report.md has FAIL marker, no_code=true -> exit 1, hint names Technical Design"
setup_sdx_repo "t10" "Verification" "true" "false"
printf '### [FAIL] found stuff\n' > "$TMPPROJ/.claude/sessions/t10/verification_report.md"
out="$(run_stage next "t10" 2>&1 1>/dev/null)"
ec=$?
if [ "$ec" -eq 1 ] && printf '%s' "$out" | grep -q 'Technical Design'; then
  pass "rejected, fix_stage=Technical Design under no_code"
else
  fail "Expected FAIL rejection naming Technical Design" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 11: init — REQ-FLAG-3, both flags true -> exit 2 ----
# The fixture below uses stage="Execution" ON PURPOSE: it is the one stage value for which
# the LATER REQ-SCALE-4 check ("no_code=true excludes starting on stage 'Execution'") would
# ALSO independently produce exit 2 if the REQ-FLAG-3 check itself were broken/removed — so
# checking only the exit code here is tautological and would not actually discriminate
# whether REQ-FLAG-3 fired. The assertion therefore also pins down the MESSAGE: it must be
# specifically about the no_code/no_gates contradiction (REQ-FLAG-3's own wording), and must
# NOT be REQ-SCALE-4's ("исключает старт") or REQ-SCALE-5's ("допускает старт") wording,
# which are the two other checks that could otherwise mask REQ-FLAG-3 going unreachable.
echo "[11] init: no_code=true AND no_gates=true -> exit 2, message names the flag conflict (REQ-FLAG-3), not a stage-exclusion check"
TMPPROJ="$(mktemp -d)"
out="$(run_stage init "t11" "proto" "Execution" "interactive" "sdx/t11" "true" "true" 2>&1 1>/dev/null)"
ec=$?
sf="$(state_file t11)"
if [ "$ec" -eq 2 ] && [ ! -f "$sf" ]    && printf '%s' "$out" | grep -q 'no_code и no_gates'    && ! printf '%s' "$out" | grep -q 'исключает старт'    && ! printf '%s' "$out" | grep -q 'допускает старт'; then
  pass "exit 2, no state file created, message names the no_code/no_gates conflict specifically"
else
  fail "Expected exit 2, no file, message about the flag conflict (REQ-FLAG-3), not a stage check" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 12: init — REQ-SCALE-5, no_gates=true on a stage other than Execution -> exit 2 ----
echo "[12] init: no_gates=true, stage != Execution -> exit 2"
TMPPROJ="$(mktemp -d)"
out="$(run_stage init "t12" "proto" "Discovery" "interactive" "sdx/t12" "false" "true" 2>&1 1>/dev/null)"
ec=$?
if [ "$ec" -eq 2 ] && printf '%s' "$out" | grep -q 'Execution'; then
  pass "exit 2, names Execution as the only allowed start"
else
  fail "Expected exit 2 naming Execution" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 13: init — REQ-SCALE-4, no_code=true on an excluded stage -> exit 2 ----
echo "[13] init: no_code=true, stage=Execution (excluded) -> exit 2"
TMPPROJ="$(mktemp -d)"
out="$(run_stage init "t13" "grooming" "Execution" "interactive" "sdx/t13" "true" "false" 2>&1 1>/dev/null)"
ec=$?
if [ "$ec" -eq 2 ]; then
  pass "exit 2, no_code excludes Execution"
else
  fail "Expected exit 2" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 14: init — start on an arbitrary canonical stage without flags succeeds
# (no more "first active stage of a track" concept) ----
echo "[14] init: start directly on Business Spec (skipping Discovery), no flags -> success"
TMPPROJ="$(mktemp -d)"
out="$(run_stage init "t14" "feature" "Business Spec" "interactive" "sdx/t14" "false" "false")"
ec=$?
sf="$(state_file t14)"
if [ "$ec" -eq 0 ] && [ -f "$sf" ] && [ "$(jq -r '.stage' "$sf")" = "Business Spec" ]; then
  pass "arbitrary canonical starting stage accepted"
else
  fail "Expected success starting on Business Spec" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 15: init — unrecognized stage name -> exit 2 ----
echo "[15] init: unrecognized stage name -> exit 2"
TMPPROJ="$(mktemp -d)"
out="$(run_stage init "t15" "feature" "Nonexistent" "interactive" "sdx/t15" "false" "false" 2>&1 1>/dev/null)"
ec=$?
sf="$(state_file t15)"
if [ "$ec" -eq 2 ] && [ ! -f "$sf" ]; then
  pass "exit 2, no state file created"
else
  fail "Expected exit 2, no file" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 16: next (no_code) — auto-skip Task Planning/Execution/Documentation in one
# call, landing directly on Verification (REQ-SCALE-4) ----
echo "[16] next: no_code=true, Technical Design -> Verification in one call (auto-skip 3 stages)"
setup_sdx_repo "t16" "Technical Design" "true" "false"
printf '# design\n' > "$TMPPROJ/.claude/sessions/t16/DESIGN.md"
out="$(run_stage next "t16")"
ec=$?
sf="$(state_file t16)"
if [ "$ec" -eq 0 ] && [ "$(jq -r '.stage' "$sf")" = "Verification" ] \
   && [ "$out" = "OK Technical Design -> Verification" ]; then
  pass "single call skips Task Planning/Execution/Documentation under no_code"
else
  fail "Expected auto-skip straight to Verification" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 17: next (no_gates) — OK no-op Execution, reproduced across 3 consecutive
# calls, file byte-for-byte untouched every time (REQ-LEGAL-1, explicit acceptance
# criterion) ----
echo "[17] next: no_gates=true -> OK no-op Execution across 3 consecutive calls, file never touched"
setup_sdx_repo "t17" "Execution" "false" "true"
sf="$(state_file t17)"
sum0="$(md5sum "$sf" | cut -d' ' -f1)"
o1="$(run_stage next "t17")"; e1=$?
o2="$(run_stage next "t17")"; e2=$?
o3="$(run_stage next "t17")"; e3=$?
sum3="$(md5sum "$sf" | cut -d' ' -f1)"
if [ "$e1" -eq 0 ] && [ "$e2" -eq 0 ] && [ "$e3" -eq 0 ] \
   && [ "$o1" = "OK no-op Execution" ] && [ "$o2" = "OK no-op Execution" ] && [ "$o3" = "OK no-op Execution" ] \
   && [ "$sum0" = "$sum3" ]; then
  pass "three consecutive calls all no-op, file byte-for-byte unchanged"
else
  fail "Expected stable no-op across repeated calls" "e1=$e1 o1='$o1' e2=$e2 o2='$o2' e3=$e3 o3='$o3'"
fi
cleanup

# ---- Scenario 18: next --to — genuine backtrack + outdated marking, no upper bound
# (REQ-BACKTRACK-2/W-1 precedent preserved) ----
echo "[18] next --to: genuine backtrack marks all later artifacts outdated, target's own artifact untouched"
setup_sdx_repo "t18" "Task Planning"
printf '# spec\n' > "$TMPPROJ/.claude/sessions/t18/SPEC.md"
printf '# design\n' > "$TMPPROJ/.claude/sessions/t18/DESIGN.md"
out="$(run_stage next "t18" --to "Business Spec")"
ec=$?
sf="$(state_file t18)"
spec_first="$(head -1 "$TMPPROJ/.claude/sessions/t18/SPEC.md")"
design_first="$(head -1 "$TMPPROJ/.claude/sessions/t18/DESIGN.md")"
if [ "$ec" -eq 0 ] && [ "$(jq -r '.stage' "$sf")" = "Business Spec" ] \
   && [ "$spec_first" = "# spec" ] \
   && printf '%s' "$design_first" | grep -q '<!-- SDX-OUTDATED' \
   && printf '%s' "$out" | grep -q "OUTDATED: .*DESIGN.md"; then
  pass "backtrack succeeded, target's own SPEC.md untouched, DESIGN.md (later) marked outdated"
else
  fail "Expected backtrack + outdated marking" "ec=$ec out='$out' spec1='$spec_first' design1='$design_first'"
fi
cleanup

# ---- Scenario 19: next --to — idempotent re-marking, including two different foldable
# stages pointing at the SAME change_note.md, does not duplicate the banner. Both halves
# below are LIVE: count1 exercises intra-call dedup (Business Spec + Technical Design +
# Task Planning are all foldable stages hit by ONE --to call), count2 exercises cross-call
# dedup by genuinely returning to that file via a SECOND, separate --to call reached through
# real forward movement (plain `next`, which --to itself cannot do — --to only ever moves
# backward, so a prior version of this scenario tried to "move forward again" with --to
# itself, which is rejected and silently no-ops, leaving the second half dead/tautological).
echo "[19] next --to: repeated marking of the same change_note.md, both within one --to call and across two separate --to calls, never duplicates the banner"
setup_sdx_repo "t19" "Task Planning"
printf '# note\n' > "$TMPPROJ/.claude/sessions/t19/change_note.md"
# First --to call: Task Planning -> Discovery marks Business Spec/Technical Design/Task
# Planning (three foldable stages, same file) in one pass.
run_stage next "t19" --to "Discovery" > /dev/null
count1="$(grep -c '<!-- SDX-OUTDATED' "$TMPPROJ/.claude/sessions/t19/change_note.md")"
# Genuinely move forward again via plain `next` (fold-credit still satisfies the gate, since
# change_note.md is non-empty) all the way back to Execution, then issue a SECOND, separate
# --to call targeting a DIFFERENT foldable stage (Business Spec) — this re-triggers marking
# via Technical Design + Task Planning a second time, on the SAME file, from a fresh script
# invocation (not merely a second row in the same loop as count1).
run_stage next "t19" > /dev/null   # Discovery -> Business Spec
run_stage next "t19" > /dev/null   # Business Spec -> Technical Design
run_stage next "t19" > /dev/null   # Technical Design -> Task Planning
run_stage next "t19" > /dev/null   # Task Planning -> Execution
run_stage next "t19" --to "Business Spec" > /dev/null
count2="$(grep -c '<!-- SDX-OUTDATED' "$TMPPROJ/.claude/sessions/t19/change_note.md")"
if [ "$count1" -eq 1 ] && [ "$count2" -eq 1 ] && [ "$(jq -r '.stage' "$(state_file t19)")" = "Business Spec" ]; then
  pass "banner never duplicated, neither within one --to call nor across two separate --to calls"
else
  fail "Expected exactly one banner occurrence in both halves" "count1=$count1 count2=$count2"
fi
cleanup

# ---- Scenario 20: next --to — target == current stage -> no-op, file untouched ----
echo "[20] next --to: target == current stage -> exit 0 no-op, file untouched"
setup_sdx_repo "t20" "Technical Design"
sf="$(state_file t20)"
before_sum="$(md5sum "$sf" | cut -d' ' -f1)"
out="$(run_stage next "t20" --to "Technical Design")"
ec=$?
after_sum="$(md5sum "$sf" | cut -d' ' -f1)"
if [ "$ec" -eq 0 ] && [ "$out" = "OK no-op Technical Design" ] && [ "$before_sum" = "$after_sum" ]; then
  pass "no-op when target equals current stage"
else
  fail "Expected no-op" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 21: next --to — target later than current -> exit 1, points at /sdx:next
# without arguments (REQ-NAV-1: --to cannot be used to move forward) ----
echo "[21] next --to: target later than current -> exit 1, message points at /sdx:next"
setup_sdx_repo "t21" "Discovery"
out="$(run_stage next "t21" --to "Execution" 2>&1 1>/dev/null)"
ec=$?
sf="$(state_file t21)"
if [ "$ec" -eq 1 ] && [ "$(jq -r '.stage' "$sf")" = "Discovery" ] \
   && printf '%s' "$out" | grep -q '/sdx:next'; then
  pass "rejected forward --to target, points at /sdx:next"
else
  fail "Expected rejection of forward --to target" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 22: next --to — unrecognized target name -> exit 1 ----
echo "[22] next --to: unrecognized target name -> exit 1, stage unchanged"
setup_sdx_repo "t22" "Discovery"
out="$(run_stage next "t22" --to "Nonexistent" 2>&1 1>/dev/null)"
ec=$?
sf="$(state_file t22)"
if [ "$ec" -eq 1 ] && [ "$(jq -r '.stage' "$sf")" = "Discovery" ]; then
  pass "unrecognized --to target rejected, stage unchanged"
else
  fail "Expected rejection of unrecognized target" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 23: next --to — on a no_gates session, target != Execution -> exit 1
# (REQ-LEGAL-1 priority over REQ-NAV-1) ----
echo "[23] next --to: no_gates=true, target != Execution -> exit 1 (REQ-LEGAL-1 priority)"
setup_sdx_repo "t23" "Execution" "false" "true"
out="$(run_stage next "t23" --to "Discovery" 2>&1 1>/dev/null)"
ec=$?
sf="$(state_file t23)"
if [ "$ec" -eq 1 ] && [ "$(jq -r '.stage' "$sf")" = "Execution" ] \
   && printf '%s' "$out" | grep -q 'no_gates'; then
  pass "--to blocked while no_gates==true, only Execution stays reachable"
else
  fail "Expected --to rejection under no_gates" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 24: REQ-COMPAT-1 — legacy 'track' field present, no no_code/no_gates ->
# next treats them as false/false, does not fail on the unexpected key ----
echo "[24] REQ-COMPAT-1: legacy 'track' field in JSON, no no_code/no_gates keys -> next works as no_code=false,no_gates=false"
TMPPROJ="$(mktemp -d)"
mkdir -p "$TMPPROJ/.claude/sessions/t24"
jq -n '{session_id:"t24", type:"feature", track:"full", stage:"Discovery", gate_mode:"interactive", git_branch:"sdx/t24"}' \
  > "$TMPPROJ/.claude/sessions/t24/session_state.json"
printf 'notes\n' > "$TMPPROJ/.claude/sessions/t24/context_report.md"
out="$(run_stage next "t24")"
ec=$?
sf="$(state_file t24)"
if [ "$ec" -eq 0 ] && [ "$(jq -r '.stage' "$sf")" = "Business Spec" ] && [ "$(jq -r '.track' "$sf")" = "full" ]; then
  pass "legacy 'track' key tolerated, transition succeeds as flags-false, track key left untouched"
else
  fail "Expected legacy track compat" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 25: REQ-COMPAT-3 diagnostics — stage is a legacy name ('Change') -> next
# exits 2 with an understandable message, does not crash/corrupt ----
echo "[25] REQ-COMPAT-3: stage='Change' (legacy name) -> next exits 2 with diagnostic, not a crash"
TMPPROJ="$(mktemp -d)"
mkdir -p "$TMPPROJ/.claude/sessions/t25"
jq -n '{session_id:"t25", type:"feature", track:"standard", stage:"Change", gate_mode:"interactive", git_branch:"sdx/t25"}' \
  > "$TMPPROJ/.claude/sessions/t25/session_state.json"
sf="$(state_file t25)"
before_sum="$(md5sum "$sf" | cut -d' ' -f1)"
out="$(run_stage next "t25" 2>&1 1>/dev/null)"
ec=$?
after_sum="$(md5sum "$sf" | cut -d' ' -f1)"
if [ "$ec" -eq 2 ] && [ "$before_sum" = "$after_sum" ] && printf '%s' "$out" | grep -qi 'нераспознан\|устарел'; then
  pass "legacy stage name diagnosed with exit 2, file untouched"
else
  fail "Expected diagnostic exit 2 on legacy stage name" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 26: REQ-COMPAT-3 diagnostics via next --to too — legacy stage name as the
# CURRENT stage prevents an automatic --to resolution as well ----
echo "[26] REQ-COMPAT-3: stage='Update' (legacy name), next --to Discovery -> exit 2, not silently accepted"
TMPPROJ="$(mktemp -d)"
mkdir -p "$TMPPROJ/.claude/sessions/t26"
jq -n '{session_id:"t26", type:"grooming", track:"doc", stage:"Update", gate_mode:"interactive", git_branch:"sdx/t26"}' \
  > "$TMPPROJ/.claude/sessions/t26/session_state.json"
out="$(run_stage next "t26" --to "Discovery" 2>&1 1>/dev/null)"
ec=$?
if [ "$ec" -eq 2 ]; then
  pass "legacy current-stage name blocks --to resolution too, exit 2"
else
  fail "Expected exit 2 on legacy current stage under --to" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 27 (REQ-COMPAT-3, forward mode): current stage is an empty string "" ----
# Regression test for a real bug found by QA at Verification: stage_exists() used an
# unconditional `$1==s` awk pattern, which matched SDX_STAGE_TABLE's empty leading heredoc
# record when s=="" — `next` (forward, no --to) would then silently treat index 0+1=1 as a
# valid candidate and advance to Discovery instead of diagnosing REQ-COMPAT-3. next --to
# already handled this correctly (scenario 26 covers a legacy-name variant of that path); this
# scenario locks down that plain `next` is symmetric with it for a *corrupted* (not merely
# legacy-named) current stage.
echo "[27] REQ-COMPAT-3: stage='' (empty string), forward next -> exit 2, file untouched, not silently healed to Discovery"
TMPPROJ="$(mktemp -d)"
mkdir -p "$TMPPROJ/.claude/sessions/t27"
jq -n '{session_id:"t27", type:"feature", stage:"", gate_mode:"interactive", git_branch:"sdx/t27", no_code:false, no_gates:false}'   > "$TMPPROJ/.claude/sessions/t27/session_state.json"
sf="$(state_file t27)"
before_sum="$(md5sum "$sf" | cut -d' ' -f1)"
out="$(run_stage next "t27" 2>&1 1>/dev/null)"
ec=$?
after_sum="$(md5sum "$sf" | cut -d' ' -f1)"
if [ "$ec" -eq 2 ] && [ "$before_sum" = "$after_sum" ] && printf '%s' "$out" | grep -qi 'нераспознан\|устарел'; then
  pass "empty stage diagnosed with exit 2, file untouched, not healed to Discovery"
else
  fail "Expected diagnostic exit 2 on empty stage, not a silent heal" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 28 (REQ-COMPAT-3, forward mode): .stage key is entirely absent from the JSON ----
# Same bug, second manifestation: `jq -r '.stage // empty'` on a missing key also yields the
# empty string, going through the identical broken stage_exists("") path.
echo "[28] REQ-COMPAT-3: .stage key absent from session_state.json, forward next -> exit 2, file untouched"
TMPPROJ="$(mktemp -d)"
mkdir -p "$TMPPROJ/.claude/sessions/t28"
jq -n '{session_id:"t28", type:"feature", gate_mode:"interactive", git_branch:"sdx/t28", no_code:false, no_gates:false}'   > "$TMPPROJ/.claude/sessions/t28/session_state.json"
sf="$(state_file t28)"
before_sum="$(md5sum "$sf" | cut -d' ' -f1)"
out="$(run_stage next "t28" 2>&1 1>/dev/null)"
ec=$?
after_sum="$(md5sum "$sf" | cut -d' ' -f1)"
if [ "$ec" -eq 2 ] && [ "$before_sum" = "$after_sum" ] && printf '%s' "$out" | grep -qi 'нераспознан\|устарел'; then
  pass "missing .stage key diagnosed with exit 2, file untouched, not healed to Discovery"
else
  fail "Expected diagnostic exit 2 on missing .stage key, not a silent heal" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 29 (REQ-TEST-1): sanity — canonical stage_names() order AND, per stage, the
# gate-artifact/FAIL-marker/fold-credit columns match the human-readable projection table in
# sdx/protocol.md ("Единая шкала этапов и режимы-флаги"). The single machine-readable source
# of truth is SDX_STAGE_TABLE inside this script; sdx/protocol.md's table is a projection of
# ALL FOUR columns (#/Этап/Гейт-артефакт/FAIL-маркер/Fold-credit) for humans — a prior version
# of this scenario compared ONLY the ordered stage-name column, so protocol.md and the script
# could silently disagree on e.g. which file gates a stage, or whether a stage carries a
# FAIL-marker/fold-credit, without this sanity check ever noticing. This scenario fails on ANY
# divergence in any of the four columns, for any stage.
#
# Normalization needed because the two tables render the same values differently for humans
# vs. the script's compact pipe format:
#   artifact    — protocol.md wraps filenames in backticks (stripped) and spells "no gate" as
#                 an em-dash + parenthetical ("— (нет объективного гейта)"), normalized to "-"
#                 to match the script's own placeholder.
#   fail_marker — protocol.md spells it "да (`^### \[FAIL\]`)" / "нет" / em-dash for stages
#                 with no gate at all; normalized to yes/no/no respectively.
#   foldable    — protocol.md spells it "да" / "нет" / em-dash for stages with no gate at all;
#                 normalized to yes/no/no respectively.
echo "[29] REQ-TEST-1 sanity: stage_names() order AND artifact/FAIL-marker/fold-credit columns match sdx/protocol.md's stage table"
PROTOCOL_MD="$SCRIPT_DIR/../protocol.md"
if [ ! -f "$PROTOCOL_MD" ]; then
  fail "sdx/protocol.md not found for REQ-TEST-1 cross-check" "expected at $PROTOCOL_MD"
else
  # stage_names() is not exposed as a subcommand — extract the same ordered table directly
  # from SDX_STAGE_TABLE, exactly as the script's own helpers read it, to avoid depending on
  # an extra CLI surface just for this test. Already in "stage|artifact|fail_marker|foldable"
  # form, one row per line, no normalization needed on this side.
  script_rows="$(sed -n "/^SDX_STAGE_TABLE='/,/^'/p" "$SCRIPT" | sed '1d;$d')"
  # protocol.md side: same four columns, normalized to the script's vocabulary (see comment
  # block above). LC_ALL=C.UTF-8 (or the environment's own UTF-8 locale) is relied upon for
  # the em-dash ("—", U+2014) comparisons below to work byte-for-byte consistently.
  protocol_rows="$(awk -F'|' '
    /^\| [0-9]+ \| /{
      name=$3; artifact=$4; failm=$5; fold=$6
      gsub(/^ +| +$/, "", name)
      gsub(/^ +| +$/, "", artifact)
      gsub(/^ +| +$/, "", failm)
      gsub(/^ +| +$/, "", fold)
      gsub(/`/, "", artifact)
      if (artifact ~ /^—/) artifact = "-"
      fm = (failm ~ /^да/) ? "yes" : "no"
      fc = (fold == "да") ? "yes" : "no"
      print name "|" artifact "|" fm "|" fc
    }
  ' "$PROTOCOL_MD")"
  if [ "$script_rows" = "$protocol_rows" ]; then
    pass "canonical stage order + artifact/FAIL-marker/fold-credit columns match sdx/protocol.md's projection table"
  else
    fail "stage table mismatch between sdx-stage.sh (SDX_STAGE_TABLE) and sdx/protocol.md" \
      "script: [$script_rows] protocol: [$protocol_rows]"
  fi
fi

# ---- Scenario 30b (REQ-NAV-2, upper-bound discrimination): an artifact belonging to a
# stage LATER than the DEPARTING (current) stage — a legitimate leftover from an earlier
# full cycle through the canonical order, e.g. a previous Technical Design pass whose
# DESIGN.md survives while the session is currently sitting back on Business Spec — must
# still be marked outdated on backtrack. REQ-NAV-2 bounds marking by the END of the
# canonical order, NOT by the departing stage's own index; a regression that narrowed the
# loop to "stages between target and the departing stage" would leave this DESIGN.md
# untouched while still passing scenario 18 (there, every existing artifact sits AT OR
# BEFORE the departing stage, so that scenario cannot tell the two bounds apart).
echo "[30b] next --to: artifact belonging to a stage LATER than the departing (current) stage is marked outdated too"
setup_sdx_repo "t30b" "Business Spec"
printf '# spec\n' > "$TMPPROJ/.claude/sessions/t30b/SPEC.md"
# DESIGN.md is Technical Design's artifact (canonical index 3) — LATER than the departing
# stage Business Spec (canonical index 2). Its presence here models a leftover from an
# earlier cycle; the session has since been backtracked to Business Spec by other means
# without touching DESIGN.md, which is exactly the "artifact exists past current stage"
# case the reviewer's finding requires a test for.
printf '# design\n' > "$TMPPROJ/.claude/sessions/t30b/DESIGN.md"
out="$(run_stage next "t30b" --to "Discovery")"
ec=$?
design_first="$(head -1 "$TMPPROJ/.claude/sessions/t30b/DESIGN.md")"
if [ "$ec" -eq 0 ] \
   && printf '%s' "$design_first" | grep -q '<!-- SDX-OUTDATED' \
   && printf '%s' "$out" | grep -q "OUTDATED: .*DESIGN.md"; then
  pass "artifact of a stage later than the departing stage (DESIGN.md, idx 3 > departing idx 2) marked outdated"
else
  fail "Expected marking to extend past the departing stage's own index" "ec=$ec out='$out' design1='$design_first'"
fi
cleanup

# ---- Scenario 30 (REQ-SCALE-4, backtrack direction): next --to targeting an EXCLUDED
# stage while no_code==true must be refused even though the move is a genuine backtrack
# (idx_target < idx_current) — the exclusion is a property of the TARGET stage, not of
# direction. Regression test for a reviewer finding: the exclusion check existed only in
# cmd_init and was missing from the --to branch of cmd_next, so `next --to "Execution"` on
# a no_code session passed silently. Verification stage -> --to "Execution" is a legitimate
# backward move by index alone (7 -> 5), so this specifically discriminates the new check
# from the pre-existing "forward move rejected" check (scenario 21), which never fires here.
echo "[30] next --to: no_code=true, target is an excluded stage reached via genuine backtrack -> exit 1, message names REQ-SCALE-4"
setup_sdx_repo "t30" "Verification" "true" "false"
sf="$(state_file t30)"
before_sum="$(md5sum "$sf" | cut -d' ' -f1)"
out="$(run_stage next "t30" --to "Execution" 2>&1 1>/dev/null)"
ec=$?
after_sum="$(md5sum "$sf" | cut -d' ' -f1)"
if [ "$ec" -eq 1 ] && [ "$before_sum" = "$after_sum" ] \
   && [ "$(jq -r '.stage' "$sf")" = "Verification" ] \
   && printf '%s' "$out" | grep -q 'REQ-SCALE-4'; then
  pass "excluded --to target refused under no_code even on a genuine backtrack, message names REQ-SCALE-4"
else
  fail "Expected --to rejection of excluded target under no_code" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 31 (T02, REQ-STATE-1/2, DEBT-038): cmd_init no longer writes artifacts/history ----
echo "[31] cmd_init no longer writes artifacts/history (DEBT-038, REQ-STATE-1/2)"
TMPPROJ="$(mktemp -d)"
run_stage init "t31" "feature" "Discovery" "interactive" "sdx/t31" "false" "false" > /dev/null
sf="$(state_file t31)"
has_artifacts="$(jq 'has("artifacts")' "$sf")"
has_history="$(jq 'has("history")' "$sf")"
if [ "$has_artifacts" = "false" ] && [ "$has_history" = "false" ]; then
  pass "green: fresh session_state.json has no artifacts/history keys"
else
  fail "31 green" "has_artifacts=$has_artifacts has_history=$has_history"
fi
cleanup

# Red side (DoD demands a real mutation, not an honest limit — the mutation is cheap: restore
# the two dead keys into the SAME jq filter literal cmd_init uses, in a mktemp copy of the
# script, and run cmd_init from the mutant against a fresh fixture — style of test-selftest.sh
# [T28] (mutant-copy-and-run, not "checked by hand once").
mutant="$(mktemp)"
sed "s/no_code:\$no_code, no_gates:\$no_gates}/no_code:\$no_code, no_gates:\$no_gates, artifacts:[], history:[]}/" \
  "$SCRIPT" > "$mutant"
TMPPROJ="$(mktemp -d)"
CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$mutant" init "t31r" "feature" "Discovery" "interactive" "sdx/t31r" "false" "false" > /dev/null
sf_r="$(state_file t31r)"
has_artifacts_r="$(jq 'has("artifacts")' "$sf_r" 2>/dev/null)"
has_history_r="$(jq 'has("history")' "$sf_r" 2>/dev/null)"
if [ "$has_artifacts_r" = "true" ] && [ "$has_history_r" = "true" ]; then
  pass "red: mutant with artifacts/history re-inserted into the jq filter produces has(...)==true — scenario discriminates"
else
  fail "31 red" "expected mutant to reproduce DEBT-038 (has_artifacts=true, has_history=true), got has_artifacts=$has_artifacts_r has_history=$has_history_r"
fi
rm -f "$mutant"
cleanup

# ---- Scenario 32 (T03, REQ-STATE-2, DEBT-038): legacy session_state.json with
# artifacts/history survives cmd_next untouched -- honest limit on the red side, no discriminating
# mutation exists for this scenario (recorded explicitly per [T08]/[T27] test-selftest.sh style,
# not a silent skip) ----
echo "[32] legacy session_state.json with artifacts/history survives cmd_next untouched (REQ-STATE-2)"
setup_sdx_repo "t32" "Discovery"
sf="$(state_file t32)"
# The legacy artifacts/history fields are injected HERE, deliberately, rather than inherited from
# setup_sdx_repo: after the Group 8 (T26) hygiene pass the shared fixture constructor writes the
# current 7-key schema, so a scenario about PRE-EXISTING legacy state must construct that state
# explicitly. This also keeps the scenario honest -- what it models (a session_state.json written
# by an older sdx-stage.sh) is visible at the point of use instead of being a side effect of a
# helper shared with 30 other scenarios.
jq '. + {artifacts: [], history: []}' "$sf" > "$sf.tmp" && mv "$sf.tmp" "$sf"
printf '# ctx\n' > "$TMPPROJ/.claude/sessions/t32/context_report.md"
out="$(run_stage next "t32")"
ec=$?
if [ "$ec" -eq 0 ] \
   && [ "$(jq -r '.stage' "$sf")" = "Business Spec" ] \
   && [ "$(jq -e '.artifacts == [] and .history == []' "$sf")" = "true" ]; then
  pass "legacy artifacts/history fields survive cmd_next unread and untouched, stage transitioned correctly"
else
  fail "32" "ec=$ec stage=$(jq -r '.stage' "$sf" 2>/dev/null) artifacts=$(jq -c '.artifacts' "$sf" 2>/dev/null) history=$(jq -c '.history' "$sf" 2>/dev/null)"
fi
cleanup
# Honest limit (same spirit as [T08]/[T27] test-selftest.sh, recorded explicitly rather than
# silently skipped): no discriminating mutation exists for this scenario's "not read" half.
# No line in sdx-stage.sh today reads .artifacts or .history -- the ONLY mutation that could turn
# this scenario red would be to ADD code that reads them, i.e. to reintroduce the exact defect
# DEBT-038 removed. That would be a tautological test ("we didn't add what we deliberately don't
# add"), not a meaningful red side, so it is not constructed. What IS meaningfully red-tested is
# the survival half (scenario 31's mutant demonstrates the write side is real and reversible);
# this scenario's own contribution -- confirming cmd_next does not choke on or strip legacy
# fields -- is asserted green only, by design, matching DESIGN.md's DoD table row B verbatim.

fi   # end of the pre-FEAT-016 scenarios (skipped in mutation re-runs)

# ======================================================================================
# FEAT-016: mandate mode (REQ-MAND-8..11). Scenarios [M30]-[M40] (plan numbers 30-40; the legacy suite already has [30]-[32]); mutation section [M41].
# Mandate mode = BOTH .mesh/endpoint.yaml and .mesh/mandate.yaml in the project; otherwise nothing below applies.
# ======================================================================================

# Mutation re-runs stop at the first red check (that is all [M41] needs; keeps the suite fast).
if [ -n "${SDX_STAGE_MUT:-}" ]; then
  trap cleanup EXIT
  fail() { echo "  FAIL: $1 — $2"; exit 1; }
fi

# mwant <N>: scenario M<N> runs unless SDX_STAGE_ONLY (a space-separated list of numbers) excludes it.
mwant() { [ -z "${SDX_STAGE_ONLY:-}" ] && return 0; case " $SDX_STAGE_ONLY " in *" $1 "*) return 0 ;; esac; return 1; }

# setup_mandate <block|flow|absent> [stage...]: writes .mesh/endpoint.yaml + .mesh/mandate.yaml into $TMPPROJ.
#   block  -> the node dump shape (indentless list; no stages -> an empty "stages:" key)
#   flow   -> "stages: [a, b]" ("[]" without stages)
#   absent -> no stages key at all
# MAND_DELIVERY (default artifact.offer) sets mandate.delivery.
setup_mandate() {
  local form="$1" y s; shift
  mkdir -p "$TMPPROJ/.mesh"
  printf 'endpoint:\n  on_write: notice\n' > "$TMPPROJ/.mesh/endpoint.yaml"
  y="mandate:\n  executor: sdx-test\n  digest: 0123456789ab\n  delivery: ${MAND_DELIVERY:-artifact.offer}\n"
  case "$form" in
    block)
      if [ "$#" -eq 0 ]; then y="${y}  stages:\n"
      else y="${y}  stages:\n"; for s in "$@"; do y="${y}  - $s\n"; done; fi ;;
    flow)
      if [ "$#" -eq 0 ]; then y="${y}  stages: []\n"
      else y="${y}  stages: [$(IFS=,; echo "$*" | sed 's/,/, /g')]\n"; fi ;;
    absent) ;;
  esac
  printf "$y" > "$TMPPROJ/.mesh/mandate.yaml"
}
# put_artifact <sid> <file>: a non-empty artifact in the session directory
put_artifact() { printf 'x\n' > "$TMPPROJ/.claude/sessions/$1/$2"; }
# tree_sum: content snapshot of the whole temp project
tree_sum() { (cd "$TMPPROJ" && find . -type f | sort | while read -r f; do printf '%s ' "$f"; cksum < "$f"; done); }
# active_status <active-set output> <stage>: the status column for a stage
active_status() { printf '%s\n' "$1" | awk -F'\t' -v s="$2" '$1 == s { print $2 }'; }

# ---- Scenario 30: regression — no mandate mode means 2.3.x behaviour ----
if mwant 30; then
echo "[M30] without mandate mode next behaves as before (no .mesh / endpoint only / mandate only)"
for variant in none endpoint-only mandate-only; do
  setup_sdx_repo "m30" "Business Spec"
  put_artifact m30 SPEC.md
  case "$variant" in
    endpoint-only) mkdir -p "$TMPPROJ/.mesh"; printf 'on_write: deny\n' > "$TMPPROJ/.mesh/endpoint.yaml" ;;
    mandate-only)  mkdir -p "$TMPPROJ/.mesh"; printf 'mandate:\n  stages: [spec]\n' > "$TMPPROJ/.mesh/mandate.yaml" ;;
  esac
  out="$(run_stage next m30 2>&1)"; ec=$?
  if [ "$ec" -eq 0 ] && [ "$out" = "OK Business Spec -> Technical Design" ]; then
    pass "[M30] $variant: Business Spec -> Technical Design as in 2.3.x"
  else
    fail "[M30] $variant" "ec=$ec out='$out'"
  fi
  cleanup
done

fi

# ---- Scenario 31: stages [spec] (block and flow) skips design/execute stages; Verification -> Closeout skips Deployment ----
if mwant 31; then
echo "[M31] stages [spec]: Business Spec -> Verification in one next; Verification -> Closeout"
for form in block flow; do
  setup_sdx_repo "m31" "Business Spec"
  setup_mandate "$form" spec
  put_artifact m31 SPEC.md
  out="$(run_stage next m31 2>&1)"; ec=$?
  if [ "$ec" -eq 0 ] && [ "$out" = "OK Business Spec -> Verification" ] && [ "$(jq -r .stage "$(state_file m31)")" = "Verification" ]; then
    pass "[M31] $form: Business Spec -> Verification (design/execute/documentation skipped)"
  else
    fail "[M31] $form forward" "ec=$ec out='$out'"
  fi
  put_artifact m31 verification_report.md
  out="$(run_stage next m31 2>&1)"; ec=$?
  if [ "$ec" -eq 0 ] && [ "$out" = "OK Verification -> Closeout" ]; then
    pass "[M31] $form: Verification -> Closeout (Deployment skipped)"
  else
    fail "[M31] $form to Closeout" "ec=$ec out='$out'"
  fi
  cleanup
done

fi

# ---- Scenario 32: stages [execute, verify]: init on Discovery refused, start-stage finds Execution ----
if mwant 32; then
echo "[M32] stages [execute, verify]: init Discovery -> rc 2; start-stage Discovery -> Execution"
for form in block flow; do
  TMPPROJ="$(mktemp -d)"
  setup_mandate "$form" execute verify
  out="$(run_stage init "m32" "feature" "Discovery" "interactive" "sdx/m32" "false" "false" 2>&1)"; ec=$?
  if [ "$ec" -eq 2 ] && [ ! -f "$(state_file m32)" ] && printf '%s' "$out" | grep -q 'Discovery' && printf '%s' "$out" | grep -q 'start-stage'; then
    pass "[M32] $form: init on an excluded stage -> rc 2, no state file, message names the stage and start-stage"
  else
    fail "[M32] $form init" "ec=$ec out='$out' state=$([ -f "$(state_file m32)" ] && echo yes || echo no)"
  fi
  out="$(run_stage start-stage "Discovery" "false" "false" 2>&1)"; ec=$?
  if [ "$ec" -eq 0 ] && [ "$out" = "Execution" ]; then pass "[M32] $form: start-stage Discovery -> Execution"
  else fail "[M32] $form start-stage" "ec=$ec out='$out'"; fi
  out="$(run_stage init "m32" "feature" "Execution" "interactive" "sdx/m32" "false" "false" 2>&1)"; ec=$?
  if [ "$ec" -eq 0 ] && [ "$(jq -r .stage "$(state_file m32)")" = "Execution" ]; then pass "[M32] $form: init on the allowed stage works"
  else fail "[M32] $form init allowed" "ec=$ec out='$out'"; fi
  cleanup
done

fi

# ---- Scenario 33: Deployment excluded for every delivery (including artifact.offer) ----
if mwant 33; then
echo "[M33] Deployment is excluded for delivery pr / branch / artifact.offer"
for dlv in pr branch artifact.offer; do
  setup_sdx_repo "m33" "Verification"
  MAND_DELIVERY="$dlv" setup_mandate block spec design execute verify
  put_artifact m33 verification_report.md
  out="$(run_stage next m33 2>&1)"; ec=$?
  if [ "$ec" -eq 0 ] && [ "$out" = "OK Verification -> Closeout" ]; then pass "[M33] delivery=$dlv: Verification -> Closeout, Deployment never offered"
  else fail "[M33] delivery=$dlv" "ec=$ec out='$out'"; fi
  cleanup
done

fi

# ---- Scenario 34: --to an excluded stage refused (rc 1, state byte-identical); --to an active stage works ----
if mwant 34; then
echo "[M34] next --to <excluded> -> rc 1, state unchanged, stage named; --to <active> works"
setup_sdx_repo "m34" "Verification"
setup_mandate flow spec
sf="$(state_file m34)"
before="$(cksum < "$sf")"
out="$(run_stage next m34 --to "Execution" 2>&1)"; ec=$?
after="$(cksum < "$sf")"
if [ "$ec" -eq 1 ] && [ "$before" = "$after" ] && printf '%s' "$out" | grep -q 'Execution' && printf '%s' "$out" | grep -q 'execute'; then
  pass "[M34] --to Execution refused: rc 1, state file byte-identical, message names the stage and its class"
else
  fail "[M34] --to excluded" "ec=$ec same=$([ "$before" = "$after" ] && echo yes || echo no) out='$out'"
fi
out="$(run_stage next m34 --to "Deployment" 2>&1)"; ec=$?
if [ "$ec" -eq 1 ] && [ "$(jq -r .stage "$sf")" = "Verification" ]; then pass "[M34] --to Deployment refused under a mandate"
else fail "[M34] --to Deployment" "ec=$ec out='$out'"; fi
out="$(run_stage next m34 --to "Business Spec" 2>&1)"; ec=$?
if [ "$ec" -eq 0 ] && [ "$(jq -r .stage "$sf")" = "Business Spec" ]; then pass "[M34] --to an active stage works as before"
else fail "[M34] --to active" "ec=$ec out='$out'"; fi
cleanup

fi

# ---- Scenario 35: unreadable mandates: next rc 1 (state untouched), init rc 2 (state not created) ----
if mwant 35; then
echo "[M35] unreadable mandate: next -> rc 1, init -> rc 2, fail-closed"
for bad in "not yaml at all" $'repo: x\n' $'mandate:\n  stages: spec\n' $'mandate:\n  stages: [lint]\n' $'mandate:\n\tstages: [spec]\n'; do
  label="$(printf '%s' "$bad" | head -c 30 | tr '\n\t' '~~')"
  setup_sdx_repo "m35" "Business Spec"
  put_artifact m35 SPEC.md
  mkdir -p "$TMPPROJ/.mesh"
  printf 'on_write: notice\n' > "$TMPPROJ/.mesh/endpoint.yaml"
  printf '%s' "$bad" > "$TMPPROJ/.mesh/mandate.yaml"
  sf="$(state_file m35)"; before="$(cksum < "$sf")"
  out="$(run_stage next m35 2>&1)"; ec=$?
  if [ "$ec" -eq 1 ] && [ "$before" = "$(cksum < "$sf")" ] && printf '%s' "$out" | grep -q 'не разобран'; then
    pass "[M35] next, mandate [$label]: rc 1, state unchanged, reason shown"
  else
    fail "[M35] next [$label]" "ec=$ec out='$out'"
  fi
  rm -f "$sf"
  out="$(run_stage init "m35" "feature" "Business Spec" "interactive" "sdx/m35" "false" "false" 2>&1)"; ec=$?
  if [ "$ec" -eq 2 ] && [ ! -f "$sf" ]; then pass "[M35] init, mandate [$label]: rc 2, no state file"
  else fail "[M35] init [$label]" "ec=$ec out='$out'"; fi
  cleanup
done

fi

# ---- Scenario 36: empty / absent stages -> only Verification and Closeout are active ----
if mwant 36; then
echo "[M36] stages empty / [] / absent: Execution -> Verification"
for form in block flow absent; do
  setup_sdx_repo "m36" "Execution"
  setup_mandate "$form"
  out="$(run_stage next m36 2>&1)"; ec=$?
  if [ "$ec" -eq 0 ] && [ "$out" = "OK Execution -> Verification" ]; then pass "[M36] $form: Execution -> Verification"
  else fail "[M36] $form" "ec=$ec out='$out'"; fi
  cleanup
done
TMPPROJ="$(mktemp -d)"; setup_mandate block
out="$(run_stage start-stage "Discovery" "false" "false" 2>&1)"; ec=$?
if [ "$ec" -eq 0 ] && [ "$out" = "Verification" ]; then pass "[M36] start-stage Discovery with empty stages -> Verification"
else fail "[M36] start-stage" "ec=$ec out='$out'"; fi
cleanup

fi

# ---- Scenario 37: no_gates needs execute in the mandate; an existing no_gates session ignores the mandate ----
if mwant 37; then
echo "[M37] no_gates: init / start-stage need execute; next on an existing no_gates session is a no-op"
TMPPROJ="$(mktemp -d)"; setup_mandate flow spec verify
out="$(run_stage init "m37" "proto" "Execution" "interactive" "sdx/m37" "false" "true" 2>&1)"; ec=$?
if [ "$ec" -eq 2 ] && [ ! -f "$(state_file m37)" ]; then pass "[M37] init Execution no_gates=true without execute -> rc 2"
else fail "[M37] init no_gates" "ec=$ec out='$out'"; fi
out="$(run_stage start-stage "Execution" "false" "true" 2>&1)"; ec=$?
if [ "$ec" -eq 1 ] && printf '%s' "$out" | grep -q 'no_gates'; then pass "[M37] start-stage no_gates=true without execute -> rc 1, message names no_gates"
else fail "[M37] start-stage no_gates" "ec=$ec out='$out'"; fi
cleanup
TMPPROJ="$(mktemp -d)"; setup_mandate flow execute
out="$(run_stage start-stage "Execution" "false" "true" 2>&1)"; ec=$?
if [ "$ec" -eq 0 ] && [ "$out" = "Execution" ]; then pass "[M37] start-stage no_gates=true with execute -> Execution"
else fail "[M37] start-stage no_gates ok" "ec=$ec out='$out'"; fi
out="$(run_stage init "m37" "proto" "Execution" "interactive" "sdx/m37" "false" "true" 2>&1)"; ec=$?
if [ "$ec" -eq 0 ] && [ "$(jq -r .no_gates "$(state_file m37)")" = "true" ]; then pass "[M37] init Execution no_gates=true with execute works"
else fail "[M37] init no_gates ok" "ec=$ec out='$out'"; fi
cleanup
setup_sdx_repo "m37b" "Execution" false true
setup_mandate flow spec
out="$(run_stage next m37b 2>&1)"; ec=$?
if [ "$ec" -eq 0 ] && [ "$out" = "OK no-op Execution" ]; then pass "[M37] existing no_gates session: next -> OK no-op Execution regardless of the mandate"
else fail "[M37] existing no_gates session" "ec=$ec out='$out'"; fi
printf 'garbage: [' > "$TMPPROJ/.mesh/mandate.yaml"
out="$(run_stage next m37b 2>&1)"; ec=$?
if [ "$ec" -eq 0 ] && [ "$out" = "OK no-op Execution" ]; then pass "[M37] existing no_gates session: even an unreadable mandate is not read"
else fail "[M37] no_gates unreadable" "ec=$ec out='$out'"; fi
cleanup

fi

# ---- Scenario 38: no_code + stages [execute, verify] ----
if mwant 38; then
echo "[M38] no_code session type + stages [execute, verify]: start-stage Discovery -> Verification"
TMPPROJ="$(mktemp -d)"; setup_mandate block execute verify
out="$(run_stage start-stage "Discovery" "true" "false" 2>&1)"; ec=$?
if [ "$ec" -eq 0 ] && [ "$out" = "Verification" ]; then pass "[M38] no_code + mandate (Execution excluded by no_code): -> Verification"
else fail "[M38] start-stage no_code" "ec=$ec out='$out'"; fi
out="$(run_stage start-stage "Business Spec" "false" "false" 2>&1)"; ec=$?
if [ "$ec" -eq 0 ] && [ "$out" = "Execution" ]; then pass "[M38] start-stage Business Spec without flags -> Execution"
else fail "[M38] start-stage plain" "ec=$ec out='$out'"; fi
out="$(run_stage start-stage "Closeout" "false" "false" 2>&1)"; ec=$?
[ "$ec" -eq 0 ] && [ "$out" = "Closeout" ] && pass "[M38] start-stage Closeout stays Closeout" || fail "[M38] start-stage Closeout" "ec=$ec out='$out'"
out="$(run_stage start-stage "Deployment" "false" "false" 2>&1)"; ec=$?
[ "$ec" -eq 0 ] && [ "$out" = "Closeout" ] && pass "[M38] start-stage Deployment under a mandate -> Closeout" || fail "[M38] start-stage Deployment" "ec=$ec out='$out'"
out="$(run_stage start-stage "Nonsense" "false" "false" 2>&1)"; ec=$?
[ "$ec" -eq 2 ] && pass "[M38] start-stage with an unknown stage -> rc 2" || fail "[M38] start-stage unknown" "ec=$ec out='$out'"
out="$(run_stage start-stage "Discovery" "true" "true" 2>&1)"; ec=$?
[ "$ec" -eq 2 ] && pass "[M38] start-stage with no_code and no_gates both true -> rc 2" || fail "[M38] start-stage both flags" "ec=$ec out='$out'"
out="$(run_stage start-stage "Discovery" "maybe" "false" 2>&1)"; ec=$?
[ "$ec" -eq 2 ] && pass "[M38] start-stage with a non-boolean flag -> rc 2" || fail "[M38] start-stage literal" "ec=$ec out='$out'"
cleanup
TMPPROJ="$(mktemp -d)"
out="$(run_stage start-stage "Business Spec" "false" "false" 2>&1)"; ec=$?
[ "$ec" -eq 0 ] && [ "$out" = "Business Spec" ] && pass "[M38] no mandate: start-stage Business Spec prints Business Spec" || fail "[M38] start-stage without mandate" "ec=$ec out='$out'"
out="$(run_stage start-stage "Execution" "true" "false" 2>&1)"; ec=$?
[ "$ec" -eq 0 ] && [ "$out" = "Verification" ] && pass "[M38] no mandate, no_code: start-stage Execution -> Verification (flag only)" || fail "[M38] start-stage no_code only" "ec=$ec out='$out'"
cleanup

fi

# ---- Scenario 39: active-set ----
if mwant 39; then
echo "[M39] active-set prints nine rows with the narrowing sources"
setup_sdx_repo "m39" "Discovery"
setup_mandate block spec
out="$(run_stage active-set m39 2>&1)"; ec=$?
if [ "$ec" -eq 0 ] && [ "$(printf '%s\n' "$out" | grep -c .)" -eq 9 ] \
   && [ "$(active_status "$out" "Discovery")" = "active" ] && [ "$(active_status "$out" "Business Spec")" = "active" ] \
   && [ "$(active_status "$out" "Technical Design")" = "excluded:mandate(design)" ] \
   && [ "$(active_status "$out" "Execution")" = "excluded:mandate(execute)" ] \
   && [ "$(active_status "$out" "Deployment")" = "excluded:mandate(never)" ] \
   && [ "$(active_status "$out" "Verification")" = "active" ] && [ "$(active_status "$out" "Closeout")" = "active" ]; then
  pass "[M39] stages [spec]: statuses and mandate(<class>) sources"
else
  fail "[M39] active-set mandate" "ec=$ec out='$out'"
fi
cleanup
setup_sdx_repo "m39b" "Discovery" true false
setup_mandate flow execute verify
out="$(run_stage active-set m39b 2>&1)"; ec=$?
if [ "$ec" -eq 0 ] && [ "$(active_status "$out" "Discovery")" = "excluded:mandate(spec)" ] \
   && [ "$(active_status "$out" "Task Planning")" = "excluded:no_code,mandate(design)" ] \
   && [ "$(active_status "$out" "Execution")" = "excluded:no_code" ] \
   && [ "$(active_status "$out" "Deployment")" = "excluded:no_code,mandate(never)" ] \
   && [ "$(active_status "$out" "Verification")" = "active" ]; then
  pass "[M39] no_code + mandate: both sources listed, no_code first"
else
  fail "[M39] active-set no_code" "ec=$ec out='$out'"
fi
cleanup
setup_sdx_repo "m39c" "Execution" false true
setup_mandate flow execute
out="$(run_stage active-set m39c 2>&1)"; ec=$?
if [ "$ec" -eq 0 ] && [ "$(active_status "$out" "Execution")" = "active" ] \
   && [ "$(active_status "$out" "Discovery")" = "excluded:no_gates,mandate(spec)" ] \
   && [ "$(active_status "$out" "Closeout")" = "excluded:no_gates" ]; then
  pass "[M39] no_gates: only Execution active; sources no_gates (+ mandate)"
else
  fail "[M39] active-set no_gates" "ec=$ec out='$out'"
fi
cleanup
setup_sdx_repo "m39d" "Discovery"
out="$(run_stage active-set m39d 2>&1)"; ec=$?
if [ "$ec" -eq 0 ] && [ "$(printf '%s\n' "$out" | grep -c 'active$')" -eq 9 ]; then pass "[M39] no flags, no mandate: all nine stages active"
else fail "[M39] active-set plain" "ec=$ec out='$out'"; fi
cleanup
setup_sdx_repo "m39e" "Discovery"
mkdir -p "$TMPPROJ/.mesh"; printf 'on_write: notice\n' > "$TMPPROJ/.mesh/endpoint.yaml"; printf 'mandate:\n  stages: [lint]\n' > "$TMPPROJ/.mesh/mandate.yaml"
out="$(run_stage active-set m39e 2>/dev/null)"; ec=$?
first="$(printf '%s\n' "$out" | head -1)"
case "$first" in "MANDATE-ERROR "*) [ "$ec" -eq 1 ] && pass "[M39] unreadable mandate: rc 1 and first line MANDATE-ERROR" || fail "[M39] MANDATE-ERROR rc" "ec=$ec" ;; *) fail "[M39] MANDATE-ERROR" "ec=$ec out='$out'" ;; esac
if [ "$(printf '%s\n' "$out" | grep -c 'unknown:mandate')" -eq 9 ] && ! printf '%s\n' "$out" | grep -q 'active'; then pass "[M39] unreadable mandate: nine rows are unknown:mandate, none claims active"
else fail "[M39] unreadable mandate rows" "out='$out'"; fi
cleanup

fi

# ---- Scenario 40: start-stage / active-set are read-only ----
if mwant 40; then
echo "[M40] start-stage and active-set change no file"
setup_sdx_repo "m40" "Discovery"
setup_mandate block spec
snap1="$(tree_sum)"
o1="$(run_stage start-stage "Discovery" "false" "false" 2>&1)"; e1=$?
o2="$(run_stage start-stage "Execution" "false" "true" 2>&1)"; e2=$?
o3="$(run_stage active-set m40 2>&1)"; e3=$?
snap2="$(tree_sum)"
if [ "$e1" -eq 0 ] && [ "$o1" = "Discovery" ] && [ "$e2" -eq 1 ] && [ "$e3" -eq 0 ] && [ -n "$o3" ] && [ -n "$snap1" ] && [ "$snap1" = "$snap2" ]; then
  pass "[M40] the commands ran (rc 0/1/0) and the project tree is byte-identical afterwards"
else fail "[M40] read-only" "rc=$e1/$e2/$e3 o1='$o1' tree-same=$([ "$snap1" = "$snap2" ] && echo yes || echo no)"; fi
cleanup
fi

# ---- [42] (FEAT-017, REQ-PKG-25): the optional field `commitment` survives every stage write ----
# The field is written by order-import.sh stamp-state (a separate jq after init), never by this script; here it is
# stamped with the same jq. Characterisation: passes without new code in sdx-stage.sh; its red side is the mutant
# of write_stage in [M41] below (the mutant keeps only `.stage`, a copy of the script — the checkout is untouched).
if mwant 42; then
echo "[42] commitment survives next / next --to; init writes the seven keys and no commitment"
TMPPROJ="$(mktemp -d)"
out="$(run_stage init m42 feature Discovery interactive sdx/m42 false false 2>&1)"; ec=$?
keys="$(jq -r 'keys | join(",")' "$(state_file m42)" 2>/dev/null)"
if [ "$ec" -eq 0 ] && [ "$keys" = "gate_mode,git_branch,no_code,no_gates,session_id,stage,type" ]; then
  pass "[42] init writes exactly the seven keys, no commitment"
else fail "[42] init keys" "ec=$ec keys=[$keys] out=[$out]"; fi
sf="$(state_file m42)"
jq --arg c "C-ACME-001" '. + {commitment:$c}' "$sf" > "$sf.tmp" && mv "$sf.tmp" "$sf"
others_before="$(jq -S 'del(.commitment, .stage)' "$sf")"
put_artifact m42 context_report.md
out="$(run_stage next m42 2>&1)"; ec=$?
if [ "$ec" -eq 0 ] && [ "$(jq -r .stage "$sf")" = "Business Spec" ] && [ "$(jq -r .commitment "$sf")" = "C-ACME-001" ]; then
  pass "[42] next keeps commitment (Discovery -> Business Spec)"
else fail "[42] next keeps commitment" "ec=$ec out=[$out] state=$(jq -c . "$sf")"; fi
out="$(run_stage next m42 --to Discovery 2>&1)"; ec=$?
if [ "$ec" -eq 0 ] && [ "$(jq -r .stage "$sf")" = "Discovery" ] && [ "$(jq -r .commitment "$sf")" = "C-ACME-001" ]; then
  pass "[42] next --to keeps commitment (back to Discovery)"
else fail "[42] next --to keeps commitment" "ec=$ec out=[$out] state=$(jq -c . "$sf")"; fi
if [ "$(jq -S 'del(.commitment, .stage)' "$sf")" = "$others_before" ]; then pass "[42] the other keys are byte-for-byte the same after both writes"
else fail "[42] other keys" "changed: $(jq -c . "$sf")"; fi
cleanup
fi

# ---- [43] (DEBT-046, found 2026-10-31): the no_code refusal of `next --to` must not leave a stray file ----
# The refusal text used to carry backticks inside double quotes — a command substitution whose
# `-> false` part is a redirect, silently creating an empty file named 'false' in the cwd.
if mwant 43; then
echo "[43] next --to refused under no_code: no stray file in the cwd, no backticks in the message"
setup_sdx_repo "m43" "Verification" "true" "false"
rm -f "$PWD/false"
out="$(run_stage next "m43" --to "Execution" 2>&1 1>/dev/null)"; ec=$?
if [ "$ec" -eq 1 ] && [ ! -e "$PWD/false" ] && ! printf '%s' "$out" | grep -q '[`]'; then
  pass "[43] refusal (rc 1) leaves no '\$PWD/false' and carries no backticks (DEBT-046)"
else
  fail "[43] no_code refusal side effect" "ec=$ec stray=$([ -e "$PWD/false" ] && echo yes || echo no) backticks=$(printf '%s' "$out" | grep -c '[`]')"
fi
rm -f "$PWD/false"
fi

# ---- [M41] mutation runs (FEAT-016): copies of sdx-stage.sh + lib/ in a temp dir, anchored by "# MAND-*" tags ----
if [ -z "${SDX_STAGE_MUT:-}" ]; then
echo "[M41] mutation runs: each mutant must differ from the original and turn its scenarios red"
MUTROOT="$(mktemp -d)"
# smut <name> <file> <sed-expr> <scenarios>: <file> is sdx-stage.sh or lib/mandate.sh
smut() {
  local name="$1" file="$2" expr="$3" only="$4" d="$MUTROOT/$1" out first
  mkdir -p "$d/lib"
  cp "$SCRIPT_DIR/sdx-stage.sh" "$d/"; cp "$SCRIPT_DIR"/lib/*.sh "$d/lib/"
  sed "$expr" "$SCRIPT_DIR/$file" > "$d/$file"
  if cmp -s "$SCRIPT_DIR/$file" "$d/$file"; then fail "[M41] $name" "mutant is identical to the original (anchor missing?)"; return; fi
  out="$(SDX_STAGE_MUT=1 SDX_STAGE_UNDER_TEST="$d/sdx-stage.sh" SDX_STAGE_ONLY="$only" bash "${BASH_SOURCE[0]}" 2>&1)"
  if printf '%s\n' "$out" | grep -q 'FAIL:'; then
    first="$(printf '%s\n' "$out" | grep -m1 'FAIL:' | cut -c1-110)"
    pass "[M41] мутант $name → красный (ожидаемо) в [M$only]: ${first#  FAIL: }"
  else
    fail "[M41] $name" "scenarios [$only] stayed green on the mutant (the check proves nothing)"
  fi
}
smut MAND-MODE   sdx-stage.sh '/# MAND-MODE/s|\[ -f "\$proj/.mesh/endpoint.yaml" \] \&\& ||' "30"
smut MAND-EXCL   sdx-stage.sh '/# MAND-EXCL/s|{ \[ "\$MANDATE_ON" = 1 \] \&\& ! mandate_stage_allowed "\$1"; }|{ return 1; }|' "31 34"
smut MAND-SKIP   sdx-stage.sh '/# MAND-SKIP/s|while is_skipped .* do|while false; do|' "31"
smut MAND-DEPLOY lib/mandate.sh '/# MAND-NEVER/s/return 1/return 0/' "33"
smut SDX-UNKNOWN sdx-stage.sh '/# SDX-UNKNOWN/s|\[ "\$rc" -ne 0 \]|false|' "39"
smut MAND-TO     sdx-stage.sh '/# MAND-TO/s|if is_excluded_by_mandate "\$to_target"; then|if false; then|' "34"
# FEAT-017: a write_stage that keeps only `.stage` loses the optional `commitment` field -> [42] (no anchor in sdx-stage.sh: matched by text)
smut WRITE-STAGE-COMMITMENT sdx-stage.sh "s|jq --arg s \"\$new\" '\.stage = \$s' \"\$state\"|jq --arg s \"\$new\" '{stage: \$s}' \"\$state\"|" "42"
smut STRAY-FALSE sdx-stage.sh 's|(no_code: true -> false в|(`no_code: true -> false` в|' "43"
rm -f "$PWD/false"   # the STRAY-FALSE mutant recreates the stray file by design; never leave it in the checkout
rm -rf "$MUTROOT"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "ALL PASSED"
  exit 0
else
  exit 1
fi
