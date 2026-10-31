#!/usr/bin/env bash
# Tests for sdx/hooks/protocol-export.sh (FEAT-017, REQ-PKG-19..22): protocol.yaml built from the session journals.
# The schema oracle is python3 -I + yaml.safe_load with the logic of protocol_check() of the node (sim-kit core/dev.py:
# 596-606, read as data, never imported): five list sections, decisions[i].{id,what,why} non-empty. python3/PyYAML appear
# here ONLY as the oracle (INFO-skip, never PASS, when absent); nothing is written outside a temporary directory.
#
#  [X1] format A (### Развилка + Вариант / Обоснование / Варианты, continuation lines) + the built-in negative of the oracle
#  [X2] the LITERAL decisions_log.md of this session (format B: "- <date> [tag] text")
#  [X3] a mix of A and B in one file, order kept
#  [X4] no files / empty session directory / empty decisions_log.md -> five empty lists, rc 0; no directory and no sources -> rc 1
#  [X5] adr: a record that names ADR-<n> -> true, otherwise false
#  [X6] id: D-1..D-n, unique, continuous (a skipped record takes no number)
#  [X7] hostile values (quote, backslash, ---, ": ", tab, 5000 characters, U+2028) survive a safe_load roundtrip
#  [X8] verified / deltas / done from verification_report.md, SPEC.md / change_note.md, PLAN.md / docs/history/plans/<sid>.md
#  [X9] --from-rev <parent of the Closeout step-5 commit> gives the same file as a run before step 5
#  [X10] portability (BUG-010), no python / eval in the script
#  [Mut] mutation runs (copies of the script + lib/ in a temp dir, anchored by "# PKG-X-*")
# PROTOCOL_EXPORT_ONLY="X1 X4" restricts a run; PROTOCOL_EXPORT_UNDER_TEST is the script under test (mutation runs).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${PROTOCOL_EXPORT_UNDER_TEST:-$SCRIPT_DIR/protocol-export.sh}"
LIB="$SCRIPT_DIR/lib"
export PYTHONDONTWRITEBYTECODE=1

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
info() { echo "  INFO: $1"; }
want() { local t; [ -z "${PROTOCOL_EXPORT_ONLY:-}" ] && return 0; for t in $PROTOCOL_EXPORT_ONLY; do [ "$t" = "$1" ] && return 0; done; return 1; }

echo "=== test-protocol-export.sh ==="
echo ""

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck disable=SC1091
. "$LIB/pr-lib.sh"
# shellcheck disable=SC1091
. "$LIB/pkg-fixture.sh"

PXSID=s1
HAVE_YAML=0; python3 -I -c 'import yaml' >/dev/null 2>&1 && HAVE_YAML=1

# mkproj <name> [decisions_log text]: a project with a session directory (the log file only when text is given)
mkproj() {
  PXP="$TMP/$1"; rm -rf "$PXP"; mkdir -p "$PXP/.claude/sessions/$PXSID"
  if [ $# -ge 2 ]; then printf '%s' "$2" > "$PXP/.claude/sessions/$PXSID/decisions_log.md"; fi
}

# px <project> [args...]: RC / OUT (the protocol text, --out -) / ERR of one run
px() {
  local p="$1"; shift
  OUT="$(bash "$SCRIPT" --sid "$PXSID" --proj "$p" --out - "$@" 2>"$TMP/err")"; RC=$?
  ERR="$(cat "$TMP/err")"
}

# oracle <text> -> ORJ = {"errors":[...],"data":{...}} (protocol_check of the node); rc 77: no PyYAML
oracle() {
  printf '%s\n' "$1" > "$TMP/o.yaml"
  ORJ="$(python3 -I -B - "$TMP/o.yaml" <<'PY'
import json, sys
try:
    import yaml
except Exception:
    sys.exit(77)
KEYS = {"done": list, "decisions": list, "questions": list, "verified": list, "deltas": list}
try:
    d = yaml.safe_load(open(sys.argv[1], encoding="utf-8").read()) or {}
except Exception as e:
    print(json.dumps({"errors": ["YAML: %s" % str(e).splitlines()[0]], "data": {}}, ensure_ascii=False)); sys.exit(0)
if not isinstance(d, dict):
    print(json.dumps({"errors": ["не отображение"], "data": {}}, ensure_ascii=False)); sys.exit(0)
errs = ["%s: ожидается список" % k for k, t in KEYS.items() if k in d and not isinstance(d[k], t)]
errs += ["нет раздела %s" % k for k in KEYS if k not in d]
for i, dcn in enumerate(d.get("decisions") or []):
    for k in ("id", "what", "why"):
        if not (isinstance(dcn, dict) and dcn.get(k)):
            errs.append("decisions[%d]: нет %s" % (i, k))
print(json.dumps({"errors": errs, "data": d}, ensure_ascii=False))
PY
  )"
  return $?
}
# pj <jq filter> -> the value from the last oracle run
pj() { printf '%s' "$ORJ" | jq -r "$1" 2>/dev/null; }
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "got [$2] expected [$3]"; fi; }
# keys_present <text>: the structural check that does not need PyYAML: five top-level keys
keys_present() { local k; for k in done decisions questions verified deltas; do printf '%s\n' "$1" | grep -q "^$k:" || return 1; done; return 0; }

# ================================================================================================= fixtures (journals)
LOG_A=$'# Журнал решений\n\n### Развилка: [триада] Выбор подхода (этап: Technical Design)\n- Вариант: Использовать A,\n  с продолжением на второй строке.\n- Обоснование: Потому что простое\n  и проверенное.\n- Варианты: B (медленно); C (дорого)\n\n### Развилка: Без тега\n- Вариант: Только вариант\n- Обоснование: Есть причина\n'
LOG_B=$'# Журнал решений: x\n\n- 2026-10-31 [триаж] Принято по дефолту. Подробности: вторая фраза записи.\n- [контракт] Запись без даты\n  с продолжением на второй строке.\n'
LOG_GOLD=$(cat <<'GOLD_EOF'
# Журнал решений: feat-017-mo-change-package-20261031

- 2026-10-31 [триаж] (оркестратор, Discovery → Business Spec; не стоп-рубрика — все решения следуют эталону sim-kit 0.9.1 и ответу владельца МО 28.10) Q-1: `/sdx:pr` — отдельная команда; мост `/sdx:archive` при `delivery: pr|branch` делегирует ей (один вход). Q-3: `base` — `repo.base` из заказа `work.order`, если есть, иначе основная ветка SDX; узел пересчитывает `merge-base` сам. Q-4: `commitment` и снимок заказа — `order.yaml` в каталоге сессии (tracked) + поле `commitment` в `session_state.json` (новое, необязательное). Q-5: порядок `/sdx:pr`: шаги 1–4 Closeout → экспорт `protocol.yaml` в каталог сессии (tracked на `sdx/<sid>`) → шаг 5 (`git rm -r`) → squash в `change/<C>-<exec>` → коммит `CHANGE.yaml`; доставка `protocol.yaml` узлу в `work/<C>/` — вне SDX (при `history: mo` узел читает ветку `sdx/<sid>` своего клона, при `history: executor` — вопрос upstream). Q-8: `final` = `full` (К-6 FEAT-016), реестр ADR проверяется на покрытие `docs_paths` с предупреждением (ответ МО §3.3). Q-9: `github` без `gh` — деградация до `bare` (push ветки + инструкция открыть PR вручную, одна строка), не отказ; `bare` — push в `repo.url` заказа или `origin`. Q-12: поле `change` в `artifact.offer` НЕ добавляется (узел его игнорирует, `mesh.py:702`); оффер при `bridge:offer` остаётся шагом 0. Q-14: `CHANGE.template.yaml` — четвёртый вендорённый файл `sdx/mo/` (хеш, сторож); `CONTRIBUTING-MO.md` — в `sdx/templates/` (не вендорённый, сторож правила (d) не трогается). R-2: `CHANGE.yaml` создаётся git-plumbing (`git update-index --cacheinfo`/`commit-tree`) без записи файла в рабочее дерево — хук области не срабатывает; upstream: манифест исключить из `_in_scope` хука, как в `audit()`. Squash (без каталога сессии) — по требованию МО; история остаётся в `sdx/<sid>`. Push ветки `change/*` — внешний эффект: подтверждение пользователя перед push в любом `gate_mode` (`[контракт]`), ветки `sdx/<sid>` на хостинг заказчика не выталкиваются.
- 2026-10-31 [триаж] Гейт Business Spec: SPEC.md (REQ-PKG-1…35) утверждён пользователем с предложенными дефолтами 12 открытых вопросов.
- 2026-10-31 [триада] Гейт Technical Design: DESIGN.md принят пользователем со всеми предложениями по коллизиям К-1…К-19 (К-1 — датированное отступление от PROC-028: вендоринг CHANGE.template.yaml в этой сессии; К-2 трейлеры служебного коммита; К-3 без force; К-9 подтверждение --from-issue; К-10 параллельный раннер при >150 с; К-12 документ = путь под docs/). SPEC дополнен разделом поправок.
GOLD_EOF
)

# ---------------------------------------------------------------------------------------------------- [X1]
if want X1; then
echo "[X1] format A: ### Развилка + Вариант / Обоснование / Варианты, continuation lines"
mkproj x1 "$LOG_A"
px "$PXP"
eq "[X1] rc 0" "$RC" "0"
if keys_present "$OUT"; then pass "[X1] all five top-level keys are present"; else fail "[X1] keys" "$OUT"; fi
if [ "$HAVE_YAML" = 1 ]; then
  oracle "$OUT"
  eq "[X1] the schema oracle accepts the output (protocol_check)" "$(pj '.errors|length')" "0"
  eq "[X1] two decisions" "$(pj '.data.decisions|length')" "2"
  eq "[X1] D-1: id / tag / stage" "$(pj '.data.decisions[0]|[.id,.tag,.stage]|join("|")')" "D-1|триада|Technical Design"
  eq "[X1] D-1: what (continuation line joined by one space)" "$(pj '.data.decisions[0].what')" "Использовать A, с продолжением на второй строке."
  eq "[X1] D-1: why (continuation line joined)" "$(pj '.data.decisions[0].why')" "Потому что простое и проверенное."
  eq "[X1] D-1: alternatives from «Варианты»" "$(pj '.data.decisions[0].alternatives|join("|")')" "B (медленно); C (дорого)"
  eq "[X1] D-1: adr false" "$(pj '.data.decisions[0].adr')" "false"
  eq "[X1] D-2: no tag, no stage, no alternatives" "$(pj '.data.decisions[1]|[.id,.tag,.stage,(.alternatives|length)]|join("|")')" "D-2|||0"
  eq "[X1] questions: «[тег] название» per record" "$(pj '.data.questions|join("|")')" "[триада] Выбор подхода|Без тега"
  # the built-in negative: the oracle must turn red on a protocol that lacks a section / a field
  oracle "$(printf '%s\n' "$OUT" | grep -v '^deltas:')"
  if [ "$(pj '.errors|length')" -ge 1 ] && printf '%s' "$ORJ" | grep -q 'нет раздела deltas'; then pass "[X1] negative: the oracle flags a protocol without the deltas section"; else fail "[X1] negative (section)" "$ORJ"; fi
  oracle "$(printf '%s\n' "$OUT" | grep -v '^    why:')"
  if printf '%s' "$ORJ" | grep -q 'нет why'; then pass "[X1] negative: the oracle flags a decision without why"; else fail "[X1] negative (why)" "$ORJ"; fi
else
  info "[X1] python3/PyYAML absent: the content checks of the schema oracle are skipped (not a PASS)"
fi
fi

# ---------------------------------------------------------------------------------------------------- [X2]
if want X2; then
echo "[X2] the literal decisions_log.md of this session (format B)"
mkproj x2 "$LOG_GOLD"$'\n'
px "$PXP"
eq "[X2] rc 0" "$RC" "0"
if [ "$HAVE_YAML" = 1 ]; then
  oracle "$OUT"
  eq "[X2] the schema oracle accepts the output" "$(pj '.errors|length')" "0"
  eq "[X2] three decisions D-1..D-3" "$(pj '.data.decisions|map(.id)|join(",")')" "D-1,D-2,D-3"
  eq "[X2] tags in order" "$(pj '.data.decisions|map(.tag)|join(",")')" "триаж,триаж,триада"
  eq "[X2] what and why are non-empty everywhere" "$(pj '.data.decisions|map(select((.what|length)>0 and (.why|length)>0))|length')" "3"
  eq "[X2] what is the first sentence of the entry, at most 200 characters" "$(pj '.data.decisions[1].what')" "Гейт Business Spec: SPEC.md (REQ-PKG-1…35) утверждён пользователем с предложенными дефолтами 12 открытых вопросов."
  eq "[X2] why is the whole entry text" "$(pj '.data.decisions[1].why|startswith("Гейт Business Spec: SPEC.md") and endswith("12 открытых вопросов.")')" "true"
  eq "[X2] D-1: the long entry is cut to 200 characters in what, not in why" "$(pj '(.data.decisions[0].what|length) <= 200 and (.data.decisions[0].why|length) > 1500')" "true"
  eq "[X2] no ADR is named -> adr false for all" "$(pj '.data.decisions|map(select(.adr))|length')" "0"
  eq "[X2] questions: three" "$(pj '.data.questions|length')" "3"
else
  info "[X2] python3/PyYAML absent: the content checks are skipped (not a PASS)"
  if keys_present "$OUT" && printf '%s\n' "$OUT" | grep -q 'id: "D-3"'; then pass "[X2] (no oracle) three decisions are written"; else fail "[X2] decisions" "$OUT"; fi
fi
fi

# ---------------------------------------------------------------------------------------------------- [X3]
if want X3; then
echo "[X3] a mix of A and B in one file, order kept"
mkproj x3 "$LOG_B"$'\n'"### Развилка: [деструктив] Третья запись"$'\n'"- Вариант: Делать без удаления"$'\n'"- Обоснование: Откат дороже"$'\n'"- 2026-11-01 [объём] Четвёртая запись. Хвост."$'\n'
px "$PXP"
eq "[X3] rc 0" "$RC" "0"
if [ "$HAVE_YAML" = 1 ]; then
  oracle "$OUT"
  eq "[X3] the schema oracle accepts the output" "$(pj '.errors|length')" "0"
  eq "[X3] order of the file is kept: B, B, A, B" "$(pj '.data.decisions|map(.tag)|join(",")')" "триаж,контракт,деструктив,объём"
  eq "[X3] B: the first sentence is «what»" "$(pj '.data.decisions[0].what')" "Принято по дефолту."
  eq "[X3] B: a continuation line is joined into why" "$(pj '.data.decisions[1].why')" "Запись без даты с продолжением на второй строке."
  eq "[X3] A after B: Вариант / Обоснование" "$(pj '.data.decisions[2]|[.what,.why]|join("|")')" "Делать без удаления|Откат дороже"
  eq "[X3] ids D-1..D-4" "$(pj '.data.decisions|map(.id)|join(",")')" "D-1,D-2,D-3,D-4"
else
  info "[X3] python3/PyYAML absent: the content checks are skipped (not a PASS)"
fi
fi

# ---------------------------------------------------------------------------------------------------- [X4]
if want X4; then
echo "[X4] no files / empty directory / empty log -> five empty lists, rc 0; no directory and no sources -> rc 1"
empty_ok() {  # <label> <project>
  px "$2"
  if [ "$RC" -eq 0 ] && keys_present "$OUT" && [ "$(printf '%s\n' "$OUT" | grep -c '^[a-z]*: \[\]$')" = 5 ]; then pass "[X4] $1: rc 0, five empty lists"; else fail "[X4] $1" "rc=$RC out=[$OUT]"; fi
  if [ "$HAVE_YAML" = 1 ]; then oracle "$OUT"; eq "[X4] $1: the oracle accepts the file" "$(pj '.errors|length')" "0"; fi
}
mkproj x4a; empty_ok "an empty session directory" "$PXP"
mkproj x4b ""; empty_ok "an empty decisions_log.md" "$PXP"
mkproj x4c "# Журнал решений"$'\n'; empty_ok "a log without records" "$PXP"
rm -rf "$TMP/x4d"; mkdir -p "$TMP/x4d"
px "$TMP/x4d"
if [ "$RC" -eq 1 ] && [ -z "$OUT" ] && [ -n "$ERR" ]; then pass "[X4] no session directory and no sources: rc 1 with a reason"; else fail "[X4] no directory" "rc=$RC out=[$OUT] err=[$ERR]"; fi
bash "$SCRIPT" --sid ../x --proj "$TMP/x4d" --out - >/dev/null 2>&1; rc=$?
eq "[X4] a hostile sid is refused (rc 2)" "$rc" "2"
bash "$SCRIPT" --proj "$TMP/x4d" >/dev/null 2>&1; rc=$?
eq "[X4] no --sid: usage, rc 2" "$rc" "2"
# the default output: .claude/sessions/<sid>/protocol.yaml
mkproj x4e "$LOG_A"
bash "$SCRIPT" --sid "$PXSID" --proj "$PXP" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && [ -s "$PXP/.claude/sessions/$PXSID/protocol.yaml" ] && keys_present "$(cat "$PXP/.claude/sessions/$PXSID/protocol.yaml")"; then pass "[X4] the default output is .claude/sessions/<sid>/protocol.yaml"; else fail "[X4] default output" "rc=$rc"; fi
fi

# ---------------------------------------------------------------------------------------------------- [X6]
if want X6; then
echo "[X6] id: D-1..D-n, unique and continuous; a record without what and why is skipped with a note"
LOG6=$'### Развилка: [триада] Первая\n- Вариант: a1\n- Обоснование: b1\n\n### Развилка: Пустая запись\n\n### Развилка: [FAIL] Третья\n- Вариант: a3\n- Обоснование: b3\n\n- [контракт] Четвёртая. Хвост.\n- [триаж] Пятая. Хвост.\n'
mkproj x6 "$LOG6"
px "$PXP"
eq "[X6] rc 0" "$RC" "0"
if printf '%s' "$ERR" | grep -q 'Пустая запись'; then pass "[X6] the skipped record is named on stderr"; else fail "[X6] skip note" "err=[$ERR]"; fi
if [ "$HAVE_YAML" = 1 ]; then
  oracle "$OUT"
  eq "[X6] ids D-1..D-4 (the skipped record takes no number)" "$(pj '.data.decisions|map(.id)|join(",")')" "D-1,D-2,D-3,D-4"
  eq "[X6] ids are unique" "$(pj '.data.decisions|map(.id)|unique|length')" "4"
  eq "[X6] the schema oracle accepts the output" "$(pj '.errors|length')" "0"
else
  ids="$(printf '%s\n' "$OUT" | grep -o 'id: "D-[0-9]*"' | tr '\n' ' ')"
  eq "[X6] (no oracle) ids D-1..D-4" "$ids" 'id: "D-1" id: "D-2" id: "D-3" id: "D-4" '
fi
fi

#@@SECTIONS-END@@

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
