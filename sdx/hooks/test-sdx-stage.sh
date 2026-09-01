#!/usr/bin/env bash
# Unit tests for sdx-stage.sh (REQ-SCALE-1..9, REQ-FLAG-1..4, REQ-LEGAL-1, REQ-COMPAT-1..3,
# REQ-NAV-1..2). Runs self-contained: creates temporary "project" dirs, exercises the CLI,
# cleans up. Usage: bash sdx/hooks/test-sdx-stage.sh
#
# Scenario 29 (REQ-TEST-1) cross-checks the canonical stage_names() order against the
# human-readable stage-order projection table in sdx/protocol.md — see that scenario below.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/sdx-stage.sh"

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
    '{session_id:$session_id, type:$type, stage:$stage, gate_mode:"interactive", git_branch:("sdx/"+$session_id), no_code:$no_code, no_gates:$no_gates, artifacts:[], history:[]}' \
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
# stages pointing at the SAME change_note.md, does not duplicate the banner ----
echo "[19] next --to: repeated marking of the same change_note.md via two foldable stages does not duplicate the banner"
setup_sdx_repo "t19" "Task Planning"
printf '# note\n' > "$TMPPROJ/.claude/sessions/t19/change_note.md"
run_stage next "t19" --to "Discovery" > /dev/null
count1="$(grep -c '<!-- SDX-OUTDATED' "$TMPPROJ/.claude/sessions/t19/change_note.md")"
# Move forward again then back to a DIFFERENT foldable stage to re-trigger marking logic.
run_stage next "t19" --to "Business Spec" > /dev/null 2>&1
run_stage next "t19" --to "Discovery" > /dev/null
count2="$(grep -c '<!-- SDX-OUTDATED' "$TMPPROJ/.claude/sessions/t19/change_note.md")"
if [ "$count1" -eq 1 ] && [ "$count2" -eq 1 ]; then
  pass "banner never duplicated across repeated marking of the same file"
else
  fail "Expected exactly one banner occurrence" "count1=$count1 count2=$count2"
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
jq -n '{session_id:"t24", type:"feature", track:"full", stage:"Discovery", gate_mode:"interactive", git_branch:"sdx/t24", artifacts:[], history:[]}' \
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
jq -n '{session_id:"t25", type:"feature", track:"standard", stage:"Change", gate_mode:"interactive", git_branch:"sdx/t25", artifacts:[], history:[]}' \
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
jq -n '{session_id:"t26", type:"grooming", track:"doc", stage:"Update", gate_mode:"interactive", git_branch:"sdx/t26", artifacts:[], history:[]}' \
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
jq -n '{session_id:"t27", type:"feature", stage:"", gate_mode:"interactive", git_branch:"sdx/t27", no_code:false, no_gates:false, artifacts:[], history:[]}'   > "$TMPPROJ/.claude/sessions/t27/session_state.json"
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
jq -n '{session_id:"t28", type:"feature", gate_mode:"interactive", git_branch:"sdx/t28", no_code:false, no_gates:false, artifacts:[], history:[]}'   > "$TMPPROJ/.claude/sessions/t28/session_state.json"
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

# ---- Scenario 29 (REQ-TEST-1): sanity — canonical stage_names() order matches the
# human-readable stage-order projection table in sdx/protocol.md. The single machine-
# readable source of truth is SDX_STAGE_TABLE inside this script; sdx/protocol.md keeps a
# projection of the same order for humans (section "Единая шкала этапов и режимы-флаги").
# This scenario fails on ANY divergence — a skipped/added/reordered stage name in either
# place — by comparing the two ordered lists line by line. ----
echo "[29] REQ-TEST-1 sanity: stage_names() order matches sdx/protocol.md's stage-order table"
PROTOCOL_MD="$SCRIPT_DIR/../protocol.md"
if [ ! -f "$PROTOCOL_MD" ]; then
  fail "sdx/protocol.md not found for REQ-TEST-1 cross-check" "expected at $PROTOCOL_MD"
else
  # stage_names() is not exposed as a subcommand — extract the same ordered list directly
  # from SDX_STAGE_TABLE via awk, exactly like the function itself does, to avoid depending
  # on an extra CLI surface just for this test.
  script_order="$(awk -F'|' '$1{print $1}' <<<"$(sed -n "/^SDX_STAGE_TABLE='/,/^'/p" "$SCRIPT" | sed '1d;$d')")"
  protocol_order="$(grep -E '^\| [0-9] \| ' "$PROTOCOL_MD" | awk -F'|' '{gsub(/^ +| +$/, "", $3); print $3}')"
  if [ "$script_order" = "$protocol_order" ]; then
    pass "canonical stage order in sdx-stage.sh matches sdx/protocol.md's projection table"
  else
    fail "stage order mismatch between sdx-stage.sh (SDX_STAGE_TABLE) and sdx/protocol.md" \
      "script: [$script_order] protocol: [$protocol_order]"
  fi
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "ALL PASSED"
  exit 0
else
  exit 1
fi
