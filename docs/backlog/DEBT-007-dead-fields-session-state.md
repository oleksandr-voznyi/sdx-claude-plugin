---
id: DEBT-007
type: debt
status: open
priority: normal
wave: 10
source: audit-2026-07-01 (B4)
session: null
links: []
---

# DEBT-007. Мёртвые поля в `session_state.json`

## Суть
`artifacts` и `history` объявлены в схеме протокола, но ни одна команда их не
пишет/не читает (состав артефактов по ADR-005 выводится из git). `status`
(`draft|review|approved|executing`) упоминается один раз — в гейте Business Spec.

## Рекомендация
Убрать `artifacts`/`history` из схемы; `status` либо специфицировать
(когда какие переходы), либо заменить на реально нужное гейтам — например
`approvals: {spec, design, warn_ack}`.
