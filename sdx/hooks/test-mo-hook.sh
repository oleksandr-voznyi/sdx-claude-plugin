#!/usr/bin/env bash
# Tests for sdx/hooks/mo-hook.sh — PreToolUse wrapper over the vendored sim-kit hook (FEAT-015,
# REQ-MO-HOOK-1..10). The wrapper is the plugin's own code; sdx/mo/devagent_hook.py is vendored
# (read-only for this suite: the real hook runs ONLY from a copy inside a scratch tree, so no run
# can leave __pycache__ in the checkout — scenario [11] asserts it).
#
# Scenarios:
#  [1]  no .mesh/endpoint.yaml: silence, python/jq not touched (incl. PATH without jq, failing python3 stub)
#  [2]  on_write mode is read like the hook does (13 fixtures + parity with the real hook when python3 exists)
#  [3]  cannot-check matrix (no python3 / no hook file / no jq / garbage stdin / rc 1 / rc 127 / killed) x {notice, deny}
#  [4]  python3 present, PyYAML absent (real hook, blocked yaml): delegated policy
#  [5]  hook rc 2 -> JSON deny with the hook's stderr as reason, exit 0, no duplicate on stderr
#  [6]  hook rc 0 (stderr passed through once) + stdin byte-for-byte (200 KB, multi-line) + argv/env
#  [7]  mailbox guard for Write-family tools (+ controls that are NOT the guard: named boundary)
#  [8]  real vendored hook (needs python3 + PyYAML, else INFO-skip): deny/notice/outside/Bash/lease
#  [9]  no __pycache__ after real runs (scenarios 4 and 8), by substance
#  [10] scenarios 3-8 repeated in a project without .claude/ (not a VCS repo) and in a repo on "main"
#  [11] the checkout sdx/mo/ is untouched (no __pycache__)
#  [12] portability: forbidden constructs absent from mo-hook.sh; red side on a mutant that has one
#  [13] mutation runs (copies of the wrapper in a temp dir, anchored by "# MO-*" tags; every mutant must
#       differ from the original, and the targeted scenario must go red on it)
# Static prose invariants of the delivery live in test-mo-prose.sh, not here.
# MO_HOOK_UNDER_TEST overrides the wrapper path (used to show the whole suite red without an implementation).
# Environment without python3/PyYAML: scenarios 4, 8, 9 and the parity part of [2] are INFO-skipped, not PASS.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ORIG_HOOK="${MO_HOOK_UNDER_TEST:-$SCRIPT_DIR/mo-hook.sh}"
HOOK="$ORIG_HOOK"
BASH_BIN="$(command -v bash)"
REAL_JQ="$(command -v jq || true)"
REAL_PY="$(command -v python3 || true)"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
info() { echo "  INFO: $1"; }

echo "=== test-mo-hook.sh ==="
echo ""

if [ -z "$REAL_JQ" ]; then
  echo "jq is required to run this suite (assertions parse JSON)"; exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FXN=0
HAVE_PY=0; HAVE_YAML=0
if [ -n "$REAL_PY" ]; then
  HAVE_PY=1
  PYTHONDONTWRITEBYTECODE=1 "$REAL_PY" -c 'import yaml' >/dev/null 2>&1 && HAVE_YAML=1
fi
REAL_FX=""        # fixtures where the REAL hook ran (checked by [9])
PROJ_KIND=plain   # plain | repo
LBL=""

# ---------------------------------------------------------------- fixture helpers
# new_fx: fresh scratch tree. $fx/proj = project, $fx/root = fake plugin root, $fx/bin = isolated PATH.
new_fx() {
  FXN=$((FXN + 1)); fx="$TMP/fx$FXN"
  mkdir -p "$fx/bin" "$fx/root/sdx/hooks" "$fx/root/sdx/mo" "$fx/proj" "$fx/proj/src"
  if [ "$PROJ_KIND" = repo ] && command -v git >/dev/null 2>&1; then
    git init -q "$fx/proj" >/dev/null 2>&1
    git -C "$fx/proj" symbolic-ref HEAD refs/heads/main >/dev/null 2>&1
  fi
}
# bin_set <py: none|stub|real> <jq: yes|no>
bin_set() {
  local t src
  rm -f "$fx/bin/"*
  for t in bash cat; do ln -s "$(command -v "$t")" "$fx/bin/$t"; done
  [ "$2" = yes ] && ln -s "$REAL_JQ" "$fx/bin/jq"
  case "$1" in
    stub)
      cat > "$fx/bin/python3" <<STUB
#!$BASH_BIN
# stub python3: records what it was given; behaviour via STUB_RC / STUB_ERR / STUB_KILL
{ echo "ARGV1=\${1-}"; echo "PDWB=\${PYTHONDONTWRITEBYTECODE-unset}"; echo "MED=\${MESH_ENDPOINT_DIR-unset}"; echo "CPD=\${CLAUDE_PROJECT_DIR-unset}"; } > "\$STUB_LOG.meta"
cat > "\$STUB_LOG.stdin"
[ -n "\${STUB_ERR-}" ] && printf '%s' "\$STUB_ERR" >&2
[ "\${STUB_KILL-}" = 1 ] && kill -9 \$\$
exit \${STUB_RC:-0}
STUB
      chmod +x "$fx/bin/python3" ;;
    real) src="$REAL_PY"; ln -s "$src" "$fx/bin/python3" ;;
  esac
}
hook_file_stub() { : > "$fx/root/sdx/mo/devagent_hook.py"; }
hook_file_real() {
  cp "$ROOT/sdx/mo/devagent_hook.py" "$ROOT/sdx/mo/mesh_endpoint.py" "$fx/root/sdx/mo/"
  REAL_FX="$REAL_FX $fx"
}
# ep <text>: write .mesh/endpoint.yaml
ep() { mkdir -p "$fx/proj/.mesh"; printf '%s\n' "$1" > "$fx/proj/.mesh/endpoint.yaml"; }
# block_yaml: a yaml module that fails to import (python3 present, PyYAML "absent")
block_yaml() { mkdir -p "$fx/stubyaml"; printf 'raise ImportError("blocked for test")\n' > "$fx/stubyaml/yaml.py"; }

# run_hook <stdin-text>: runs $HOOK in isolation. Results: RC, OUT, ERR. Env knobs: RUN_CWD, NO_PROJ_VAR, EXTRA_PP.
run_hook() {
  rm -f "$fx/stub.meta" "$fx/stub.stdin"
  ( cd "${RUN_CWD:-$fx/proj}" || exit 99
    export PATH="$fx/bin" CLAUDE_PLUGIN_ROOT="$fx/root" STUB_LOG="$fx/stub"
    [ -n "${EXTRA_PP:-}" ] && export PYTHONPATH="$EXTRA_PP"
    if [ "${NO_PROJ_VAR:-}" = 1 ]; then unset CLAUDE_PROJECT_DIR; else export CLAUDE_PROJECT_DIR="$fx/proj"; fi
    exec "$BASH_BIN" "$HOOK" <<<"$1" >"$fx/out" 2>"$fx/err" )
  RC=$?
  OUT="$(cat "$fx/out")"; ERR="$(cat "$fx/err")"
}
stub_ran() { [ -f "$fx/stub.meta" ]; }
is_json_deny() { printf '%s' "$OUT" | jq -e '.hookSpecificOutput.hookEventName=="PreToolUse" and .hookSpecificOutput.permissionDecision=="deny"' >/dev/null 2>&1; }
one_line() { [ -n "$1" ] && [ "$(printf '%s\n' "$1" | wc -l | tr -d ' ')" = 1 ]; }
reason() { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason' 2>/dev/null; }

mk_bash()  { jq -nc --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c},cwd:"/",session_id:"s1"}'; }
mk_write() { # tool path cwd
  local key=file_path; [ "$1" = NotebookEdit ] && key=notebook_path
  jq -nc --arg t "$1" --arg p "$2" --arg c "${3:-/}" --arg k "$key" '{tool_name:$t,tool_input:({($k):$p}),cwd:$c,session_id:"s1"}'
}

# expect_notice_line <label>: rc 0, stdout empty, stderr exactly one line
expect_notice_line() {
  if [ "$RC" = 0 ] && [ -z "$OUT" ] && one_line "$ERR"; then pass "$1"
  else fail "$1" "rc=$RC out=[$OUT] err=[$ERR]"; fi
}
# expect_deny_json <label>: rc 0 (NOT 2), stdout valid deny JSON, stderr empty
expect_deny_json() {
  if [ "$RC" = 0 ] && is_json_deny && [ -z "$ERR" ]; then pass "$1"
  else fail "$1" "rc=$RC out=[$OUT] err=[$ERR]"; fi
}
expect_silent() {
  if [ "$RC" = 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; then pass "$1"
  else fail "$1" "rc=$RC out=[$OUT] err=[$ERR]"; fi
}

# ---------------------------------------------------------------- [1]
scen1() {
  echo "[1$LBL] no .mesh/endpoint.yaml: silence; python3 and jq are not touched"
  local ev; ev="$(mk_bash 'ls')"
  # (a) no .mesh at all; no jq on PATH; python3 stub records a marker and fails
  new_fx; bin_set stub no; hook_file_stub
  STUB_RC=1 STUB_ERR="boom" run_hook "$ev"
  if [ "$RC" = 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ] && ! stub_ran; then pass "[1a$LBL] no .mesh, no jq, failing python3: silent, python3 not started"
  else fail "[1a$LBL] no .mesh" "rc=$RC out=[$OUT] err=[$ERR] stub_ran=$(stub_ran && echo yes || echo no)"; fi
  # (b) .mesh/ exists but without endpoint.yaml
  new_fx; bin_set stub no; hook_file_stub; mkdir -p "$fx/proj/.mesh/outbox"
  STUB_RC=1 STUB_ERR="boom" run_hook "$ev"
  if [ "$RC" = 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ] && ! stub_ran; then pass "[1b$LBL] .mesh/ without endpoint.yaml: silent, python3 not started"
  else fail "[1b$LBL] .mesh/ w/o endpoint.yaml" "rc=$RC out=[$OUT] err=[$ERR]"; fi
  # (c) CLAUDE_PROJECT_DIR unset -> project is the hook's cwd; no file there -> silent
  new_fx; bin_set stub no; hook_file_stub
  NO_PROJ_VAR=1 STUB_RC=1 run_hook "$ev"
  if [ "$RC" = 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ] && ! stub_ran; then pass "[1c$LBL] no CLAUDE_PROJECT_DIR, empty cwd: silent"
  else fail "[1c$LBL] no CLAUDE_PROJECT_DIR" "rc=$RC out=[$OUT] err=[$ERR]"; fi
  # (d) CLAUDE_PROJECT_DIR unset, endpoint.yaml in cwd -> active ("." fallback), no python3 -> deny JSON
  new_fx; bin_set none yes; hook_file_stub; ep 'on_write: deny'
  NO_PROJ_VAR=1 run_hook "$ev"
  expect_deny_json "[1d$LBL] no CLAUDE_PROJECT_DIR, endpoint.yaml in cwd: active (deny mode, no python3 -> JSON deny)"
  # (e) unreadable project dir argument does not crash
  new_fx; bin_set stub yes; hook_file_stub
  rm -rf "$fx/proj"
  RUN_CWD="$fx" STUB_RC=1 run_hook "$ev"
  expect_silent "[1e$LBL] project directory absent: silent exit 0"
}

# ---------------------------------------------------------------- [2]
# fixture table: name|content|expected (printf %b is applied to content)
MODE_FIXTURES='notice|on_write: notice|notice
deny|on_write: deny|deny
DENY (case)|on_write: DENY|deny
single quoted|on_write: '"'"'deny'"'"'|deny
double quoted|on_write: "deny"|deny
trailing comment|on_write: deny  # c|deny
key absent|instance: x|notice
commented out|# on_write: deny|notice
indented|  on_write: deny|deny
allow (any other value)|on_write: allow|notice
two keys deny first|on_write: deny\non_write: notice|deny
two keys notice first|on_write: notice\non_write: deny|notice
value on next line|on_write:\n  deny|deny
longer word|on_write: denyx|notice'
scen2() {
  echo "[2$LBL] on_write mode is read as the sim-kit hook reads it (observed via the no-python3 branch)"
  local line name content want got n=0
  while IFS= read -r line; do
    name="${line%%|*}"; rest="${line#*|}"; content="${rest%|*}"; want="${rest##*|}"
    n=$((n + 1))
    new_fx; bin_set none yes; hook_file_stub
    mkdir -p "$fx/proj/.mesh"; printf '%b\n' "$content" > "$fx/proj/.mesh/endpoint.yaml"
    run_hook "$(mk_bash 'ls')"
    if is_json_deny && [ "$RC" = 0 ]; then got=deny; elif [ "$RC" = 0 ] && one_line "$ERR" && [ -z "$OUT" ]; then got=notice; else got="other(rc=$RC)"; fi
    if [ "$got" = "$want" ]; then pass "[2.$n$LBL] $name -> $want"; else fail "[2.$n$LBL] $name" "want $want got $got"; fi
  done <<<"$MODE_FIXTURES"
  # unreadable file (chmod 000) -> notice (SKIP as root: root reads anything)
  if [ "$(id -u)" = 0 ]; then
    info "[2.unreadable$LBL] SKIP: running as root, chmod 000 does not stop reads"
  else
    new_fx; bin_set none yes; hook_file_stub; ep 'on_write: deny'; chmod 000 "$fx/proj/.mesh/endpoint.yaml"
    run_hook "$(mk_bash 'ls')"
    if [ "$RC" = 0 ] && [ -z "$OUT" ] && one_line "$ERR"; then pass "[2.unreadable$LBL] unreadable endpoint.yaml -> notice"
    else fail "[2.unreadable$LBL] unreadable endpoint.yaml" "rc=$RC out=[$OUT] err=[$ERR]"; fi
    chmod 600 "$fx/proj/.mesh/endpoint.yaml"
  fi
  # parity with the real hook: PyYAML blocked, so the hook decides purely by its own mode regex (rc 2 = deny)
  if [ "$HAVE_PY" = 1 ]; then
    n=0
    while IFS= read -r line; do
      name="${line%%|*}"; rest="${line#*|}"; content="${rest%|*}"; want="${rest##*|}"
      n=$((n + 1))
      new_fx; bin_set real yes; hook_file_real; block_yaml
      mkdir -p "$fx/proj/.mesh"; printf '%b\n' "$content" > "$fx/proj/.mesh/endpoint.yaml"
      ( cd "$fx/proj"; PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$fx/stubyaml" CLAUDE_PROJECT_DIR="$fx/proj" \
          "$REAL_PY" "$fx/root/sdx/mo/devagent_hook.py" <<<"$(mk_bash ls)" >/dev/null 2>&1 )
      local drc=$?
      if [ "$drc" = 2 ]; then got=deny; else got=notice; fi
      if [ "$got" = "$want" ]; then pass "[2p.$n$LBL] parity with real hook: $name -> $want"
      else fail "[2p.$n$LBL] parity with real hook: $name" "table says $want, real hook says $got (rc=$drc)"; fi
    done <<<"$MODE_FIXTURES"
    # known divergence (named in DESIGN): not PASS, only visible
    new_fx; bin_set none yes; hook_file_stub; mkdir -p "$fx/proj/.mesh"; printf 'on_write: deny\xd0\xb9\n' > "$fx/proj/.mesh/endpoint.yaml"
    run_hook "$(mk_bash ls)"
    info "[2.known$LBL] 'denyй' (non-ASCII tail): wrapper mode is locale dependent (decision: $(is_json_deny && echo deny || echo notice)); Python reads it as not-deny — named divergence, not a pass"
  else
    info "[2p$LBL] no python3: parity part SKIPPED (not a pass)"
  fi
}

# ---------------------------------------------------------------- [3]
# one cell of the matrix: <cond> <mode>
cell3() {
  local cond="$1" mode="$2" ev; ev="$(mk_bash 'ls -la')"
  new_fx; ep "on_write: $mode"
  case "$cond" in
    "no python3")     bin_set none yes; hook_file_stub; run_hook "$ev" ;;
    "no hook file")   bin_set stub yes; run_hook "$ev" ;;
    "no jq")          bin_set stub no; hook_file_stub; run_hook "$ev" ;;
    "garbage stdin")  bin_set stub yes; hook_file_stub; run_hook 'this is {not json' ;;
    "hook rc 1")      bin_set stub yes; hook_file_stub; STUB_RC=1 STUB_ERR="Traceback line" run_hook "$ev" ;;
    "hook rc 127")    bin_set stub yes; hook_file_stub; STUB_RC=127 run_hook "$ev" ;;
    "hook killed")    bin_set stub yes; hook_file_stub; STUB_KILL=1 run_hook "$ev" ;;
  esac
  if [ "$mode" = notice ]; then expect_notice_line "[3$LBL] $cond / notice: one stderr line, exit 0, stdout empty"
  else expect_deny_json "[3$LBL] $cond / deny: JSON deny on stdout, exit 0 (not 2)"; fi
}
scen3() {
  echo "[3$LBL] cannot check the target: policy by mode (notice fail-open, deny fail-closed)"
  local c m
  for c in "no python3" "no hook file" "no jq" "garbage stdin" "hook rc 1" "hook rc 127" "hook killed"; do
    for m in notice deny; do cell3 "$c" "$m"; done
  done
  # the static no-jq literal is itself valid JSON naming the cause
  new_fx; bin_set stub no; hook_file_stub; ep 'on_write: deny'; run_hook "$(mk_bash ls)"
  if is_json_deny && printf '%s' "$(reason)" | grep -q 'jq'; then pass "[3j$LBL] no-jq deny literal is valid JSON and names jq"
  else fail "[3j$LBL] no-jq literal" "out=[$OUT]"; fi
}

# ---------------------------------------------------------------- [4]
scen4() {
  echo "[4$LBL] python3 present, PyYAML absent: delegated to the hook (real vendored copy)"
  if [ "$HAVE_PY" != 1 ]; then info "[4$LBL] no python3: SKIPPED (not a pass)"; return; fi
  local m
  for m in notice deny; do
    new_fx; bin_set real yes; hook_file_real; block_yaml; ep "on_write: $m"
    EXTRA_PP="$fx/stubyaml" run_hook "$(mk_bash 'ls')"
    if [ "$m" = notice ]; then
      if [ "$RC" = 0 ] && [ -z "$OUT" ] && one_line "$ERR" && printf '%s' "$ERR" | grep -q 'PyYAML'; then pass "[4$LBL] notice: exit 0, silent stdout, one stderr line naming PyYAML"
      else fail "[4$LBL] notice" "rc=$RC out=[$OUT] err=[$ERR]"; fi
    else
      if [ "$RC" = 0 ] && is_json_deny && [ -z "$ERR" ] && printf '%s' "$(reason)" | grep -q 'PyYAML'; then pass "[4$LBL] deny: JSON deny whose reason names PyYAML, exit 0"
      else fail "[4$LBL] deny" "rc=$RC out=[$OUT] err=[$ERR]"; fi
    fi
  done
}

# ---------------------------------------------------------------- [5]
scen5() {
  echo "[5$LBL] hook rc 2 -> JSON deny; reason = hook stderr; no duplicate"
  local m want
  want='DENY [MO-exec-paths]: запись "под кавычками" \ обратный слэш
вторая строка: 100% {json}'
  for m in notice deny; do
    new_fx; bin_set stub yes; hook_file_stub; ep "on_write: $m"
    STUB_RC=2 STUB_ERR="$want" run_hook "$(mk_bash 'cp a /dep/a')"
    if [ "$RC" = 0 ] && is_json_deny && [ -z "$ERR" ] && [ "$(reason)" = "$want" ]; then pass "[5$LBL] $m: valid JSON deny, reason equals hook stderr byte-for-byte, exit 0, stderr empty"
    else fail "[5$LBL] $m" "rc=$RC out=[$OUT] err=[$ERR] reason=[$(reason)]"; fi
  done
  new_fx; bin_set stub yes; hook_file_stub; ep 'on_write: notice'
  STUB_RC=2 run_hook "$(mk_bash 'x')"
  if [ "$RC" = 0 ] && is_json_deny && [ -n "$(reason)" ]; then pass "[5e$LBL] rc 2 with empty stderr: block kept, placeholder reason"
  else fail "[5e$LBL] rc 2 empty stderr" "rc=$RC out=[$OUT] err=[$ERR]"; fi
}

# ---------------------------------------------------------------- [6]
scen6() {
  echo "[6$LBL] hook rc 0: pass-through, stdin delivered intact, argv/env"
  local ev big
  new_fx; bin_set stub yes; hook_file_stub; ep 'on_write: notice'
  STUB_RC=0 STUB_ERR="devagent_hook: заметка" run_hook "$(mk_bash 'ls')"
  if [ "$RC" = 0 ] && [ -z "$OUT" ] && [ "$ERR" = "devagent_hook: заметка" ] && one_line "$ERR"; then pass "[6a$LBL] rc 0 + stderr line: passed through exactly once, stdout empty"
  else fail "[6a$LBL] rc 0 with stderr" "rc=$RC out=[$OUT] err=[$ERR]"; fi
  STUB_RC=0 run_hook "$(mk_bash 'ls')"
  expect_silent "[6b$LBL] rc 0 without stderr: fully silent"
  # stdin byte-for-byte: multi-line content, and >=200 KB (catches truncation / SIGPIPE)
  head -c 200000 /dev/zero | tr '\0' 'a' > "$TMP/big.txt"; printf '\nline2 "q" \\ ключ\n' >> "$TMP/big.txt"
  ev="$(jq -nc --rawfile c "$TMP/big.txt" '{tool_name:"Write",tool_input:{file_path:"/x/y",content:$c},cwd:"/",session_id:"s1"}')"
  STUB_RC=0 MESH_ENDPOINT_DIR=/elsewhere run_hook "$ev"
  printf '%s\n' "$ev" > "$fx/expected.stdin"
  if stub_ran && cmp -s "$fx/expected.stdin" "$fx/stub.stdin"; then pass "[6c$LBL] 200 KB multi-line stdin reaches the hook byte-for-byte"
  else fail "[6c$LBL] stdin delivery" "stub stdin differs from input ($(wc -c < "$fx/stub.stdin" 2>/dev/null) bytes)"; fi
  local a1 pd me cp
  a1="$(sed -n 's/^ARGV1=//p' "$fx/stub.meta")"; pd="$(sed -n 's/^PDWB=//p' "$fx/stub.meta")"
  me="$(sed -n 's/^MED=//p' "$fx/stub.meta")"; cp="$(sed -n 's/^CPD=//p' "$fx/stub.meta")"
  [ "$a1" = "$fx/root/sdx/mo/devagent_hook.py" ] && pass "[6d$LBL] argv[1] = \$CLAUDE_PLUGIN_ROOT/sdx/mo/devagent_hook.py" || fail "[6d$LBL] argv[1]" "[$a1]"
  [ "$pd" = 1 ] && pass "[6e$LBL] PYTHONDONTWRITEBYTECODE=1 is set for the hook" || fail "[6e$LBL] PYTHONDONTWRITEBYTECODE" "[$pd]"
  [ "$me" = "$fx/proj" ] && pass "[6f$LBL] MESH_ENDPOINT_DIR = project dir (a foreign inherited value is overridden)" || fail "[6f$LBL] MESH_ENDPOINT_DIR" "[$me]"
  [ "$cp" = "$fx/proj" ] && pass "[6g$LBL] CLAUDE_PROJECT_DIR passed on" || fail "[6g$LBL] CLAUDE_PROJECT_DIR" "[$cp]"
}

# ---------------------------------------------------------------- [7]
scen7() {
  echo "[7$LBL] mailbox guard: Write-family tools cannot write .mesh/endpoint.yaml / cursors.json"
  local tool m f form p cwd ev n=0 bad=0 pp
  for m in notice deny; do
    new_fx; bin_set stub yes; hook_file_stub; ep "on_write: $m"
    pp="$fx/proj"
    for tool in Write Edit MultiEdit NotebookEdit; do
      for f in endpoint.yaml cursors.json; do
        for form in abs rel dots dslash updir; do
          cwd="$pp"
          case "$form" in
            abs)    p="$pp/.mesh/$f" ;;
            rel)    p=".mesh/$f" ;;
            dots)   p="$pp/./.mesh/../.mesh/$f" ;;
            dslash) p="$pp//.mesh/$f" ;;
            updir)  p="../.mesh/$f"; cwd="$pp/src" ;;
          esac
          n=$((n + 1))
          run_hook "$(mk_write "$tool" "$p" "$cwd")"
          if [ "$RC" = 0 ] && is_json_deny && [ -z "$ERR" ] && ! stub_ran; then :
          else bad=$((bad + 1)); fail "[7$LBL] $m $tool $f ($form)" "rc=$RC out=[$OUT] err=[$ERR] stub_ran=$(stub_ran && echo yes || echo no)"; fi
        done
      done
    done
    [ "$bad" = 0 ] && pass "[7a$LBL] $m: all $n guarded combinations (4 tools x 2 files x 5 path forms) -> JSON deny, hook not started" ; bad=0; n=0
  done
  # without jq the guard cannot read the input: deny -> literal JSON deny, notice -> one line (SPEC boundary)
  new_fx; bin_set stub no; hook_file_stub; ep 'on_write: deny'; run_hook "$(mk_write Write "$fx/proj/.mesh/endpoint.yaml")"
  expect_deny_json "[7b$LBL] no jq / deny: literal JSON deny"
  new_fx; bin_set stub no; hook_file_stub; ep 'on_write: notice'; run_hook "$(mk_write Write "$fx/proj/.mesh/endpoint.yaml")"
  expect_notice_line "[7c$LBL] no jq / notice: one stderr line (boundary)"
  # controls: NOT blocked by the guard (the hook is started, nothing is denied) — a named boundary, not a PASS of the guard
  new_fx; bin_set stub yes; hook_file_stub; ep 'on_write: deny'; pp="$fx/proj"
  local c
  for c in "Write|$pp/.mesh/outbox/x.json" "Write|$pp/.mesh/hook-state.json" "Write|$pp/src/endpoint.yaml" \
           "Write|$pp/.mesh/endpoint.yaml.bak" "Edit|$pp/.mesh/inbox/l/000001.json" "Read|$pp/.mesh/endpoint.yaml"; do
    run_hook "$(mk_write "${c%%|*}" "${c#*|}" "$pp")"
    if [ "$RC" = 0 ] && [ -z "$OUT" ] && stub_ran; then info "[7d$LBL] boundary (not the guard): ${c%%|*} ${c#*|} -> passed to the hook, not blocked by the wrapper"
    else fail "[7d$LBL] control ${c%%|*} ${c#*|}" "rc=$RC out=[$OUT] err=[$ERR] stub_ran=$(stub_ran && echo yes || echo no)"; fi
  done
  run_hook "$(mk_bash "cat $pp/.mesh/endpoint.yaml; echo x > $pp/.mesh/endpoint.yaml")"
  if [ "$RC" = 0 ] && [ -z "$OUT" ] && stub_ran; then info "[7e$LBL] boundary (REQ-MO-HOOK-8): Bash text naming endpoint.yaml is not guarded — hook started"
  else fail "[7e$LBL] Bash control" "rc=$RC out=[$OUT] err=[$ERR]"; fi
}

# ---------------------------------------------------------------- [8]
# setup_real <mode>: real hook copy, exec_paths=[$fx/dep], no lease
setup_real() {
  new_fx; bin_set real yes; hook_file_real
  mkdir -p "$fx/dep" "$fx/other"; dep="$(cd "$fx/dep" && pwd -P)"
  ep "endpoint_id: e-dev-test
node_id: n-0123456789ab
node_path: /nonexistent
link: test~dev
instance: inst1
exec_paths: [$dep]
on_write: $1"
}
scen8() {
  echo "[8$LBL] real vendored hook (copy): exec_paths write without / with a lease"
  if [ "$HAVE_PY" != 1 ] || [ "$HAVE_YAML" != 1 ]; then info "[8$LBL] no python3 or no PyYAML: SKIPPED (not a pass)"; return; fi
  local dep
  setup_real deny; run_hook "$(jq -nc --arg p "$dep/a" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"},cwd:"/",session_id:"s8"}')"
  if [ "$RC" = 0 ] && is_json_deny && [ -z "$ERR" ] && printf '%s' "$(reason)" | grep -q 'DENY \[MO-exec-paths\]'; then pass "[8a$LBL] deny: Write into exec_paths -> JSON deny with DENY [MO-exec-paths], exit 0, stderr empty"
  else fail "[8a$LBL] deny Write" "rc=$RC out=[$OUT] err=[$ERR]"; fi
  setup_real notice; run_hook "$(jq -nc --arg p "$dep/a" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"},cwd:"/",session_id:"s8"}')"
  expect_silent "[8b$LBL] notice: same write -> exit 0, nothing on stdout/stderr"
  setup_real deny; run_hook "$(jq -nc --arg p "$fx/other/a" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"},cwd:"/",session_id:"s8"}')"
  expect_silent "[8c$LBL] deny: Write outside exec_paths -> silent"
  setup_real deny; run_hook "$(jq -nc --arg c "touch $dep/x" '{tool_name:"Bash",tool_input:{command:$c},cwd:"/",session_id:"s8"}')"
  if [ "$RC" = 0 ] && is_json_deny && printf '%s' "$(reason)" | grep -q 'DENY \[MO-exec-paths\]'; then pass "[8g$LBL] deny: Bash touch in exec_paths -> JSON deny"
  else fail "[8g$LBL] deny Bash" "rc=$RC out=[$OUT] err=[$ERR]"; fi
  # (d) lease: a lease.granted envelope, built with the vendored ehash, in the project's inbox
  setup_real deny
  mkdir -p "$fx/proj/.mesh/inbox/test~dev"
  PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$fx/root/sdx/mo" "$REAL_PY" - "$fx/proj/.mesh/inbox/test~dev/000001.json" <<'PY'
import sys, json, datetime as dt
import mesh_endpoint as me
n = dt.datetime.now(dt.timezone.utc)
e = {"v": 1, "msg_id": "M-lease00001", "link": "test~dev", "seq": 1, "prev": "0" * 64,
     "from": {"node": "n-0123456789ab", "path": None, "session": None, "role": "node"},
     "to": {"node": "e-dev-test", "path": None}, "kind": "lease.granted", "correlation_id": None, "in_reply_to": None,
     "created": n.isoformat(), "expires": (n + dt.timedelta(hours=72)).isoformat(),
     "body": {"instance": "inst1", "run_id": "r1", "holder": "mo", "expires": (n + dt.timedelta(hours=1)).isoformat()},
     "body_sha256": "x", "authority": None, "data_only": True}
e["hash"] = me.ehash(e)
open(sys.argv[1], "w").write(me.canon(e) + "\n")
PY
  run_hook "$(jq -nc --arg p "$dep/a" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"},cwd:"/",session_id:"s8"}')"
  expect_silent "[8d$LBL] deny + lease.granted in inbox: Write into exec_paths passes (red side = [8a], the same write without a lease)"
}

# ---------------------------------------------------------------- [9]
scen9() {
  echo "[9] no __pycache__ after real hook runs (by substance, not by env)"
  local f bad=0 seen=0
  for f in $REAL_FX; do
    seen=$((seen + 1))
    if [ -e "$f/root/sdx/mo/__pycache__" ]; then bad=$((bad + 1)); fail "[9] $f" "__pycache__ appeared in the hook directory"; fi
  done
  if [ "$seen" = 0 ]; then info "[9] no real hook runs happened (no python3/PyYAML): SKIPPED (not a pass)"
  elif [ "$bad" = 0 ]; then pass "[9] $seen real-hook fixtures: no __pycache__ in any hook directory"; fi
}

# ---------------------------------------------------------------- core run (3..8), optionally per project kind
run_core() {
  scen3; scen4; scen5; scen6; scen7; scen8
}

# ---------------------------------------------------------------- main run
scen1
scen2
PROJ_KIND=plain; LBL=""
run_core
scen9
echo "[10] scenarios 3-8 in a project without .claude/ (not a VCS repo): ran above (fixtures have no .claude/)"
if command -v git >/dev/null 2>&1; then
  echo "[10] ... and in a VCS repo on main"
  PROJ_KIND=repo; LBL=" repo"
  run_core
  scen9
else
  info "[10] no git: repo variant SKIPPED"
fi
PROJ_KIND=plain; LBL=""

echo "[11] the checkout sdx/mo/ is untouched"
if [ -d "$ROOT/sdx/mo" ]; then
  [ ! -e "$ROOT/sdx/mo/__pycache__" ] && pass "[11] no __pycache__ in $ROOT/sdx/mo" || fail "[11] checkout" "__pycache__ present in sdx/mo/"
else info "[11] sdx/mo/ does not exist yet: SKIPPED"; fi

# ---------------------------------------------------------------- [12] portability
echo "[12] portability (BUG-010): forbidden constructs in the wrapper"
FORBID='tim''eout|map''file|declare -''A|[$]\{[a-zA-Z_]+,,\}|%''N|readlink -''f|real''path|resolve-session|git '
if [ -f "$ORIG_HOOK" ]; then
  if grep -nE "$FORBID" "$ORIG_HOOK" >/dev/null 2>&1; then fail "[12a] portability" "forbidden construct: $(grep -nE "$FORBID" "$ORIG_HOOK" | head -3)"
  else pass "[12a] mo-hook.sh has no GNU-only/bash4-only constructs and no VCS/branch dependency"; fi
  cp "$ORIG_HOOK" "$TMP/port-mut.sh"; printf 'ma''pfile -t xs <<<""\n' >> "$TMP/port-mut.sh"
  if ! cmp -s "$ORIG_HOOK" "$TMP/port-mut.sh" && grep -qE "$FORBID" "$TMP/port-mut.sh"; then pass "[12b] red side: the same grep flags a mutant with a bash4 construct"
  else fail "[12b] red side of the portability grep" "mutant not flagged"; fi
else
  fail "[12] portability" "$ORIG_HOOK does not exist"
fi

# ---------------------------------------------------------------- [13] mutation runs
echo "[13] mutation runs: each mutant must differ from the original and turn its scenario red"
MUTDIR="$TMP/mut"; mkdir -p "$MUTDIR"
# mutate <name> <sed-expr> <scenario-calls...>: counters are saved around the run; mutant output is kept aside.
mutate() {
  local name="$1" expr="$2" calls="$3" mf p0 f0 d first
  mf="$MUTDIR/$name.sh"
  if [ ! -f "$ORIG_HOOK" ]; then fail "[13] $name" "no wrapper to mutate"; return; fi
  sed "$expr" "$ORIG_HOOK" > "$mf"
  if cmp -s "$ORIG_HOOK" "$mf"; then fail "[13] $name" "mutant is identical to the original (anchor missing?)"; return; fi
  p0=$PASS_COUNT; f0=$FAIL_COUNT
  HOOK="$mf"; REAL_FX=""
  eval "$calls" >"$MUTDIR/$name.out" 2>&1
  HOOK="$ORIG_HOOK"
  d=$((FAIL_COUNT - f0)); PASS_COUNT=$p0; FAIL_COUNT=$f0
  first="$(grep -m1 'FAIL:' "$MUTDIR/$name.out" | cut -c1-110)"
  if [ "$d" -gt 0 ]; then pass "[13] mutant $name -> red ($d failing checks; first: ${first#  FAIL: })"
  else fail "[13] mutant $name" "scenario stayed green on the mutant (the check proves nothing)"; fi
}
mutate EARLY-EXIT   '/# MO-EARLY-EXIT/d' 'scen1'
mutate MODE-REGEX   's|^mode_re=.*# MO-MODE$|mode_re="(^\|"$'"'"'\\n'"'"'")on_write: *([[:alnum:]_]+)"|' 'scen2'
mutate FAIL-OPEN    's|if \[ "\$mode" = deny \]; then   # MO-FAILOPEN|if false; then|' 'scen3'
mutate RC2          's|exit 0   # MO-RC2|exit 2|' 'scen3; scen5'
mutate TRANSLATE    's|^    deny_json .*# MO-TRANSLATE$|    printf "%s\\n" "$err" >\&2; exit 2 ;;|' 'scen5; scen8'
mutate NO-STDIN     's|<<<"\$input")"; rc=\$?|</dev/null)"; rc=$?|' 'scen6'
mutate BYTECODE-ENV 's|PYTHONDONTWRITEBYTECODE=1 CLAUDE_PROJECT_DIR|CLAUDE_PROJECT_DIR|' 'scen6'
mutate BYTECODE-FS  's|PYTHONDONTWRITEBYTECODE=1 CLAUDE_PROJECT_DIR|CLAUDE_PROJECT_DIR|' 'scen8; scen9'
mutate NO-GUARD     '/# MO-GUARD/d' 'scen7'
mutate NO-NORM      's|^  case "\$fp" in /\*) ;; \*) fp=.*# MO-NORM$|  :|' 'scen7'
mutate NO-HOOKFILE  '/# MO-HOOKFILE/d' 'scen3'

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
