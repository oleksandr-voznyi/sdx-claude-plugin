---
id: BUG-004
type: bug
status: closed
priority: normal
wave: 5
source: audit-2026-07-01 (B3)
session: fix-diff-computation-contract-20260722
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

## Резолюция
Закрыто сессией `fix-diff-computation-contract-20260722` (трек `standard`) — реализована
рекомендация целиком, включая усиление:
- `commands/verify.md` шаг 4 — оркестратор перенаправляет diff редиректом в
  `.claude/sessions/<id>/delivery.diff` (не через контекст); шаг 5 передаёт ревьюеру **путь**.
- `agents/reviewer.md` — из frontmatter `tools:` изъят `Bash` (`Read, Write, Glob, Grep`);
  «Вход»/«Инструкция 2» велят читать файл, не вычислять. Контракт изоляции стал enforcement.
- Смежный дефект (найден на Discovery): `reviewer.md` хардкодил `git diff main...`, тогда как
  фреймворк резолвит основную ветку динамически (`default-branch.sh`, REQ-BRANCH-3, ADR-010).
  Хардкод `main` удалён — исчез вместе с изъятием самостоятельного вычисления.
- `delivery.diff` — эфемерный буфер: targeted-паттерн `.claude/sessions/*/delivery.diff`
  добавлен в корневой `.gitignore` и seed-блок `commands/init.md` (REQ-SESS-2, как `.stopgate.*`).
- `sdx/protocol.md` (раздел Fresh-eyes) приведён в соответствие — держит триаду
  «протокол ↔ `verify.md` ↔ `reviewer.md`» когерентной (сама ось BUG-004).

Верификация (standard): регресс 9/9 hook-сьютов зелёные, gitignore-паттерн проверен
исполнением; fresh-eyes `reviewer` — PASS, 0 FAIL, 0 WARN. Особенность: сессия
верифицировалась уже по новому контракту (diff подан файлом, ревьюер без `Bash`) — живая
самопроверка правки.
