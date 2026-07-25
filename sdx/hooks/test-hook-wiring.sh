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
echo "[2] Every registered command is invoked via 'bash <path>' (no exec-bit dependency)"
direct=""
for cmd in "${COMMANDS[@]}"; do
  case "$cmd" in
    bash\ *) ;;                      # invoked through the interpreter — mode-independent
    *) direct="$direct
    $cmd" ;;
  esac
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
  # Strip the leading `bash `, then resolve ${CLAUDE_PLUGIN_ROOT} to the repo root
  # and drop the quoting the wiring uses around it.
  path="${cmd#bash }"
  path="${path//\"/}"
  path="${path/\$\{CLAUDE_PLUGIN_ROOT\}/$ROOT}"
  path="${path%% *}"
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

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "ALL PASSED"
  exit 0
else
  exit 1
fi
