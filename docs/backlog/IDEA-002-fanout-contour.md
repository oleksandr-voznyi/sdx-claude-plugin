---
id: IDEA-002
type: idea
status: open
priority: normal
wave: null
source: bundle sdx-efficiency-automation-2026 (REQ-LANE-1, Фаза 4)
session: null
links: [DEBT-008, IDEA-001]
---

# IDEA-002. Fanout-контур: stateless-задачи по портфелю репозиториев (REQ-LANE-1)

## Суть
Второй контур `sdx fanout` рядом с интерактивным посессионным пайплайном:
stateless-задачи по N репозиториям (регенерация доков, аудиты, массовый
`/sdx:init --existing`), пригодные для headless и Batch API. Элемент = самодостаточный
промпт; роль SDX — шаблон элемента (формат спеки/отчёта), не сессионная машина.

## Рекомендация
Реализовать в Фазе 4 по дизайн-срезу — см. `docs/specs/phases-2-4-deferred.md`
(раздел REQ-LANE-1). Биллинг headless идёт из отдельного пула по API-ставкам —
бюджет закладывать явно. Зависимость: кэш-правила REQ-CACHE-1 (IDEA-001).
