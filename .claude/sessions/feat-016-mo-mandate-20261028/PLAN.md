# Implementation Plan: FEAT-016 п.2–9 — мандат МО и декларации (плагин 2.4.0)

## Статус реализации
52/52 задач Execution (T01–T52; дорожка Ф T01–T15 выполнена, gate Ф зелёный), 0/3 задач Closeout (C1–C3). Этап: Execution.

Условные обозначения. `SPEC`/`DESIGN` — одноимённые файлы этой сессии (SPEC включает раздел «Поправки по коллизиям DESIGN» К-1…К-6, обязательный). `ДЛ-N` — `decisions_log.md`. `К-N` — коллизии DESIGN. `A1…A21` — критерии приёмки SPEC №1…21 (ниже «Критерий N»). Якоря `# MAND-*`/`# MO-*` — метки для мутационных прогонов (определены в DESIGN). Дорожки: **Ф** — фундамент (последовательно, один исполнитель), **A**, **B**, **C** — параллельные `developer` после Ф, **З** — завершение (последовательно, после A/B/C).

## Правила исполнения (для всех задач)

- **Не `gate_mode: auto` (PROC-020, критерий 21).** Метка **[PROC-020]** — задача трогает hook-скрипты/механизм надзора; перед ней оркестратор проверяет `jq -r .gate_mode session_state.json` != `auto`, иначе стоп. Вся сессия идёт не в `auto` (проверяется в T51).
- **Коммит на ветке `sdx/feat-016-mo-mandate-20261028` после каждой задачи** (`sdx(feat-016-mo-mandate-20261028): T<NN> …`). Дорожки A/B/C правят **непересекающиеся файлы**; единственные общие точки: `test-mo-prose.sh` (только C), `docs/DECISIONS.md` (только C), `sdx/protocol.md` (только C).
- **TDD.** Для каждой кодовой задачи сначала пишется и фиксируется красной тест-задача (сьют/сценарий падает из-за отсутствия реализации; в DoD — `bash <suite>; echo $?` != 0 и перечень красных строк), затем код делает её зелёной, затем (где указано) мутанты. Порядок «реализация раньше теста» — отклонение, фиксируется в разделе «Отклонения» (прецедент feat-015).
- **Мутационная дисциплина.** Мутант = копия файла в `mktemp -d` + `sed` по метке `# MAND-*`/`# MO-*`; перед прогоном `! cmp -s orig mutant`; в выводе сьюта строка «мутант X → красный (ожидаемо)» с указанием краснеющего сценария. Чекаут мутациям не подвергается (`git status --porcelain` пуст после прогона).
- **Переносимость (BUG-010).** bash 3.2: нет `declare -A`, `mapfile`, `timeout`, `${v,,}`, `date +%s%N`, GNU-флагов `sed/cp/stat`; `LC_ALL=C` для awk/glob; новые скрипты вызываются как `bash <путь>`. Тест портируемости `FORBID` (как `test-mo-hook.sh [12]`) покрывает все новые lib/скрипты.
- **Тесты.** Формат итога сьюта `Results: N passed, M failed`; `mktemp -d` + `trap`; без записи в чекаут (в т.ч. `__pycache__`); PyYAML/python3 — только оракул, INFO-skip (не PASS) при отсутствии. Сьюты подхватываются глобом `verify-cmd.sh` (регистрация не нужна).
- **Размер задачи ≈ ≤30 строк кода**; тест-сценарии дробятся по группам таблиц DESIGN «Тесты».
- **Не менять:** `hooks/hooks.json`, `sdx/mo/*` (PROC-028, `test-mo-inventory.sh`), `stop-gate.sh`, `archive-verify.sh`, `agents/reviewer.md`.

## Чек-лист задач

### Дорожка Ф — Фундамент (последовательно; блокирует A, B, C)

#### Ф-1. `lib/miniyaml.sh` + `lib/mandate.sh` + `test-mandate-lib.sh`

- [x] **T01** `[TEST]` [PROC-020] `test-mandate-lib.sh`: каркас, корпус L1 (miniyaml-часть), L3, L9
  - Зависит от: —
  - Файлы: `sdx/hooks/test-mandate-lib.sh` (новый; шапка-комментарий как у `test-mo-inventory.sh`)
  - Что: каркас (`mktemp -d`, `trap`, `pass/fail`, `Results:`); хелпер `fx <имя> <содержимое>`; статическая таблица корпуса ~35 фикстур для `my_parse`/`my_load`/`my_*`: блочные списки с отступом и без, flow (одно- и многострочные), смешанная форма, CRLF, комментарии, `---`, кавычки (`''`, `\"`, `\\`), `valid_until: '2026-12-31'`, пустой/`null`/`[]` `stages`; отказы: не YAML, табуляция в отступе, второй документ, дубликат ключа, flow-словарь, якорь/алиас/тег, ключ под скаляром, ключ после элементов списка. L3 — реальный дамп узла (полный `how_to_deliver`, `format: 1`). L9 — портируемость lib-файлов (`FORBID`) + красная сторона на копии с `mapfile`; `grep -n python3` по `lib/*.sh` и `sdx-stage.sh` пусто (инвариант REQ-MAND-33).
  - DoD: `bash sdx/hooks/test-mandate-lib.sh; echo $?` != 0 (нет `lib/miniyaml.sh`); `bash -n`; `grep -nE 'timeout|mapfile|declare -A|%N' sdx/hooks/test-mandate-lib.sh` — только внутри строк мутанта.
  - Закрывает: REQ-MAND-10, 33; критерий 7 (тестовая часть).

- [x] **T02** `[CODE]` [PROC-020] `lib/miniyaml.sh`: `my_parse`, `my_load`, аксессоры, `my_q`
  - Зависит от: T01
  - Файлы: `sdx/hooks/lib/miniyaml.sh` (новый)
  - Что: по DESIGN «`lib/miniyaml.sh`»: awk-разборщик подмножества (стек отступов `tind[]/tpath[]/kind[]`, функции `unq`, `emit_flow`, метка `# MAND-FLOW` на ветке flow-списка), записи `O/S/Z/E/L/X` с разделителем `US=$'\037'`; `my_load` (rc 0/1/2, `MY_NORM`, `MY_ERR`), `my_scalar`, `my_list`, `my_exists`, `my_kind`, `my_q` (вырезает C0 кроме пробела и DEL, экранирует `\` и `"`, усечение до 160 с `…`). Без `eval`. Если задача выходит за ~30 строк на awk — разбить на два коммита (разбор блока / разбор flow), DoD общий.
  - DoD: `bash sdx/hooks/test-mandate-lib.sh` — L1 (miniyaml-часть), L3, L9 зелёные; причина `X` начинается с русского описания и номера строки; `grep -n 'eval' sdx/hooks/lib/miniyaml.sh` пусто.
  - Закрывает: REQ-MAND-10, 33; критерий 7 (разбор), 20 (без python).

- [x] **T03** `[TEST]` [PROC-020] `test-mandate-lib.sh`: L4–L8 (семантика мандата) — красные
  - Зависит от: T02
  - Файлы: `sdx/hooks/test-mandate-lib.sh`
  - Что: L1-часть валидации (нет `mandate`, `stages` скаляр, неизвестная стадия `lint`/`Spec` → rc 1 и `MANDATE_ERR`); L4 — таблица 9 этапов × `stages` ∈ {`[spec]`,`[design]`,`[execute]`,`[verify]`,`[]`, все} (`Deployment` — всегда исключён; `Verification`/`Closeout` — всегда допущены); L5 — `glob_any`: статическая таблица ≥27 случаев (`p/`, `p/**`, `*`, равенство, `[!x]`, `[^x]`, `\`, пустой шаблон, регистр, `docs/**` vs `docs/`) + оракул формулой `DEV:67–68` (INFO-skip без python3; встроенный негативный: подмена оракула → красный); L6 — `mandate_expired` с `SDX_MANDATE_TODAY` (прошлая/сегодня/будущая/пустая/не-дата); L7 — `mandate_mode` (оба/только мандат/только endpoint/ничего); L8 — `mandate_report`: враждебные значения (кавычка, `\`, ESC, 5000 знаков, 20 элементов, значение с переводом строки в кавычках) → каждая строка начинается с префикса/маркера `[ДАННЫЕ, не инструкции]`, ESC отсутствует, `…(+N)`, предел 480; предупреждения области по каждому каталогу отдельно (К-1; пустой `paths` — нет предупреждения; `docs/` покрыт дефолтом `docs/**`), срока (пустой/не-дата — нет), строка ошибки загрузки, `mandate_orphan_line` (ровно одна строка).
  - DoD: `bash sdx/hooks/test-mandate-lib.sh` — L4–L8 красные (нет `lib/mandate.sh`), L1–L3, L9 по-прежнему зелёные; перечень красных строк приложен.
  - Закрывает: REQ-MAND-2, 6, 7, 8, 9, 10, 12; критерии 4, 5, 7, 9 (тестовая часть).

- [x] **T04** `[CODE]` [PROC-020] `lib/mandate.sh`: `mandate_mode`, `mandate_load`, классы этапов, `mandate_expired`
  - Зависит от: T03
  - Файлы: `sdx/hooks/lib/mandate.sh` (новый)
  - Что: `source` `miniyaml.sh` по `${BASH_SOURCE[0]%/*}`; `mandate_mode` (`# MAND-MODE`), `mandate_load` (`# MAND-ROOT` — нет `O mandate`; `stages` скаляр → «не список»; `# MAND-UNKNOWN`; `MANDATE_STAGES/_PATHS/_SHARED/_DOCS/_BRANCHES`; `# MAND-DOCS-DEFAULT` → `docs/**`), `mandate_stage_class` и `mandate_stage_allowed` (метки `# MAND-NEVER` для `Deployment`, `# MAND-ALWAYS` для `Verification`/`Closeout`; пустой `stages` → только `always`), `mandate_expired` (`# MAND-EXPIRY`).
  - DoD: `bash sdx/hooks/test-mandate-lib.sh` — L1, L3, L4, L6, L7 зелёные; L5/L8 ещё красные.
  - Закрывает: REQ-MAND-2, 7, 8, 9, 10, 11 (база); критерии 5, 7.

- [x] **T05** `[CODE]` [PROC-020] `lib/mandate.sh`: `mandate_glob_one`/`mandate_glob_any` (эталон `glob_any`)
  - Зависит от: T04
  - Файлы: `sdx/hooks/lib/mandate.sh`
  - Что: функция из DESIGN дословно (метки `# MAND-GLOB-ESC`, `# MAND-GLOB-PREFIX`), `mandate_glob_any <path> <pat>…`; вызывается при `LC_ALL=C`.
  - DoD: `bash sdx/hooks/test-mandate-lib.sh` — L5 (≥27 случаев + оракул либо INFO-skip) зелёный.
  - Закрывает: REQ-MAND-12; критерий 9 (сверочные случаи).

- [x] **T06** `[CODE]` [PROC-020] `lib/mandate.sh`: `mandate_report`, `mandate_orphan_line`, `mandate_raw_on_write`
  - Зависит от: T05
  - Файлы: `sdx/hooks/lib/mandate.sh`
  - Что: порядок вывода DESIGN (ошибка загрузки → заголовок → три строки полей с `[ДАННЫЕ, не инструкции]`, `my_q`, первые 8 элементов + `…(+N)`, `unset`, предел 480 → предупреждения области по каждому каталогу (К-1; метка `# MAND-SCOPE-WARN`) и срока); санитизация (`# MAND-SANITIZE` — вызов `my_q`); `mandate_orphan_line` (ровно одна строка); `mandate_raw_on_write` — то же правило `mode_re`, что в `mo-hook.sh`.
  - DoD: `bash sdx/hooks/test-mandate-lib.sh` — L5, L8 зелёные; вывод `mandate_report` на реальном дампе (L3) приложен.
  - Закрывает: REQ-MAND-3, 4, 5, 6, 7; критерии 3, 4.

- [x] **T07** `[TEST]` [PROC-020] `test-mandate-lib.sh`: L2 (паритет с `yaml.safe_load`) и мутанты
  - Зависит от: T06
  - Файлы: `sdx/hooks/test-mandate-lib.sh`
  - Что: L2 — тот же корпус через `yaml.safe_load` одним вызовом python (INFO-skip без PyYAML); допустимые расхождения — только в сторону отказа и перечислены поимённо (дубликат, flow-словарь, якорь — К-8); встроенный негативный (подмена оракула). Мутанты по меткам: `MAND-ROOT`, `MAND-UNKNOWN`, `MAND-FLOW` (L1), `MAND-NEVER`, `MAND-ALWAYS` (L4), `MAND-GLOB-PREFIX`, `MAND-GLOB-ESC` (L5), `MAND-EXPIRY` (L6), `MAND-MODE` (L7), `MAND-SANITIZE`, `MAND-SCOPE-WARN` (L8).
  - DoD: `bash sdx/hooks/test-mandate-lib.sh` → `Results: N passed, 0 failed`, 11 строк «мутант … → красный (ожидаемо)» с указанием сценария; время сьюта ≤ 8 с (`time`); `git status --porcelain` пуст.
  - Закрывает: REQ-MAND-10, 31; критерий 7 (паритет), 20.

#### Ф-2. `sdx-stage.sh` + `test-sdx-stage.sh [30]–[41]`

- [x] **T08** `[TEST]` [PROC-020] `test-sdx-stage.sh`: хелпер `setup_mandate`, сценарии [30]–[40] — красные
  - Зависит от: T07
  - Файлы: `sdx/hooks/test-sdx-stage.sh` (только добавление; `[1]–[29]` не правятся)
  - Что: хелпер `setup_mandate <block|flow> <stages…>` (пишет `.mesh/endpoint.yaml` + `.mesh/mandate.yaml` в `TMPPROJ`); [30] регресс без мандата (нет `.mesh/`; только endpoint; только mandate со `stages: [spec]` → `next` идёт на `Technical Design`); [31] `[spec]` (оба вида): `Business Spec`→`Verification` одним `next`, `Verification`→`Closeout`; [32] `[execute, verify]`: `init Discovery` rc 2, `start-stage Discovery false false`→`Execution`; [33] `Deployment` исключён при `delivery` ∈ {pr, branch, artifact.offer}; [34] `--to` исключённого → rc 1, байтовое сравнение `session_state.json`, причина называет стадию; `--to` активного — штатно; [35] нечитаемые мандаты → `next` rc 1, `init` rc 2, файл состояния не создан/не изменён; [36] пустой/отсутствующий `stages`: `Execution`→`Verification`; [37] `no_gates=true` без `execute`: `init Execution` rc 2, `start-stage … true` rc 1; с `execute` штатно; `next` у существующей `no_gates`-сессии — `OK no-op Execution` независимо от мандата; [38] `no_code`+`[execute, verify]`: `start-stage Discovery true false`→`Verification`; [39] `active-set` (источники `no_code`, `no_gates`, `mandate(spec)`; при нечитаемом — rc 1 и `MANDATE-ERROR`); [40] read-only (снимок `find|cksum` до/после `start-stage`/`active-set`).
  - DoD: `bash sdx/hooks/test-sdx-stage.sh` — [1]–[29] и [30] зелёные, [31]–[39] красные (перечень приложен); [40] красный/пропуск до T10.
  - Закрывает: REQ-MAND-1, 8, 9, 10, 11; критерии 1, 5, 6, 7, 8 (тестовая часть).

- [x] **T09** `[CODE]` [PROC-020] `sdx-stage.sh`: `mandate_gate_load`, `is_excluded_by_mandate`, `is_skipped`, врезки в `init`/`next`/`--to`
  - Зависит от: T08
  - Файлы: `sdx/hooks/sdx-stage.sh`
  - Что: функции из DESIGN (меток `# MAND-MODE` в gate, `# MAND-EXCL`); врезки: `cmd_init` после шага 5 и до шага 6 (`mandate_gate_load 2`, затем отказ rc 2 с текстом DESIGN); `cmd_next` после приоритета 0 `no_gates` (`mandate_gate_load 1`); `--to` после проверки `no_code`-исключения (rc 1, `write_stage` не вызывается); цикл форварда `while is_skipped … # MAND-SKIP`. Ленивое подключение lib только в режиме мандата; нет lib при режиме мандата → fail-closed; python не используется.
  - DoD: `bash sdx/hooks/test-sdx-stage.sh` — [1]–[39] зелёные кроме `active-set`/`start-stage`; в частности [30] (регресс) и [31]–[38] зелёные; `grep -n python3 sdx/hooks/sdx-stage.sh` пусто.
  - Закрывает: REQ-MAND-8, 9, 10, 11; критерии 5, 6, 7, 8.

- [x] **T10** `[CODE]` [PROC-020] `sdx-stage.sh`: подкоманды `start-stage` и `active-set`, usage-строка
  - Зависит от: T09
  - Файлы: `sdx/hooks/sdx-stage.sh`
  - Что: `start-stage <желаемый> <no_code> <no_gates>` (литералы и взаимоисключение флагов как в `init`, rc 2; `no_gates` → кандидат только `Execution`, при исключении rc 1 с текстом; иначе вперёд по каноническому порядку до первого неисключённого; нечитаемый мандат → rc 1); `active-set <sid>` (девять строк `<Этап>\t<active|excluded:…>`, `MANDATE-ERROR <причина>` rc 1); usage-строка диспетчера расширена `start-stage|active-set` (К-10).
  - DoD: `bash sdx/hooks/test-sdx-stage.sh` — [30]–[40] зелёные; без мандата `start-stage Business Spec false false` печатает `Business Spec`.
  - Закрывает: REQ-MAND-11, 26; критерии 8, 18 (источники сужения).

- [x] **T11** `[TEST]` [PROC-020] `test-sdx-stage.sh`: мутационная секция [41]
  - Зависит от: T10
  - Файлы: `sdx/hooks/test-sdx-stage.sh`
  - Что: хелпер копирования `sdx-stage.sh` + `lib/` в temp (в сьюте мутантов раньше не было); мутанты `MAND-MODE` (режим без endpoint), `MAND-EXCL` (мандат не исключает), `MAND-SKIP` (цикл не пропускает), `MAND-DEPLOY` (Deployment допущен), `MAND-TO` (нет отказа `--to`) — каждый краснит свой сценарий ([30]/[31]/[33]/[34] соответственно).
  - DoD: `bash sdx/hooks/test-sdx-stage.sh` → `Results: N passed, 0 failed`, 5 строк «мутант … → красный»; прирост времени сьюта ≤ 3 с.
  - Закрывает: REQ-MAND-31; критерии 5, 6, 20.

#### Ф-3. `mandate-info.sh`, `mandate-scope.sh`, `test-mandate-scope.sh`

- [x] **T12** `[TEST]` [PROC-020] `test-mandate-scope.sh`: каркас, сценарии (1)–(10) `mandate-scope.sh` и блок [M] `mandate-info.sh` — красные
  - Зависит от: T07
  - Файлы: `sdx/hooks/test-mandate-scope.sh` (новый)
  - Что: фикстуры — временный git-репозиторий (`main`, `sdx/s1`, файлы в диффе), мандат в обеих формах. (1) нет мандата и мандат без endpoint → нет вывода, отчёт побайтно не тронут; (2) файл вне объединения → `### [FAIL]`, rc 1, `^### \[FAIL\]` срабатывает; (3) `shared_paths` → `### [WARN]`, в т.ч. файл одновременно в `paths` и `shared`; (4) пустой `scope.paths` → нет `FAIL`, `WARN` по `shared` остаётся; (5) `docs_paths` не задан → `docs/**`, `docs/DECISIONS.md` в диффе ok; (6) `--planned docs/DECISIONS.md` при узком `docs_paths` → `FAIL` с причиной; при `docs/**` — нет; пустой `paths` — не FAIL; (7) повторный `--into` заменяет блок, остальной отчёт побайтно сохранён; (8) нечитаемый мандат → `FAIL`-блок, rc 1; (9) сверочные случаи `glob_any` через скрипт; (10) просроченный мандат → не-заголовочная строка `> Предупреждение:` и rc != 1; rc 2 при отсутствии `--into`. Блок [M]: `mode` (три значения), `show` (`none` — пусто; `orphan` — ровно одна строка; `on` — вывод равен `mandate_report`), `status` (все поля; `PyYAML` без записи на диск, снимок до/после), `closeout-mode` (`standard` без мандата и при `artifact.offer`; `bridge` при `pr|branch`; `undefined:patch`; `error:…` при нечитаемом), `closeout-check <sid>` (зелёный; красные: не та ветка, грязное дерево, каталог сессии в `HEAD`).
  - DoD: `bash sdx/hooks/test-mandate-scope.sh; echo $?` != 0 (нет скриптов); `bash -n`; перечень красных строк по (1)–(10) и [M] приложен.
  - Закрывает: REQ-MAND-12, 13, 14, 15, 23, 23a, 26; критерии 2, 9, 10, 16, 18 (тестовая часть).

- [x] **T13** `[CODE]` [PROC-020] `mandate-info.sh`: `mode`, `show`, `status`, `closeout-mode`, `closeout-check`
  - Зависит от: T12
  - Файлы: `sdx/hooks/mandate-info.sh` (новый)
  - Что: CLI по таблице DESIGN (`proj` по умолчанию `${CLAUDE_PROJECT_DIR:-.}`; rc 0 везде кроме `closeout-check` 0/1); `show` вызывает `mandate_report "$proj" "SDX mandate:"` / `mandate_orphan_line`; `status` — строка МО по шаблону DESIGN (`PyYAML`: `PYTHONDONTWRITEBYTECODE=1 python3 -c 'import yaml'`, ничего не пишется; `on_write` обоих файлов; `valid_until`, `digest`); `closeout-mode` (метка `# MAND-BRIDGE`; `undefined:<delivery>` — К-5; `error:…`); `closeout-check` (ветка == `sdx/<sid>`; `git status --porcelain` пуст `# MAND-CHECK-TREE`; в `HEAD` нет путей `.claude/sessions/<sid>/` `# MAND-CHECK-SESSION`; ветку не удаляет и не сливает).
  - DoD: `bash sdx/hooks/test-mandate-scope.sh` — блок [M] зелёный; (1)–(10) по `mandate-scope.sh` пока красные.
  - Закрывает: REQ-MAND-3, 5, 23, 23a, 23b (определение режима), 26; критерии 2, 4, 16, 18.

- [x] **T14** `[CODE]` [PROC-020] `mandate-scope.sh`: `diff ⊆ область`, `--planned`, блок в `verification_report.md`
  - Зависит от: T13
  - Файлы: `sdx/hooks/mandate-scope.sh` (новый)
  - Что: алгоритм DESIGN: стандартный вход — пути по строке; режим не `on` → ничего не печатает и не пишет (rc 0); `mandate_load` fail → блок `### [FAIL] Мандат МО не разобран` rc 1; для каждого файла `in_union`/`in_shared` (`# MAND-OUTSIDE`, `# MAND-SHARED`, `# MAND-EMPTY-PATHS`); `--planned` (`# MAND-PLANNED`); блок между `<!-- SDX-MANDATE-SCOPE:BEGIN/END -->` с заменой awk-ом при повторе (`# MAND-REPLACE`); не-заголовочная строка срока; коды 0/1/2; stdout — сводка `PASS|FAIL K|WARN L`.
  - DoD: `bash sdx/hooks/test-mandate-scope.sh` — (1)–(10) и [M] зелёные; `grep -n 'python' sdx/hooks/mandate-scope.sh` пусто.
  - Закрывает: REQ-MAND-12, 13, 14, 15, 7; критерии 9, 10.

- [x] **T15** `[TEST]` [PROC-020] `test-mandate-scope.sh`: мутанты и портируемость
  - Зависит от: T14
  - Файлы: `sdx/hooks/test-mandate-scope.sh`
  - Что: мутанты (копия скриптов + lib в temp) `MAND-OUTSIDE`, `MAND-SHARED`, `MAND-EMPTY-PATHS`, `MAND-PLANNED`, `MAND-REPLACE` (scope), `MAND-BRIDGE`, `MAND-CHECK-TREE`, `MAND-CHECK-SESSION` (info) — каждый краснит свой сценарий; портируемость (`FORBID`) по `mandate-scope.sh`/`mandate-info.sh`.
  - DoD: `bash sdx/hooks/test-mandate-scope.sh` → `Results: N passed, 0 failed`, 8 строк «мутант … → красный»; время сьюта ≤ 5 с; **gate-контроль Ф:** `bash .claude/sdx/verify-cmd.sh` зелёный (регресс всех прежних сьютов).
  - Закрывает: REQ-MAND-31; критерии 9, 10, 16, 20.

### Дорожка A — `mo-hook.sh` и `mo-session.sh` (после T07; независима от B, C; файлы: `mo-hook.sh`, `mo-session.sh`, `test-mo-hook.sh`, `test-mo-session.sh`)

- [x] **T16** `[TEST]` [PROC-020] `test-mo-hook.sh`: `[2m]` (режим из двух файлов), `[7m]` (охрана `mandate.yaml`), `[8i]` (паритет формы дампа) — красные
  - Зависит от: T07
  - Файлы: `sdx/hooks/test-mo-hook.sh` (только добавление; `[1]–[13]`, `mutate`, `scen*` не правятся)
  - Что: `[2m]` матрица `{endpoint: notice|deny|нет ключа} × {mandate: нет файла|notice|deny|Deny|блочная форма дампа с `on_write: 'deny'`|flow}` в сценарии «не могу проверить» (нет `python3`) → JSON deny ⇔ `deny` хотя бы в одном; `mandate.yaml` без `endpoint.yaml` — тишина. `[7m]` `Write|Edit|MultiEdit|NotebookEdit` × формы пути (`abs`, `rel`, `dots`, `dslash`, `updir`, физический через симлинк) × режим × (область / пустая область / файла `mandate.yaml` нет) → JSON deny, rc 0, причина называет `mandate.yaml`; контроли `.mesh/other.yaml`, `.mesh/inbox/x.json` не блокируются; текст отказа для `endpoint.yaml`/`cursors.json` не изменился (сверка с прежней строкой). `[8i]` паритет `mode_re` и `yaml.safe_load(...)['mandate'].get('on_write')` на формах корпуса (нужен PyYAML, иначе INFO-skip).
  - DoD: `bash sdx/hooks/test-mo-hook.sh` — `[1]–[13]` зелёные, `[2m]` (ячейка «endpoint notice, mandate deny») и `[7m]` красные; перечень приложен.
  - Закрывает: REQ-MAND-16, 17, 1; критерии 11, 12 (тестовая часть).

- [x] **T17** `[CODE]` [PROC-020] `mo-hook.sh`: `MAND-MODE2` (режим из двух файлов)
  - Зависит от: T16
  - Файлы: `sdx/hooks/mo-hook.sh`
  - Что: одна строка-якорь сразу после блока `mode=notice … # MO-MODE` (DESIGN, `# MAND-MODE2`); `mode_re` тот же; `mandate.yaml` читается только после раннего выхода по `endpoint.yaml` (`# MO-EARLY-EXIT` не меняется); файл автономен — `source` не подключается.
  - DoD: `bash sdx/hooks/test-mo-hook.sh` — `[2m]` и `[8i]` зелёные (или честный INFO-skip для `[8i]`), `[1]–[13]` зелёные; `! grep -qE 'git |resolve-session|source |^\. ' sdx/hooks/mo-hook.sh`.
  - Закрывает: REQ-MAND-16, 2, 33; критерий 11.

- [x] **T18** `[CODE]` [PROC-020] `mo-hook.sh`: `MO-GUARD-MANDATE` (охрана `mandate.yaml`)
  - Зависит от: T17
  - Файлы: `sdx/hooks/mo-hook.sh`
  - Что: `is_mailbox_file` получает третий параметр-список имён (дефолт `"endpoint.yaml cursors.json"`, цикл `for f in $names`); вызов для `endpoint/cursors` и его текст/якорь `# MO-GUARD` не меняются; второй вызов `… "mandate.yaml" && deny_json "…"  # MO-GUARD-MANDATE` с текстом DESIGN; охрана безусловна по наличию файла `mandate.yaml` и действует в обоих режимах (К-4).
  - DoD: `bash sdx/hooks/test-mo-hook.sh` — `[7m]` зелёный, `[1]–[13]` без правок утверждений зелёные.
  - Закрывает: REQ-MAND-17; критерий 12.

- [x] **T19** `[TEST]` [PROC-020] `test-mo-hook.sh`: мутанты в `[13]` (+2) и портируемость
  - Зависит от: T18
  - Файлы: `sdx/hooks/test-mo-hook.sh`
  - Что: два вызова `mutate` в `[13]`: `MAND-MODE2` (`/# MAND-MODE2/d` → краснит `[2m]` «endpoint notice, mandate deny»), `MAND-GUARD-MANDATE` (`/# MO-GUARD-MANDATE/d`) и `MAND-NAME` (`s|"mandate.yaml"|"mandate.yml"|`) → краснит `[7m]`; `[12]` (портируемость) по-прежнему зелёный.
  - DoD: `bash sdx/hooks/test-mo-hook.sh` → `Results: N passed, 0 failed`; 3 строки «мутант … → красный»; прирост времени сьюта ≤ 4 с (`time`); `ls -a sdx/mo` без `__pycache__`.
  - Закрывает: REQ-MAND-16, 17, 31; критерии 11, 12.

- [x] **T20** `[TEST]` [PROC-020] `test-mo-session.sh`: сценарии `[10]`–`[12]` (мандат) — красные
  - Зависит от: T07
  - Файлы: `sdx/hooks/test-mo-session.sh` (добавление; прежние «old»-фрагменты и сценарии не правятся)
  - Что: фикстурный корень получает `cp` `sdx/hooks/lib/{miniyaml,mandate}.sh`. `[10]` мандат без `endpoint.yaml` → ровно одна строка, rc 0, python/jq не запускались; `[11]` с мандатом (обе формы): группа под `[ДАННЫЕ, не инструкции]` после строк `inbox`/`leases` и до финальной строки, поля, `on_write` только если задан, враждебные значения не ломают вывод (все строки с префиксом), предупреждения области/срока, rc 0; `[12]` без `python3/PyYAML` + мандат → ровно одна строка, содержащая «не прочитан» (К-2: **мандат при этом показывается и в вырожденном режиме?** — следовать SPEC-поправке REQ-MAND-4: показ мандата не зависит от python/PyYAML, т.е. группа полей печатается в stderr рядом со строкой-предупреждением о зависимостях; сверить с текстом DESIGN «Ветка нет python3/PyYAML» и зафиксировать итоговую форму в тесте; без мандата строка бит-в-бит прежняя).
  - DoD: `bash sdx/hooks/test-mo-session.sh` — сценарии 1–9 прежние зелёные, `[10]`–`[12]` красные; перечень приложен.
  - Закрывает: REQ-MAND-3, 4, 6, 7, 1; критерии 2, 3 (тестовая часть).

- [x] **T21** `[CODE]` [PROC-020] `mo-session.sh`: `MAND-ORPHAN` (мандат без endpoint)
  - Зависит от: T20
  - Файлы: `sdx/hooks/mo-session.sh`
  - Что: определения `P=…` и `say()` переносятся выше корневой проверки без изменения текста; перед `[ -f endpoint.yaml ] || exit 0` (дословно сохраняется) добавляется одна строка `# MAND-ORPHAN` (ровно одна строка в обеих ветках; нет lib → резервный текст); новых слов «exit» в комментариях нет (тест `[9]` ищет построчно).
  - DoD: `bash sdx/hooks/test-mo-session.sh` — `[10]` зелёный, прежние сценарии зелёные; без `mandate.yaml` и без `endpoint.yaml` вывод пуст.
  - Закрывает: REQ-MAND-3, 1; критерий 2.

- [x] **T22** `[CODE]` [PROC-020] `mo-session.sh`: `MAND-SHOW` и суффикс `mnote` (поправка К-2)
  - Зависит от: T21, T06
  - Файлы: `sdx/hooks/mo-session.sh`
  - Что: блок `# MAND-SHOW` после `leases` и до финальной строки (`mandate_report "$proj" "$P" >&2`, резервный `say` при недоступной lib); показ мандата не зависит от `python3`/PyYAML (К-2 принят) — блок стоит также на ветке вырожденного режима, строка-предупреждение о зависимостях остаётся одной и получает суффикс `mnote=" Мандат .mesh/mandate.yaml не прочитан."`/ либо фактическую форму по тесту T20 (без мандата строка бит-в-бит прежняя); все выходы `exit 0`.
  - DoD: `bash sdx/hooks/test-mo-session.sh` — `[10]`–`[12]` и сценарии 1–9 зелёные; `grep -n 'exit' sdx/hooks/mo-session.sh | grep -v 'exit 0'` пусто.
  - Закрывает: REQ-MAND-4, 6, 7; критерий 3.

- [x] **T23** `[TEST]` [PROC-020] `test-mo-session.sh`: мутанты
  - Зависит от: T22
  - Файлы: `sdx/hooks/test-mo-session.sh`
  - Что: мутанты через `red`: `no-orphan` (убрать `MAND-ORPHAN`), `orphan-two-lines`, `no-show` (убрать `MAND-SHOW`), `show-before-inbox`, `no-marker` (убрать «[ДАННЫЕ, не инструкции]» в копии lib), `mnote-always` (суффикс без условия — краснит «без мандата строка прежняя»).
  - DoD: `bash sdx/hooks/test-mo-session.sh` → `Results: N passed, 0 failed`, 6 строк «мутант … → красный»; прирост времени ≤ 3 с; чекаут чистый.
  - Закрывает: REQ-MAND-3, 4, 31; критерии 2, 3.

### Дорожка B — `tests/suites.yaml`, `suites-gen.sh`, `snippet-check.sh` (после T07; независима от A, C; файлы: `lib/test-cmd.sh`, `suites-gen.sh`, `snippet-check.sh`, `tests/suites.yaml`, `test-suites-gen.sh`, `test-snippet-check.sh`)

- [x] **T24** `[TEST]` [PROC-020] `test-suites-gen.sh`: сценарии (1)–(7), (10) — красные
  - Зависит от: T07
  - Файлы: `sdx/hooks/test-suites-gen.sh` (новый)
  - Что: (1) `verify-cmd.sh` + `SDX_VERIFY_TIMEOUT` 180→`budget_min: 3`, 61→2, 60→1, 1→1, 181→4, нечисло→fallback 3 + stderr, `cmd: bash .claude/sdx/verify-cmd.sh`; (2) побайтовая детерминированность (два каталога); (3) идемпотентность (`OK`, файл без изменений; ручная правка `unit.cmd` → `DIFFERS`, файл не изменён; форма `unit: "<cmd>"` читается; `--check` без файла → `ABSENT`); (4) `NOCMD` — файл не создан; (5) автодетект `composer`/`npm`/`phpunit` и приоритет (verify-cmd.sh побеждает); (6) структура: корень `suites`, `unit` — `{cmd, budget_min, selector}`, закомментированные `module`/`regression` присутствуют и **не** активны (`my_exists suites.module` = нет); (7) тест-близнец с `stop-gate.sh` (по классу команды: ветка `sdx/t`, `stage=Execution`, `SDX_STOP_GATE=1`, заглушки `composer`/`npm`/`vendor/bin/phpunit` пишут метку; метка запуска настоящего `stop-gate.sh` совпадает с `TC_KIND`); (10) портируемость.
  - DoD: `bash sdx/hooks/test-suites-gen.sh; echo $?` != 0 (нет `suites-gen.sh`/`lib/test-cmd.sh`); `bash -n`; перечень красных строк приложен.
  - Закрывает: REQ-MAND-18, 19, 20; критерий 13 (тестовая часть).

- [x] **T25** `[CODE]` [PROC-020] `lib/test-cmd.sh`: `test_cmd_resolve`
  - Зависит от: T24
  - Файлы: `sdx/hooks/lib/test-cmd.sh` (новый)
  - Что: зеркало блока `stop-gate.sh:49–64` (порядок `.claude/sdx/verify-cmd.sh` → `composer.json` с `"test"` → `package.json` с `"test"` → `phpunit.xml|.dist`), результаты `TC_KIND` (`verify-cmd|composer|npm|phpunit|none`), `TC_CMD` (`bash .claude/sdx/verify-cmd.sh` | `composer test` | `npm test --silent` | `./vendor/bin/phpunit`). `stop-gate.sh` не трогать.
  - DoD: `bash sdx/hooks/test-suites-gen.sh` — (5) и (7) (близнец) зелёные на уровне `TC_KIND`; `git diff --stat sdx/hooks/stop-gate.sh` пуст.
  - Закрывает: REQ-MAND-18, 20 (одна правда с stop-gate).

- [x] **T26** `[CODE]` [PROC-020] `suites-gen.sh`: создание, `--check`, исходы
  - Зависит от: T25
  - Файлы: `sdx/hooks/suites-gen.sh` (новый)
  - Что: исходы `CREATED|OK|DIFFERS|ABSENT|NOCMD` и rc 2 по таблице DESIGN; `budget_min = ceil(S/60)`, `S=${SDX_VERIFY_TIMEOUT:-180}`, не целое положительное → 180 + stderr (метка `# SG-CEIL`); побайтово детерминированный шаблон с комментариями-образцами `module`/`regression`; `cmd` с `bash` (`# SG-BASH`); не перезаписывает (`# SG-OVERWRITE`), `NOCMD` без файла (`# SG-NOCMD`); чтение существующего файла через `my_*` (обе формы `unit`); запись атомарна (`mktemp` + `mv`), `mkdir -p tests`; скаляры со служебными символами квотируются.
  - DoD: `bash sdx/hooks/test-suites-gen.sh` — (1)–(7), (10) зелёные.
  - Закрывает: REQ-MAND-18, 19, 20; критерий 13.

- [x] **T27** `[TEST]` [PROC-020] `test-suites-gen.sh`: мутанты `SG-*`
  - Зависит от: T26
  - Файлы: `sdx/hooks/test-suites-gen.sh`
  - Что: мутанты `SG-CEIL`, `SG-OVERWRITE`, `SG-NOCMD`, `SG-ORDER` (composer раньше verify-cmd.sh — ловит близнец), `SG-BASH` — каждый краснит свой сценарий.
  - DoD: `bash sdx/hooks/test-suites-gen.sh` → `Results: N passed, 0 failed`, 5 строк «мутант … → красный»; время сьюта ≤ 6 с.
  - Закрывает: REQ-MAND-31, 18–20; критерий 13.

- [x] **T28** `[CODE]` `tests/suites.yaml` (dogfood) + сценарии (8), (9)
  - Зависит от: T27
  - Файлы: `tests/suites.yaml` (новый, tracked), `sdx/hooks/test-suites-gen.sh`
  - Что: сначала сценарии (8) (файл tracked: `git ls-files tests/suites.yaml`; `unit.cmd` == `bash .claude/sdx/verify-cmd.sh`; `budget_min` ≥ 3; `module`/`regression` — комментарии) и (9) (при PyYAML — `safe_load` образца и dogfood-файла; INFO-skip иначе) — красные; затем файл получается запуском `bash sdx/hooks/suites-gen.sh` в корне репозитория (`CREATED`; `.gitignore` не правится) и коммитится.
  - DoD: `bash sdx/hooks/test-suites-gen.sh` — (8), (9) зелёные; `bash sdx/hooks/suites-gen.sh --check` → `OK`; `git ls-files tests/suites.yaml` непусто; `grep -n 'tests/' .gitignore` не находит игнорирования.
  - Закрывает: REQ-MAND-21, 20; критерий 14 (автоматическая часть; `run_suites` вживую — ручной сценарий п.3).

- [x] **T29** `[TEST]` [PROC-020] `test-snippet-check.sh` — красный
  - Зависит от: T07
  - Файлы: `sdx/hooks/test-snippet-check.sh` (новый)
  - Что: `ABSENT` (нет маркеров), `OK`, `STALE`, `BROKEN` (два блока, нет `SDX:END`); CRLF и хвостовые пробелы допустимы; текст вне маркеров не влияет; встроенный мутант «сравнение без учёта содержимого» → красный; портируемость.
  - DoD: `bash sdx/hooks/test-snippet-check.sh; echo $?` != 0 (нет `snippet-check.sh`).
  - Закрывает: REQ-MAND-25; критерий 17 (тестовая часть).

- [x] **T30** `[CODE]` `snippet-check.sh`
  - Зависит от: T29
  - Файлы: `sdx/hooks/snippet-check.sh` (новый)
  - Что: `bash snippet-check.sh <CLAUDE.md> [шаблон]` (шаблон по умолчанию `claude-md-snippet.md` рядом с плагином, путь вычисляется от `${BASH_SOURCE[0]}`); stdout `ABSENT|BROKEN|OK|STALE`, rc 0; без записи; без `--replace`.
  - DoD: `bash sdx/hooks/test-snippet-check.sh` → `Results: N passed, 0 failed` и мутант красный; `bash sdx/hooks/snippet-check.sh CLAUDE.md` печатает одно из четырёх слов.
  - Закрывает: REQ-MAND-25; критерий 17.

### Дорожка C — Проза и документы (после T07 для интерфейсов; зависимости от скриптов — только по именам и CLI из DESIGN; файлы: `commands/*`, `agents/devops.md`, `sdx/templates/claude-md-snippet.md`, `sdx/protocol.md`, `docs/*`, `README*`, `CLAUDE.md`, `test-mo-prose.sh`)

- [x] **T31** `[TEST]` `test-mo-prose.sh`: инварианты `[9]`–`[16]` — красные
  - Зависит от: —
  - Файлы: `sdx/hooks/test-mo-prose.sh` (только добавление; `[17]` — T47)
  - Что: `[9]` «два признака» (`protocol.md`, `docs/designs/mo-interop.md`, `README.md`, `README.en.md`, `docs/DECISIONS.md` ADR-021 п.3): есть `mandate.yaml` в формулировке признака и **нет** «единственный признак»/«единственным признаком»; `[10]` `agents/devops.md`: `mandate.yaml`, `scope.branches`, `теги`, переключатель `endpoint.yaml`, `PYTHONDONTWRITEBYTECODE=1`; `[11]` сниппет: одно предложение о `.mesh/mandate.yaml`, нет `/sdx:pr`, маркеры `SDX:BEGIN`/`SDX:END` по одному; `[12]` `commands/archive.md` и протокол: `bridge`, `(n/a, мандат)`, `closeout-check`, «`archive-verify.sh` не вызывается» при мандате, `change/<C>-<exec>`, `undefined`; `[13]` `commands/verify.md`: `mandate-scope.sh`, `--into`, `--planned`; `[14]` `commands/start.md`: `mandate-info.sh show`, `start-stage`; `[15]` протокол «Активность этапа»: мандат — третий сужающий источник, `Deployment` исключён при мандате, абзац «`Deployment` под МО» сохраняет `Deployment`/`artifact.offer` (инвариант прежнего `[5b]`); `[16]` `docs/DECISIONS.md`: поправки к ADR-020 и ADR-021 с датой. Красная сторона каждого — той же функцией на повреждённой копии (файл без слова / со старой формулировкой).
  - DoD: `bash sdx/hooks/test-mo-prose.sh` — прежние `[1]–[8]` зелёные, `[9]`–`[16]` красные (перечень приложен); на повреждённых копиях инварианты красные — показано.
  - Закрывает: REQ-MAND-22, 23, 24, 27, 28; критерии 15, 16, 17, 19 (тестовая часть).

- [x] **T32** `[DOC]` `commands/start.md` и `commands/import.md`: показ мандата и `start-stage`
  - Зависит от: T31
  - Файлы: `commands/start.md`, `commands/import.md`
  - Что: `start.md` — шаг 1а (`bash "${CLAUDE_PLUGIN_ROOT}/sdx/hooks/mandate-info.sh" show`, вывод показать пользователю **дословно**; ссылка на DEBT-045), шаг 3 — стартовый этап проходит через `sdx-stage.sh start-stage "<stage>" "<no_code>" "<no_gates>"`, ненулевой rc → показать stderr и остановиться до шага 5 (ветка не создаётся), шаг 6 — описание кода `2` дополнено «или мандат МО исключает стартовый этап/не разобран»; `import.md` — тот же `start-stage` перед `init`.
  - DoD: `bash sdx/hooks/test-mo-prose.sh` — `[14]` зелёный; `git diff --stat` затрагивает только эти два файла.
  - Закрывает: REQ-MAND-5, 10, 11; критерии 4, 7, 8.

- [x] **T33** `[DOC]` `commands/next.md` и `commands/status.md`
  - Зависит от: T31
  - Файлы: `commands/next.md`, `commands/status.md`
  - Что: `next.md` — «ограничение цели по флагу» дополнено «и мандатом МО (`stages`; `Deployment` при мандате исключён всегда)», код `1` с причиной «мандат МО исключает этап» = обычный отказ перехода (`[ERROR] Ошибка перехода: …`, `stage` не изменён), при мандате `artifact.offer` отправляется на `Execution`/`Verification` (ДЛ-1); `status.md` — новый чисто читающий шаг между 5 и 6: `mandate-info.sh status` + `sdx-stage.sh active-set <id>`, вывести строку МО и таблицу активности с источниками.
  - DoD: `grep -c 'mandate-info.sh status' commands/status.md` ≥ 1, `grep -c 'active-set' commands/status.md` ≥ 1; `grep -c 'мандат' commands/next.md` ≥ 1; в `status.md` нет инструментов записи (команда остаётся «чисто читающей»: `git diff commands/status.md` не добавляет `Write`/`Edit`/запись файлов).
  - Закрывает: REQ-MAND-8, 9, 11, 26; критерии 5, 6, 18.

- [x] **T34** `[DOC]` `commands/verify.md`: шаг 6а
  - Зависит от: T31
  - Файлы: `commands/verify.md`
  - Что: шаг 6а после создания `verification_report.md` ревьюером и до шага 7: при `mandate-info.sh mode == on` блок `git -c core.quotepath=off diff --name-only "$def"...sdx/<id> -- . ':!.claude/sessions/**' | bash "${CLAUDE_PLUGIN_ROOT}/sdx/hooks/mandate-scope.sh" --into <verification_report.md> --planned …`; правило `--planned` (`docs/specs/` — есть `SPEC.md` или `change_note.md`; `docs/designs/` — есть `DESIGN.md`; `docs/history/plans/` — есть `PLAN.md`; `docs/history/sessions-log.md` и `docs/backlog/` — всегда; `docs/DECISIONS.md` — если сессия вводит/правит ADR, при сомнении включать); затем прочитать отчёт с блоком и свести находки; `mandate_expired` → строка в сводку; без мандата шаг не выполняется. `agents/reviewer.md` не менять.
  - DoD: `bash sdx/hooks/test-mo-prose.sh` — `[13]` зелёный; `git diff --stat agents/reviewer.md` пуст.
  - Закрывает: REQ-MAND-12, 13, 14, 15, 7; критерии 9, 10.

- [x] **T35** `[DOC]` `commands/archive.md`: мост Closeout
  - Зависит от: T31
  - Файлы: `commands/archive.md`
  - Что: `mandate-info.sh closeout-mode`: `standard` — прежний чек-лист; `bridge` — шаги 1–5 (п.2 с учётом `docs_in_repo`: `none` → `(n/a, docs_in_repo: none)` для переносов в `docs/specs|designs` и ADR, `final`/`full` — штатно, К-6), шаги 6–8 `(n/a, мандат)`, вместо `archive-verify.sh` — `closeout-check <sid>`, ветка `sdx/<id>` остаётся, пошаговая инструкция ручной сборки пакета `change/<C>-<exec>` (squash из `sdx/<id>` + `CHANGE.yaml` по `CHANGE.template.yaml` sim-kit; «до `/sdx:pr`, `FEAT-017`»); `undefined:<delivery>` и `error:…` — остановка и вопрос пользователю (стоп-рубрика «контракт»); rc 1 `sdx-stage.sh` при нечитаемом мандате — «гейт не пройден, чек-лист не начинается».
  - DoD: `bash sdx/hooks/test-mo-prose.sh` — `[12]` по `archive.md` зелёный; стандартная ветка чек-листа (шаги 1–8) в диффе не изменена (`git diff commands/archive.md` — только добавления).
  - Закрывает: REQ-MAND-23, 23a, 23b; критерий 16.

- [x] **T36** `[DOC]` `commands/init.md` и `commands/reconcile.md`: `tests/suites.yaml`, устаревший SDX-блок
  - Зависит от: T31
  - Файлы: `commands/init.md`, `commands/reconcile.md`
  - Что: `init.md` — шаг 2c («`tests/suites.yaml` создаёт сверка (шаг 4, `/sdx:reconcile`) вызовом `suites-gen.sh`; файл tracked, паттерн `.gitignore` не добавляется»), шаг 6 (отчёт) включает исход `CREATED|OK|DIFFERS|NOCMD`; `reconcile.md` — шаг 6, две новые категории: (е) `tests/suites.yaml` — `suites-gen.sh --check` (`ABSENT` → применимо на шаге 10 по подтверждению группы вызовом без `--check`; `DIFFERS`/`NOCMD` — только находка), (ж) «устаревший SDX-блок `CLAUDE.md`» — `snippet-check.sh`, замена блока целиком между маркерами **только с явного согласия**; в `--scan-only` ничего не пишется.
  - DoD: `grep -c 'suites-gen.sh' commands/init.md commands/reconcile.md` ≥ 1 в каждом; `grep -c 'snippet-check.sh' commands/reconcile.md` ≥ 1; `bash sdx/hooks/test-init-patterns.sh` зелёный (паттерны `.gitignore` не менялись).
  - Закрывает: REQ-MAND-18, 20, 25; критерии 13, 17.

- [x] **T37** `[DOC]` [PROC-020] `agents/devops.md` и сниппет `claude-md-snippet.md`
  - Зависит от: T31
  - Файлы: `agents/devops.md`, `sdx/templates/claude-md-snippet.md`
  - Что: `devops.md` — «Режим МО» различает два признака; подпункт про мандат (не сливать в ветки вне `scope.branches`, не создавать теги — это `change.merge`/`change.promote` узла; пустой `scope.branches` = «ограничение не задано», но слияние в `main`/`dev`/`stage` и теги под мандатом не действие `devops`; `Deployment` исключён, `prod-guard` и stop-gate не ослабляются); п.3 «Инструкций» уточнён; ссылка «`endpoint.yaml`/`cursors.json` не правишь» → «и `.mesh/mandate.yaml`»; frontmatter не менять. Сниппет — одно предложение в абзаце «МО над стендами» (до фразы «Нет `.mesh/endpoint.yaml` — пункт неприменим»), без `/sdx:pr`, маркеры не менять.
  - DoD: `bash sdx/hooks/test-mo-prose.sh` — `[10]`, `[11]` зелёные (и красные на повреждённых копиях); `sed -n '1,/^---$/p' agents/devops.md` совпадает с `git show main:agents/devops.md`; `bash sdx/hooks/snippet-check.sh CLAUDE.md sdx/templates/claude-md-snippet.md` — не падает.
  - Закрывает: REQ-MAND-22, 24; критерии 15, 17.

- [x] **T38** `[DOC]` `sdx/protocol.md`: подраздел «Мандат», «два признака», границы (а)–(д)
  - Зависит от: T31
  - Файлы: `sdx/protocol.md`
  - Что: «МО-хук» — «два признака» (`endpoint.yaml` — стенды, 0.7.x, FEAT-015; `mandate.yaml` — процесс изменений, 0.9); новый подраздел «Мандат» (признак, показ и `[ДАННЫЕ, не инструкции]`, гейт стадий и таблица отображения, область `verify` с различием `_in_scope` хука и `glob_any`+`docs_paths`, `--planned`, мост Closeout, граница К-8 «разбор — подмножество YAML, строже `safe_load` в сторону отказа», переиздание мандата в середине сессии, В13); границы (а)–(д): (д) снимается, (а) дополняется `mandate.yaml` и безусловной охраной (К-4); ссылки «MI §6 мандат» → §7.
  - DoD: `bash sdx/hooks/test-mo-prose.sh` — `[9]` по `protocol.md` зелёный; `grep -cE 'единственн(ый|ым) признак' sdx/protocol.md` = 0.
  - Закрывает: REQ-MAND-27, 29; критерий 19.

- [x] **T39** `[DOC]` `sdx/protocol.md`: «Активность этапа», «Механизм перехода», «Closeout», «Deployment под МО»
  - Зависит от: T38 (тот же файл)
  - Файлы: `sdx/protocol.md`
  - Что: «Единая шкала…»/«Активность этапа» — мандат как третий сужающий источник, порядок приоритета `no_gates` → флаги/мандат → объём дельты; абзац «`Deployment` под МО`: при мандате исключён всегда, `artifact.offer` — на `Execution`/`Verification`; для `endpoint.yaml` без мандата норма прежняя; таблицу этапов не менять; «Механизм перехода» — `start-stage`, `active-set`, коды отказа мандата (init 2 / next 1, К-7); «Контракт закрытия» — ветка `bridge` (шаги 1–5, `(n/a, мандат)` для 6–8, `closeout-check` вместо `archive-verify.sh`, `undefined:<delivery>` → остановка, `change/<C>-<exec>`).
  - DoD: `bash sdx/hooks/test-mo-prose.sh` — `[12]` по протоколу и `[15]` зелёные (в т.ч. прежний `[5b]`); `bash sdx/hooks/test-sdx-stage.sh` зелёный (таблица этапов не тронута); список пунктов стоп-рубрики без изменений (`diff` с `git show main:sdx/protocol.md` по этому разделу пуст).
  - Закрывает: REQ-MAND-9, 11a, 23, 29; критерии 5, 16, 19.

- [x] **T40** `[DOC]` `docs/DECISIONS.md`: поправки к ADR-020 и ADR-021
  - Зависит от: T39
  - Файлы: `docs/DECISIONS.md`
  - Что: датированная (2026-10-28) поправка к ADR-020 («мандат МО — третий сужающий источник активного набора; `Deployment` при мандате исключён»); датированная поправка к ADR-021 («третий слой границы: мягкая (хук по `scope`) → жёсткая (аудит `diff ⊆ scope` на `/sdx:verify` и у узла) → окончательная (слияние узлом)»; снятие промежуточной границы (д); п.3 «два признака»; п.7 — для `endpoint.yaml` без мандата; безусловная охрана `mandate.yaml`, К-4); перечень имён файлов `mesh_endpoint.py`/`devagent_hook.py`/`MO-INTEROP.md` не уменьшать.
  - DoD: `bash sdx/hooks/test-mo-prose.sh` — `[16]` и `[9]` (ADR-021) зелёные; `grep -c 'mesh_endpoint.py\|devagent_hook.py\|MO-INTEROP.md' docs/DECISIONS.md` не меньше значения на `main`.
  - Закрывает: REQ-MAND-11a, 27, 28; критерий 19.

- [x] **T41** `[DOC]` Дельты `docs/specs/mo-interop.md` и `docs/designs/mo-interop.md`
  - Зависит от: T40
  - Файлы: `docs/specs/mo-interop.md`, `docs/designs/mo-interop.md`
  - Что: перенести дельты этой поставки (REQ-MAND-* в сжатом виде с пометкой `[ADDED]/[MODIFIED]` и ссылкой на ADR); убрать «промежуточная граница до `FEAT-016`» (пункт (7) поправки в шапке дизайна; границы в SPEC); «два признака» в дизайне (`:39`, `:280` и аналогичные места); ссылки на `from.kit`/`version-skew` — как названные отступы.
  - DoD: `bash sdx/hooks/test-mo-prose.sh` — `[9]` по дизайну зелёный; `grep -n 'до `FEAT-016`' docs/specs/mo-interop.md docs/designs/mo-interop.md` пусто; `bash sdx/hooks/test-mo-inventory.sh` зелёный.
  - Закрывает: REQ-MAND-27, 29; критерий 19.

- [x] **T42** `[DOC]` `README.md`, `README.en.md`, `CLAUDE.md`: «два признака», состав
  - Зависит от: T38
  - Файлы: `README.md`, `README.en.md`, `CLAUDE.md`
  - Что: абзац про активацию МО-хуков → «два признака» (RU/EN симметрично, одни и те же факты); перечень `sdx/hooks/` (lib, `mandate-*`, `suites-gen`, `snippet-check`) и `tests/suites.yaml`; запись о версии 2.4.0 (двуязычно); `CLAUDE.md` §6 — тот же перечень и «два признака» (§3 упоминания МО нет — править только то, что есть); три имени `mesh_endpoint.py`/`devagent_hook.py`/`MO-INTEROP.md` остаются на каждой поверхности (проверка (д) `test-mo-inventory.sh`).
  - DoD: `bash sdx/hooks/test-mo-inventory.sh` зелёный; `bash sdx/hooks/test-mo-prose.sh` — `[9]` по README×2 зелёный; `grep -c 'mandate.yaml' README.md README.en.md` ≥ 1 в каждом (визуальная сверка пары записана в коммите).
  - Закрывает: REQ-MAND-27, 29; критерий 19.

### Дорожка З — Завершение (последовательно, после T15, T19, T23, T30, T28, T42 и остальных дорожки C)

- [x] **T43** `[TEST]` [CODE] `test-mo-prose.sh [17]` + `plugin.json` 2.4.0
  - Зависит от: T15, T19, T23, T30, T42
  - Файлы: `sdx/hooks/test-mo-prose.sh`, `.claude-plugin/plugin.json` (и `.claude-plugin/marketplace.json`, если версия указана)
  - Что: сначала `[17]` — `jq -r .version .claude-plugin/plugin.json` == `2.4.0` (красная сторона на копии со старой версией) — красный на 2.3.1; затем `version` 2.3.1 → 2.4.0.
  - DoD: `bash sdx/hooks/test-mo-prose.sh` → `Results: N passed, 0 failed`; `jq -r .version .claude-plugin/plugin.json` → `2.4.0`; `grep -n version .claude-plugin/marketplace.json` согласовано.
  - Закрывает: REQ-MAND-30; критерий 19.

- [x] **T44** `[DOC]` Бэклог `docs/backlog/FEAT-016-…md`
  - Зависит от: T40
  - Файлы: `docs/backlog/FEAT-016-*.md`
  - Что: привести запись к ДЛ-1 (Deployment исключён при мандате по эталону), ДЛ-2 (имена `unit/module/regression`), 0.9.1 вместо 0.9.0, «389» → без числа; `status` на Closeout (C2), не здесь.
  - DoD: `grep -c '0\.9\.1' docs/backlog/FEAT-016-*.md` ≥ 1; `grep -c '389' docs/backlog/FEAT-016-*.md` = 0; `grep -c 'unit' docs/backlog/FEAT-016-*.md` ≥ 1.
  - Закрывает: REQ-MAND-29; критерий 19.

- [x] **T45** `[DOC]` `.claude/sdx/verify-cmd.sh`: актуализация комментария о длительности (без изменения логики)
  - Зависит от: T46
  - Файлы: `.claude/sdx/verify-cmd.sh`
  - Что: строки комментария «~60 секунд, 15 сьютов» обновить по фактическому замеру T46 (число сьютов и время); исполняемая часть не меняется.
  - DoD: `git diff .claude/sdx/verify-cmd.sh` — только строки комментариев (`grep -v '^#'` по дифф-строкам пуст); `bash -n`.
  - Закрывает: REQ-MAND-32; критерий 20.

- [x] **T46** `[INFRA]` Полный прогон с замером времени
  - Зависит от: T43, T44
  - Файлы: — (проверка; результат в сообщении коммита и `change_note`-заметке)
  - Что: `time bash .claude/sdx/verify-cmd.sh`; приложить итоговые строки `Results:` всех сьютов (включая новые `test-mandate-lib`, `test-mandate-scope`, `test-suites-gen`, `test-snippet-check`); записать, какие оракульные ветки дали PASS, какие INFO-skip (python3/PyYAML).
  - DoD: exit 0, все сьюты `0 failed`; **время ≤ 120 с (цель), ≤ 180 с (предел)** — иначе вернуться к задачам-источникам прироста (сьюты T07/T11/T15/T19/T23/T27) и ужать представителей, не теряя мутантов; `ls -a sdx/mo` без `__pycache__`; `find . -name __pycache__ -not -path './.git/*'` пусто; `git status --porcelain` пуст.
  - Закрывает: REQ-MAND-31, 32; критерий 20.

- [x] **T47** `[DOC]` `MANUAL_TEST.md` — ручной сценарий для Verification
  - Зависит от: T14, T26 (скрипты существуют)
  - Файлы: `.claude/sessions/feat-016-mo-mandate-20261028/MANUAL_TEST.md` (новый)
  - Что: перенести DESIGN «Ручной сценарий для Verification» (п.1–5) как «действие / предусловие / ожидаемое / результат (заполняется)»: (1) канал SessionStart для модели (DEBT-045; гарантированный канал — вывод `/sdx:start`); (2) реальный мандат узла (`./mo mandate issue` на чекауте sim-kit 0.9.1 либо `dev.mandate_yaml(...)`; точная команда помечена «не проверена») → `start-stage/next`, `mandate-info.sh show`; (3) `dev.py run_suites` читает `tests/suites.yaml` (допустимо подменить `cmd` на `true` во временной копии); (4) мост Closeout `delivery: pr` на одноразовой сессии (проза `archive.md`); (5) взаимодействие двух PreToolUse на `Bash` с `mandate.on_write: deny` и записью вне области; ветка «выполнить нельзя» → «не проверено» записывается как непроверенное допущение; поля версий (`claude --version`, sim-kit).
  - DoD: `grep -c '^## Случай' MANUAL_TEST.md` ≥ 5; у каждого случая есть строки «Ожидаемый результат» и «Результат (заполняется)»; присутствует фраза «не проверено» в ветках невозможности; прогон — задача `qa`/пользователя на Verification.
  - Закрывает: критерии 3 (канал), 7 (реальный дамп), 14 (Л), 16 (проза), 11–12 (живая часть).

- [x] **T48** `[INFRA]` Проверки инвариантов поставки
  - Зависит от: T46
  - Файлы: —
  - Что: (а) хеши `sdx/mo/*` не изменены: `(cd sdx/mo && sha256sum -c SIMKIT_SHA256)` — `OK`×3 и `git diff --stat main -- sdx/mo` пуст; (б) `git diff --stat main -- hooks/hooks.json sdx/hooks/stop-gate.sh sdx/hooks/archive-verify.sh agents/reviewer.md` пуст; (в) `grep -n python3 sdx/hooks/sdx-stage.sh sdx/hooks/lib/*.sh` пусто; (г) без мандата поведение 2.3.x — прогнать вручную `CLAUDE_PROJECT_DIR=$PWD bash sdx/hooks/mo-hook.sh <<<'{"tool_name":"Bash","tool_input":{"command":"ls"}}'` и `mo-session.sh` в этом репо (`.mesh/` нет) → пустой вывод, rc 0.
  - DoD: все четыре проверки дают указанный результат (вывод приложен).
  - Закрывает: REQ-MAND-1, 31, 33; критерии 1, 20.

- [x] **T49** `[TEST]` Регресс: все прежние сьюты без правок утверждений
  - Зависит от: T46
  - Файлы: —
  - Что: `git diff main -- sdx/hooks/test-*.sh` — только добавления (`grep '^-[^-]'` не находит удалённых/изменённых утверждений, кроме нумерации новых секций); `test-stop-gate.sh`, `test-archive-verify.sh`, `test-hook-wiring.sh`, `test-selftest.sh`, `test-mo-inventory.sh` зелёные.
  - DoD: перечисленные сьюты `0 failed`; дифф — только добавление.
  - Закрывает: REQ-MAND-1, 31; критерий 1, 20.

- [x] **T50** `[DOC]` Заготовка релизных заметок 2.4.0 и записки upstream (текст в каталоге сессии; публикация — на Closeout)
  - Зависит от: T46
  - Файлы: `.claude/sessions/feat-016-mo-mandate-20261028/release_notes_2.4.0.md`, `.claude/sessions/feat-016-mo-mandate-20261028/upstream_note_sim-kit.md` (только в каталоге сессии)
  - Что: двуязычные накопительные заметки (русский блок, `---`, английский; раздел «Границы» с непроверенным: канал SessionStart, `run_suites` вживую, ручной мост Closeout, `Bash`-пути мандата); записка upstream: (1) предложение включить `.claude/sessions/**` в дефолтный `docs_paths` узла (ДЛ-3), (2) ссылки на `/sdx:pr` в §6 эталона, (3) вопросы К-5/К-6 владельцу МО, (4) реестр решений `docs/DECISIONS.md` в `docs_paths`.
  - DoD: оба файла существуют; в заметках есть разделы «Границы»/«Boundaries»; `sdx/mo/*` и `sim-kit` не изменены (`git -C /home/archi/Code/aibok/agentico/meta-orchestrator/sim-kit status --porcelain` пуст относительно начала сессии).
  - Закрывает: REQ-MAND-30; критерий 19 (процесс).

- [x] **T51** `[INFRA]` Финальная сверка процесса
  - Зависит от: T46–T50
  - Файлы: —
  - Что: `jq -r .gate_mode .claude/sessions/feat-016-mo-mandate-20261028/session_state.json` != `auto`; перечень красных сторон (T07/T11/T15/T19/T23/T27/T29/T31) отмечен ссылками на коммиты; раздел «Отклонения» заполнен фактами (если были); чек-лист PLAN актуализирован.
  - DoD: перечисленное подтверждено в сообщении коммита.
  - Закрывает: критерий 21; REQ-MAND-31.

- [x] **T52** `[TEST]` Выборочная проверка тест-близнеца и dogfood после полного прогона
  - Зависит от: T46
  - Файлы: —
  - Что: на чистом чекауте прогнать `bash sdx/hooks/test-suites-gen.sh` и `bash sdx/hooks/suites-gen.sh --check` (ожидаемо `OK`); при наличии sim-kit 0.9.1 (`/home/archi/Code/aibok/agentico/meta-orchestrator/sim-kit`) — по MANUAL_TEST п.3 прочитать `tests/suites.yaml` через `run_suites` с подменой `cmd` (результат — в `verification`-заметку, не гейт).
  - DoD: `--check` → `OK`; если проверка `run_suites` выполнена — результат записан, иначе помечено «не проверено».
  - Закрывает: критерий 14 (Л).

### Closeout (после Verification; не Execution)

- [ ] **C1** `[DOC]` Результаты ручного сценария (`MANUAL_TEST.md`) и канала SessionStart записать как факт либо «не проверено»; синхронизировать текст протокола/ADR при смене статуса допущения.
- [ ] **C2** `[DOC]` Бэклог (ADR-015): статус `FEAT-016` → закрыт (`session`); новые записи `DEBT-`/`IDEA-` — записка upstream (`.claude/sessions/**` в дефолтном `docs_paths`, ссылки на `/sdx:pr` в §6 эталона), К-5/К-6 (вопросы владельцу МО: `patch|worktree`, `docs_in_repo: final|full`), К-11 (посторонний `false` — `DEBT-046`), «периметр self-test МО-хуков» (`DEBT-043`, вторая часть); перенос `SPEC.md`/`DESIGN.md` → `docs/specs|designs`, план → `docs/history/plans/`.
- [ ] **C3** `[DOC]` Релиз: заметки 2.4.0 (двуязычные), тег `v2.4.0` на merge-коммите, `/plugin marketplace update sdx`; push/релиз — только по явной просьбе пользователя.

## Зависимости между задачами

```
Ф-1:  T01 ─> T02 ─> T03 ─> T04 ─> T05 ─> T06 ─> T07
Ф-2:  T07 ─> T08 ─> T09 ─> T10 ─> T11
Ф-3:  T07 ─> T12 ─> T13 ─> T14 ─> T15          (T12 не зависит от Ф-2; последовательно для единого исполнителя Ф)
      T11 + T15 = gate Ф: `verify-cmd.sh` зелёный → старт дорожек A, B, C (A/B/C фактически нужны только T07; C — лишь T31)

Дорожка A (mo-hook, mo-session):
      T07 ─> T16 ─> T17 ─> T18 ─> T19
      T07 ─> T20 ─> T21 ─> T22 ─> T23         (T22 нужен также T06; A-1 и A-2 независимы друг от друга)
Дорожка B (suites / snippet):
      T07 ─> T24 ─> T25 ─> T26 ─> T27 ─> T28
      T07 ─> T29 ─> T30
Дорожка C (проза), T31 первым:
      T31 ─> T32, T33, T34, T35, T36, T37       (разные файлы, параллельны)
      T31 ─> T38 ─> T39 ─> T40 ─> T41           (protocol.md → DECISIONS.md → docs/*mo-interop: последовательно)
      T38 ─> T42
Дорожка З:
      T15, T19, T23, T30, T42 ─> T43 ─> T46 ─> T45, T48, T49, T50 ─> T51
      T40 ─> T44 ─> T46
      T14, T26 ─> T47 ; T46 ─> T52
      T51 ─> [Verification: /sdx:verify, ручной сценарий T47] ─> C1 ─> C2 ─> C3
```

Порядок поставки (DESIGN «Декомпозиция»): 1 (T01–T07) → 2 (T08–T11) → 3 (T12–T15) обязателен; 4 (A: T16–T19), 5 (A: T20–T23), 6 (B: T24–T30) независимы друг от друга после T07; 7 (C: T31–T42) независим от кода (интерфейсы CLI зафиксированы DESIGN); 8 (З: T43–T52) — после всех дорожек. Три параллельные дорожки `developer`: **A** — `mo-hook.sh`/`mo-session.sh` и их сьюты (T16–T23), **B** — `suites-gen.sh`/`lib/test-cmd.sh`/`snippet-check.sh`/`tests/suites.yaml` и сьюты (T24–T30), **C** — проза и документы (T31–T42). Конфликтов по файлам нет (общих файлов у дорожек нет: `test-mo-hook.sh`/`test-mo-session.sh` — только A, `test-mo-prose.sh` — только C до T43).

## Тестовый цикл

- Полный прогон: `bash .claude/sdx/verify-cmd.sh` (глоб `sdx/hooks/test-*.sh` подхватывает новые сьюты); локально по дорожке — `bash sdx/hooks/test-<suite>.sh`.
- Бюджет времени (DESIGN): прирост ≈ +25–30 с к ≈ 78 с → ≈ 105 с; цель ≤ 120 с, предел 180 с (`SDX_VERIFY_TIMEOUT`); замер — T46.
- Окружение без `python3`/PyYAML: оракульные ветки (L2, L5-оракул, `[8i]`, (9)) дают INFO-skip, не PASS; в DoD T07/T19/T28/T46 указывать, какой вариант получен.

## Таблица покрытия критериев SPEC 1–21 задачами

| № | Критерий | Задачи |
|---|---|---|
| 1 | Без `mandate.yaml` — прежнее поведение, все сьюты зелёные | T08 ([30]), T09, T16–T19, T20–T23, T12 (сц. 1), T46, T48, T49 |
| 2 | `mandate.yaml` без `endpoint.yaml` — режима нет, одна строка предупреждения | T03 (L7, orphan-строка), T04, T12 ([M]), T13, T20 ([10]), T21, T23, T08 ([30]в) |
| 3 | `mo-session`: группа полей под «[ДАННЫЕ, не инструкции]», без python — деградация, `exit 0` | T03 (L8), T06, T20 ([11][12]), T22, T23, T47 (канал) |
| 4 | `/sdx:start`: показ группы и предупреждений области/срока; пустой `paths` — без предупреждения | T03 (L8), T06, T12 ([M] show), T13, T32 |
| 5 | `stages` → пропуск этапов; `Deployment` исключён при любом `delivery` | T03 (L4), T04, T08 ([31][32][33][36]), T09, T11, T33, T39 |
| 6 | `--to` исключённого → rc 1, `stage` не изменён | T08 ([34]), T09, T11 (`MAND-TO`), T33 |
| 7 | Нечитаемый/пустой мандат; блочная и flow-формы; паритет с `safe_load` | T01, T02, T03, T04, T07 (L2), T08 ([35][36]), T09, T32, T47 (п.2) |
| 8 | `no_gates` без `execute` — отказ `init`; `no_code`-тип стартует на первом неисключённом | T08 ([37][38]), T10, T32 |
| 9 | `/sdx:verify`: FAIL/WARN/пустой `paths`, `glob_any`, без мандата — нет проверки | T03 (L5), T05, T12 ((1)–(5)(7)–(10)), T14, T15, T34 |
| 10 | `docs/DECISIONS.md` вне `docs_paths` — FAIL при переносе | T12 ((6)), T14, T15 (`MAND-PLANNED`), T34 |
| 11 | `mo-hook`: режим из двух файлов; мутант `MAND-MODE2` | T16 ([2m][8i]), T17, T19 |
| 12 | Охрана `mandate.yaml` от `Write`/`Edit`/`MultiEdit`/`NotebookEdit` | T16 ([7m]), T18, T19 |
| 13 | `tests/suites.yaml` из `init`/`reconcile`: `unit`, бюджет в минутах вверх, идемпотентность, `NOCMD` | T24, T25, T26, T27, T36 |
| 14 | Dogfood `tests/suites.yaml` tracked, структура проверена, `run_suites` читает | T28, T47 (п.3), T52 |
| 15 | `agents/devops.md`: без слияний вне `scope.branches` и без тегов; `prod-guard` не ослаблен | T31 ([10]), T37 |
| 16 | Closeout-мост `delivery: pr|branch`; `artifact.offer` и без мандата — штатный | T12 ([M] closeout), T13, T15, T31 ([12]), T35, T39, T47 (п.4) |
| 17 | Сниппет: одно предложение, без `/sdx:pr`; `reconcile`: находка «устаревший блок» с согласием | T29, T30, T31 ([11]), T36, T37 |
| 18 | `/sdx:status`: строка МО, источники сужения, ничего не пишет | T08 ([39][40]), T10, T12 ([M] status), T13, T33 |
| 19 | Документы приведены к «двум признакам»; ADR-020/021; бэклог; `test-mo-inventory.sh`; версия 2.4.0 | T31 ([9][15][16]), T38–T44, T50 |
| 20 | Полный `verify-cmd.sh` зелёный, время в пределе; `sdx-stage.sh` без python; `sdx/mo/*` не изменены | T07, T11, T15, T45, T46, T48, T49 |
| 21 | Сессия не в `gate_mode: auto` (PROC-020) | Правила исполнения, метки [PROC-020], T51 |

Покрытие REQ-MAND (сверка): 1 — T08/T16/T20/T48/T49; 2 — T03/T04/T17; 3 — T06/T13/T21; 4 — T06/T22; 5 — T13/T32; 6 — T06; 7 — T04/T06/T14; 8–9 — T04/T09/T33/T39; 10 — T02/T09; 11 — T09/T10/T32; 11a, 28 — T40; 12–15 — T05/T14/T34; 16 — T17; 17 — T18; 18–20 — T24–T27/T36; 21 — T28; 22 — T37; 23, 23a, 23b — T13/T35/T39; 24 — T37; 25 — T30/T36; 26 — T10/T13/T33; 27, 29 — T38/T41/T42/T44; 30 — T43/T50; 31 — T07/…/T49; 32 — T45/T46; 33 — T02/T09/T17/T48.

## Отклонения при исполнении (фиксируются здесь, не сглаживаются)
Дорожка Ф (T01–T15), исполнитель `developer`; факты, без сглаживания:

1. **T02 — два коммита** (`af30501` блок + скаляры + аксессоры + `my_q`, flow — заглушка; `e020f01` flow). Разбиение предусмотрено текстом задачи (разбор больше ~30 строк awk); DoD общий и проверен на втором коммите.
2. **T01/T03 — граница L9.** `mandate.sh` перенесена из цикла портируемости T01 в T03: иначе DoD T02 («L9 зелёный») был бы невыполним при отсутствии `lib/mandate.sh`.
3. **`${var//…}` заменён на `_my_rep` (T05).** DESIGN приводит `mandate_glob_one` с `${p//\\/\\\\}` «дословно»; прогон при `BASH_COMPAT=32/41` (эмуляция старой семантики кавычек замены) показал, что удвоение обратной косой там не работает (красные `a\b`, `a\\x`, и `my_q` экранирование). Подставлен переносимый литеральный `_my_rep` (`%%`/`#`-срезы), тот же приём в `my_q`; `mandate_glob_one` дополнен `local LC_ALL=C` (DESIGN требовал «вызывается при LC_ALL=C»). Настоящего bash 3.2 в окружении нет — переносимость подтверждена FORBID-grep, `BASH_COMPAT=32/41` и `busybox awk` (тот же результат `213 passed`), не самим 3.2.
4. **Аксессоры `miniyaml.sh` — чистый bash, не `awk -F`** (DESIGN: «`awk -F"$US"` по `MY_NORM`»). Причина — время: форк-стоимость в окружении высока, `mandate_load` на awk-аксессорах (~15 процессов) утраивал время сьюта. Добавлены безподоболочечные формы `_my_scalar/_my_list/_my_kind/_my_q` (результат в `MY_S/MY_L/MY_K/MY_QV`); публичные `my_*` сохранены. `my_q` возвращает строку **в двойных кавычках** (`"abc"`), усечение — `…` внутри кавычек.
5. **`mandate_report`.** К-1 реализовано как **одна строка предупреждения на каждый непокрытый каталог** (`.claude/sessions/`, затем `docs/`). `docs_paths` показывается эффективным (`docs/**` по умолчанию). Строка ошибки загрузки содержит причину под `my_q` (она частично происходит из данных мандата). Пробные пути — `.claude/sessions/x` и `docs/x`.
6. **Сценарии мандата в `test-sdx-stage.sh` названы `[M30]–[M41]`**, а не `[30]–[41]`: в сьюте уже есть унаследованные `[30]–[32]` (номера в плане/DESIGN устарели). Соответствие 1:1 (M30 = «30» плана и т.д.). Единственные правки унаследованной части файла: строка `SCRIPT=` (теперь `${SDX_STAGE_UNDER_TEST:-…}`) и пара строк `if [ -z "${SDX_STAGE_MUT:-}" ]; then … fi` вокруг прежних сценариев — чтобы мутационные перезапуски `[M41]` не гоняли их; тела сценариев не тронуты.
7. **Мутант `MAND-DEPLOY`** (T11) реализован правкой метки `# MAND-NEVER` в копии `lib/mandate.sh` (метка `MAND-DEPLOY` в коде не вводилась — «Deployment допущен» и есть `never → return 0`).
8. **Мутанты `[Mut]` в `test-mandate-lib.sh`/`test-mandate-scope.sh`/`[M41]`** повторно запускают сам сьют с `MANDATE_ONLY`/`MANDATE_SCOPE_ONLY`/`SDX_STAGE_ONLY` и остановкой на первой красной проверке (иначе бюджет времени не выдерживался). В `mandate-info.sh` метка `# MAND-BRIDGE` стоит на строке `artifact.offer) echo standard` (мутант «bridge и при artifact.offer»), а не на `pr|branch`.
9. **Контракт скриптов, добавленный сверх DESIGN (мелочи):** `active-set` при нечитаемом мандате печатает `MANDATE-ERROR <причина>` первой строкой, затем девять строк **без учёта мандата**, rc 1 (DESIGN: «rc 1 и первая строка»); `mandate-scope.sh` проверяет аргументы (нет `--into`, неизвестный ключ → rc 2) **до** проверки режима; непарные/повторные маркеры `SDX-MANDATE-SCOPE` в отчёте → rc 2, файл не меняется; сводка stdout — `PASS` | `FAIL K` | `WARN L`; `closeout-check` исключает `.mesh/` из проверки чистоты дерева (`git status -- . ':!.mesh'`: каталог узловой, обычно вне git, иначе проверка была бы вечно красной); `closeout-mode`: при отсутствии `delivery` — `undefined:unset`, значение сводится к `[A-Za-z0-9._-]` (прочее `?`, ≤40 знаков); `status` при нечитаемом мандате печатает `valid_until=не_разобран digest=не_разобран`; `mandate-info.sh` при неизвестной подкоманде/без `<sid>` — rc 2.
10. **L2/L5.** Список допустимых расхождений с `safe_load` (оракул, 62 фикстуры) — 12 имён: `anchor block-scalar doc-end-marker dup-key dup-top flow-dict list-of-dicts list-outside-key nested-flow not-yaml quoted-key tag`; всё — «подмножество отказывает, `safe_load` принимает». Таблица L5 — 42 случая (в т.ч. `[ab]/x` против `[ab]/**`, единственный случай, где ветка `MAND-GLOB-PREFIX` не дублируется остальными).
11. **Время (замеры при загруженной машине: load average 2–4, другие процессы; `sys`-время доминирует).** Базовый прогон `verify-cmd.sh` до работ: 55,6 с (15 сьютов). После T15: **86,4 с** (17 сьютов, rc 0). По сьютам: `test-mandate-lib` ≈ 6,0–6,3 с (цель ≤ 8 ✓); `test-sdx-stage` 2,9 → 8,5–11 с (секция `[M30]–[M40]` ≈ +3 с, `[M41]` ≈ +2,5 с: цель ≤ 3 с на `[M41]` ✓, суммарный прирост выше оценки DESIGN «+2 с»); `test-mandate-scope` ≈ 6,7–10 с при цели ≤ 5 с — **не достигнута в этом окружении** (286 запусков процессов в сценариях (1)–(10), мутанты ≈ 3,3 с); дальнейшее сжатие потребует сокращения числа сценариев. Контроль бюджета (180 с) — на gate Closeout (T51).


### Отклонения дорожек A/B/C (перенесены оркестратором из отчётов developer, 2026-10-29)
**A (T16–T23).** T17+T18 одним коммитом `132e77c` (там же исправлен приоритет `&&`/`||` в `[8i]` из T16). Суффикс `mnote` — « Мандат .mesh/mandate.yaml читается без python3 и показан ниже.» вместо «не прочитан» (К-2: мандат в вырожденном режиме показывается; DESIGN «Компоненты» в этом месте устарел). `MAND-SHOW` — функция `mand_show()`, вызывается после `leases`, в вырожденной ветке и при отказе `pull` (расширение). `MAND-ORPHAN` обёрнут `{ …; } >&2`. В сьюте: `date` в `mk_pathdir`, `${PLUGROOT:-$FXROOT}`, `SDX_MANDATE_TODAY`, логирующий `jq` (`jq.log`), `write_mandate`. Flow-форма `[2m]` — flow-списки, `on_write` отдельной строкой. Итог 154 / 43 проверки.
**B (T24–T30).** Метка `SG-BASH` в `lib/test-cmd.sh`, не в `suites-gen.sh`. `SG-ORDER` — не перестановка веток, а `! -f composer.json` в условии verify-cmd (ловит только близнец). Сверх DESIGN: валидация `SDX_VERIFY_TIMEOUT` (не целое/`0`/длиннее 9 цифр → 180 с + stderr), сравнение `budget_min` только для формы-словаря, квотирование скаляров, атомарная запись через `tests/.suites.XXXXXX`. `snippet-check.sh`: нет `CLAUDE.md` → `ABSENT`; нет шаблона/не ровно один блок → rc 2. Цель T27 «≤ 6 с» не достигнута (10–11 с при load ≈ 9). Итог 63 / 22 проверки.
**C (T31–T42).** Коммит T26 дорожки B переписан `--amend` (`2110cbe` → `a7cf002`, добавлен `commands/status.md`; сообщение не менялось) — ошибка процесса, дальше не повторялась. `[11]`: `/sdx:pr([^a-z]|$)` (иначе ловился `/sdx:proto`); `[9]` без `grep -i` по кириллице. Унаследованный `[3]` краснеет при `LC_ALL=C` — не трогали. Шаги команд нумерованы «1а/2а/5а/6а» без перенумерации. `docs_in_repo` в мосте берётся из `mandate-info.sh show`. Итог `test-mo-prose.sh` 79.
**Оркестратор.** Сьют `test-mo-session.sh` писал в cwd файлы `mandate_orphan_line` и `out=…`: `${src//old/new}` в bash ≥ 5.2 раскрывает `&` в замене (`patsub_replacement`) — мутанты с `>&2`/`2>&1` превращались в редиректы в файл. Исправлено `shopt -u patsub_replacement` в `mutate()`; мутанты `orphan-two-lines`/`show-before-inbox` теперь настоящие.

### Отклонения дорожки З (T43–T52)
1. **T46 — время выше цели.** `time bash .claude/sdx/verify-cmd.sh`: real **2m3,851s (123,9 с)**, user 42,6 с, sys 80,2 с; load average 10,5 / 8,2 / 7,8 на 8 ядрах (машина сильно загружена). Цель 120 с превышена на 3,9 с, предел 180 с выдержан; сьюты не ужимались (прирост — `sys`-время от числа запусков процессов). Rc 0, 19/19 сьютов `0 failed`. Оракульные ветки (L2, L5, `[8i]`, (9), `test-suites-gen [9]`) дали **PASS** (python3 + PyYAML 6.0.3); INFO — только именованные границы (`[2.known]`, `[7d]`, `[7e]`, сц. 7 `mo-session`).
2. **T48(в) — `grep python3` не пуст.** В `mandate-info.sh` три строки (63, 65, 75): проба **наличия** python3/PyYAML для строки `status` (`PYTHONDONTWRITEBYTECODE=1 python3 -c 'import yaml'`), задокументирована в шапке скрипта; разбор мандата идёт без python. Остальные файлы перечня — пусто.
3. **T49 — три изменённые строки прежних сьютов** (не утверждения): `test-mo-session.sh` (`date` в PATH-фикстуре; `${PLUGROOT:-$FXROOT}`), `test-sdx-stage.sh` (`SCRIPT=${SDX_STAGE_UNDER_TEST:-…}`); уже указаны в отклонениях Ф/A.
4. **T50 — имена файлов** `release_notes_draft.md` и `upstream_note_draft.md` (по постановке оркестратора, вместо `release_notes_2.4.0.md`/`upstream_note_sim-kit.md` в тексте задачи); в заметки включена версия 2.3.1 (не выпускалась). `git status` sim-kit показывает только посторонние неотслеживаемые пути родительского репозитория (`Claude outputs/`, `agentico/reviews/SDX-MO-vendoring-note-2026-10-28.md`) — не от этой работы.
5. **T51 — сверка.** `gate_mode` = `interactive` (не `auto`); все коммиты ветки `main..HEAD` содержат `Co-Authored-By`. Красные стороны: T07 `0f6fe91`, T11 `11b867e`, T15 `d82a1a2`, T19 `0cc1a7c`, T23 `ed57eed`, T27 `275ba9a`, T29 `1d759b2`, T31 `eb61e72`. T45 и T46 зафиксированы в порядке T46 → T45 (T45 зависит от замера).
6. **T52 — живой `run_suites` не выполнялся** (`dev.py` не импортировался); формат проверен `yaml.safe_load` по схеме строк 285–312: `suites=['unit']`, `unit.cmd` — str, `budget_min=3` — int. «Не проверено» вживую — MANUAL_TEST случай 3.
