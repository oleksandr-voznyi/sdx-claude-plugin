---
id: IDEA-003
type: idea
status: deferred
priority: normal
wave: null
source: bundle sdx-efficiency-automation-2026 (REQ-LOOP-1, Фаза 4)
session: null
links: [DEBT-008]
---

# IDEA-003. Self-improving loop: стоимостный сигнал в Closeout (REQ-LOOP-1)

## Суть
Closeout-рефлексия расширяется стоимостным сигналом: jsonl-анализатор
(`~/.claude/projects/*.jsonl`, офлайн) атрибуцирует расход по агенту/сессии; вывод
(«оправдал ли фронтир-тир расход на типичных задачах проекта») пишется в
`docs/history/`; из лога рождаются проектные оверрайды `model` агентов. Ядро SDX
не трогается.

## Рекомендация
Реализовать в Фазе 4 по дизайн-срезу — см. `docs/specs/phases-2-4-deferred.md`
(раздел REQ-LOOP-1).

## Резолюция
Отложено (roadmap) — создано промоутом roadmap Фаз 2–4 из gitignored-бандла
(сессия `fw-roadmap-20260720`, закрытие DEBT-008); в работу — при планировании
соответствующей фазы.
