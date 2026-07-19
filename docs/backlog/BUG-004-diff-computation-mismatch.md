---
id: BUG-004
type: bug
status: open
priority: normal
wave: 5
source: audit-2026-07-01 (B3)
session: null
links: [ADR-004, ADR-005]
---

# BUG-004. Противоречие verify.md ↔ reviewer.md: кто вычисляет diff

## Суть
`/sdx:verify` шаги 4–5: оркестратор вычисляет diff и передаёт его ревьюеру как
данные. `reviewer.md` инструкция 2: «Получи diff поставки целиком (`git diff ...`)» — т.е.
ревьюер вычисляет сам через Bash. Второе хуже по токенам (diff дважды в контекстах) и по
изоляции (Bash даёт ревьюеру доступ ко всему, включая `session.log` — стена держится на прозе).

## Рекомендация
Оркестратор материализует diff в файл редиректом
(`git diff main...sdx/<id> > .claude/sessions/<id>/delivery.diff` — не через свой контекст)
и передаёт путь; из `reviewer.md` убрать самостоятельное вычисление. Усиление: забрать у
`reviewer` Bash (Read/Glob/Grep/Write хватает, если diff в файле) — контракт изоляции станет
enforcement, а не договорённостью. Снимает исключение из ADR-005 о двойной токенизации.
