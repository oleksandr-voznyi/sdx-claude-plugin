#!/usr/bin/env bash
# Tests for sdx/hooks/mandate-scope.sh and sdx/hooks/mandate-info.sh (FEAT-016, REQ-MAND-12..15, 23, 23a, 26).
#
# mandate-scope.sh: `diff ⊆ mandate area` check for /sdx:verify — reads changed paths on stdin and writes a
# deterministic block into verification_report.md between SDX-MANDATE-SCOPE markers (idempotent). It is silent
# and writes nothing outside mandate mode (both .mesh/endpoint.yaml and .mesh/mandate.yaml present).
# mandate-info.sh: CLI for the commands (mode | show | status | closeout-mode | closeout-check <sid>).
#
# Scenarios of mandate-scope.sh:
#  (1)  no mandate / mandate without endpoint -> no output, report untouched (REQ-MAND-15)
#  (2)  a file outside paths U shared U docs -> "### [FAIL]" in the report, rc 1 (the gate's ^### \[FAIL\] fires)
#  (3)  shared_paths -> "### [WARN]" (also when the file is in paths AND shared)
#  (4)  empty scope.paths -> no FAIL, WARN for shared stays
#  (5)  docs_paths unset -> docs/** by default
#  (6)  --planned: Closeout transfers outside docs_paths -> FAIL; docs/** or empty paths -> none
#  (7)  repeated --into replaces the block, the rest of the report is preserved byte-for-byte
#  (8)  unreadable mandate -> FAIL block, rc 1 (fail-closed)
#  (9)  glob_any reference cases through the script
#  (10) expired mandate -> a non-heading "> Предупреждение:" line, rc != 1; rc 2 without --into
# Block [M]: mandate-info.sh — mode, show, status, closeout-mode, closeout-check.
# Block [P]: portability (BUG-010) of the two scripts.
# Block [Mut]: mutation runs on copies of the scripts + lib/ (anchored by "# MAND-*" tags).
# MANDATE_SCOPE_ONLY="1 2 M" restricts a run to the named blocks (used by the mutation runs).
set -uo pipefail
unset PYTHONDONTWRITEBYTECODE
unset SDX_MANDATE_TODAY

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCOPE="${MANDATE_SCOPE_UNDER_TEST:-$SCRIPT_DIR/mandate-scope.sh}"
INFO="${MANDATE_INFO_UNDER_TEST:-$SCRIPT_DIR/mandate-info.sh}"
LIB="${MANDATE_LIB_FOR_TEST:-$SCRIPT_DIR/lib}"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
info() { echo "  INFO: $1"; }
want() { [ -z "${MANDATE_SCOPE_ONLY:-}" ] && return 0; case " $MANDATE_SCOPE_ONLY " in *" $1 "*) return 0 ;; esac; return 1; }

echo "=== test-mandate-scope.sh ==="
echo ""

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Mutation re-runs stop at the first red check (all [Mut] needs; keeps the suite fast).
if [ -n "${MANDATE_SCOPE_NESTED:-}" ]; then fail() { echo "  FAIL: $1 — $2"; exit 1; }; fi
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# ---------------------------------------------------------------- fixtures
# put <dir> <relpath> <content>: write a file (parents created)
put() { local pd="$1/$2"; pd="${pd%/*}"; [ -d "$pd" ] || mkdir -p "$pd"; printf '%s' "$3" > "$1/$2"; }
# gitc <dir> <git args...>
gitc() { local d="$1"; shift; git -C "$d" "$@"; }

# mkrepo <name>: a git repo with main (base files) and branch sdx/s1 checked out carrying a rich diff
mkrepo() {
  local d="$TMP/repo-$1"
  mkdir -p "$d"
  gitc "$d" init -q
  gitc "$d" symbolic-ref HEAD refs/heads/main
  put "$d" README.md $'base\n'; put "$d" src/a.php $'<?php\n'; put "$d" docs/x.md $'x\n'
  put "$d" .gitignore $'.stopgate.*\n'
  gitc "$d" add -A; gitc "$d" commit -q -m base
  gitc "$d" checkout -q -b sdx/s1
  put "$d" src/new.php $'1\n'; put "$d" src/dir/deep.php $'2\n'; put "$d" other/z.txt $'3\n'
  put "$d" composer.lock $'4\n'; put "$d" docs/DECISIONS.md $'5\n'; put "$d" docs/specs/s.md $'6\n'; put "$d" notes.md $'7\n'
  put "$d" .claude/sessions/s1/PLAN.md $'plan\n'
  gitc "$d" add -A; gitc "$d" commit -q -m work
  printf '%s' "$d"
}
# difflist <repo>: the changed paths exactly as /sdx:verify computes them
difflist() { gitc "$1" -c core.quotepath=off diff --name-only "main...sdx/s1" -- . ':!.claude/sessions/**'; }
# mesh <repo> <endpoint 0|1> <mandate-content or ->: (re)write the untracked .mesh files
mesh() {
  [ -d "$1/.mesh" ] || mkdir -p "$1/.mesh"
  if [ "$2" = 1 ]; then printf 'on_write: notice\n' > "$1/.mesh/endpoint.yaml"; else rm -f "$1/.mesh/endpoint.yaml"; fi
  if [ "$3" != "-" ]; then printf '%s' "$3" > "$1/.mesh/mandate.yaml"; else rm -f "$1/.mesh/mandate.yaml"; fi
  return 0
}
# scope <repo> <report> [args...]: run the script with the repo's diff list on stdin. Sets OUT, RC.
scope() {
  local d="$1" rep="$2"; shift 2
  OUT="$(printf '%s\n' "$DIFFL" | bash "$SCOPE" --proj "$d" --into "$rep" "$@" 2>"$TMP/scope.err")"; RC=$?
  ERRTXT="$(<"$TMP/scope.err")"
}
# scope_in <repo> <report> <stdin text> [args...]
scope_in() {
  local d="$1" rep="$2" in="$3"; shift 3
  OUT="$(printf '%s\n' "$in" | bash "$SCOPE" --proj "$d" --into "$rep" "$@" 2>"$TMP/scope.err")"; RC=$?
  ERRTXT="$(<"$TMP/scope.err")"
}
has() { local c; c="$(<"$1")"; case "$c" in *"$2"*) return 0 ;; esac; return 1; }   # no process spawned
REPORT_SEED=$'# Verification report\n\n## Итог\n- PASS\n'
fresh_report() { printf '%s' "$REPORT_SEED" > "$1"; }

if want 1 || want 2 || want 3 || want 4 || want 5 || want 6 || want 7 || want 8 || want 9 || want 10; then
REPO="$(mkrepo main)"
DIFFL="$(difflist "$REPO")"   # computed once: the same list /sdx:verify would pipe in
DIFFN="$(printf '%s\n' "$DIFFL" | grep -c .)"
if [ "$DIFFN" -ne 7 ]; then echo "fixture broken: expected 7 changed paths, got $DIFFN"; exit 1; fi
fi

# ================================================================ (1) silent outside mandate mode
if want 1; then
echo "(1) no mandate / mandate without endpoint: nothing printed, nothing written"
for variant in none endpoint-only mandate-only; do
  case "$variant" in
    none) mesh "$REPO" 0 - ;;
    endpoint-only) mesh "$REPO" 1 - ;;
    mandate-only) mesh "$REPO" 0 $'mandate:\n  scope:\n    paths: [nothing/**]\n' ;;
  esac
  R="$TMP/r1-$variant.md"; fresh_report "$R"; before="$(cksum < "$R")"
  scope "$REPO" "$R"
  if [ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERRTXT" ] && [ "$before" = "$(cksum < "$R")" ]; then pass "(1) $variant: rc 0, no stdout/stderr, report byte-identical"
  else fail "(1) $variant" "rc=$RC out=[$OUT] err=[$ERRTXT] changed=$([ "$before" = "$(cksum < "$R")" ] && echo no || echo yes)"; fi
done
R="$TMP/r1-absent.md"; rm -f "$R"; mesh "$REPO" 1 -
scope "$REPO" "$R"
if [ "$RC" -eq 0 ] && [ ! -e "$R" ]; then pass "(1) outside mandate mode a missing report is not created"; else fail "(1) report not created" "rc=$RC exists=$([ -e "$R" ] && echo yes || echo no)"; fi
fi

# ================================================================ (2) outside the area
if want 2; then
echo "(2) file outside paths U shared U docs -> FAIL"
for form in block flow; do
  if [ "$form" = block ]; then M=$'mandate:\n  executor: e1\n  digest: d1\n  scope:\n    paths:\n    - src/**\n'
  else M=$'mandate:\n  executor: e1\n  digest: d1\n  scope:\n    paths: [src/**]\n'; fi
  mesh "$REPO" 1 "$M"; R="$TMP/r2-$form.md"; fresh_report "$R"
  scope "$REPO" "$R"
  if [ "$RC" -eq 1 ] && grep -q '^### \[FAIL\]' "$R" && has "$R" '`other/z.txt`' && has "$R" '`notes.md`' && ! has "$R" '[FAIL] [Область] Файл вне области мандата: `src/new.php`'; then
    pass "(2) $form: rc 1, FAIL for other/z.txt and notes.md (gate regex fires), none for src/new.php"
  else fail "(2) $form" "rc=$RC out=[$OUT]"; fi
  case "$OUT" in FAIL*) pass "(2) $form: stdout summary starts with FAIL" ;; *) fail "(2) $form summary" "out=[$OUT]" ;; esac
  has "$R" "executor=e1" && has "$R" "digest=d1" && pass "(2) $form: block names executor and digest" || fail "(2) $form header" "no executor/digest"
  has "$R" '<!-- SDX-MANDATE-SCOPE:BEGIN -->' && has "$R" '<!-- SDX-MANDATE-SCOPE:END -->' && pass "(2) $form: BEGIN/END markers present" || fail "(2) $form markers" "missing"
done
mesh "$REPO" 1 $'mandate:\n  scope:\n    paths: [src/**, other/**, notes.md, composer.lock]\n'
R="$TMP/r2-ok.md"; fresh_report "$R"; scope "$REPO" "$R"
if [ "$RC" -eq 0 ] && ! grep -q '^### \[FAIL\]' "$R" && [ "${OUT%% *}" = WARN -o "${OUT%% *}" = PASS ]; then pass "(2) every changed file inside the union -> no FAIL (docs/** default covers docs/)"
else fail "(2) all inside" "rc=$RC out=[$OUT]"; fi
fi

# ================================================================ (3) shared_paths -> WARN
if want 3; then
echo "(3) shared_paths -> WARN (also when the file is in paths AND shared)"
mesh "$REPO" 1 $'mandate:\n  scope:\n    paths: [src/**, other/**, notes.md]\n    shared_paths: [composer.lock]\n'
R="$TMP/r3.md"; fresh_report "$R"; scope "$REPO" "$R"
if [ "$RC" -eq 0 ] && has "$R" '### [WARN] [Область] Общий путь (shared_paths): `composer.lock`' && ! grep -q '^### \[FAIL\]' "$R"; then pass "(3) composer.lock in shared only: WARN, no FAIL, rc 0"
else fail "(3) shared" "rc=$RC out=[$OUT]"; fi
mesh "$REPO" 1 $'mandate:\n  scope:\n    paths: [src/**, other/**, notes.md, composer.lock]\n    shared_paths: [composer.lock]\n'
R="$TMP/r3b.md"; fresh_report "$R"; scope "$REPO" "$R"
if [ "$RC" -eq 0 ] && has "$R" '### [WARN] [Область] Общий путь (shared_paths): `composer.lock`'; then pass "(3) file in paths AND shared_paths: still WARN"
else fail "(3) paths+shared" "rc=$RC out=[$OUT]"; fi
case "$OUT" in WARN*) pass "(3) summary starts with WARN" ;; *) fail "(3) summary" "out=[$OUT]" ;; esac
fi

# ================================================================ (4) empty paths
if want 4; then
echo "(4) empty scope.paths: no FAIL (no restriction), WARN for shared stays"
for M in $'mandate:\n  scope:\n    paths: []\n    shared_paths: [composer.lock]\n' $'mandate:\n  scope:\n    shared_paths: [composer.lock]\n' $'mandate:\n  stages: [spec]\n'; do
  mesh "$REPO" 1 "$M"; R="$TMP/r4.md"; fresh_report "$R"; scope "$REPO" "$R"
  if [ "$RC" -eq 0 ] && ! grep -q '^### \[FAIL\]' "$R"; then pass "(4) rc 0 and no FAIL for [$(printf '%s' "$M" | tr '\n' '~' | cut -c1-48)]"
  else fail "(4) empty paths" "rc=$RC out=[$OUT]"; fi
done
mesh "$REPO" 1 $'mandate:\n  scope:\n    paths: []\n    shared_paths: [composer.lock]\n'
R="$TMP/r4w.md"; fresh_report "$R"; scope "$REPO" "$R"
has "$R" '`composer.lock`' && has "$R" '[WARN]' && pass "(4) the shared WARN remains with empty paths" || fail "(4) shared WARN" "missing"
fi

# ================================================================ (5) docs default
if want 5; then
echo "(5) docs_paths unset -> docs/**"
mesh "$REPO" 1 $'mandate:\n  scope:\n    paths: [src/**, other/**, notes.md, composer.lock]\n'
R="$TMP/r5.md"; fresh_report "$R"; scope "$REPO" "$R"
if [ "$RC" -eq 0 ] && ! has "$R" '`docs/DECISIONS.md`' && ! has "$R" '`docs/specs/s.md`'; then pass "(5) docs/DECISIONS.md and docs/specs/s.md in the diff are inside the default docs area"
else fail "(5) default docs" "rc=$RC out=[$OUT]"; fi
mesh "$REPO" 1 $'mandate:\n  scope:\n    paths: [src/**, other/**, notes.md, composer.lock]\n    docs_paths: [docs/specs/**]\n'
R="$TMP/r5b.md"; fresh_report "$R"; scope "$REPO" "$R"
if [ "$RC" -eq 1 ] && has "$R" '[FAIL] [Область] Файл вне области мандата: `docs/DECISIONS.md`' && ! has "$R" 'Файл вне области мандата: `docs/specs/s.md`'; then pass "(5) narrow docs_paths: docs/DECISIONS.md is FAIL, docs/specs/s.md is fine"
else fail "(5) narrow docs" "rc=$RC out=[$OUT]"; fi
fi

# ================================================================ (6) --planned
if want 6; then
echo "(6) --planned: Closeout transfers (К-3)"
mesh "$REPO" 1 $'mandate:\n  scope:\n    paths: [src/**, other/**, notes.md, composer.lock]\n    docs_paths: [docs/specs/**]\n'
R="$TMP/r6.md"; fresh_report "$R"; scope_in "$REPO" "$R" "src/new.php" --planned docs/DECISIONS.md --planned docs/specs/s.md
if [ "$RC" -eq 1 ] && has "$R" '[FAIL] [Область] Перенос Closeout вне docs_paths: `docs/DECISIONS.md`' && ! has "$R" 'Перенос Closeout вне docs_paths: `docs/specs/s.md`'; then
  pass "(6) narrow docs_paths: planned docs/DECISIONS.md -> FAIL with the reason, docs/specs/s.md fine"
else fail "(6) planned narrow" "rc=$RC out=[$OUT]"; fi
mesh "$REPO" 1 $'mandate:\n  scope:\n    paths: [src/**]\n'
R="$TMP/r6b.md"; fresh_report "$R"; scope_in "$REPO" "$R" "src/new.php" --planned docs/DECISIONS.md --planned docs/history/sessions-log.md
if [ "$RC" -eq 0 ] && ! grep -q '^### \[FAIL\]' "$R"; then pass "(6) default docs/**: planned transfers are fine"
else fail "(6) planned default" "rc=$RC out=[$OUT]"; fi
mesh "$REPO" 1 $'mandate:\n  scope:\n    paths: []\n    docs_paths: [docs/specs/**]\n'
R="$TMP/r6c.md"; fresh_report "$R"; scope_in "$REPO" "$R" "src/new.php" --planned docs/DECISIONS.md
if [ "$RC" -eq 0 ] && ! grep -q '^### \[FAIL\]' "$R"; then pass "(6) empty paths: --planned never fails (no restriction)"
else fail "(6) planned empty paths" "rc=$RC out=[$OUT]"; fi
mesh "$REPO" 1 $'mandate:\n  scope:\n    paths: [src/**]\n'
R="$TMP/r6d.md"; fresh_report "$R"; scope_in "$REPO" "$R" "src/new.php" --planned docs/DECISIONS.md --planned docs/x.md
has "$R" 'запланированных переносов Closeout: 2' && pass "(6) the block counts the planned transfers" || fail "(6) planned count" "no count line"
fi

# ================================================================ (7) idempotent block
if want 7; then
echo "(7) repeated --into replaces the block; the rest of the report is preserved"
mesh "$REPO" 1 $'mandate:\n  scope:\n    paths: [src/**]\n'
R="$TMP/r7.md"; fresh_report "$R"; scope "$REPO" "$R"
strip_block() { awk '/<!-- SDX-MANDATE-SCOPE:BEGIN -->/ { skip = 1 } !skip { print } /<!-- SDX-MANDATE-SCOPE:END -->/ { skip = 0 }' "$1"; }
out1="$(strip_block "$R")"; n1="$(grep -c 'SDX-MANDATE-SCOPE:BEGIN' "$R")"
case "$out1" in "$REPORT_SEED"*|"${REPORT_SEED%$'\n'}"*) [ "$n1" = 1 ] && pass "(7) after the first run the original report text is intact before the block" ;; *) fail "(7) original text" "[$out1]" ;; esac
scope_in "$REPO" "$R" "src/new.php"
out2="$(strip_block "$R")"; n2="$(grep -c 'SDX-MANDATE-SCOPE:BEGIN' "$R")"; e2="$(grep -c 'SDX-MANDATE-SCOPE:END' "$R")"
if [ "$n1" = 1 ] && [ "$n2" = 1 ] && [ "$e2" = 1 ] && [ "$out1" = "$out2" ] && ! has "$R" '`other/z.txt`'; then pass "(7) second run: exactly one block, text outside identical, block content replaced"
else fail "(7) replace" "n1=$n1 n2=$n2 e2=$e2 same=$([ "$out1" = "$out2" ] && echo yes || echo no)"; fi
{ printf '%s' "$REPORT_SEED"; printf 'tail after\n'; } > "$TMP/r7b.md"
scope "$REPO" "$TMP/r7b.md"
has "$TMP/r7b.md" 'tail after' && has "$TMP/r7b.md" 'SDX-MANDATE-SCOPE:BEGIN' && pass "(7) text that precedes the block is untouched" || fail "(7) tail" "lost"
fi

# ================================================================ (8) unreadable mandate
if want 8; then
echo "(8) unreadable mandate -> FAIL block, rc 1"
for M in $'mandate:\n\tpaths: [src/**]\n' $'just text\n' $'mandate:\n  stages: [lint]\n'; do
  mesh "$REPO" 1 "$M"; R="$TMP/r8.md"; fresh_report "$R"; scope "$REPO" "$R"
  if [ "$RC" -eq 1 ] && grep -q '^### \[FAIL\] Мандат МО не разобран' "$R" && ! grep -q 'Файл вне области' "$R"; then pass "(8) [$(printf '%s' "$M" | head -c 20 | tr '\n\t' '~~')] -> FAIL block 'Мандат МО не разобран', rc 1"
  else fail "(8) unreadable" "rc=$RC out=[$OUT]"; fi
done
fi

# ================================================================ (9) glob reference cases
if want 9; then
echo "(9) glob_any reference cases through the script"
# pattern | file | expected: in (inside the area) / out (FAIL)
while IFS='|' read -r gpat gfile gexp; do
  [ -z "$gpat" ] && continue
  mesh "$REPO" 1 "mandate:
  scope:
    paths: [\"$gpat\"]
    docs_paths: [\"zzz/**\"]
"
  R="$TMP/r9.md"; fresh_report "$R"; scope_in "$REPO" "$R" "$gfile"
  if [ "$gexp" = in ]; then
    if [ "$RC" -eq 0 ] && ! grep -q '^### \[FAIL\]' "$R"; then pass "(9) '$gpat' covers '$gfile'"; else fail "(9) '$gpat' vs '$gfile'" "expected inside, rc=$RC"; fi
  else
    if [ "$RC" -eq 1 ] && grep -q '^### \[FAIL\]' "$R"; then pass "(9) '$gpat' does not cover '$gfile'"; else fail "(9) '$gpat' vs '$gfile'" "expected outside, rc=$RC"; fi
  fi
done <<'TABLE'
src/**|src/a.php|in
src/**|src|out
src/lib/|src/lib/a.php|in
src/lib/|src/library/a|out
*.md|a/b.md|in
[!x]*|y.txt|in
[!x]*|x.txt|out
[^b]*|a.txt|out
[^b]*|b.txt|in
Src/**|src/a|out
[ab]/**|[ab]/x|in
TABLE
fi

# ================================================================ (10) expiry and usage
if want 10; then
echo "(10) expired mandate: warning line, not a heading, no block; usage errors rc 2"
mesh "$REPO" 1 $'mandate:\n  valid_until: \'2020-01-01\'\n  scope:\n    paths: [src/**, other/**, notes.md, composer.lock]\n'
R="$TMP/r10.md"; fresh_report "$R"
OUT="$(printf '%s\n' "$DIFFL" | SDX_MANDATE_TODAY=2026-10-28 bash "$SCOPE" --proj "$REPO" --into "$R" 2>&1)"; RC=$?
if [ "$RC" -ne 1 ] && grep -q '^> Предупреждение:.*мандат истёк' "$R" && ! grep -q '^#.*истёк' "$R"; then pass "(10) expired: '> Предупреждение:' line (not a heading), rc $RC != 1"
else fail "(10) expired" "rc=$RC"; fi
mesh "$REPO" 1 $'mandate:\n  valid_until: \'2999-01-01\'\n  scope:\n    paths: [src/**, other/**, notes.md, composer.lock]\n'
R="$TMP/r10b.md"; fresh_report "$R"; scope "$REPO" "$R"
has "$R" 'SDX-MANDATE-SCOPE:BEGIN' && ! grep -q 'Предупреждение' "$R" && pass "(10) a valid mandate carries no expiry line" || fail "(10) valid" "warning present"
OUT="$(printf '%s\n' "$DIFFL" | bash "$SCOPE" --proj "$REPO" 2>&1)"; RC=$?
[ "$RC" -eq 2 ] && pass "(10) no --into -> rc 2" || fail "(10) usage" "rc=$RC"
OUT="$(printf '%s\n' "$DIFFL" | bash "$SCOPE" --proj "$REPO" --into "$TMP/no-such-dir/r.md" 2>&1)"; RC=$?
[ "$RC" -eq 2 ] && pass "(10) report in a missing directory -> rc 2" || fail "(10) unwritable report" "rc=$RC"
OUT="$(bash "$SCOPE" --proj "$REPO" --into "$R" --bogus 2>&1 </dev/null)"; RC=$?
[ "$RC" -eq 2 ] && pass "(10) unknown option -> rc 2" || fail "(10) unknown option" "rc=$RC"
fi

# ================================================================ [M] mandate-info.sh
# mkd <name> <endpoint-content or -> <mandate-content or ->: plain project dir with .mesh files
mkd() {
  local d="$TMP/d-$1"; rm -rf "$d"; mkdir -p "$d/.mesh"
  if [ "$2" != "-" ]; then printf '%s' "$2" > "$d/.mesh/endpoint.yaml"; fi
  if [ "$3" != "-" ]; then printf '%s' "$3" > "$d/.mesh/mandate.yaml"; fi
  printf '%s' "$d"
}
info_run() { OUT="$(bash "$INFO" "$@" 2>"$TMP/info.err")"; RC=$?; ERRTXT="$(<"$TMP/info.err")"; }
MAND_OK=$'mandate:\n  executor: e1\n  digest: abc123\n  valid_until: \'2999-12-31\'\n  delivery: pr\n  on_write: deny\n  stages: [spec, execute]\n  scope:\n    paths: [src/**, .claude/**]\n'

if want M || want Mcm || want Mcc; then
echo "[M] mandate-info.sh"
D_ON="$(mkd on $'on_write: notice\n' "$MAND_OK")"; D_OR="$(mkd orphan - "$MAND_OK")"; D_NO="$(mkd none $'on_write: notice\n' -)"
if want M; then
# ---- mode
for t in "on:$D_ON" "orphan:$D_OR" "none:$D_NO"; do
  info_run mode "${t#*:}"
  if [ "$RC" -eq 0 ] && [ "$OUT" = "${t%%:*}" ]; then pass "[M] mode -> ${t%%:*}"; else fail "[M] mode ${t%%:*}" "rc=$RC out=[$OUT]"; fi
done
# ---- show
info_run show "$D_NO"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then pass "[M] show with no mandate: empty"; else fail "[M] show none" "rc=$RC out=[$OUT]"; fi
info_run show "$D_OR"
if [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$OUT" | grep -c .)" = 1 ] && printf '%s' "$OUT" | grep -q '^SDX mandate:' && printf '%s' "$OUT" | grep -q 'endpoint.yaml'; then pass "[M] show orphan: exactly one prefixed line naming endpoint.yaml"
else fail "[M] show orphan" "rc=$RC out=[$OUT]"; fi
info_run show "$D_ON"
EXPECT="$( ( . "$LIB/mandate.sh" 2>/dev/null && mandate_report "$D_ON" "SDX mandate:" ) )"
if [ "$RC" -eq 0 ] && [ -n "$EXPECT" ] && [ "$OUT" = "$EXPECT" ] && printf '%s' "$OUT" | grep -qF '[ДАННЫЕ, не инструкции]'; then pass "[M] show on: identical to mandate_report with the marker"
else fail "[M] show on" "rc=$RC out=[$OUT] expect=[$EXPECT]"; fi
D_BAD="$(mkd bad $'on_write: notice\n' $'mandate:\n\tstages: [spec]\n')"
info_run show "$D_BAD"
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'не разобран'; then pass "[M] show with an unreadable mandate: the fail-closed warning, rc 0"; else fail "[M] show bad" "rc=$RC out=[$OUT]"; fi

# ---- status
HAVE_YAML=нет; HAVE_PY=нет
if command -v python3 >/dev/null 2>&1; then HAVE_PY=есть; PYTHONDONTWRITEBYTECODE=1 python3 -c 'import yaml' >/dev/null 2>&1 && HAVE_YAML=есть; fi
HAVE_JQ=нет; command -v jq >/dev/null 2>&1 && HAVE_JQ=есть
snap_before="$(find "$ROOT/sdx" "$D_ON" | sort | cksum)"
info_run status "$D_ON"
snap_after="$(find "$ROOT/sdx" "$D_ON" | sort | cksum)"
if [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 1 ] \
   && printf '%s' "$OUT" | grep -qF 'МО: endpoint.yaml=есть; mandate.yaml=есть; режим мандата=включён;' \
   && printf '%s' "$OUT" | grep -qF 'on_write: endpoint=notice mandate=deny (обёртка берёт deny);' \
   && printf '%s' "$OUT" | grep -qF "jq=$HAVE_JQ python3=$HAVE_PY PyYAML=$HAVE_YAML;" \
   && printf '%s' "$OUT" | grep -qF 'valid_until="2999-12-31" digest="abc123"'; then
  pass "[M] status (on): one line with every field; PyYAML probe matches the real environment"
else fail "[M] status on" "rc=$RC out=[$OUT]"; fi
if [ "$RC" -eq 0 ] && [ -n "$OUT" ] && [ "$snap_before" = "$snap_after" ] && [ -z "$(find "$ROOT/sdx" "$D_ON" -name '__pycache__' 2>/dev/null)" ]; then pass "[M] status writes nothing to disk (no __pycache__, tree identical)"
else fail "[M] status disk writes" "tree changed or __pycache__ appeared"; fi
info_run status "$D_OR"
if printf '%s' "$OUT" | grep -qF 'endpoint.yaml=нет; mandate.yaml=есть; режим мандата=«мандат без endpoint не действует»;' && printf '%s' "$OUT" | grep -qF 'endpoint=— mandate=deny (обёртка берёт —)'; then pass "[M] status (orphan): режим «мандат без endpoint не действует», wrapper inactive"
else fail "[M] status orphan" "out=[$OUT]"; fi
info_run status "$D_NO"
if printf '%s' "$OUT" | grep -qF 'mandate.yaml=нет; режим мандата=выключен;' && printf '%s' "$OUT" | grep -qF 'mandate=— (обёртка берёт notice)' && printf '%s' "$OUT" | grep -qF 'valid_until=— digest=—'; then pass "[M] status (endpoint only): режим выключен, valid_until/digest are —"
else fail "[M] status none" "out=[$OUT]"; fi
D_EW="$(mkd ewdeny $'on_write: deny\n' $'mandate:\n  stages: [spec]\n')"
info_run status "$D_EW"
printf '%s' "$OUT" | grep -qF 'endpoint=deny mandate=— (обёртка берёт deny)' && pass "[M] status: endpoint deny -> wrapper takes deny" || fail "[M] status endpoint deny" "out=[$OUT]"
# degraded toolchain: PATH without python3 / without jq
NOPY="$TMP/nopybin"; mkdir -p "$NOPY"
for t in bash cat sed awk grep tr date head tail cut wc sort uniq dirname basename git jq mktemp rm mkdir ls env find cksum; do
  p="$(command -v "$t" 2>/dev/null)"; [ -n "$p" ] && ln -sf "$p" "$NOPY/$t"
done
OUT="$(PATH="$NOPY" bash "$INFO" status "$D_ON" 2>&1)"; RC=$?
printf '%s' "$OUT" | grep -qF 'python3=нет PyYAML=нет' && pass "[M] status without python3: python3=нет PyYAML=нет" || fail "[M] status no python" "rc=$RC out=[$OUT]"
rm -f "$NOPY/jq"
OUT="$(PATH="$NOPY" bash "$INFO" status "$D_ON" 2>&1)"; RC=$?
printf '%s' "$OUT" | grep -qF 'jq=нет' && pass "[M] status without jq: jq=нет" || fail "[M] status no jq" "rc=$RC out=[$OUT]"

fi   # mode / show / status
if want M || want Mcm; then
# ---- closeout-mode
cm() { # name mandate-body expected
  local d; d="$(mkd "cm-$1" $'on_write: notice\n' "$2")"
  info_run closeout-mode "$d"
  case "$3" in
    error:*) if [ "$RC" -eq 0 ] && case "$OUT" in error:*) true ;; *) false ;; esac; then pass "[M] closeout-mode $1 -> $OUT"; else fail "[M] closeout-mode $1" "rc=$RC out=[$OUT]"; fi ;;
    *) if [ "$RC" -eq 0 ] && [ "$OUT" = "$3" ]; then pass "[M] closeout-mode $1 -> $OUT"; else fail "[M] closeout-mode $1" "rc=$RC out=[$OUT] expected [$3]"; fi ;;
  esac
}
cm offer  $'mandate:\n  delivery: artifact.offer\n'  standard
cm pr     $'mandate:\n  delivery: pr\n'              bridge
cm branch $'mandate:\n  delivery: branch\n'          bridge
cm patch  $'mandate:\n  delivery: patch\n'           undefined:patch
cm worktree $'mandate:\n  delivery: worktree\n'      undefined:worktree
cm unset  $'mandate:\n  executor: e\n'               undefined:unset
cm broken $'mandate:\n\tdelivery: pr\n'              error:
cm hostile $'mandate:\n  delivery: "p$(id)\\"r; x"\n' undefined:p??id??r??x
info_run closeout-mode "$D_NO"
[ "$RC" -eq 0 ] && [ "$OUT" = standard ] && pass "[M] closeout-mode without a mandate -> standard" || fail "[M] closeout-mode none" "out=[$OUT]"
D_OR2="$(mkd or2 - $'mandate:\n  delivery: pr\n')"
info_run closeout-mode "$D_OR2"
[ "$RC" -eq 0 ] && [ "$OUT" = standard ] && pass "[M] closeout-mode with an orphan mandate -> standard (mandate mode is off)" || fail "[M] closeout-mode orphan" "out=[$OUT]"

fi   # closeout-mode
if want M || want Mcc; then
# ---- closeout-check
mkco() { # name: git repo on sdx/s1, clean tree, no session path in HEAD
  local d="$TMP/co-$1"; mkdir -p "$d"
  gitc "$d" init -q; gitc "$d" symbolic-ref HEAD refs/heads/main
  put "$d" README.md $'r\n'; put "$d" .gitignore $'.stopgate.*\n'
  gitc "$d" add -A; gitc "$d" commit -q -m base
  gitc "$d" checkout -q -b sdx/s1
  put "$d" src/a.php $'a\n'; gitc "$d" add -A; gitc "$d" commit -q -m work
  mkdir -p "$d/.mesh"; printf 'on_write: notice\n' > "$d/.mesh/endpoint.yaml"; printf 'mandate:\n  delivery: pr\n' > "$d/.mesh/mandate.yaml"
  printf '%s' "$d"
}
CO="$(mkco green)"
head_before="$(gitc "$CO" rev-parse HEAD)"; main_before="$(gitc "$CO" rev-parse main)"
info_run closeout-check s1 "$CO"
if [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$OUT" | grep -c '^OK ')" -ge 3 ] && ! printf '%s' "$OUT" | grep -q '^FAIL'; then pass "[M] closeout-check green: rc 0, three OK lines (untracked .mesh/ does not make the tree dirty)"
else fail "[M] closeout-check green" "rc=$RC out=[$OUT]"; fi
if [ -n "$OUT" ] && [ "$head_before" = "$(gitc "$CO" rev-parse HEAD)" ] && [ "$main_before" = "$(gitc "$CO" rev-parse main)" ] && gitc "$CO" rev-parse --verify -q refs/heads/sdx/s1 >/dev/null && [ "$(gitc "$CO" rev-parse --abbrev-ref HEAD)" = "sdx/s1" ]; then pass "[M] closeout-check neither merges, deletes nor switches the branch"
else fail "[M] closeout-check side effects" "repo state changed"; fi
CO2="$(mkco wrongbranch)"; gitc "$CO2" checkout -q main
info_run closeout-check s1 "$CO2"
[ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q '^FAIL' && printf '%s' "$OUT" | grep -q 'sdx/s1' && pass "[M] closeout-check: not on sdx/<sid> -> FAIL, rc 1" || fail "[M] closeout-check wrong branch" "rc=$RC out=[$OUT]"
CO3="$(mkco dirty)"; printf 'changed\n' >> "$CO3/src/a.php"
info_run closeout-check s1 "$CO3"
[ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q '^FAIL' && pass "[M] closeout-check: modified tracked file -> FAIL, rc 1" || fail "[M] closeout-check dirty" "rc=$RC out=[$OUT]"
CO3b="$(mkco untracked)"; printf 'x\n' > "$CO3b/new-untracked.txt"
info_run closeout-check s1 "$CO3b"
[ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q '^FAIL' && pass "[M] closeout-check: untracked file -> FAIL, rc 1" || fail "[M] closeout-check untracked" "rc=$RC out=[$OUT]"
CO4="$(mkco session)"; put "$CO4" .claude/sessions/s1/PLAN.md $'plan\n'; gitc "$CO4" add -A; gitc "$CO4" commit -q -m session
info_run closeout-check s1 "$CO4"
[ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q '^FAIL' && printf '%s' "$OUT" | grep -q '.claude/sessions/s1' && pass "[M] closeout-check: session directory in HEAD -> FAIL, rc 1" || fail "[M] closeout-check session in HEAD" "rc=$RC out=[$OUT]"
info_run closeout-check
[ "$RC" -eq 2 ] && pass "[M] closeout-check without <sid> -> rc 2" || fail "[M] closeout-check usage" "rc=$RC"
info_run no-such-subcommand
[ "$RC" -eq 2 ] && pass "[M] unknown subcommand -> rc 2" || fail "[M] unknown subcommand" "rc=$RC"
fi   # closeout-check
fi   # [M]

# ================================================================ [P] portability
if want P; then
echo "[P] portability (BUG-010): forbidden constructs absent from the scripts"
FORBID='tim''eout|map''file|declare -''A|[$]\{[a-zA-Z_]+,,\}|%''N|readlink -''f|real''path'
for f in mandate-scope.sh mandate-info.sh; do
  if [ ! -f "$SCRIPT_DIR/$f" ]; then fail "[P] $f" "file missing"; continue; fi
  if grep -nE "$FORBID" "$SCRIPT_DIR/$f" >/dev/null 2>&1; then fail "[P] $f" "forbidden: $(grep -nE "$FORBID" "$SCRIPT_DIR/$f" | head -3)"
  else pass "[P] $f has no GNU-only/bash4-only constructs"; fi
done
if [ -f "$SCRIPT_DIR/mandate-scope.sh" ]; then
  cp "$SCRIPT_DIR/mandate-scope.sh" "$TMP/port-mut.sh"; printf 'ma''pfile -t xs <<<""\n' >> "$TMP/port-mut.sh"
  if ! cmp -s "$SCRIPT_DIR/mandate-scope.sh" "$TMP/port-mut.sh" && grep -qE "$FORBID" "$TMP/port-mut.sh"; then pass "[P] red side: the same grep flags a mutant with a bash4 construct"
  else fail "[P] red side" "mutant not flagged"; fi
else fail "[P] red side" "mandate-scope.sh missing"; fi
PYNAME='py''thon'
hits="$(grep -n "$PYNAME" "$SCRIPT_DIR/mandate-scope.sh" 2>/dev/null)"
if [ -f "$SCRIPT_DIR/mandate-scope.sh" ] && [ -z "$hits" ]; then pass "[P] no python in mandate-scope.sh"; else fail "[P] no python in mandate-scope.sh" "${hits:-file missing}"; fi
fi

# ================================================================ [Mut] mutation runs
if want Mut && [ -z "${MANDATE_SCOPE_NESTED:-}" ]; then
echo "[Mut] mutation runs: copies of the scripts + lib/ in a temp dir; each mutant must differ and turn its block red"
MUTROOT="$TMP/mut"; mkdir -p "$MUTROOT"
# mutate <name> <script file> <sed expr> <blocks>
mutate() {
  local name="$1" file="$2" expr="$3" only="$4" d="$MUTROOT/$1" out first
  if [ ! -f "$SCRIPT_DIR/$file" ]; then fail "[Mut] $name" "no $file to mutate"; return; fi
  mkdir -p "$d/lib"
  cp "$SCRIPT_DIR/mandate-scope.sh" "$SCRIPT_DIR/mandate-info.sh" "$d/" 2>/dev/null; cp "$SCRIPT_DIR"/lib/*.sh "$d/lib/" 2>/dev/null
  sed "$expr" "$SCRIPT_DIR/$file" > "$d/$file"
  if cmp -s "$SCRIPT_DIR/$file" "$d/$file"; then fail "[Mut] $name" "mutant is identical to the original (anchor missing?)"; return; fi
  out="$(MANDATE_SCOPE_NESTED=1 MANDATE_SCOPE_ONLY="$only" MANDATE_SCOPE_UNDER_TEST="$d/mandate-scope.sh" MANDATE_INFO_UNDER_TEST="$d/mandate-info.sh" bash "${BASH_SOURCE[0]}" 2>&1)"
  if printf '%s\n' "$out" | grep -q 'FAIL:'; then
    first="$(printf '%s\n' "$out" | grep -m1 'FAIL:' | cut -c1-110)"
    pass "[Mut] мутант $name → красный (ожидаемо) в [$only]: ${first#  FAIL: }"
  else
    fail "[Mut] $name" "blocks [$only] stayed green on the mutant (the check proves nothing)"
  fi
}
mutate MAND-OUTSIDE      mandate-scope.sh '/# MAND-OUTSIDE/s/if \[ "\$restricted" = 1 \] \&\& ! mandate_in_union "\$f"; then/if false; then/' "2"
mutate MAND-SHARED       mandate-scope.sh '/# MAND-SHARED/s/if mandate_match_list "\$f" "\$MANDATE_SHARED"; then/if false; then/' "3"
mutate MAND-EMPTY-PATHS  mandate-scope.sh '/# MAND-EMPTY-PATHS/s/\[ -n "\$MANDATE_PATHS" \] \&\& restricted=1/restricted=1/' "4"
mutate MAND-PLANNED      mandate-scope.sh '/# MAND-PLANNED/s/while IFS= read -r f; do/while false; do/' "6"
mutate MAND-REPLACE      mandate-scope.sh '/# MAND-REPLACE/s/if \[ "\$have_block" = 1 \]; then/if false; then/' "7"
mutate MAND-BRIDGE       mandate-info.sh '/# MAND-BRIDGE/s/echo standard/echo bridge/' "Mcm"
mutate MAND-CHECK-TREE   mandate-info.sh '/# MAND-CHECK-TREE/s/\[ -z "\$dirty" \]/true/' "Mcc"
mutate MAND-CHECK-SESSION mandate-info.sh '/# MAND-CHECK-SESSION/s/\[ -z "\$insess" \]/true/' "Mcc"
fi
echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
