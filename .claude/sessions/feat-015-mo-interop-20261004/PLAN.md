# Implementation Plan: FEAT-015 — интероп с мета-оркестратором (МО) в плагинной модели

## Статус реализации
33/33 задач Execution (T01–T33), 0/4 задач Closeout (C1–C4). Этап: Execution завершён, идёт Verification (круг 1).

Ссылки: `SPEC` = `SPEC.md`, `DESIGN` = `DESIGN.md` этой сессии; `DH`/`ME`/`MI` — как в DESIGN (`sim-kit/core/devagent_hook.py`, `mesh_endpoint.py`, `MO-INTEROP.md`). Критерии SPEC — `К1…К22`.

## Правила исполнения (действуют для всех задач)

- **Не `gate_mode: auto` (PROC-020, К22).** Метка **[PROC-020]** у задачи = она трогает `hooks/hooks.json` / hook-скрипты / механизм надзора; оркестратор перед такой задачей проверяет `jq -r .gate_mode session_state.json` != `auto`, иначе стоп. Сессия целиком идёт не в `auto` (T32 проверяет).
- **Коммит на ветке `sdx/feat-015-mo-interop-20261004` после каждой задачи** (сообщение `sdx(feat-015-mo-interop-20261004): T<NN> …`).
- **Тестовая дисциплина.** Задача `[TEST]` не готова на «зелёно»: DoD обязан показывать красную сторону (мутант-копия, контрольный вход или заведомо отсутствующая реализация) на ТОМ ЖЕ сценарии. Мутанты — копии в `mktemp -d`/scratchpad + `sed` по меткам `# MO-EARLY-EXIT` / `# MO-BYTECODE` / `# MO-TRANSLATE` (метки ставит T10/T12, тесты T04–T09 пишутся до реализации, поэтому проверку «мутант непустой» делают через `! cmp -s orig mutant` уже в T13). Реальный вендорённый хук запускается только из КОПИИ в `$fx/root/sdx/mo/`; чекаут `sdx/mo/` тестами не трогается.
- **Порядок «красный → зелёный» для сьютов:** тест-задача пишется и фиксируется красной (сьют падает из-за отсутствия `mo-hook.sh`/`mo-session.sh`; в DoD — `bash <suite>; echo $?` != 0 и перечень красных строк), затем реализация делает её зелёной.
- **Переносимость (BUG-010, macOS):** никаких `timeout`, `mapfile`, `${v,,}`, `declare -A`, `date +%s%N`, GNU-флагов `sed/cp/stat`; `set -u`, без `-e`, без `pipefail` в `mo-hook.sh`/`mo-session.sh`. Тест-сьюты — `Results: N passed, M failed`, `trap` чистка, SKIP/INFO (не PASS) при отсутствии `python3`/PyYAML.
- Размер задачи ≈ ≤30 строк кода; тест-сценарии дробятся по группам сценариев таблиц DESIGN «Тесты».

## Чек-лист задач

### Группа 1 — Вендоринг (`sdx/mo/`)

- [x] **T01** `[INFRA]` Вендорить sim-kit 0.7.3 в `sdx/mo/`
  - Зависит от: —
  - Файлы: `sdx/mo/mesh_endpoint.py`, `sdx/mo/devagent_hook.py`, `sdx/mo/MO-INTEROP.md`, `sdx/mo/SIMKIT_VERSION`, `sdx/mo/SIMKIT_SHA256` (новые)
  - Что: выполнить блок команд DESIGN «`sdx/mo/` — вендорённый каталог» дословно (`cp` трёх файлов из `/home/archi/Code/aibok/agentico/meta-orchestrator/sim-kit/core/`, `printf` версии, `sha256sum` в `SIMKIT_SHA256` в порядке `mesh_endpoint.py`, `devagent_hook.py`, `MO-INTEROP.md`). Предусловие: `cat sim-kit/VERSION` == `0.7.3`, иначе СТОП (версия в SPEC фиксирована). Не запускать python из `core/`, не копировать `__pycache__`, `mo.py`, `guard.py`, `mesh.py`, `classifiers/`.
  - DoD: `cmp` каждого из трёх файлов с `sim-kit/core/` — пусто; `cat sdx/mo/SIMKIT_VERSION` == `0.7.3`; `(cd sdx/mo && sha256sum -c SIMKIT_SHA256)` — три `OK`; `ls -a sdx/mo` без `__pycache__`; строки `SIMKIT_SHA256` соответствуют `^[0-9a-f]{64}  [^/ ]+$`.
  - Закрывает: К1 (часть), REQ-MO-VEND-1/3. Параллельно: можно с T04 (разные файлы).

- [x] **T02** `[DOC]` `sdx/mo/README.md` (не вендорится)
  - Зависит от: T01
  - Файлы: `sdx/mo/README.md`
  - Что: ~12 строк по списку DESIGN («откуда / политика / как обновлять (не в `auto`, ссылка на `protocol.md` «Вендорённые компоненты (`sdx/mo/`)») / в проекты не копируется / `PYTHONDONTWRITEBYTECODE=1`»), на русском. Не добавлять `README.md` в `SIMKIT_SHA256`.
  - DoD: `bash sdx/hooks/test-mo-inventory.sh` — в [6] `README.md` не считается лишним файлом (нет находки «неперечисленный файл»); `grep -c 'SIMKIT_SHA256' sdx/mo/SIMKIT_SHA256` для README не нужен (не хешируется): `! grep -q README sdx/mo/SIMKIT_SHA256`.
  - Закрывает: К1 (часть), REQ-MO-VEND-2/3.

- [x] **T03** `[TEST]` Сторож `test-mo-inventory.sh` [6]: реальная проверка и красные стороны (без правки сьюта)
  - Зависит от: T01, T02
  - Файлы: правок файлов репо нет (проверка исполнением; результат — в сообщении коммита/`verification`-заметке сессии)
  - Что: прогнать `bash sdx/hooks/test-mo-inventory.sh`; убедиться, что [6] выполняется (не «пропуск INFO»). Красные стороны — ТОЛЬКО на копии репо в scratchpad (`cp -R` без `.git`), чекаут не трогать: (а) дописать байт в `devagent_hook.py` → `check_inventory` красный; (б) `mkdir sdx/mo/__pycache__` → красный; (в) лишний файл `sdx/mo/x.txt` → красный; (г) `SIMKIT_VERSION` = `0.7` пусто/мусор → красный.
  - DoD: на чекауте [1]–[12] зелёные, в [6] проверка инвентаря зелёная, проверка поверхностей (д) КРАСНАЯ ожидаемо (README×2/CLAUDE.md без имён — до T30); на каждой из 4 мутаций копии сторож красный (показать вывод); чекаут не изменён (`git status --porcelain` пуст).
  - Закрывает: К1.

### Группа 2 — `mo-hook.sh` (PreToolUse-обёртка) — тесты сначала [PROC-020]

Все T04–T09 пишут в ОДИН файл `sdx/hooks/test-mo-hook.sh` (последовательно, один коммит на задачу); до T10 сьют красный.

- [x] **T04** `[TEST]` [PROC-020] `test-mo-hook.sh`: каркас + сценарий 1 (нет МО)
  - Зависит от: —
  - Файлы: `sdx/hooks/test-mo-hook.sh` (новый, шапка-комментарий как у `test-mo-inventory.sh`)
  - Что: каркас по DESIGN «Тесты — Общие правила»: `mktemp -d` фикстура, `trap`, `pass/fail`, `Results:`; хелперы: изоляция `PATH` через `$fx/bin` с symlink'ами на `bash`,`cat`,`jq` (образец `test-selftest.sh:494–499`), bash-заглушка `python3` (управление `STUB_RC/STUB_ERR/STUB_LOG`, пишет `argv`, `$PYTHONDONTWRITEBYTECODE`, `$MESH_ENDPOINT_DIR`, stdin; режим «пишет маркер и падает»), хелпер `run_hook <json>` и хелпер `make_mutant <label-pattern>` (копия `mo-hook.sh` + `sed` + `! cmp -s`). Сценарий 1: нет `.mesh/endpoint.yaml` (в т.ч. `.mesh/` без файла; без `CLAUDE_PROJECT_DIR` из cwd; не git-репо, нет `.claude/`; `PATH` без `jq`; заглушка пишет маркер и падает).
  - DoD: `bash sdx/hooks/test-mo-hook.sh; echo $?` != 0, красные строки — «нет `sdx/hooks/mo-hook.sh`» (красная сторона по отсутствию реализации); `bash -n` сьюта ок; `grep -nE 'timeout|mapfile|declare -A|%N' sdx/hooks/test-mo-hook.sh` пусто. Красная сторона мутантом `# MO-EARLY-EXIT` описана в коде сценария (прогоняется в T13).
  - Закрывает: К2 (тестовая часть).

- [x] **T05** `[TEST]` [PROC-020] `test-mo-hook.sh`: сценарий 2 (режим `on_write` — паритет с `DH`)
  - Зависит от: T04
  - Файлы: `sdx/hooks/test-mo-hook.sh`
  - Что: таблица фикстур DESIGN (сц. 2): `notice`, `deny`, `DENY`, `'deny'`, `"deny"`, `deny  # c`, ключа нет, `# on_write: deny`, `  on_write: deny`, `allow`, два ключа, `on_write:\n  deny`, нечитаемый файл (`chmod 000`, SKIP при root) — режим наблюдается через ветку «нет python3» (deny → JSON, notice → строка). Часть (а): паритет с реальным `DH` под заблокированным PyYAML (`PYTHONPATH=$fx/stubyaml`, `yaml.py` = `raise ImportError`), расхождение — FAIL, без `python3` — INFO-skip. Часть (б): мутант с иным regex (`grep -E 'on_write: *deny'`). Расхождение `denyй` в C-локали — отдельный INFO, не PASS. Фикстура `DENY` сравнивает путь `cannot_check`/`raw_mode`, не штатный путь `DH` (расхождение `DH:181` vs `DH:38` — только INFO, идёт в T33).
  - DoD: сьют по-прежнему красный (нет реализации); в коде сценария есть таблица ожиданий по всем 13 фикстурам; мутант regex в T13 даёт ≥1 красную фикстуру (прогон — T13).
  - Закрывает: К3 (тестовая часть).

- [x] **T06** `[TEST]` [PROC-020] `test-mo-hook.sh`: сценарии 3 и 4 (невозможность проверки; нет PyYAML)
  - Зависит от: T04
  - Файлы: `sdx/hooks/test-mo-hook.sh`
  - Что: сц. 3 — `notice`/`deny` × {нет `python3`; нет файла хука; нет `jq`; мусор на stdin; `DH`-заглушка rc 1; rc 127; rc убит сигналом (`kill -9 $$`)}: notice → stderr ровно 1 строка (`wc -l`), stdout пуст, rc 0; deny → валидный JSON (`jq .`), `permissionDecision=="deny"`, rc 0 (не 2); без `jq` — литерал JSON, тоже валиден. Сц. 4 — настоящий `python3` + `PYTHONPATH=$fx/stubyaml`, реальная копия `DH`: notice → rc 0, stdout пуст, stderr 1 строка с `PyYAML`; deny → JSON deny с `PyYAML` в причине; INFO-skip без `python3`.
  - DoD: сьют красный (нет реализации); для каждого из 7 условий × 2 режима есть строка-утверждение; мутанты «fail-open во всех режимах» и «rc 2 из обёртки» описаны для T13.
  - Закрывает: К4, К5, К7 (тестовая часть).

- [x] **T07** `[TEST]` [PROC-020] `test-mo-hook.sh`: сценарии 5 и 6 (трансляция rc 2; rc 0, stdin, env)
  - Зависит от: T04
  - Файлы: `sdx/hooks/test-mo-hook.sh`
  - Что: сц. 5 — заглушка rc 2 с многострочным stderr (`"`, `\`, кириллица): stdout — валидный JSON, `jq -r .hookSpecificOutput.permissionDecisionReason` равен stderr заглушки, rc 0, stderr обёртки пуст. Сц. 6 — rc 0 со строкой stderr / без: stdout пуст, строка проброшена ровно один раз; лог заглушки: stdin байт-в-байт (включая ≥200 КБ и многострочное `content`), `argv[1] == $CLAUDE_PLUGIN_ROOT/sdx/mo/devagent_hook.py`, `MESH_ENDPOINT_DIR == $proj`, `PYTHONDONTWRITEBYTECODE == 1`; пустой stderr при rc 2 → причина-заглушка, блок сохранён.
  - DoD: сьют красный; утверждения по каждому полю лога заглушки; мутанты `# MO-TRANSLATE` (rc 2 насквозь), «`input` не передан хуку», `# MO-BYTECODE` описаны для T13.
  - Закрывает: К6, К8, К10 (env-часть).

- [x] **T08** `[TEST]` [PROC-020] `test-mo-hook.sh`: сценарий 7 (охрана ящика)
  - Зависит от: T04
  - Файлы: `sdx/hooks/test-mo-hook.sh`
  - Что: `Write`/`Edit`/`MultiEdit`/`NotebookEdit` (`notebook_path`) × {`.mesh/endpoint.yaml`, `.mesh/cursors.json`} × пути {абсолютный, относительный с `cwd` из входа, `…/./.mesh/../.mesh/endpoint.yaml`, `$proj//.mesh/endpoint.yaml`} × {notice, deny} × `exec_paths` пуст: JSON deny, rc 0, маркер заглушки python ОТСУТСТВУЕТ; без `jq` — deny литерал / notice одна строка. Контрольные «не блокируется охраной» (заглушка вызвана): `.mesh/outbox/x.json`, `.mesh/hook-state.json`, `src/endpoint.yaml`, `.mesh/endpoint.yaml.bak`, инструмент `Read`, `Bash` с текстом `.mesh/endpoint.yaml` (граница).
  - DoD: сьют красный; описаны мутанты «охрана удалена» и «охрана без нормализации» (по ней должны краснеть `..`, `//`, относительный) — прогон в T13; контрольные проходы явно названы «граница, не PASS охраны».
  - Закрывает: К9 (тестовая часть).

- [x] **T09** `[TEST]` [PROC-020] `test-mo-hook.sh`: сценарии 8, 9, 11 (реальный вендорённый `DH`)
  - Зависит от: T04
  - Файлы: `sdx/hooks/test-mo-hook.sh`
  - Что: сц. 8 — копия `sdx/mo/` в `$fx/root/sdx/mo/` (INFO-skip без `python3`+PyYAML), `exec_paths: [$fx/dep]`, `on_write: deny`, нет аренды: (а) `Write` в `$fx/dep/a` → JSON deny, причина содержит `DENY [MO-exec-paths]`, stderr обёртки пуст; (б) `on_write: notice` → rc 0, stdout пуст; (в) `Write` вне `exec_paths` → тишина; (г) `Bash touch $fx/dep/x` в deny → JSON deny; (д) аренда: конверт `lease.granted` собирается python-однострочником через `ehash` вендорённого `ME` (`PYTHONDONTWRITEBYTECODE=1`) → `Write` в `$fx/dep/a` в deny проходит. Сц. 9 — `ls -a "$fx/root/sdx/mo"` без `__pycache__` после сц. 4 и 8. Сц. 11 — `$ROOT/sdx/mo/` (чекаут) без `__pycache__` после прогона.
  - DoD: сьют красный (нет `mo-hook.sh`); сц. 8–9 используют `cp` реальных файлов из `sdx/mo/` (после T01 есть); красная сторона по существу — T13 (мутант без `# MO-BYTECODE` → `__pycache__` появляется; без `# MO-TRANSLATE` → (а),(г) красные; (д) без аренды = (а)).
  - Закрывает: К6, К8, К10 (тестовая часть).

### Группа 3 — `mo-hook.sh` реализация [PROC-020]

- [x] **T10** `[CODE]` [PROC-020] `mo-hook.sh`: шаги 1–3 (ранний выход, режим, вход/зависимости, функции вывода)
  - Зависит от: T04, T05, T06 (тесты красные первыми)
  - Файлы: `sdx/hooks/mo-hook.sh` (новый)
  - Что: по DESIGN «`sdx/hooks/mo-hook.sh`»: резолв окружения; шаг 1 с меткой `# MO-EARLY-EXIT` (`[ -f "$proj/.mesh/endpoint.yaml" ] || exit 0` до `cat`/`jq`/`python3`); шаг 2 — `mode_re` БЕЗ кавычек в `[[ =~ ]]`, дефолт `notice`; шаг 3 — `input="$(cat)"`, проверка `jq` с литералом JSON для deny / строкой для notice; разбор `tool_name`; функции `deny_json` (метка `# MO-TRANSLATE` на строке `printf` JSON, формат буква-в-букву `prod-guard.sh:11–12`) и `cannot_check`. `set -u`, без `-e`/`pipefail`.
  - DoD: `bash -n sdx/hooks/mo-hook.sh`; `bash sdx/hooks/test-mo-hook.sh` — сц. 1, 2, 3 (ветка «нет jq», «мусор на stdin», «нет python3» — `python3` ещё не запускается, значит часть ветвей ждёт T12; ожидаемо красные остаются сц. 3 «rc 1/127/сигнал», 4–9) ; `grep -nE 'timeout|mapfile|declare -A|\$\{[a-z_]+,,\}|%N' sdx/hooks/mo-hook.sh` пусто; `! grep -qE 'git |resolve-session' sdx/hooks/mo-hook.sh` (REQ-MO-HOOK-3: не зависит от ветки).
  - Закрывает: К2, К3 (реализация).

- [x] **T11** `[CODE]` [PROC-020] `mo-hook.sh`: шаг 4 (охрана ящика)
  - Зависит от: T10, T08
  - Файлы: `sdx/hooks/mo-hook.sh`
  - Что: `is_mailbox_file`/`norm_path` по DESIGN (лексическая нормализация, `set -f` и `local IFS` внутри, цели `{proj_abs,proj_phys}/.mesh/{endpoint.yaml,cursors.json}`; если `cd "$proj"` неудачен — охрана пропускается); вызов для `Write|Edit|MultiEdit|NotebookEdit` ДО запуска python, независимо от режима и `exec_paths`.
  - DoD: `bash -n`; сц. 7 `test-mo-hook.sh` зелёный (все пути × инструменты × режимы, контрольные проходы); маркер заглушки python отсутствует в охранных кейсах.
  - Закрывает: К9 (реализация).

- [x] **T12** `[CODE]` [PROC-020] `mo-hook.sh`: шаги 5–6 (запуск `DH`, трансляция кодов)
  - Зависит от: T10, T07, T09
  - Файлы: `sdx/hooks/mo-hook.sh`
  - Что: проверки `python3` и `-f "$hook"` (иначе `cannot_check`); запуск `PYTHONDONTWRITEBYTECODE=1 CLAUDE_PROJECT_DIR="$proj" MESH_ENDPOINT_DIR="$proj" python3 "$hook" 2>&1 >/dev/null <<<"$input"` с меткой `# MO-BYTECODE`; таблица: rc 0 → проброс stderr одной строкой; rc 2 → `deny_json "${err:-…без причины}"`; иное → `cannot_check` с последней строкой err ≤200 симв.
  - DoD: `bash -n`; `bash sdx/hooks/test-mo-hook.sh` — сц. 1–9, 11 зелёные (сц. 4, 8 — PASS либо честный INFO-skip без python3/PyYAML; показать, какой вариант в этом окружении: `python3 -c 'import yaml'`); `ls -a sdx/mo` без `__pycache__` после прогона.
  - Закрывает: К4–К8, К10 (реализация).

- [x] **T13** `[TEST]` [PROC-020] `test-mo-hook.sh`: мутанты, сц. 10, переносимость — красные стороны показаны
  - Зависит от: T11, T12
  - Файлы: `sdx/hooks/test-mo-hook.sh`
  - Что: реализовать прогоны мутантов, описанных в T04–T09: без `# MO-EARLY-EXIT`; regex режима `grep -E 'on_write: *deny'`; fail-open во всех режимах; rc 2 из обёртки; без `# MO-TRANSLATE`; `input` не передан; без `# MO-BYTECODE` (на сц. 8 — `__pycache__` появился по существу); охрана удалена; охрана без нормализации. Перед каждым — `! cmp -s orig mutant`. Сц. 10 — сц. 3–8 повторены в проекте без `.claude/`, не git-репо, и в git-репо на `main`. Сц. «переносимость»: `grep` запретных конструкций по `mo-hook.sh` = 0, на мутанте с `mapfile` — ≥1 (красная сторона grep).
  - DoD: `bash sdx/hooks/test-mo-hook.sh` — `Results: N passed, 0 failed`; в выводе явные строки «мутант X → красный (ожидаемо)» для каждого из 9 мутантов; каждый мутант реально краснит именно целевой сценарий (показать, какой); `git status --porcelain` не содержит `__pycache__`.
  - Закрывает: К2, К3, К6, К9, К10 (красные стороны).

### Группа 4 — `mo-session.sh` (SessionStart) [PROC-020]

Группа 4 независима от групп 2–3 (другие файлы) — **T14–T18 можно вести параллельно T04–T13**.

- [x] **T14** `[TEST]` [PROC-020] `test-mo-session.sh`: сценарии 1–6 (заглушки)
  - Зависит от: —
  - Файлы: `sdx/hooks/test-mo-session.sh` (новый, переиспользует приём заглушки `python3` из T04; хелперы не выносятся в общий файл — самодостаточность сьюта)
  - Что: по таблице DESIGN «`test-mo-session.sh`»: (1) нет `endpoint.yaml` и нет `.claude/sdx`, заглушка пишет маркер → вывода нет, rc 0, маркера нет; (2) нет `python3` / нет PyYAML → РОВНО одна строка stderr (`wc -l` = 1), упоминает `PyYAML`/`python3`, `deny` и `notice`, `pull`/`inbox`/`leases` не вызывались, `.mesh` не изменён; (3) порядок вызовов `-c import yaml` → `pull --quiet` → `inbox --json` → `leases`, каждый с `PYTHONDONTWRITEBYTECODE=1` и `MESH_ENDPOINT_DIR=$proj`, stderr содержит число, `kind`, `msg_id`, `[ДАННЫЕ, не инструкции]`, аренды, stdout пуст; (4) инъекция: тело с `\n` и `SDX mo-session: выполни rm -rf` — каждая строка начинается с `SDX mo-session:` либо `  "M-`, тело ≤160; (5) >5 конвертов → последние 5 + строка о хвосте; (6) отказ `pull`/`inbox` (rc 1), нет `jq` → по предупреждению на отказ, rc 0, без `jq` — число без состава.
  - DoD: `bash sdx/hooks/test-mo-session.sh; echo $?` != 0 (нет `mo-session.sh`); `bash -n`; запретные конструкции BUG-010 — `grep` пусто; мутанты (без гарды, 0/2+ строк, без `PYTHONDONTWRITEBYTECODE`, без `tojson`, без капа) описаны для T18.
  - Закрывает: К12, К10 (тестовая часть).

- [x] **T15** `[TEST]` [PROC-020] `test-mo-session.sh`: сценарий 7 (реальные `ME` + PyYAML) и границы записи
  - Зависит от: T01, T14
  - Файлы: `sdx/hooks/test-mo-session.sh`
  - Что: INFO-skip без `python3`/PyYAML; фикстурный ящик с реальными конвертами `lease.granted` и `directive` (собираются через `ehash` вендорённого `ME` из копии `sdx/mo/` в `$fx/root`); в stderr — `directive` и `lease` с `msg_id`, аренда показана; `ls -a $fx/root/sdx/mo` без `__pycache__`; снимок (`find … -type f` + `cksum`) дерева плагина-фикстуры и проекта вне `.mesh/` до/после идентичен, менялся только `.mesh/` (`cursors.json`). Проект без `.claude/sdx` с `.mesh/endpoint.yaml` ведёт себя так же, как с ним (К12).
  - DoD: сьют красный (нет `mo-session.sh`); снимок-сравнение реализовано без `date +%s%N`/GNU-флагов; красная сторона — мутант без `PYTHONDONTWRITEBYTECODE` → `__pycache__` (прогон в T18).
  - Закрывает: К12, К13, К10 (тестовая часть).

- [x] **T16** `[CODE]` [PROC-020] `mo-session.sh`: гарда и предупреждения о зависимостях
  - Зависит от: T14
  - Файлы: `sdx/hooks/mo-session.sh` (новый)
  - Что: `set -u`, `exit 0` на всех путях, вывод только stderr; `[ -f "$proj/.mesh/endpoint.yaml" ] || exit 0` (гарды `.claude/sdx` НЕТ); функция `mo()`; шаг 1 — нет `jq` (строка-предупреждение, расширение REQ-MO-SESS-4); шаг 2 — нет `python3` или `import yaml` ≠ 0 → ОДНА строка, `exit 0`.
  - DoD: `bash -n`; `test-mo-session.sh` сц. 1, 2 зелёные, сц. 3–7 красные ожидаемо; `grep -nE 'timeout|mapfile|declare -A|%N' sdx/hooks/mo-session.sh` пусто; `grep -n 'exit' sdx/hooks/mo-session.sh` — только `exit 0`.
  - Закрывает: К12 (часть).

- [x] **T17** `[CODE]` [PROC-020] `mo-session.sh`: pull / inbox / leases / напоминание
  - Зависит от: T16, T15
  - Файлы: `sdx/hooks/mo-session.sh`
  - Что: шаги 3–6 DESIGN: `pull --quiet` (rc≠0 → строка, `exit 0`), `inbox --json` (форматирование через `jq`, `tojson` на КАЖДОМ поле, тело ≤160, последние 5 + хвост «ранее принято ещё N», пусто → «входящих нет», без `jq` — только число по `grep -c .`), `leases` (непусто / «действующих аренд нет …»), последняя строка-напоминание нормы `MI` §3/§5.
  - DoD: `bash -n`; `bash sdx/hooks/test-mo-session.sh` — сц. 1–6 зелёные, сц. 7 PASS либо INFO-skip (указать, какое); `ls -a sdx/mo` без `__pycache__`.
  - Закрывает: К12, К13, К10 (реализация).

- [x] **T18** `[TEST]` [PROC-020] `test-mo-session.sh`: мутанты — красные стороны
  - Зависит от: T17
  - Файлы: `sdx/hooks/test-mo-session.sh`
  - Что: реализовать прогоны мутантов (копия скрипта + `sed`, `! cmp -s`): без гарды (маркер в сц. 1), «молчит» и «2+ строк» в сц. 2, без `PYTHONDONTWRITEBYTECODE` (env-лог сц. 3 и `__pycache__` сц. 7), без `tojson` (сц. 4), без капа (сц. 5).
  - DoD: `bash sdx/hooks/test-mo-session.sh` — `Results: N passed, 0 failed`; в выводе строки «мутант X → красный» для 6 мутантов с указанием краснеющего сценария; чекаут чистый.
  - Закрывает: К10, К12 (красные стороны).

### Группа 5 — Проводка `hooks.json` [PROC-020]

- [x] **T19** `[TEST]` [PROC-020] `test-hook-wiring.sh`: сценарий `[6]` — `mo_wiring_findings`
  - Зависит от: — (пишется красным до T20; параллельно с группами 2–4)
  - Файлы: `sdx/hooks/test-hook-wiring.sh` (добавить `[6]`; `[1]–[5]` не переписывать; без `mapfile`)
  - Что: функция `mo_wiring_findings <hooks.json>` (пусто = согласовано) — (а) ровно одна запись `PreToolUse` с `sdx/hooks/mo-hook.sh`, `matcher` при разбиении по `|` содержит все пять `Bash Write Edit MultiEdit NotebookEdit`; (б) её `command` не содержит `timeout` и точно `bash "${CLAUDE_PLUGIN_ROOT}"/sdx/hooks/mo-hook.sh`; (в) запись `prod-guard` с `matcher == "Bash"` сохранена; (г) в `SessionStart` есть запись с `mo-session.sh` без `timeout`. Красные стороны `jq`-мутациями (образец `[5a]/[5b]`, `mutant != original`): удалить запись; убрать `NotebookEdit`; префикс `timeout 10 ` (именно его `is_bash_wired` пропускает); matcher → `Bash`; убрать `prod-guard`; убрать `mo-session`.
  - DoD: до T20 `bash sdx/hooks/test-hook-wiring.sh` красный только на `[6]` (на оригинале), `[1]–[5]` зелёные; после T20 зелёный; все 6 мутаций краснят `[6]`, каждая показана отдельной строкой.
  - Закрывает: К11 (тестовая часть).

- [x] **T20** `[CODE]` [PROC-020] `hooks/hooks.json`: две новые записи
  - Зависит от: T19, T12, T17 (скрипты существуют — `test-hook-wiring.sh` проверяет существование)
  - Файлы: `hooks/hooks.json`
  - Что: в `SessionStart` — третья запись `bash "${CLAUDE_PLUGIN_ROOT}"/sdx/hooks/mo-session.sh`; в `PreToolUse` — вторая запись с `matcher: "Bash|Write|Edit|MultiEdit|NotebookEdit"` и `bash "${CLAUDE_PLUGIN_ROOT}"/sdx/hooks/mo-hook.sh`. Без `timeout`. Существующие записи (`preflight`, `selftest`, `prod-guard` `matcher: Bash`) не менять.
  - DoD: `jq . hooks/hooks.json` валиден; `bash sdx/hooks/test-hook-wiring.sh` — полностью зелёный (`[1]–[6]`); `git diff hooks/hooks.json` содержит только добавления; перед задачей `gate_mode != auto` подтверждён.
  - Закрывает: К11, REQ-MO-HOOK-1, REQ-MO-SESS-1.

### Группа 6 — Прозаический слой (параллельно друг другу после T21; от кода групп 2–5 не зависит)

- [x] **T21** `[TEST]` Статические grep-инварианты текстов (красные до T22–T30)
  - Зависит от: —
  - Файлы: `sdx/hooks/test-mo-hook.sh` (отдельная секция «static»; решение lead-dev: один файл, чтобы не расширять `test-hook-wiring.sh`, не переносимый на macOS из-за `mapfile`)
  - Что: инварианты DESIGN «Статические проверки»: `agents/devops.md` — каждая строка с `mesh_endpoint.py` содержит `PYTHONDONTWRITEBYTECODE=1` (либо это определение `mo()` с ним), файл содержит `.mesh/endpoint.yaml`, `request`, `auto`; `claude-md-snippet.md` — `.mesh/endpoint.yaml` между `SDX:BEGIN` и `SDX:END`; `commands/init.md` — строка `.mesh/`; `sdx/protocol.md` — «Восемь тегов» и 0 вхождений «семь тегов»/«семи тегов»; `commands/verify.md` и `commands/resume.md` — нет перечня тегов и числа тегов (REQ-MO-PROTO-2: предмет отсутствует, `grep -cE 'семь|восемь|\[триаж\]\s*,\s*\[' ` = 0 — подобрать выражение по факту текста и записать его в тесте); пункты стоп-рубрики не изменены (сверка списка с `git show main:sdx/protocol.md`, неизменность).
  - DoD: до T22–T28 секция красная (показать список красных строк); красные стороны контролем на копиях: копия `protocol.md` с «семь тегов» → красная; копия `devops.md` с вызовом `mesh_endpoint.py` без флага → красная; копия сниппета без блока → красная; на копии `init.md` без `.mesh/` → красная; после T22–T28 — зелёная.
  - Закрывает: К14, К15, К16 (grep-часть), К17 (grep-часть).

- [x] **T22** `[DOC]` `sdx/protocol.md`: тексты 1.1–1.5, 1.9 (теги, стоп-рубрика, enforcement-слой)
  - Зависит от: T21
  - Файлы: `sdx/protocol.md`
  - Что: DESIGN «Схема данных / API → Тексты правок → 1»: 1.1 («Восемь» тегов, `[директива]`, оговорка про шесть/седьмой/восьмой, «один из восьми»); 1.2 (пример `directive` после «Критерий по умолчанию для не перечисленного…», СПИСОК пунктов стоп-рубрики не менять); 1.3 (вводный абзац «Enforcement-слой»); 1.4 («Механизм блокировки PreToolUse»); 1.5 (заголовок «Оставшиеся три хука…» + предложение-граница в `prod-guard`); 1.9 (`(SessionStart, PreToolUse, Stop)`).
  - DoD: `grep -cE 'семь(и)? тегов' sdx/protocol.md` = 0, «Восемь» есть; `diff` пунктов стоп-рубрики с `main` пуст; секция T21 по протоколу зелёная; `bash sdx/hooks/test-sdx-stage.sh` зелёный (таблица этапов не тронута).
  - Закрывает: К17, К18 (часть). Параллельно: T23–T28.

- [x] **T23** `[DOC]` `sdx/protocol.md`: новый подраздел «МО-хук» (1.6)
  - Зависит от: T22 (тот же файл — последовательно после него)
  - Файлы: `sdx/protocol.md`
  - Что: подраздел «МО-хук (`mo-hook`, `mo-session`) — FEAT-015, ADR-021» перед «Вендорённые компоненты (`sdx/mo/`)»: две записи проводки, граница с `prod-guard`, различие политик отказа, четыре честные границы (а)–(г), оговорка «приоритет решений нескольких хуков — свойство харнесса, не проверено до Verification».
  - DoD: `grep -c 'PYTHONDONTWRITEBYTECODE' sdx/protocol.md` ≥ 1 в подразделе; в тексте явно названы: подмена `endpoint.yaml` через `Bash`, best-effort охрана, лексическая нормализация, прямой вызов без флага; `deny > defer > ask > allow` помечено как не подтверждённое; ссылки на `BUG-002/008/010` присутствуют.
  - Закрывает: К18 (часть), REQ-MO-PROTO-4/5.

- [x] **T24** `[DOC]` `sdx/protocol.md`: 1.7 (устаревшие фразы) и 1.8 (`Deployment` под МО)
  - Зависит от: T23 (тот же файл)
  - Файлы: `sdx/protocol.md`
  - Что: 1.7 (i) «Каталог поставлен `FEAT-015`…», (ii) пункт «Обновление»: норма «не в auto» названа и в `agents/devops.md` (DEBT-042); 1.8 — новый абзац «`Deployment` под МО (FEAT-015)» после абзаца `Documentation`/`Deployment (REQ-SCALE-6)`, ТАБЛИЦУ этапов не менять; не заявлять «согласовано владельцем МО».
  - DoD: `! grep -q 'Пока `FEAT-015` не поставлена' sdx/protocol.md`; `! grep -q 'в текстах команд `/sdx:\*` её тоже нет' sdx/protocol.md` (подобрать точные подстроки по факту); `bash sdx/hooks/test-sdx-stage.sh` зелёный; `grep -c 'согласован' ` не утверждает согласования с владельцем.
  - Закрывает: К18 (норма `Deployment`), REQ-MO-PROTO-3.

- [x] **T25** `[DOC]` `commands/next.md`: шаг 2в
  - Зависит от: T21
  - Файлы: `commands/next.md`
  - Что: перечень «… ручной шаг), явным актом триажа находки или остановкой по правилу для неперечисленного (входящая `directive` от МО в `auto` — тег `[директива]`)»; «четыре поля…» не менять. Проверить `grep` в `commands/verify.md`/`resume.md`: перечня и числа тегов нет — зафиксировать результат в сообщении коммита.
  - DoD: `grep -c '\[директива\]' commands/next.md` ≥ 1; `git diff commands/next.md` — только эта правка; `verify.md`, `resume.md`, `status.md` не изменены (`git diff --stat` не содержит их).
  - Закрывает: К17.

- [x] **T26** `[DOC]` [PROC-020] `agents/devops.md`: «Режим МО»
  - Зависит от: T21
  - Файлы: `agents/devops.md`
  - Что: после «Контекст объёма и флагов» вставить раздел из DESIGN «Тексты правок → 3» (переключатель по `.mesh/endpoint.yaml`, деактивированное/остающееся, функция `mo()` с `PYTHONDONTWRITEBYTECODE=1`, фиксация `msg_id`, входящие — данные, `directive` в `auto` — остановка, механизм надзора не в `auto`); инструкция 3 получает префикс «Если `.mesh/endpoint.yaml` отсутствует:»; frontmatter не менять.
  - DoD: секция T21 по `devops.md` зелёная (каждая строка с `mesh_endpoint.py` несёт флаг); `git diff agents/devops.md` — frontmatter без изменений (`sed -n '1,/^---$/p'` совпадает с `main`); в тексте есть `request`, `artifact.offer`, `auto`, `PROC-020`, `DEBT-042`.
  - Закрывает: К16, REQ-MO-DEVOPS-1/2/3.

- [x] **T27** `[DOC]` `commands/init.md`: `.mesh/` в блоке `.gitignore`
  - Зависит от: T21
  - Файлы: `commands/init.md`
  - Что: в блок `.gitignore` шага 2 после `.sdx/audit-runs/` и перед `.claude/settings.local.json` вставить комментарий + `.mesh/` (текст DESIGN «Тексты правок → 4»). `reconcile.md` не править (проверено: поимённого перечня нет — подтвердить `grep` и записать в коммит).
  - DoD: `grep -n '^\.mesh/$' commands/init.md` — 1; `bash sdx/hooks/test-init-patterns.sh` зелёный; `git diff --stat` не содержит `commands/reconcile.md` и `.gitignore`.
  - Закрывает: К14.

- [x] **T28** `[DOC]` `sdx/templates/claude-md-snippet.md`: абзац «МО над стендами»
  - Зависит от: T21
  - Файлы: `sdx/templates/claude-md-snippet.md`
  - Что: после пункта «Роли», внутри `SDX:BEGIN…END`, пункт из DESIGN «Тексты правок → 5» (условный).
  - DoD: `sed -n '/SDX:BEGIN/,/SDX:END/p' sdx/templates/claude-md-snippet.md | grep -c '\.mesh/endpoint\.yaml'` ≥ 1; маркеры `SDX:BEGIN/END` целы (по одному); секция T21 зелёная; красная сторона T21 (копия без абзаца) краснеет.
  - Закрывает: К15.

- [x] **T29** `[DOC]` ADR-021 + строка в поправке ADR-013
  - Зависит от: T22–T24 (решения ссылаются на тексты протокола)
  - Файлы: `docs/DECISIONS.md`
  - Что: ADR-021 по формату соседних ADR (контекст / решение (1)–(7) / последствия (границы 1.6) / отвергнутое (список из DESIGN)); в поправке 2026-10-04 к ADR-013 дописать «(решения интеропа — ADR-021)»; перечень трёх имён файлов в поправках СОХРАНИТЬ. Дата — дата коммита/Closeout.
  - DoD: `grep -n '^## ADR-021\|ADR-021' docs/DECISIONS.md` находит запись и ссылку из ADR-013; `grep -c 'mesh_endpoint.py\|devagent_hook.py\|MO-INTEROP.md' docs/DECISIONS.md` не уменьшился относительно `main`; в ADR перечислены все 6 отвергнутых вариантов.
  - Закрывает: К18 (ADR), REQ-MO-PROTO-6.

- [x] **T30** `[DOC]` Поверхности состава: `README.md`, `README.en.md`, `CLAUDE.md` §6
  - Зависит от: T01
  - Файлы: `README.md`, `README.en.md`, `CLAUDE.md`
  - Что: DESIGN «Тексты правок → 6»: строка `sdx/mo/` в таблице «Состав плагина» (RU и EN симметрично), `sdx/hooks/` + `mo-hook, mo-session`, абзац про МО-хуки «молчат без `.mesh/endpoint.yaml`», строка `sdx/` в `CLAUDE.md` §6 с тремя именами. Три имени (`mesh_endpoint.py`, `devagent_hook.py`, `MO-INTEROP.md`) — literal match на каждой поверхности.
  - DoD: `bash sdx/hooks/test-mo-inventory.sh` ЦЕЛИКОМ зелёный ([6] проверка поверхностей (д)); красная сторона: на копии без одного имени в `README.en.md` (scratchpad) → (д) красный; двуязычная пара — одни и те же факты (визуальная сверка, строка в коммите); `git diff CLAUDE.md` меняет только строку `sdx/` в §6.
  - Закрывает: К19. Параллельно: T22–T29.

### Группа 7 — Ручной сценарий, финальная проверка, внешняя записка

- [x] **T31** `[TEST]` [DOC] `MANUAL_TEST.md`: ручной сценарий «два PreToolUse на `Bash`» + «канал SessionStart»
  - Зависит от: T20 (проводка существует; сценарий исполняется на Verification)
  - Файлы: `.claude/sessions/feat-015-mo-interop-20261004/MANUAL_TEST.md` (новый)
  - Что: перенести DESIGN «Ручной сценарий для Verification» дословно как действие / предусловие / ожидаемое: подготовка (`mktemp -d`, `.claude/sdx/prod-guard.conf` = `PGDENY`, `.mesh/endpoint.yaml` с `exec_paths` и `on_write: deny`, `python3`+PyYAML+`jq`, `claude --plugin-dir /home/archi/Code/sdx-claude-plugin`, проверка загрузки `hooks.json` через `/hooks`/`--debug`); случаи 1–6; критерий (1, 2 — блок при «молчащем» втором хуке в обе стороны; 3 — блок; 4 — проход); поля для записи результата (версия `claude --version`, фактический текст блока, наличие/отсутствие файлов `dep/x`); отдельный блок «Канал SessionStart» («видит»/«не видит»); явная ветка «выполнить нельзя» → допущение «агрегация решений двух хуков не проверена» записывается как НЕПРОВЕРЕННОЕ (не «подтверждено») в `verification_report.md`/`change_note.md`/`DESIGN.md`. Прогон — задача `qa`/пользователя на Verification, не Execution (задача выполнена созданием файла).
  - DoD: `grep -c '^## Случай' MANUAL_TEST.md` ≥ 7 (6 случаев + канал SessionStart); для каждого случая есть строки «Ожидаемый результат» и «Результат (заполняется)»; в файле присутствует фраза «не проверено» в ветке невозможности; `PGDENY` и `MESH`-пути совпадают с DESIGN.
  - Закрывает: К20, К21 (живая часть — описана; исполнение внешнее).

- [x] **T32** `[INFRA]` Финальный прогон: `verify-cmd.sh` + `test-mo-inventory.sh [6]` зелёные, чистота артефактов, не-`auto`
  - Зависит от: T03, T13, T18, T20, T21–T30
  - Файлы: — (проверка; результат в коммите/`change_note`-заметке)
  - Что: `bash .claude/sdx/verify-cmd.sh` целиком; отдельно `bash sdx/hooks/test-mo-inventory.sh`; проверки: `ls -a sdx/mo` без `__pycache__`; `find . -name __pycache__ -not -path './.git/*'` пусто; `git status --porcelain` пуст; сьюты `test-mo-hook.sh`, `test-mo-session.sh`, `test-hook-wiring.sh [6]` подхвачены глобом `test-*.sh` (видны в выводе verify-cmd); зелёная живая сторона К21: `CLAUDE_PROJECT_DIR=$PWD bash sdx/hooks/mo-hook.sh <<<'{"tool_name":"Bash","tool_input":{"command":"ls"}}'` и то же для `mo-session.sh` в этом репо (`.mesh/` нет) → пустой stdout/stderr, rc 0; `jq -r .gate_mode .claude/sessions/feat-015-mo-interop-20261004/session_state.json` != `auto`; `diff` пунктов стоп-рубрики с `main` пуст.
  - DoD: `verify-cmd.sh` exit 0 со всеми сьютами зелёными (приложить итоговые строки `Results:`); `test-mo-inventory.sh` [6] — зелёный и НЕ «пропуск (INFO)»; перечисленные проверки чистоты дают пустой вывод; каждая из красных сторон T03/T13/T18/T19/T21 показана в соответствующих коммитах (ссылки на хеши в записи).
  - Закрывает: К1, К19, К21 (зелёная сторона), К22.

- [x] **T33** `[DOC]` **ВНЕШНЯЯ** — записка upstream в sim-kit (текст-заготовка; отправка вне репозитория на Closeout)
  - Зависит от: T13 (факты о `DH:181` vs `DH:38` подтверждены прогоном)
  - Файлы: `.claude/sessions/feat-015-mo-interop-20261004/upstream_note_sim-kit.md` (только в каталоге сессии; в репо плагина не архивируется, в `sim-kit` НЕ пишется в Execution)
  - Что: текст-заготовка адресата `agentico/reviews/` (sim-kit): (1) `MO-INTEROP.md` §5 и docstring `devagent_hook.py:17–18` вызывают инструменты без `PYTHONDONTWRITEBYTECODE=1` → в плагинной модели создаётся `sdx/mo/__pycache__/` в корне плагина (нарушение ADR-013); просьба: добавить флаг в примеры/docstring; (2) регистр `on_write`: `raw_mode` приводит к нижнему (`DH:38`), основной путь сравнивает `== "deny"` с учётом регистра (`DH:181`) — `on_write: DENY` блокирует при `cannot_check` и НЕ блокирует в штатной проверке (прогнано: rc 0, notice отправлен); (3) факт: плагин фиксирует норму `Deployment` под МО (завершается отправкой `artifact.offer`/`request`), формального согласования владельцем МО нет — вопрос 5 `intake.md`. С воспроизводящими командами и ссылками на строки. Выполняется ПОСЛЕ Verification, на Closeout — оркестратор/пользователь кладёт в `sim-kit/agentico/reviews/`; это внешнее действие, не гейт сессии.
  - DoD: файл существует, содержит 3 пункта с номерами строк `DH`/`MI` и воспроизводящей командой для п.2; `grep -c 'PYTHONDONTWRITEBYTECODE' upstream_note_sim-kit.md` ≥ 1; в `/home/archi/Code/aibok/agentico/meta-orchestrator/sim-kit` ничего не изменено (`git -C … status --porcelain` пуст относительно начала сессии).
  - Закрывает: границы SPEC («Правки вендорённых файлов» — только записка upstream); критерия SPEC не закрывает (внешняя, вне поставки).

### Группа 8 — Closeout (после Verification; не Execution)

- [ ] **C1** `[DOC]` Результат ручного шага: записать итог `MANUAL_TEST.md` (К20) и «канал SessionStart» (видит/не видит) как факт или непроверенное допущение — в `verification_report.md`/`change_note`-месте; текст ADR-021/протокола синхронизировать, если «не проверено» → «подтверждено/опровергнуто».
- [ ] **C2** `[DOC]` Бэклог (`docs/backlog/`, ADR-015): новые `DEBT-`/`IDEA-` записи — расширение периметра `selftest.sh` и строка «МО: python3/PyYAML» в `/sdx:status` (класс DEBT-010); хеш-проверка установленной копии `sdx/mo/` в рантайме; регистр `on_write` `DH:181` vs `DH:38` (ссылка на записку T33); статус `FEAT-015` → закрыт; формальное согласование нормы `Deployment` с владельцем МО (вопрос 5 `intake.md`).
- [ ] **C3** `[DOC]` Релиз: минорная версия `plugin.json`, двуязычные накопительные релизные заметки; тег на merge-коммите (практика репо); `/plugin marketplace update sdx` для обновления установленной копии; дата в ADR-021.
- [ ] **C4** `[INFRA]` Отправить записку T33 в `sim-kit/agentico/reviews/` (внешнее действие, по явному подтверждению пользователя); приёмка на MOVE.IO (К21, В) — вне поставки, записать как открытый хвост.

## Зависимости между задачами

```
T01 ─┬─> T02 ─> T03
     ├─> T09 (копия вендорённого DH для сц. 8–9), T15, T30

Группа 2/3 (mo-hook):
T04 ─┬─> T05, T06, T07, T08, T09      (тесты в одном файле — писать последовательно, порядок любой;
     │                                  каждая красная до реализации)
     ├─> T10 (шаги 1–3; нужны T05, T06) ─┬─> T11 (шаг 4; нужны T08)
     │                                    └─> T12 (шаги 5–6; нужны T07, T09)
     └─> T13 (мутанты, сц. 10; нужны T11, T12)

Группа 4 (mo-session) — ПАРАЛЛЕЛЬНА группе 2/3:
T14 ─> T15 ─> T16 ─> T17 ─> T18          (T16 нужен только T14; T17 нужен T15)

Группа 5 (проводка):
T19 (параллельно всему; красный) ; T12 + T17 + T19 ─> T20

Группа 6 (проза) — параллельна группам 2–5:
T21 ─┬─> T22 ─> T23 ─> T24 ─> T29       (protocol.md — один файл, последовательно)
     ├─> T25, T26, T27, T28            (разные файлы, параллельно между собой и с T22–T24)
T01 ─> T30 (параллельно T22–T29)

T20 ─> T31 (MANUAL_TEST.md)
T13 ─> T33 (записка upstream; текст, внешняя)

Финал: T03, T13, T18, T20, T21–T30 ─> T32 ─> [Verification: /sdx:verify, /sdx:manual по T31] ─> C1–C4 (Closeout)
```

Параллельные «дорожки» (разные файлы, конфликтов нет): **A** — T04…T13 (`test-mo-hook.sh`, `mo-hook.sh`); **B** — T14…T18 (`test-mo-session.sh`, `mo-session.sh`); **C** — T19 (`test-hook-wiring.sh`); **D** — T21…T30 (проза и поверхности). Узкие места: T20 (ждёт обе дорожки A и B + C), T32 (ждёт все).

Рекомендуемый порядок одним проходом: T01 → T02 → T03 → (T04…T09 красные) → T10 → T11 → T12 → T13 → (T14, T15 красные) → T16 → T17 → T18 → T19 → T20 → T21 → T22…T30 → T31 → T32 → T33. Задачи, помеченные **[PROC-020]**, — T04–T20, T26 (и T14–T18): оркестратор подтверждает не-`auto` перед каждой.

## Тестовый цикл

- Полный прогон: `bash .claude/sdx/verify-cmd.sh` (глоб `sdx/hooks/test-*.sh`: новые `test-mo-hook.sh`, `test-mo-session.sh` и расширенный `test-hook-wiring.sh` подхватываются без регистрации).
- Сторож: `bash sdx/hooks/test-mo-inventory.sh` не правится; после T01 [6] реальный; проверка поверхностей (д) красная ожидаемо до T30.
- Окружение без `python3`/PyYAML: сц. 4, 5(мутант-паритет), 8, 9 `test-mo-hook.sh` и сц. 7 `test-mo-session.sh` дают INFO-skip, не PASS (REQ-MO-INV-2); в DoD T12/T17/T32 указывается, какой вариант (PASS/INFO) получен.

## Таблица «критерий SPEC → задачи»

| Критерий SPEC | Задачи |
|---|---|
| К1 — `sdx/mo/` состав/байты, `test-mo-inventory.sh` [6] реальный | T01, T02, T03, T32 |
| К2 — нет `endpoint.yaml`: тишина, python/jq не тронуты; мутант без раннего выхода | T04, T10, T13 |
| К3 — режим `on_write` как у `DH` | T05, T10, T13 |
| К4 — нет `python3`: notice строка / deny JSON | T06, T10, T12 |
| К5 — python3 есть, PyYAML нет | T06, T12 (делегировано `DH`) |
| К6 — `DH` rc 2 → JSON deny, без дубля; мутант | T07, T09, T12, T13 |
| К7 — иной код выхода `DH` (1, 127) | T06, T12 |
| К8 — `DH` rc 0, stdin доставлен целиком | T07, T09, T12 |
| К9 — охрана `.mesh/endpoint.yaml`/`cursors.json` | T08, T11, T13 |
| К10 — нет `__pycache__`; мутант без `PYTHONDONTWRITEBYTECODE`; `mo-session.sh` | T07, T09, T12, T13, T14, T15, T17, T18 |
| К11 — `hooks.json` и `test-hook-wiring.sh` | T19, T20 |
| К12 — `mo-session.sh` поведение (без/с `.claude/sdx`) | T14, T15, T16, T17, T18 |
| К13 — запись `mo-session.sh` ограничена `.mesh/` | T15, T17 |
| К14 — `.mesh/` в `init.md`, `test-init-patterns.sh`, `reconcile.md` | T21, T27 |
| К15 — абзац «МО над стендами» в сниппете | T21, T28 |
| К16 — `agents/devops.md` (переключатель, флаг, не в `auto`) | T21, T26 (живое поведение — внешне, В) |
| К17 — восемь тегов согласованы, `[директива]` в «Стоп-рубрике» | T21, T22, T25 |
| К18 — `Deployment` под МО, граница `prod-guard`/МО-хук, описание слоя, ADR | T22, T23, T24, T29 |
| К19 — поверхности состава, `verify-cmd.sh` зелёный | T30, T32 |
| К20 — проверка двух хуков на `Bash` на реальном харнессе | T31 (создание сценария); исполнение — Verification, итог — C1 |
| К21 — живая проверка на MOVE.IO (вне поставки) / зелёная сторона «нет `.mesh`» | T32 (зелёная сторона), T31; внешняя часть — C4 |
| К22 — сессия не в `gate_mode: auto` | правила исполнения, метки [PROC-020], T20, T32 |

Все 22 критерия привязаны хотя бы к одной задаче. T33 (записка upstream) и C1–C4 — внешние/Closeout, критерии не закрывают, кроме указанных хвостов К20/К21.


## Отклонения при исполнении (фиксируются здесь, не сглаживаются)
- **T03**: красные мутации сторожа на реальном `sdx/mo/` не прогонялись при отметке — перенесены в T32 (финальный прогон).
- **T04–T12 (дорожка A)**: порядок TDD не соблюдён — реализация написана раньше сьюта; красная сторона показана задним числом прогоном с `MO_HOOK_UNDER_TEST=/nonexistent` (17 passed / 274 failed) и 11 мутантами по меткам. Это нарушение DoD по форме, не по существу доказательства.
- **T21**: grep-инварианты текстов — в отдельном сьюте `test-mo-prose.sh`, а не в `test-mo-hook.sh` (решение оркестратора: дорожки не делят файлы). Проверка «пункты стоп-рубрики неизменны относительно `main`» в сьют не вошла (сверка с веткой хрупка) — подтверждена diff'ом.
- **T18**: красной стороны «без `PYTHONDONTWRITEBYTECODE` → `__pycache__`» у `mo-session.sh` нет по построению (скрипт — `__main__`, ничего не импортирует локально; байткод не пишется и без переменной — прогнано); различимо только по env-логу. Для `mo-hook.sh` (есть импорт) красная сторона есть (`[9]`).
- **Сторож `test-mo-inventory.sh` правлен в круге 2** (отсутствие `sdx/mo/` → FAIL, красная сторона [6r], `MO_DIR_UNDER_TEST`), вопреки SPEC REQ-MO-VEND-3/DESIGN «не правится» — причина: после поставки отсутствие каталога стало регрессом.
- **Время прогона**: `test-mo-hook.sh` первоначально ≈ 66 с (полный `verify-cmd.sh` ≈ 98 с при потолке `stop-gate` 180 с); ужат до ≈ 20 с без потери веток (представители в `[10]`, покрывающий набор в `[7]`, 122 → 104 проверки, 11 мутантов на месте) — полный прогон ≈ 54 с; комментарий `verify-cmd.sh` актуализирован.
- **T32 факт**: 15/15 сьютов, 371 проверка, 54 с; мутации T03 на реальном `sdx/mo/` (локальная правка, лишний файл, `__pycache__`, переименование в README) — каждая 18/1; `sdx/mo/__pycache__` отсутствует; `gate_mode: interactive`; `mo-hook.sh`/`mo-session.sh` в этом репо без `.mesh/` — rc 0, вывод пуст (К21, зелёная сторона).
