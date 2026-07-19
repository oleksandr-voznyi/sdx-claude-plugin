---
id: DEBT-008
type: debt
status: closed
priority: null
wave: null
source: audit-2026-07-01 (C1)
session: fw-roadmap-20260720
links: [IDEA-001, IDEA-002, IDEA-003, IDEA-004, IDEA-005, IDEA-006]
---

# DEBT-008. Roadmap Фаз 2–4 живёт в gitignored-файле — риск потери

## Суть
`.sdx/bundles/` в `.gitignore`, а единственная полная спецификация отложенных
требований (REQ-LANE-1, REQ-LOOP-1, REQ-CACHE-1, REQ-LEAN-1, REQ-CHECKPOINT-1,
escalate-тир) — это неверсионируемый
`.sdx/bundles/upgrade_2026-06-27/sdx-efficiency-automation-2026.bundle.md`.
`docs/specs/phase1-…` содержит только список имён. Один `rm`/clone — roadmap исчез.

## Рекомендация
Промоутить Фазы 2–4 в трекаемый `docs/roadmap.md` (или
`docs/specs/phases-2-4-deferred.md`) — по собственному правилу Closeout «дельты
переносятся в постоянные доки».

## Резолюция
Закрыто сессией `fw-roadmap-20260720` (2026-07-20): полные формулировки и дизайн-срезы
Фаз 2–4 промоучены в `docs/specs/phases-2-4-deferred.md`; каждое отложенное требование
получило трекинг-запись бэклога (IDEA-001…IDEA-006); спека Фазы 1 перелинкована.
Бандл остаётся локальным справочным артефактом.
