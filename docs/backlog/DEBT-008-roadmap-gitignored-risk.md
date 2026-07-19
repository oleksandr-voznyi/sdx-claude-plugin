---
id: DEBT-008
type: debt
status: open
priority: high
wave: 2
source: audit-2026-07-01 (C1)
session: null
links: []
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
