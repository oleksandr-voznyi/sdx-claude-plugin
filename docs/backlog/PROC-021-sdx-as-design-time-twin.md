---
id: PROC-021
type: proc
status: open
priority: normal
wave: 5
source: intake sdx-runtime-rethink-20260830 (тезис Т1)
session: null
links: [DEBT-031, PROC-016, PROC-017, FEAT-006, FEAT-009, IDEA-010]
---

# PROC-021. Позиционирование SDX как design-time двойника ядра Конструктора

## Суть
SDX — не вспомогательная методичка рядом с продуктом, а тот же архитектурный контур, только
design-time и с человеком в роли durable-движка. Соответствие покомпонентное и не метафорическое:
durable runtime ↔ сессия-ветка; state store ↔ git-история; policy hooks ↔ `hooks.json`;
HITL inbox ↔ интерактивные гейты; M1 Identity & Authority ↔ `tools:` во frontmatter;
M3 Observability ↔ `session.log` + Closeout; M8 Evals ↔ fresh-eyes `reviewer`;
process definitions ↔ триада SPEC/DESIGN/PLAN.

Продуктовое следствие: SDX становится третьим активом рядом с Core и AIBoK — авторской средой
спецификаций, которые исполняет ядро. Открытый вопрос №1 `Constructor-concept.md` (собственный DSL
против расширения BPMN/SDX-формата) тогда решается не выбором, а промоушеном триады до языка
процессов.

## Рекомендация
Зафиксировать позиционирование ADR'ом и провести его последствия по документам: раздел о связи
с AIBoK/Конструктором в README, явное указание, какие механики SDX являются прототипами каких
модулей ядра (`FEAT-006` → M1, `FEAT-004` → M3, `PROC-016` → M8, `FEAT-009` → диагностика).

Правка самих `AIBoK-structure.md` и `Constructor-concept.md` — вне бэклога плагина.

## Зависимости и порядок
После того как волны 1–4 покажут, что механики работают: позиционирование на непроверенных
прототипах — маркетинг, а не архитектура.
