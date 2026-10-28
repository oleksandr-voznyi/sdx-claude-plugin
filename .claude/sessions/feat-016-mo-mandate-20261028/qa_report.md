# QA report — feat-016-mo-mandate-20261028 (плагин 2.4.0)

Дата: 2026-10-29. Роль: qa (корректность исполнением). Репозиторий не менялся; мутанты и фикстуры — во временных копиях вне чекаута.

## 1. Полный прогон
`bash .claude/sdx/verify-cmd.sh` -> **19/19 сьютов зелёные, 0 FAIL**, wall time **1 м 54 с (114 с)** при предельных 180 с (машина загружена; sys 74 с). Запас 66 с. Число проверок по сьютам: mandate-lib 213, mo-hook 154, sdx-stage 93, mandate-scope 92, mo-prose 81, suites-gen 63, mo-session 43, resume-contract 40, selftest 36, archive-verify 26, snippet-check 22, mo-inventory 20, stop-gate 20, hook-wiring 18, integration-stage-lifecycle 11, prod-guard 9, default-branch 6, init-patterns 3, resolve-session 3. `sdx/mo/*`: `sha256sum -c SIMKIT_SHA256` OK, `git diff main -- sdx/mo` пуст; `__pycache__` в `sdx/mo/` нет; `sdx-stage.sh` без python (grep).

## 2. Матрица критериев приёмки SPEC 1–21 -> доказательство
Обозначения: сьют:секция/сценарий (номера из вывода прогона). «Мои» = сквозной прогон п.4 / мутанты п.3.

| № | Доказательство | Оценка |
|---|---|---|
| 1 без мандата как 2.3.x | test-sdx-stage [M30] (без `.mesh` / только endpoint / только mandate) + остальные 93 проверки без правок; test-mo-hook [1],[2],[3]-[8] (старые сценарии), test-mo-session [1],[3],[7]; test-mandate-scope (1); test-integration-stage-lifecycle [1]-[11]; мои E2E «без мандата» (mo-session без группы, `next --to Discovery` rc 0, hook молчит) | покрыто |
| 2 mandate без endpoint | test-mo-session [10] (ровно одна строка, python/jq не стартуют); test-sdx-stage [M30]; test-mandate-scope (1); test-mo-hook [1]; мои E2E (одна строка, `start-stage`=Discovery, хук молчит на `Write` в mandate.yaml) | покрыто |
| 3 показ в mo-session | test-mo-session [11] (блок+flow, после inbox/leases, до закрывающей), [4] инъекция, [12] без python/PyYAML (мандат показан, К-2); test-mandate-lib [L8],[L1q]; мои E2E (реальный запуск с `mesh_endpoint.py`, rc 0) | покрыто |
| 4 `/sdx:start`: показ и предупреждения | скриптовая часть: test-mandate-lib [L8],[L8w] (К-1 по каталогам, истёк срок, пустой paths без предупреждения), test-mandate-scope [M] `show`; проза `start.md`: test-mo-prose [14] (токены `mandate-info.sh`, `start-stage`) | скрипты покрыты; проза — только grep токенов |
| 5 набор этапов по `stages`, Deployment | test-mandate-lib [L4] (9 стадий x наборы); test-sdx-stage [M31],[M32],[M33],[M36]; мои E2E: `[spec]` Discovery->Business Spec->Verification; `[execute,verify]` Execution->Documentation->Verification->Closeout | покрыто |
| 6 `--to` исключённого | test-sdx-stage [M34]; мои E2E (`--to Discovery`, `--to Business Spec`: rc 1, stage не менялся, причина в stderr; `--to Execution` из Closeout — штатно) | покрыто |
| 7 нечитаемый/пустой/формы/паритет | test-mandate-lib [L1] корпус, [L2] паритет с `yaml.safe_load`, [L3] форма дампа узла, [L1v]; test-sdx-stage [M35],[M36]; мои E2E (5 нечитаемых вариантов -> rc 1 с причиной; пустой `[]` -> Verification; реальный `dev.py mandate_yaml()`-дамп разобран) | покрыто; граница см. §5 F1 |
| 8 `no_gates` без execute, `no_code`-стартовый | test-sdx-stage [M37],[M38]; мои E2E (`init proto Execution ... true` при `[spec]` и `[spec,verify]` -> rc 2; при `[execute,verify]` -> успех; `start-stage Discovery true false` -> Verification) | покрыто |
| 9 verify под мандатом: FAIL/WARN/пустой/glob_any | test-mandate-scope (2),(3),(4),(8),(9),(10) (+блочная и flow-форма); test-mandate-lib [L5] (таблица из `dev.py glob_any` + оракул); мои E2E (вне области -> `FAIL 1` rc 1 + `### [FAIL]`; shared -> `WARN 1` rc 0; без мандата — ничего не пишет) | покрыто |
| 10 DECISIONS вне docs_paths | test-mandate-scope (5),(6) (`--planned`, К-3); мои E2E (узкий `docs/specs/**`: planned `docs/DECISIONS.md` -> `### [FAIL] Перенос Closeout вне docs_paths`); оркестраторская часть (вычисление `--planned`) — проза `verify.md` шаг 6a, test-mo-prose [13] только токены `mandate-scope.sh`/`--into`/`--planned` | скрипт покрыт; правило вычисления `--planned` — проза |
| 11 mo-hook режимы | test-mo-hook [2m] (2 файла, обе формы), [8i] паритет regex vs safe_load, [13] мутанты; мои E2E (endpoint notice + mandate deny: `Write` вне области -> deny от sim-kit хука) и мутанты M4a/M4c красные | покрыто |
| 12 охрана mandate.yaml | test-mo-hook [7m] (4 инструмента, оба режима, пустая область, прочие `.mesh/` файлы); мои E2E (Write/Edit/MultiEdit/NotebookEdit -> deny с именем `mandate.yaml`; `.mesh/foo.txt` — пропуск; путь с `src/../.mesh/mandate.yaml` — deny); мутант M4b красный | покрыто |
| 13 `suites.yaml` из init/reconcile | test-suites-gen [1] ceil (180->3, 61->2), [2],[3] идемпотентность, [4] NOCMD, [5],[6], [7] близнец stop-gate, [9] оракул safe_load, [Mut]; мои E2E (CREATED, второй запуск OK, правка cmd -> DIFFERS и файл не тронут, `safe_load` читает). **Проводка в `init.md` (2в) и `reconcile.md` (е)**: тестом не закреплена (§4 G1) | скрипт покрыт; проза без теста |
| 14 dogfood `tests/suites.yaml` | test-suites-gen [8] (tracked, структура, `--check` = OK), [9]; `dev.py run_suites` вживую — только ручной (MANUAL_TEST случай 3); по коду `run_suites` читает `suites.unit.cmd`/`budget_min` — формат совпадает | автотест + ручной (не выполнялся мной) |
| 15 devops.md | test-mo-prose [10] (mandate.yaml, scope.branches, теги, prod-guard, красные стороны) | покрыто grep-инвариантом |
| 16 Closeout-мост | test-mo-prose [12] (archive.md/protocol.md: bridge, `(n/a, мандат)`, closeout-check, `change/<C>-<exec>`, undefined, «не вызывается»); скриптовая часть: test-mandate-scope [M] `closeout-mode`/`closeout-check`; мои E2E (`bridge`; без мандата `standard`; `closeout-check` нашёл FAIL по ветке/грязному дереву) | покрыто; пункты «docs_in_repo: none» и «сохранение ветки» в archive.md не закреплены (§4 G2) |
| 17 сниппет и reconcile | test-mo-prose [11]; test-snippet-check (22: ABSENT/BROKEN/OK/STALE, красная сторона); мои E2E (старый абзац -> `STALE`, шаблон -> `OK`). Находка/замена в `reconcile.md` (ж) — проза без теста (§4 G1) | скрипт покрыт; проза без теста |
| 18 `/sdx:status` | test-mandate-scope [M] `status`; мои E2E (строка МО, два признака, `on_write` обоих, "обёртка берёт deny", digest). Шаг 5а в `commands/status.md` — только проза, теста нет (§4 G1) | скрипт покрыт; проза без теста |
| 19 документы, версия | test-mo-prose [4],[9],[15],[16],[17] (две стороны, ADR, 2.4.0); test-mo-inventory (20); `plugin.json` = 2.4.0 | покрыто |
| 20 прогон/время/без python/sdx/mo | §1; test-mandate-lib [L9] и test-suites-gen [P] (переносимость, нет python); test-mo-hook [11] (чекаут `sdx/mo/` не тронут) | покрыто |
| 21 не `auto` | `session_state.json`: `gate_mode: interactive` (на момент проверки). Процессный критерий, автотеста нет; T51 PLAN ссылается на ручную сверку | только процесс, проверено чтением |

## 3. Собственные мутанты (копия репозитория вне чекаута; запуск релевантных сьютов)
Все мутанты отличались от оригинала (NO-DIFF не было). Исход: красные = существующий сьют поймал.

| ID | Мутация | Красные сьюты (FAIL) | Итог |
|---|---|---|---|
| M1 | `mandate.sh`: не проверять неизвестную стадию (`_mandate_bad_stage` вырезан) | mandate-lib (2), sdx-stage (2) | поймано |
| M2 | `mandate.sh`: класс `execute` всегда разрешён (`next` на Execution при мандате без execute) | sdx-stage (14), mandate-lib (5) | поймано |
| M3a | `mandate-scope.sh`: shared-файл не даёт WARN | mandate-scope (5) | поймано |
| M3b | `mandate_in_union` без `shared_paths` (shared-only файл -> FAIL) | mandate-scope (1), mandate-lib (1) | поймано (тонко: по одному FAIL) |
| M4a | `mo-hook.sh`: mandate перекрывает endpoint менее строгим `notice` | mo-hook (1) | поймано (одним сценарием) |
| M4b | `mo-hook.sh`: охрана mandate.yaml только в режиме deny | mo-hook (3) | поймано |
| M4c | `mo-hook.sh`: значение `on_write` mandate регистрозависимо (`DENY` не распознан) | mo-hook (3) | поймано |
| M5a | `suites-gen.sh`: при DIFFERS перезаписывает файл | suites-gen (2) | поймано |
| M5b | `suites-gen.sh`: `--check` пишет файл | suites-gen (2) | поймано |
| M6 | `mo-session.sh`: мандат показывается до `pull`/`inbox` | mo-session (3) | поймано |
| M7 | `mandate-info.sh closeout-mode`: `branch` не мост | mandate-scope (1) | поймано |
| M9 | `sdx-stage.sh`: проверка `--to` на исключённый этап отключена | sdx-stage (3) | поймано |
| M10 | `mandate_expired`: `-lt` -> `-le` (граница срока) | mandate-lib (2) | поймано |
| M11 | `mandate.sh`: нет дефолта `docs/**` | mandate-scope (7), mandate-lib (6) | поймано |
| M12 | `mo-session.sh`: нет показа мандата в деградированной ветке без python | mo-session (2) | поймано |
| M14 | `mandate.sh`: Deployment разрешён (`never` -> `execute`) | sdx-stage (6), mandate-lib (3) | поймано |
| M17 | `mandate-scope.sh`: заголовок находки `##` вместо `### [FAIL]` (гейт-regex не сработает) | mandate-scope (7) | поймано |
| P1 | `reconcile.md`: удалены вызовы `suites-gen.sh`/`snippet-check.sh` | test-mo-prose зелёный | **НЕ поймано** |
| P2 | `status.md`: удалён вызов `mandate-info.sh status` | test-mo-prose зелёный | **НЕ поймано** |
| P3 | `init.md`: удалён абзац про `suites-gen.sh` | test-mo-prose зелёный | **НЕ поймано** |
| P4 | `archive.md`: убраны `docs_in_repo` и `sdx/<sid>` (сохранение ветки) | test-mo-prose зелёный | **НЕ поймано** |
| P5 | `verify.md`: убран `mandate-scope.sh` | mo-prose (1) | поймано |
| P6 | `next.md`: слово `mandate` заменено на `MANDATE` | test-mo-prose зелёный | **НЕ поймано** (в `next.md` нет закреплённого токена мандата) |

Вывод: все 17 мутантов поведения (скрипты) красные. Мутанты прозы P1-P4, P6 не краснят ничего — это дыры покрытия (§4).

## 4. Дыры покрытия
- **G1 (критерии 13, 17, 18).** Проводка скриптов в командах не закреплена grep-инвариантом: `commands/reconcile.md` пункты (е)/(ж) (`suites-gen.sh --check`, `snippet-check.sh`), `commands/init.md` 2в, `commands/status.md` 5а (`mandate-info.sh status`, `active-set`). Убрать вызов — все 19 сьютов остаются зелёными. Несоответствие с SPEC REQ-MAND-31 («проза закрепляется grep-инвариантами»).
- **G2 (критерий 16, REQ-MAND-23b).** В `archive.md` не закреплены `docs_in_repo: none` (`(n/a, docs_in_repo: none)`) и сохранение ветки `sdx/<sid>` / проверка чистого дерева как текст; закреплены только bridge, `(n/a, мандат)`, `closeout-check`, `change/<C>-<exec>`, `undefined`, «не вызывается». Скрипт `closeout-check` ветку/чистоту проверяет (E2E).
- **G3.** `next.md`: нет grep-инварианта на мандатные формулировки (P6).
- **G4 (критерий 10).** Алгоритм вычисления `--planned` живёт в прозе `verify.md` (шаг 6a, строка 42); тест фиксирует только наличие флага.
- **G5.** Критерии 14 (`run_suites` вживую), 4 (прозаическая часть), 21 (процесс) — не автоматизируемы; MANUAL_TEST не исполнял.
- Слабо защищённые тонкие места (мутант ловится ровно одним сценарием): M4a (`mo-hook`, одно срабатывание) и M3b (по одному FAIL). Красные стороны есть, но запас мал.

## 5. Сквозной прогон на фикстуре (временный git-проект, `.mesh/endpoint.yaml` + `.mesh/mandate.yaml` по форме `yaml.safe_dump` из `dev.py mandate_yaml()`: `stages:[execute,verify]`, `scope.paths:[src/**]`, `shared_paths:[shared/**]`, `docs_paths:[docs/**]`, `on_write: deny`, `delivery: pr`; отдельно прогнан и настоящий дамп `dev.mandate_yaml()` с подменой реестра)

| # | Сценарий | Ожидалось | Получено | Итог |
|---|---|---|---|---|
| 1 | `start-stage Discovery false false` | `Execution` | `Execution` rc 0 | PASS |
| 2 | `init t1 feat Discovery ...` | rc 2, причина | rc 2, «мандат МО исключает стартовый этап 'Discovery'» | PASS |
| 3 | `init ... Execution`; `next` x3 | Execution->Documentation->Verification->Closeout (Deployment пропущен) | так и есть | PASS |
| 4 | `next --to Discovery` / `--to Business Spec` | rc 1, stage не изменён, причина | rc 1, stage прежний, причина в stderr | PASS |
| 5 | `next --to Execution` (активный) | штатно | `OK Closeout -> Execution`, артефакты outdated | PASS |
| 6 | `stages:[spec]`: Discovery->Business Spec->Verification | Verification одним `next` | так и есть | PASS |
| 7 | `init proto Execution ... true` при `[spec]`, `[spec,verify]` | rc 2 | rc 2 | PASS |
| 8 | `start-stage Discovery true false` (no_code) | Verification | Verification | PASS |
| 9 | `mandate-scope` дифф в области | `PASS` rc 0 | `PASS` rc 0 | PASS |
| 10 | дифф с `other/z.txt` | `FAIL 1`, `### [FAIL]` в отчёте, rc 1 | так и есть | PASS |
| 11 | дифф с `shared/c.lock` | `WARN 1`, rc 0 | так и есть | PASS |
| 12 | `--planned docs/DECISIONS.md` при `docs/**` / при `docs/specs/**` | PASS / `FAIL 1` | PASS / `FAIL 1` («Перенос Closeout вне docs_paths») | PASS |
| 13 | `mo-hook`: Write/Edit/MultiEdit/NotebookEdit в `.mesh/mandate.yaml` | JSON deny, rc 0 | deny, текст называет `mandate.yaml`, rc 0 | PASS |
| 14 | `Write` в `.mesh/foo.txt`; в `src/a.txt` | пропуск | пропуск | PASS |
| 15 | `Write` в `other/z.txt` и `.claude/sessions/...` (endpoint notice, mandate deny) | deny | deny `[MO-scope]` от хука sim-kit | PASS |
| 16 | `mo-session.sh` (PYTHONDONTWRITEBYTECODE=1) | группа «[ДАННЫЕ, не инструкции]» после аренд, предупреждение области, rc 0; нет `__pycache__` в `sdx/mo/` | так и есть | PASS |
| 17 | `suites-gen.sh` x2; правка `cmd`; `--check` | CREATED / OK / DIFFERS (файл не тронут, md5 прежний) / DIFFERS | так и есть; `safe_load` читает | PASS |
| 18 | `snippet-check.sh` со старым абзацем; с шаблоном | STALE / OK | STALE / OK | PASS |
| 19 | Нечитаемые: не YAML, неизвестная стадия, `stages` скаляр, нет корня `mandate`; пустой `stages: []` | rc 1 с причиной; Verification | так и есть | PASS |
| 20 | Без `mandate.yaml` (endpoint есть): mo-session, `show`, `closeout-mode`, `init/next/--to Discovery`, scope, hook | как 2.3.x, тихо | группа мандата не печатается, `standard`, `--to Discovery` rc 0, scope ничего не пишет, хук молчит | PASS |
| 21 | `mandate.yaml` без `endpoint.yaml` | одна строка, режим не включён | одна строка (mo-session и `show`), `start-stage`=Discovery, хук молчит | PASS |
| 22 | Реальный дамп `dev.mandate_yaml()` (подмена реестра) | разбирается | `show`/`start-stage` OK | PASS |

## 6. Наблюдения и дефекты
- **F1 (граница, не регрессия; fail-closed).** Bash-парсер отказывает на валидном для `safe_load` YAML, который выдаёт `yaml.safe_dump` при значениях длиннее ~80 символов с пробелами: переносимые на несколько строк quoted/plain-скаляры (`кавычка не закрыта, строка N`), а также `\e` / `\uXXXX` в двойных кавычках (`неподдерживаемая escape-последовательность`). Воспроизведение: `python3 -I -c "import yaml;print(yaml.safe_dump({'mandate':{'executor':'dev-1','note':'word '*40,'stages':['execute']}},sort_keys=False))" > .mesh/mandate.yaml; sdx-stage.sh start-stage Discovery false false` -> rc 1, `/sdx:start`/`/sdx:next` откажут. Для известных ключей реального дампа (`dev.py` 0.9.1: стадии, пути, короткие скаляры, `how_to_deliver.*`) значения коротки, дамп разбирается (проверено), так что на реальном мандате сегодня не срабатывает; станет блокирующим, если узел добавит длинный свободный текст в мандат. Названо в SPEC (К-8, «строже safe_load в сторону отказа»), но случай «многострочный скаляр от `safe_dump`» там как конкретный пример не фигурирует. Рекомендация: записать как `DEBT-` (парсер для многострочных скаляров или явный отказ с понятной причиной в протоколе).
- **F2 (косметика).** `suites-gen.sh` в сообщении `DIFFERS` печатает `budget_min="3" vs 3` (кавычки у текущего значения, число у ожидаемого) — выглядит как расхождение при равных значениях; смысл сообщения (расходится `cmd`) понятен, но вводит в заблуждение, если расходится только `cmd`.
- **F3 (косметика).** `sdx-stage.sh active-set` при нечитаемом мандате печатает `MANDATE-ERROR` и затем девять строк `active` (строки без сужения). Для `/sdx:status` ошибка видна, но таблица выглядит «всё активно»; гейт при этом отказывает. Допустимо, но можно подавлять таблицу.
- Дефектов, меняющих исход гейтов, не найдено. Артефакт `verification_report.md` (от reviewer) в рабочем дереве untracked — я его не трогал.

## 7. Итог
Автоматическая часть: полный прогон зелёный (19/19, 114 с из 180 с), все 17 поведенческих мутантов краснеют, сквозной прогон на фикстуре (22 сценария) PASS, режим «без мандата» неотличим от 2.3.x. Открыто: дыры покрытия прозы G1-G4 (рекомендую добавить grep-инварианты в `test-mo-prose.sh` на `reconcile.md` (е)(ж), `init.md` 2в, `status.md` 5а, `archive.md` `docs_in_repo`/ветка, `next.md`), критерии 14 (живой `run_suites`), 4 (проза), 21 (процесс) — ручные; F1 — кандидат в бэклог.
