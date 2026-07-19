---
id: IDEA-004
type: idea
status: open
priority: normal
wave: null
source: bundle sdx-efficiency-automation-2026 (REQ-CHECKPOINT-1, Фаза 3)
session: null
links: [DEBT-008]
---

# IDEA-004. Расщепление назначения /sdx:checkpoint (REQ-CHECKPOINT-1)

## Суть
`/sdx:checkpoint` совмещает две роли: durable-state для возобновления многосессионного
флоу (нужно оставить) и ручной сброс контекстного давления (устарел — эту работу делает
авто-компакция контекста).

## Рекомендация
Реализовать в Фазе 3: оставить checkpoint как durable-state, убрать роль
anti-overflow-клапана; правка §5 `CLAUDE.md` и раздела checkpoint в `protocol.md` —
см. `docs/specs/phases-2-4-deferred.md` (раздел REQ-CHECKPOINT-1).
