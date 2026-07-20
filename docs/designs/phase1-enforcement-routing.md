# Technical Design: SDX Enforcement & Routing — Фаза 1

> Методология — русский; код, комментарии и имена полей — английский; runtime-сообщения
> хуков — русский (язык общения), согласно `CLAUDE.md §1`.
> Источник-референс: `.sdx/bundles/upgrade_2026-06-27/...bundle.md` §2/§4/§5. Этот DESIGN
> применяет к бандлу решения по 5 открытым вопросам Discovery — расхождения с бандлом
> помечены `[ПРАВКА vs БАНДЛ]`.

## Архитектурный обзор

Фаза 1 вводит **детерминированный enforcement-слой** поверх существующей stage/track-машины
SDX. Четыре инварианта, ранее закреплённые только в прозе, переводятся в исполняемые
артефакты, активируемые через хуки Claude Code и команду `/sdx:archive`:

- **stage-gate** (PreToolUse `Write|Edit|MultiEdit`) — заморозка записи в код до гейта Execution.
- **stop-gate** (Stop) — тест-пол: ход не завершается на красном прогоне в Execution/Verification.
- **prod-guard** (PreToolUse `Bash`) — блокировка прод-команд по per-project паттернам.
- **archive-verify** (вызов из `/sdx:archive`) — инварианты Closeout 1/5/6 в скрипте.

Плюс **model routing**: явное поле `model` во frontmatter всех 8 субагентов.

Все хуки **safe-by-default**: активны только внутри SDX-ветки (`sdx/<id>`), при отсутствии
сессии/состояния/конфига деградируют в no-op (`exit 0`, проход). Активная сессия определяется
по git-ветке — единственный источник истины, не требующий переменных окружения. Состояние
стадии читается из `.claude/sessions/<id>/session_state.json` (поле `.stage`).

Ключевое свойство безопасности самоустановки: **все артефакты enforcement лежат под
`.claude/**`**, который входит в always-allow список stage-gate. Поэтому установка и
активация хуков физически не может быть заблокирована самим stage-gate (см. ADR-5).

### Подтверждения контракта хуков (версия Claude Code 2.1.195, верифицировано на бинарнике)

| Факт | Статус | Источник |
|---|---|---|
| PreToolUse блокировка: `hookSpecificOutput.permissionDecision:"deny"` + `permissionDecisionReason` | ПОДТВЕРЖДЁН (switch: `deny`→`blockingError`) | strings бинарника |
| `decision:"block"` для PreToolUse | DEPRECATED | strings бинарника |
| exit 2 блокирует для `Stop`/`SubagentStop`/`TaskCompleted`/`TeammateIdle`/`UserPromptSubmit` | ПОДТВЕРЖДЁН; PreToolUse в наборе ОТСУТСТВУЕТ | strings бинарника |
| `model` как поле agent-frontmatter | ПОДТВЕРЖДЁН (`"Model alias this agent uses. If omitted, inherits the parent's model"`) | zod-схема в бинарнике |
| `effort`/`reasoningEffort` как поле agent-frontmatter | НЕ НАЙДЕН в схеме агента (есть только CLI/session) | zod-схема в бинарнике |
| `tool_input.file_path`, `tool_input.command`, `CLAUDE_PROJECT_DIR`, `.stage`, matcher `A|B|C` | ПОДТВЕРЖДЕНЫ | Discovery |

---

## Компоненты и Интеграции

- **[ADDED]** `.claude/sdx/hooks/stage-gate.sh` — PreToolUse-хук `Write|Edit|MultiEdit`. REQ-GATE-1.
- **[ADDED]** `.claude/sdx/hooks/stop-gate.sh` — Stop-хук. REQ-GATE-2.
- **[ADDED]** `.claude/sdx/hooks/prod-guard.sh` — PreToolUse-хук `Bash`. REQ-PROD-1.
- **[ADDED]** `.claude/sdx/hooks/archive-verify.sh` — вызывается из `/sdx:archive`. REQ-CLOSEOUT-1.
- **[ADDED]** `.claude/sdx/prod-guard.conf` — пустой документированный шаблон паттернов. REQ-PROD-1.
- **[ADDED]** `.claude/sdx/stage-gate.allow` — опциональный per-project allowlist (шаблон с комментариями). REQ-GATE-1.
- **[ADDED]** `.claude/sdx/verify-cmd.sh.template` — НЕ исполняемый per-project шаблон. См. ADR-4.
- **[ADDED]** `.claude/settings.json` — project-level проводка хуков (файла нет, создаётся).
- **[MODIFIED]** `.claude/agents/*.md` (8 файлов) — добавить `model:` во frontmatter. REQ-ROUTE-1.
- **[MODIFIED]** `.claude/commands/sdx/archive.md` — вызов `archive-verify.sh` после мёржа.
- **[MODIFIED]** `.claude/commands/sdx/verify.md` — примечание о stop-gate под шагом 2.
- **[MODIFIED]** `.claude/sdx/protocol.md` — раздел «Enforcement-слой (хуки)».
- **[MODIFIED]** `CLAUDE.md` — §2 (model-note), §3 Closeout (ссылка на archive-verify).
- **[DEVOPS]** `git config core.hooksPath` и репо-корневой `hooks/pre-commit` — **ОТЛОЖЕНЫ за Фазу 1** (см. «Решения по скоупу»).

### Решения по скоупу относительно бандла

- **[ПРАВКА vs БАНДЛ]** `hooks/pre-commit` + `core.hooksPath hooks` (§5.6/§5.9 бандла) **исключены
  из Фазы 1**. Обоснование (историческое, на момент проектирования): (1) это единственный
  артефакт вне `.claude/**`, ломающий чистую самоустановку; (2) pre-commit полезен только при
  наличии lint/test-команд, которых у мета-проекта SDX на тот момент не было (no-op) (устарело
  для тест-команды, см. поправку к ADR-4 — но lint-команда по-прежнему отсутствует); (3) SPEC
  Фазы 1 их не требует (нет в критериях приёмки). Переносится в проектные потребители как
  опциональный per-project артефакт.
- **[ПРАВКА vs БАНДЛ]** `verify-cmd.sh` создаётся как **неисполняемый шаблон** (`.template`),
  не активный скрипт — см. ADR-4.

---

## Схема данных / API

### Контракт PreToolUse-хуков (stage-gate, prod-guard) — ИТОГОВЫЙ

`[ПРАВКА vs БАНДЛ]` Бандл использовал `exit 2 + stderr`. Переходим на **JSON-вывод** (ADR-1).

| Исход | stdout | exit |
|---|---|---|
| Пропуск (allow) | пусто | `0` |
| Блокировка (deny) | `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"<reason-ru>"}}` | `0` |

Causa: при `permissionDecision:"deny"` Claude Code формирует `blockingError` из
`permissionDecisionReason`, возвращая его агенту как причину отказа; вызов инструмента
не выполняется, ход НЕ прерывается. Не зависит от deprecated-семантики exit 2 для PreToolUse.

### Контракт Stop-хука (stop-gate) — ИТОГОВЫЙ

| Исход | stderr | exit |
|---|---|---|
| Пропуск (no-op/зелёный/loop-guard сработал/**кэш-хит**) | (опц. пояснение) | `0` |
| Блокировка завершения хода (красный) | хвост вывода теста + причина | `2` |

Causa: для событий Stop-семейства `exit 2 + stderr` — подтверждённый блокирующий механизм
(stderr возвращается агенту). Остаётся как в бандле.

**Green-run cache (ADR-011).** Между резолвом verify-команды и инкрементом loop-guard
stop-gate сверяет отпечаток рабочего дерева (`git rev-parse HEAD` + md5 от `git status
--porcelain`) с сохранённым отпечатком последнего зелёного прогона (`.stopgate.ok` в каталоге
сессии). Совпадение → `exit 0` без перезапуска verify (кэш-хит — новый путь «Пропуск»).
Отпечаток пишется только в ветке успешного прогона; красный прогон кэш не создаёт. `SDX_STOP_GATE=1`
обходит чтение кэша (форс всегда честный), но зелёный форс всё равно обновляет `.stopgate.ok`.
Проверка размещена ДО инкремента loop-guard, поэтому кэш-хит не крутит счётчик `.stopgate.count`.
Инвалидация автоматическая: любое изменение дерева меняет отпечаток. Устраняет находку аудита A4
(десятки прогонов без изменений кода за длинную Execution).

### Контракт archive-verify

`archive-verify.sh <session_id>` → `exit 0` при выполнении инвариантов 1/5/6 (с явным `[OK]`),
`exit 1` (`[ABORT]`/`[FAIL]`) при нарушении. Вызывается из `/sdx:archive` ПОСЛЕ мёржа ветки.

### Раскладка model (REQ-ROUTE-1)

`effort` НЕ добавляется ни одному агенту (ADR-3). Используются полные model ID (схема их
допускает наравне с алиасами; ID точнее пиннят поколение).

| Агент | model | effort |
|---|---|---|
| `reviewer` | `claude-opus-4-8` | — |
| `architect` | `claude-sonnet-4-6` | — |
| `ba` | `claude-sonnet-4-6` | — |
| `lead-dev` | `claude-sonnet-4-6` | — |
| `developer` | `claude-sonnet-4-6` | — |
| `qa` | `claude-sonnet-4-6` | — |
| `devops` | `claude-sonnet-4-6` | — |
| `tech-writer` | `claude-haiku-4-5` | — |

Добавляется одна строка `model: <id>` в существующий YAML frontmatter, остальные поля
(`name`, `description`, `tools`) не трогаются.

### Проводка `.claude/settings.json` (создаётся)

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Write|Edit|MultiEdit",
        "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/sdx/hooks/stage-gate.sh" }] },
      { "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/sdx/hooks/prod-guard.sh" }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/sdx/hooks/stop-gate.sh" }] }
    ]
  }
}
```

`[ПРАВКА vs БАНДЛ]` **`SubagentStop` НЕ проводится** (ADR-2). Stop-секция — единственная для stop-gate.

---

## Псевдокод/уточнённый bash скриптов

### stage-gate.sh (PreToolUse Write|Edit|MultiEdit) — REQ-GATE-1

```bash
#!/usr/bin/env bash
# SDX stage-gate (REQ-GATE-1): freeze code writes until the Execution gate.
# PreToolUse hook. Blocks via JSON permissionDecision:"deny" (NOT exit 2).
set -uo pipefail

input="$(cat)"
proj="${CLAUDE_PROJECT_DIR:-.}"

deny() {  # $1 = reason (ru); JSON to stdout, exit 0
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}' \
    "$(printf '%s' "$1" | jq -Rs .)"
  exit 0
}

target="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
[ -z "$target" ] && exit 0                       # no path -> nothing to gate

# Normalize separators (Windows backslashes) before prefix strip / glob matching.
target="${target//\\//}"
proj="${proj//\\//}"

# Active session = git branch (SDX invariant: branch = sdx/<id>).
branch="$(git -C "$proj" branch --show-current 2>/dev/null || true)"
case "$branch" in sdx/*) sid="${branch#sdx/}" ;; *) exit 0 ;; esac

state="$proj/.claude/sessions/${sid}/session_state.json"
[ -f "$state" ] || exit 0
stage="$(jq -r '.stage // empty' "$state" 2>/dev/null || echo '')"

case "$stage" in Execution|Deployment) exit 0 ;; esac   # code writes legitimate

rel="${target#"$proj"/}"
# Always-allowed: docs, framework files, any markdown (planning artifacts).
case "$rel" in docs/*|.claude/*|*.md) exit 0 ;; esac

# Optional per-project allowlist (one glob per line; '#' comments).
allow="$proj/.claude/sdx/stage-gate.allow"
if [ -f "$allow" ]; then
  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    case "$pat" in \#*) continue ;; esac
    # shellcheck disable=SC2254
    case "$rel" in $pat) exit 0 ;; esac
  done < "$allow"
fi

deny "SDX stage-gate: запись в код ($rel) заблокирована — стадия '$stage', код заморожен до гейта Execution. Артефакты планирования пишите в docs/ или каталог сессии; иначе пройдите /sdx:next до Execution."
```

`[ПРАВКА vs БАНДЛ]`: блок-ветка `exit 2 + echo >&2` → `deny()` (JSON). `jq -Rs .` корректно
экранирует reason в JSON-строку. Остальная логика идентична §5.1 бандла.

`[ПРАВКА 2026-07-20, BUG-006]`: нормализация `\` → `/` в `target`/`proj` до вычисления `rel`
и глобов — на Windows `file_path` приходит с backslash, без нормализации не срабатывали ни
срезка префикса, ни slash-глобы allow-листа (проходил только `*.md`). Регистр буквы диска
(`C:`/`c:`) не нормализуется (нет репро). Тесты: сценарии 9/10 `test-stage-gate.sh`.

### prod-guard.sh (PreToolUse Bash) — REQ-PROD-1

```bash
#!/usr/bin/env bash
# SDX prod-guard (REQ-PROD-1): block shell commands matching prod-guard.conf patterns.
# PreToolUse hook on Bash. Blocks via JSON permissionDecision:"deny".
set -uo pipefail
proj="${CLAUDE_PROJECT_DIR:-.}"

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}' \
    "$(printf '%s' "$1" | jq -Rs .)"
  exit 0
}

cmd="$(cat | jq -r '.tool_input.command // empty')"
[ -z "$cmd" ] && exit 0
conf="$proj/.claude/sdx/prod-guard.conf"
[ -f "$conf" ] || exit 0                          # NB: no conf = no protection (opt-in)
while IFS= read -r pat; do
  [ -z "$pat" ] && continue
  case "$pat" in \#*) continue ;; esac
  if printf '%s' "$cmd" | grep -Eiq -- "$pat"; then
    deny "SDX prod-guard: команда совпала с прод-паттерном (/$pat/) и заблокирована. Прод-деплой — только явное действие человека, не агента. При осознанном деплое снимите блок вручную."
  fi
done < "$conf"
exit 0
```

`[ПРАВКА vs БАНДЛ]`: `exit 2 + echo >&2` → `deny()` (JSON). Логика паттернов — как §5.3.

### stop-gate.sh (Stop) — REQ-GATE-2

```bash
#!/usr/bin/env bash
# SDX stop-gate (REQ-GATE-2): deterministic test floor under Verification.
# Stop hook. exit 2 + stderr blocks turn-end until verify command is green.
set -uo pipefail

proj="${CLAUDE_PROJECT_DIR:-.}"
branch="$(git -C "$proj" branch --show-current 2>/dev/null || true)"
case "$branch" in sdx/*) sid="${branch#sdx/}" ;; *) exit 0 ;; esac
state="$proj/.claude/sessions/${sid}/session_state.json"
[ -f "$state" ] || exit 0
stage="$(jq -r '.stage // empty' "$state" 2>/dev/null || echo '')"

# Enforce only where green is expected, unless forced (headless, Phase 4).
if [ "${SDX_STOP_GATE:-0}" != "1" ]; then
  case "$stage" in Execution|Verification) ;; *) exit 0 ;; esac
fi

# Loop-guard: stop re-blocking after 3 red attempts; hand back to human.
guard="$proj/.claude/sessions/${sid}/.stopgate.count"
n=$(( $(cat "$guard" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$guard"
if [ "$n" -gt 3 ]; then
  echo "SDX stop-gate: тесты всё ещё красные после $((n-1)) попыток — нужно вмешательство человека." >&2
  rm -f "$guard"; exit 0
fi

# Resolve verify command: per-project executable script wins, else autodetect.
cmd=""
if [ -x "$proj/.claude/sdx/verify-cmd.sh" ]; then cmd="$proj/.claude/sdx/verify-cmd.sh"
elif [ -f "$proj/composer.json" ] && grep -q '"test"' "$proj/composer.json"; then cmd="composer test"
elif [ -f "$proj/package.json" ] && grep -q '"test"' "$proj/package.json"; then cmd="npm test --silent"
elif [ -f "$proj/phpunit.xml" ] || [ -f "$proj/phpunit.xml.dist" ]; then cmd="./vendor/bin/phpunit"
fi
[ -z "$cmd" ] && exit 0                            # no known test command -> no-op (meta-project)

if ( cd "$proj" && eval "$cmd" >/tmp/sdx-stopgate.out 2>&1 ); then
  rm -f "$guard"; exit 0
else
  echo "SDX stop-gate: тест-прогон ('$cmd') красный — ход не завершён. Исправьте и повторите. Хвост:" >&2
  tail -20 /tmp/sdx-stopgate.out >&2
  exit 2
fi
```

Без правок относительно §5.2 бандла (контракт Stop через exit 2 подтверждён). Зависит от
ADR-4: для мета-проекта `verify-cmd.sh` неисполняемый → автодетект пуст → `exit 0` (no-op)
(снимок Фазы 1; устарело для мета-проекта, см. поправку к ADR-4 — механизм автодетекта и
no-op-деградации без правок остаётся актуальным для прочих проектов без тест-команды).

### archive-verify.sh — REQ-CLOSEOUT-1

```bash
#!/usr/bin/env bash
# SDX archive-verify (REQ-CLOSEOUT-1): enforce Closeout invariants 1, 5, 6.
# Usage: archive-verify.sh <session_id>  — called from /sdx:archive AFTER merge.
set -uo pipefail
proj="${CLAUDE_PROJECT_DIR:-.}"
sid="${1:?session_id required}"
sdir="$proj/.claude/sessions/$sid"
fail=0

# Item 1: working tree clean.
if [ -n "$(git -C "$proj" status --porcelain)" ]; then
  echo "[FAIL] рабочее дерево не чистое — есть незакоммиченные изменения." >&2; fail=1
fi
# Item 5: branch merged into main (only if branch still exists).
if git -C "$proj" rev-parse --verify "sdx/$sid" >/dev/null 2>&1; then
  if ! git -C "$proj" branch --merged main | grep -q "sdx/$sid"; then
    echo "[FAIL] ветка sdx/$sid не слита в main." >&2; fail=1
  fi
fi
[ "$fail" -ne 0 ] && { echo "[ABORT] Closeout не завершён — устраните FAIL и повторите." >&2; exit 1; }

# Item 6: delete session dir + verify (the historically-skipped step).
rm -rf "$sdir"
[ -d "$sdir" ] && { echo "[FAIL] не удалось удалить $sdir" >&2; exit 1; }
git -C "$proj" branch -d "sdx/$sid" >/dev/null 2>&1 || true
echo "[OK] Closeout-инварианты выполнены: дерево чистое, ветка слита, сессия $sid удалена."
```

Без правок относительно §5.5 бандла. Не читает stage — не зависит от названий стадий.
Примечание реализации: текущий каталог сессии (`fw-enforce-route-20260627`) содержит этот
DESIGN.md; на Closeout текущей сессии скрипт его удалит штатно — дельты переносятся в `docs/`.

### prod-guard.conf (пустой шаблон, REQ-PROD-1)

```
# One extended-regex per line. EMPTY (all-comment) FILE = NO PROTECTION.
# Заполняется под каждый проект: прод-хосты, флаги окружения, деплой-команды.
# SDX meta-project has NO production environment -> intentionally empty.
# Примеры (раскомментировать и адаптировать под проект):
# ssh[[:space:]]+.*prod
# --env[=[:space:]]prod
# deploy.*(prod|production)
# rsync.*@.*prod
```

### stage-gate.allow (опциональный шаблон)

```
# One glob per line, project-relative. '#' comments. Empty = no extra allowance.
# Расширяет always-allow (docs/**, .claude/**, *.md) под нужды проекта.
# Пример: разрешить запись миграций до Execution
# database/migrations/*
```

### verify-cmd.sh.template (per-project, НЕ исполняемый — ADR-4)

```bash
#!/usr/bin/env bash
# Per-project verify command for stop-gate (and optional pre-commit).
# COPY to verify-cmd.sh AND `chmod +x` to activate. Until then stop-gate no-ops.
# --fast -> quick subset ; no arg -> full suite.
set -uo pipefail
case "${1:-}" in
  --fast) exec ./vendor/bin/phpunit --testsuite=unit ;;   # PHP example
  *)      exec ./vendor/bin/phpunit ;;
esac
# Node example: --fast -> npm run test:unit ; else -> npm test
```

---

## Решения и обоснования (ADR)

### ADR-1 — Механизм блокировки PreToolUse: JSON `permissionDecision:"deny"`

**Решение.** stage-gate и prod-guard блокируют через JSON-вывод
`hookSpecificOutput.permissionDecision:"deny"` + `permissionDecisionReason` на stdout, `exit 0`.
**НЕ** используем `exit 2` и **НЕ** используем deprecated `decision:"block"`.

**Обоснование (верифицировано на бинарнике 2.1.195).** (1) В коде Claude Code есть switch
`permissionDecision: case "deny" -> permissionBehavior="deny", blockingError=permissionDecisionReason`
— это явно поддерживаемый, текущий путь. (2) Строка `decision:"block" ... deprecated for
PreToolUse, use hookSpecificOutput.permissionDecision instead` подтверждает устаревание
старого JSON-поля. (3) Блокирующая ветка `exit 2` enumerated только для
`Stop|SubagentStop|TaskCompleted|TeammateIdle|UserPromptSubmit` — **PreToolUse в этом наборе
отсутствует**, значит надёжность `exit 2` для PreToolUse не гарантирована. JSON-путь
устраняет зависимость от непроверенной семантики. Это и есть «безопасный вариант» из
context_report §1, выбранный на основании прямого подтверждения, а не догадки.

### ADR-2 — Скоуп stop-gate: только `Stop`, без `SubagentStop`

**Решение.** stop-gate проводится на событие `Stop` (завершение хода основной сессии).
`SubagentStop` НЕ проводится.

**Обоснование.** (1) **Цель** — детерминированный пол под Verification, которую ведёт
основная сессия через `/sdx:verify`; её завершение хода = событие `Stop`. Это прямое
попадание. (2) **TDD red-green.** В Execution developer-субагент по дисциплине TDD пишет
сначала падающий тест (красный — ожидаемое промежуточное состояние), затем код. Привязка
к `SubagentStop` блокировала бы завершение хода developer'а на «правильном» красном, воюя
с самим циклом TDD. (3) **Шум и стоимость.** `SubagentStop` срабатывает для ВСЕХ субагентов
(`ba`, `architect`, `reviewer`, `qa`...). Прогон тестов на завершении каждого — лишние
запуски без выгоды. (4) **Покрытие Execution сохраняется** через stage-фильтр на `Stop`:
когда оркестратор завершает ход в стадии Execution после возврата developer'а, stop-gate
ловит устойчиво-красное состояние на границе оркестратора. Цена — задержка в один ход
оркестратора (приемлемо: это пол, а не пошаговый блокер). Тем самым SPEC-скоуп
«Execution/Verification» соблюдён фильтром по стадии, а не вторым событием.

**Отвергнуто.** Вариант «оба события + фильтр по стадии» — отвергнут из-за пункта (2):
даже со stage-фильтром он бьёт по developer'у в Execution в момент намеренного красного.

### ADR-3 — `effort` во frontmatter: не включаем

**Решение.** Ни одному агенту не добавляется `effort`. Только `model`.

**Обоснование (верифицировано на бинарнике).** zod-схема агента содержит
`model: string().optional() ("Model alias this agent uses...")`, но поля `effort`/
`reasoningEffort` в объекте схемы агента НЕТ — `effort` присутствует лишь как CLI/session-флаг.
Добавление неподдерживаемого ключа во frontmatter в лучшем случае игнорируется, в худшем —
ломает парсинг. SPEC REQ-ROUTE-1 делает `effort` условным; условие (подтверждённая
поддержка) не выполнено → исключаем. `reviewer` получает только `model: claude-opus-4-8`.
**effort — вне frontmatter, опускаем.**

### ADR-4 — verify-cmd для мета-проекта: no-op деградация, шаблон неисполняемый

**Решение.** В ядре SDX `verify-cmd.sh` НЕ создаётся исполняемым. Поставляется
`verify-cmd.sh.template` (без `chmod +x`). stop-gate, не найдя исполняемого `verify-cmd.sh`
и не обнаружив composer/npm/phpunit, выходит `exit 0` (no-op).

**Обоснование.** Мета-проект SDX не имеет тест-сьюта; принудительная заглушка с фиктивным
«зелёным» прогоном дала бы ложное чувство защиты и риск ложно-зелёного гейта. Безопаснее
честный no-op: stop-gate прозрачен там, где тестировать нечего (SPEC REQ-GATE-2 «Деградация»,
обязательное поведение). `verify-cmd.sh` — **per-project ответственность потребителей**;
шаблон документирует, как его активировать (скопировать + `chmod +x`). Проверка `[ -x ... ]`
в stop-gate гарантирует, что неисполняемый `.template` не подхватится.

> **Поправка 2026-07-20 (DEBT-004).** Допущение «у мета-проекта SDX нет тест-сьюта» закрыто:
> `sdx/hooks/` содержит 5 юнит-тест-сьютов (`test-*.sh`, 56 тестов), и мета-проект теперь
> сам поставляется с исполняемым `.claude/sdx/verify-cmd.sh` (per-project конфиг, dogfooding),
> который последовательно запускает эти сьюты. stop-gate на SDX-сессиях самого фреймворка
> активен, а не no-op. Механизм no-op-деградации, описанный выше, при этом НЕ меняется и
> остаётся спроектированным поведением по умолчанию для произвольных проектов без известной
> тест-команды (`verify-cmd.sh` неисполняем/отсутствует и автодетект composer/npm/phpunit пуст).

### ADR-5 — Порядок установки без самоблокировки

**Решение.** Все enforcement-артефакты размещаются под `.claude/**`, который входит в
always-allow stage-gate. Поэтому установка/активация хуков не блокируется stage-gate ни на
какой стадии. Безопасный порядок установки:

1. Создать `.claude/sdx/hooks/*.sh`, `.claude/sdx/prod-guard.conf`, `.claude/sdx/stage-gate.allow`,
   `.claude/sdx/verify-cmd.sh.template` — пути под `.claude/**` → проход даже при активном
   stage-gate на не-Execution стадии.
2. Создать `.claude/settings.json` — тоже под `.claude/**` → проход. С момента записи
   stage-gate становится активным.
3. `chmod +x .claude/sdx/hooks/*.sh` — Bash-команда; prod-guard.conf пуст → не блокируется.
4. Изменить `.claude/agents/*.md`, `.claude/commands/sdx/{archive,verify}.md`,
   `.claude/sdx/protocol.md`, `CLAUDE.md` — все под `.claude/**` или `*.md` (CLAUDE.md в корне,
   но `*.md` always-allow) → проход.

**Обоснование логикой allowlist.** stage-gate допускает запись при
`case "$rel" in docs/*|.claude/*|*.md) exit 0`. Все артефакты Фазы 1 матчат `.claude/*`
либо `*.md`. Единственный путь, который НЕ матчил бы (`hooks/pre-commit` в корне репо),
**вынесен за Фазу 1** (см. «Решения по скоупу»). Следовательно самоблокировка структурно
невозможна, и установку можно безопасно выполнять на стадии Execution текущей сессии (где
gate и так открыт), при этом даже до Execution `.claude/**`-записи прошли бы. Доп. гарантий
по порядку не требуется. **Операционный caveat:** project-level `settings.json` считывается
Claude Code; для гарантированной активации хуков может потребоваться перезапуск сессии CLI —
зафиксировать в инструкции установки (PLAN.md).

---

## Обработка ошибок и Граничные случаи

- **Вне SDX-ветки** (`branch != sdx/*`): все хуки `exit 0` (прозрачны). Подтверждено инвариантом ветки.
- **Нет `session_state.json` / пустой `.stage`**: stage-gate и stop-gate `exit 0` (no-op).
- **Нет `tool_input.file_path`/`.command`**: `exit 0` (нечего гейтить).
- **Пустой/отсутствующий `prod-guard.conf`**: prod-guard `exit 0` — нет защиты (намеренный opt-in).
  Проверка conf выполняется раньше проверки `jq` (см. «Доработки после Фазы 1: A2»), поэтому
  отсутствие `jq` на проекте без сконфигурированной защиты НЕ блокирует Bash-команды.
- **Запись тестов на Verification**: stage-gate открывает тестовые каталоги (`tests/**`,
  `test/**`, `spec/**`, вкл. вложенные) на стадии Verification (см. «Доработки после Фазы 1: A1»).
- **Нет тест-команды**: stop-gate `exit 0` (no-op) — обязательное поведение для проектов без
  тест-команды (см. поправку к ADR-4; для самого мета-проекта SDX условие с 2026-07-20 не
  выполняется — см. `.claude/sdx/verify-cmd.sh`).
- **3 красных прогона подряд**: stop-gate снимает блок (`exit 0`), чистит `.stopgate.count`,
  возвращает управление человеку. Claude Code дополнительно ограничивает серию блоков.
- **archive-verify при грязном дереве/неслитой ветке**: `exit 1` до удаления каталога —
  необратимое удаление не выполняется, пока инварианты 1/5 не выполнены.
- **`jq`/`git` недоступны**: команды в подстановках падают в пустую строку под `|| true` /
  `2>/dev/null` → ветви no-op. Discovery подтвердил доступность обоих в окружении.
- **RЕ-вход stop-gate медленным сьютом**: ограничение — stop-gate эффективен при быстром
  прогоне (<~30 c); для медленных сьютов потребитель задаёт `verify-cmd.sh --fast`
  (unit-подмножество). Зафиксировано как per-project рекомендация.

## Риски и деградация (safe-by-default)

| Условие | Поведение | Класс |
|---|---|---|
| Нет ветки `sdx/*` | Все хуки no-op | by design |
| Нет `session_state.json`/`.stage` | stage/stop-gate no-op | by design |
| Нет тест-команды (проект без test-command) | stop-gate no-op | by design (см. поправку к ADR-4) |
| Пустой `prod-guard.conf` | prod-guard без защиты | by design (opt-in) |
| Пустой `stage-gate.allow` | только базовый always-allow | by design |
| `settings.json` не перечитан CLI | хуки не активны до рестарта | операционный (caveat в PLAN) |
| Медленный тест-сьют | задержка завершения хода | per-project (`--fast`) |
| Задержка в 1 ход (Stop-only stop-gate) | красное ловится на границе оркестратора | принято (ADR-2) |

## Безопасность

- **Принцип минимума доверия.** Enforcement дублирует, а не заменяет договорённости: prod-guard
  усиливает ограничение `tools` агента `devops` (enforcement важнее декларации).
- **Прод-деплой — только человек.** REQ-PROD-1: агентские Bash-команды, совпавшие с прод-паттерном,
  блокируются на уровне хука вне зависимости от стадии.
- **Необратимые операции под защитой.** archive-verify удаляет каталог сессии и ветку только
  после доказанной чистоты дерева и слияния — нет потери незакоммиченной работы.
- **Экранирование.** reason-сообщения в JSON экранируются через `jq -Rs .` — инъекция спецсимволов
  в `permissionDecisionReason` исключена.
- **Изоляция reviewer сохраняется** (не затрагивается Фазой 1): `reviewer` остаётся без `Edit`,
  получает только артефакты+diff; смена его `model` на Opus не меняет контракт изоляции.

---

## Точечные текстовые дельты документов

### `.claude/sdx/protocol.md` — `[ADDED]` раздел «Enforcement-слой (хуки)»

Вставить новый раздел (после «Гейты (Gates)»):

> ## Enforcement-слой (хуки)
> Инварианты, обязанные выполняться всегда, вынесены из прозы в детерминированные хуки
> (`.claude/sdx/hooks/`), проводка — `.claude/settings.json`. Все хуки активны только в
> SDX-ветке `sdx/<id>` и деградируют в no-op при отсутствии сессии/конфига (safe-by-default).
> - **stage-gate** (PreToolUse `Write|Edit|MultiEdit`): запись в код заморожена до гейта
>   Execution; `docs/**`, `.claude/**`, `*.md` открыты всегда (артефакты планирования).
>   Блокировка — JSON `permissionDecision:"deny"`. Plan mode НЕ используется намеренно — он
>   заблокировал бы и `.md`-артефакты Spec/Design/Plan.
> - **stop-gate** (Stop): тест-прогон как пол под Verification; ход не завершается на красном
>   (скоуп Execution/Verification или `SDX_STOP_GATE=1`). После 3 красных подряд — возврат
>   человеку. Привязан к `Stop` (не `SubagentStop`), чтобы не воевать с TDD red-green developer'а.
>   Деградирует в no-op без известной тест-команды (`verify-cmd.sh` — per-project).
> - **prod-guard** (PreToolUse `Bash`): прод-команды по `prod-guard.conf` блокируются; пустой
>   conf = нет защиты (opt-in per-project). Прод-деплой — только явное действие человека.
> - **archive-verify** (вызов из `/sdx:archive` после мёржа): Closeout 1/5/6 enforced скриптом.

### `.claude/commands/sdx/archive.md` — `[MODIFIED]`

После пункта 5 чек-листа (Слияние) добавить пункт-вызов (и перенумеровать существующие 6/7):

> - `[ ]` **6. Enforcement-проверка закрытия.** Вызови:
>   `bash .claude/sdx/hooks/archive-verify.sh <session_id>`
>   Скрипт выполняет инвариант 1 (чистое дерево), 5 (ветка слита), 7 (удаление каталога
>   сессии + верификация) и удаляет слитую ветку. Ненулевой код → Closeout НЕ завершён:
>   устрани FAIL и повтори. Прозовые формулировки этих инвариантов ниже заменяются ссылкой
>   на скрипт.

(Связанные пункты 1/6 прозы помечаются «enforced `archive-verify.sh`».)

### `.claude/commands/sdx/verify.md` — `[MODIFIED]`

В шаг 2 добавить примечание:

> Примечание: детерминированный пол обеспечивает stop-gate-хук (Stop) — ход не завершится на
> красном прогоне в Execution/Verification. `qa` отвечает за СУЖДЕНИЕ о покрытии/тавтологичности
> ПОВЕРХ зелёного прогона, гарантированного хуком. В мета-проекте без тест-сьюта stop-gate
> прозрачен (no-op) — суждение `qa` остаётся единственным слоем.
>
> _(Снимок Фазы 1 — формулировка, добавленная в `verify.md` на момент проектирования; устарела
> для мета-проекта, см. поправку к ADR-4. Актуальный текст `commands/verify.md` обобщён на
> «проект без известной тест-команды».)_

### `CLAUDE.md` — `[MODIFIED]`

- **§2 «Ролевая модель»** — добавить строку: «Каждый субагент объявляет `model` во frontmatter
  (раскладка: `reviewer`→Opus, `tech-writer`→Haiku, остальные→Sonnet; обоснование — DESIGN/
  protocol «Enforcement-слой»). Поле `effort` во frontmatter не используется (не поддерживается).»
- **§3 Closeout (этап 9)** — в описании чек-листа заменить прозу пунктов «чистое дерево /
  ветка слита / удаление файлов сессии» на: «инварианты 1/5/6 enforced скриптом
  `.claude/sdx/hooks/archive-verify.sh` (вызывается `/sdx:archive` после мёржа)».

---

## Доработки после Фазы 1

Устранение находок аудита `docs/audit-2026-07-01-recommendations.md`. Псевдокод хуков выше —
снимок Фазы 1; фактические скрипты в `.claude/sdx/hooks/` отражают правки ниже (источник истины —
код + тесты).

### A1 — тестовые пути открыты на Verification (сессия fw-enforce-a1a2-20260703)

**Проблема.** stage-gate разрешал запись только на `Execution|Deployment`. Но по `/sdx:verify`
шаг 2 агент `qa` пишет интеграционные тесты на стадии Verification — тестовые пути не подпадали
под always-allow (`docs/*|.claude/*|*.md`) и блокировались на любом прикладном проекте.

**Решение.** На стадии `Verification` stage-gate дополнительно пропускает тестовые каталоги по
встроенным glob'ам: `tests/*`, `test/*`, `spec/*` и вложенные `*/tests/*`, `*/test/*`, `*/spec/*`.
Правки **не-тестового** кода по FAIL-находкам остаются заморожены — только через
`/sdx:backtrack --to Execution` (граница «код заморожен, тесты открыты» проверена тестом).
Со-локованные тесты (напр. Go `foo_test.go`) не покрываются директорными glob'ами намеренно —
для них используется per-project `stage-gate.allow`. `qa.md`/`verify.md` править не потребовалось.
_Осознанный компромисс:_ `spec/` в части проектов хранит спецификации API (`spec/openapi.yaml`),
а не тесты — на Verification запись туда будет разрешена (окно узкое; квитировано в верификации).

### A2 — порядок проверок prod-guard: conf раньше jq (сессия fw-enforce-a1a2-20260703)

**Проблема.** prod-guard проверял наличие `jq` раньше наличия/содержимого `prod-guard.conf`.
На проекте без прод-среды (conf отсутствует/пустой = «защиты нет по договорённости») отсутствие
`jq` превращалось в fail-closed-блокировку **каждой** Bash-команды, включая `ls`.

**Решение.** Проверка conf поднята выше проверки `jq` (она jq не требует): (1) нет файла → `exit 0`;
(2) скан на наличие хотя бы одной активной (непустой, не-комментарий) строки-паттерна; нет
активных → `exit 0`; (3) только при сконфигурированной защите — проверка `jq` (fail-closed
сохранён: нет jq → deny) и матчинг. Fail-closed теперь включается лишь там, где защита реально
задана.

Тесты: `test-stage-gate.sh` (+2: Verification allow/deny), `test-prod-guard.sh` (+2: no-op без
jq при отсутствии/пустоте conf). Прогон всех сьютов хуков: 35 passed, 0 failed.

### C7+C2 — модель сессии = worktree = ветка + автоопределение ветки (сессия fw-session-worktree-20260703)

**Проблема.** ADR-005 декларировал инкрементальные коммиты артефактов сессии, но `.claude/sessions/`
целиком лежал в `.gitignore` (C7) — коммит был физически невозможен; `/sdx:switch` делал слепой
`git add -A && commit` в общем дереве (C2); хуки и prose-команды хардкодили `main` как имя основной
ветки.

**Решение.** Переход на модель «одна сессия = свой git worktree на ветке `sdx/<id>`» с
версионированием артефактов (вариант A: `git rm -r` каталога сессии коммитом НА ВЕТКЕ до мёржа).
`archive-verify.sh` переработан: резолв основной ветки через новый `lib/default-branch.sh` (без
хардкода `main`), инвариант 6 = каталог сессии не tracked в дереве основной ветки, освобождение
worktree через `git worktree remove --force` вместо `rm -rf`. Полное описание — `docs/specs/`
и `docs/designs/session-worktree-model.md`, ADR-009 (worktree + tracked artifacts) и ADR-010
(автоопределение основной ветки) в `docs/DECISIONS.md`. Псевдокод `archive-verify.sh` выше по
этому файлу — снимок Фазы 1; источник истины — переработанный скрипт + `test-archive-verify.sh`.

## Передача DevOps

- **[DEVOPS]** Активация project-level `.claude/settings.json` может требовать перезапуска
  сессии Claude Code CLI — учесть в инструкции установки (PLAN.md).
- **[DEVOPS]** `chmod +x .claude/sdx/hooks/*.sh` обязателен после раскладки (хуки запускаются
  как `command`).
- **[ОТЛОЖЕНО]** `git config core.hooksPath hooks` + `hooks/pre-commit` — вне Фазы 1
  (per-project, требует lint/test-команд; тест-команда у мета-проекта с 2026-07-20 есть —
  `.claude/sdx/verify-cmd.sh` (DEBT-004), lint-команды по-прежнему нет, вывод об отсрочке
  pre-commit сохраняется).
