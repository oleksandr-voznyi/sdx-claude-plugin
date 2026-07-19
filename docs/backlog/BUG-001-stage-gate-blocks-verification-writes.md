---
id: BUG-001
type: bug
status: closed
priority: null
wave: null
source: audit-2026-07-01 (A1)
session: fw-enforce-a1a2-20260703
links: []
---

# BUG-001. Stage-gate блокирует qa и developer на стадии Verification — КРИТИЧНО

## Суть
`stage-gate.sh` разрешает запись в код только на `Execution|Deployment`. Но по
`/sdx:verify` шаг 2 агент `qa` пишет интеграционные тесты на стадии Verification (это его
объявленная роль), а шаг 7 направляет `developer` исправлять FAIL-находки. Тестовые файлы
(`tests/*` и т.п.) не подпадают под always-allow (`docs/*`, `.claude/*`, `*.md`) — хук их
задержит. PreToolUse действует и на субагентов. В мета-проекте не всплыло (здесь всё `.md`),
но на любом прикладном проекте full/standard верификация упрётся в собственный гейт.

## Рекомендация
Выбрать одну модель и зафиксировать в DESIGN/протоколе:
- (предпочтительно) добавить `Verification` в разрешённые стадии для тестовых путей
  (встроенный allow `tests/**`, `test/**`, `spec/**`), а правки кода по FAIL-находкам
  по-прежнему требовать через `/sdx:backtrack --to Execution`;
- либо декларировать, что все тесты пишутся на Execution, а `qa` на Verification только
  запускает и судит — тогда поправить `qa.md` и `verify.md`.

## Резолюция
Закрыто (сессия `fw-enforce-a1a2-20260703`, 2026-07-03) — выбрана предпочтительная модель:
тестовые пути открыты на Verification, правки кода — через backtrack.
