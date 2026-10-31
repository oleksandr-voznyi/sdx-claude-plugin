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
RECONCILE_MD="$ROOT/commands/reconcile.md"
STATUS_MD="$ROOT/commands/status.md"
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
  [ "$v" = "2.5.0" ] || { echo "plugin version is '$v', expected 2.5.0"; return 1; }
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
  printf '%s\n' "$block" | grep -qE '/sdx:pr([^a-z]|$)' || { echo "no /sdx:pr inside the SDX block of $f"; return 1; }  # not /sdx:proto (FEAT-017 pin)
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
chk_offer_once() {  # the offer is sent once: the bridge step is skipped when already sent (WARN-1, round 2)
  grep -F 'bridge:offer' "$1" | grep -qF 'уже отправлен' || { echo "no 'bridge:offer' line with 'уже отправлен' in $1"; return 1; }
}
chk_offer_once_devops() {  # devops.md: the Closeout-bridge sentence names the skip of an already sent offer
  grep -F 'bridge:offer' "$1" | grep -qF 'уже отправлен' || { echo "no 'bridge:offer' line with 'уже отправлен' in $1"; return 1; }
}
chk_no_old_bridge_phrase() {  # negative invariant: the bridge is not tied to 'delivery: pr|branch' only (FAIL-1, round 2)
  if grep -qF 'delivery: pr|branch' "$1"; then echo "stale 'delivery: pr|branch' in $1"; return 1; fi
  if grep -Eq 'artifact\.offer[^;.]{0,80}(штатн|standard)|Closeout (штатн|is the standard)' "$1"; then echo "stale 'artifact.offer ... standard Closeout' phrase in $1"; return 1; fi
  return 0
}
chk_offer_once_prose() {  # next.md / CLAUDE.md / ADR-020 amendment: a line naming the offer also names the skip of an already sent one (round 3)
  grep -F 'offer' "$1" | grep -qF 'уже отправлен' || { echo "no 'offer' line with 'уже отправлен' in $1"; return 1; }
}
chk_reconcile_wiring() {  # reconcile.md items (е)/(ж): the scripts are actually called (REQ-MAND-20, 25)
  local f="$1"
  grep -F '(е)' "$f" | grep -F 'suites-gen.sh' | grep -qF -- '--check' || { echo "no (е) line calling suites-gen.sh --check in $f"; return 1; }
  grep -F '(ж)' "$f" | grep -qF 'snippet-check.sh' || { echo "no (ж) line calling snippet-check.sh in $f"; return 1; }
}
chk_init_suites() {  # init.md step 2в calls suites-gen.sh
  grep -E '^2в\.' "$1" | grep -qF 'suites-gen.sh' || { echo "no step 2в calling suites-gen.sh in $1"; return 1; }
}
chk_status_mandate() {  # status.md step 5а: mandate-info.sh status + active-set, text matches the script output
  local l; l="$(grep -E '^5а\.' "$1")"
  [ -n "$l" ] || { echo "no step 5а in $1"; return 1; }
  for t in 'mandate-info.sh' 'status' 'sdx-stage.sh' 'active-set' 'endpoint.yaml=нет; mandate.yaml=нет' 'unknown:mandate'; do
    printf '%s' "$l" | grep -qF -- "$t" || { echo "step 5а lacks '$t' in $1"; return 1; }
  done
  # the first output word the prose promises must not be a phrase the script never prints
  printf '%s' "$l" | grep -qF 'печатает ту же строку' || { echo "step 5а does not say that the script prints the line itself in $1"; return 1; }
}
chk_next_mandate() {  # next.md: mandate narrows the target; refusal wording
  for t in 'Ограничение цели мандатом МО' 'mandate.stages' 'мандат МО исключает этап' 'не правь `.mesh/mandate.yaml`'; do
    grep -qF -- "$t" "$1" || { echo "no '$t' in $1"; return 1; }
  done
}
chk_verify_planned() {  # verify.md: the rule that computes --planned keys (REQ-MAND-14, К-3)
  local l; l="$(grep -F 'Правило `--planned`:' "$1")"
  [ -n "$l" ] || { echo "no 'Правило --planned' line in $1"; return 1; }
  for t in '`docs/specs/` — если в сессии есть `SPEC.md` или `change_note.md`' '`docs/designs/` — если есть `DESIGN.md`' '`docs/history/plans/` — если есть `PLAN.md`' '`docs/backlog/` — всегда' '`docs/DECISIONS.md`'; do
    printf '%s' "$l" | grep -qF -- "$t" || { echo "--planned rule lacks '$t' in $1"; return 1; }
  done
  printf '%s' "$l" | grep -qF 'docs_in_repo: none' || { echo "--planned rule lacks 'docs_in_repo: none' in $1"; return 1; }
  printf '%s' "$l" | grep -qF 'не передаются' || { echo "--planned rule lacks 'не передаются' in $1"; return 1; }
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

chk_bridge_archive() {  # [12] pin (FEAT-017): archive.md = chk_bridge + the bridge for pr|branch is a PACKAGE delegated to commands/pr.md
  local f="$1"
  chk_bridge "$f" || return 1
  grep -F 'commands/pr.md' "$f" | grep -F '(n/a, пакет)' | grep -qF 'не вызывается' || { echo "no bridge line with commands/pr.md + '(n/a, пакет)' + 'не вызывается' in $f"; return 1; }
}
chk_archive_pkg() {  # [19] archive.md: two Closeout variants, bridge delegates to /sdx:pr, the rest of the bridge and standard steps 1-8 intact
  local f="$1" t n
  chk_bridge_archive "$f" || return 1
  grep -qF 'два варианта' "$f" || { echo "no 'два варианта' in $f"; return 1; }
  grep -qF '„пакет“' "$f" || { echo "no '„пакет“' in $f"; return 1; }
  grep -F 'bridge:offer' "$f" | grep -qF '(n/a, мандат)' || { echo "no bridge:offer line with '(n/a, мандат)' in $f"; return 1; }
  grep -F 'bridge:offer' "$f" | grep -qF 'решение узла' || { echo "no bridge:offer line with 'решение узла' in $f"; return 1; }
  for t in 'пошаговую инструкцию ручной сборки' '(1) собрать squash-коммит'; do
    if grep -qF -- "$t" "$f"; then echo "stale manual 3-step instruction ('$t') in $f"; return 1; fi
  done
  for t in 'undefined:<delivery>' 'error:<причина>' '`standard`'; do
    grep -qF -- "$t" "$f" || { echo "no '$t' in $f"; return 1; }
  done
  for n in '1. Коммиты.' '2. Перенос дельт в постоянные документы.' '3. Архив плана.' '4. Глобальный лог знаний и бэклог.' '5. Удаление файлов сессии' '6. Резолв основной ветки и слияние.' '7. Enforcement-проверка закрытия.' '8. Финальная запись.'; do
    grep -qF -- "**$n" "$f" || { echo "standard step '$n' missing in $f"; return 1; }
  done
  grep -qF 'git merge --no-ff sdx/<session_id>' "$f" || { echo "no 'git merge --no-ff' in $f"; return 1; }
  grep -qF 'archive-verify.sh" <session_id>' "$f" || { echo "no archive-verify.sh call in $f"; return 1; }
}

# ---- FEAT-017 (T69): protocol, snippet = MO-INTEROP section 6, ADR-022, devops, surfaces, CONTRIBUTING-MO ----
chk_protocol_pkg() {  # [21] protocol.md: two Closeout variants (merge / package), bridge for pr|branch lifted, /sdx:pr scripts, journals
  local f="$1" t
  for t in 'два варианта' '„пакет“' 'pr-build.sh' 'pr-check.sh' 'pr-publish.sh' 'protocol-export.sh' 'order-import.sh' 'SDX-PR-' 'commitment' 'protocol.yaml' '--from-order' 'К-1)' 'К-17' 'формат A' 'формат B' 'full' 'CHANGE.template.yaml'; do
    grep -qF -- "$t" "$f" || { echo "no '$t' in $f"; return 1; }
  done
  grep -F 'bridge' "$f" | grep -F 'pr' | grep -F '/sdx:pr' | grep -qF 'пакет' || { echo "no bridge line saying pr|branch is delivered as a package by /sdx:pr in $f"; return 1; }
  for t in 'пользователь собирает вручную' 'до `/sdx:pr`, `FEAT-017`' 'названная временная граница'; do
    if grep -qF -- "$t" "$f"; then echo "stale temporary-bridge wording ('$t') in $f"; return 1; fi
  done
  chk_bridge "$f"
}
chk_snippet_interop() {  # [22] the SDX block of the snippet carries the text of section 6 of the vendored MO-INTEROP.md (quote lines joined by a space)
  local f="$1" sec6 block
  sec6="$(awk '/^## 6\./{p=1;next} /^## 7\./{p=0} p && /^> /{sub(/^> /,""); printf "%s%s", (n++ ? " " : ""), $0}' "$ROOT/sdx/mo/MO-INTEROP.md")"
  [ -n "$sec6" ] || { echo "section 6 of MO-INTEROP.md not found"; return 1; }
  block="$(sed -n '/SDX:BEGIN/,/SDX:END/p' "$f")"
  printf '%s\n' "$block" | grep -qF -- "$sec6" || { echo "the SDX block of $f does not contain the text of section 6 of MO-INTEROP.md"; return 1; }
  printf '%s\n' "$block" | grep -qE '/sdx:pr([^a-z]|$)' || { echo "no /sdx:pr in the SDX block of $f"; return 1; }
}
chk_adr22() {  # [23] ADR-022 heading + body terms; ADR-021 carries a dated note about lifting the bridge
  local f="$1" t
  grep -E '^## ADR-022\.' "$f" | grep -qF 'Пакет изменения' || { echo "no heading '## ADR-022.' naming 'Пакет изменения' in $f"; return 1; }
  for t in 'CHANGE.template.yaml' 'Closeout' 'feat-017-mo-change-package-20261031'; do
    adr_section "$f" ADR-022 | grep -qF -- "$t" || { echo "ADR-022 lacks '$t' in $f"; return 1; }
  done
  adr_section "$f" ADR-021 | grep -F 'Поправка 2026-10-31' | grep -qF 'feat-017-mo-change-package-20261031' || { echo "no dated amendment (2026-10-31, feat-017) of ADR-021 in $f"; return 1; }
}
chk_devops_pkg() {  # [24] devops.md: mandate rules kept + /sdx:pr is the delivery action (not devops), no merges / tags, CHANGE.template.yaml; frontmatter intact
  local f="$1" t
  chk_devops_mandate "$f" || return 1
  for t in '/sdx:pr' 'CHANGE.template.yaml' 'name: devops' 'model: sonnet' 'tools: Read, Write, Edit, Glob, Grep, Bash'; do
    grep -qF -- "$t" "$f" || { echo "no '$t' in $f"; return 1; }
  done
  [ "$(sed -n 1p "$f")" = '---' ] && [ "$(sed -n 6p "$f")" = '---' ] || { echo "frontmatter of $f is not lines 1-6"; return 1; }
}
chk_surface_pkg() {  # [25] README x2 and CLAUDE.md name the new surface
  local f="$1" t
  for t in 'CHANGE.template.yaml' 'pr-build.sh' 'CONTRIBUTING-MO.md' '2.5.0' '/sdx:pr' 'mesh_endpoint.py' 'devagent_hook.py' 'MO-INTEROP.md'; do
    grep -qF -- "$t" "$f" || { echo "no '$t' in $f"; return 1; }
  done
}
chk_contributing() {  # [27] <root>: CONTRIBUTING-MO.md is a template of the plugin, not a vendored file
  [ -f "$1/sdx/templates/CONTRIBUTING-MO.md" ] || { echo "no sdx/templates/CONTRIBUTING-MO.md in $1"; return 1; }
  [ ! -e "$1/sdx/mo/CONTRIBUTING-MO.md" ] || { echo "CONTRIBUTING-MO.md sits in sdx/mo/ of $1"; return 1; }
}

PR_REFUSE='/sdx:pr: нужен режим мандата МО (.mesh/endpoint.yaml и .mesh/mandate.yaml); без него сдача пакетом неприменима — закрывайте сессию через /sdx:archive.'
chk_pr_head() {
  local f="$1" t
  [ "$(sed -n 1p "$f")" = '---' ] || { echo "no frontmatter in $f"; return 1; }
  sed -n 2,6p "$f" | grep -q '^description: ' || { echo "no description in $f"; return 1; }
  sed -n 2,6p "$f" | grep -qF 'argument-hint: [<C>] [--title "<заголовок>"] [--resubmit] [--build-only]' || { echo "no argument-hint in $f"; return 1; }
}
chk_pr_calls() {  # the pipeline names every script and the confirmation contract
  local f="$1" t
  for t in 'pr-check.sh' 'pr-build.sh' 'pr-publish.sh' 'protocol-export.sh' 'mandate-info.sh' 'pr-mode' 'AskUserQuestion' 'в любом `gate_mode`' '[контракт]' '--phase pre' '--phase post' 'SDX-PR-Branch' 'SDX-PR-Confirmed' 'git commit --allow-empty -F -' '600000'; do
    grep -qF -- "$t" "$f" || { echo "no '$t' in $f"; return 1; }
  done
}
# verify-1 FAIL-1: every pr-check.sh call in pr.md carries both --commitment and --title (without an order they are the only source)
chk_pr_carry() {
  local f="$1" s seg n=0
  while IFS="$(printf '\t')" read -r s seg; do
    [ "$s" = pr-check.sh ] || continue
    n=$((n + 1))
    case "$seg" in *--commitment*) ;; *) echo "a pr-check.sh call without --commitment in $f: $seg"; return 1 ;; esac
    case "$seg" in *--title*) ;; *) echo "a pr-check.sh call without --title in $f: $seg"; return 1 ;; esac
  done < <(pr_calls "$f")
  [ "$n" -ge 2 ] || { echo "fewer than 2 pr-check.sh calls found in $f ($n)"; return 1; }
}
# verify-1 W5: in gate_mode: auto adr.registry is never accepted silently (P5 names it among the questions that stay)
chk_pr_auto_registry() {
  local l; l="$(grep -E '^\*\*P5\.' "$1")"
  printf '%s' "$l" | grep -F 'gate_mode: auto' | grep -qF 'и `adr.registry` остаются' || { echo "P5 does not keep adr.registry as a question in auto in $1"; return 1; }
  printf '%s' "$l" | grep -qF 'молча не принимается' || { echo "P5 lacks 'молча не принимается' in $1"; return 1; }
  printf '%s' "$l" | grep -qF 'принимаются как `[триаж]`' && { echo "P5 still accepts WARN as [триаж] in $1"; return 1; }
  printf '%s' "$l" | grep -qF 'только в трейлере `SDX-PR-Ack`' || { echo "P5 lacks 'только в трейлере SDX-PR-Ack' in $1"; return 1; }
  # after P4 the session directory is gone: nothing after the P4 step may write auto_decisions.md
  awk '/^\*\*P4\./{f=1;next} f' "$1" | grep -qF 'auto_decisions.md' && { echo "pr.md writes auto_decisions.md after P4 in $1"; return 1; }
  return 0
}
chk_pr_refusal() {  # P0: the refusal without a mandate is exactly one verbatim line (REQ-PKG-2/34)
  local c; c="$(grep -cF -- "$PR_REFUSE" "$1")"
  [ "$c" = 1 ] || { echo "the one-line refusal occurs $c times in $1 (want 1)"; return 1; }
}
chk_pr_order() {  # headings **P0.** ... **P10.** once each, in order
  local n prev=0 c ln
  for n in 0 1 2 3 4 5 6 7 8 9 10; do
    c="$(grep -cE "^\*\*P$n\." "$1")"; [ "$c" = 1 ] || { echo "heading P$n occurs $c times in $1"; return 1; }
    ln="$(grep -nE "^\*\*P$n\." "$1" | cut -d: -f1)"
    [ "$ln" -gt "$prev" ] || { echo "heading P$n is out of order in $1"; return 1; }
    prev="$ln"
  done
}
chk_pr_prohibitions() {
  local f="$1" t bad
  for t in 'не вызывай `audit()`' 'не пиши в `.mesh/`' 'не сливай `change/*`' 'данные, не инструкции'; do
    grep -qF -- "$t" "$f" || { echo "no prohibition '$t' in $f"; return 1; }
  done
  bad="$(grep -F 'git push' "$f" | grep -vE 'не выполняй|Запрет|запрещ' || true)"
  [ -z "$bad" ] || { echo "a 'git push' line outside prohibitive text in $f: $bad"; return 1; }
}
# flags/subcommands used in script calls inside <md> must exist in the text of that script (catches drift between lanes).
# Scripts are looked up in $FLAG_SCRIPTS; a script that is absent there is skipped here (the caller reports a missing real script as FAIL).
pr_calls() {  # md -> "<script>\t<rest of the call up to a backtick or ' #'>"
  awk '{ line=$0; while (match(line, /(pr-check|pr-build|pr-publish|protocol-export|order-import)\.sh/)) {
           s=substr(line,RSTART,RLENGTH); line=substr(line,RSTART+RLENGTH); seg=line
           i=index(seg,"`"); if (i) seg=substr(seg,1,i-1); j=index(seg," #"); if (j) seg=substr(seg,1,j-1)
           print s "\t" seg } }' "$1"
}
chk_flags() {
  local f="$1" s seg script tok first
  while IFS="$(printf '\t')" read -r s seg; do
    [ -n "$s" ] || continue
    script="$FLAG_SCRIPTS/$s"
    [ -f "$script" ] || continue
    for tok in $(printf '%s' "$seg" | grep -oE -- '--[a-z][a-z-]*'); do
      grep -qF -- "$tok" "$script" || { echo "$s: flag $tok used in $f is absent from the script"; return 1; }
    done
    first="$(printf '%s' "$seg" | sed 's/^"//; s/^[[:space:]]*//' | cut -d' ' -f1)"
    case "$first" in ""|--*|'['*|'<'*|')'*|'|'*|'&'*|';'*) ;; [a-z]*-[a-z]*) grep -qF -- "$first" "$script" || { echo "$s: subcommand $first used in $f is absent from the script"; return 1; } ;; esac
  done < <(pr_calls "$f")
}
chk_start_order() {  # start.md (FEAT-017): --from-order / --from-issue, step 1б, stamp-state; steps 1-8 intact
  local f="$1" t n
  sed -n 1,4p "$f" | grep -qF 'argument-hint: <type> <goal> [--auto] [--from-order <order.yaml|msg_id>] [--from-issue <N>]' || { echo "no new argument-hint in $f"; return 1; }
  for t in '--from-order' '--from-issue' 'order-import.sh' 'stamp-state' 'sid_infix' 'from-file' 'from-msg' 'from-issue' 'MISMATCH' 'AskUserQuestion' 'repo.base' 'pr-mode' 'order.yaml' 'commitment'; do
    grep -qF -- "$t" "$f" || { echo "no '$t' in $f"; return 1; }
  done
  blk="$(awk '/^1б\./{p=1;print;next} p && /^[0-9]/{p=0} p' "$f")"
  printf "%s" "$blk" | grep -qF AskUserQuestion || { echo "step 1б lacks AskUserQuestion in $f"; return 1; }
  printf "%s" "$blk" | grep -qF 'в любом `gate_mode`' || { echo "step 1б lacks в любом gate_mode in $f"; return 1; }
  # verify-1 W4: --from-order in gate_mode: auto is a [директива] stop (AskUserQuestion), like --from-issue
  printf "%s" "$blk" | grep -F -- '--from-order' | grep -F 'gate_mode: auto' | grep -F '[директива]' | grep -qF 'AskUserQuestion' || { echo "step 1б lacks the auto + --from-order [директива] stop in $f"; return 1; }
  for n in '1' '2' '3' '4' '5' '6' '7' '8'; do
    grep -qE "^$n\. " "$f" || { echo "step $n missing in $f"; return 1; }
  done
  chk_start_mandate "$f"
}
chk_status_pkg() {  # status.md (FEAT-017): commitment in step 3, step 5б reads pr-status, stays read-only
  local f="$1" l
  l="$(grep -E '^5б\.' "$f")"
  [ -n "$l" ] || { echo "no step 5б in $f"; return 1; }
  for t in 'mandate-info.sh' 'pr-status' 'каталог сессии удалён' 'Чисто читающий'; do
    printf '%s' "$l" | grep -qF -- "$t" || { echo "step 5б lacks '$t' in $f"; return 1; }
  done
  grep -F '**Session ID**' "$f" | grep -qF 'commitment' || { echo "step 3 lacks commitment in $f"; return 1; }
  if sed -n '/^---$/,/^---$/p' "$f" | grep -q '^tools:'; then echo "status.md must not declare tools"; return 1; fi
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
echo "[11] CLAUDE.md snippet: one sentence on .mesh/mandate.yaml, /sdx:pr named (FEAT-017), markers once"
expect_ok "snippet" chk_snippet_mandate "$SNIPPET"
grep -vF '.mesh/mandate.yaml' "$SNIPPET" > "$TMP/t11a.md"
expect_red "red: snippet without the mandate sentence" chk_snippet_mandate "$TMP/t11a.md"
sed 's#/sdx:pr#/sdx:zz#g' "$SNIPPET" > "$TMP/t11b.md"
expect_red "red: snippet without /sdx:pr" chk_snippet_mandate "$TMP/t11b.md"
sed 's/<!-- SDX:END/<!-- SDX:END2/' "$SNIPPET" | grep -v 'SDX:END2' > "$TMP/t11c.md"
expect_red "red: snippet without the SDX:END marker" chk_snippet_mandate "$TMP/t11c.md"
{ cat "$SNIPPET"; } | awk '{print} /\.mesh\/mandate\.yaml/ && !d {print "второй `.mesh/mandate.yaml`"; d=1}' > "$TMP/t11d.md"
expect_red "red: mandate sentence on two lines" chk_snippet_mandate "$TMP/t11d.md"

echo ""
echo "[12] Closeout bridge: commands/archive.md and protocol.md"
expect_ok "archive.md" chk_bridge_archive "$ARCHIVE_MD"
expect_ok "protocol.md" chk_bridge "$PROTOCOL"
for t in 'bridge:offer' '(n/a, мандат)' 'closeout-check' 'change/<C>-<exec>' 'undefined' 'не вызывается' 'docs_in_repo' '(n/a, docs_in_repo: none)' 'Ветка `sdx/<id>`'; do
  for pair in "archive.md:$ARCHIVE_MD" "protocol.md:$PROTOCOL"; do
    grep -vF -- "$t" "${pair#*:}" > "$TMP/t12.md"
    if [ "${pair%%:*}" = archive.md ]; then bfn=chk_bridge_archive; else bfn=chk_bridge; fi
    expect_red "red: ${pair%%:*} without '$t'" "$bfn" "$TMP/t12.md"
  done
done

echo ""
echo "[12b] offer sent once (archive.md, protocol.md, devops.md); no stale 'delivery: pr|branch' bridge phrase"
expect_ok "archive.md offer once" chk_offer_once "$ARCHIVE_MD"
expect_ok "protocol.md offer once" chk_offer_once "$PROTOCOL"
sed 's/уже отправлен/zz-removed/g' "$ARCHIVE_MD" > "$TMP/t12b.md"; expect_red "red: archive.md without 'уже отправлен'" chk_offer_once "$TMP/t12b.md"
sed 's/уже отправлен/zz-removed/g' "$PROTOCOL" > "$TMP/t12c.md"; expect_red "red: protocol.md without 'уже отправлен'" chk_offer_once "$TMP/t12c.md"
expect_ok "devops.md offer once" chk_offer_once_devops "$DEVOPS_MD"
sed 's/уже отправлен/zz-removed/g' "$DEVOPS_MD" > "$TMP/t12e.md"; expect_red "red: devops.md without 'уже отправлен'" chk_offer_once_devops "$TMP/t12e.md"
adr_section "$DECISIONS" ADR-020 > "$TMP/adr020.md"
CLAUDE_MD="$ROOT/CLAUDE.md"
for pair in "next.md:$NEXT_MD" "CLAUDE.md:$CLAUDE_MD" "ADR-020:$TMP/adr020.md"; do
  expect_ok "${pair%%:*} offer once" chk_offer_once_prose "${pair#*:}"
  sed 's/уже отправлен/zz-removed/g' "${pair#*:}" > "$TMP/t12f.md"
  expect_red "red: ${pair%%:*} without 'уже отправлен'" chk_offer_once_prose "$TMP/t12f.md"
done
adr_section "$DECISIONS" ADR-021 > "$TMP/adr021.md"
for pair in "protocol.md:$PROTOCOL" "ADR-021:$TMP/adr021.md" "README.md:$README_RU" "README.en.md:$README_EN" "archive.md:$ARCHIVE_MD" "devops.md:$DEVOPS_MD"; do
  expect_ok "no stale phrase in ${pair%%:*}" chk_no_old_bridge_phrase "${pair#*:}"
  { cat "${pair#*:}"; echo 'Closeout при `delivery: pr|branch` — мост'; } > "$TMP/t12d.md"
  expect_red "red: ${pair%%:*} with stale 'delivery: pr|branch'" chk_no_old_bridge_phrase "$TMP/t12d.md"
  { cat "${pair#*:}"; echo 'При `artifact.offer` Closeout штатный.'; } > "$TMP/t12g.md"
  expect_red "red: ${pair%%:*} with stale 'artifact.offer Closeout штатный'" chk_no_old_bridge_phrase "$TMP/t12g.md"
  { cat "${pair#*:}"; echo 'With artifact.offer Closeout is the standard one.'; } > "$TMP/t12h.md"
  expect_red "red: ${pair%%:*} with stale 'standard one'" chk_no_old_bridge_phrase "$TMP/t12h.md"
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
echo "[17] .claude-plugin/plugin.json: version 2.5.0"
expect_ok "plugin.json" chk_plugin_version "$ROOT/.claude-plugin/plugin.json"
sed 's/"version": "2\.5\.0"/"version": "2.4.0"/' "$ROOT/.claude-plugin/plugin.json" > "$TMP/t17.json"
expect_red "red: plugin.json with the old version" chk_plugin_version "$TMP/t17.json"

echo ""
echo "[18] wiring prose: reconcile.md (е)/(ж), init.md 2в, status.md 5а, next.md, verify.md --planned rule"
expect_ok "reconcile.md" chk_reconcile_wiring "$RECONCILE_MD"
sed 's/suites-gen\.sh/zz-removed/g' "$RECONCILE_MD" > "$TMP/t18a.md"; expect_red "red: reconcile.md without suites-gen.sh" chk_reconcile_wiring "$TMP/t18a.md"
sed 's/snippet-check\.sh/zz-removed/g' "$RECONCILE_MD" > "$TMP/t18b.md"; expect_red "red: reconcile.md without snippet-check.sh" chk_reconcile_wiring "$TMP/t18b.md"
sed 's/--check/zz-removed/g' "$RECONCILE_MD" > "$TMP/t18c.md"; expect_red "red: reconcile.md without --check" chk_reconcile_wiring "$TMP/t18c.md"
expect_ok "init.md 2в" chk_init_suites "$INIT_MD"
sed 's/suites-gen\.sh/zz-removed/g' "$INIT_MD" > "$TMP/t18d.md"; expect_red "red: init.md without suites-gen.sh" chk_init_suites "$TMP/t18d.md"
expect_ok "status.md 5а" chk_status_mandate "$STATUS_MD"
for t in 'mandate-info\.sh' 'active-set' 'unknown:mandate' 'endpoint\.yaml=нет; mandate\.yaml=нет' 'печатает ту же строку'; do
  sed "s/$t/zz-removed/g" "$STATUS_MD" > "$TMP/t18e.md"; expect_red "red: status.md without '$t'" chk_status_mandate "$TMP/t18e.md"
done
expect_ok "next.md" chk_next_mandate "$NEXT_MD"
for t in 'Ограничение цели мандатом МО' 'mandate\.stages' 'мандат МО исключает этап' 'не правь `\.mesh\/mandate\.yaml`'; do
  sed "s/$t/zz-removed/g" "$NEXT_MD" > "$TMP/t18f.md"; expect_red "red: next.md without '$t'" chk_next_mandate "$TMP/t18f.md"
done
expect_ok "verify.md --planned rule" chk_verify_planned "$VERIFY_MD"
for t in 'если в сессии есть `SPEC.md` или `change_note.md`' 'если есть `DESIGN.md`' 'если есть `PLAN.md`' '`docs\/backlog\/` — всегда' '`docs\/DECISIONS.md`' 'docs_in_repo: none' 'не передаются'; do
  sed "s/$t/zz-removed/g" "$VERIFY_MD" > "$TMP/t18g.md"; expect_red "red: verify.md --planned rule without '$t'" chk_verify_planned "$TMP/t18g.md"
done


echo ""
echo "[19] commands/archive.md: two Closeout variants, the bridge delegates to /sdx:pr (REQ-PKG-1, 26, 30)"
expect_ok "archive.md" chk_archive_pkg "$ARCHIVE_MD"
for t in 'commands/pr.md' '(n/a, пакет)' 'два варианта' '„пакет“' 'решение узла' '(n/a, мандат)' 'undefined:<delivery>' 'error:<причина>' '**3. Архив плана.' '**6. Резолв основной ветки и слияние.' 'git merge --no-ff sdx/<session_id>' 'archive-verify.sh" <session_id>'; do
  grep -vF -- "$t" "$ARCHIVE_MD" > "$TMP/t19.md"
  expect_red "red: archive.md without '$t'" chk_archive_pkg "$TMP/t19.md"
done
{ cat "$ARCHIVE_MD"; echo 'Пользователю выведи пошаговую инструкцию ручной сборки пакета: (1) собрать squash-коммит'; } > "$TMP/t19b.md"
expect_red "red: archive.md with the old manual instruction" chk_archive_pkg "$TMP/t19b.md"

echo ""
echo "[20] commands/pr.md: pipeline P0..P10, scripts, confirmation in any gate_mode, prohibitions, flags match the scripts (REQ-PKG-1, 2, 3, 13, 17, 35)"
PR_MD="$ROOT/commands/pr.md"
expect_ok "pr.md frontmatter" chk_pr_head "$PR_MD"
expect_ok "pr.md calls and contract" chk_pr_calls "$PR_MD"
expect_ok "pr.md one-line refusal (P0)" chk_pr_refusal "$PR_MD"
expect_ok "pr.md every pr-check call carries --commitment and --title" chk_pr_carry "$PR_MD"
sed '/^\*\*P7\./s/ \[--commitment <C>\] \[--title "<T>"\]` (те/` (те/' "$PR_MD" > "$TMP/t20k.md"
expect_red "red: pr.md P7 pr-check post without --commitment/--title" chk_pr_carry "$TMP/t20k.md"
sed '/^\*\*P7\./s/ \[--title "<T>"\]` (те/` (те/' "$PR_MD" > "$TMP/t20k2.md"
expect_red "red: pr.md P7 pr-check post without --title" chk_pr_carry "$TMP/t20k2.md"
expect_ok "pr.md P5 keeps adr.registry as a question in auto" chk_pr_auto_registry "$PR_MD"
sed '/^\*\*P5\./s/ и `adr.registry` остаются/ остаются/' "$PR_MD" > "$TMP/t20l.md"
expect_red "red: pr.md P5 without adr.registry among the auto questions" chk_pr_auto_registry "$TMP/t20l.md"
sed '/^\*\*P5\./s/молча не принимается/принимается/' "$PR_MD" > "$TMP/t20m.md"
expect_red "red: pr.md P5 without 'молча не принимается'" chk_pr_auto_registry "$TMP/t20m.md"
sed '/^\*\*P5\./s/Журнал авторежима сессии вести негде/Запись в `auto_decisions.md`/' "$PR_MD" > "$TMP/t20n.md"
expect_red "red: pr.md P5 writes auto_decisions.md after P4" chk_pr_auto_registry "$TMP/t20n.md"
sed '/^\*\*P5\./s/только в трейлере `SDX-PR-Ack`/в трейлере/' "$PR_MD" > "$TMP/t20o.md"
expect_red "red: pr.md P5 without 'только в трейлере SDX-PR-Ack'" chk_pr_auto_registry "$TMP/t20o.md"
expect_ok "pr.md order P0..P10" chk_pr_order "$PR_MD"
expect_ok "pr.md prohibitions, no bare git push" chk_pr_prohibitions "$PR_MD"
sed '1,5{/^argument-hint:/d;}' "$PR_MD" > "$TMP/t20a.md"; expect_red "red: pr.md without argument-hint" chk_pr_head "$TMP/t20a.md"
for t in 'pr-check.sh' 'pr-build.sh' 'pr-publish.sh' 'protocol-export.sh' 'pr-mode' 'AskUserQuestion' 'в любом `gate_mode`' '[контракт]' '--phase post' 'SDX-PR-Confirmed' 'git commit --allow-empty -F -'; do
  sed "s/$(printf '%s' "$t" | sed 's/[][\.*^$/]/\\&/g')/zz-removed/g" "$PR_MD" > "$TMP/t20b.md"
  expect_red "red: pr.md without '$t'" chk_pr_calls "$TMP/t20b.md"
done
sed 's/нужен режим мандата МО/zz-removed/' "$PR_MD" > "$TMP/t20c.md"; expect_red "red: pr.md with a changed refusal line" chk_pr_refusal "$TMP/t20c.md"
{ cat "$PR_MD"; echo "$PR_REFUSE"; } > "$TMP/t20d.md"; expect_red "red: pr.md with the refusal twice" chk_pr_refusal "$TMP/t20d.md"
sed -e 's/^\*\*P5\./**PX./' -e 's/^\*\*P6\./**P5./' -e 's/^\*\*PX\./**P6./' "$PR_MD" > "$TMP/t20e.md"; expect_red "red: pr.md with P5/P6 swapped" chk_pr_order "$TMP/t20e.md"
grep -vE '^\*\*P8\.' "$PR_MD" > "$TMP/t20f.md"; expect_red "red: pr.md without P8" chk_pr_order "$TMP/t20f.md"
{ cat "$PR_MD"; echo '    git push origin change/C-1-ex1'; } > "$TMP/t20g.md"; expect_red "red: pr.md with a bare git push" chk_pr_prohibitions "$TMP/t20g.md"
for t in 'не вызывай `audit()`' 'не пиши в `.mesh/`' 'не сливай `change/*`'; do
  sed "s/$(printf '%s' "$t" | sed 's/[][\.*^$/]/\\&/g')/zz-removed/g" "$PR_MD" > "$TMP/t20h.md"; expect_red "red: pr.md without '$t'" chk_pr_prohibitions "$TMP/t20h.md"
done
# flag consistency. Fixture: stubs carrying exactly the CLI of DESIGN (green side independent of the parallel lanes) ...
FX="$TMP/flagfx"; mkdir -p "$FX"
echo '# --sid --proj --phase --commitment --title --base-name --no-tests pre post all' > "$FX/pr-check.sh"
echo '# --sid --proj --commitment --title --base-name --allow-diverged --resubmit --notes' > "$FX/pr-build.sh"
echo '# --sid --proj --commitment --title --base-name --remote --hosting --dry-run' > "$FX/pr-publish.sh"
echo '# --sid --proj --out --from-rev' > "$FX/protocol-export.sh"
echo '# from-file from-msg from-issue list stamp-state --proj --out --inbox-json --repo --sid --commitment' > "$FX/order-import.sh"
for md in "$PR_MD" "$START_MD"; do
  FLAG_SCRIPTS="$FX" expect_ok "$(basename "$md"): every script flag exists in the DESIGN CLI (fixture)" chk_flags "$md"
done
{ cat "$PR_MD"; echo '`bash "${CLAUDE_PLUGIN_ROOT}/sdx/hooks/pr-build.sh" --sid x --zz-bogus`'; } > "$TMP/t20i.md"
FLAG_SCRIPTS="$FX" expect_red "red: pr.md with a flag no script knows" chk_flags "$TMP/t20i.md"
sed 's/--allow-diverged//' "$FX/pr-build.sh" > "$TMP/pr-build.sh"; mkdir -p "$TMP/flagfx2"; cp "$FX"/*.sh "$TMP/flagfx2/"; cp "$TMP/pr-build.sh" "$TMP/flagfx2/pr-build.sh"
FLAG_SCRIPTS="$TMP/flagfx2" expect_red "red: a script that dropped --allow-diverged (drift between lanes)" chk_flags "$PR_MD"
{ cat "$START_MD"; echo '`bash "${CLAUDE_PLUGIN_ROOT}/sdx/hooks/order-import.sh" from-nowhere x`'; } > "$TMP/t20j.md"
FLAG_SCRIPTS="$FX" expect_red "red: start.md with an unknown order-import subcommand" chk_flags "$TMP/t20j.md"
# ... and against the real scripts: a script called by the command but absent from sdx/hooks/ is a failure
for md in "$PR_MD" "$START_MD"; do
  have=""; for s in pr-check pr-build pr-publish protocol-export order-import; do
    if pr_calls "$md" | grep -q "^$s.sh"; then
      if [ -f "$SCRIPT_DIR/$s.sh" ]; then have="$have $s"; else fail "$(basename "$md"): $s.sh is called but missing" "no sdx/hooks/$s.sh"; fi
    fi
  done
  if [ -n "$have" ]; then FLAG_SCRIPTS="$SCRIPT_DIR" expect_ok "$(basename "$md"): flags of${have} match the real scripts" chk_flags "$md"; fi
done

echo ""
echo "[26] commands/start.md (--from-order, --from-issue, step 1б, stamp-state) and commands/status.md (commitment, step 5б pr-status)"
expect_ok "start.md" chk_start_order "$START_MD"
for t in '--from-order' '--from-issue' 'stamp-state' 'sid_infix' 'MISMATCH' 'repo.base' 'pr-mode' 'order.yaml'; do
  sed "s/$t/zz-removed/g" "$START_MD" > "$TMP/t26a.md"; expect_red "red: start.md without '$t'" chk_start_order "$TMP/t26a.md"
done
sed 's/^   - (iii-а) При `gate_mode: auto` приём заказа через `--from-order`/   - (iii-а) При другом режиме приём через `--from-order`/' "$START_MD" > "$TMP/t26f.md"
expect_red "red: start.md without the auto + --from-order [директива] stop" chk_start_order "$TMP/t26f.md"
sed 's/^1б\./1x./' "$START_MD" > "$TMP/t26b.md"; expect_red "red: start.md without step 1б" chk_start_order "$TMP/t26b.md"
sed 's/^3\. /3x. /' "$START_MD" > "$TMP/t26c.md"; expect_red "red: start.md without step 3" chk_start_order "$TMP/t26c.md"
expect_ok "status.md" chk_status_pkg "$STATUS_MD"
for t in 'pr-status' 'каталог сессии удалён' 'commitment' '^5б\.'; do
  sed "s/$t/zz-removed/g" "$STATUS_MD" > "$TMP/t26d.md"; expect_red "red: status.md without '$t'" chk_status_pkg "$TMP/t26d.md"
done

sed '1a tools: Write' "$STATUS_MD" > "$TMP/t26e.md"
expect_red "red: status.md declaring write tools" chk_status_pkg "$TMP/t26e.md"
echo ""
echo "[21] protocol.md: two Closeout variants, the FEAT-016 bridge for pr|branch lifted, /sdx:pr scripts, journals (REQ-PKG-22, 30, 33)"
expect_ok "protocol.md" chk_protocol_pkg "$PROTOCOL"
for t in 'два варианта' '„пакет“' 'pr-build.sh' 'pr-check.sh' 'pr-publish.sh' 'protocol-export.sh' 'order-import.sh' 'SDX-PR-' 'commitment' 'protocol.yaml' '--from-order' 'К-17' 'формат A' 'формат B' 'CHANGE.template.yaml'; do
  sed "s/$(printf '%s' "$t" | sed 's/[][\.*^$/]/\\&/g')/zz-removed/g" "$PROTOCOL" > "$TMP/t21.md"
  expect_red "red: protocol.md without '$t'" chk_protocol_pkg "$TMP/t21.md"
done
{ cat "$PROTOCOL"; echo 'Пакет `change/<C>-<exec>` пользователь собирает вручную — названная временная граница.'; } > "$TMP/t21b.md"
expect_red "red: protocol.md with the temporary manual bridge" chk_protocol_pkg "$TMP/t21b.md"

echo ""
echo "[22] sdx/templates/claude-md-snippet.md = section 6 of the vendored MO-INTEROP.md (REQ-PKG-32)"
expect_ok "snippet" chk_snippet_interop "$SNIPPET"
sed 's/сдавай пакет изменения/сдавай всё подряд/' "$SNIPPET" > "$TMP/t22a.md"; expect_red "red: snippet with a changed sentence of section 6" chk_snippet_interop "$TMP/t22a.md"
sed 's#/sdx:pr#/sdx:zz#g' "$SNIPPET" > "$TMP/t22b.md"; expect_red "red: snippet without /sdx:pr" chk_snippet_interop "$TMP/t22b.md"
grep -vF 'МО над стендами и над процессом изменений' "$SNIPPET" > "$TMP/t22c.md"; expect_red "red: snippet without the section 6 paragraph" chk_snippet_interop "$TMP/t22c.md"

echo ""
echo "[23] docs/DECISIONS.md: ADR-022 'Пакет изменения', dated amendment of ADR-021 (REQ-PKG-31)"
expect_ok "DECISIONS.md" chk_adr22 "$DECISIONS"
sed 's/^## ADR-022\..*/## ADR-022. Иное/' "$DECISIONS" > "$TMP/t23a.md"; expect_red "red: ADR-022 heading without 'Пакет изменения'" chk_adr22 "$TMP/t23a.md"
grep -v '^## ADR-022\.' "$DECISIONS" > "$TMP/t23b.md"; expect_red "red: no ADR-022 heading" chk_adr22 "$TMP/t23b.md"
awk '/^## ADR-021\./{p=1} /^## ADR-022\./{p=0} p && /Поправка 2026-10-31/ {gsub(/feat-017-mo-change-package-20261031/,"zz")} {print}' "$DECISIONS" > "$TMP/t23c.md"; expect_red "red: ADR-021 amendment without the session id" chk_adr22 "$TMP/t23c.md"
sed 's/CHANGE\.template\.yaml/zz.yaml/g' "$DECISIONS" > "$TMP/t23d.md"; expect_red "red: ADR-022 without CHANGE.template.yaml" chk_adr22 "$TMP/t23d.md"

echo ""
echo "[24] agents/devops.md: /sdx:pr is the delivery action, no merges / tags, CHANGE.template.yaml, frontmatter intact (REQ-PKG-32, 33)"
expect_ok "devops.md" chk_devops_pkg "$DEVOPS_MD"
for t in '/sdx:pr' 'CHANGE\.template\.yaml' 'теги' 'model: sonnet'; do
  sed "s/$t/zz-removed/g" "$DEVOPS_MD" > "$TMP/t24.md"; expect_red "red: devops.md without '$t'" chk_devops_pkg "$TMP/t24.md"
done

echo ""
echo "[25] README.md, README.en.md, CLAUDE.md: CHANGE.template.yaml, pr-build.sh, CONTRIBUTING-MO.md, 2.5.0, /sdx:pr (REQ-PKG-33)"
for pair in "README.md:$README_RU" "README.en.md:$README_EN" "CLAUDE.md:$ROOT/CLAUDE.md"; do
  expect_ok "${pair%%:*}" chk_surface_pkg "${pair#*:}"
  for t in 'CHANGE\.template\.yaml' 'pr-build\.sh' 'CONTRIBUTING-MO\.md' '2\.5\.0'; do
    sed "s/$t/zz-removed/g" "${pair#*:}" > "$TMP/t25.md"; expect_red "red: ${pair%%:*} without '$t'" chk_surface_pkg "$TMP/t25.md"
  done
done

echo ""
echo "[27] sdx/templates/CONTRIBUTING-MO.md exists and is not a vendored file of sdx/mo/ (REQ-PKG-33)"
expect_ok "plugin tree" chk_contributing "$ROOT"
mkdir -p "$TMP/c27a/sdx/templates" "$TMP/c27a/sdx/mo" "$TMP/c27b/sdx/templates" "$TMP/c27b/sdx/mo"
: > "$TMP/c27a/sdx/mo/CONTRIBUTING-MO.md"; : > "$TMP/c27b/sdx/templates/CONTRIBUTING-MO.md"; : > "$TMP/c27b/sdx/mo/CONTRIBUTING-MO.md"
expect_red "red: file only in sdx/mo/" chk_contributing "$TMP/c27a"
expect_red "red: file in both places" chk_contributing "$TMP/c27b"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
