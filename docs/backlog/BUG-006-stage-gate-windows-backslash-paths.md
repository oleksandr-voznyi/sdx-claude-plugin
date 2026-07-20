---
id: BUG-006
type: bug
status: closed
priority: high
wave: null
source: полевой репорт (Windows-сессия SDX, обход через shell)
session: fw-stagegate-winpath-20260720
links: [BUG-001, DEBT-003]
---

# BUG-006. stage-gate на Windows блокирует не-md файлы в .claude/sessions

## Суть
На Windows `file_path` в hook input приходит с backslash-разделителями. В `stage-gate.sh`
срезка префикса `rel="${target#"$proj"/}"` и все `case`-глобы allow-листа
(`docs/*|.claude/*|*.md`, тестовые каталоги Verification, per-project allow) написаны под
forward slash — не срабатывают. Совпадает только `*.md` (паттерн без разделителя), поэтому
markdown-артефакты проходили, а `session_state.json` и прочие не-md файлы сессии блокировались.
Рабочий процесс обходился записью через shell (что само по себе — сигнал DEBT-003).

## Рекомендация
Нормализовать разделители (`\` → `/`) в `target` и `$CLAUDE_PROJECT_DIR` до вычисления `rel`
и всех сопоставлений; добавить тест-сценарии с backslash-путями (allow и deny). Регистр буквы
диска (`C:` vs `c:`) не нормализуется — нет репро; добавить при появлении репорта.

## Резолюция
Закрыто сессией `fw-stagegate-winpath-20260720` (v1.2.1): нормализация `\` → `/` в
`stage-gate.sh` до срезки префикса и глобов; тест-сценарии 9 (allow, нетавтологичный —
без фикса красный) и 10 (deny-guard). Регистр буквы диска — вне скоупа (нет репро).
