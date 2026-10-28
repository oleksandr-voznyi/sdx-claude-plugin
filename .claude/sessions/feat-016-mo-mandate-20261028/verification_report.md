# Verification Report: feat-016-mo-mandate-20261028

## Сводка
- Объём: полный (SPEC + DESIGN + PLAN), no_code: нет, no_gates: нет; поставка 2.4.0 «мандат и декларации» (40 файлов, `delivery.diff` против основной ветки, без каталога сессии).
- Итог: **FAIL**
- Находки: FAIL: 1, WARN: 8, INFO: 11
- Метод: fresh-eyes сверка контракта (SPEC REQ-MAND-1…33, 11a, 23a/23b; поправки К-1…К-6; DESIGN; отклонения PLAN) с diff, плюс сверка с эталоном (`sdx/mo/MO-INTEROP.md` §6/§7, `sdx/mo/devagent_hook.py`, `sim-kit/core/dev.py` `glob_any`/`audit`/`run_suites`/`mandate_yaml`, `policy/tests.yaml`) и текущими файлами репозитория. Тесты не запускались (у ревьюера нет `Bash`): покрытие ниже **видимое** (прочитано по diff), а не доказанное прогоном.

### Сводка по осям
| Ось | FAIL | WARN | Комментарий |
|---|---|---|---|
| Полнота | 0 | 4 | Все REQ имеют реализацию; пробелы — в grep-инвариантах прозы, в переносе отдельных формулировок в постоянные документы и в ручной части (MANUAL_TEST не заполнен). Лишнего кода (scope creep) нет; дополнения сверх DESIGN названы в PLAN «Отклонения» (п.9 Ф, A, B) и безвредны. |
| Корректность | 1 | 2 | Семантика области совпадает с `dev.py` (`glob_any`, пустой `scope.paths`, дефолт `docs/**`, `shared_paths` → WARN); поля мандата — по `mandate_yaml()`; формат `tests/suites.yaml` читается `run_suites` (`cmd` строка, `budget_min` минуты, `selector` пустой — не используется); имена наборов — по `policy/tests.yaml` (`app:unit`). Дефект — гарантия «более строгий из двух `on_write`» не действует при python3 без PyYAML. |
| Когерентность | (тот же FAIL) | 3 | Пять носителей в основном согласованы (отображение стадий, «Verification/Closeout всегда», «Deployment при мандате исключён всегда», мост Closeout, охрана `mandate.yaml`, предупреждения по каталогам). Расхождения: протокол обещает fail-closed там, где код fail-open (FAIL); слияние в `main` на стандартном Closeout под мандатом с `artifact.offer`; тексты `status.md`/дельты `docs/specs`. |

Отдельно по запрошенным пунктам:
- (1) Обратная совместимость: каждая новая ветка кода видимо стоит за предикатом «оба файла» (`_mandate_try`, `mandate_mode`, `MAND-MODE2` после `MO-EARLY-EXIT`, `mand_show`, `closeout-mode → standard`, `mandate-scope.sh` выходит молча). Безусловные отступы ровно названные: `tests/suites.yaml`, `/sdx:status`/сниппет/`reconcile`, охрана `mandate.yaml` при `endpoint.yaml` (К-4), usage-строка (К-10), строка «мандат без endpoint» (REQ-MAND-3). Одна оговорка — INFO-4 (`start-stage` без мандата при `no_code`).
- (2) Пять носителей — см. ось когерентности; расхождения — FAIL-1, WARN-1, WARN-3, WARN-5, WARN-7, INFO-1.
- (3) Эталон: `mandate_glob_one` дословно повторяет формулу `dev.py:70` (`fnmatch` ∨ `fnmatch(p.rstrip("/")+"/*")` ∨ `startswith(p.rstrip("*").rstrip("/")+"/")`), нейтрализуя `\` и `[^` (в Python `fnmatch` `[^` — литерал); `.mesh/*` из `_in_scope` хука не перенесён (по SPEC); исходы `mandate-scope.sh` = `audit()` `dev.py:383–387`.
- (4) Тесты: у каждой новой ветки видна красная сторона (мутанты по меткам `MAND-*`/`SG-*`/`SC-CMP`, встроенные негативы оракулов L2/L5); тавтологий на ключевых сценариях не найдено; сьюты работают в `mktemp -d`, мутанты — на копиях; `test-mo-session.sh` исправлен от записи в cwd (`patsub_replacement`). Пробелы — WARN-4, WARN-8.
- (5) Число вендорённой версии sim-kit в `sdx/protocol.md` и `docs/DECISIONS.md` **отсутствует** (только поколения формата «0.7.x»/«0.9»). Но новая дельта `docs/specs/mo-interop.md` пишет «вендоринг 0.9.1» — WARN-5.
- (6) Проза команд ↔ интерфейсы скриптов: подкоманды, флаги, коды и исходы в `start/import/next/verify/archive/init/reconcile` совпадают со скриптами; расхождение — `status.md` («МО: нет», WARN-3); мелочи — INFO-11.

## Матрица трассируемости

| Требование / критерий | Реализация (файл) | Тест | Когерентность | Статус |
|---|---|---|---|---|
| REQ-MAND-1 (без мандата — как 2.3.x; исключения) | `sdx-stage.sh` `_mandate_try` (2×`-f`), `mo-hook.sh` `MAND-MODE2` после early-exit, `mo-session.sh` `mnote`/`mand_show`, `mandate-scope.sh` ранний выход | да: `test-sdx-stage [M30]`, `test-mo-session m10b/m12c` + мутант `mnote-always`, `test-mo-hook [7m.d]`, `test-mandate-scope (1)`, прежние сьюты | ok (INFO-4) | OK |
| REQ-MAND-2 (признак — оба файла) | `lib/mandate.sh` `mandate_mode`, `sdx-stage.sh` `MAND-MODE` | да: L7 + мутант `MAND-MODE`, `[M41] MAND-MODE`, `[2m.orphan]` | ok | OK |
| REQ-MAND-3 (мандат без endpoint) | `mandate_orphan_line`, `mo-session.sh` `MAND-ORPHAN`, `mandate-info.sh show` | да: `test-mo-session [10]` + `no-orphan`/`orphan-two-lines`, `[M] show orphan` | ok (INFO-1) | OK |
| REQ-MAND-4 (+К-2) (показ на SessionStart) | `mandate_report`, `mo-session.sh` `mand_show` (после leases, в вырожденном режиме, после отказа pull) | да: `[11]`, `[12]`, мутанты `no-show`/`show-before-inbox`/`no-marker`; L8 | ok (DESIGN «Компоненты» устарел — известно) | OK |
| REQ-MAND-5 (показ на `/sdx:start`) | `commands/start.md` шаг 1а → `mandate-info.sh show` | grep `test-mo-prose [14]`; `[M] show on` = `mandate_report` | ok | OK |
| REQ-MAND-6 (+К-1) (предупреждения по каталогам) | `mandate_report` `MAND-SCOPE-WARN` (по каждому каталогу; пустой `paths` — нет) | да: L8w + мутант | ok | OK |
| REQ-MAND-7 (срок) | `mandate_expired`, `mandate_report`, строка `> Предупреждение:` в `mandate-scope.sh` | да: L6 + `MAND-EXPIRY`, `(10)` | ok (INFO-3) | OK |
| REQ-MAND-8 (третий сужающий источник, отображение) | `_mandate_class`, `mandate_stage_allowed`, `is_skipped`/`MAND-SKIP` | да: L4, `[M31][M32][M36]`, мутанты `MAND-SKIP`/`MAND-EXCL` | ok | OK |
| REQ-MAND-9 (V/C всегда; Deployment исключён всегда) | класс `always`/`never` | да: L4, `[M33]` (pr/branch/artifact.offer), `MAND-NEVER`/`MAND-ALWAYS`/`MAND-DEPLOY`; grep `[15]` | ok (INFO-10) | OK |
| REQ-MAND-10 (нечитаемый — fail-closed; паритет с safe_load) | `lib/miniyaml.sh`, `mandate_load` | да: L1 (~60 фикстур), L2 оракул + перечень расхождений «только в сторону отказа», `[M35]` | ok (К-8 названа в протоколе) | OK |
| REQ-MAND-11 (`--to`, init, start-stage, no_gates/no_code) | `cmd_init` шаг 5a, `MAND-TO`, `cmd_start_stage` | да: `[M32][M34][M37][M38]`, `MAND-TO` | ok (INFO-4) | OK |
| REQ-MAND-11a, 28 (ADR-020/021 поправки) | `docs/DECISIONS.md` | grep `[16]`, `[9]` (ADR-021) | ok | OK |
| REQ-MAND-12 (`diff ⊆ область`, `glob_any`) | `mandate-scope.sh`, `mandate_glob_one/_any`, `mandate_in_union` | да: L5 (42 случая + оракул формулой `dev.py`), `(2)(5)(9)`, `MAND-GLOB-*`, `MAND-OUTSIDE` | ok — совпадает с `dev.py:69–70, 383–387` | OK |
| REQ-MAND-13 (FAIL/WARN/пустой paths) | `mandate-scope.sh` `MAND-OUTSIDE`/`MAND-SHARED`/`MAND-EMPTY-PATHS` | да: `(2)(3)(4)` + мутанты | ok | OK |
| REQ-MAND-14 (+К-3) (переносы Closeout) | `--planned`, `verify.md` шаг 6а | да: `(6)` + `MAND-PLANNED`; grep `[13]` | ok (INFO-2) | OK |
| REQ-MAND-15 (нет мандата — нет проверки) | ранний выход `mandate-scope.sh` | да: `(1)` | ok | OK |
| REQ-MAND-16 (более строгий `on_write`) | `mo-hook.sh` `MAND-MODE2` | да для «нет python3»: `[2m]`, `[8i]`, мутант `MAND-MODE2`; **нет** для «python3 без PyYAML» | **дрейф** (протокол обещает fail-closed) | **FAIL** |
| REQ-MAND-17 (+К-4) (охрана `mandate.yaml`) | `is_mailbox_file` 3-й параметр, `MO-GUARD-MANDATE` | да: `[7m]` (4 инструмента × 5 форм пути × 2 режима × scope/empty/none, симлинк, контроли), `MAND-GUARD-MANDATE`/`MAND-NAME` | ok | OK |
| REQ-MAND-18 (генерация из той же команды) | `lib/test-cmd.sh`, `suites-gen.sh`, `init.md` 2в, `reconcile.md` (е) | да: `test-suites-gen (1)–(7)`, близнец со `stop-gate.sh`, `SG-*` | дрейф для исполняемых не-bash раннеров (WARN-2) | WARN |
| REQ-MAND-19 (поля, минуты вверх) | `suites-gen.sh` `SG-CEIL`, `SG-BASH` | да: `(1)` 180→3, 61→2, 60→1, 1→1, 181→4, мусор→3 | см. WARN-2 | WARN |
| REQ-MAND-20 (идемпотентность, NOCMD, tracked) | `suites-gen.sh` `SG-OVERWRITE`/`SG-NOCMD` | да: `(3)(4)(8)` | ok | OK |
| REQ-MAND-21 (dogfood) | `tests/suites.yaml` | да: `(8)(9)`; живой `run_suites` — **не выполнен** (T52, MANUAL_TEST сл.3) | ok по формату (`dev.py:292–308`) | WARN (WARN-8) |
| REQ-MAND-22 (`devops`) | `agents/devops.md` | grep `[10]` | ok | OK |
| REQ-MAND-23 (мост Closeout) | `archive.md` 2а, протокол «Контракт закрытия», `mandate-info.sh closeout-mode/closeout-check` | да: `[M] closeout-*` + `MAND-BRIDGE`/`MAND-CHECK-*`; grep `[12]`; проза — ручной сл.4 (не заполнен) | см. WARN-1 | WARN |
| REQ-MAND-23a (+К-5) (`patch|worktree` → остановка) | `closeout-mode` `undefined:<delivery>`, `archive.md` | да: `cm patch/worktree/unset`; grep `undefined` | ok | OK |
| REQ-MAND-23b (+К-6) (`docs_in_repo: none`) | `archive.md` 2а, протокол | **нет** grep-инварианта | ok по тексту | WARN (WARN-4) |
| REQ-MAND-24 (сниппет) | `claude-md-snippet.md` | grep `[11]` (одна строка, нет `/sdx:pr`) | ok (WARN-1 — содержательно) | OK |
| REQ-MAND-25 (`reconcile`: устаревший блок) | `snippet-check.sh`, `reconcile.md` (ж) | да: `test-snippet-check` + `SC-CMP`; категория в `reconcile.md` — **нет** grep (обещан DESIGN-трассировкой) | ok | WARN (WARN-4) |
| REQ-MAND-26 (`/sdx:status`) | `mandate-info.sh status`, `sdx-stage.sh active-set`, `status.md` 5а | да: `[M] status`, `[M39][M40]`; проза — ревью | **дрейф** текста «МО: нет» | WARN (WARN-3) |
| REQ-MAND-27 («два признака», §6→§7) | протокол, `docs/designs/mo-interop.md`, README×2, `CLAUDE.md` §6, ADR-021 | grep `[9]` (без `CLAUDE.md`) | остаток §6 в `FEAT-016` (WARN-6); `CLAUDE.md` §3 (WARN-7) | WARN |
| REQ-MAND-29 (дельты постоянных документов) | `docs/specs|designs/mo-interop.md`, протокол, `FEAT-016` | grep `[9]`, `test-mo-inventory.sh` | дрейф дельты `docs/specs` (WARN-5) | WARN |
| REQ-MAND-30 (версия 2.4.0) | `plugin.json`; `marketplace.json` версии не содержит | grep `[17]` | ok; заметки — на Closeout | OK |
| REQ-MAND-31 (регресс, красные стороны) | — | все сьюты; правки прежних сьютов — только обвязка (PLAN Ф-6, A, З-3) | ok | OK |
| REQ-MAND-32 (время) | комментарий `verify-cmd.sh` (19 сьютов, ~80–125 с) | замер T46 123,9 с < 180 с | ok (INFO-7) | OK |
| REQ-MAND-33 (зависимости) | `sdx-stage.sh`/lib без python; `mandate-info.sh` — только проба наличия PyYAML для `status` | L9 grep; `[P]` | ok (PLAN З-2 названо) | OK |
| Критерии 1–2, 4–13, 15, 17, 19–20 | см. строки REQ выше | А/Ф/Р в diff | ok | OK |
| Критерий 3 (канал SessionStart) | — | ручной сл.1 не заполнен | — | WARN (WARN-8) |
| Критерий 14 (Л: `run_suites` вживую) | — | не выполнено (PLAN З-6) | — | WARN (WARN-8) |
| Критерий 16 (проза моста) | — | ручной сл.4 не заполнен | WARN-1 | WARN |
| Критерий 18 (`/sdx:status`) | — | — | WARN-3 | WARN |
| Критерий 21 (не `auto`) | — | PLAN T51: `gate_mode = interactive` (со слов PLAN; `session_state.json` ревьюер не сверял) | ok | OK |

## Находки

### [FAIL] [Корректность/Когерентность] «Более строгий из двух `on_write`» не действует при python3 без PyYAML — протокол и ADR обещают fail-closed, код делает fail-open
- Где: `sdx/hooks/mo-hook.sh:40` (`MAND-MODE2`) и `:113–121` (python3 проверяется, PyYAML — нет; при `rc 0` хука вывод пропускается); `sdx/mo/devagent_hook.py:37–58` (`cannot_check` хука берёт режим `raw_mode()` **только** из `endpoint.yaml`); `sdx/protocol.md:294` (новая фраза «в режиме мандата — более строгий из `endpoint.on_write` и `mandate.on_write`») в паре с `sdx/protocol.md:301` («при … невозможности проверить цель (нет `python3`/PyYAML/`jq` …) — … в режиме `deny` fail-closed»); `docs/DECISIONS.md` поправка ADR-021 (3); `mandate-info.sh status` печатает «(обёртка берёт deny)»; REQ-MAND-16, критерий 11.
- Суть: когда python3 есть, а PyYAML нет (самый частый вырожденный случай), обёртка запускает хук sim-kit. Хук не может импортировать `mesh_endpoint`, вызывает свой `cannot_check`, а тот читает режим только из `endpoint.yaml`. При `endpoint.on_write: notice` и `mandate.on_write: deny` хук завершается с `exit 0` и печатает «проверка пропущена (режим notice)». Обёртка пропускает этот вывод — запись не блокируется. Протокол (стр. 294 + 301), поправка к ADR-021 и строка `/sdx:status` для этого случая утверждают «deny / fail-closed». `[2m]` проверяет только сценарий «нет python3» (`bin_set none`), поэтому тест расхождения не видит. Названные границы протокола (fail-open хука при *битом* мандате) этот случай не покрывают.
- Ожидалось: если `mandate.on_write: deny`, «не могу проверить» закрывается fail-closed для **всех** причин из стр. 301, либо исключение «python3 без PyYAML» явно названо как граница.
- Фактически: fail-open без упоминания в документах.
- Ожидаемое исправление (одно на выбор пользователя): (а) в `mo-hook.sh`, только если `deny` пришёл из `mandate.yaml` (`endpoint` = notice), проверять наличие PyYAML (`PYTHONDONTWRITEBYTECODE=1 python3 -c 'import yaml'`) до запуска хука и при отсутствии вызывать `cannot_check`. Плюс ячейка `[2m]` «python3 есть, PyYAML нет» и мутант. Стоимость — один процесс только в этой комбинации (ADR-021 отверг предпроверку на *каждый* вызов). (б) Назвать границу в протоколе («Политики отказа» и «Мандат МО — границы подраздела»), в поправке к ADR-021, в строке `mandate-info.sh status` (например, «обёртка берёт deny; при отсутствии PyYAML хук применяет только endpoint.on_write») и в строке `mo-session` о зависимостях.

### [WARN] [Когерентность] Стандартный Closeout под мандатом с `delivery: artifact.offer` сливает `sdx/<id>` в основную ветку, а протокол, ADR и сниппет говорят, что под мандатом исполнитель в защищённые ветки не сливает
- Где: `commands/archive.md` 2а (`standard` при `delivery: artifact.offer` → «прежний чек-лист шагов 1–8», шаг 6 — мёрж в основную ветку); `sdx/protocol.md` «Три слоя границы» («исполнитель сам не сливает в защищённые ветки и не ставит теги»); `sdx/templates/claude-md-snippet.md` («слияние в защищённые ветки — не твоё действие»); `agents/devops.md` («слияние в `main`/`dev`/`stage` … под мандатом всё равно не твоё действие»); эталон `MO-INTEROP.md` §7 («окончательная — слияние только узлом»).
- Суть: SPEC REQ-MAND-23 прямо оставляет штатный Closeout при `artifact.offer`, так что поставка формально соответствует SPEC. Но в режиме мандата локальный мёрж в `main` на Closeout противоречит формулировкам трёх других носителей и эталону. Если трактовать его как «не публикация», это нигде не сказано.
- Ожидалось / Фактически: один ответ на вопрос «сливает ли исполнитель под мандатом в основную ветку при `artifact.offer`» во всех носителях / ответы расходятся.
- Ожидаемое исправление: решение пользователя (стоп-рубрика `[триада]`/`[контракт]`). Либо при любом режиме мандата использовать мост, либо добавить в протокол, сниппет и `devops.md` оговорку «кроме локального мёржа на Closeout при `artifact.offer`» и задать вопрос владельцу МО.

### [WARN] [Корректность] `tests/suites.yaml` не повторяет stop-gate для исполняемых раннеров на другом языке
- Где: `sdx/hooks/lib/test-cmd.sh:14` (`TC_CMD="bash .claude/sdx/verify-cmd.sh"` всегда); `sdx/hooks/stop-gate.sh:108–112` (если раннер исполняемый, он запускается напрямую по shebang, иначе через `bash`); `commands/init.md` 2c («раннер на другом языке требует бита»).
- Суть: REQ-MAND-18 требует «ту же тест-команду, что исполняет stop-gate», а REQ-MAND-19 — «через `bash`, не зависит от бита». Для раннера на Python/Node с битом исполнения stop-gate запускает его корректно, а узел по `suites.yaml` выполнит `bash <python-файл>` и получит падение. Тест-близнец (7) сверяет только класс команды (`TC_KIND`) на bash-раннере, поэтому расхождения не видит. Это внутреннее напряжение самой SPEC, а не отступление от неё.
- Ожидаемое исправление: решение пользователя. Либо `cmd` по биту (`./.claude/sdx/verify-cmd.sh` при `-x`) с ячейкой близнеца для исполняемого не-bash раннера, либо названная граница в протоколе и в шапке генерируемого файла.

### [WARN] [Когерентность] `commands/status.md` ссылается на вывод, которого скрипт не печатает
- Где: `commands/status.md` шаг 5а («без `.mesh/` — «МО: нет»»); `sdx/hooks/mandate-info.sh:59–84` (всегда печатает `МО: endpoint.yaml=нет; mandate.yaml=нет; режим мандата=выключен; on_write: … (обёртка берёт —); …`).
- Суть: проза команды называет текст исхода, которого нет в интерфейсе скрипта (п.(6) постановки).
- Ожидаемое исправление: заменить «МО: нет» на фактическую строку либо ввести в скрипт короткий исход для случая «`.mesh/` нет» и закрепить его в `[M] status`.

### [WARN] [Полнота] Grep-инварианты прозы обещаны DESIGN, но покрывают не всё
- Где: DESIGN «Трассировка», строка 25 («`test-mo-prose` (категория в `reconcile.md`)»); REQ-MAND-31 («проза закрепляется grep-инвариантами»); `sdx/hooks/test-mo-prose.sh` `[9]–[17]`.
- Суть: нет инвариантов для: категории (ж) «устаревший SDX-блок» и (е) `suites-gen.sh --check` в `commands/reconcile.md`; шага 2в в `commands/init.md`; `(n/a, docs_in_repo: none)` (REQ-MAND-23b) — `chk_bridge` проверяет `bridge`, `(n/a, мандат)`, `closeout-check`, `change/<C>-<exec>`, `undefined`, «не вызывается», но не `docs_in_repo`; абзаца о мандате в `commands/next.md`; шага 5а в `commands/status.md`. Для этих мест покрытие — только ревью.
- Ожидаемое исправление: добавить проверки в `test-mo-prose.sh` с красной стороной на повреждённой копии, по образцу `[12]`/`[13]`.

### [WARN] [Когерентность] Дельта `docs/specs/mo-interop.md` искажает исключения REQ-MAND-1 и дублирует номер вендорённой версии
- Где: `docs/specs/mo-interop.md`, раздел «Дельта FEAT-016», первый пункт (diff, стр. 462).
- Суть: (1) Там сказано «с тремя названными отступами — протокольные `from.kit`/`version-skew` (вендоринг 0.9.1) и безусловная охрана». В SPEC REQ-MAND-1 (с К-4) исключения другие: `tests/suites.yaml`, новое содержание `/sdx:status`/сниппета и охрана `mandate.yaml`. `from.kit`/`version-skew` — «неизбежно, не дефект», а не исключение. Постоянная спецификация переписывает сессионную по-другому. (2) «0.9.1» в документе плагина противоречит PROC-028 п.2: «документы плагина ссылаются на файл [`SIMKIT_VERSION`], не дублируют число». В протоколе и `DECISIONS.md` номера нет — там чисто.
- Ожидаемое исправление: перечислить исключения как в SPEC (с К-4); «вендоринг 0.9.1» заменить ссылкой на `sdx/mo/SIMKIT_VERSION`.

### [WARN] [Полнота] В записи `FEAT-016` остались ссылки на «`MO-INTEROP.md` §6» для мандата
- Где: `docs/backlog/FEAT-016-mo-mandate-and-declarations.md:7` (`source:` — «sim-kit 0.9.x `core/MO-INTEROP.md` §6 «Мандат разработки»») и `:66`.
- Суть: REQ-MAND-27 требует заменить ссылки «MI §6 мандат» на §7. В вендорённой 0.9.1 мандат — §7, а §6 — шаблон сниппета. Строку 7 поставка правила (0.9.0 → 0.9.x), но параграф оставила прежним.
- Ожидаемое исправление: §6 → §7 в обеих строках (на Closeout вместе с C2 — допустимо).

### [WARN] [Когерентность] `CLAUDE.md` §3 описывает сужение активного набора без мандата
- Где: `CLAUDE.md` §3 «Единая шкала + режимы-флаги» («двумя ортогональными механизмами», «два независимых булевых флага … могут только СУЖАТЬ»); поправка к ADR-020 (мандат — третий сужающий источник; `Deployment` при мандате исключён всегда).
- Суть: SPEC требовала от `CLAUDE.md` только «два признака» (§6 — сделано), поэтому это не нарушение REQ. Но `CLAUDE.md` — нормативный носитель, а после поправки к ADR-020 его описание шкалы неполно: «Deployment при мандате» и «третий источник» есть в протоколе, ADR, `next.md`, `devops.md` и README, но не здесь (п.(2) постановки).
- Ожидаемое исправление: одно предложение в §3 о мандате как третьем сужающем источнике (только в режиме мандата) со ссылкой на протокол.

### [WARN] [Полнота] Ручная часть приёмки не выполнена: покрытие критериев 3, 7 (реальный дамп), 14 (Л) и 16 (проза) пока только видимое
- Где: `MANUAL_TEST.md` (случаи 1–5, «Результат (заполняется)» пуст); PLAN «Отклонения З» п.6 (живой `run_suites` не выполнялся: `dev.py` не импортировался); `test-mandate-lib.sh` L3.
- Суть: (1) «Реальный дамп» в L3 написан вручную, а не порождён `dev.py mandate_yaml()`. В нём `history: squash`, а `dev.py:25` допускает только `executor|mo|both` — для парсера это безразлично, но фикстура не является дампом узла. (2) Формат `tests/suites.yaml` сверен с `run_suites` по коду (`dev.py:292–308`: `suites` → `unit` → словарь с `cmd`/`budget_min`; `selector` не используется — набор запускается целиком) — видимо корректно, но не прогоном. (3) Проза моста Closeout не проходилась.
- Ожидаемое исправление: прогнать MANUAL_TEST до гейта или квитировать каждый случай как «не проверено» с переносом в бэклог (C1).

### [INFO] [Когерентность] README×2: «без `endpoint.yaml` — no-op», хотя при одном `mandate.yaml` `mo-session` печатает строку
- Где: `README.md`/`README.en.md` (абзац «Хуки safe-by-default»); REQ-MAND-3.
- Суть: при `mandate.yaml` без `endpoint.yaml` вывод не пуст (одна строка предупреждения). Мелкая неточность; можно дописать «(кроме одной строки о мандате без endpoint)».

### [INFO] [Корректность] Правило `--planned` не учитывает `docs_in_repo: none` и передаёт каталоги
- Где: `commands/verify.md` шаг 6а; `mandate-scope.sh` (проверка `glob_any(<каталог>/, union)`).
- Суть: при `docs_in_repo: none` переносы в `docs/specs|designs` на Closeout — `(n/a)` (К-6), но `--planned docs/specs/` всё равно передаётся. Кроме того, каталог `docs/specs/` не совпадёт с шаблоном вида `docs/specs/*.md`. В обоих случаях возможен ложный `FAIL` при узком `docs_paths`. С дефолтом `docs/**` (`mandate_yaml()` подставляет его всегда) не проявляется.

### [INFO] [Корректность] `mandate_expired` распознаёт только `YYYY-MM-DD`
- Где: `sdx/hooks/lib/mandate.sh` `mandate_expired`.
- Суть: при `valid_until` с временем (`2026-10-01T00:00:00`) предупреждения не будет, хотя узел (`dev.py:369`, сравнение строк) отклонит пакет. `lint` формат не фиксирует; вероятность низкая.

### [INFO] [Когерентность] `start-stage` без мандата не всегда возвращает входной этап
- Где: `sdx-stage.sh` `cmd_start_stage`; тест `[M38]` («no mandate, no_code: start-stage Execution -> Verification»); DESIGN «Обратная совместимость» («без мандата возвращает входной этап … иначе — прежний отказ делает `init`»); `commands/start.md` («без мандата это тот же `stage`»).
- Суть: при `no_code=true` и этапе, исключённом `no_code`, `start-stage` молча продвигает этап вперёд. Раньше `init` отказывал с кодом 2. Через `start.md` этот путь недостижим (`no_code`-типы стартуют с `Discovery`), поэтому это внутреннее расхождение DESIGN и прозы, а не наблюдаемое изменение поведения.

### [INFO] [Когерентность] `active-set` читает мандат и у `no_gates`-сессии
- Где: `sdx-stage.sh` `cmd_active_set`; протокол «Приоритет-0 `no_gates` мандат не читает вовсе».
- Суть: подкоманда только читает и служит `/sdx:status`; при нечитаемом мандате она выдаст `MANDATE-ERROR` и для `no_gates`-сессии. Формулировку протокола стоит сузить до `init`/`next`.

### [INFO] [Корректность] `closeout-check` не учитывает `.mesh/` при проверке чистоты дерева
- Где: `mandate-info.sh:117` (`git status --porcelain -- . ':!.mesh'`); PLAN «Отклонения Ф» п.9.
- Суть: решение разумное (`.mesh/` — фенотип узла вне git). В протоколе и `archive.md` сказано просто «дерево чистое», без исключения `.mesh/`.

### [INFO] [Корректность] Суффикс `mnote` утверждает «показан ниже» и тогда, когда мандат не разобран
- Где: `mo-session.sh:58`.
- Суть: если `mandate.yaml` битый или lib недоступна, следующая строка — «не разобран»/«не показан». Смысл восстанавливается по следующей строке.

### [INFO] [Корректность] Время прогона близко к пределу
- Где: `.claude/sdx/verify-cmd.sh` (комментарий); PLAN З-1 (123,9 с при load ≈ 10; цель 120 с не достигнута).
- Суть: REQ-MAND-32 выполнен (< 180 с), но запас ≈ 56 с под нагрузкой; при превышении stop-gate будет краснеть на каждом ходе.

### [INFO] [Корректность] Переносимость на bash 3.2 подтверждена эмуляцией, а не настоящим bash 3.2
- Где: PLAN «Отклонения Ф» п.3 (`BASH_COMPAT=32/41`, `busybox awk`, FORBID-grep).
- Суть: видимое, не доказанное покрытие BUG-010.

### [INFO] [Когерентность] DESIGN «Компоненты» устарел в двух местах
- Где: DESIGN `mo-session.sh` (суффикс «не прочитан» — до К-2) и `mo-hook.sh` («охрана безусловна по наличию файла `mandate.yaml`»; К-4 и код: безусловно при наличии `endpoint.yaml`, даже если `mandate.yaml` нет — `[7m]` вариант `none`).
- Суть: код следует SPEC-поправкам; при переносе DESIGN в `docs/history/` на Closeout стоит пометить.

### [INFO] [Полнота] Оговорка REQ-MAND-9 «`Verification` без `verify` в `stages` — локальный пол, не сдача узлу; `Closeout` — сдача исполнителя» не перенесена в протокол и постоянную спецификацию
- Где: REQ-MAND-9; в репозитории она есть только в `docs/backlog/FEAT-016-…md`.
- Суть: исполняемого поведения за ней нет, но смысл этапа под мандатом в нормативных носителях не зафиксирован.

### [INFO] [Когерентность] Мелкие расхождения прозы с исходами скриптов
- Где: `commands/init.md` шаг 6 (перечень `CREATED|OK|DIFFERS|NOCMD` без `ABSENT`, хотя `reconcile` сначала вызывает `--check`, а при отказе от сверки файл не создаётся); `commands/reconcile.md` (е)/(ж) (не описан код 2 `suites-gen.sh`/`snippet-check.sh`: нечитаемый файл, `tests` не каталог, нет шаблона).
- Суть: при rc 2 оркестратору нечем руководствоваться; стоит добавить строку «код 2 — показать stderr, находка без применения».
