---
id: DEBT-047
type: debt
status: open
priority: normal
wave: null
source: session (sdx/feat-016-mo-mandate-20261028), Verification 2026-10-29
session: null
links: [FEAT-016, DEBT-045, FEAT-017, FEAT-018]
---

# DEBT-047. Ручной сценарий мандата МО не выполнен: канал SessionStart, реальный мандат узла, живой `run_suites`, проза моста Closeout, два PreToolUse при `deny`

## Суть
Поставка `FEAT-016` (2.4.0) проверена автотестами (19 сьютов) и сквозным QA на фикстурном репозитории, но пять случаев
`docs/history/experiments/mo-mandate-manual-test-2026-10-29.md` требуют бинарника Claude Code и/или живого узла МО и по решению
пользователя 2026-10-29 записаны как **НЕ ПРОВЕРЕНО**: (1) видит ли модель stderr `mo-session` с группой полей мандата
(`DEBT-045`, тот же канал); (2) разбор мандата, выданного реальным `./mo mandate issue`; (3) чтение `tests/suites.yaml` живым
`dev.py run_suites` на стенде узла; (4) проза моста Closeout `bridge`/`bridge:offer` на реальной сессии; (5) агрегация
`prod-guard` + `mo-hook` на одном `Bash` при `mandate.on_write: deny`.

## Рекомендация
Пройти сценарий первой живой сессией под узлом (пилот — новый проект, §5 п.4 записки владельца МО 26.10), результат записать
в тот же файл эксперимента; расхождения — `BUG-`записями. Закрывать вместе с `DEBT-045`.
