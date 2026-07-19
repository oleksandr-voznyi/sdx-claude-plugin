---
id: DEBT-006
type: debt
status: closed
priority: null
wave: null
source: audit-2026-07-01 (B2)
session: fw-model-aliases-20260702
links: [DEBT-005]
---

# DEBT-006. Раскладка моделей продублирована в трёх местах

## Суть
Frontmatter агентов (источник истины), `CLAUDE.md` §2 (конкретные ID) и
SPEC/DESIGN Фазы 1. При обновлении (B1) — три точки правки, `CLAUDE.md` гарантированно отстанет.

## Рекомендация
В `CLAUDE.md` оставить только принцип («фронтир — на оценочное суждение,
дешёвые — на механику; раскладка — во frontmatter агентов»), без конкретных ID.
Делать вместе с B1.

## Резолюция
Закрыто (сессия `fw-model-aliases-20260702`, 2026-07-02) — в `CLAUDE.md` остался принцип
без ID, источник истины — frontmatter.
