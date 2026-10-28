# QA report: feat-016a-simkit-090 (vendored sim-kit 0.9.0)

## Прогон сьютов
`bash .claude/sdx/verify-cmd.sh` -> exit 0, **15/15 suites passed**, ALL PASSED.

## Допущения обёрток о реальном хуке 0.9.0 (исполнение)
Фикстура: временный каталог в scratchpad (вне репо), `PYTHONDONTWRITEBYTECODE=1`, полный endpoint.yaml
(endpoint_id/node_id/node_path/link/instance/exec_paths/on_write), Write через stdin. "raw" = `devagent_hook.py`, "wrap" = `mo-hook.sh`.

| Случай | Ожидалось | Получено | Итог |
|---|---|---|---|
| (а) без endpoint.yaml | тишина, exit 0 | raw rc=0, wrap rc=0, stdout/stderr пусты | PASS |
| (б) deny, Write в exec_paths без аренды | raw exit 2, `DENY [MO-exec-paths]`; wrap: JSON deny, exit 0 | raw rc=2 `DENY [MO-exec-paths]: запись в каталог исполнения inst1 ... без ар(енды)`; wrap rc=0, JSON `permissionDecision:"deny"`, stderr пуст | PASS |
| (в) notice, та же запись | exit 0, без блока | rc=0, stdout и stderr пусты (хук 0.9.0 не пишет в stderr при реальной записи; "максимум одна строка" соблюдено) | PASS |
| (г1) mandate.yaml (scope src/, deny) + Write docs/x.md | exit 2, `DENY [MO-scope]`; wrap -> JSON deny | raw rc=2 `DENY [MO-scope]: запись вне области мандата ...`; wrap rc=0 JSON deny, правок обёртки нет | PASS |
| (г2) Write src/a.py | тихо | raw и wrap rc=0, пусто | PASS |
| (г3) mandate.yaml без endpoint.yaml | хук молчит | raw rc=0, wrap rc=0, пусто (обёртка выходит раньше; raw тоже молчит) | PASS |
| (д) `__pycache__` в sdx/mo/ | нет | `find sdx/mo -name __pycache__` пусто; `git status` чист | PASS |
| (е) mo-session.sh с endpoint.yaml | inbox/leases без ошибок | "входящих нет", "действующих аренд нет", rc=0; `mesh_endpoint.py pull --quiet`, `inbox --json`, `leases` по отдельности rc=0 | PASS |

Замечания (не дефекты, к сведению):
- Неполный endpoint.yaml (без `link`) реальный хук 0.9.0 обрабатывает как `KeyError`: в deny -> fail-closed deny (корректно по политике), в notice -> одна строка stderr; при наличии mandate.yaml и неполном endpoint.yaml хук падает с traceback (rc=1), обёртка превращает в deny (deny-режим) - т.е. обёртка безопасна. Это поведение вендорённого кода, не правился.
- Write с относительным путём при `cwd:"/"` против mandate scope не блокируется (путь резолвится относительно cwd, вне проекта). Поведение вендорённого хука; реальный Claude Code присылает абсолютные `file_path`.
- Заголовок `MO-INTEROP.md` "Версия протокола: sim-kit 0.7.4" - версия протокола апстрима, при `SIMKIT_VERSION`=0.9.0 и `KIT="0.9.0"` это ожидаемо; правкам не подлежит (PROC-028).

## Вывод о покрытии (г)
В `test-mo-hook.sh` и `test-mo-session.sh` упоминаний mandate нет: ветка MO-scope существующими сьютами НЕ покрыта. Суждение: для приёмки этой сессии
исполнение выше достаточно (обёртка не менялась, перевод exit 2 -> JSON deny обобщён по тексту stderr и уже защищён мутантом MO-TRANSLATE
в сценарии [8a]). Красная сторона для (г) (сценарий вроде [8h]: mandate.yaml + Write вне scope -> JSON deny с `DENY [MO-scope]`; зелёная: Write в scope; контроль: mandate без endpoint) - зона второй сессии FEAT-016,
где mandate станет заявленной возможностью обёрток. Тесты в этой сессии не добавлялись.
Рекомендация: зафиксировать в backlog/FEAT-016, что до тех пор MO-scope работает "бесплатно", но без регрессионной защиты.

## Дополнение оркестратора (2026-10-28, после круга 2)
Отчёт выше написан до добавления сценариев `[8h]`–`[8h4]` в `test-mo-hook.sh` (область мандата через обёртку; независимость
`mandate.on_write`). Повторный прогон оркестратором: `bash .claude/sdx/verify-cmd.sh` — 15/15 сьютов; `test-mo-hook.sh` —
115/115, 12 мутантов красные; `tests/kit.sh` sim-kit на выгрузке тега `sim-kit-0.9.0` — `ok=331 fail=0`. Суждение QA о
покрытии (г) заменено фактом: красная сторона `[8h]` — мутант `TRANSLATE` (`SCEN8_MIN=1`).
