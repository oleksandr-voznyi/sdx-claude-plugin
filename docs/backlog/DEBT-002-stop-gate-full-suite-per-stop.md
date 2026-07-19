---
id: DEBT-002
type: debt
status: closed
priority: null
wave: null
source: audit-2026-07-01 (A4)
session: fw-econ-a4d1-20260703
links: [ADR-011]
---

# DEBT-002. Stop-gate гоняет полный тест-сьют на каждом завершении хода

## Суть
На Execution/Verification каждый `Stop` запускает verify-команду (до 180 с).
Длинная Execution-стадия из десятков ходов = десятки прогонов без изменений кода.

## Рекомендация
Кэшировать по состоянию дерева: сохранять в `.stopgate.ok` хэш
(`git rev-parse HEAD` + хэш `git status --porcelain`/diff) последнего зелёного прогона и
выходить `exit 0`, если дерево не изменилось.

## Резолюция
Закрыто (сессия `fw-econ-a4d1-20260703`, 2026-07-03) — green-run cache по отпечатку дерева
(`HEAD` + porcelain) в `.stopgate.ok`, ADR-011.
