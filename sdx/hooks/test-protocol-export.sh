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

# ---------------------------------------------------------------------------------------------------- [X5]
if want X5; then
echo "[X5] adr: a record that names ADR-<n> -> true, otherwise false"
mkproj x5 $'- 2026-10-31 [контракт] Принято решение по ADR-021. Подробности ниже.\n- [триаж] Обычное решение без ссылок. Хвост.\n\n### Развилка: [контракт] Формат\n- Вариант: Вариант A\n- Обоснование: Закреплено в ADR-007, см. реестр\n\n### Развилка: [объём] Другое\n- Вариант: Вариант B\n- Обоснование: Просто так\n'
px "$PXP"
eq "[X5] rc 0" "$RC" "0"
if [ "$HAVE_YAML" = 1 ]; then
  oracle "$OUT"
  eq "[X5] adr per record: B with ADR-021 / B without / A with ADR-007 / A without" "$(pj '.data.decisions|map(.adr)|join(",")')" "true,false,true,false"
else
  info "[X5] python3/PyYAML absent: the content checks are skipped (not a PASS)"
  eq "[X5] (no oracle) adr lines" "$(printf '%s\n' "$OUT" | grep '^    adr:' | tr -d ' \n')" "adr:trueadr:falseadr:trueadr:false"
fi
fi

# ---------------------------------------------------------------------------------------------------- [X7]
if want X7; then
echo "[X7] hostile values survive a safe_load roundtrip (line breaks, tabs and U+2028 become spaces)"
big="$(head -c 5000 /dev/zero | tr '\0' 'x')"
raw="say \"hi\" \\ back --- end: x"$'\t'"tab"$'\xe2\x80\xa8'"sep # not-a-comment [a, b] {c: d} & * ! | > '' $big"
exp="say \"hi\" \\ back --- end: x tab sep # not-a-comment [a, b] {c: d} & * ! | > '' $big"
mkproj x7 "- 2026-10-31 [триаж] $raw"$'\n'"### Развилка: [контракт] Заголовок: с двоеточием \"и кавычками\""$'\n'"- Вариант: $raw"$'\n'"- Обоснование: $raw"$'\n'
px "$PXP"
eq "[X7] rc 0" "$RC" "0"
if [ "$HAVE_YAML" = 1 ]; then
  oracle "$OUT"
  eq "[X7] the schema oracle accepts the output" "$(pj '.errors|length')" "0"
  eq "[X7] B: why = the record with the tab and U+2028 replaced by spaces" "$(pj '.data.decisions[0].why')" "$exp"
  eq "[X7] A: what survives" "$(pj '.data.decisions[1].what')" "$exp"
  eq "[X7] A: why survives (5000-character tail intact)" "$(pj '.data.decisions[1].why|length')" "${#exp}"
  eq "[X7] the title with a colon and quotes survives in questions" "$(pj '.data.questions[1]')" '[контракт] Заголовок: с двоеточием "и кавычками"'
else
  info "[X7] python3/PyYAML absent: the roundtrip is skipped (not a PASS)"
fi
fi

# ---------------------------------------------------------------------------------------------------- [X8]
if want X8; then
echo "[X8] verified / deltas / done from the session artifacts"
mkproj x8 "$LOG_A"
S8="$PXP/.claude/sessions/$PXSID"
cat > "$S8/verification_report.md" <<'MD'
# Verification Report: s1

## Сводка
- Объём: полный, no_code: нет
- Итог: PASS
- Находки: FAIL: 0, WARN: 1

## Матрица трассируемости
| Требование / критерий | Реализация (файл) | Тест | Когерентность | Статус |
|------------------------|-------------------|------|----------------|--------|
| REQ-1 | a.sh:1 | да | ok | OK |
| REQ-2 | b.sh:2 | нет | ok | WARN |
| REQ-3 | c.sh:3 | да | ok | OK |

## Находки
### [WARN] [Полнота] Нет теста для REQ-2
- Где: REQ-2

<!-- SDX-MANDATE-SCOPE:BEGIN -->
## Область мандата (детерминированная проверка)
- Мандат: executor=ex1, digest=123456789012; файлов в диффе: 3
- Итог по области: PASS
<!-- SDX-MANDATE-SCOPE:END -->
MD
cat > "$S8/SPEC.md" <<'MD'
# Спецификация
Используется Delta-формат: [ADDED], [MODIFIED], [REMOVED] — это проза, не дельта.

## Дельта
- [ADDED] **REQ-PKG-1** — первое требование
- [MODIFIED] **REQ-PKG-2** — второе
- [ADDED] **REQ-PKG-1** — повтор того же
### [REMOVED] Старое поведение без идентификатора требования, и очень длинное описание, которое точно длиннее восьмидесяти знаков
MD
printf '# Change note\n\n- [ADDED] REQ-NOTE-9 — not used when SPEC.md exists\n' > "$S8/change_note.md"
cat > "$S8/PLAN.md" <<'MD'
# Plan
- [x] **T01** первая задача
- [ ] **T02** не сделана
- [X] **T03** третья задача с очень длинным описанием, которое должно быть обрезано до ста двадцати знаков, потому что так написано в схеме экспорта протокола сессии
MD
px "$PXP"
eq "[X8] rc 0" "$RC" "0"
if [ "$HAVE_YAML" = 1 ]; then
  oracle "$OUT"
  eq "[X8] the schema oracle accepts the output" "$(pj '.errors|length')" "0"
  eq "[X8] verified: the Сводка bullets, the matrix counts, the scope verdict" "$(pj '.data.verified|join("|")')" "Объём: полный, no_code: нет|Итог: PASS|Находки: FAIL: 0, WARN: 1|Матрица: OK 2, WARN 1, FAIL 0|Итог по области: PASS"
  eq "[X8] deltas: from SPEC.md, ids, duplicates dropped, order kept" "$(pj '.data.deltas[0:2]|join("|")')" "[ADDED] REQ-PKG-1|[MODIFIED] REQ-PKG-2"
  eq "[X8] deltas: a delta without an id keeps the first 80 characters of its text" "$(pj '.data.deltas|length') $(pj '.data.deltas[2]|startswith("[REMOVED] Старое поведение") and (length <= 90)')" "3 true"
  eq "[X8] done: only the checked tasks, each at most 120 characters" "$(pj '.data.done|length') $(pj '.data.done[0]') $(pj '.data.done[1]|length <= 120')" "2 **T01** первая задача true"
  # sources and their order
  rm "$S8/SPEC.md"; px "$PXP"; oracle "$OUT"
  eq "[X8] without SPEC.md the deltas come from change_note.md" "$(pj '.data.deltas|join("|")')" "[ADDED] REQ-NOTE-9"
  rm "$S8/PLAN.md"; mkdir -p "$PXP/docs/history/plans"; printf -- '- [x] **H1** from the archive\n' > "$PXP/docs/history/plans/$PXSID.md"
  px "$PXP"; oracle "$OUT"
  eq "[X8] without PLAN.md done comes from docs/history/plans/<sid>.md" "$(pj '.data.done|join("|")')" "**H1** from the archive"
  rm "$PXP/docs/history/plans/$PXSID.md"; px "$PXP"; oracle "$OUT"
  eq "[X8] without a plan at all: one entry from change_note.md (a folded delta)" "$(pj '.data.done|join("|")')" "change_note.md: Change note"
  rm "$S8/change_note.md" "$S8/verification_report.md"; px "$PXP"; oracle "$OUT"
  eq "[X8] without the other sources: verified, deltas and done are empty, rc 0" "$RC $(pj '[.data.verified,.data.deltas,.data.done]|map(length)|join(",")')" "0 0,0,0"
else
  info "[X8] python3/PyYAML absent: the content checks are skipped (not a PASS)"
fi
fi

# ---------------------------------------------------------------------------------------------------- [X9]
if want X9; then
echo "[X9] --from-rev <parent of the Closeout step-5 commit> gives the same file as a run before step 5"
G9="$TMP/x9"; rm -rf "$G9"; mkdir -p "$G9/.claude/sessions/$PXSID"
git -C "$G9" init -q -b dev 2>/dev/null || git -C "$G9" init -q
gc() { git -C "$G9" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
printf '%s' "$LOG_A" > "$G9/.claude/sessions/$PXSID/decisions_log.md"
printf '# Report\n\n## Сводка\n- Итог: PASS\n' > "$G9/.claude/sessions/$PXSID/verification_report.md"
printf -- '- [x] **T01** done\n' > "$G9/.claude/sessions/$PXSID/PLAN.md"
gc add -A && gc commit -q -m "session"
REV9="$(git -C "$G9" rev-parse HEAD)"
bash "$SCRIPT" --sid "$PXSID" --proj "$G9" --out - > "$TMP/x9.before" 2>/dev/null
gc rm -r -q ".claude/sessions/$PXSID" && gc commit -q -m "step 5: git rm session"
bash "$SCRIPT" --sid "$PXSID" --proj "$G9" --from-rev "$REV9" > "$TMP/x9.rev" 2> "$TMP/x9.err"; rc=$?
if [ "$rc" -eq 0 ] && [ -s "$TMP/x9.before" ] && cmp -s "$TMP/x9.before" "$TMP/x9.rev"; then pass "[X9] --from-rev <parent of the step-5 commit> equals the run before step 5 (stdout)"; else fail "[X9] --from-rev" "rc=$rc $(diff "$TMP/x9.before" "$TMP/x9.rev" | head -4)"; fi
if [ ! -e "$G9/.claude/sessions/$PXSID" ]; then pass "[X9] --from-rev writes nothing into the working tree"; else fail "[X9] working tree" "the session directory came back"; fi
bash "$SCRIPT" --sid "$PXSID" --proj "$G9" --out - >/dev/null 2>&1; rc=$?
eq "[X9] the same run on the working tree after step 5: rc 1 (no sources, no directory)" "$rc" "1"
bash "$SCRIPT" --sid "$PXSID" --proj "$G9" --from-rev "$(git -C "$G9" rev-parse HEAD)" >/dev/null 2>&1; rc=$?
eq "[X9] --from-rev at the commit that already removed the directory: rc 1" "$rc" "1"
for bad in "--output=x" "-x" "no-such-rev-here" ""; do
  bash "$SCRIPT" --sid "$PXSID" --proj "$G9" --from-rev "$bad" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 2 ]; then pass "[X9] a malformed or unknown revision [$bad] is refused (rc 2)"; else fail "[X9] revision [$bad]" "rc=$rc"; fi
done
fi

# ---------------------------------------------------------------------------------------------------- [X10]
if want X10; then
echo "[X10] portability (BUG-010) of protocol-export.sh; no python, no eval"
FORBID='tim''eout|map''file|declare -''A|[$]\{[a-zA-Z_]+,,\}|%''N|readlink -''f|real''path'
if grep -nE "$FORBID" "$SCRIPT" >/dev/null 2>&1; then fail "[X10] protocol-export.sh portability" "forbidden: $(grep -nE "$FORBID" "$SCRIPT" | head -3)"
else pass "[X10] protocol-export.sh: no GNU-only / bash4-only constructs"; fi
cp "$SCRIPT" "$TMP/port-mut.sh"; printf 'ma''pfile -t xs <<<""\n' >> "$TMP/port-mut.sh"
if ! cmp -s "$SCRIPT" "$TMP/port-mut.sh" && grep -qE "$FORBID" "$TMP/port-mut.sh"; then pass "[X10] red side: the same grep flags a script with a bash4 construct"
else fail "[X10] red side of the portability grep" "mutant not flagged"; fi
if grep -nE 'py''thon|\bev''al\b' "$SCRIPT" >/dev/null 2>&1; then fail "[X10] no python, no eval" "found: $(grep -nE 'py''thon|\bev''al\b' "$SCRIPT" | head -2)"; else pass "[X10] protocol-export.sh has no python and no eval"; fi
fi

# ---------------------------------------------------------------------------------------------------- [Mut]
if want Mut && [ -z "${PROTOCOL_EXPORT_NESTED:-}" ]; then
echo "[Mut] mutation runs: each mutant (a copy of the script + lib/ in a temp dir) must differ from the original and turn its block red"
MUTDIR="$TMP/mut"; mkdir -p "$MUTDIR"
# mutate <name> <sed expr> <block>: re-enter this script with PROTOCOL_EXPORT_ONLY=<block> against the mutated copy
mutate() {
  local name="$1" expr="$2" only="$3" d="$MUTDIR/$1" out first
  mkdir -p "$d/lib"; cp "$SCRIPT_DIR/protocol-export.sh" "$d/"; cp "$LIB"/*.sh "$d/lib/"
  sed "$expr" "$SCRIPT_DIR/protocol-export.sh" > "$d/protocol-export.sh"
  if cmp -s "$SCRIPT_DIR/protocol-export.sh" "$d/protocol-export.sh"; then fail "[Mut] $name" "mutant is identical to the original (anchor missing?)"; return; fi
  out="$(PROTOCOL_EXPORT_NESTED=1 PROTOCOL_EXPORT_UNDER_TEST="$d/protocol-export.sh" PROTOCOL_EXPORT_ONLY="$only" bash "${BASH_SOURCE[0]}" 2>&1)"
  if printf '%s\n' "$out" | grep -q 'FAIL:'; then
    first="$(printf '%s\n' "$out" | grep -m1 'FAIL:' | cut -c1-110)"
    pass "[Mut] мутант $name → красный (ожидаемо) в [$only]: ${first#  FAIL: }"
  else
    fail "[Mut] $name" "block [$only] stayed green on the mutant (the check proves nothing)"
  fi
}
mutate PKG-X-FMTB  '/# PKG-X-FMTB/s/триада/нетакоготега/' X2
mutate PKG-X-EMPTY '/# PKG-X-EMPTY/s/"\\(\$k): \[\]"/""/' X4
mutate PKG-X-ADR   '/# PKG-X-ADR/s/a = .*) ? 1 : 0/a = 0/' X5
mutate PKG-X-ID    '/# PKG-X-ID/s/((\.key + 1) . tostring)/"1"/' X6
mutate PKG-X-REV   '/# PKG-X-REV/s/if \[ -n "\$REVSHA" \]/if false/' X9
fi

#@@SECTIONS-END@@

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
