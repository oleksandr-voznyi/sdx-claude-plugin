---
id: IDEA-006
type: idea
status: open
priority: low
wave: null
source: bundle sdx-efficiency-automation-2026 (§2.7, часть REQ-NOOP-TEAMS)
session: null
links: [DEBT-008]
---

# IDEA-006. Опциональный escalate-тир параллельного Execution

## Суть
Параллельное исполнение — сознательно НЕ дефолт (анти-требование REQ-NOOP-TEAMS: SDX
одно-агентный, обходит ~7× множитель стоимости). Опциональный escalate-тир возможен
только когда full-`PLAN.md` содержит доказуемо независимые `[CODE]`-задачи.

## Рекомендация
Если/когда понадобится: запуск независимых задач в git worktrees с файловыми локами и
ревью хендоффов человеком — см. `docs/specs/phases-2-4-deferred.md` (раздел escalate-тир).
Учесть, что ADR-012 отказался от worktree для сессий — для параллельного тира решение
о механизме изоляции принимать заново (новый ADR).
