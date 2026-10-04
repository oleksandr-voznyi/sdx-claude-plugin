---
id: DEBT-043
type: debt
status: open
priority: normal
wave: null
source: session (sdx/feat-015-mo-interop-20261004), граница SPEC «Self-test»
session: null
links: [FEAT-015, FEAT-014, DEBT-010, DEBT-037]
---

# DEBT-043. Self-test enforcement-слоя не покрывает МО-хуки; `/sdx:status` не показывает состояние МО

## Суть
`selftest.sh` (FEAT-014) пробует живость трёх хуков (`preflight`, `prod-guard`, `stop-gate`). `FEAT-015` добавил
две записи `hooks.json` — `mo-hook` (PreToolUse) и `mo-session` (SessionStart) — и периметр self-test
осознанно не расширял (граница SPEC). Класс `DEBT-010`: тихая деградация МО-хука (например, потеря `jq` или
`python3` в проекте под МО) не видна пользователю до первой блокировки в режиме `deny`. Отдельно: `/sdx:status`
не показывает строку «МО: `.mesh/endpoint.yaml` есть/нет, python3/PyYAML/jq доступны, режим `on_write`».

## Рекомендация
Расширить `selftest.sh` синтетической пробой `mo-hook.sh` (вход `Bash ls` без `.mesh/` → тишина; с фикстурным
`endpoint.yaml` в scratch → ожидаемый исход по режиму) и строкой в `/sdx:status`. Проба не должна запускать
python в проектах без МО (REQ-MO-HOOK-3).
