---
id: PROC-001
type: proc
status: closed
priority: null
wave: null
source: audit-2026-07-01 (C3)
session: fw-auto-gates-20260719
links: [ADR-014, REQ-PATCHV-1/2]
---

# PROC-001. У patch-трека нет ни одного слоя проверки по умолчанию

## Суть
На patch: stage-gate прозрачен (сразу Execution), Verification «по запросу»,
fresh-eyes «опционально», stop-gate no-op без тест-команды. Правка уходит в `main` без
независимой проверки, только с самооценкой автора.

## Рекомендация
На patch-Closeout — обязательный лёгкий fresh-eyes прогон (diff маленький,
стоимость копеечная; можно моделью подешевле), либо хотя бы обязательный регрессионный тест
как гейт (сейчас «как правило достаточен», т.е. необязателен).

## Резолюция
Закрыто (сессия `fw-auto-gates-20260719`, 2026-07-19) — Verification на patch обязательна
в лёгком объёме (fresh-eyes против change_note + регрессионный тест), гейт archive требует
verification_report без FAIL; ADR-014, REQ-PATCHV-1/2.
