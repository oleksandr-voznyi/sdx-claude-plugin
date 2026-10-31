# Implementation Plan: FEAT-017 — сдача пакетом изменения (плагин 2.5.0 «/sdx:pr»)

## Статус реализации
21/82 задач Execution (T01–T82; дорожка Ф T01–T21 выполнена, gate Ф зелёный), 0/3 задач Closeout (C1–C3). Этап: Execution (дорожки A/B/C — не начаты).

Условные обозначения. `SPEC`/`DESIGN` — одноимённые файлы этой сессии (SPEC включает раздел «Поправки по коллизиям DESIGN» К-1…К-12 и REQ-PKG-36, обязательный). `ДЛ` — `decisions_log.md`. `К-N` — коллизии DESIGN. `A1…A16` — критерии приёмки SPEC в порядке их записи (см. таблицу покрытия внизу). `SK` = `/home/archi/Code/aibok/agentico/meta-orchestrator/sim-kit`. Якоря `# PKG-*` — метки мутационных прогонов (определены в DESIGN). Дорожки: **Ф** — фундамент (последовательно, один исполнитель), **A**, **B**, **C** — параллельные `developer` после Ф, **З** — замыкание (последовательно, после A/B/C).

## Правила исполнения (для всех задач)

- **Не `gate_mode: auto` (PROC-020).** Поставка не меняет механизм надзора (`mo-hook.sh`, `mo-session.sh`, `hooks.json`), но трогает `sdx/mo/` (T02) и `lib/mandate.sh`/`mandate-info.sh`; метка **[PROC-020]** — перед такой задачей оркестратор проверяет `jq -r .gate_mode session_state.json` != `auto`, иначе стоп. Вся сессия идёт не в `auto` (проверка в T82).
- **Коммит на ветке `sdx/feat-017-mo-change-package-20261031` после каждой задачи** (`sdx(feat-017-mo-change-package-20261031): T<NN> …`). Дорожки A/B/C правят **непересекающиеся файлы** (см. «Владение файлами»); `--amend` запрещён (прецедент feat-016).
- **TDD.** Для каждой `[CODE]`-задачи сначала фиксируется красная `[TEST]`-задача (в DoD: `bash <suite>; echo $?` != 0 и перечень красных строк), затем код делает её зелёной, затем (где указано) мутанты. Порядок «реализация раньше теста» — отклонение, фиксируется в разделе «Отклонения».
- **Мутационная дисциплина.** Мутант = копия скрипта (+ `lib/`) в `mktemp -d` + `sed` по метке `# PKG-*`; перед прогоном `! cmp -s orig mutant`; в выводе сьюта строка «мутант X → красный (ожидаемо)» с указанием краснеющего сценария. В мутационной подстановке `sed`/`${v//}` помнить про `shopt -u patsub_replacement` (bash >= 5.2, прецедент feat-016). Чекаут мутациям не подвергается (`git status --porcelain` пуст после прогона). Вложенный прогон мутанта: `<SUITE>_NESTED=1`, путь изменённого скрипта `<SUITE>_UNDER_TEST`, `SCEN_MIN=1` сокращает матрицу до различающего блока.
- **Переносимость (BUG-010).** bash 3.2: нет `declare -A`, `mapfile`, `timeout`, `${v,,}`, `date +%s%N`, GNU-флагов `sed/cp/stat`, **массивов** (списки — строки через `\n`); `LC_ALL=C` для awk/glob; скрипты вызываются как `bash <путь>`. Тест портируемости `FORBID` (как `test-mo-hook.sh [12]`) покрывает все новые lib/скрипты. **В новых скриптах нет `python`/`python3`/`eval`** (исключение — `order-import.sh from-msg` вызывает `mesh_endpoint.py`, который сам требует python; python в тестах — только оракул с INFO-skip).
- **Тесты.** Итог сьюта `Results: N passed, M failed`; `mktemp -d` + `trap`; без записи в чекаут и без `__pycache__` (`PYTHONDONTWRITEBYTECODE=1`); блоки выбираются `<SUITE>_ONLY` (`PR_BUILD_ONLY`, `PR_CHECK_ONLY`, `PR_PUBLISH_ONLY`, `PROTOCOL_EXPORT_ONLY`, `ORDER_IMPORT_ONLY`); фикстуры — `lib/pkg-fixture.sh` (шаблон собирается один раз за прогон, `cp -a` на блок). Оракульные ветки (python3/PyYAML) при отсутствии дают INFO-skip, не PASS; в DoD T21/T77 указывать, какой вариант получен. Сьюты подхватываются глобом `verify-cmd.sh` (регистрация не нужна).
- **Размер задачи ≈ ≤30 строк кода**; если задача выходит за предел — делится на два коммита с общим DoD (как T02 feat-016).
- **Не менять (инвариант, проверка T80):** `hooks/hooks.json`, `sdx/hooks/stop-gate.sh`, `archive-verify.sh`, `sdx-stage.sh`, `mo-hook.sh`, `mo-session.sh`, `lib/miniyaml.sh`, `lib/test-cmd.sh`, `agents/reviewer.md`, три прежних файла `sdx/mo/` (`mesh_endpoint.py`, `devagent_hook.py`, `MO-INTEROP.md`); `marketplace.json` версии не содержит.
- **Внутренние служебные коммиты/записи не обходят хуки:** командные строки `/sdx:pr` не содержат перенаправлений `>` в проект (К-17).
- **Допущение плана сверх DESIGN (отмечено как отклонение 0):** добавлен малый сьют `test-pkg-fixture.sh` (самопроверка помощника и python-оракула, T16) — иначе общий помощник не имел бы собственной красной стороны (TDD); бюджет ≈ 1,5 с, в бюджет К-10 заложен.

## Владение файлами

| Дорожка | Файлы (исключительное владение) |
|---|---|
| Ф | `sdx/mo/CHANGE.template.yaml`, `sdx/mo/SIMKIT_SHA256`, `sdx/mo/README.md`, `sdx/templates/CONTRIBUTING-MO.md`, `sdx/hooks/lib/{pr-lib,pkg-fixture,mandate}.sh`, `test-mandate-lib.sh`, `test-mo-inventory.sh`, `test-pkg-fixture.sh`; упоминания имени в README×2/CLAUDE.md/protocol.md/DECISIONS.md (T03, единожды) |
| A | `order-import.sh`, `protocol-export.sh`, `test-order-import.sh`, `test-protocol-export.sh`, `test-sdx-stage.sh` (только [42]) |
| B | `pr-build.sh`, `pr-check.sh`, `pr-publish.sh`, `test-pr-build.sh`, `test-pr-check.sh`, `test-pr-publish.sh` |
| C | `mandate-info.sh`, `test-mandate-scope.sh`, `commands/{pr,archive,start,status}.md`, `test-mo-prose.sh` (до T68) |
| З | всё остальное: `sdx/protocol.md`, `docs/*`, `README*`, `CLAUDE.md`, `agents/devops.md`, сниппет, `plugin.json`, `test-mo-prose.sh` (после T68), `.claude/sdx/verify-cmd.sh` |

После Ф файлы `lib/pr-lib.sh`, `lib/pkg-fixture.sh`, `lib/mandate.sh` — **заморожены**: дорожка, которой нужна правка библиотеки, фиксирует это в «Отклонениях» и возвращает задачу оркестратору (правит исполнитель Ф до продолжения дорожек).

## Чек-лист задач

### Дорожка Ф — Фундамент (последовательно; блокирует A, B, C)

#### Ф-0. Вендоринг и «как сдать изменение» (DESIGN T0; К-1)

- [x] **T01** `[TEST]` [PROC-020] `test-mo-inventory.sh`: четвёртый вендорённый файл и красная сторона `CONTRIBUTING-MO.md`
  - Зависит от: —
  - Файлы: `sdx/hooks/test-mo-inventory.sh` (только добавление; правила (c)/(d)/(e) не меняются)
  - Что: прочитать текущие правила (c)/(d)/(e) сьюта и добавить проверки: на реальном `sdx/mo/` присутствуют четыре файла, `CHANGE.template.yaml` имеет строку в `SIMKIT_SHA256`, проходит (c)/(d)/(e) и упомянут на пяти поверхностях (`README.md`, `README.en.md`, `CLAUDE.md`, `sdx/protocol.md`, `docs/DECISIONS.md`); красная сторона на фикстуре: `CONTRIBUTING-MO.md` внутри копии `sdx/mo/` — находка (d).
  - DoD: `bash sdx/hooks/test-mo-inventory.sh; echo $?` != 0 (нет файла/строки хеша/упоминаний); прежние проверки зелёные; перечень красных строк приложен.
  - Закрывает: REQ-PKG-28, 29; A14 (тестовая часть).

- [x] **T02** `[INFRA]` [PROC-020] Вендоринг `CHANGE.template.yaml` sim-kit 0.9.1 (датированное отступление от PROC-028, К-1)
  - Зависит от: T01
  - Файлы: `sdx/mo/CHANGE.template.yaml` (новый), `sdx/mo/SIMKIT_SHA256` (строка добавляется в порядке существующих), `sdx/mo/README.md` (упоминание)
  - Что: из каталога `SK` (`cd SK && git show sim-kit-0.9.1:./CHANGE.template.yaml > <tmp>`), сверить `sha256` с `346d2e6e52477faf69811411dfa11a96526daa28639a05ff523b9e90d86fd5cd` **в момент копирования** и с рабочей копией `SK/CHANGE.template.yaml`; копия побайтовая (без правок, перевод строки как в теге); `SIMKIT_VERSION` остаётся `0.9.1`; три прежних файла не трогаются.
  - DoD: `(cd sdx/mo && sha256sum -c SIMKIT_SHA256)` — `OK`×4; `git diff --stat main -- sdx/mo/mesh_endpoint.py sdx/mo/devagent_hook.py sdx/mo/MO-INTEROP.md sdx/mo/SIMKIT_VERSION` пуст; `git -C SK status --porcelain` не добавил изменений; в сообщении коммита — оба хеша.
  - Закрывает: REQ-PKG-28; A14.

- [x] **T03** `[DOC]` Упоминание `CHANGE.template.yaml` на пяти поверхностях сторожа и оговорка К-1
  - Зависит от: T02
  - Файлы: `README.md`, `README.en.md`, `CLAUDE.md`, `sdx/protocol.md`, `docs/DECISIONS.md` (минимальные правки: имя файла в перечне вендорённых; в `protocol.md` «Вендорённые компоненты» — оговорка «добавление файла того же выпуска допустимо в сессии поставки, обновление версии — по-прежнему отдельная сессия»)
  - Что: полный текст документов — T70–T74; здесь только то, что нужно сторожу инвентаря. Правка README пары симметрична (RU/EN, те же факты).
  - DoD: `bash sdx/hooks/test-mo-inventory.sh` зелёный (T01 → зелёный); `grep -c 'CHANGE.template.yaml'` ≥ 1 в каждом из пяти файлов; `bash sdx/hooks/test-mo-prose.sh` не краснее, чем до задачи.
  - Закрывает: REQ-PKG-28; A14.

- [x] **T04** `[DOC]` `sdx/templates/CONTRIBUTING-MO.md` — «как сдать изменение» (нейтрально к инструменту)
  - Зависит от: T02
  - Файлы: `sdx/templates/CONTRIBUTING-MO.md` (новый; собственный текст SDX, не вендорённый)
  - Что: по DESIGN «Вендоринг, шаблон «как сдать»»: что такое пакет и кому отдавать; имя ветки `change/<C>-<executor>`; порядок «код → один squash-коммит → `CHANGE.yaml` отдельным последним коммитом»; таблица полей манифеста с командами вычисления (`git rev-parse`, `git archive --format=tar <head> | sha256sum`, `git diff --name-only`); `touches_shared`, `adr`, `docs`; область и срок мандата; схема `protocol.yaml` (пять списков, `decisions[] {id, what, why}`) и куда положить; что делает узел сам, чего исполнитель не делает (слияние, теги, push в защищённые ветки); чек-лист самопроверки; ссылка на `sdx/mo/CHANGE.template.yaml`; упоминаются только `git`, `sha256sum`, текстовый редактор.
  - DoD: `bash sdx/hooks/test-mo-inventory.sh` зелёный (в `sdx/mo/` файла нет); `grep -cE 'CHANGE.template.yaml|archive_sha256|touches_shared|protocol.yaml|change/<C>-<executor>' sdx/templates/CONTRIBUTING-MO.md` ≥ 5; `grep -nE 'sdx:|Claude|/sdx' sdx/templates/CONTRIBUTING-MO.md` пусто (нейтральность).
  - Закрывает: REQ-PKG-29; A14.

#### Ф-1. `mandate_fnmatch` и `lib/pr-lib.sh` (DESIGN T1)

- [x] **T05** `[TEST]` [PROC-020] `test-mandate-lib.sh`: секция `[P]` — таблица `mandate_fnmatch` (красная)
  - Зависит от: T04
  - Файлы: `sdx/hooks/test-mandate-lib.sh` (только добавление; L1–L9 не правятся)
  - Что: таблица ≥ 15 случаев: `change/*` ↔ `change/C-ex1` да; `change/*` ↔ `feat/x` нет; `change` ↔ `change/x` **нет** (у `mandate_glob_one` — да; отдельная строка-«различитель»); `[^x]`, `[!x]`, `\`, пустой шаблон, регистр, `*` без разделителя; вызов при `LC_ALL=C`.
  - DoD: `bash sdx/hooks/test-mandate-lib.sh` — старые L1–L9 зелёные, секция `[P]` красная (функции нет); перечень приложен.
  - Закрывает: REQ-PKG-11 (е); A2 (тестовая часть).

- [x] **T06** `[CODE]` [PROC-020] `lib/mandate.sh`: `mandate_fnmatch` (`# PKG-FNMATCH`)
  - Зависит от: T05
  - Файлы: `sdx/hooks/lib/mandate.sh` (добавление одной функции; остальные не тронуты)
  - Что: функция из DESIGN дословно (`_my_rep` для удвоения `\` и экранирования `[^`; `case "$f" in $p`); `local LC_ALL=C`.
  - DoD: `bash sdx/hooks/test-mandate-lib.sh` — `[P]` и L1–L9 зелёные; `git diff sdx/hooks/lib/mandate.sh` — только добавление.
  - Закрывает: REQ-PKG-11 (е); A2.

- [x] **T07** `[TEST]` `test-mandate-lib.sh`: секция `[L10]` — чистые функции `pr-lib` и портируемость (красная)
  - Зависит от: T06
  - Файлы: `sdx/hooks/test-mandate-lib.sh`
  - Что: таблицы: `pr_valid_id` (валидные: `C-ACME-001`, `ex1`, 64 знака; невалидные: пусто, `client-harness:kitgroup`, `..`, `a..b`, ведущий `-`/`.`, пробел, `/`, 65 знаков, окончание `.`/`.lock`, юникод); `pr_clean` (перевод строки/табуляция → пробел, ESC/C0/DEL/U+2028/2029/0085 вырезаны, trim, усечение); `pr_has_secret` (`password: x`, `"token"=`, `api_key:`, `client-secret :` да; обычный текст, слово `tokenizer` без `:`/`=` нет); `pr_sha256` (известный вектор `abc`); `pr_url_ok` (`ssh://`, `https://`, `http://`, `file://`, `git@host:o/r.git`, абсолютный путь — да; `ext::sh -c x`, `fd::1`, `transport::x`, `-oProxyCommand=x`, пробел, пусто, `ftp://` — нет); `pr_url_show` (`https://u:p@h/x.git` → без `u:p@`; ssh-вид `git@h:o/r` не искажается); `pr_hosting` (`github.com` в URL → `github`; локальный путь → `bare`; подсказка `bare` приоритетнее). `FORBID`-портируемость по `lib/pr-lib.sh` + красная сторона на копии с `mapfile`; `grep -nE 'python|eval' sdx/hooks/lib/pr-lib.sh` пусто.
  - DoD: `bash sdx/hooks/test-mandate-lib.sh` — `[L10]` красный (нет `lib/pr-lib.sh`), прежнее зелёное; перечень приложен.
  - Закрывает: REQ-PKG-5, 10, 14; A8 (тестовая часть).

- [x] **T08** `[CODE]` `lib/pr-lib.sh`: `pr_valid_id`, `pr_clean`, `pr_has_secret`, `pr_sha256` (`# PKG-ID`, `# PKG-SECRET`)
  - Зависит от: T07
  - Файлы: `sdx/hooks/lib/pr-lib.sh` (новый; шапка-комментарий; `source` `miniyaml.sh`, `mandate.sh`, `test-cmd.sh` по `${BASH_SOURCE[0]%/*}`; bash 3.2, без массивов)
  - Что: по DESIGN «`lib/pr-lib.sh`»: `pr_valid_id` (`^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$`, без `..`, не оканчивается `.`/`.lock`); `pr_clean`; `pr_has_secret` (ERE зеркала `REDACT[0]` из `sdx/mo/mesh_endpoint.py:35` — сверить с вендорённым файлом, `grep -Eiq`); `pr_sha256` (`sha256sum` | `shasum -a 256`, нет утилит → rc 2).
  - DoD: `bash sdx/hooks/test-mandate-lib.sh` — строки `[L10]` по этим четырём функциям зелёные.
  - Закрывает: REQ-PKG-5, 10; A8.

- [x] **T09** `[CODE]` `lib/pr-lib.sh`: `pr_url_ok`, `pr_url_show`, `pr_hosting` (`# PKG-URL-WL`)
  - Зависит от: T08
  - Файлы: `sdx/hooks/lib/pr-lib.sh`
  - Что: whitelist схем (`ssh`, `https`, `http`, `file`, scp-вид `user@host:path`, абсолютный локальный путь); отказ на `ext::`/`fd::`/`transport::`, пробелы/управляющие, ведущий `-`; `pr_url_show` вырезает учётные данные; `pr_hosting`: подсказка заказа приоритетнее, иначе `github.com` → `github`, иначе `bare`.
  - DoD: `bash sdx/hooks/test-mandate-lib.sh` — `[L10]` целиком зелёный.
  - Закрывает: REQ-PKG-14, 15, 16; A8, A9.

- [x] **T10** `[TEST]` `test-mandate-lib.sh`: секция `[L11]` — git-зависимые функции `pr-lib` на мини-репозитории (красная)
  - Зависит от: T09
  - Файлы: `sdx/hooks/test-mandate-lib.sh`
  - Что: встроенный мини-репозиторий (`dev`; `sdx/s1` с каталогом сессии → код → `git rm -r` сессии; `order.yaml` в формате «Схема данных» DESIGN, `.mesh/*.yaml`). Проверки: `pr_session_rev` (HEAD с каталогом; HEAD без — родитель коммита `git rm`; нет — rc 1); `pr_sess_cat` (файл есть/нет); `pr_order_load` (все `PR_O_*`; пусто без снимка); `pr_base_ref` (локальная предпочтительнее remote-tracking; нет ни одной → rc 1; дрейф сообщается); `pr_files` (`-z`, путь с кириллицей без quotepath; путь с `\n` → rc 1); `pr_scope_eval` (`PR_OUT`, `PR_SHARED`, `PR_DOCSF`, `PR_SESSF`, `PR_DOCS_OUTSIDE`; пустой `paths` — без `PR_OUT`); `pr_registry` (`docs/DECISIONS.md` изменён → `one` + якорь `ADR-099`; не изменён → `none`; два кандидата по маске → `ambiguous`); `pr_resolve` (порядок источников: снимок заказа > аргумент; расхождение аргумента с непустым снимком → rc 1 `PR_ERR`; `<exec>` только из `mandate.executor`; `docs_in_repo` не задан → `final`).
  - DoD: `bash sdx/hooks/test-mandate-lib.sh` — `[L11]` красный (функций нет); `[L10]`, L1–L9 зелёные; перечень приложен.
  - Закрывает: REQ-PKG-4, 5, 7, 12, 26, 27; A3, A5, A11 (тестовая часть).

- [x] **T11** `[CODE]` `lib/pr-lib.sh`: `pr_session_rev`, `pr_sess_cat`, `pr_order_load` (`# PKG-SESSREV`)
  - Зависит от: T10
  - Файлы: `sdx/hooks/lib/pr-lib.sh`
  - Что: D-5 DESIGN: коммит, где ещё лежит `.claude/sessions/<sid>/` (HEAD либо родитель коммита, удалившего `session_state.json` на ветке `sdx/<sid>`; `git log --diff-filter=D`); `git show "$rev:path"`; `pr_order_load` — `my_load` снимка.
  - DoD: `bash sdx/hooks/test-mandate-lib.sh` — строки `[L11]` по этим трём функциям зелёные.
  - Закрывает: REQ-PKG-4; A3.

- [x] **T12** `[CODE]` `lib/pr-lib.sh`: `pr_base_ref`, `pr_files`, `pr_scope_eval`
  - Зависит от: T11
  - Файлы: `sdx/hooks/lib/pr-lib.sh`
  - Что: `refs/heads/<name>` > `refs/remotes/<remote>/<name>`, имя — `repo.base` заказа, иначе `lib/default-branch.sh`, без `fetch`; `git -c core.quotepath=off diff --name-only -z`; путь с управляющим символом → rc 1; `pr_scope_eval` через `mandate_in_union`/`mandate_glob_any`.
  - DoD: `bash sdx/hooks/test-mandate-lib.sh` — строки `[L11]` по этим функциям зелёные.
  - Закрывает: REQ-PKG-5, 9, 11 (в), 12, 27; A5.

- [x] **T13** `[CODE]` `lib/pr-lib.sh`: `pr_registry`
  - Зависит от: T12
  - Файлы: `sdx/hooks/lib/pr-lib.sh`
  - Что: кандидаты — изменённые файлы диффа `base..head`; `docs/DECISIONS.md` приоритетен, затем единственное совпадение маски `docs/**/{DECISIONS,decisions}*.md`; `PR_REG_PATH`, `PR_REG_STATE` (`one|none|ambiguous`), якоря `git diff -U0 base head -- <reg> | grep '^+#'` → первый токен `[A-Z]+-[0-9]+`.
  - DoD: `bash sdx/hooks/test-mandate-lib.sh` — строки `[L11]` по `pr_registry` зелёные.
  - Закрывает: REQ-PKG-9 (adr), 26; A11.

- [x] **T14** `[CODE]` `lib/pr-lib.sh`: `pr_resolve`
  - Зависит от: T13
  - Файлы: `sdx/hooks/lib/pr-lib.sh`
  - Что: итоговые `PR_C`, `PR_EXEC`, `PR_BRANCH`, `PR_TITLE`, `PR_BASE_NAME/REF/SHA`, `PR_URL`, `PR_HOSTING_HINT`, `PR_DELIVERY`, `PR_DOCS_MODE`, `PR_DIGEST`; rc 0|1 с `PR_ERR` «<поле>: <причина>»; молчаливой подмены нет.
  - DoD: `bash sdx/hooks/test-mandate-lib.sh` — `[L11]` целиком зелёный; `grep -nE 'python|eval' sdx/hooks/lib/pr-lib.sh` пусто.
  - Закрывает: REQ-PKG-4, 5, 7; A3.

- [x] **T15** `[TEST]` [PROC-020] `test-mandate-lib.sh`: мутанты `PKG-FNMATCH`, `PKG-ID`, `PKG-SECRET`, `PKG-URL-WL`, `PKG-SESSREV`
  - Зависит от: T14
  - Файлы: `sdx/hooks/test-mandate-lib.sh`
  - Что: мутанты по меткам: `PKG-FNMATCH` (подмена на `glob_one` → краснит «`change` ↔ `change/x`»), `PKG-ID` (снять запрет `..`/`:`), `PKG-SECRET` (пустой шаблон), `PKG-URL-WL` (принимать `ext::`), `PKG-SESSREV` (вернуть всегда `HEAD`).
  - DoD: `bash sdx/hooks/test-mandate-lib.sh` → `Results: N passed, 0 failed`, 5 строк «мутант … → красный (ожидаемо)»; прирост времени сьюта ≤ 3 с; `git status --porcelain` пуст.
  - Закрывает: REQ-PKG-5, 10, 14, 4; A8, A3.

#### Ф-2. `lib/pkg-fixture.sh` и оракул `audit()` (DESIGN T2)

- [x] **T16** `[TEST]` `test-pkg-fixture.sh` — самопроверка помощника и оракула (красная)
  - Зависит от: T15
  - Файлы: `sdx/hooks/test-pkg-fixture.sh` (новый; шапка-комментарий как у других сьютов)
  - Что: каркас; (а) `pkg_fixture_template` создаёт bare `remote.git` (`dev`), клон `wc`, `sdx/s1` с историей «сессия → код → `git rm -r` сессии», `.mesh/endpoint.yaml` + `.mesh/mandate.yaml` (форма дампа узла, `executor: ex1`, `digest: "123456789012"`, `valid_until: "2099-01-01"`, `delivery: pr`, `docs_in_repo: final`, `scope.paths [src/mod1/**]`, `shared_paths [package-lock.json]`, `docs_paths [docs/**]`, `branches [change/*]`), `.claude/sdx/verify-cmd.sh` (управляемый `exit 0|1`); (б) `pkg_fixture_copy` быстрый и независимый (изменение копии не видно шаблону); (в) оракул `pkg_oracle` (python `audit()`): на пакете `pkg_craft_good` → `approve`; на каждой фабрике `pkg_craft_bad_<вид>` → не `approve` с ожидаемым id провала; (г) встроенный негатив: подмена вердикта оракула краснит сверку; (д) INFO-skip без python3/PyYAML; (е) `FORBID`-портируемость `lib/pkg-fixture.sh`.
  - DoD: `bash sdx/hooks/test-pkg-fixture.sh; echo $?` != 0 (нет помощника); `bash -n`; перечень красных строк приложен.
  - Закрывает: REQ-PKG-11; A1, A2 (тестовая часть).

- [x] **T17** `[CODE]` `lib/pkg-fixture.sh`: `pkg_fixture_template`, `pkg_fixture_copy`
  - Зависит от: T16
  - Файлы: `sdx/hooks/lib/pkg-fixture.sh` (новый; `source`-файл, имя не `test-*.sh`)
  - Что: шаблон один раз за прогон (`PKG_FIXTURE_TEMPLATE` от родителя наследуется вложенными прогонами мутантов); `cp -a` копий; содержимое по DESIGN «`lib/pkg-fixture.sh`» (`src/mod1/a.js`, `src/core/b.js`, `package-lock.json`, `docs/DECISIONS.md` с ADR-099 в диффе, `docs/specs/mod1.md`; `order.yaml`, `decisions_log.md`, `verification_report.md` с `Итог: PASS`, `change_note.md` в каталоге сессии).
  - DoD: `bash sdx/hooks/test-pkg-fixture.sh` — блоки (а), (б) зелёные; создание шаблона ≤ 1 с.
  - Закрывает: инфраструктура A1–A5.

- [x] **T18** `[CODE]` `lib/pkg-fixture.sh`: python-оракул `pkg_oracle` (транслитерация `audit()`)
  - Зависит от: T17
  - Файлы: `sdx/hooks/lib/pkg-fixture.sh`
  - Что: один вызов `python3 -I` (heredoc) на пакет; транслитерация формальных проверок `SK/core/dev.py:340–424` (`manifest_of`, `format`, `manifest.commit` (`tip^ == head`, разница — ровно `CHANGE.yaml`), `branch` по `fnmatch`, `scope` по `glob_any` (`DEV:67–68`), `shared.declared`, `archive_sha256`, `adr`); реестр обязательств, тесты и ревью не воспроизводятся; вывод `approve` или `<verdict> <ids>`; нет python3/PyYAML → INFO-skip (rc 77).
  - DoD: `bash sdx/hooks/test-pkg-fixture.sh` — блок (в) для `pkg_craft_good` → `approve` (после T19), блоки (г), (д) зелёные; `ls -a` чекаута без `__pycache__`.
  - Закрывает: REQ-PKG-11, 35 (живой `audit()` не вызывается); A1.

- [x] **T19** `[CODE]` `lib/pkg-fixture.sh`: `pkg_craft_good` и фабрики красных пакетов, часть 1
  - Зависит от: T18
  - Файлы: `sdx/hooks/lib/pkg-fixture.sh`
  - Что: фабрики обходным plumbing'ом по образцу `mkpkg` (`SK/tests/kit.sh:695–742`), независимо от `pr-build.sh`: `pkg_craft_good`; красные: лишний коммит между `head` и вершиной (`manifest.commit`), посторонний файл в манифест-коммите, неверный `archive_sha256`, файл вне области (`scope`).
  - DoD: `bash sdx/hooks/test-pkg-fixture.sh` — good → `approve`, четыре красные → не `approve` с ожидаемыми id.
  - Закрывает: REQ-PKG-11; A1, A2.

- [x] **T20** `[CODE]` `lib/pkg-fixture.sh`: фабрики красных пакетов, часть 2
  - Зависит от: T19
  - Файлы: `sdx/hooks/lib/pkg-fixture.sh`
  - Что: `touches_shared` не объявлен при пересечении, каталог сессии в пакете, `format: 2`, манифест внутри головы (без `archive_sha256` вершины), фальшивый `scope_touched`, секрет в `notes`, чужие `commitment`/`executor`/`mandate_digest`.
  - DoD: `bash sdx/hooks/test-pkg-fixture.sh` → `Results: N passed, 0 failed` (при PyYAML — все оракульные ветки PASS; иначе INFO-skip и это записано); время сьюта ≤ 3 с.
  - Закрывает: REQ-PKG-11, 12; A1, A2, A5.

- [x] **T21** `[INFRA]` Gate Ф: полный прогон перед стартом дорожек A/B/C
  - Зависит от: T20, T03
  - Файлы: —
  - Что: `time bash .claude/sdx/verify-cmd.sh`; проверка, что `git diff --stat main -- sdx/hooks/stop-gate.sh sdx/hooks/archive-verify.sh sdx/hooks/sdx-stage.sh sdx/hooks/mo-hook.sh sdx/hooks/mo-session.sh sdx/hooks/lib/miniyaml.sh sdx/hooks/lib/test-cmd.sh hooks/hooks.json` пуст; зафиксировать замер времени (база для К-10).
  - DoD: exit 0, все сьюты `0 failed`; время и число сьютов записаны в сообщении коммита (исходный ориентир: 123,9 с под нагрузкой / 19 сьютов в feat-016); `find . -name __pycache__ -not -path './.git/*'` пусто.
  - Закрывает: A14, A16 (база замера).

### Дорожка A — приём заказа и экспорт протокола (после T21; независима от B, C)

#### A-1. `order-import.sh` (DESIGN T3)

- [ ] **T22** `[TEST]` `test-order-import.sh`: каркас, O1 (golden файла), O2 (паритет и отказы), красные
  - Зависит от: T21
  - Файлы: `sdx/hooks/test-order-import.sh` (новый)
  - Что: каркас (`ORDER_IMPORT_ONLY`, фикстура из `pkg-fixture.sh`); O1 — статический golden: заказ в виде `yaml.safe_dump`-текста с переносами (одинарные кавычки, продолжение строк, список с переносом) → `commitment`, `title`, `requirements`, `repo.base/url`, `deliver.branch` совпадают с ожидаемыми; O2 — паритет `order-unfold`+`miniyaml` с `yaml.safe_load` на ~25 сгенерированных дампах (python/PyYAML, INFO-skip); отказы с причиной: двойные кавычки с переносом, блочный скаляр `|`/`>`, пустая строка внутри значения, якорь, список словарей, flow-словарь, файл > 64 КиБ.
  - DoD: `bash sdx/hooks/test-order-import.sh; echo $?` != 0 (нет скрипта); `bash -n`; перечень красных строк приложен.
  - Закрывает: REQ-PKG-23; A10 (тестовая часть).

- [ ] **T23** `[CODE]` `order-import.sh`: каркас, `order-unfold` (awk), `from-file` (`# PKG-O-UNFOLD`)
  - Зависит от: T22
  - Файлы: `sdx/hooks/order-import.sh` (новый)
  - Что: диспетчер подкоманд; `from-file`: первый непробельный символ `{` → JSON (`jq`), иначе `LC_ALL=C tr -d '\r'` → `order-unfold` → `my_load`; `order-unfold` по DESIGN (склейка продолжений с отступом больше ключа одним пробелом; маркер `#UNFOLD-ERR` для двойной кавычки с переносом и пустой строки внутри значения); граница названа в комментарии скрипта; лимит 64 КиБ.
  - DoD: `bash sdx/hooks/test-order-import.sh` — O1, O2 зелёные (оракульная часть PASS либо INFO-skip).
  - Закрывает: REQ-PKG-23; A10.

- [ ] **T24** `[CODE]` `order-import.sh`: нормализация, проверки идентификаторов, flat-JSON (`# PKG-O-ID`)
  - Зависит от: T23
  - Файлы: `sdx/hooks/order-import.sh`
  - Что: порядок проверок DESIGN: `action == work.order`, `format == 1`; `pr_valid_id` на `commitment.id`/`executor` (поле называется); `pr_clean` на `title`/`requirements` (≤4000); `due`; `repo.base` через `check-ref-format --branch`; `repo.url` через `pr_url_ok`; `pr_has_secret` на `title`/`requirements`; вывод flat-JSON (`jq`); `sid_infix` (≤40 знаков); коды 0/1/2.
  - DoD: `bash sdx/hooks/test-order-import.sh` — O1, O2 зелёные; ручная проверка: заказ с `C` = `a/b` → rc 1, имя поля в stderr.
  - Закрывает: REQ-PKG-10, 23, 25; A10.

- [ ] **T25** `[TEST]` `test-order-import.sh`: O3 (конверт, `list`), O4 (issue), O6 (враждебные значения) — красные
  - Зависит от: T24
  - Файлы: `sdx/hooks/test-order-import.sh`
  - Что: O3 — `--inbox-json` со строками конвертов (`directive`/`work.order`, посторонний `kind`, два заказа) → выбор по `msg_id`; `list`; неизвестный `msg_id` и `msg_id` вне `^[A-Za-z0-9._:-]{1,80}$` → rc 1; O4 — `gh`-стаб (в `PATH`) отдаёт `{"body": …}` с несколькими fenced-блоками (первый — не заказ) → берётся первый yaml-блок с `action: work.order`; без `gh` → rc 1 с подсказкой `--from-order <файл>`; O6 — `C` с `/`, `..`, пробелом; `title` с переводом строки, `` ` ``, `$(…)`, ESC, 5000 знаков; `repo.url` с `ext::`; секрет в `requirements` → rc 1 либо сведено без побочных эффектов (файл-маркер не создан).
  - DoD: `bash sdx/hooks/test-order-import.sh` — O1, O2 зелёные, O3, O4, O6 красные (перечень приложен).
  - Закрывает: REQ-PKG-10, 23, 24; A10.

- [ ] **T26** `[CODE]` `order-import.sh`: `from-msg`, `list`
  - Зависит от: T25
  - Файлы: `sdx/hooks/order-import.sh`
  - Что: `jq -c 'select(.kind=="directive" and .body.action=="work.order" and .msg_id==$id) | .body'`; без `--inbox-json` — `PYTHONDONTWRITEBYTECODE=1 MESH_ENDPOINT_DIR="$proj" python3 "$here/../mo/mesh_endpoint.py" pull` затем `inbox --json` (нет python3/PyYAML — отказ с подсказкой `--inbox-json`/`from-file`); `list` — `msg_id / C / название`; угадывания «последнего» нет.
  - DoD: `bash sdx/hooks/test-order-import.sh` — O3 зелёный, O6 — часть про конверт зелёная.
  - Закрывает: REQ-PKG-23; A10.

- [ ] **T27** `[CODE]` `order-import.sh`: `from-issue` (`# PKG-O-FENCE`)
  - Зависит от: T26
  - Файлы: `sdx/hooks/order-import.sh`
  - Что: `gh issue view <N> [--repo] --json body`; нет `gh` → rc 1 с подсказкой; первый fenced-блок ```` ```yaml ````/`yml` с `action: work.order` на нулевом отступе (≤64 КиБ), далее как YAML-файл; формат обёртки — допущение SDX (Q-10), пометить в шапке.
  - DoD: `bash sdx/hooks/test-order-import.sh` — O4, O6 целиком зелёные.
  - Закрывает: REQ-PKG-24; A10.

- [ ] **T28** `[TEST]` `test-order-import.sh` O5, O7 и `test-sdx-stage.sh [42]` — красные
  - Зависит от: T27
  - Файлы: `sdx/hooks/test-order-import.sh`, `sdx/hooks/test-sdx-stage.sh` (только добавление секции `[42]`; `[1]–[41]`/`[M30]–[M41]` не правятся)
  - Что: O5 — `mandate_digest`/`executor`/`deliver.branch` не совпали с локальным мандатом → rc 3, **все** `MISMATCH`-строки сразу, значения через `pr_clean`; O7 — `--out` пишет `order.yaml` в нашем формате, `pr_order_load` читает те же значения (круговая сверка с `lib/pr-lib.sh`), `stamp-state` добавляет `commitment`, не трогает остальные ключи, идемпотентен, отказывает на другом значении и невалидном `C`; `[42]` — характеризационный: поле `commitment` переживает `next` и `next --to`, `init` пишет прежние семь ключей без него (проходит и без нового кода; красная сторона — мутант `write_stage`, теряющий поле, в T31).
  - DoD: `bash sdx/hooks/test-order-import.sh` — O5, O7 красные (перечень приложен); `bash sdx/hooks/test-sdx-stage.sh` — `[42]` зелёный (характеризационный), остальное без изменений.
  - Закрывает: REQ-PKG-23, 25; A10.

- [ ] **T29** `[CODE]` `order-import.sh`: сверка с мандатом и снимок `--out` (`# PKG-O-DIGEST`, `# PKG-O-EXEC`, `# PKG-O-BRANCH`)
  - Зависит от: T28
  - Файлы: `sdx/hooks/order-import.sh`
  - Что: сверка после нормализации (`mandate_load`; rc 3 + строки `MISMATCH <поле> order=<..> local=<..>`); снимок `--out` рендерится `jq` в формате «Схема данных» DESIGN (все скаляры одной строкой в кавычках; `hosting` только если есть в заказе; мандат целиком не копируется).
  - DoD: `bash sdx/hooks/test-order-import.sh` — O5 зелёный; O7 — части про снимок зелёные.
  - Закрывает: REQ-PKG-23, 25; A10.

- [ ] **T30** `[CODE]` `order-import.sh`: `stamp-state` (`# PKG-O-STAMP`)
  - Зависит от: T29
  - Файлы: `sdx/hooks/order-import.sh`
  - Что: `jq --arg c "$C" '. + {commitment:$c}'` во временный файл рядом + `mv` (как `write_stage`); отказ, если состояния нет, `C` невалиден или поле уже стоит с другим значением; идемпотентен.
  - DoD: `bash sdx/hooks/test-order-import.sh` целиком зелёный; `bash sdx/hooks/test-sdx-stage.sh` зелёный; `git diff --stat main -- sdx/hooks/sdx-stage.sh` пуст.
  - Закрывает: REQ-PKG-25; A10.

- [ ] **T31** `[TEST]` `test-order-import.sh`: мутанты `PKG-O-*`; мутант для `[42]`
  - Зависит от: T30
  - Файлы: `sdx/hooks/test-order-import.sh`, `sdx/hooks/test-sdx-stage.sh`
  - Что: мутанты: `PKG-O-UNFOLD` (без склейки → O1), `PKG-O-FENCE` (берёт первый fenced-блок любого типа → O4), `PKG-O-DIGEST`/`PKG-O-EXEC`/`PKG-O-BRANCH` (сверка не срабатывает → O5), `PKG-O-ID` (без `pr_valid_id` → O6), `PKG-O-STAMP` (перезапись чужого значения → O7); в `test-sdx-stage.sh` `[42]` — мутант копии `sdx-stage.sh`, у которой `write_stage` теряет `commitment` (`jq` оставляет только `.stage`), краснит `[42]` (мутант не меняет чекаут).
  - DoD: `bash sdx/hooks/test-order-import.sh` → `Results: N passed, 0 failed`, 6 строк «мутант … → красный»; время сьюта ≤ 5 с; `bash sdx/hooks/test-sdx-stage.sh` — 1 новый мутант красный (ожидаемо), прирост ≤ 1 с; `git status --porcelain` пуст.
  - Закрывает: REQ-PKG-23–25; A10.

#### A-2. `protocol-export.sh` (DESIGN T4)

- [ ] **T32** `[TEST]` `test-protocol-export.sh`: X1–X4, X6 — красные
  - Зависит от: T21
  - Файлы: `sdx/hooks/test-protocol-export.sh` (новый)
  - Что: каркас (`PROTOCOL_EXPORT_ONLY`); оракул схемы — `python3 -I` + `yaml.safe_load` с логикой `protocol_check()` (`DEV:577–593`: пять ключей-списков, `decisions[i].{id,what,why}` непусты; INFO-skip без PyYAML, проверки через `jq` на JSON-форме остаются); X1 — формат A (`### Развилка`, `Вариант`/`Обоснование`, многострочное продолжение, `Варианты`) → `decisions`, `alternatives`, `tag`, `stage`; встроенный негатив: оракул на файле без одного раздела краснеет; X2 — **буквальная golden-копия `decisions_log.md` этой сессии** (вставляется в сьют как heredoc; формат B `- <дата> [тег] текст`) → `what`/`why` непусты, тег, `D-1…`; X3 — смесь A+B, порядок сохранён; X4 — нет файлов / пустой каталог / пустой `decisions_log.md` → пять пустых списков, rc 0; нет каталога и нет источников → rc 1; X6 — `id` `D-1…D-n`, уникальны.
  - DoD: `bash sdx/hooks/test-protocol-export.sh; echo $?` != 0 (нет скрипта); перечень красных строк приложен.
  - Закрывает: REQ-PKG-19, 20, 21; A6 (тестовая часть).

- [ ] **T33** `[CODE]` `protocol-export.sh`: разбор `decisions_log.md` (awk → TSV, форматы A и B; `# PKG-X-FMTB`, `# PKG-X-ADR`)
  - Зависит от: T32
  - Файлы: `sdx/hooks/protocol-export.sh` (новый)
  - Что: awk-ядро из DESIGN (блок `### Развилка:` и строка `- <дата> [тег] текст`; формат B: `what` — первое предложение ≤200 знаков, `why` — вся запись); `adr` = запись содержит `ADR-[0-9]+`; запись без `what` и `why` пропускается со строкой в stderr; аргументы `--sid`, `--proj`.
  - DoD: `bash sdx/hooks/test-protocol-export.sh` — X1–X3 (по частям `decisions`) зелёные.
  - Закрывает: REQ-PKG-20; A6, A7.

- [ ] **T34** `[CODE]` `protocol-export.sh`: рендер `jq`, скелет из пяти списков, `rc` (`# PKG-X-ID`, `# PKG-X-EMPTY`)
  - Зависит от: T33
  - Файлы: `sdx/hooks/protocol-export.sh`
  - Что: рендер одним `jq` (`tojson`; `D-<n>` по порядку; `questions[]` = `"[<тег>] <название>"`); пустые источники → `done: []` и т. д., все пять ключей присутствуют всегда; rc 1 только если нет ни одного читаемого источника и каталога сессии; запись в `.claude/sessions/<sid>/protocol.yaml` (по умолчанию) либо `--out`.
  - DoD: `bash sdx/hooks/test-protocol-export.sh` — X1–X4, X6 зелёные (оракул схемы PASS либо INFO-skip).
  - Закрывает: REQ-PKG-19, 20, 21; A6.

- [ ] **T35** `[TEST]` `test-protocol-export.sh`: X5, X7, X8, X9 — красные
  - Зависит от: T34
  - Файлы: `sdx/hooks/test-protocol-export.sh`
  - Что: X5 — запись с `ADR-021` → `adr: true`, без → `false`; X7 — враждебные значения (`"`, `\`, `---`, `: `, табуляция, 5000 знаков, U+2028) → roundtrip через `safe_load`; X8 — `verified` (строки `- …` раздела `## Сводка`, `Матрица: OK a, WARN b, FAIL c` по последнему столбцу таблицы, `Итог по области: …` из блока `SDX-MANDATE-SCOPE`), `deltas` (`"[ADDED|MODIFIED|REMOVED] REQ-…"` из `SPEC.md`, иначе `change_note.md`; дубликаты убраны), `done` (`PLAN.md` сессии, иначе `docs/history/plans/<sid>.md`, иначе `change_note.md`) ; X9 — `--from-rev <родитель коммита шага 5>` даёт тот же файл, что запуск до шага 5.
  - DoD: `bash sdx/hooks/test-protocol-export.sh` — X8, X9 красные, X5/X7 — по состоянию кода (перечень приложен).
  - Закрывает: REQ-PKG-19–21; A6, A7.

- [ ] **T36** `[CODE]` `protocol-export.sh`: `verified`, `deltas`, `done`
  - Зависит от: T35
  - Файлы: `sdx/hooks/protocol-export.sh`
  - Что: извлечение по таблице источников DESIGN («Источники и правила»); число кругов не экспортируется (К-5); `done` ≤120 знаков на запись, для свёрнутой дельты — одна запись `change_note.md: <первый заголовок или строка>`.
  - DoD: `bash sdx/hooks/test-protocol-export.sh` — X8 зелёный.
  - Закрывает: REQ-PKG-21; A6.

- [ ] **T37** `[CODE]` `protocol-export.sh`: `--from-rev`, `--out`, сводка stderr (`# PKG-X-REV`)
  - Зависит от: T36
  - Файлы: `sdx/hooks/protocol-export.sh`
  - Что: `--from-rev REV` читает `git show REV:.claude/sessions/<sid>/…`, вывод в stdout; сводка `protocol: done N decisions M (adr K) questions Q verified V deltas D`; коды 0/1/2.
  - DoD: `bash sdx/hooks/test-protocol-export.sh` целиком зелёный; `grep -nE 'python|eval' sdx/hooks/protocol-export.sh` пусто.
  - Закрывает: REQ-PKG-4, 19; A6.

- [ ] **T38** `[TEST]` `test-protocol-export.sh`: мутанты `PKG-X-FMTB`, `PKG-X-EMPTY`, `PKG-X-ADR`, `PKG-X-ID`, `PKG-X-REV`; портируемость
  - Зависит от: T37
  - Файлы: `sdx/hooks/test-protocol-export.sh`
  - Что: `PKG-X-FMTB` (не читает формат B → X2), `PKG-X-EMPTY` (опускает пустой раздел → X4), `PKG-X-ADR` (всегда `false` → X5), `PKG-X-ID` (дубликат id → X6), `PKG-X-REV` (читает рабочее дерево вместо `REV` → X9); `FORBID`.
  - DoD: `bash sdx/hooks/test-protocol-export.sh` → `Results: N passed, 0 failed`, 5 строк «мутант … → красный»; время сьюта ≤ 4 с.
  - Закрывает: REQ-PKG-19–22; A6, A7.

### Дорожка B — сборка, проверка и публикация пакета (после T21; независима от A, C)

#### B-1. `pr-build.sh` (DESIGN T5)

- [ ] **T39** `[TEST]` `test-pr-build.sh`: B7 (отказы), B9 (расходящийся `base`), B8a (повторная сдача до манифеста) — красные
  - Зависит от: T21
  - Файлы: `sdx/hooks/test-pr-build.sh` (новый)
  - Что: каркас (`PR_BUILD_ONLY`, `pkg_fixture_copy`); B7: `executor` с `:` (`pr-build: executor: …`), `C` с `..`/ведущим `-`/пробелом/65 знаками, секрет в заголовке, путь с управляющим символом, `CHANGE.yaml` в коде, пустой дифф, каталог сессии в дереве `sdx/<sid>`, нет мандата, мандат без `endpoint.yaml`, не та ветка, нет `user.name/email` → rc 2; B9: `dev` ушёл вперёд после выреза — rc 3 `NEED allow-diverged`; с флагом дифф `base..head` только изменения сессии; конфликт слияния → rc 1; B8a: существующая `change/*` без флага → rc 3 `NEED resubmit`; с флагом `parent` нового `head` = прежняя вершина; не-пакетная `change/*` (нет `CHANGE.yaml`) → rc 1.
  - DoD: `bash sdx/hooks/test-pr-build.sh; echo $?` != 0 (нет скрипта); перечень красных строк приложен.
  - Закрывает: REQ-PKG-5, 6, 7, 10, 18; A3, A8 (тестовая часть).

- [ ] **T40** `[CODE]` `pr-build.sh`, часть 1: аргументы, отказы, дерево, родитель, `head` (`# PKG-ANCESTOR`, `# PKG-CAS`, `# PKG-NOCHANGEYAML`)
  - Зависит от: T39
  - Файлы: `sdx/hooks/pr-build.sh` (новый; `set -uo pipefail`, bash 3.2, `die rc msg`)
  - Что: по DESIGN «`pr-build.sh`», алгоритм до `head`: режим мандата, `pr_resolve`, `refs/heads/sdx/$sid`, текущая ветка = `sdx/<sid>`, дерево (предок `base` → дерево вершины; иначе `--allow-diverged` + `git merge-tree --write-tree`), родитель (`base` либо прежняя вершина с `--resubmit` и проверкой `CHANGE.yaml` на ней), отказы «каталог сессии в дереве», `check-ref-format`, `pr_has_secret` на заголовке/путях, `CHANGE.yaml` в дереве; `head=$(… | git commit-tree "$tree" -p "$parent")`; ничего не пишет в рабочее дерево.
  - DoD: `PR_BUILD_ONLY="B7 B9 B8a" bash sdx/hooks/test-pr-build.sh` зелёный; `grep -nE 'python|eval|checkout|worktree' sdx/hooks/pr-build.sh` пусто.
  - Закрывает: REQ-PKG-5, 6, 7, 10, 18; A3.

- [ ] **T41** `[TEST]` `test-pr-build.sh`: B1–B5, B11 — красные
  - Зависит от: T40
  - Файлы: `sdx/hooks/test-pr-build.sh`
  - Что: B1 — золотой путь: rc 0, JSON, `tip^ == head`, родитель `head` = `base`, `base..head` — ровно один коммит с темой `C: заголовок`, python-оракул `pkg_oracle` → `approve`; встроенный негатив: оракул на повреждённом пакете ≠ `approve`; B2 — plumbing: до/после совпадают `HEAD`, имя ветки, `git status --porcelain`, `git ls-files -s`; `CHANGE.yaml` на диске нет (`find`); дерево `tip` = дерево `head` + один блоб; B3 — `archive_sha256` = пересчёт в независимом клоне (`git clone` + `git archive`) и в фикстуре; B4 — `scope_touched` включает `package-lock.json`, `touches_shared` оба исхода; B5 — `adr` (реестр менялся → `["docs/DECISIONS.md#ADR-099"]`; не менялся → `[]` + `notes`; `docs_in_repo: none` → `[]`), `spec` есть/нет (ключ опущен), `verify.tests` `pass`/`unknown`; B11 — в `git ls-tree -r tip` нет `.claude/sessions/` и `protocol.yaml`.
  - DoD: `bash sdx/hooks/test-pr-build.sh` — B7, B9, B8a зелёные, B1–B5, B11 красные (перечень приложен).
  - Закрывает: REQ-PKG-6, 8, 9, 12, 19; A1, A3, A4, A5, A7, A11.

- [ ] **T42** `[CODE]` `pr-build.sh`, часть 2: значения манифеста (`# PKG-SCOPE-TOUCHED`, `# PKG-SHARED`, `# PKG-ARCHIVE`, `# PKG-EMPTY`)
  - Зависит от: T41
  - Файлы: `sdx/hooks/pr-build.sh`
  - Что: `mbase=merge-base(head, base)`; `PR_FILES` (включая сгенерированное); пустой дифф → отказ; `pr_scope_eval` → `touches_shared`; `asha = git -c tar.umask=0002 archive --format=tar "$head" | pr_sha256` (от `head`, не от `tip`); `spec` (позднее всего менявшийся `docs/specs/*.md@<sha>`; нет — ключ опускается); `verify.tests` (`Итог: PASS` в `verification_report.md` на `PR_SESS_REV` → `pass`, иначе `unknown`), `verify.report`; `adr` через `pr_registry` (при `docs_in_repo: none` → `[]`); `docs` = `PR_DOCSF`; `history_ref: executor:sdx/<sid>`; `notes` (`--notes` либо `SDX <версия плагина>: сессия <sid>` + пометки реестра); значения собираются в JSON `$vals` (`jq -n`).
  - DoD: `PR_BUILD_ONLY="B7 B9 B8a" bash sdx/hooks/test-pr-build.sh` по-прежнему зелёный; ручной прогон на копии фикстуры печатает в stderr строки `pr-build: base=… head=… files=N shared=bool` (отладочный вывод остаётся, это часть stderr-контракта «человекочитаемые строки»).
  - Закрывает: REQ-PKG-9, 12, 26; A4, A5, A7, A11.

- [ ] **T43** `[TEST]` `test-pr-build.sh`: B6 (экранирование), B10 (шаблон), B12 (`tip`-родитель) — красные
  - Зависит от: T42
  - Файлы: `sdx/hooks/test-pr-build.sh`
  - Что: B6 — заголовок с `"`, `\`, `: `, `#`, `'`, `{}`, ` - `, юникодом, переводом строки (сведён к пробелу); манифест разобран `miniyaml` и `yaml.safe_load` (оракул) с одинаковыми значениями; `mandate_digest` из цифр остаётся строкой; B10 — ключи и порядок манифеста = ключам шаблона `sdx/mo/CHANGE.template.yaml`; копия шаблона с лишним ключом → rc 1 «обновите плагин»; копия без ключа `adr` → манифест без `adr`; B12 — родитель вершины = `head` (не `base`); манифест-коммит меняет ровно один файл.
  - DoD: `bash sdx/hooks/test-pr-build.sh` — B6, B10, B12 красные (вместе с B1–B5, B11); перечень приложен.
  - Закрывает: REQ-PKG-8, 9, 10; A1, A3.

- [ ] **T44** `[CODE]` `pr-build.sh`, часть 3: обход шаблона и рендер `jq` (`# PKG-TEMPLATE-KEYS`, `# PKG-QUOTE`)
  - Зависит от: T43
  - Файлы: `sdx/hooks/pr-build.sh`
  - Что: ключи шаблона (`$here/../mo/CHANGE.template.yaml`) в порядке файла; неизвестный ключ → rc 1 «шаблон sim-kit содержит поле '<k>', неизвестное pr-build — обновите плагин»; `RENDER_CHANGE` — jq-программа DESIGN (`sc`: `tojson`, U+2028/2029/0085 → пробел, `null` → `""`; `lst`; `emit`; `verify` вложенным отображением); все строки в кавычках; необязательные ключи (`module`, `contracts_changed`, `migrations`, `layer`) не заполняются.
  - DoD: `PR_BUILD_ONLY="B6 B10 B7 B9 B8a" bash sdx/hooks/test-pr-build.sh` зелёный (оракул `safe_load` PASS или INFO-skip).
  - Закрывает: REQ-PKG-8, 9, 10; A1.

- [ ] **T45** `[CODE]` `pr-build.sh`, часть 4: коммит манифеста plumbing'ом, `update-ref` CAS, JSON-выход (`# PKG-PLUMB`, `# PKG-TIPPARENT`)
  - Зависит от: T44
  - Файлы: `sdx/hooks/pr-build.sh`
  - Что: `git hash-object -w --stdin` → временный индекс (`GIT_INDEX_FILE`, `trap rm`) → `read-tree head` → `update-index --add --cacheinfo 100644,<blob>,CHANGE.yaml` → `write-tree` → `commit-tree -p "$head"` (тема `SDX: CHANGE.yaml (<C>)`) → `update-ref refs/heads/$PR_BRANCH "$tip" "$zero"` (создание — нули; повтор — прежняя вершина); JSON-выход по «JSON-выходы» DESIGN; `warnings[]`.
  - DoD: `bash sdx/hooks/test-pr-build.sh` целиком зелёный (B1–B12; оракул `approve` при PyYAML); время сьюта ≤ 6 с без мутантов.
  - Закрывает: REQ-PKG-8, 9, 18; A1, A3, A4, A5.

- [ ] **T46** `[TEST]` `test-pr-build.sh`: мутанты `PKG-*` (11)
  - Зависит от: T45
  - Файлы: `sdx/hooks/test-pr-build.sh`
  - Что: `PKG-PLUMB` (запись `CHANGE.yaml` в рабочее дерево → B2), `PKG-ARCHIVE` (хеш от `tip` → B3), `PKG-SCOPE-TOUCHED` (без сгенерированных → B4), `PKG-SHARED` (всегда `false` → B4), `PKG-QUOTE` (рендер без `tojson` → B6), `PKG-NOCHANGEYAML` (нет отказа → B7), `PKG-EMPTY` (пустой дифф допускается → B7), `PKG-CAS` (нулевое «старое значение» заменено на пустое → B8), `PKG-ANCESTOR` (без ветви расхождения → B9), `PKG-TEMPLATE-KEYS` (неизвестные ключи молча пропускаются → B10), `PKG-TIPPARENT` (`-p base` → B12).
  - DoD: `bash sdx/hooks/test-pr-build.sh` → `Results: N passed, 0 failed`, 11 строк «мутант … → красный»; время сьюта ≤ 10 с (цель DESIGN ≈ 8); `git status --porcelain` пуст.
  - Закрывает: REQ-PKG-8, 9, 10, 18; A1, A3–A5.

#### B-2. `pr-check.sh` (DESIGN T6; после T46)

- [ ] **T47** `[TEST]` `test-pr-check.sh`: C1–C3 (фаза `pre`) — красные
  - Зависит от: T46
  - Файлы: `sdx/hooks/test-pr-check.sh` (новый)
  - Что: каркас (`PR_CHECK_ONLY`); C1 — `pre` зелёный: rc 0, `PR-CHECK PASS`, тест-стаб `exit 0`; C2 — rc 1, каждый свой `FAIL <id>`: грязное дерево, каталог сессии в `HEAD`, не та ветка, недопустимый `executor`, имя вне `scope.branches` (`branches: [feat/*]`), истёкший мандат (`SDX_MANDATE_TODAY`), файл вне области, документ вне `docs_paths` при `final`, пустой дифф, красный тест-стаб (`exit 1`, хвост в stderr), `repo.url` вида `ext::…`, нет `digest`; C3 — rc 3, `WARN <id>`: расходящийся `base`, ветка уже есть, реестр ADR не менялся (`final`), реестр вне `docs_paths`, дрейф remote-tracking, `export-ignore` в `info/attributes`, `history: executor` + `docs_in_repo: none`; при `docs_in_repo: none` реестр не проверяется.
  - DoD: `bash sdx/hooks/test-pr-check.sh; echo $?` != 0 (нет скрипта); перечень красных строк приложен.
  - Закрывает: REQ-PKG-11, 12, 26, 27; A2, A11 (тестовая часть).

- [ ] **T48** `[CODE]` `pr-check.sh`, `pre`, часть 1: каркас, closeout/ID/ветка/срок/мандат/`base` (`# PKG-C-TREE`, `# PKG-C-SESSION`, `# PKG-C-BRANCH`, `# PKG-C-EXPIRED`)
  - Зависит от: T47
  - Файлы: `sdx/hooks/pr-check.sh` (новый)
  - Что: формат строк `OK|FAIL|WARN|NOTE <id>: <текст>` и итог `PR-CHECK PASS|WARN n|FAIL n`, rc 0/3/1/2; значения мандата/заказа в выводе через `pr_clean`; проверки: `closeout.branch/tree/session` (прокси `mandate-info.sh closeout-check <sid>`), `id.commitment/executor`, `branch.name` (`check-ref-format`), `branch.scope` (`mandate_fnmatch`, `scope.branches` непуст), `mandate.valid` (`mandate_expired`), `mandate.digest`, `mandate.lint`, `base.ref`, `base.ancestor`, `base.remote-drift`, `branch.exists`.
  - DoD: `PR_CHECK_ONLY=C1 bash sdx/hooks/test-pr-check.sh` и часть C2 (строки tree/session/branch/executor/expired/digest) и C3 (ancestor/exists/drift/lint) зелёные.
  - Закрывает: REQ-PKG-11 (а, г, е, ж), 5; A2.

- [ ] **T49** `[CODE]` `pr-check.sh`, `pre`, часть 2: дифф, `docs.final`, реестр, URL, `attrs`, `shared.note` (`# PKG-C-SCOPE`, `# PKG-C-DOCS-FINAL`, `# PKG-C-ADR`)
  - Зависит от: T48
  - Файлы: `sdx/hooks/pr-check.sh`
  - Что: предсказанный дифф (`git diff --name-only base_sha sdx/<sid>`; при расхождении — по дереву `merge-tree --write-tree`); `diff.nonempty`, `diff.scope` (`mandate_in_union`), `diff.session`, `docs.final` (путь под `docs/` вне `docs_paths`, К-12), `adr.registry` (WARN: не менялся/неоднозначен/вне `docs_paths`; при `none` не проверяется), `shared.note`, `attrs.export`, `url.scheme` (`pr_url_ok`), `url.origin-drift`.
  - DoD: `bash sdx/hooks/test-pr-check.sh` — C1–C3 зелёные, кроме строки красного теста-стаба.
  - Закрывает: REQ-PKG-11 (в, г), 12, 26, 27; A2, A11.

- [ ] **T50** `[CODE]` `pr-check.sh`, `pre`, часть 3: проверка `tests` и `--no-tests` (`# PKG-C-TESTS`)
  - Зависит от: T49
  - Файлы: `sdx/hooks/pr-check.sh`
  - Что: повторный прогон `test_cmd_resolve` из корня под `timeout`/`gtimeout ${SDX_VERIFY_TIMEOUT:-180}` (нет утилиты — без лимита и `NOTE tests: нет timeout`); нет команды — `NOTE`; `--no-tests` — `NOTE`; `base.ancestor` WARN → `WARN tests: прогон не относится к пакету`; запуск последним и только без `FAIL` выше; хвост красного вывода в stderr.
  - DoD: `bash sdx/hooks/test-pr-check.sh` — C1–C3 целиком зелёные.
  - Закрывает: REQ-PKG-11 (з); A2.

- [ ] **T51** `[TEST]` `test-pr-check.sh`: C4–C7 (фаза `post`, паритет с оракулом) — красные
  - Зависит от: T50
  - Файлы: `sdx/hooks/test-pr-check.sh`
  - Что: C4 — `post` зелёный на пакете из `pr-build` + оракул `approve`; C5 — красные пакеты `pkg_craft_*`: лишний коммит между `head` и вершиной, посторонний файл в манифест-коммите, неверный `archive_sha256`, файл вне области, `touches_shared` не объявлен, каталог сессии в пакете, `format: 2`, манифест внутри головы, фальшивый `scope_touched`, секрет в `notes`, чужие `commitment`/`executor`/`digest`; C6 — паритет: `оракул ≠ approve ⇔ pr-check post ≠ PASS` по проверкам, которые оракул покрывает, таблица «пакет → ожидаемые id провала»; встроенный негатив: подмена вердикта оракула краснит сверку; C7 — `all` = `pre` затем `post` (только если `pre` без `FAIL`); `--no-tests` пропускает только тесты; враждебный `executor` (ESC/перевод строки) в выводе через `pr_clean`.
  - DoD: `bash sdx/hooks/test-pr-check.sh` — C1–C3 зелёные, C4–C7 красные (перечень приложен).
  - Закрывает: REQ-PKG-8, 11, 12; A1, A2, A5.

- [ ] **T52** `[CODE]` `pr-check.sh`, `post`, часть 1: манифест и коммит (`# PKG-C-TIPCOMMIT`)
  - Зависит от: T51
  - Файлы: `sdx/hooks/pr-check.sh`
  - Что: `manifest.parse` (`miniyaml`), `manifest.format` (`change.format == 1`), `manifest.commit` (один родитель `== change.head`, `git diff --name-only head tip` = `CHANGE.yaml`), `manifest.headtree`, `manifest.identity` (`commitment`/`executor`/`mandate_digest` против заказа/мандата, имя ветки).
  - DoD: `bash sdx/hooks/test-pr-check.sh` — C4 и строки C5 про `format`, лишний коммит, посторонний файл, манифест внутри головы, чужие идентификаторы зелёные.
  - Закрывает: REQ-PKG-8, 11 (б); A1, A2.

- [ ] **T53** `[CODE]` `pr-check.sh`, `post`, часть 2: `archive`, `scope`, `shared`, `adr`, `secret`, `pkg.*`, повтор, фаза `all` (`# PKG-C-ARCHIVE`, `# PKG-C-SHARED`)
  - Зависит от: T52
  - Файлы: `sdx/hooks/pr-check.sh`
  - Что: `manifest.archive` (пересчёт от `head`), `manifest.scope` (множество = `git diff --name-only mbase head`), `manifest.shared` (вычисленное `true`, в манифесте не `true` → FAIL; обратное — NOTE), `manifest.adr` (при `final`; каждый путь до `#` в `PR_FILES`), `manifest.secret`, `pkg.session/scope/nonempty` (по `base..tip` без `CHANGE.yaml`), повтор `branch.scope`/`mandate.valid`/`closeout.*`; `--phase all`.
  - DoD: `bash sdx/hooks/test-pr-check.sh` целиком зелёный (C1–C7; сверка с оракулом PASS либо INFO-skip).
  - Закрывает: REQ-PKG-9, 11 (б, в, г, д, е, ж, и), 12, 26; A1, A2, A5, A11.

- [ ] **T54** `[TEST]` `test-pr-check.sh`: мутанты `PKG-C-*`; портируемость
  - Зависит от: T53
  - Файлы: `sdx/hooks/test-pr-check.sh`
  - Что: `PKG-C-TREE`, `PKG-C-SESSION`, `PKG-C-BRANCH`, `PKG-C-EXPIRED`, `PKG-C-SCOPE`, `PKG-C-DOCS-FINAL`, `PKG-C-ADR`, `PKG-C-TESTS`, `PKG-C-TIPCOMMIT`, `PKG-C-ARCHIVE`, `PKG-C-SHARED` — каждый краснит свой сценарий C2/C3/C5; `FORBID` по `pr-check.sh`.
  - DoD: `bash sdx/hooks/test-pr-check.sh` → `Results: N passed, 0 failed`, 11 строк «мутант … → красный»; время сьюта ≤ 12 с (цель DESIGN ≈ 10); `git status --porcelain` пуст.
  - Закрывает: REQ-PKG-11, 12, 26, 27; A2, A5, A11.

#### B-3. `pr-publish.sh` (DESIGN T7; зависит от T46, не от `pr-check`)

- [ ] **T55** `[TEST]` `test-pr-publish.sh`: P1–P4, P6, P7 — красные
  - Зависит от: T46
  - Файлы: `sdx/hooks/test-pr-publish.sh` (новый)
  - Что: каркас (`PR_PUBLISH_ONLY`); пакет — из `pr-build.sh`; P1 — push в локальный bare как `repo.url`: на удалённой стороне ровно одна новая ссылка `refs/heads/change/<C>-<exec>` (`for-each-ref`), `sdx/s1` и теги отсутствуют; `remote_sha == tip`; P2 — враждебный конфиг: `push.default=matching`, `remote.origin.push=+refs/heads/*:refs/heads/*`, `push.followTags=true` + аннотированный тег на `sdx/s1` → по-прежнему только `change/…`, тегов нет; P3 — не-fast-forward: на удалённой стороне `change/…` на постороннем коммите → rc 1; повтор уже отправленного → rc 0, `already: true`; FF-продолжение уходит без `--force`; P4 — `https://github.com/o/r.git`, `git@github.com:o/r.git` → `github`, локальный путь → `bare`, подсказка заказа приоритетнее; P6 — отказы: ветка `sdx/s1`/`main`; URL `ext::sh -c 'touch MARK'` (маркер не создан), `-oProxyCommand=…`, пробел, нет remote; `prod-guard.conf` с `git push` → rc 1; P7 — `https://u:p@host/x.git` не попадает в stdout/stderr/JSON (`--dry-run`).
  - DoD: `bash sdx/hooks/test-pr-publish.sh; echo $?` != 0 (нет скрипта); перечень красных строк приложен.
  - Закрывает: REQ-PKG-14, 15, 18, 35; A8 (тестовая часть).

- [ ] **T56** `[CODE]` `pr-publish.sh`, часть 1: refspec, whitelist, `prod-guard`, FF-проверка, push, JSON (`# PKG-P-REFSPEC`, `# PKG-P-URLWL`, `# PKG-P-PRODGUARD`, `# PKG-P-FF`, `# PKG-P-NOFOLLOW`)
  - Зависит от: T55
  - Файлы: `sdx/hooks/pr-publish.sh` (новый)
  - Что: по DESIGN «`pr-publish.sh`»: только `change/*`; `remote` = `--remote` либо `repo.url` заказа, иначе `origin` (имя настроенного remote либо URL, прошедший `pr_url_ok`); `spec="refs/heads/B:refs/heads/B"` без `+`; внутренний прогон `prod-guard.sh` на синтезированной команде `git push …`; `ls-remote` FF-проверка (`rsha == tip` → `already: true`, push не выполняется); `GIT_ALLOW_PROTOCOL=file:ssh:https:http GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND=… git -c push.followTags=false -c push.default=nothing push --porcelain --no-follow-tags -- "$remote" "$spec"`; повторный `ls-remote` (`remote_sha == tip`); `--dry-run`; `pr_url_show` на всём выводе; силового режима нет.
  - DoD: `bash sdx/hooks/test-pr-publish.sh` — P1–P4, P6, P7 зелёные; `grep -nE -- '--force|--all|--mirror|--tags|\+refs' sdx/hooks/pr-publish.sh` находит только строки запретительных комментариев.
  - Закрывает: REQ-PKG-14, 15, 18, 35; A8.

- [ ] **T57** `[TEST]` `test-pr-publish.sh`: P5 (`gh`) — красный
  - Зависит от: T56
  - Файлы: `sdx/hooks/test-pr-publish.sh`
  - Что: `gh`-стаб в `PATH` пишет argv: (а) есть и авторизован → `pr list --head … --repo o/r` затем `pr create --repo o/r --base dev --head change/… --title "C: T" --body-file F`; тело содержит обязательство, `executor`, число файлов, `verify`, `adr`, строку про `touches_shared`, нет секретов; (б) `gh` нет → rc 0, `degraded: gh-missing`, одна строка `instruction`; (в) `gh auth status` rc 1 → `gh-unauthenticated`; (г) PR уже есть → его URL, `create` не вызывается; (д) сбой `gh` → `gh-failed`, rc 0; push во всех случаях выполнен; секрет в теле → отказ до отправки.
  - DoD: `bash sdx/hooks/test-pr-publish.sh` — P1–P4, P6, P7 зелёные, P5 красный; перечень приложен.
  - Закрывает: REQ-PKG-10, 16; A9 (тестовая часть).

- [ ] **T58** `[CODE]` `pr-publish.sh`, часть 2: хостинг `github`, `gh pr create`, деградация, тело PR (`# PKG-P-GH`)
  - Зависит от: T57
  - Файлы: `sdx/hooks/pr-publish.sh`
  - Что: `pr_hosting`; `owner/repo` из URL по `github.com[:/]owner/repo(.git)?` (не разобрался → деградация); `command -v gh` + `gh auth status`; `gh pr list` → существующий PR либо `gh pr create` (аргументы массивом без оболочки через позиционные параметры); любая недоступность → `pr: null`, `degraded`, `instruction` «Откройте PR вручную: <branch> → <base> в <url без учётных данных>.», rc 0; тело из `git show tip:CHANGE.yaml` → `my_load`, значения через `pr_clean`, `pr_has_secret` на теле.
  - DoD: `bash sdx/hooks/test-pr-publish.sh` целиком зелёный.
  - Закрывает: REQ-PKG-10, 16, 35; A9.

- [ ] **T59** `[TEST]` `test-pr-publish.sh`: мутанты `PKG-P-*`; портируемость
  - Зависит от: T58
  - Файлы: `sdx/hooks/test-pr-publish.sh`
  - Что: `PKG-P-REFSPEC` (refspec со `+refs/heads/*` → P1), `PKG-P-NOFOLLOW` (убрать нейтрализацию конфига → P2), `PKG-P-FF` (без проверки → P3), `PKG-P-GH` (отказ вместо деградации → P5), `PKG-P-URLWL` (принимать `ext::` → P6), `PKG-P-PRODGUARD` (без внутреннего прогона → P6); `FORBID` по `pr-publish.sh`.
  - DoD: `bash sdx/hooks/test-pr-publish.sh` → `Results: N passed, 0 failed`, 6 строк «мутант … → красный»; время сьюта ≤ 8 с (цель DESIGN ≈ 6); `ls`/`git ls-remote` не оставляют артефактов в чекауте.
  - Закрывает: REQ-PKG-14, 16, 35; A8, A9.

### Дорожка C — `mandate-info.sh` и проза (после T21; прозаические задачи опираются на имена и выводы скриптов из DESIGN)

#### C-1. `mandate-info.sh pr-mode | pr-status` (DESIGN T8)

- [ ] **T60** `[TEST]` [PROC-020] `test-mandate-scope.sh` `[M]`: `pr-mode`, `pr-status` — красные
  - Зависит от: T21
  - Файлы: `sdx/hooks/test-mandate-scope.sh` (только добавление; прежние `[M]` не правятся)
  - Что: `pr-mode`: нет мандата → `REFUSE no-mandate`; orphan (только `mandate.yaml`) → `REFUSE orphan`; `delivery: pr`/`branch` → `OK executor=… delivery=… docs_in_repo=… history=… digest=…`; `artifact.offer` → `REFUSE delivery:artifact.offer`; `patch` → `REFUSE delivery:patch`; нечитаемый мандат → `REFUSE error:…`; `docs_in_repo` не задан → `final`; враждебный `executor` (ESC, кавычки, `:`) → через `safe` (`?`); `pr-status <sid>`: нет служебных коммитов → `PR: не сдан`; `submitted` (трейлеры `SDX-PR-*`) → строка `PR: branch=… head=… tip=… remote=… hosting=… pr=…`; `built` → `PR: собран, не отправлен …`; враждебные трейлеры → через `safe`; учётные данные в `SDX-PR-Remote` не печатаются.
  - DoD: `bash sdx/hooks/test-mandate-scope.sh; echo $?` != 0 (подкоманд нет); прежние сценарии (1)–(10) и `[M]` зелёные; перечень красных строк приложен.
  - Закрывает: REQ-PKG-2, 17, 34; A12 (тестовая часть), A13.

- [ ] **T61** `[CODE]` [PROC-020] `mandate-info.sh`: `pr-mode` (`# PKG-PRMODE-NOMANDATE`, `# PKG-PRMODE-DELIVERY`)
  - Зависит от: T60
  - Файлы: `sdx/hooks/mandate-info.sh` (только добавление подкоманды; `closeout-mode`/`closeout-check` и их мутанты не меняются)
  - Что: по DESIGN «`mandate-info.sh` — `pr-mode`»: `mandate_mode` ≠ `on` → `REFUSE no-mandate` (`orphan` — отдельно); `mandate_load` fail → `REFUSE error:<причина через safe>`; `delivery` ∉ {`pr`,`branch`} → `REFUSE delivery:<safe>`; иначе `OK …`; все значения проходят `safe` (`[A-Za-z0-9._-]`, прочее `?`); rc 0/1.
  - DoD: `bash sdx/hooks/test-mandate-scope.sh` — строки `pr-mode` зелёные; `git diff sdx/hooks/mandate-info.sh` — только добавление.
  - Закрывает: REQ-PKG-2, 34; A12, A13.

- [ ] **T62** `[CODE]` [PROC-020] `mandate-info.sh`: `pr-status`
  - Зависит от: T61
  - Файлы: `sdx/hooks/mandate-info.sh`
  - Что: `git log --grep "^sdx(<sid>): pr (submitted|built) " -n1`, трейлеры `SDX-PR-*` читаются как данные и выводятся через `safe`; `pr_url_show` для remote; варианты «не сдан» / `submitted` / `built`.
  - DoD: `bash sdx/hooks/test-mandate-scope.sh` целиком зелёный; `grep -nE 'eval' sdx/hooks/mandate-info.sh` пусто (python — только прежняя проба `status`).
  - Закрывает: REQ-PKG-17; A8.

- [ ] **T63** `[TEST]` [PROC-020] `test-mandate-scope.sh`: мутанты `PKG-PRMODE-NOMANDATE`, `PKG-PRMODE-DELIVERY`
  - Зависит от: T62
  - Файлы: `sdx/hooks/test-mandate-scope.sh`
  - Что: `PKG-PRMODE-NOMANDATE` (режим не проверяется → `OK` без мандата), `PKG-PRMODE-DELIVERY` (допускается `artifact.offer`) — каждый краснит свой сценарий `[M]`.
  - DoD: `bash sdx/hooks/test-mandate-scope.sh` → `Results: N passed, 0 failed`, +2 строки «мутант … → красный»; прирост времени ≤ 1 с.
  - Закрывает: REQ-PKG-2, 34; A12, A13.

#### C-2. Команды и проверка прозы (DESIGN T9)

- [ ] **T64** `[TEST]` `test-mo-prose.sh`: `[19]` (`archive.md`), `[20]` (`pr.md`), `[26]` (`start.md`/`status.md`), пин `[12]` — красные
  - Зависит от: T21
  - Файлы: `sdx/hooks/test-mo-prose.sh` (только добавление и изменение пинов 2.4.0 `[12]`; `[17]`, `[11]`, `[21]`–`[25]`, `[27]` — T69)
  - Что: `[19]` — `archive.md` делегирует `commands/pr.md` для `bridge`, ручной инструкции из трёх шагов нет, шаги 6–8 `(n/a, пакет)` для `bridge`, `(n/a, мандат)` остаётся для `bridge:offer`, ветки `bridge:offer`/`undefined`/`error:*`/`standard` на месте; в `standard` шаги 1–8 не тронуты; `[20]` — `pr.md`: вызовы `pr-check.sh`, `pr-build.sh`, `pr-publish.sh`, `protocol-export.sh`, `mandate-info.sh pr-mode`, `AskUserQuestion`, «в любом gate_mode», дословная одна строка отказа без мандата (P0), порядок P0…P10, нет командной строки `git push` вне запретительного текста, запреты (не вызывать `audit()`, не писать в `.mesh/`, не сливать `change/*`), **согласованность флагов:** каждый токен `--флаг` в вызовах `pr-*.sh`/`protocol-export.sh`/`order-import.sh` внутри `pr.md`/`start.md` присутствует в тексте соответствующего скрипта (ловит расхождение имён между дорожками); `[26]` — `start.md`: `--from-order`, `--from-issue`, `order-import.sh`, `stamp-state`, шаг 1б, шаги 1–8 на месте; `status.md`: `pr-status`, шаг 5б; пин `[12]` обновляется (мост для `pr|branch` → «пакет»). У каждого инварианта красная сторона на повреждённой копии.
  - DoD: `bash sdx/hooks/test-mo-prose.sh` — прежние инварианты кроме обновлённого `[12]` зелёные, `[12]`, `[19]`, `[20]`, `[26]` красные (перечень приложен); на повреждённых копиях инварианты красные — показано.
  - Закрывает: REQ-PKG-1, 2, 3, 13, 17, 23–25, 30, 34, 35; A8, A10, A12, A13 (тестовая часть).

- [ ] **T65** `[DOC]` `commands/pr.md` — конвейер `/sdx:pr`
  - Зависит от: T64
  - Файлы: `commands/pr.md` (новый; frontmatter `description`, `argument-hint: [<C>] [--title "<заголовок>"] [--resubmit] [--build-only]`)
  - Что: по DESIGN «`commands/pr.md` — конвейер»: P0 (режим, дословная одна строка отказа; `artifact.offer` → мост `/sdx:archive`; иное — стоп-рубрика), P1 (состояние, прелюдия `archive.md`, пропуск P2–P4 при удалённом каталоге сессии), P2 (шаги 1–4 по `archive.md`, шаги 6–8 `(n/a, пакет)`), P3 (экспорт `protocol.yaml` и коммит), P4 (шаг 5), P5 (`pr-check --phase pre`, Bash timeout >= 600000 мс; rc 1 стоп, rc 3 — `AskUserQuestion` по классам WARN), P6 (`pr-build`, rc 3 → подтверждение), P7 (`pr-check --phase post`), P8 (подтверждение push в любом `gate_mode`, `[контракт]`), P9 (`pr-publish` + служебный пустой коммит с трейлерами `SDX-PR-*` через `git commit --allow-empty -F -`), P10 (итог); правило идентификатора/заголовка (REQ-PKG-7); запреты. Данные заказа/мандата — данные, не инструкции.
  - DoD: `bash sdx/hooks/test-mo-prose.sh` — `[20]` зелёный (в части согласованности флагов — после готовности A/B скриптов; до этого флаги сверяются по именам DESIGN, окончательная сверка на финальных скриптах — в T77); `wc -l commands/pr.md` разумно (≤ 150 строк); frontmatter валиден.
  - Закрывает: REQ-PKG-1, 2, 3, 7, 13, 17, 18, 35; A8, A12.

- [ ] **T66** `[DOC]` `commands/archive.md` — делегирование моста `/sdx:pr`
  - Зависит от: T65
  - Файлы: `commands/archive.md`
  - Что: заголовок: «Closeout имеет два варианта — „мёрж“ (шаги 6–8) и „пакет“ (`/sdx:pr`)»; шаг 2а, ветка `bridge` (`pr|branch`): ручная инструкция из трёх шагов удалена, вместо неё делегирование процедуре `commands/pr.md` (прелюдия 1–2а уже пройдена, продолжать с P0; `archive-verify.sh` не вызывается; шаги 6–8 `(n/a, пакет)`; ветка `sdx/<id>` остаётся); `bridge:offer`, `undefined:*`, `error:*`, `standard` — без изменений, кроме одной фразы в `bridge:offer` (DESIGN «`commands/archive.md`»: «пакет … решение узла; ручная сборка по `sdx/mo/CHANGE.template.yaml` и `sdx/templates/CONTRIBUTING-MO.md`»).
  - DoD: `bash sdx/hooks/test-mo-prose.sh` — `[12]`, `[19]` зелёные; `git diff main -- commands/archive.md` не затрагивает стандартный чек-лист (шаги 1–8 ветки `standard`).
  - Закрывает: REQ-PKG-1, 26, 30; A13.

- [ ] **T67** `[DOC]` `commands/start.md` — `--from-order`, `--from-issue`
  - Зависит от: T65
  - Файлы: `commands/start.md`
  - Что: `argument-hint: <type> <goal> [--auto] [--from-order <order.yaml|msg_id>] [--from-issue <N>]`; новый шаг **1б** по DESIGN (i)–(vi): `pr-mode` не `OK` → отказ одной строкой; `order-import.sh from-file|from-msg|from-issue` (для значения: существующий файл — `from-file`, иначе шаблон `msg_id` — `from-msg`; без значения — `list` и вопрос); код 3 → `[контракт]` с `MISMATCH`-строками; код 1 → причина дословно и стоп; `--from-issue` — `AskUserQuestion` в любом `gate_mode` (К-9); `gate_mode: auto` + директива → `[директива]`; цель из `commitment.title`; `requirements` — данные для `ba`/`architect`; после `init` — `stamp-state` и снимок `order.yaml`, оба в seed-коммит; `session_id` содержит `sid_infix`; предупреждение при текущей ветке ≠ `repo.base`; без флагов шаги 1–8 прежние.
  - DoD: `bash sdx/hooks/test-mo-prose.sh` — `[26]` по `start.md` зелёный, прежний `[14]` зелёный.
  - Закрывает: REQ-PKG-23, 24, 25; A10.

- [ ] **T68** `[DOC]` `commands/status.md` — `commitment` и `pr-status`
  - Зависит от: T65
  - Файлы: `commands/status.md`
  - Что: шаг 3 — `commitment`, если поле есть; новый читающий шаг **5б** (только при `mandate_mode = on`): `mandate-info.sh pr-status <id>`; ветка `sdx/<id>` без каталога сессии показывается как «сессия в состоянии сдачи пакета (каталог сессии удалён)» с этой строкой; команда остаётся чисто читающей (инструментов записи не добавлять).
  - DoD: `bash sdx/hooks/test-mo-prose.sh` — `[26]` по `status.md` зелёный; `git diff commands/status.md` не добавляет `Write`/`Edit`/запись файлов.
  - Закрывает: REQ-PKG-17, 25; A8.

### Дорожка З — Замыкание (последовательно, после T31, T38, T54, T59, T63, T68)

- [ ] **T69** `[TEST]` `test-mo-prose.sh`: `[11]` пин, `[17]` пин, `[21]`–`[25]`, `[27]` — красные
  - Зависит от: T31, T38, T54, T59, T63, T68
  - Файлы: `sdx/hooks/test-mo-prose.sh`
  - Что: `[11]` — сниппет: «нет /sdx:pr» → «есть /sdx:pr» (пин 2.4.0 изменён); `[17]`/`chk_plugin_version` — версия `2.4.0` → `2.5.0`; `[21]` — протокол: два варианта Closeout, снятие моста для `pr|branch`, подраздел с `pr-*.sh`, `protocol-export.sh`, `order-import.sh`, служебный коммит с трейлерами, `commitment`, оговорка К-1, граница К-17, оба формата журнала; `[22]` — сниппет = текст §6 `sdx/mo/MO-INTEROP.md` (после снятия `> ` и склейки строк) и содержит `/sdx:pr`; `[23]` — `docs/DECISIONS.md`: ADR-022 заголовком; `[24]` — `agents/devops.md`: `/sdx:pr`, «теги», `CHANGE.template.yaml`, frontmatter не изменён; `[25]` — `README.md`/`README.en.md`/`CLAUDE.md` называют `CHANGE.template.yaml`, `pr-build.sh`, `CONTRIBUTING-MO.md`, `2.5.0`; `[27]` — `sdx/templates/CONTRIBUTING-MO.md` существует, `sdx/mo/` его не содержит. Красная сторона каждого — повреждённая копия.
  - DoD: `bash sdx/hooks/test-mo-prose.sh` — `[11]`, `[17]`, `[21]`–`[25]`, `[27]` красные (перечень приложен); остальное зелёное.
  - Закрывает: REQ-PKG-29–33; A14, A15 (тестовая часть).

- [ ] **T70** `[DOC]` `sdx/protocol.md`
  - Зависит от: T69
  - Файлы: `sdx/protocol.md`
  - Что: по DESIGN «Перечень правок документов»: (1) «Контракт закрытия» — два варианта Closeout, `bridge` (`pr|branch`) → пакет, ручная инструкция снята, `bridge:offer`/`undefined`/`error` сохранены, токен `bridge` помечен «исторический» (К-7); (2) подраздел «Мандат» — скрипты `pr-build`/`pr-check`/`pr-publish`/`protocol-export`/`order-import`, служебный коммит с трейлерами (К-2, К-16), `commitment` в `session_state.json`, граница (5) `docs_in_repo` (`final` = `full`, реестр по `docs_paths`), граница «внутренние записи скриптов не видны хуку» (К-17), канал `protocol.yaml` (К-18); (3) «Вендорённые компоненты» — четвёртый файл, оговорка К-1 (уже частично — T03), `CONTRIBUTING-MO.md` — не вендорённый; (4) «Журнал решений» — оба формата записи.
  - DoD: `bash sdx/hooks/test-mo-prose.sh` — `[21]`, `[12]` по протоколу зелёные; `bash sdx/hooks/test-mo-inventory.sh` зелёный; список пунктов стоп-рубрики без изменений (`diff` раздела с `git show main:sdx/protocol.md` пуст).
  - Закрывает: REQ-PKG-22, 30, 33; A13, A15.

- [ ] **T71** `[DOC]` `docs/DECISIONS.md` — ADR-022 «Пакет изменения — второй вариант Closeout»
  - Зависит от: T70
  - Файлы: `docs/DECISIONS.md`
  - Что: контекст, решение (D-1…D-12 кратко), отвергнутые альтернативы (checkout/worktree, `git notes`, `--force-with-lease`, PyYAML для заказа, переименование токена), последствия; снимает мост FEAT-016 как временный для `pr|branch`; датированная (2026-10-31) поправка к ADR-021 (мост → пакет, `docs_in_repo: final = full`); поправка к ADR-020 не нужна; число упоминаний `mesh_endpoint.py`/`devagent_hook.py`/`MO-INTEROP.md` не уменьшено; ссылки на `CHANGE.template.yaml`.
  - DoD: `bash sdx/hooks/test-mo-prose.sh` — `[23]` и прежние `[16]`, `[9]` зелёные; `grep -c 'mesh_endpoint.py\|devagent_hook.py\|MO-INTEROP.md' docs/DECISIONS.md` не меньше значения на `main`; `bash sdx/hooks/test-mo-inventory.sh` зелёный.
  - Закрывает: REQ-PKG-31; A15.

- [ ] **T72** `[DOC]` Сниппет `claude-md-snippet.md` (§6 `MO-INTEROP.md` 0.9.1) и `agents/devops.md`
  - Зависит от: T71
  - Файлы: `sdx/templates/claude-md-snippet.md`, `agents/devops.md`
  - Что: сниппет — абзац «МО над стендами» заменяется полным текстом §6 `sdx/mo/MO-INTEROP.md` 0.9.1 (REQ-PKG-32), маркеры `SDX:BEGIN`/`SDX:END` по одному и не меняются; `devops.md` — «Режим МО»: действие сдачи — `/sdx:pr` (основная сессия, не `devops`), слияний вне `scope.branches` и тегов по-прежнему нет, пункт `artifact.offer` сохранён, упоминание `CHANGE.template.yaml`; frontmatter не менять.
  - DoD: `bash sdx/hooks/test-mo-prose.sh` — `[11]`, `[22]`, `[24]` и прежний `[10]` зелёные; `sed -n '1,/^---$/p' agents/devops.md` совпадает с `git show main:agents/devops.md`; `bash sdx/hooks/test-snippet-check.sh` зелёный; `bash sdx/hooks/snippet-check.sh CLAUDE.md` печатает одно из `ABSENT|BROKEN|OK|STALE`.
  - Закрывает: REQ-PKG-32, 33; A15.

- [ ] **T73** `[DOC]` `README.md`, `README.en.md`, `CLAUDE.md`
  - Зависит от: T72
  - Файлы: `README.md`, `README.en.md`, `CLAUDE.md`
  - Что: таблица `sdx/mo/` — четыре файла; новые скрипты `sdx/hooks/` (`pr-build`, `pr-check`, `pr-publish`, `protocol-export`, `order-import`, `lib/pr-lib`, `lib/pkg-fixture`), `commands/pr.md`, `sdx/templates/CONTRIBUTING-MO.md`; абзац «Версия 2.5.0 — сдача пакетом изменения» (RU/EN симметрично, те же факты); `CLAUDE.md` §3 «Этапы → Closeout» — два варианта, §6 — перечень `sdx/hooks/`, `sdx/mo/` (четыре файла), `sdx/templates/CONTRIBUTING-MO.md`; три прежних имени `mesh_endpoint.py`/`devagent_hook.py`/`MO-INTEROP.md` остаются на каждой поверхности.
  - DoD: `bash sdx/hooks/test-mo-inventory.sh` зелёный; `bash sdx/hooks/test-mo-prose.sh` — `[25]` и прежний `[9]` по README×2 зелёные; `grep -c 'pr-build.sh' README.md README.en.md CLAUDE.md` ≥ 1 в каждом; визуальная сверка пары RU/EN записана в сообщении коммита.
  - Закрывает: REQ-PKG-33; A15.

- [ ] **T74** `[DOC]` Дельты `docs/specs|designs/mo-interop.md`, поправка `decision-journal-and-resume.md`, запись бэклога FEAT-017
  - Зависит от: T73
  - Файлы: `docs/specs/mo-interop.md`, `docs/designs/mo-interop.md`, `docs/designs/decision-journal-and-resume.md`, `docs/backlog/FEAT-017-*.md`
  - Что: `docs/specs/mo-interop.md` — REQ-MAND-23/23a/23b с отметкой «заменено REQ-PKG-30 для `pr|branch`», раздел «Дельты FEAT-017» (REQ-PKG-1…36 сжато); `docs/designs/mo-interop.md` — «Дельта FEAT-017» (сжатый перенос дизайна; полный дизайн после Closeout — `docs/history/designs/feat-017-…md`); `decision-journal-and-resume.md` — датированная поправка: необязательное поле `commitment` в `session_state.json`, формат B записи журнала; запись бэклога — уточнения (`CONTRIBUTING-MO.md` в `sdx/templates/`, поле `change` в `artifact.offer` не добавляется, `docs_in_repo`), `status` на Closeout (C2), не здесь.
  - DoD: `bash sdx/hooks/test-mo-prose.sh` зелёный по этим файлам; `bash sdx/hooks/test-mo-inventory.sh` зелёный; `grep -c 'FEAT-017' docs/specs/mo-interop.md docs/designs/mo-interop.md` ≥ 1 в каждом; `grep -c 'commitment' docs/designs/decision-journal-and-resume.md` ≥ 1.
  - Закрывает: REQ-PKG-30, 33; A15.

- [ ] **T75** `[CODE]` `plugin.json` 2.4.0 → 2.5.0
  - Зависит от: T69 (красный `[17]` уже есть), T74
  - Файлы: `.claude-plugin/plugin.json` (`marketplace.json` версии не содержит — не трогать)
  - Что: `version` → `2.5.0`.
  - DoD: `jq -r .version .claude-plugin/plugin.json` → `2.5.0`; `bash sdx/hooks/test-mo-prose.sh` → `Results: N passed, 0 failed` (все `[9]`–`[27]` зелёные); `grep -n version .claude-plugin/marketplace.json` — версии нет.
  - Закрывает: REQ-PKG-33; A15.

- [ ] **T76** `[DOC]` Заготовки релизных заметок 2.5.0 и записки upstream (в каталоге сессии)
  - Зависит от: T75
  - Файлы: `.claude/sessions/feat-017-mo-change-package-20261031/release_notes_draft.md`, `.claude/sessions/feat-017-mo-change-package-20261031/upstream_note_draft.md` (только в каталоге сессии; публикация в `docs/history/releases/v2.5.0-notes.md` — на Closeout)
  - Что: двуязычные накопительные заметки (русский блок, `---`, английский); раздел «Границы»/«Boundaries» с непроверенным: живой `audit()`, `gh` на реальном GitHub, `archive_sha256` между версиями git, хук области на `/sdx:pr`, канал `protocol.yaml` при `history: executor`, `--from-order` с реальным ящиком; записка upstream владельцу МО (К-18): (1) канал доставки `protocol.yaml` при `history: executor`, (2) формат issue-заказа, (3) исключение корневого `CHANGE.yaml` из `_in_scope` хука, (4) семантика `docs_in_repo: final|full`, (5) `artifact.offer` с полем `change` не добавляется.
  - DoD: оба файла существуют; в заметках есть «Границы»/«Boundaries»; `git -C /home/archi/Code/aibok/agentico/meta-orchestrator/sim-kit status --porcelain` не показывает изменений от этой работы.
  - Закрывает: REQ-PKG-33; A15 (процесс).

- [ ] **T77** `[INFRA]` Полный прогон с замером; сверка флагов `pr.md` со скриптами; решение по К-10
  - Зависит от: T75, T76
  - Файлы: —
  - Что: `time bash .claude/sdx/verify-cmd.sh`; приложить итоговые строки `Results:` всех сьютов (включая новые `test-pr-build`, `test-pr-check`, `test-pr-publish`, `test-protocol-export`, `test-order-import`, `test-pkg-fixture`); записать, какие оракульные ветки дали PASS, какие INFO-skip; убедиться, что `test-mo-prose [20]` (сверка флагов `pr.md` ↔ скрипты) зелёный на финальных скриптах (при расхождении — править `commands/pr.md`/`start.md`, не скрипты, либо зафиксировать отклонение). Если время > 150 с без нагрузки — решение К-10: сначала `SCEN_MIN=1` для мутантов в основном прогоне (полный набор — под `PKG_FULL=1`), затем параллельный раннер (T78).
  - DoD: exit 0, все сьюты `0 failed`; **время ≤ 150 с (цель), ≤ 180 с (предел)**; число сьютов = прежнее + 6; `find . -name __pycache__ -not -path './.git/*'` пусто; `git status --porcelain` пуст.
  - Закрывает: REQ-PKG-36; A16.

- [ ] **T78** `[DOC]` `.claude/sdx/verify-cmd.sh`: комментарий о длительности (при необходимости — `SDX_VERIFY_JOBS`, К-10)
  - Зависит от: T77
  - Файлы: `.claude/sdx/verify-cmd.sh` (dogfood-раннер репозитория, не плагин)
  - Что: актуализировать комментарий «число сьютов, время» по замеру T77 (без изменения исполняемой части). **Условная ветка:** если T77 дал > 150 с — добавить параллельный запуск сьютов (`SDX_VERIFY_JOBS`, по умолчанию 2; сьюты независимы — каждый работает в `mktemp`) как отдельный коммит с собственной проверкой (`bash -n`, повторный полный прогон ≤ 150 с, порядок/вывод итоговых строк сохранены) и записью в «Отклонения».
  - DoD: без условной ветки — `git diff .claude/sdx/verify-cmd.sh` содержит только строки комментариев; с условной веткой — `SDX_VERIFY_JOBS=1` даёт прежнее поведение, повторный замер приложен; `bash -n .claude/sdx/verify-cmd.sh`.
  - Закрывает: REQ-PKG-36; A16.

- [ ] **T79** `[DOC]` `MANUAL_TEST.md` — ручной сценарий для Verification
  - Зависит от: T58, T67
  - Файлы: `.claude/sessions/feat-017-mo-change-package-20261031/MANUAL_TEST.md` (новый)
  - Что: перенести DESIGN «Ручной сценарий для Verification» (пп. 1–8) как «Случай N» с полями «Действие / Предусловие / Ожидаемый результат / Результат (заполняется)»: (1) живой `audit()` узла 0.9.1 на пакете (`./mo change poll app` → `./mo change audit app change/C-…`; точные команды выдачи мандата помечены «не проверены»); (2) `gh pr create` на реальном репозитории GitHub и деградация после `gh auth logout`; (3) доставка `protocol.yaml` (`./mo work protocol <C>`); (4) хук области на командные строки `/sdx:pr` при `on_write: deny`; (5) проза `pr.md`/`archive.md` (подтверждение push в `interactive` **и** `auto`, отказ без мандата, делегирование); (6) `/sdx:start --from-order <msg_id>` с реальным `mesh_endpoint.py pull`, `--from-issue`; (7) `archive_sha256` на другой версии git; (8) замер полного прогона; ветка «выполнить нельзя» → «не проверено» (непроверенное допущение); поля версий (`git --version`, `claude --version`, sim-kit).
  - DoD: `grep -c '^## Случай' MANUAL_TEST.md` ≥ 8; у каждого случая есть строки «Ожидаемый результат» и «Результат (заполняется)»; фраза «не проверено» присутствует в ветках невозможности; прогон — задача `qa`/пользователя на Verification.
  - Закрывает: A1, A9, A10, A8 (живые части), A16.

- [ ] **T80** `[INFRA]` Проверки инвариантов поставки
  - Зависит от: T77
  - Файлы: —
  - Что: (а) `(cd sdx/mo && sha256sum -c SIMKIT_SHA256)` — `OK`×4 и `git diff --stat main -- sdx/mo/mesh_endpoint.py sdx/mo/devagent_hook.py sdx/mo/MO-INTEROP.md` пуст; (б) `git diff --stat main -- hooks/hooks.json sdx/hooks/stop-gate.sh sdx/hooks/archive-verify.sh sdx/hooks/sdx-stage.sh sdx/hooks/mo-hook.sh sdx/hooks/mo-session.sh sdx/hooks/lib/miniyaml.sh sdx/hooks/lib/test-cmd.sh agents/reviewer.md` пуст; (в) `grep -nE 'python|eval' sdx/hooks/lib/pr-lib.sh sdx/hooks/lib/mandate.sh sdx/hooks/pr-build.sh sdx/hooks/pr-check.sh sdx/hooks/pr-publish.sh sdx/hooks/protocol-export.sh` пусто, а в `order-import.sh` — только вызов `mesh_endpoint.py` в `from-msg`; (г) без мандата поведение прежнее: `bash sdx/hooks/mandate-info.sh pr-mode` в этом репозитории (`.mesh/` нет) → `REFUSE no-mandate`; `mo-hook.sh` и `mo-session.sh` на этом репозитории — пустой вывод, rc 0; (д) `pr.md` не содержит `git push` вне запретительного текста.
  - DoD: все пять проверок дают указанный результат (вывод приложен).
  - Закрывает: REQ-PKG-28, 34, 35; A12, A13, A14.

- [ ] **T81** `[TEST]` Регресс: прежние сьюты без правок утверждений
  - Зависит от: T77
  - Файлы: —
  - Что: `git diff main -- sdx/hooks/test-*.sh` — только добавления, кроме пинов `test-mo-prose.sh` (`[11]`, `[12]`, `[17]`, `chk_plugin_version`; Q-17 SPEC), каждый изменённый пин перечислен; `test-stop-gate.sh`, `test-archive-verify.sh`, `test-hook-wiring.sh`, `test-selftest.sh`, `test-snippet-check.sh`, `test-mo-inventory.sh`, `test-sdx-stage.sh`, `test-mo-hook.sh`, `test-mo-session.sh`, `test-suites-gen.sh`, `test-init-patterns.sh` зелёные.
  - DoD: перечисленные сьюты `0 failed`; дифф — только добавление плюс перечисленные пины.
  - Закрывает: REQ-PKG-30, 34; A12, A13, A15.

- [ ] **T82** `[INFRA]` Финальная сверка процесса
  - Зависит от: T77–T81
  - Файлы: —
  - Что: `jq -r .gate_mode .claude/sessions/feat-017-mo-change-package-20261031/session_state.json` != `auto`; перечень красных сторон (T05, T07, T10, T16, T22, T25, T28, T32, T35, T39, T41, T43, T47, T51, T55, T57, T60, T64, T69) отмечен ссылками на коммиты; раздел «Отклонения» заполнен фактами (если были); чек-лист PLAN актуализирован (процент, галочки); ни один коммит ветки не сделан через `--amend`.
  - DoD: перечисленное подтверждено в сообщении коммита.
  - Закрывает: процесс (PROC-020); REQ-PKG-36.

### Closeout (после Verification; не Execution)

- [ ] **C1** `[DOC]` Результаты ручного сценария (`MANUAL_TEST.md`) записать как факт либо «не проверено»; синхронизировать текст протокола/ADR-022 при смене статуса допущения.
- [ ] **C2** `[DOC]` Бэклог (ADR-015): статус `FEAT-017` → закрыт (`session`); новые записи `DEBT-` «токен `closeout-mode` → `package`», `DEBT-` «единый формат `decisions_log.md`», `IDEA-` «upstream-записка владельцу МО (К-18)», `IDEA-` «параллельный раннер `verify-cmd.sh`» (если не понадобился по К-10); перенос `SPEC.md`/`DESIGN.md` → `docs/specs|designs`, план → `docs/history/plans/`, дизайн → `docs/history/designs/feat-017-mo-change-package-20261031.md`.
- [ ] **C3** `[DOC]` Релиз: заметки 2.5.0 (двуязычные) в `docs/history/releases/v2.5.0-notes.md`, тег `v2.5.0` на merge-коммите, `/plugin marketplace update sdx`; push/релиз — только по явной просьбе пользователя. Closeout сессии — вариант «мёрж» (шаги 1–8): сама сессия SDX-репозитория не под мандатом.

## Зависимости между задачами

```
Ф-0:  T01 ─> T02 ─> T03
                 └─> T04
Ф-1:  T04 ─> T05 ─> T06 ─> T07 ─> T08 ─> T09 ─> T10 ─> T11 ─> T12 ─> T13 ─> T14 ─> T15
Ф-2:  T15 ─> T16 ─> T17 ─> T18 ─> T19 ─> T20
Gate: T20, T03 ─> T21 (полный прогон; старт дорожек A, B, C)

Дорожка A (order-import, protocol-export; независима от B, C):
      T21 ─> T22 ─> T23 ─> T24 ─> T25 ─> T26 ─> T27 ─> T28 ─> T29 ─> T30 ─> T31
      T21 ─> T32 ─> T33 ─> T34 ─> T35 ─> T36 ─> T37 ─> T38        (A-1 и A-2 независимы друг от друга)
Дорожка B (pr-build, pr-check, pr-publish):
      T21 ─> T39 ─> T40 ─> T41 ─> T42 ─> T43 ─> T44 ─> T45 ─> T46
      T46 ─> T47 ─> T48 ─> T49 ─> T50 ─> T51 ─> T52 ─> T53 ─> T54     (pr-check)
      T46 ─> T55 ─> T56 ─> T57 ─> T58 ─> T59                          (pr-publish; независим от pr-check)
Дорожка C (mandate-info, проза):
      T21 ─> T60 ─> T61 ─> T62 ─> T63                                 (mandate-info; независим от A, B)
      T21 ─> T64 ─> T65 ─> T66, T67, T68                             (T66–T68 — разные файлы, параллельны)
Дорожка З:
      T31, T38, T54, T59, T63, T68 ─> T69 ─> T70 ─> T71 ─> T72 ─> T73 ─> T74 ─> T75 ─> T76 ─> T77
      T77 ─> T78, T80, T81 ; T58, T67 ─> T79 ; T78..T81 ─> T82
      T82 ─> [Verification: /sdx:verify, ручной сценарий T79] ─> C1 ─> C2 ─> C3
```

Порядок поставки (DESIGN «Декомпозиция»): 0 (T01–T04) → 1 (T05–T15) → 2 (T16–T21) обязателен и последователен; затем **три параллельные дорожки `developer`**: **A** — `order-import.sh`/`protocol-export.sh` (T22–T38; DESIGN T3, T4), **B** — `pr-build.sh` → {`pr-check.sh`, `pr-publish.sh`} (T39–T59; DESIGN T5–T7; внутри B pr-check и pr-publish независимы друг от друга после T46), **C** — `mandate-info.sh` (T60–T63; DESIGN T8) и команды/проза (T64–T68; DESIGN T9, зависимость от A/B — только по именам и выводам скриптов, финальная сверка флагов — `test-mo-prose [20]` и T77); затем З (DESIGN T10, T11). Конфликтов по файлам нет (см. «Владение файлами»; `test-mo-prose.sh` — только C до T68, затем З).

## Тестовый цикл

- Полный прогон: `bash .claude/sdx/verify-cmd.sh` (глоб `sdx/hooks/test-*.sh` подхватывает новые сьюты); локально по дорожке — `bash sdx/hooks/test-<suite>.sh`, узко — `<SUITE>_ONLY="<блоки>"`.
- Бюджет времени (DESIGN «Бюджет времени»): прирост ≈ +33 с (+ ≈ 1,5 с `test-pkg-fixture`) к ≈ 105–125 с → ≈ 140–160 с при пределе 180 с; критерий A16 — ≤ 150 с без нагрузки; замеры: T21 (база), T77 (итог). Рычаги К-10: `SCEN_MIN=1` в основном прогоне мутантов, затем `SDX_VERIFY_JOBS` (T78, условная ветка).
- Окружение без `python3`/PyYAML: оракульные ветки (`pkg_oracle`, паритет `order-unfold` с `safe_load`, схема `protocol_check()`, роундтрип экранирования) дают INFO-skip, не PASS; остальные проверки (через `jq`) остаются; в DoD T21/T77 указывать, какой вариант получен.
- Не тестируется автоматически (ручной сценарий, T79): живой `audit()` узла, реальный `gh`/GitHub, `archive_sha256` на другой версии git, хук области на командные строки `/sdx:pr`, поведение модели по прозе `pr.md`, `--from-order` с реальным `mesh_endpoint.py pull`.

## Таблица покрытия критериев приёмки SPEC (A1–A16) задачами

| № | Критерий (кратко) | Задачи |
|---|---|---|
| A1 | Пакет `/sdx:pr` проходит зеркальные формальные проверки `audit()` (`format`, `manifest.commit`, `scope`, `archive_sha256`, `adr`, `branch`, `mandate.valid`) — без `reject`/`return` | T16, T18–T20, T41, T43–T46, T51–T53, T79 (п.1) |
| A2 | Красные стороны `pr-check` (лишний коммит, посторонний файл в манифест-коммите, путь вне `scope`, неверный `archive_sha256`, каталог сессии, грязное дерево, ветка вне `scope.branches`, истёкший мандат, красный stop-gate) блокируют push | T05, T06, T16, T19, T20, T47–T54 |
| A3 | Сборка не пишет `CHANGE.yaml` в рабочее дерево; дерево чистое, ветка `sdx/<sid>` | T10, T11, T14, T15, T39–T41, T43, T45, T46 |
| A4 | `archive_sha256` = `sha256(git archive --format=tar <head>)`, воспроизводим в независимом клоне | T41 (B3), T42, T45, T46 (`PKG-ARCHIVE`) |
| A5 | `touches_shared` оба исхода, `scope_touched` включает сгенерированное | T12, T20, T41 (B4), T42, T51, T53, T54, T46 |
| A6 | `protocol.yaml`: пять списков, непустые `id/what/why`, пустые источники → пустые списки, файла нет в `change/*` | T32–T38, T41 (B11), T45 |
| A7 | Запись журнала с ADR → `adr: true`, без → `false` | T33, T35, T38 (`PKG-X-ADR`), T41 (B5) |
| A8 | Без подтверждения push не выполняется ни в `standard`, ни в `auto`; только явный refspec `change/<C>-<exec>`, `sdx/*` не уходит | T55–T59, T62, T64, T65, T68, T79 (п.5) |
| A9 | `github` без `gh`: push + одна строка инструкции, не отказ; с `gh` — PR против `repo.base` с телом из манифеста | T09, T57–T59, T79 (п.2) |
| A10 | `--from-order` (файл, конверт) переносит `commitment` в `session_state.json`/`order.yaml`, `C-…` в `sid`; несовпадение `mandate_digest` останавливает; `--from-issue` без `gh` отказывает с подсказкой | T22–T31, T64, T67, T79 (п.6) |
| A11 | `docs_in_repo`: `none` — переносы `(n/a)`, дельты в `protocol.yaml`; `final` — нет документов вне `docs_paths`, `adr` непуст и в пакете; реестр вне `docs_paths`/не менявшийся — предупреждение | T10, T13, T41 (B5), T42, T47, T49, T53, T54, T66 |
| A12 | Без мандата `/sdx:pr` — одна строка отказа; прочие команды и тесты 2.4.0 не меняют поведения | T60, T61, T63, T64, T65, T80, T81 |
| A13 | `artifact.offer` и `patch\|worktree` — поведение моста 2.4.0 сохранено; в `artifact.offer` нет поля `change` | T60, T61, T63, T64, T66, T70, T80, T81 |
| A14 | `CHANGE.template.yaml` в `sdx/mo/`, хеш в `SIMKIT_SHA256`, сторож инвентаря зелёный на пяти поверхностях; `CONTRIBUTING-MO.md` не ломает сторож | T01–T04, T21, T69, T80 |
| A15 | Протокол, `archive.md`, ADR, сниппет, `devops.md`, README×2, `CLAUDE.md`, дельты `mo-interop`, версия 2.5.0 согласованы; сторожа прозы зелёные | T66, T69–T76, T81 |
| A16 | Полный прогон укладывается в таймаут stop-gate с запасом; новые сьюты не используют внешнюю копию sim-kit и живой `audit()` | T21 (база), T77, T78, T79 (п.8), T18 (оракул — транслитерация, не вызов) |

## Сверка покрытия по REQ-PKG

| REQ-PKG | Задачи | REQ-PKG | Задачи |
|---|---|---|---|
| 1 | T64, T65, T66 | 19 | T32–T38, T41 |
| 2 | T60, T61, T63, T64, T65 | 20 | T32–T35, T38 |
| 3 | T64, T65 | 21 | T32, T34–T36, T38 |
| 4 | T10, T11, T14, T15, T35, T37 | 22 | T35, T70 |
| 5 | T07, T08, T10–T12, T14, T39, T40, T48 | 23 | T22–T31, T64, T67 |
| 6 | T39–T41 | 24 | T25, T27, T67 |
| 7 | T10, T14, T39, T40, T65 | 25 | T24, T28–T31, T67, T68 |
| 8 | T41, T43–T46, T52 | 26 | T10, T13, T42, T47, T49, T53, T66 |
| 9 | T41–T46, T53 | 27 | T10, T12, T47, T49, T54 |
| 10 | T07, T08, T24, T25, T39, T43, T44, T57, T58 | 28 | T01–T03, T80 |
| 11 | T05, T06, T16, T18–T20, T47–T54 | 29 | T01, T04, T69, T73 |
| 12 | T41, T42, T47, T49, T51, T53 | 30 | T64, T66, T70, T74, T81 |
| 13 | T64, T65 (проза P8, «в любом gate_mode», трейлеры К-2) | 31 | T71 |
| 14 | T07, T09, T55, T56, T59 | 32 | T69, T72 |
| 15 | T09, T55, T56 | 33 | T69, T70, T72–T76 |
| 16 | T09, T57–T59 | 34 | T60, T61, T63, T80, T81 |
| 17 | T60, T62, T65, T68 | 35 | T18, T55, T56, T58, T59, T65, T80 |
| 18 | T39, T40, T45, T55, T56, T65 | 36 | T77, T78, T82 |

Поправки SPEC К-1…К-12: К-1 — T02, T03 (+ T70, T80); К-2 — T62, T65 (трейлеры вместо `decisions_log.md`); К-3 — T40, T45, T56 (FF-цепочка, без force); К-9 — T67 (подтверждение `--from-issue` в любом `gate_mode`); К-10 — T77, T78; К-12 — T49 (`docs.final`); К-4…К-8, К-11, К-13…К-19 — реализуются по тексту DESIGN в соответствующих задачах (К-4 — T33, К-5 — T34/T36, К-6 — T62/T68, К-7 — T70, К-8 — T23, К-11 — T50/T65, К-13 — T12/T48, К-14 — T42/T49, К-15 — T39/T40, К-16 — T65, К-17 — T70, К-18 — T76, К-19 — T40).

## Отклонения при исполнении (фиксируются здесь, не сглаживаются)

Дорожка Ф (T01–T21), исполнитель Ф:

1. **`grep -nE 'python|eval'` по `pr-lib.sh` (DoD T14) не «пусто» буквально.** Находит имя функции `pr_scope_eval` (имя интерфейса из DESIGN/PLAN T12) и упоминания его в комментариях. Слов `python` и команды `eval` в файле нет; сьют проверяет `grep -nE 'py''thon|\bev''al\b'` (граница слова) — зелёный. Имя функции не менялось, чтобы не ломать интерфейс дорожек.
2. **Время (DoD «≤ N с»).** T15: `test-mandate-lib.sh` ~6,5 с → ~10 с (+3,5 с при пределе +3 с; из них ~2,1 с — собственно `[L11]` на мини-репозитории, ~1,2 с — 5 мутантов; мутант `PKG-SESSREV` идёт в сокращённом прогоне `MANDATE_MIN`). T20: `test-pkg-fixture.sh` ~3,9 с при пределе 3 с (16 пакетов × ~0,24 с на крафт и оракул). Сумма превышения (~1,4 с) уместилась в бюджет К-10: gate Ф 77 с.
3. **`[L9]` `test-mandate-lib.sh`** («нет python в `lib/*.sh`») переписан: `lib/pkg-fixture.sh` исключён по имени (тестовый помощник с python-оракулом, самопроверяется `test-pkg-fixture.sh`); остальные lib-файлы и `sdx-stage.sh` по-прежнему обязаны быть чистыми. Без этого T18 краснил бы существующий сьют.
4. **Коммит T08** оставил красной строку портируемости `[L10]` (слова-триггеры в комментарии шапки `pr-lib.sh`); исправлено в коммите T09 (шапка переписана). T08/T09/T11/T12 коммитились по DoD «целевые строки зелёные», а не «весь сьют зелёный» — DoD задач этого и требует.
5. **Уточнения интерфейса относительно DESIGN (библиотеки заморожены в таком виде):** `pr_registry <proj> <base> <head>` читает `$PR_FILES` (в DESIGN — `<files>`; нужен дифф для якорей) и отдаёт якоря целиком `<файл>#<TOKEN>`; `pr_session_rev` ищет по ветке `refs/heads/sdx/<sid>`, а не по `HEAD` (результат тот же при штатном состоянии); `pr_sess_cat` пересчитывает ревизию на каждый вызов (ветка двигается между шагами); `pr_order_load` возвращает rc 0/1/2 (снимок / нет снимка / не читается) и сохраняет `MY_NORM` вызвавшего (мандат остаётся загруженным); `pr_resolve` сам загружает мандат (`MANDATE_*` пригодны для `pr_scope_eval`), опционально выставляет `PR_DIGEST_DRIFT`, `PR_BASE_DRIFT`; `--title` явно побеждает название из снимка (явное решение пользователя), расхождение `--commitment`/`--base-name` со снимком — отказ; `pr_files` читает без обнаружения переименований (`--no-renames`) — обе стороны переименования попадают в область; `pr_url_show` для `ssh://` вырезает только `user:pass@`, для `http(s)` — весь userinfo; `pr_hosting` отдаёт значение переменной `PR_HOSTING`.
6. **`lib/pkg-fixture.sh`:** `pkg_fixture_template <workdir>` (шаблон создаётся под рабочим каталогом вызывающего, чистит его `trap`); экспортирует гермеричное окружение git (`GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=<tpl>/gitconfig`; локальные `user.name/email` в клоне); копия переписывает `origin` и добавляет `url.<копия>.insteadOf <шаблон>` (URL заказа в снимке — путь шаблона); сверх списка DESIGN добавлены виды `bad_branch` (имя вне `scope.branches`; ветку называет фабрика, см. `PKG_BRANCH_MADE`) и `no_adr` (оракул: `return adr`); `fake_scope` оракул **не** ловит по построению (аудит узла пересчитывает `scope_touched` сам) — ожидаемый ответ `approve`, ловит его `pr-check post` (`manifest.scope`, дорожка B). Оракульные ветки в моём прогоне PASS (python3, PyYAML 6.0.3); без PyYAML — rc 77 → INFO-skip у вызывающих.
7. **PLAN.md** актуализирован одним коммитом после T21 (не по задачам): галочки и счётчик.
8. **T02/T03:** упоминание в `sdx/mo/README.md` сделано в T02 (по плану), в пяти поверхностях и в `protocol.md`/`DECISIONS.md` (датированная оговорка К-1 без числа версии) — в T03.
9. **Прогон gate T21:** 20/20 сьютов, 77,1 с (real; user 32 с, sys 50 с; load average ~0,8 на старте), 19 прежних + `test-pkg-fixture.sh`; `__pycache__` в чекауте нет; `git status` чист. Ориентир feat-016 (123,9 с под нагрузкой / 19 сьютов) несопоставим по нагрузке; базовый прогон 19 сьютов до Ф на этой машине отдельно не замерялся — число 77,1 с служит базой К-10 для дорожек A/B/C (сьюты Ф вместе дают ≈ +14 с по замерам отдельных сьютов: test-mandate-lib +3,5 с, test-pkg-fixture ≈ 3,9 с, прочее — mo-inventory и т. п.).
