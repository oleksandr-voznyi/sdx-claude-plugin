---
id: DEBT-045
type: debt
status: open
priority: normal
wave: null
source: session (sdx/feat-015-mo-interop-20261004), решение пользователя 2026-10-05 — MANUAL_TEST не исполнялся
session: null
links: [FEAT-015, FEAT-006, PROC-020]
---

# DEBT-045. Два утверждения FEAT-015 держатся как допущения: агрегация двух PreToolUse на `Bash` и канал SessionStart

## Суть
1. **К20 / REQ-MO-HOOK-9.** На `Bash` срабатывают два PreToolUse-хука (`prod-guard`, `mo-hook`). Что `deny`
   любого из них достаточен для блока — свойство харнесса; на бинарнике не проверено (сценарий есть:
   `docs/history/experiments/mo-interop-manual-test-2026-10-05.md`, случаи 1–4). Утверждение о приоритете
   `deny > defer > ask > allow` из `FEAT-006` — тоже допущение.
2. **Канал SessionStart.** `mo-session.sh` печатает входящие и аренды в stderr; видит ли это модель — не
   проверено (случай 7 там же). Пока единственный гарантированный канал — явное `inbox --json` (`devops`,
   сниппет CLAUDE.md).

Оба записаны словом «не проверено» в протоколе, ADR-021 и `docs/designs/mo-interop.md`.

## Рекомендация
Первая живая сессия после `/plugin marketplace update sdx` в проекте с `.mesh/endpoint.yaml` (MOVE.IO):
прогнать семь случаев сценария, записать версию `claude` и факты; затем заменить «не проверено» на
«подтверждено/опровергнуто» в трёх документах. Если «не видит» — это факт о канале, не дефект.
