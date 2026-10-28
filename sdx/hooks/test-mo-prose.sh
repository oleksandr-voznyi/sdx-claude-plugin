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
ARCHIVE_MD="$ROOT/commands/archive.md"
START_MD="$ROOT/commands/start.md"
DESIGN_MO="$ROOT/docs/designs/mo-interop.md"
README_RU="$ROOT/README.md"
README_EN="$ROOT/README.en.md"

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
chk_plugin_version() {
  local v; v="$(jq -r .version "$1" 2>/dev/null)"
  [ "$v" = "2.4.0" ] || { echo "plugin version is '$v', expected 2.4.0"; return 1; }
}

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
  # the paragraph on the oversight mechanism: "не в авторежиме" + `request` + `gate_mode: auto` on one line
  grep -F 'не в авторежиме' "$f" | grep -qF '`request`' || { echo "no paragraph with 'не в авторежиме' and request in $f"; return 1; }
  grep -F 'не в авторежиме' "$f" | grep -qF 'gate_mode: auto' || { echo "no paragraph with 'не в авторежиме' and 'gate_mode: auto' in $f"; return 1; }
  return 0
}
chk_protocol_deploy() {  # the "Deployment под МО" paragraph: a line naming both Deployment and artifact.offer
  grep -F 'Deployment' "$1" | grep -qF 'artifact.offer' || { echo "no line with 'Deployment' and 'artifact.offer' in $1"; return 1; }
}
chk_init_mesh() {
  grep -qE '^[[:space:]]*\.mesh/[[:space:]]*$' "$1" || { echo "no .mesh/ line in $1"; return 1; }
  grep -qF 'почтовый ящик мета-оркестратора (МО) — фенотип' "$1" || { echo "no comment 'почтовый ящик мета-оркестратора (МО) — фенотип' in $1"; return 1; }
}
chk_snippet() {
  local block
  block="$(sed -n '/SDX:BEGIN/,/SDX:END/p' "$1")"
  printf '%s\n' "$block" | grep -qF 'МО над стендами' || { echo "no 'МО над стендами' inside SDX block"; return 1; }
  printf '%s\n' "$block" | grep -qF 'inbox --json' || { echo "no 'inbox --json' inside SDX block"; return 1; }
  return 0
}
chk_adr() {
  grep -E '^## ADR-021\.' "$1" | grep -qF 'мета-оркестратор' || { echo "no heading '## ADR-021.' naming мета-оркестратор in $1"; return 1; }
}

# ---- FEAT-016 (mandate) checks -------------------------------------------------------------
adr_section() {  # adr_section <file> <ADR-NNN> — the body of one ADR (heading up to the next '## ')
  awk -v h="## $2." 'index($0, h) == 1 { p = 1; print; next } /^## / { p = 0 } p' "$1"
}
chk_two_signs() {  # the MO activation is "two signs" and mandate.yaml is named; the old "single sign" wording is gone
  grep -qF 'mandate.yaml' "$1" || { echo "no mandate.yaml in $1"; return 1; }
  grep -qE '(д|Д)ва признака|[Tt]wo (activation )?(signs|markers|criteria)' "$1" || { echo "no 'два признака' / 'two signs' in $1"; return 1; }
  if grep -qE '(е|Е)динственн(ый|ым) признак|([Ss]ingle|[Oo]nly) (activation )?(sign|marker|criterion)' "$1"; then echo "stale 'single sign' wording in $1"; return 1; fi
  return 0
}
chk_two_signs_adr() {  # ADR-021 only (point 3 of the decision)
  local t="$TMP/adr21.$$.md"
  adr_section "$1" ADR-021 > "$t"
  [ -s "$t" ] || { echo "no ADR-021 section in $1"; return 1; }
  chk_two_signs "$t"
}
chk_devops_mandate() {
  local f="$1" t
  chk_devops "$f" || return 1
  for t in 'mandate.yaml' 'scope.branches' 'теги' 'prod-guard'; do
    grep -qF "$t" "$f" || { echo "no '$t' in $f"; return 1; }
  done
  return 0
}
chk_snippet_mandate() {
  local f="$1" block n
  block="$(sed -n '/SDX:BEGIN/,/SDX:END/p' "$f")"
  n="$(printf '%s\n' "$block" | grep -cF '.mesh/mandate.yaml' || true)"
  [ "$n" = 1 ] || { echo "'.mesh/mandate.yaml' must occur on exactly one line of the SDX block, found $n"; return 1; }
  if grep -qE '/sdx:pr([^a-z]|$)' "$f"; then echo "/sdx:pr in $f"; return 1; fi  # not /sdx:proto
  [ "$(grep -c 'SDX:BEGIN' "$f")" = 1 ] && [ "$(grep -c 'SDX:END' "$f")" = 1 ] || { echo "SDX:BEGIN/SDX:END markers not exactly once in $f"; return 1; }
  return 0
}
chk_bridge() {  # Closeout bridge under a mandate (REQ-MAND-23, 23a)
  local f="$1" t
  for t in 'bridge' 'bridge:offer' '(n/a, мандат)' 'closeout-check' 'change/<C>-<exec>' 'undefined' 'docs_in_repo' '(n/a, docs_in_repo: none)'; do
    grep -qF -- "$t" "$f" || { echo "no '$t' in $f"; return 1; }
  done
  grep -F 'Ветка `sdx/<id>`' "$f" | grep -qF 'не слива' || { echo "no line saying branch sdx/<id> stays unmerged in $f"; return 1; }
  grep -F 'archive-verify.sh' "$f" | grep -qF 'не вызывается' || { echo "no line saying archive-verify.sh 'не вызывается' in $f"; return 1; }
  return 0
}
chk_verify_scope() {
  local f="$1" t
  for t in 'mandate-scope.sh' '--into' '--planned'; do
    grep -qF -- "$t" "$f" || { echo "no '$t' in $f"; return 1; }
  done
}
chk_start_mandate() {
  grep -qF 'mandate-info.sh" show' "$1" || grep -qF 'mandate-info.sh show' "$1" || { echo "no 'mandate-info.sh show' in $1"; return 1; }
  grep -qF 'start-stage' "$1" || { echo "no start-stage in $1"; return 1; }
}
chk_protocol_activity() {  # mandate = third narrowing source; Deployment excluded under a mandate; old [5b] paragraph kept
  grep -qF 'третий сужающий источник' "$1" || { echo "no 'третий сужающий источник' in $1"; return 1; }
  grep -F 'Deployment' "$1" | grep -F 'мандат' | grep -qE 'исключ' || { echo "no line with Deployment + мандат + исключ in $1"; return 1; }
  chk_protocol_deploy "$1"
}
chk_adr_amendments() {  # dated amendments to ADR-020 and ADR-021 by the mandate session
  local f="$1" a
  for a in ADR-020 ADR-021; do
    adr_section "$f" "$a" | grep -F 'Поправка 2026-10-28' | grep -qF 'feat-016-mo-mandate-20261028' || { echo "no dated amendment of $a by feat-016-mo-mandate-20261028 in $f"; return 1; }
  done
  adr_section "$f" ADR-020 | grep -qF 'третий сужающий источник' || { echo "ADR-020 amendment lacks 'третий сужающий источник'"; return 1; }
  return 0
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
sed 's/не в авторежиме/в любом режиме/g' "$DEVOPS_MD" > "$TMP/d3.md"
expect_red "red: copy without 'не в авторежиме'" chk_devops "$TMP/d3.md"
sed 's/`request`/запрос/g' "$DEVOPS_MD" > "$TMP/d4.md"
expect_red "red: copy without request" chk_devops "$TMP/d4.md"
sed 's/gate_mode: auto/режим x/g' "$DEVOPS_MD" > "$TMP/d5.md"
expect_red "red: copy without 'gate_mode: auto'" chk_devops "$TMP/d5.md"

echo ""
echo "[5b] protocol.md: the 'Deployment под МО' paragraph (Deployment + artifact.offer)"
expect_ok "protocol.md" chk_protocol_deploy "$PROTOCOL"
sed 's/artifact\.offer/offer-x/g' "$PROTOCOL" > "$TMP/p3.md"
expect_red "red: copy without artifact.offer" chk_protocol_deploy "$TMP/p3.md"
grep -vF 'Deployment' "$PROTOCOL" > "$TMP/p4.md"
expect_red "red: copy without any Deployment line" chk_protocol_deploy "$TMP/p4.md"

echo ""
echo "[6] commands/init.md deploys the .mesh/ gitignore pattern"
expect_ok "init.md" chk_init_mesh "$INIT_MD"
grep -vE '^[[:space:]]*\.mesh/[[:space:]]*$' "$INIT_MD" > "$TMP/i1.md"
expect_red "red: copy without .mesh/" chk_init_mesh "$TMP/i1.md"
grep -vF 'почтовый ящик мета-оркестратора (МО) — фенотип' "$INIT_MD" > "$TMP/i2.md"
expect_red "red: copy without the 'почтовый ящик мета-оркестратора (МО) — фенотип' comment" chk_init_mesh "$TMP/i2.md"

echo ""
echo "[7] CLAUDE.md snippet has the 'МО над стендами' item inside the SDX block"
expect_ok "snippet" chk_snippet "$SNIPPET"
grep -vF 'МО над стендами' "$SNIPPET" > "$TMP/c1.md"
expect_red "red: copy without the item" chk_snippet "$TMP/c1.md"

echo ""
echo "[8] docs/DECISIONS.md records ADR-021 as a heading naming the meta-orchestrator"
expect_ok "DECISIONS.md" chk_adr "$DECISIONS"
grep -v 'ADR-021' "$DECISIONS" > "$TMP/a1.md"
expect_red "red: copy without ADR-021" chk_adr "$TMP/a1.md"
sed 's/^## ADR-021\..*/## ADR-021. Интероп/' "$DECISIONS" > "$TMP/a2.md"
expect_red "red: ADR-021 heading without 'мета-оркестратор'" chk_adr "$TMP/a2.md"
{ grep -v '^## ADR-021\.' "$DECISIONS"; echo 'см. ADR-021, мета-оркестратор'; } > "$TMP/a3.md"
expect_red "red: bare ADR-021 mention is not the heading" chk_adr "$TMP/a3.md"

echo ""
echo "[9] two signs (endpoint.yaml + mandate.yaml): protocol, design, READMEs, ADR-021"
for pair in "protocol.md:$PROTOCOL" "designs/mo-interop.md:$DESIGN_MO" "README.md:$README_RU" "README.en.md:$README_EN"; do
  expect_ok "${pair%%:*}" chk_two_signs "${pair#*:}"
done
expect_ok "DECISIONS.md ADR-021" chk_two_signs_adr "$DECISIONS"
sed 's/mandate\.yaml/x.yaml/g' "$PROTOCOL" > "$TMP/t9a.md"
expect_red "red: protocol without mandate.yaml" chk_two_signs "$TMP/t9a.md"
{ cat "$README_RU"; echo 'единственный признак — endpoint.yaml'; } > "$TMP/t9b.md"
expect_red "red: README with 'единственный признак'" chk_two_signs "$TMP/t9b.md"
{ cat "$README_EN"; echo 'the only activation marker is endpoint.yaml'; } > "$TMP/t9c.md"
expect_red "red: README.en with 'only activation marker'" chk_two_signs "$TMP/t9c.md"
sed 's/два признака/один признак/g; s/Два признака/Один признак/g' "$DESIGN_MO" > "$TMP/t9d.md"
expect_red "red: design without 'два признака'" chk_two_signs "$TMP/t9d.md"
adr_section "$DECISIONS" ADR-021 | sed 's/два признака/один признак/g; s/Два признака/Один признак/g' > "$TMP/t9e.md"
{ echo '## ADR-021. x'; sed 1d "$TMP/t9e.md"; } > "$TMP/t9f.md"
expect_red "red: ADR-021 without 'два признака'" chk_two_signs_adr "$TMP/t9f.md"

echo ""
echo "[10] agents/devops.md: mandate mode (mandate.yaml, scope.branches, теги), endpoint switch kept"
expect_ok "devops.md" chk_devops_mandate "$DEVOPS_MD"
for t in 'mandate\.yaml' 'scope\.branches' 'теги' 'prod-guard'; do
  sed "s/$t/zz-removed/g" "$DEVOPS_MD" > "$TMP/t10.md"
  expect_red "red: devops without '$t'" chk_devops_mandate "$TMP/t10.md"
done
{ cat "$DEVOPS_MD"; echo 'python3 sdx/mo/mesh_endpoint.py pull'; } > "$TMP/t10b.md"
expect_red "red: flagless mesh_endpoint.py call" chk_devops_mandate "$TMP/t10b.md"

echo ""
echo "[11] CLAUDE.md snippet: one sentence on .mesh/mandate.yaml, no /sdx:pr, markers once"
expect_ok "snippet" chk_snippet_mandate "$SNIPPET"
grep -vF '.mesh/mandate.yaml' "$SNIPPET" > "$TMP/t11a.md"
expect_red "red: snippet without the mandate sentence" chk_snippet_mandate "$TMP/t11a.md"
{ cat "$SNIPPET"; echo 'см. /sdx:pr'; } > "$TMP/t11b.md"
expect_red "red: snippet with /sdx:pr" chk_snippet_mandate "$TMP/t11b.md"
sed 's/<!-- SDX:END/<!-- SDX:END2/' "$SNIPPET" | grep -v 'SDX:END2' > "$TMP/t11c.md"
expect_red "red: snippet without the SDX:END marker" chk_snippet_mandate "$TMP/t11c.md"
{ cat "$SNIPPET"; } | awk '{print} /\.mesh\/mandate\.yaml/ && !d {print "второй `.mesh/mandate.yaml`"; d=1}' > "$TMP/t11d.md"
expect_red "red: mandate sentence on two lines" chk_snippet_mandate "$TMP/t11d.md"

echo ""
echo "[12] Closeout bridge: commands/archive.md and protocol.md"
expect_ok "archive.md" chk_bridge "$ARCHIVE_MD"
expect_ok "protocol.md" chk_bridge "$PROTOCOL"
for t in 'bridge:offer' '(n/a, мандат)' 'closeout-check' 'change/<C>-<exec>' 'undefined' 'не вызывается' 'docs_in_repo' '(n/a, docs_in_repo: none)' 'Ветка `sdx/<id>`'; do
  for pair in "archive.md:$ARCHIVE_MD" "protocol.md:$PROTOCOL"; do
    grep -vF -- "$t" "${pair#*:}" > "$TMP/t12.md"
    expect_red "red: ${pair%%:*} without '$t'" chk_bridge "$TMP/t12.md"
  done
done

echo ""
echo "[13] commands/verify.md: step 6a calls mandate-scope.sh --into … --planned"
expect_ok "verify.md" chk_verify_scope "$VERIFY_MD"
for t in 'mandate-scope\.sh' '--into' '--planned'; do
  sed "s/$t/zz-removed/g" "$VERIFY_MD" > "$TMP/t13.md"
  expect_red "red: verify.md without '$t'" chk_verify_scope "$TMP/t13.md"
done

echo ""
echo "[14] commands/start.md: mandate-info.sh show, start-stage"
expect_ok "start.md" chk_start_mandate "$START_MD"
sed 's/mandate-info\.sh/zz-removed/g' "$START_MD" > "$TMP/t14a.md"
expect_red "red: start.md without mandate-info.sh" chk_start_mandate "$TMP/t14a.md"
sed 's/start-stage/zz-removed/g' "$START_MD" > "$TMP/t14b.md"
expect_red "red: start.md without start-stage" chk_start_mandate "$TMP/t14b.md"

echo ""
echo "[15] protocol.md: mandate is the third narrowing source; Deployment excluded under a mandate; artifact.offer paragraph kept"
expect_ok "protocol.md" chk_protocol_activity "$PROTOCOL"
sed 's/третий сужающий источник/источник/g' "$PROTOCOL" > "$TMP/t15a.md"
expect_red "red: protocol without 'третий сужающий источник'" chk_protocol_activity "$TMP/t15a.md"
sed '/Deployment/{/мандат/s/исключ/допущ/g;}' "$PROTOCOL" > "$TMP/t15b.md"
expect_red "red: protocol without Deployment-excluded-under-mandate line" chk_protocol_activity "$TMP/t15b.md"
sed 's/artifact\.offer/offer-x/g' "$PROTOCOL" > "$TMP/t15c.md"
expect_red "red: protocol without artifact.offer" chk_protocol_activity "$TMP/t15c.md"

echo ""
echo "[16] docs/DECISIONS.md: dated amendments of ADR-020 and ADR-021 by the mandate session"
expect_ok "DECISIONS.md" chk_adr_amendments "$DECISIONS"
sed 's/feat-016-mo-mandate-20261028/zz-session/g' "$DECISIONS" > "$TMP/t16a.md"
expect_red "red: amendments without the session id" chk_adr_amendments "$TMP/t16a.md"
awk '/^## ADR-020\./{p=1} /^## ADR-021\./{p=0} p && /Поправка 2026-10-28/ {gsub(/feat-016-mo-mandate-20261028/,"zz")} {print}' "$DECISIONS" > "$TMP/t16b.md"
expect_red "red: ADR-020 amendment missing" chk_adr_amendments "$TMP/t16b.md"
sed 's/третий сужающий источник/источник/g' "$DECISIONS" > "$TMP/t16c.md"
expect_red "red: ADR-020 amendment without 'третий сужающий источник'" chk_adr_amendments "$TMP/t16c.md"

echo ""
echo "[17] .claude-plugin/plugin.json: version 2.4.0"
expect_ok "plugin.json" chk_plugin_version "$ROOT/.claude-plugin/plugin.json"
sed 's/"version": "2\.4\.0"/"version": "2.3.1"/' "$ROOT/.claude-plugin/plugin.json" > "$TMP/t17.json"
expect_red "red: plugin.json with the old version" chk_plugin_version "$TMP/t17.json"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
