#!/usr/bin/env bash
# Unit tests for stage-write-guard.sh (REQ-DENY-1..4).
# Runs self-contained: creates temporary git repos, exercises the hook, cleans up.
# Style mirrors test-stage-gate.sh (JSON on stdin via run_hook).
# Usage: bash sdx/hooks/test-stage-write-guard.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/stage-write-guard.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# Global temp dir for each test; cleaned up by cleanup().
TMPPROJ=""

# setup_sdx_repo <branch-name> <stage>
#   Creates a temp git repo on the given branch. If <stage> is non-empty, also
#   creates .claude/sessions/<sid>/session_state.json with that stage. If <stage>
#   is empty, no session_state.json is created (used by the "creation" scenario).
setup_sdx_repo() {
  local branch="$1"
  local stage="$2"
  TMPPROJ="$(mktemp -d)"
  git -C "$TMPPROJ" init -q
  git -C "$TMPPROJ" config user.email "test@test.com"
  git -C "$TMPPROJ" config user.name "Test"
  git -C "$TMPPROJ" commit -q --allow-empty -m "init"
  # Ensure branch is called 'main' regardless of system default.
  git -C "$TMPPROJ" branch -M main 2>/dev/null || true

  case "$branch" in
    sdx/*)
      local sid="${branch#sdx/}"
      git -C "$TMPPROJ" checkout -q -b "$branch"
      mkdir -p "$TMPPROJ/.claude/sessions/$sid"
      if [ -n "$stage" ]; then
        printf '{"stage":"%s"}' "$stage" > "$TMPPROJ/.claude/sessions/$sid/session_state.json"
      fi
      ;;
    *)
      # Stay on default (main) branch; no session state created.
      ;;
  esac
}

cleanup() {
  [ -n "$TMPPROJ" ] && rm -rf "$TMPPROJ"
  TMPPROJ=""
}

# run_hook <json-stdin>
#   Pipe json to the hook with CLAUDE_PROJECT_DIR set to TMPPROJ.
run_hook() {
  printf '%s' "$1" | CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK"
}

# run_hook_stderr <json-stdin> <stderr-file>
#   Same as run_hook, but also captures stderr into the given file — needed when a
#   scenario must assert on both the deny JSON on stdout AND a diagnostic on stderr
#   (e.g. the WARN-1 tool-failure case).
run_hook_stderr() {
  printf '%s' "$1" | CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK" 2>"$2"
}

# run_hook_nojq <json-stdin> <stderr-file>
#   Same, but with a PATH that has every tool the hook needs EXCEPT jq (mirrors
#   the NOJQ_BIN pattern already used by test-prod-guard.sh scenario 5/6/7).
#   Uses `type -P` (not `command -v`) to resolve real binaries: some sandboxed
#   shells define a `grep` shell function shadowing /usr/bin/grep, which would
#   otherwise produce a broken self-referential symlink here.
#   NOTE: writes stderr to the caller-supplied <stderr-file> rather than setting
#   a variable, because callers invoke this via `out="$(run_hook_nojq ...)"` —
#   command substitution runs the function in a subshell, so any variable it
#   sets is invisible to the caller once the subshell exits; a file survives.
run_hook_nojq() {
  local NOJQ_BIN
  NOJQ_BIN="$(mktemp -d)"
  for t in bash cat grep sed head printf git dirname mkdir rm; do
    src="$(type -P "$t" 2>/dev/null)" && ln -s "$src" "$NOJQ_BIN/$t" 2>/dev/null || true
  done
  printf '%s' "$1" | PATH="$NOJQ_BIN" CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK" 2>"$2"
  rm -rf "$NOJQ_BIN"
}

echo "=== test-stage-write-guard.sh ==="
echo ""

STATE_REL=".claude/sessions/test-swg/session_state.json"

# ---- Scenario 1: Edit changes "stage" -> deny ----
echo "[1] Edit changes \"stage\" value -> deny"
setup_sdx_repo "sdx/test-swg" "Execution"
NEW_STRING='{"stage":"Documentation"}'
out="$(run_hook "$(jq -cn --arg fp "$TMPPROJ/$STATE_REL" --arg ns "$NEW_STRING" '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"{\"stage\":\"Execution\"}",new_string:$ns}}')")"
ec=$?
if [ "$ec" -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then
  pass "deny JSON, exit 0"
else
  fail "Expected deny JSON + exit 0" "ec=$ec out=$out"
fi
cleanup

# ---- Scenario 2: Write with full content, .stage differs -> deny ----
echo "[2] Write with changed .stage -> deny"
setup_sdx_repo "sdx/test-swg" "Execution"
CONTENT='{"session_id":"test-swg","stage":"Documentation","track":"full"}'
out="$(run_hook "$(jq -cn --arg fp "$TMPPROJ/$STATE_REL" --arg c "$CONTENT" '{tool_name:"Write",tool_input:{file_path:$fp,content:$c}}')")"
ec=$?
if [ "$ec" -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then
  pass "deny JSON, exit 0"
else
  fail "Expected deny JSON + exit 0" "ec=$ec out=$out"
fi
cleanup

# ---- Scenario 3: Edit/Write touching only track/gate_mode/artifacts/history -> pass ----
echo "[3a] Edit changing only 'track' -> pass"
setup_sdx_repo "sdx/test-swg" "Execution"
out="$(run_hook "$(jq -cn --arg fp "$TMPPROJ/$STATE_REL" '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"\"track\":\"full\"",new_string:"\"track\":\"standard\""}}')")"
ec=$?
if [ "$ec" -eq 0 ] && [ -z "$out" ]; then
  pass "stdout empty, exit 0"
else
  fail "Expected empty stdout + exit 0" "ec=$ec out='$out'"
fi
cleanup

echo "[3b] Write changing content but .stage unchanged -> pass"
setup_sdx_repo "sdx/test-swg" "Execution"
CONTENT='{"session_id":"test-swg","stage":"Execution","track":"full","gate_mode":"auto","artifacts":["DESIGN.md"],"history":[]}'
out="$(run_hook "$(jq -cn --arg fp "$TMPPROJ/$STATE_REL" --arg c "$CONTENT" '{tool_name:"Write",tool_input:{file_path:$fp,content:$c}}')")"
ec=$?
if [ "$ec" -eq 0 ] && [ -z "$out" ]; then
  pass "stdout empty, exit 0"
else
  fail "Expected empty stdout + exit 0" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 4: Write creating a not-yet-existing session_state.json -> pass (carve-out) ----
echo "[4] Write creating session_state.json that does not exist yet -> pass (REQ-DENY-2)"
setup_sdx_repo "sdx/test-swg" ""   # no session_state.json created
CONTENT='{"session_id":"test-swg","stage":"Discovery","track":"full","gate_mode":"interactive","artifacts":[],"history":[]}'
out="$(run_hook "$(jq -cn --arg fp "$TMPPROJ/$STATE_REL" --arg c "$CONTENT" '{tool_name:"Write",tool_input:{file_path:$fp,content:$c}}')")"
ec=$?
if [ "$ec" -eq 0 ] && [ -z "$out" ]; then
  pass "stdout empty, exit 0 (creation not blocked)"
else
  fail "Expected empty stdout + exit 0" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 5: outside sdx/* branch (on main) -> pass ----
echo "[5] Edit changing 'stage' outside SDX branch (on main) -> pass"
setup_sdx_repo "main" ""
out="$(run_hook "$(jq -cn --arg fp "$TMPPROJ/$STATE_REL" '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"a",new_string:"{\"stage\":\"Documentation\"}"}}')")"
ec=$?
if [ "$ec" -eq 0 ] && [ -z "$out" ]; then
  pass "stdout empty, exit 0 (not an SDX branch)"
else
  fail "Expected empty stdout + exit 0" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 6: session_state.json at a DIFFERENT path -> pass (exact-path match) ----
echo "[6] session_state.json at a different path (docs/session_state.json) -> pass"
setup_sdx_repo "sdx/test-swg" "Execution"
out="$(run_hook "$(jq -cn --arg fp "$TMPPROJ/docs/session_state.json" '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"a",new_string:"{\"stage\":\"Documentation\"}"}}')")"
ec=$?
if [ "$ec" -eq 0 ] && [ -z "$out" ]; then
  pass "stdout empty, exit 0 (path matched by basename only, not full path)"
else
  fail "Expected empty stdout + exit 0" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 7: MultiEdit, one edit's new_string contains "stage": -> deny for whole batch ----
echo "[7] MultiEdit — one of several edits touches \"stage\": -> deny whole batch"
setup_sdx_repo "sdx/test-swg" "Execution"
# Real content must actually contain both fields the edits target — the new
# apply-and-compare mechanism (F-2 fix) simulates literal substitution against the
# real file, so a "track" edit against a file that has no "track" key would report
# "old_string not found" (see scenario 13) rather than exercising this scenario's
# intent (a benign edit followed by a stage-touching one). Overwrite the minimal
# single-field fixture with a two-field one.
printf '{"stage":"Execution","track":"full"}' > "$TMPPROJ/$STATE_REL"
INPUT="$(jq -cn --arg fp "$TMPPROJ/$STATE_REL" '
  {tool_name:"MultiEdit",tool_input:{file_path:$fp,edits:[
    {old_string:"\"track\":\"full\"",new_string:"\"track\":\"standard\""},
    {old_string:"\"stage\":\"Execution\"",new_string:"\"stage\":\"Documentation\""}
  ]}}')"
out="$(run_hook "$INPUT")"
ec=$?
if [ "$ec" -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then
  pass "deny JSON, exit 0 (whole MultiEdit batch blocked)"
else
  fail "Expected deny JSON + exit 0" "ec=$ec out=$out"
fi
cleanup

# ---- Scenario 8: jq missing, operation actually edits stage of an existing session ----
echo "[8] jq absent from PATH, real stage edit -> pass (exit 0) + stderr warning, NOT deny (REQ-DENY-4)"
setup_sdx_repo "sdx/test-swg" "Execution"
INPUT="$(jq -cn --arg fp "$TMPPROJ/$STATE_REL" '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"a",new_string:"{\"stage\":\"Documentation\"}"}}')"
STDERR_FILE="$(mktemp)"
out="$(run_hook_nojq "$INPUT" "$STDERR_FILE")"
ec=$?
RUN_STDERR="$(cat "$STDERR_FILE" 2>/dev/null || true)"
rm -f "$STDERR_FILE"
if [ "$ec" -eq 0 ] && [ -z "$out" ] && printf '%s' "$RUN_STDERR" | grep -qi "jq"; then
  pass "exit 0, no deny JSON, stderr warns about missing jq (fail-open)"
else
  fail "Expected exit 0 + empty stdout + jq warning on stderr" "ec=$ec out='$out' stderr='$RUN_STDERR'"
fi
cleanup

# ---- Scenario 9: Edit touching a "stage" mention that does NOT change its value ----
# CONTRACT CHANGE (post F-2 fix, deliberate — see verification_report.md finding F-2 and
# session report): the old key-regex mechanism treated ANY fragment containing the
# `"stage"` key substring as a hit, regardless of whether the value actually changed —
# this whitespace-reformatting case was a *documented, accepted* false positive under
# that mechanism. The new mechanism applies the edit to the real file content and
# compares the PARSED `.stage` value before/after, so a reformat that leaves the value
# unchanged is correctly recognized as a no-op and now PASSES. This is not a regression:
# it is the direct, intended benefit of switching from key-substring matching to a real
# apply-and-compare — it removes a previously-accepted false positive without
# reintroducing the false negative described in F-2 (see scenarios 11/12 below).
echo "[9] Edit reformats whitespace around \"stage\" without changing its value -> pass (false positive removed by F-2 fix)"
setup_sdx_repo "sdx/test-swg" "Execution"
INPUT="$(jq -cn --arg fp "$TMPPROJ/$STATE_REL" '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"\"stage\":\"Execution\"","new_string":"\"stage\" :  \"Execution\""}}')"
out="$(run_hook "$INPUT")"
ec=$?
if [ "$ec" -eq 0 ] && [ -z "$out" ]; then
  pass "stdout empty, exit 0 (value unchanged -> not blocked)"
else
  fail "Expected empty stdout + exit 0" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 10: Windows backslash path -> guard still fires (BUG-006 pattern) ----
echo "[10] Backslash (Windows-style) path to session_state.json -> deny same as forward-slash"
setup_sdx_repo "sdx/test-swg" "Execution"
winpath="$(printf '%s' "$TMPPROJ/$STATE_REL" | tr '/' '\\')"
INPUT="$(jq -cn --arg fp "$winpath" '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"a",new_string:"{\"stage\":\"Documentation\"}"}}')"
out="$(run_hook "$INPUT")"
ec=$?
if [ "$ec" -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then
  pass "deny JSON, exit 0 (backslash path normalized before matching)"
else
  fail "Expected deny JSON + exit 0" "ec=$ec out=$out"
fi
cleanup

# ---- Scenario 11: Edit changes the "stage" VALUE without mentioning the key at all ----
# THE F-2 REGRESSION TEST (verification_report.md finding F-2): a fully realistic Edit
# form — `old_string`/`new_string` are just the quoted value, no `"stage"` key substring
# anywhere in the fragment. Under the old key-regex mechanism this was a silent bypass
# (reproduced in the report: exit 0, empty stdout, no deny). The fix must catch this by
# applying the edit to the real file and comparing the parsed `.stage` value.
echo "[11] Edit changes stage VALUE only, key never appears in the fragment -> deny (F-2 regression)"
setup_sdx_repo "sdx/test-swg" "Execution"
INPUT="$(jq -cn --arg fp "$TMPPROJ/$STATE_REL" '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"\"Execution\"",new_string:"\"Closeout\""}}')"
out="$(run_hook "$INPUT")"
ec=$?
if [ "$ec" -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then
  pass "deny JSON, exit 0 (value-only bypass caught)"
else
  fail "Expected deny JSON + exit 0 (F-2 bypass NOT caught)" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 12: MultiEdit — same value-only bypass, but via MultiEdit ----
echo "[12] MultiEdit — one edit changes stage VALUE only, key never appears -> deny whole batch (F-2 regression)"
setup_sdx_repo "sdx/test-swg" "Execution"
printf '{"stage":"Execution","track":"full"}' > "$TMPPROJ/$STATE_REL"
INPUT="$(jq -cn --arg fp "$TMPPROJ/$STATE_REL" '
  {tool_name:"MultiEdit",tool_input:{file_path:$fp,edits:[
    {old_string:"\"track\":\"full\"",new_string:"\"track\":\"standard\""},
    {old_string:"\"Execution\"",new_string:"\"Closeout\""}
  ]}}')"
out="$(run_hook "$INPUT")"
ec=$?
if [ "$ec" -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then
  pass "deny JSON, exit 0 (value-only bypass caught via MultiEdit)"
else
  fail "Expected deny JSON + exit 0 (F-2 bypass NOT caught)" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 13: Edit whose old_string is not present in the file at all -> pass ----
# The real Edit tool call would itself fail (old_string not found) before ever writing
# anything, so the hook must not deny here — there is nothing to gate.
echo "[13] Edit old_string not found in file -> pass (real Edit would fail on its own, nothing to gate)"
setup_sdx_repo "sdx/test-swg" "Execution"
INPUT="$(jq -cn --arg fp "$TMPPROJ/$STATE_REL" '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"\"Deployment\"",new_string:"\"Closeout\""}}')"
out="$(run_hook "$INPUT")"
ec=$?
if [ "$ec" -eq 0 ] && [ -z "$out" ]; then
  pass "stdout empty, exit 0 (old_string absent, not blocked)"
else
  fail "Expected empty stdout + exit 0" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 14: replace_all=false (default) only touches the FIRST occurrence, ----
# ---- which here is NOT the stage field -> pass ----
echo "[14] Edit replace_all=false only replaces first match (non-stage field) -> pass"
setup_sdx_repo "sdx/test-swg" "Execution"
printf '{"note":"Execution","stage":"Execution"}' > "$TMPPROJ/$STATE_REL"
INPUT="$(jq -cn --arg fp "$TMPPROJ/$STATE_REL" '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"\"Execution\"",new_string:"\"Documentation\""}}')"
out="$(run_hook "$INPUT")"
ec=$?
if [ "$ec" -eq 0 ] && [ -z "$out" ]; then
  pass "stdout empty, exit 0 (only the non-stage occurrence was touched)"
else
  fail "Expected empty stdout + exit 0" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 15: replace_all=true replaces ALL occurrences, including the stage one ----
# -> deny
echo "[15] Edit replace_all=true replaces every match, including the stage field -> deny"
setup_sdx_repo "sdx/test-swg" "Execution"
printf '{"note":"Execution","stage":"Execution"}' > "$TMPPROJ/$STATE_REL"
INPUT="$(jq -cn --arg fp "$TMPPROJ/$STATE_REL" '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"\"Execution\"",new_string:"\"Documentation\"",replace_all:true}}')"
out="$(run_hook "$INPUT")"
ec=$?
if [ "$ec" -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then
  pass "deny JSON, exit 0 (replace_all correctly touched the stage occurrence too)"
else
  fail "Expected deny JSON + exit 0" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 16: WARN-1 regression — awk itself fails to exec (E2BIG on ENVIRON) on ----
# ---- an oversized session_state.json -> must DENY, not silently pass. ----
# verification_report.md WARN-1: `literal_replace` passes the whole file content through
# an awk ENVIRON variable; past ~131072 bytes (Linux single-arg/env-string exec limit),
# the `awk` process itself fails to start ("Argument list too long", non-zero exit) —
# a TOOL failure, indistinguishable (before the fix) from the STATUS "old_string not
# found" (also non-zero exit), which the caller treats as "nothing to gate" -> the edit
# sails through undetected even when it demonstrably changes `stage`.
echo "[16] Edit on an oversized session_state.json (awk ENVIRON exec failure) -> deny, not silent bypass (WARN-1)"
setup_sdx_repo "sdx/test-swg" "Execution"
BIG_PAD="$(head -c 140000 /dev/zero | tr '\0' 'x')"
printf '{"stage":"Execution","pad":"%s"}' "$BIG_PAD" > "$TMPPROJ/$STATE_REL"
INPUT="$(jq -cn --arg fp "$TMPPROJ/$STATE_REL" '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"\"Execution\"",new_string:"\"Closeout\""}}')"
STDERR_FILE="$(mktemp)"
out="$(run_hook_stderr "$INPUT" "$STDERR_FILE")"
ec=$?
RUN_STDERR="$(cat "$STDERR_FILE" 2>/dev/null || true)"
rm -f "$STDERR_FILE"
if [ "$ec" -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then
  pass "deny JSON, exit 0 (awk tool failure denied, not silently bypassed)"
else
  fail "Expected deny JSON + exit 0 (awk exec failure must not silently bypass the gate)" "ec=$ec out='$out' stderr='$RUN_STDERR'"
fi
cleanup

# ---- Scenario 17: same WARN-1 tool-failure regression, via MultiEdit ----
echo "[17] MultiEdit on an oversized session_state.json (awk ENVIRON exec failure) -> deny, not silent bypass (WARN-1)"
setup_sdx_repo "sdx/test-swg" "Execution"
BIG_PAD="$(head -c 140000 /dev/zero | tr '\0' 'x')"
printf '{"stage":"Execution","track":"full","pad":"%s"}' "$BIG_PAD" > "$TMPPROJ/$STATE_REL"
INPUT="$(jq -cn --arg fp "$TMPPROJ/$STATE_REL" '
  {tool_name:"MultiEdit",tool_input:{file_path:$fp,edits:[
    {old_string:"\"track\":\"full\"",new_string:"\"track\":\"standard\""},
    {old_string:"\"stage\":\"Execution\"",new_string:"\"stage\":\"Closeout\""}
  ]}}')"
out="$(run_hook "$INPUT")"
ec=$?
if [ "$ec" -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then
  pass "deny JSON, exit 0 (awk tool failure in MultiEdit denied, not silently bypassed)"
else
  fail "Expected deny JSON + exit 0 (awk exec failure must not silently bypass the gate)" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 18: WARN-2 regression — Write repairing an already-corrupt ----
# ---- session_state.json must NOT be blocked (the code comment already promises this; ----
# ---- the Write branch just never implemented the carve-out). ----
echo "[18] Write with fully valid content repairs an already-corrupt session_state.json -> pass (WARN-2)"
setup_sdx_repo "sdx/test-swg" "Execution"
printf '{"stage":"Execution",,,' > "$TMPPROJ/$STATE_REL"
CONTENT='{"stage":"Execution"}'
out="$(run_hook "$(jq -cn --arg fp "$TMPPROJ/$STATE_REL" --arg c "$CONTENT" '{tool_name:"Write",tool_input:{file_path:$fp,content:$c}}')")"
ec=$?
if [ "$ec" -eq 0 ] && [ -z "$out" ]; then
  pass "stdout empty, exit 0 (repair of an already-broken file is not blocked)"
else
  fail "Expected empty stdout + exit 0 (repair must not be blocked, WARN-2)" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 19: WARN-2 regression — Edit repairing an already-corrupt ----
# ---- session_state.json (turning ",,," into "}") must NOT be blocked either. ----
echo "[19] Edit repairs an already-corrupt session_state.json -> pass (WARN-2)"
setup_sdx_repo "sdx/test-swg" "Execution"
printf '{"stage":"Execution",,,' > "$TMPPROJ/$STATE_REL"
INPUT="$(jq -cn --arg fp "$TMPPROJ/$STATE_REL" '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:",,,",new_string:"}"}}')"
out="$(run_hook "$INPUT")"
ec=$?
if [ "$ec" -eq 0 ] && [ -z "$out" ]; then
  pass "stdout empty, exit 0 (repair of an already-broken file is not blocked)"
else
  fail "Expected empty stdout + exit 0 (repair must not be blocked, WARN-2)" "ec=$ec out='$out'"
fi
cleanup

# ---- Scenario 20: WARN-3 (partial fix) — a "/./" segment in file_path must not ----
# ---- defeat the exact-path comparison. (True relative-path resolution is left as a ----
# ---- documented, accepted gap — see stage-write-guard.sh comment at the normalizer.) ----
echo "[20] file_path containing a '/./' segment still matches session_state.json -> deny (WARN-3)"
setup_sdx_repo "sdx/test-swg" "Execution"
dotted_path="$TMPPROJ/.claude/./sessions/test-swg/session_state.json"
INPUT="$(jq -cn --arg fp "$dotted_path" '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"\"Execution\"",new_string:"\"Closeout\""}}')"
out="$(run_hook "$INPUT")"
ec=$?
if [ "$ec" -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then
  pass "deny JSON, exit 0 (/./ segment normalized before path comparison)"
else
  fail "Expected deny JSON + exit 0" "ec=$ec out='$out'"
fi
cleanup

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "ALL PASSED"
  exit 0
else
  exit 1
fi
