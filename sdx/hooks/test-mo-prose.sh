#!/usr/bin/env bash
# Static prose invariants of the FEAT-015 (meta-orchestrator interop) text layer.
#
# Why this suite exists. FEAT-015 changes prose in six places that must stay mutually coherent:
# the eight-tag decision-log vocabulary (protocol.md, commands/next.md), the devops agent rules
# (PYTHONDONTWRITEBYTECODE=1 on every vendored-tool call, the .mesh/endpoint.yaml switch), the
# /sdx:init gitignore block, the CLAUDE.md snippet and ADR-021. A forgotten place is silent: no
# hook reads prose. These are grep invariants, not semantics — they catch drift, not wrong words.
#
# Each scenario has a red side: the same check is run against a deliberately damaged COPY of
# the file (in a temp dir) and must fail there — a guard never exercised on a failing input
# proves nothing (pattern of test-init-patterns.sh). Static, bash 3.2 portable (no mapfile).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROTOCOL="$ROOT/sdx/protocol.md"
NEXT_MD="$ROOT/commands/next.md"
VERIFY_MD="$ROOT/commands/verify.md"
RESUME_MD="$ROOT/commands/resume.md"
DEVOPS_MD="$ROOT/agents/devops.md"
INIT_MD="$ROOT/commands/init.md"
SNIPPET="$ROOT/sdx/templates/claude-md-snippet.md"
DECISIONS="$ROOT/docs/DECISIONS.md"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# expect_ok / expect_red <label> <check-function> <file> — run the check on the real file
# (must pass) or on a damaged copy (must fail).
expect_ok() {
  local label="$1" fn="$2" file="$3" out
  if out="$("$fn" "$file")"; then pass "$label"; else fail "$label" "$out"; fi
}
expect_red() {
  local label="$1" fn="$2" file="$3"
  if "$fn" "$file" >/dev/null; then fail "$label" "check stayed green on a damaged copy"; else pass "$label"; fi
}

# ---- checks: print the reason to stdout and return 1 on violation -------------------------
chk_protocol_tags() {
  grep -q 'Восемь' "$1" || { echo "no 'Восемь' in $1"; return 1; }
  grep -q '\[директива\]' "$1" || { echo "no [директива] in $1"; return 1; }
  if grep -qiE 'семь(и)? тегов|из семи' "$1"; then echo "stale 'seven tags' wording in $1"; return 1; fi
  return 0
}
chk_next_directive() {
  grep -q '\[директива\]' "$1" || { echo "no [директива] in $1"; return 1; }
}
chk_no_tag_count() {  # commands that must not enumerate/count the tags (REQ-MO-PROTO-2)
  if grep -qiE '(семь|восемь|семи|восьми)[[:space:]]+(коротких[[:space:]]+)?тег|\[триаж\][[:space:]]*,[[:space:]]*`?\[' "$1"; then
    echo "tag count/enumeration in $1"; return 1
  fi
  return 0
}
chk_no_stale_phrases() {
  if grep -qF 'Пока `FEAT-015` не поставлена' "$1"; then echo "stale 'Пока FEAT-015 не поставлена'"; return 1; fi
  if grep -qF 'в текстах команд `/sdx:*` её тоже нет' "$1"; then echo "stale 'её тоже нет'"; return 1; fi
  return 0
}
chk_devops() {
  local f="$1" bad
  grep -qF '.mesh/endpoint.yaml' "$f" || { echo "no .mesh/endpoint.yaml in $f"; return 1; }
  grep -q 'mesh_endpoint\.py' "$f" || { echo "no mesh_endpoint.py invocation in $f"; return 1; }
  bad="$(grep 'mesh_endpoint\.py' "$f" | grep -v 'PYTHONDONTWRITEBYTECODE=1' || true)"
  [ -z "$bad" ] || { echo "mesh_endpoint.py without PYTHONDONTWRITEBYTECODE=1: $bad"; return 1; }
  return 0
}
chk_init_mesh() {
  grep -qE '^[[:space:]]*\.mesh/[[:space:]]*$' "$1" || { echo "no .mesh/ line in $1"; return 1; }
}
chk_snippet() {
  local block
  block="$(sed -n '/SDX:BEGIN/,/SDX:END/p' "$1")"
  printf '%s\n' "$block" | grep -qF 'МО над стендами' || { echo "no 'МО над стендами' inside SDX block"; return 1; }
  printf '%s\n' "$block" | grep -qF 'inbox --json' || { echo "no 'inbox --json' inside SDX block"; return 1; }
  return 0
}
chk_adr() {
  grep -q 'ADR-021' "$1" || { echo "no ADR-021 in $1"; return 1; }
}

echo "=== test-mo-prose.sh ==="
echo ""

echo "[1] protocol.md: eight tags incl. [директива], no 'seven tags'"
expect_ok "protocol.md" chk_protocol_tags "$PROTOCOL"
sed 's/Восемь/Семь/; s/\[директива\]/[x]/g' "$PROTOCOL" > "$TMP/p1.md"
expect_red "red: copy without Восемь/[директива]" chk_protocol_tags "$TMP/p1.md"
{ cat "$PROTOCOL"; echo 'один из семи тегов'; } > "$TMP/p2.md"
expect_red "red: copy with extra 'семи тегов'" chk_protocol_tags "$TMP/p2.md"

echo ""
echo "[2] commands/next.md step 2в names [директива]"
expect_ok "next.md" chk_next_directive "$NEXT_MD"
sed 's/\[директива\]/[x]/g' "$NEXT_MD" > "$TMP/n1.md"
expect_red "red: copy without [директива]" chk_next_directive "$TMP/n1.md"

echo ""
echo "[3] verify.md / resume.md carry no tag count or enumeration"
expect_ok "verify.md" chk_no_tag_count "$VERIFY_MD"
expect_ok "resume.md" chk_no_tag_count "$RESUME_MD"
{ cat "$VERIFY_MD"; echo 'Семь тегов'; } > "$TMP/v1.md"
expect_red "red: copy with 'Семь тегов'" chk_no_tag_count "$TMP/v1.md"

echo ""
echo "[4] protocol.md: stale vendored-components phrases are gone"
expect_ok "protocol.md" chk_no_stale_phrases "$PROTOCOL"
{ cat "$PROTOCOL"; echo 'Пока `FEAT-015` не поставлена, каталога нет'; } > "$TMP/s1.md"
expect_red "red: copy with 'Пока FEAT-015 не поставлена'" chk_no_stale_phrases "$TMP/s1.md"
{ cat "$PROTOCOL"; echo 'в текстах команд `/sdx:*` её тоже нет'; } > "$TMP/s2.md"
expect_red "red: copy with 'её тоже нет'" chk_no_stale_phrases "$TMP/s2.md"

echo ""
echo "[5] agents/devops.md: switch on .mesh/endpoint.yaml, every tool call has PYTHONDONTWRITEBYTECODE=1"
expect_ok "devops.md" chk_devops "$DEVOPS_MD"
{ cat "$DEVOPS_MD"; echo 'python3 sdx/mo/mesh_endpoint.py pull'; } > "$TMP/d1.md"
expect_red "red: copy with a flagless mesh_endpoint.py call" chk_devops "$TMP/d1.md"
grep -vF '.mesh/endpoint.yaml' "$DEVOPS_MD" > "$TMP/d2.md"
expect_red "red: copy without .mesh/endpoint.yaml" chk_devops "$TMP/d2.md"

echo ""
echo "[6] commands/init.md deploys the .mesh/ gitignore pattern"
expect_ok "init.md" chk_init_mesh "$INIT_MD"
grep -vE '^[[:space:]]*\.mesh/[[:space:]]*$' "$INIT_MD" > "$TMP/i1.md"
expect_red "red: copy without .mesh/" chk_init_mesh "$TMP/i1.md"

echo ""
echo "[7] CLAUDE.md snippet has the 'МО над стендами' item inside the SDX block"
expect_ok "snippet" chk_snippet "$SNIPPET"
grep -vF 'МО над стендами' "$SNIPPET" > "$TMP/c1.md"
expect_red "red: copy without the item" chk_snippet "$TMP/c1.md"

echo ""
echo "[8] docs/DECISIONS.md records ADR-021"
expect_ok "DECISIONS.md" chk_adr "$DECISIONS"
grep -v 'ADR-021' "$DECISIONS" > "$TMP/a1.md"
expect_red "red: copy without ADR-021" chk_adr "$TMP/a1.md"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
