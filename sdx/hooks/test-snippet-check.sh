#!/usr/bin/env bash
# Tests for sdx/hooks/snippet-check.sh (FEAT-016, REQ-MAND-25).
#
# `bash snippet-check.sh <CLAUDE.md> [template]` compares the SDX:BEGIN..SDX:END block of a project's
# CLAUDE.md with the plugin's template block and prints ABSENT | BROKEN | OK | STALE (rc 0, never writes).
# Fixtures only: the real sdx/templates/claude-md-snippet.md is not read here (owned by another track).
#  (1) ABSENT: no markers (also: file missing)        (2) OK: identical block
#  (3) OK despite CRLF and trailing blanks            (4) text outside the markers does not matter
#  (5) STALE: block content differs                   (6) BROKEN: two blocks / no END / no BEGIN / END before BEGIN
#  (7) default template = claude-md-snippet.md beside the plugin (path from BASH_SOURCE), no write
#  (8) red side: embedded mutant "compare without content" turns (5) red
#  (P) portability (BUG-010)
set -uo pipefail
unset PYTHONDONTWRITEBYTECODE

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHK="${SNIPPET_CHECK_UNDER_TEST:-$SCRIPT_DIR/snippet-check.sh}"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "=== test-snippet-check.sh ==="
echo ""
if [ ! -f "$CHK" ]; then fail "[0] script" "snippet-check.sh missing ($CHK)"; fi

TPL="$TMP/tpl.md"
printf '%s\n' '<!-- SDX:BEGIN — блок -->' '## SDX' '' '- пункт один  ' '- пункт два' '<!-- SDX:END -->' > "$TPL"
# run <file> [tpl] -> OUT, RC
run() { OUT="$(bash "$CHK" "$@" 2>"$TMP/err")"; RC=$?; }
expect() {   # expect <label> <word> <file>
  run "$3" "$TPL"
  if [ "$OUT" = "$2" ] && [ "$RC" -eq 0 ]; then pass "$1 -> $2"; else fail "$1" "out=[$OUT] rc=$RC err=[$(cat "$TMP/err")] want $2"; fi
}

if [ -f "$CHK" ]; then
printf 'просто текст\n# Проект\n' > "$TMP/a.md";                         expect "[1] no markers" ABSENT "$TMP/a.md"
expect "[1] file missing" ABSENT "$TMP/nope.md"
{ echo '# Проект'; cat "$TPL"; } > "$TMP/b.md";                        expect "[2] identical block" OK "$TMP/b.md"
sed 's/$/\r/' "$TPL" > "$TMP/crlf-block";  { echo '# Проект'; cat "$TMP/crlf-block"; } > "$TMP/c.md"; expect "[3] CRLF" OK "$TMP/c.md"
sed 's/$/   /' "$TPL" > "$TMP/ws-block";   cp "$TMP/ws-block" "$TMP/d.md";                         expect "[3] trailing blanks" OK "$TMP/d.md"
{ echo 'до'; echo 'до 2'; cat "$TPL"; echo 'после'; echo '- что угодно'; } > "$TMP/e.md"
expect "[4] text outside the markers" OK "$TMP/e.md"
{ echo 'до'; cat "$TPL" | sed 's/пункт два/пункт ДВА/'; } > "$TMP/f.md";      expect "[5] changed line" STALE "$TMP/f.md"
{ cat "$TPL" | sed '/пункт два/d'; } > "$TMP/g.md";                       expect "[5] removed line" STALE "$TMP/g.md"
{ cat "$TPL"; echo; } | sed 's|<!-- SDX:END -->|- лишнее\n<!-- SDX:END -->|' > "$TMP/h.md"; expect "[5] added line" STALE "$TMP/h.md"
{ cat "$TPL"; echo 'между'; cat "$TPL"; } > "$TMP/i.md";                  expect "[6] two blocks" BROKEN "$TMP/i.md"
sed '/SDX:END/d' "$TPL" > "$TMP/j.md";                                    expect "[6] no END" BROKEN "$TMP/j.md"
sed '/SDX:BEGIN/d' "$TPL" > "$TMP/k.md";                                  expect "[6] no BEGIN" BROKEN "$TMP/k.md"
{ echo '<!-- SDX:END -->'; echo x; echo '<!-- SDX:BEGIN — блок -->'; } > "$TMP/l.md"; expect "[6] END before BEGIN" BROKEN "$TMP/l.md"
cp "$TMP/b.md" "$TMP/b.before"; run "$TMP/b.md" "$TPL"
cmp -s "$TMP/b.md" "$TMP/b.before" && pass "[7] the project file is not modified" || fail "[7] no write" "file changed"
# default template: BASH_SOURCE-relative claude-md-snippet.md; fixture plugin layout hooks/ + templates/
mkdir -p "$TMP/plug/sdx/hooks" "$TMP/plug/sdx/templates"; cp "$CHK" "$TMP/plug/sdx/hooks/snippet-check.sh"; cp "$TPL" "$TMP/plug/sdx/templates/claude-md-snippet.md"
if [ -d "$SCRIPT_DIR/lib" ]; then mkdir -p "$TMP/plug/sdx/hooks/lib"; cp "$SCRIPT_DIR"/lib/*.sh "$TMP/plug/sdx/hooks/lib/" 2>/dev/null; fi
OUT="$(cd "$TMP" && bash "$TMP/plug/sdx/hooks/snippet-check.sh" "$TMP/b.md" 2>&1)"; [ "$OUT" = OK ] && pass "[7] default template found beside the plugin -> OK" || fail "[7] default template" "out=[$OUT]"
OUT="$(cd "$TMP" && bash "$TMP/plug/sdx/hooks/snippet-check.sh" "$TMP/f.md" 2>&1)"; [ "$OUT" = STALE ] && pass "[7] default template -> STALE" || fail "[7] default STALE" "out=[$OUT]"
run; [ "$RC" -eq 2 ] && pass "[7] no arguments -> rc 2" || fail "[7] usage" "rc=$RC"
run "$TMP/b.md" "$TMP/missing-template.md"; [ "$RC" -eq 2 ] && pass "[7] template missing -> rc 2" || fail "[7] template missing" "rc=$RC out=[$OUT]"
fi

echo "[8] red side: mutant 'compare without content' (anchor SC-CMP)"
if [ -f "$CHK" ] && [ -z "${SNIPPET_CHECK_NESTED:-}" ]; then
  mkdir -p "$TMP/mut"; sed '/# SC-CMP/s/if \[ "\$blk" = "\$tblk" \]; then/if true; then/' "$CHK" > "$TMP/mut/snippet-check.sh"
  if cmp -s "$CHK" "$TMP/mut/snippet-check.sh"; then fail "[8] mutant" "identical to the original (anchor missing?)"
  else
    out="$(SNIPPET_CHECK_NESTED=1 SNIPPET_CHECK_UNDER_TEST="$TMP/mut/snippet-check.sh" bash "${BASH_SOURCE[0]}" 2>&1)"
    if printf '%s\n' "$out" | grep -q 'FAIL: \[5\]'; then pass "[8] мутант SC-CMP → красный (ожидаемо): $(printf '%s\n' "$out" | grep -m1 'FAIL: \[5\]' | cut -c1-90)"
    else fail "[8] mutant" "stayed green"; fi
  fi
fi

echo "[P] portability (BUG-010)"
FORBID='tim''eout|map''file|declare -''A|[$]\{[a-zA-Z_]+,,\}|%''N|readlink -''f|real''path'
if [ -f "$SCRIPT_DIR/snippet-check.sh" ]; then
  if grep -nE "$FORBID" "$SCRIPT_DIR/snippet-check.sh" >/dev/null 2>&1; then fail "[P] snippet-check.sh" "forbidden construct"; else pass "[P] no GNU-only/bash4-only constructs"; fi
  if grep -q 'py''thon' "$SCRIPT_DIR/snippet-check.sh"; then fail "[P] python" "mentioned"; else pass "[P] no python"; fi
  cp "$SCRIPT_DIR/snippet-check.sh" "$TMP/pm.sh"; printf 'ma''pfile -t xs <<<""\n' >> "$TMP/pm.sh"
  grep -qE "$FORBID" "$TMP/pm.sh" && pass "[P] red side: grep flags a bash4 mutant" || fail "[P] red side" "not flagged"
else fail "[P] snippet-check.sh" "file missing"; fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
