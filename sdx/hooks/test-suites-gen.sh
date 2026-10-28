#!/usr/bin/env bash
# Tests for sdx/hooks/suites-gen.sh + sdx/hooks/lib/test-cmd.sh (FEAT-016, REQ-MAND-18..21).
#
# suites-gen.sh [--check] [proj] writes/checks tests/suites.yaml (the node's test declaration, read by the
# meta-orchestrator's dev.py run_suites). lib/test-cmd.sh mirrors the test-command resolution block of
# stop-gate.sh, which is NOT touched: the "twin" scenario (7) runs the real stop-gate.sh on fixtures and
# compares what it executed with what the resolver returns.
#
# Scenarios:
#  (1) budget_min = ceil(SDX_VERIFY_TIMEOUT/60): 180->3, 61->2, 60->1, 1->1, 181->4, junk->3 + stderr
#  (2) byte-for-byte determinism (two directories)
#  (3) idempotence: OK; hand-edited unit.cmd -> DIFFERS (file untouched); `unit: "<cmd>"` form; --check -> ABSENT
#  (4) NOCMD: no command known -> file not created
#  (5) autodetect composer / npm / phpunit and priority (verify-cmd.sh wins)
#  (6) structure: suites root, unit = {cmd, budget_min, selector}, module/regression only as comments
#  (7) twin with the real stop-gate.sh (per command class)
#  (8)(9) dogfood file of this repository + PyYAML oracle (added with the dogfood file)
#  (10) portability (BUG-010)
# SUITES_GEN_ONLY="1 3 P" restricts a run to the named blocks (used by the mutation runs).
set -uo pipefail
unset PYTHONDONTWRITEBYTECODE
unset SDX_VERIFY_TIMEOUT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GEN="${SUITES_GEN_UNDER_TEST:-$SCRIPT_DIR/suites-gen.sh}"
LIB="${SUITES_GEN_LIB_FOR_TEST:-$SCRIPT_DIR/lib}"
GATE="$SCRIPT_DIR/stop-gate.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
info() { echo "  INFO: $1"; }
want() { [ -z "${SUITES_GEN_ONLY:-}" ] && return 0; case " $SUITES_GEN_ONLY " in *" $1 "*) return 0 ;; esac; return 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
NP=0
# newproj: sets P to a fresh empty project directory
newproj() { NP=$((NP + 1)); P="$TMP/p$NP"; mkdir -p "$P"; }
# with_verify: P gets a .claude/sdx/verify-cmd.sh (presence activates it, as in stop-gate)
with_verify() { mkdir -p "$P/.claude/sdx"; printf '#!/usr/bin/env bash\nexit 0\n' > "$P/.claude/sdx/verify-cmd.sh"; }
# gen [args...]: runs the generator; OUT/ERR/RC
gen() {
  OUT="$(bash "$GEN" "$@" 2>"$TMP/err")"; RC=$?; ERR="$(cat "$TMP/err")"
}
first() { printf '%s' "${OUT%%[ $'\n']*}"; }

echo "=== test-suites-gen.sh ==="
echo ""
if [ ! -f "$GEN" ] || [ ! -f "$LIB/test-cmd.sh" ]; then
  fail "[0] files" "suites-gen.sh or lib/test-cmd.sh missing ($GEN, $LIB/test-cmd.sh)"
fi

if want 1 && [ -f "$GEN" ]; then
echo "[1] budget_min = ceil(SDX_VERIFY_TIMEOUT / 60)"
newproj; with_verify
gen "$P"
if [ "$(first)" = CREATED ] && [ "$RC" -eq 0 ] && [ -f "$P/tests/suites.yaml" ]; then pass "[1] 180 -> CREATED, rc 0"
else fail "[1] CREATED" "out=[$OUT] rc=$RC"; fi
if grep -qx '    cmd: bash .claude/sdx/verify-cmd.sh' "$P/tests/suites.yaml" 2>/dev/null; then pass "[1] cmd carries 'bash' and the runner path"
else fail "[1] cmd line" "$(grep -n 'cmd' "$P/tests/suites.yaml" 2>/dev/null | head -2)"; fi
for pair in 180:3 61:2 60:1 1:1 181:4 0:3 -5:3 abc:3 12x:3; do
  t="${pair%%:*}"; want_b="${pair##*:}"
  newproj; with_verify
  OUT="$(SDX_VERIFY_TIMEOUT="$t" bash "$GEN" "$P" 2>"$TMP/err")"; RC=$?; ERR="$(cat "$TMP/err")"
  got="$(grep -m1 '^    budget_min:' "$P/tests/suites.yaml" 2>/dev/null | sed 's/.*: *//')"
  if [ "$got" = "$want_b" ]; then pass "[1] SDX_VERIFY_TIMEOUT=$t -> budget_min $want_b"
  else fail "[1] SDX_VERIFY_TIMEOUT=$t" "budget_min=[$got] want $want_b"; fi
  case "$t" in abc|12x|0|-5)
    if [ -n "$ERR" ]; then pass "[1] invalid '$t' -> note on stderr"; else fail "[1] invalid '$t'" "stderr empty"; fi ;;
  esac
done
fi

if want 2 && [ -f "$GEN" ]; then
echo "[2] byte-for-byte determinism"
newproj; with_verify; A="$P"; newproj; with_verify; B="$P"
bash "$GEN" "$A" >/dev/null 2>&1; bash "$GEN" "$B" >/dev/null 2>&1
if [ -f "$A/tests/suites.yaml" ] && cmp -s "$A/tests/suites.yaml" "$B/tests/suites.yaml"; then pass "[2] two directories -> identical bytes"
else fail "[2] determinism" "files differ or missing"; fi
fi

if want 3 && [ -f "$GEN" ]; then
echo "[3] idempotence and read-back"
newproj; with_verify
gen --check "$P"
if [ "$(first)" = ABSENT ] && [ "$RC" -eq 0 ] && [ ! -e "$P/tests/suites.yaml" ]; then pass "[3] --check without file -> ABSENT, nothing written"
else fail "[3] ABSENT" "out=[$OUT] rc=$RC"; fi
gen "$P"; cp "$P/tests/suites.yaml" "$TMP/before"
gen "$P"
if [ "$(first)" = OK ] && cmp -s "$TMP/before" "$P/tests/suites.yaml"; then pass "[3] second run -> OK, file unchanged"
else fail "[3] OK" "out=[$OUT]"; fi
gen --check "$P"
[ "$(first)" = OK ] && pass "[3] --check on a matching file -> OK" || fail "[3] --check OK" "out=[$OUT]"
sed 's|cmd: bash .claude/sdx/verify-cmd.sh|cmd: make test|' "$P/tests/suites.yaml" > "$TMP/edited"; cp "$TMP/edited" "$P/tests/suites.yaml"
gen "$P"
if [ "$(first)" = DIFFERS ] && cmp -s "$TMP/edited" "$P/tests/suites.yaml" && printf '%s' "$OUT" | grep -q 'make test'; then pass "[3] hand-edited unit.cmd -> DIFFERS naming both sides, file untouched"
else fail "[3] DIFFERS" "out=[$OUT]"; fi
newproj; with_verify; mkdir -p "$P/tests"
printf 'suites:\n  unit: "bash .claude/sdx/verify-cmd.sh"\n' > "$P/tests/suites.yaml"
gen "$P"
[ "$(first)" = OK ] && pass "[3] string form 'unit: \"<cmd>\"' is read -> OK" || fail "[3] string form" "out=[$OUT]"
newproj; with_verify; mkdir -p "$P/tests"; printf 'suites:\n  module:\n    cmd: x\n' > "$P/tests/suites.yaml"
gen "$P"
[ "$(first)" = DIFFERS ] && pass "[3] no unit set -> DIFFERS" || fail "[3] no unit" "out=[$OUT]"
newproj; with_verify; mkdir -p "$P/tests"; printf 'suites: [unclosed\n  a: : b\n' > "$P/tests/suites.yaml"
cp "$P/tests/suites.yaml" "$TMP/bad"; gen "$P"
if [ "$RC" -eq 2 ] && cmp -s "$TMP/bad" "$P/tests/suites.yaml"; then pass "[3] unreadable existing file -> rc 2, file untouched"
else fail "[3] rc 2" "rc=$RC out=[$OUT]"; fi
newproj; with_verify; printf 'x' > "$P/tests"
gen "$P"
[ "$RC" -eq 2 ] && pass "[3] tests is not a directory -> rc 2" || fail "[3] tests not dir" "rc=$RC out=[$OUT]"
gen --bogus "$P"
[ "$RC" -eq 2 ] && pass "[3] unknown option -> rc 2" || fail "[3] unknown option" "rc=$RC"
fi

if want 4 && [ -f "$GEN" ]; then
echo "[4] NOCMD"
newproj
gen "$P"
if [ "$(first)" = NOCMD ] && [ "$RC" -eq 0 ] && [ ! -e "$P/tests" ]; then pass "[4] no command -> NOCMD, nothing created"
else fail "[4] NOCMD" "out=[$OUT] rc=$RC tests=$(ls "$P" 2>&1)"; fi
newproj; printf '{"name":"x"}\n' > "$P/package.json"
gen --check "$P"
[ "$(first)" = NOCMD ] && pass "[4] package.json without \"test\" -> NOCMD (--check too)" || fail "[4] no test script" "out=[$OUT]"
fi

if want 5 && [ -f "$GEN" ]; then
echo "[5] autodetect and priority"
detect() {   # detect <label> <expected cmd>   (project prepared in $P)
  gen "$P"
  got="$(grep -m1 '^    cmd:' "$P/tests/suites.yaml" 2>/dev/null | sed 's/^    cmd: *//')"
  [ "$got" = "$2" ] && pass "[5] $1 -> $2" || fail "[5] $1" "cmd=[$got] out=[$OUT]"
}
newproj; printf '{"scripts":{"test":"jest"}}\n' > "$P/package.json"; detect npm "npm test --silent"
newproj; printf '{"scripts":{"test":"x"}}\n' > "$P/composer.json"; detect composer "composer test"
newproj; touch "$P/phpunit.xml"; detect phpunit "./vendor/bin/phpunit"
newproj; touch "$P/phpunit.xml.dist"; detect "phpunit.xml.dist" "./vendor/bin/phpunit"
newproj; printf '{"scripts":{"test":"x"}}\n' > "$P/composer.json"; printf '{"scripts":{"test":"x"}}\n' > "$P/package.json"; detect "composer over npm" "composer test"
newproj; with_verify; printf '{"scripts":{"test":"x"}}\n' > "$P/composer.json"; printf '{"scripts":{"test":"x"}}\n' > "$P/package.json"; touch "$P/phpunit.xml"
detect "verify-cmd.sh wins over everything" "bash .claude/sdx/verify-cmd.sh"
fi

if want 6 && [ -f "$GEN" ]; then
echo "[6] structure"
newproj; with_verify; gen "$P"
if [ -f "$LIB/miniyaml.sh" ] && [ -f "$P/tests/suites.yaml" ]; then
  . "$LIB/miniyaml.sh"; my_load "$P/tests/suites.yaml"
  [ "$(my_kind suites)" = map ] && pass "[6] suites is the root mapping" || fail "[6] root" "kind=$(my_kind suites)"
  [ "$(my_kind suites.unit)" = map ] && pass "[6] unit is a mapping" || fail "[6] unit kind" "$(my_kind suites.unit)"
  ok=1; for k in cmd budget_min selector; do my_exists "suites.unit.$k" || ok=0; done
  [ "$ok" = 1 ] && pass "[6] unit has cmd, budget_min, selector" || fail "[6] unit keys" "missing"
  if my_exists suites.module || my_exists suites.regression; then fail "[6] samples" "module/regression are active"
  else pass "[6] module/regression are not active"; fi
  if grep -q '^  # module:' "$P/tests/suites.yaml" && grep -q '^  # regression:' "$P/tests/suites.yaml"; then pass "[6] module/regression present as comments"
  else fail "[6] comment samples" "absent"; fi
else fail "[6] structure" "no miniyaml or file"; fi
fi

if want 7 && [ -f "$LIB/test-cmd.sh" ]; then
echo "[7] twin: the real stop-gate.sh runs the command the resolver names"
MARK="$TMP/mark"; BIN="$TMP/bin"; mkdir -p "$BIN"
for t in composer npm; do printf '#!/bin/sh\necho %s > "$MARK"\n' "$t" > "$BIN/$t"; chmod +x "$BIN/$t"; done
twin_repo() {   # twin_repo: P = git repo on sdx/t at stage Execution
  newproj
  git -C "$P" init -q; git -C "$P" config user.email t@t; git -C "$P" config user.name t
  git -C "$P" commit -q --allow-empty -m init; git -C "$P" checkout -q -b sdx/t
  mkdir -p "$P/.claude/sessions/t"; printf '{"stage":"Execution"}' > "$P/.claude/sessions/t/session_state.json"
}
twin() {   # twin <label> <expected kind>   (fixture prepared in $P)
  rm -f "$MARK"
  CLAUDE_PROJECT_DIR="$P" MARK="$MARK" PATH="$BIN:$PATH" SDX_STOP_GATE=1 bash "$GATE" >/dev/null 2>&1
  ran="$(cat "$MARK" 2>/dev/null || echo none)"
  kind="$( . "$LIB/test-cmd.sh"; test_cmd_resolve "$P"; printf '%s' "$TC_KIND" )"
  if [ "$ran" = "$2" ] && [ "$kind" = "$2" ]; then pass "[7] $1: stop-gate ran '$ran', resolver says '$kind'"
  else fail "[7] $1" "stop-gate ran '$ran', resolver kind '$kind', expected '$2'"; fi
}
twin_repo; mkdir -p "$P/.claude/sdx"
printf '#!/usr/bin/env bash\necho verify-cmd > "$MARK"\n' > "$P/.claude/sdx/verify-cmd.sh"; twin verify-cmd verify-cmd
twin_repo; printf '{"scripts":{"test":"x"}}\n' > "$P/composer.json"; twin composer composer
twin_repo; printf '{"scripts":{"test":"x"}}\n' > "$P/package.json"; twin npm npm
twin_repo; mkdir -p "$P/vendor/bin"; printf '#!/bin/sh\necho phpunit > "$MARK"\n' > "$P/vendor/bin/phpunit"; chmod +x "$P/vendor/bin/phpunit"; touch "$P/phpunit.xml"; twin phpunit phpunit
twin_repo; mkdir -p "$P/.claude/sdx"; printf '#!/usr/bin/env bash\necho verify-cmd > "$MARK"\n' > "$P/.claude/sdx/verify-cmd.sh"
printf '{"scripts":{"test":"x"}}\n' > "$P/composer.json"; twin "priority (verify-cmd over composer)" verify-cmd
twin_repo; twin none none
fi

if want P; then
echo "[P] portability (BUG-010): forbidden constructs absent"
FORBID='tim''eout|map''file|declare -''A|[$]\{[a-zA-Z_]+,,\}|%''N|readlink -''f|real''path'
for f in suites-gen.sh lib/test-cmd.sh; do
  if [ ! -f "$SCRIPT_DIR/$f" ]; then fail "[P] $f" "file missing"; continue; fi
  if grep -nE "$FORBID" "$SCRIPT_DIR/$f" >/dev/null 2>&1; then fail "[P] $f" "forbidden: $(grep -nE "$FORBID" "$SCRIPT_DIR/$f" | head -3)"
  else pass "[P] $f has no GNU-only/bash4-only constructs"; fi
  PYNAME='py''thon'
  if grep -q "$PYNAME" "$SCRIPT_DIR/$f"; then fail "[P] $f" "mentions python"; else pass "[P] $f has no python"; fi
done
if [ -f "$SCRIPT_DIR/suites-gen.sh" ]; then
  cp "$SCRIPT_DIR/suites-gen.sh" "$TMP/port-mut.sh"; printf 'ma''pfile -t xs <<<""\n' >> "$TMP/port-mut.sh"
  if ! cmp -s "$SCRIPT_DIR/suites-gen.sh" "$TMP/port-mut.sh" && grep -qE "$FORBID" "$TMP/port-mut.sh"; then pass "[P] red side: the same grep flags a mutant with a bash4 construct"
  else fail "[P] red side" "mutant not flagged"; fi
else fail "[P] red side" "suites-gen.sh missing"; fi
if [ -f "$GEN" ]; then
  newproj; with_verify; PYTHONDONTWRITEBYTECODE=1 bash "$GEN" "$P" >/dev/null 2>&1
  if [ -z "$(find "$P" "$SCRIPT_DIR" -name __pycache__ 2>/dev/null)" ]; then pass "[P] no __pycache__ written"; else fail "[P] pycache" "found"; fi
fi
fi

if want Mut && [ -z "${SUITES_GEN_NESTED:-}" ]; then
echo "[Mut] mutation runs: copies of the scripts + lib/ in a temp dir; each mutant must differ and turn its block red"
MUTROOT="$TMP/mut"; mkdir -p "$MUTROOT"
# mutate <name> <file relative to hooks/> <sed expr> <blocks>
mutate() {
  local name="$1" file="$2" expr="$3" only="$4" d="$MUTROOT/$1" out first
  if [ ! -f "$SCRIPT_DIR/$file" ]; then fail "[Mut] $name" "no $file to mutate"; return; fi
  mkdir -p "$d/lib"
  cp "$SCRIPT_DIR/suites-gen.sh" "$d/" 2>/dev/null; cp "$SCRIPT_DIR"/lib/*.sh "$d/lib/" 2>/dev/null
  sed "$expr" "$SCRIPT_DIR/$file" > "$d/$file"
  if cmp -s "$SCRIPT_DIR/$file" "$d/$file"; then fail "[Mut] $name" "mutant is identical to the original (anchor missing?)"; return; fi
  out="$(SUITES_GEN_NESTED=1 SUITES_GEN_ONLY="$only" SUITES_GEN_UNDER_TEST="$d/suites-gen.sh" SUITES_GEN_LIB_FOR_TEST="$d/lib" bash "${BASH_SOURCE[0]}" 2>&1)"
  if printf '%s\n' "$out" | grep -q 'FAIL:'; then
    first="$(printf '%s\n' "$out" | grep -m1 'FAIL:' | cut -c1-110)"
    pass "[Mut] мутант $name → красный (ожидаемо) в [$only]: ${first#  FAIL: }"
  else
    fail "[Mut] $name" "blocks [$only] stayed green on the mutant (the check proves nothing)"
  fi
}
mutate SG-CEIL      suites-gen.sh '/# SG-CEIL/s/ + 59//' "1"
mutate SG-OVERWRITE suites-gen.sh '/# SG-OVERWRITE/s/if \[ -e "\$file" \]; then/if false; then/' "3"
mutate SG-NOCMD     suites-gen.sh '/# SG-NOCMD/s/if \[ "\$TC_KIND" = none \]; then/if false; then/' "4"
mutate SG-ORDER     lib/test-cmd.sh '/# SG-ORDER/s/\]; then/] \&\& [ ! -f "$proj\/composer.json" ]; then/' "7"
mutate SG-BASH      lib/test-cmd.sh '/# SG-BASH/s/"bash \.claude/".claude/' "1"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
