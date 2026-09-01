#!/usr/bin/env bash
# Unit tests for the hook wiring in hooks/hooks.json (BUG-008).
#
# Invariant under test: every registered hook command invokes its script through
# `bash <path>` rather than executing the file directly. Direct execution requires
# the exec bit, and plugin installs are not guaranteed to preserve file modes —
# an install delivering 0600 would turn the whole deterministic enforcement layer
# (SessionStart / PreToolUse / Stop) into a silent no-op with exit 126, invisible
# to the user (DEBT-010).
#
# Usage: bash sdx/hooks/test-hook-wiring.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WIRING="$ROOT/hooks/hooks.json"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

echo "=== test-hook-wiring.sh ==="
echo ""

# ---- Scenario 1: wiring file is valid JSON and registers hooks ----
echo "[1] hooks.json parses and registers at least one command"
if [ -f "$WIRING" ] && jq -e . "$WIRING" >/dev/null 2>&1; then
  pass "hooks.json exists and is valid JSON"
else
  fail "hooks.json missing or not valid JSON" "$WIRING"
  echo ""; echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"; exit 1
fi

mapfile -t COMMANDS < <(jq -r '.hooks | to_entries[] | .value[] | .hooks[] | .command' "$WIRING")
if [ "${#COMMANDS[@]}" -gt 0 ]; then
  pass "${#COMMANDS[@]} hook command(s) registered"
else
  fail "No hook commands registered" ""
  echo ""; echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"; exit 1
fi

# ---- Scenario 2: every command goes through `bash` (BUG-008) ----
# Accepts two forms, both mode-independent: plain `bash <path>` and
# `timeout <N> bash <path>` (the selftest.sh SessionStart entry, FEAT-014 — a
# `timeout`-wrapped invocation of `bash` is still going through the interpreter).
# Anchored regex, NOT a loose substring/glob check: `timeout <N> <path>` (timeout present
# but bash dropped) and bare direct execution must both still be rejected below — a naive
# "contains bash" or "contains timeout" check would silently widen the invariant.
#
# is_bash_wired() is the SAME predicate scenario 2 and scenario 5 both use, so scenario 5's
# proof that it rejects weakened forms is a proof about the actual guard, not a reimplemented
# copy of it that could drift out of sync.
is_bash_wired() {
  [[ "$1" =~ ^bash\  ]] || [[ "$1" =~ ^timeout\ [0-9]+\ bash\  ]]
}

echo "[2] Every registered command is invoked via 'bash <path>' (no exec-bit dependency)"
direct=""
for cmd in "${COMMANDS[@]}"; do
  if is_bash_wired "$cmd"; then
    :                               # invoked through the interpreter — mode-independent
  else
    direct="$direct
    $cmd"
  fi
done
if [ -z "$direct" ]; then
  pass "all ${#COMMANDS[@]} commands invoke their script through bash"
else
  fail "Command(s) rely on the exec bit (direct execution)" "$direct"
fi

# ---- Scenario 3: every referenced script actually exists ----
echo "[3] Every referenced hook script exists in the plugin tree"
missing=""
for cmd in "${COMMANDS[@]}"; do
  # Strip the optional leading `timeout <N> ` prefix, then the leading `bash `, then
  # resolve ${CLAUDE_PLUGIN_ROOT} to the repo root and drop the quoting the wiring uses
  # around it. Finally drop a trailing `;` left over from a chained `; exit 0` suffix
  # (selftest.sh's SessionStart entry, FEAT-014).
  path="$cmd"
  if [[ "$path" =~ ^timeout\ [0-9]+\ (.*)$ ]]; then
    path="${BASH_REMATCH[1]}"
  fi
  path="${path#bash }"
  path="${path//\"/}"
  path="${path/\$\{CLAUDE_PLUGIN_ROOT\}/$ROOT}"
  path="${path%% *}"
  path="${path%;}"
  [ -f "$path" ] || missing="$missing
    $path"
done
if [ -z "$missing" ]; then
  pass "all referenced hook scripts present"
else
  fail "Referenced hook script(s) not found" "$missing"
fi

# ---- Scenario 4: the invariant is load-bearing, not cosmetic ----
# Demonstrates WHY scenario 2 matters: the same script with the exec bit stripped
# runs fine through `bash` and dies with exit 126 when executed directly. Guards
# against someone "simplifying" the wiring back to direct execution.
echo "[4] With mode 0600: 'bash <path>' works, direct execution exits 126"
tmp="$(mktemp -d)"
probe="$tmp/probe.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$probe"
chmod 0600 "$probe"

ec=0; bash "$probe" >/dev/null 2>&1 || ec=$?
if [ "$ec" -eq 0 ]; then
  pass "bash <path> succeeds on a 0600 script"
else
  fail "bash <path> failed on a 0600 script" "ec=$ec"
fi

ec=0; "$probe" >/dev/null 2>&1 || ec=$?
if [ "$ec" -eq 126 ]; then
  pass "direct execution of a 0600 script fails with exit 126 (the failure mode being prevented)"
else
  # Running as root, or an exotic filesystem, can make the exec bit non-binding;
  # the invariant still holds, but this scenario can no longer demonstrate it.
  echo "  SKIP: direct execution returned ec=$ec (exec bit not enforced in this environment)"
fi
rm -rf "$tmp"

# ---- Scenario 5: the invariant survives rolling hooks.json back to a weakened form (PLAN T22
# DoD; verification_report.md W3 — this was previously demonstrated by hand once and never
# encoded, so a future change could silently re-loosen scenario 2's regex with nothing to catch
# it) ----
# Runs the SAME is_bash_wired() predicate scenario 2 uses, against synthetic copies of the
# command array where a `jq` transform mechanically reproduces each named weakened form —
# rather than hand-typed decoy strings — so this scenario is a regression test of hooks.json
# read through the real check, not a check of a reimplemented parser.
echo "[5] Weakened wiring forms named in the DoD are rejected by the same check"

check_commands_from() {
  # Prints (possibly empty) newline-joined list of commands from <file> that
  # is_bash_wired() rejects — same predicate, same jq extraction as scenarios 1/2.
  local file="$1" cmd bad=""
  local -a cmds
  mapfile -t cmds < <(jq -r '.hooks | to_entries[] | .value[] | .hooks[] | .command' "$file")
  for cmd in "${cmds[@]}"; do
    is_bash_wired "$cmd" || bad="$bad
$cmd"
  done
  printf '%s' "$bad"
}

# [5a] Roll back every "bash <path>" entry to bare direct execution (drop the "bash " prefix).
mutant_direct="$(mktemp)"
jq '(.hooks[][].hooks[].command) |= sub("^bash "; "")' "$WIRING" > "$mutant_direct"
bad_direct="$(check_commands_from "$mutant_direct")"
if [ -n "$bad_direct" ]; then
  pass "[5a] hooks.json rolled back to bare direct execution (no 'bash ' prefix) is rejected"
else
  fail "[5a] Direct-execution rollback was NOT flagged" "$mutant_direct"
fi
rm -f "$mutant_direct"

# [5b] Roll back the "timeout <N> bash <path>" entry to "timeout <N> <path>" (bash dropped,
# timeout kept) — the specific form scenario 2's anchored regex exists to distinguish from a
# loose "contains timeout" check.
mutant_timeout="$(mktemp)"
jq '(.hooks[][].hooks[].command) |= sub("timeout (?<n>[0-9]+) bash "; "timeout \(.n) ")' \
  "$WIRING" > "$mutant_timeout" 2>/dev/null
# Verify the transform actually reproduced the target form (a "timeout N bash " command was
# present AND got rewritten) before trusting the mutant as a real red case.
if grep -q '"timeout [0-9]\+ bash ' "$WIRING" && ! grep -q '"timeout [0-9]\+ bash ' "$mutant_timeout"; then
  bad_timeout="$(check_commands_from "$mutant_timeout")"
  if [ -n "$bad_timeout" ]; then
    pass "[5b] hooks.json rolled back to 'timeout <N> <path>' (bash dropped) is rejected"
  else
    fail "[5b] 'timeout <N> <path>' rollback was NOT flagged" "$mutant_timeout"
  fi
else
  fail "[5b] mutant setup failed to reproduce 'timeout <N> <path>' without bash" "$(cat "$mutant_timeout" 2>/dev/null)"
fi
rm -f "$mutant_timeout"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "ALL PASSED"
  exit 0
else
  exit 1
fi
