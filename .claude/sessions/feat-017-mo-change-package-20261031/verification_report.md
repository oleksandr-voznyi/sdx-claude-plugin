# Verification Report: feat-017-mo-change-package-20261031

## Сводка
- Объём: полный (SPEC REQ-PKG-1…36 + поправки К-1…К-12, DESIGN D-1…D-12 / К-1…К-19, PLAN 82 задачи), no_code: нет
- Итог: FAIL
- Находки: FAIL: 1, WARN: 13, INFO: 8
- Вход: `SPEC.md`, `DESIGN.md`, `PLAN.md` (раздел «Отклонения»), `decisions_log.md`, `delivery.diff` (43 файла, против `main`, без каталога сессии), эталон: вендорённые `sdx/mo/CHANGE.template.yaml` и `MO-INTEROP.md` §6–§7, рабочая копия `sim-kit/core/dev.py` (`audit()`, `manifest_of()`, `archive_sha()`, `hosting()`, `order()`, `protocol_check()`), ответ владельца МО от 28.10.
- Оговорка о покрытии: покрытие выведено из чтения diff и тестов, это **видимое** покрытие, а не доказательство. Сьюты я не запускал (Bash у ревьюера нет); итог «25/25 зелёные, 117,7 с» взят из PLAN T77 и исполнением не проверен.

### Сводка по осям
| Ось | Итог | Коротко |
|---|---|---|
| Полнота | WARN | Все REQ-PKG-1…36 прослеживаются в код или прозу. Не хватает: подтверждения `--from-order` в `auto` в прозе `start.md` (REQ-23), релизных заметок 2.5.0 (REQ-33, отложены на Closeout), автотестов на поведенческие критерии (только проза и ручной сценарий). Вне SPEC/DESIGN в поставку попало исправление DEBT-046. |
| Корректность | **FAIL** | Безопасность git-операций соблюдена: plumbing без касания дерева, индекса и HEAD, CAS через `update-ref`, явный refspec, нет force, есть whitelist и prod-guard, учётные данные вырезаются. Блокер: в P7 `pr.md` нет `--commitment`/`--title`, поэтому ручной режим без заказа (REQ-PKG-7) детерминированно падает на `FAIL id.commitment`. Также WARN: инструкция «откройте PR вручную» для хостинга `bare`; символы C1 в путях делают манифест неразбираемым для узла; отказ в push держится только на прозе. |
| Когерентность | WARN | Протокол, `archive.md`, `pr.md`, `devops.md`, сниппет, ADR-021/022, дельты `mo-interop`, README×2 и `CLAUDE.md` в целом согласованы. Мост для `pr|branch` снят, для `artifact.offer`/`undefined` сохранён. Числа версии sim-kit в документах нет, К-1 оформлена датированным отступлением. Остались дрейфы: REQ-26 против К-12 (ветка WARN недостижима), `[триаж]` в `auto`, REQ-36 в дельте, сниппет оказался надмножеством §6, неточная ссылка в `CONTRIBUTING-MO.md`. |

## Матрица трассируемости
| Требование / критерий | Реализация (файл) | Тест | Когерентность | Статус |
|---|---|---|---|---|
| REQ-PKG-1 `/sdx:pr`, делегирование из `archive.md` | `commands/pr.md`; `commands/archive.md` (шаг 2а, `bridge`) | `test-mo-prose [19][20]` (проза) | ok | OK |
| REQ-PKG-2 условия входа, отказ одной строкой | `mandate-info.sh pr-mode`; `pr.md` P0–P1 | `test-mandate-scope [M] pr-mode` + мутанты `PKG-PRMODE-*`; `[20]` | ok | OK |
| REQ-PKG-3 порядок конвейера | `pr.md` P2–P10 | `[20]` (порядок P0…P10) | ok | OK |
| REQ-PKG-4 данные заказа после шага 5 | `pr_session_rev`/`pr_sess_cat`/`pr_order_load` (`lib/pr-lib.sh`) | `test-mandate-lib [L11]` + `PKG-SESSREV`; `test-protocol-export X9` | ok | OK |
| REQ-PKG-5 имя `change/<C>-<exec>`, алфавит, `base`, расхождение | `pr_valid_id`, `pr_resolve`, `pr_base_ref`; `pr-build.sh` (`NEED allow-diverged`) | `[L10]`, `test-pr-build B7/B9`, `test-pr-check C2/C3` | ok | OK |
| REQ-PKG-6 один squash-коммит, сообщение `<C>: <title>` | `pr-build.sh` (commit-tree) | `B1`, `B8a`, `B11` | ok (К-3: при повторной сдаче FF-цепочка) | OK |
| REQ-PKG-7 `<C>` аргументом без заказа | `pr_resolve --commitment`; `pr.md` P1/P5/P6/P9 | `[L11]` resolve без снимка, `B7` | **дрейф: P7 не передаёт `--commitment`/`--title`** | **FAIL** |
| REQ-PKG-8 манифест отдельным коммитом, без записи в дерево | `pr-build.sh` (временный индекс, `update-ref` с CAS) | `B2`, `B12`, `PKG-PLUMB`, `PKG-TIPPARENT`, `PKG-CAS` | ok | OK |
| REQ-PKG-9 поля манифеста | `pr-build.sh` (обход шаблона, `jq`) | `B1`, `B3`–`B5`, `B10` + мутанты | ok | OK |
| REQ-PKG-10 экранирование, без секретов | `jq tojson`, `pr_clean`, `pr_has_secret`; `gh` с аргументами массивом | `B6`, `B7`, `P5`, `O6`, `C7` | граница: символы C1 | WARN |
| REQ-PKG-11 `pr-check` (а–и), зеркало `audit()` | `pr-check.sh` pre/post | `C1`–`C7`, оракул `pkg_oracle`, паритет `C6` | блокировка только в прозе | WARN |
| REQ-PKG-12 nonempty, показ `touches_shared` | `diff.nonempty`, `pkg.nonempty`, `shared.note`, `manifest.shared`; P8 | `C2`, `C5`, `B4` | ok | OK |
| REQ-PKG-13 подтверждение в любом `gate_mode` (К-2: трейлеры) | `pr.md` P8, P9 | `[20]` (только проза) + ручной сценарий, случай 5 | ok | WARN (только вручную) |
| REQ-PKG-14 явный refspec, без `sdx/*`, без force | `pr-publish.sh` | `P1`, `P2`, `P3`, `[Port]` + `PKG-P-REFSPEC/NOFOLLOW/FF` | ok | OK |
| REQ-PKG-15 `bare`: `repo.url` или `origin` | `pr-publish.sh` | `P1`, `P4`, `P6` | **инструкция «PR вручную» для bare** | WARN |
| REQ-PKG-16 `github`, `gh`, деградация | `pr-publish.sh gh_step` | `P5a–g` + `PKG-P-GH`; ручной сценарий, случай 2 | для `delivery: branch` PR не создаётся — решения нет в DESIGN | WARN (слито с W1) |
| REQ-PKG-17 запись результата (К-16) | `pr.md` P9; `mandate-info.sh pr-status`; `status.md` 5б | `test-mandate-scope [M] pr-status`, `[26]` | ok | OK |
| REQ-PKG-18 повторная сдача | `pr-build --resubmit`, FF в `pr-publish` | `B8a`, `P3` | ok | OK |
| REQ-PKG-19–22 `protocol.yaml` | `protocol-export.sh` | `X1`–`X9` + мутанты, оракул `protocol_check()` | ok (К-4, К-5) | OK |
| REQ-PKG-23 `--from-order`, `[директива]` в `auto`, MISMATCH | `order-import.sh`; `start.md` 1б | `O1`–`O5` + мутанты; `[26]` | **для `--from-order` в `auto` подтверждение не прописано** | WARN |
| REQ-PKG-24 `--from-issue` (К-9) | `order-import.sh from-issue`; `start.md` 1б (iii) | `O4` + `PKG-O-FENCE` | ok | OK |
| REQ-PKG-25 `commitment`, снимок, `sid_infix` | `order-import.sh stamp-state`; `start.md` 2/6а | `O7`, `test-sdx-stage [42]` + `WRITE-STAGE-COMMITMENT` | ok | OK |
| REQ-PKG-26 `docs_in_repo`, реестр ADR | `pr-check` (`adr.registry`, `manifest.adr`), `pr-build` (`adr`), `pr.md` P2 | `C3`, `B5`, `PKG-C-ADR` | **ветка «вне `docs_paths` → WARN + подтверждение» недостижима (К-12)** | WARN |
| REQ-PKG-27 документы вне `docs_paths` (К-12) | `pr-check docs.final` | `C2` + `PKG-C-DOCS-FINAL` | ok | OK |
| REQ-PKG-28 вендоринг `CHANGE.template.yaml` (К-1) | `sdx/mo/CHANGE.template.yaml`, `SIMKIT_SHA256`, пять поверхностей | `test-mo-inventory [13][14]` | ok (оговорка К-1 есть в протоколе и ADR-013) | OK |
| REQ-PKG-29 `CONTRIBUTING-MO.md` | `sdx/templates/CONTRIBUTING-MO.md` | `[27]`, `test-mo-inventory [14]` | неточная ссылка на шаблон | WARN |
| REQ-PKG-30 два варианта Closeout, мост снят для `pr|branch` | `protocol.md`, `archive.md` | `[12]`, `[19]`, `[21]` | ok | OK |
| REQ-PKG-31 ADR-022 | `docs/DECISIONS.md` | `[23]` | ok | OK |
| REQ-PKG-32 сниппет = §6 | `claude-md-snippet.md` | `[11]`, `[22]` (проверка вхождения) | надмножество §6 | WARN |
| REQ-PKG-33 devops, README×2, CLAUDE.md, дельты, версия, релизные заметки | соответствующие файлы, `plugin.json` 2.5.0 | `[17]`, `[24]`, `[25]` | **нет `docs/history/releases/v2.5.0-notes.md`** | WARN |
| REQ-PKG-34 обратная совместимость | `pr-mode`; `archive.md standard` бит в бит; `start.md` без флагов | `[19]` (шаги 1–8), `[26]`, прежние сьюты | ok | OK |
| REQ-PKG-35 запреты | `pr.md` «Запреты»; `pr-publish` | `[20]`, `P1`–`P3`, `[Port]` | ok | OK |
| REQ-PKG-36 параллельный раннер при >150 с (К-10) | не понадобился (117,7 с) | — | дельта `mo-interop` пересказывает иначе | WARN |
| Критерий 1: фикстура, паритет с `audit()` | `pr-build` + `pr-check` | `B1`, `C4`, `C6` (оракул) | ok | OK |
| Критерий 2: красные стороны `pr-check` (9 видов) | `pr-check.sh` | `C2`, `C5` + `PKG-C-*` | ok | OK |
| Критерий 3: дерево не трогается | `pr-build.sh` | `B2` | ok | OK |
| Критерий 4: `archive_sha256` в независимом клоне | `pr-build.sh` | `B3` | ok | OK |
| Критерий 5: `touches_shared`, `scope_touched` | `pr-build.sh` | `B4` | ok | OK |
| Критерии 6–7: `protocol.yaml`, `adr: true/false` | `protocol-export.sh` | `X1`–`X6` | ok | OK |
| Критерий 8: push без подтверждения не выполняется | `pr.md` P8 | только проза + ручной сценарий, случай 5 | — | WARN |
| Критерий 9: `github` без/с `gh` | `pr-publish.sh` | `P5` | ok | OK |
| Критерий 10: `--from-order`/`--from-issue` | `order-import.sh`, `start.md` | `O3`–`O5`, `O7` | см. REQ-23 | WARN |
| Критерий 11: `docs_in_repo` | `pr-check`, `pr-build` | `C2`, `C3`, `B5` | см. REQ-26 | WARN |
| Критерии 12–13: без мандата; `artifact.offer`/`patch` | `pr-mode`, `archive.md` | `[M]`, `[19]` | ok | OK |
| Критерий 14: вендоринг и сторож | `sdx/mo/` | `test-mo-inventory` | ok | OK |
| Критерий 15: согласованность прозы | см. REQ-30…33 | `[11]`–`[27]` | частично | WARN |
| Критерий 16: бюджет и отсутствие живого `audit()` | `verify-cmd.sh` (комментарий) | замер T77, ручной сценарий, случай 8 | ok | OK |

## Находки

### [FAIL] [Корректность] `pr.md` P7 вызывает `pr-check --phase post` без `--commitment`/`--title`: ручной режим без заказа (REQ-PKG-7) всегда блокируется
- Где: `commands/pr.md:28` (P7). Сравни с P5 (`:24`), P6 (`:26`), P9 (`:32`): там `[--commitment <C>] [--title "<T>"]` передаются. Код: `sdx/hooks/pr-check.sh` → `pr_resolve` (`lib/pr-lib.sh`, `pr_resolve`: «commitment: не задан (нет снимка заказа и аргумента)», затем «title: не задан»), `finish` с rc 1.
- Суть: REQ-PKG-7 допускает сдачу без заказа: `<C>` и заголовок приходят аргументами команды. `pr-check.sh` в любой фазе сначала вызывает `pr_resolve`. Без снимка `order.yaml` и без `--commitment`/`--title` он выдаёт `FAIL id.commitment`, а следом `finish` (rc 1). P7 по тексту команды предписывает на rc 1 «стоп, пакет НЕ публиковать». Значит, конвейер в том виде, как он записан в носителе, не может завершиться в сценарии REQ-PKG-7: проза утверждает путь, который код при её же вызове не проходит. Тесты этого не ловят: `test-pr-check` всегда работает с фикстурой со снимком заказа, `[20] chk_flags` проверяет только существование флагов, а не их передачу.
- Ожидалось: P7 вызывает `pr-check.sh --sid <sid> --phase post [--commitment <C>] [--title "<T>"]` так же, как P5, P6 и P9.
- Фактически: `pr-check.sh --sid <sid> --phase post` без этих аргументов.
- Исправление: добавить в P7 `[--commitment <C>] [--title "<T>"]` (и при желании прогон post в `test-pr-check` на фикстуре без `order.yaml` с аргументами). Как вариант, `pr-check post` может не требовать `title`, но `commitment` ему нужен всё равно.

### [WARN] [Корректность/Когерентность] Шаг PR в `pr-publish.sh` по хостингу и `delivery`: для `bare` выдаётся «Откройте PR вручную», для `github` + `delivery: branch` PR не создаётся. Ни то, ни другое не задано в SPEC/DESIGN
- Где: `sdx/hooks/pr-publish.sh:164` (`if [ "$hosting" = github ]; then gh_step; else instruction="$instr"; fi` под условием `PR_DELIVERY = pr`), `:141`; тест `test-pr-publish P5g`.
- Суть: REQ-PKG-15 говорит, что для `bare` пакет готов, когда ветка в репозитории и `CHANGE.yaml` лежит в корне вершины. Узел (`dev.py Bare.offers`) читает ветки, PR на `bare` не существует. А `pr.md` P10 выводит пользователю строку `instruction`, то есть в `bare` + `delivery: pr` пользователю велят «открыть PR вручную». Инструкция вводит в заблуждение. Отдельно: в `github` + `delivery: branch` PR не создаётся. Решение разумное, но в SPEC REQ-16 и DESIGN («При github: …») его нет.
- Ожидалось: для `bare` `instruction` = null (или нейтральная строка «пакет готов: ветка … в …»); правило «PR только при `delivery: pr`» записано в DESIGN/протоколе.
- Фактически: инструкция «PR вручную» на `bare`; правило по `delivery` есть только в коде и тесте.

### [WARN] [Когерентность] REQ-PKG-26 «реестр вне `docs_paths` → предупреждение, сдача после подтверждения» на деле недостижим
- Где: `sdx/hooks/pr-check.sh:193` (`docs.final` FAIL), `:202` (`adr.registry` WARN «вне docs_paths»); `lib/pr-lib.sh` `pr_registry` (кандидаты только под `docs/`); `test-pr-check C3 regpath` закрепляет «WARN + FAIL одновременно»; PLAN, «Отклонения B».
- Суть: `pr_registry` ищет реестр только под `docs/`. Если реестр лежит под `docs/` вне `docs_paths`, это одновременно «документ вне `docs_paths`», и по К-12 получается `FAIL docs.final`. Ветка WARN с подтверждением из REQ-26 (и §3 п.3 ответа МО) поэтому никогда не даёт сдать пакет. Поведение совпадает с узлом (тот отверг бы файл вне области по `scope`), но текст REQ-PKG-26 в поправках SPEC не уточнён: SPEC и код расходятся без явной записи.
- Ожидалось: поправка REQ-PKG-26 в SPEC (раздел «Поправки по коллизиям») вида «при К-12 реестр под `docs/` вне `docs_paths` — FAIL; WARN только для реестра вне `docs/`», либо поиск реестра и вне `docs/`.
- Фактически: разрешено только кодом и тестом, в SPEC/DESIGN не отражено.

### [WARN] [Корректность] «`pr-check` блокирует push» держится только на прозе: `pr-publish.sh` пакет перед отправкой не проверяет
- Где: `sdx/hooks/pr-publish.sh` (нет ни вызова `pr-check --phase post`, ни сверки `tip` с проверенным); `commands/pr.md:28`, `:32`.
- Суть: REQ-PKG-11 и D-7 обещают «push блокируется без права обхода». На деле блокировка — это порядок шагов в `pr.md`. `pr-publish.sh` отправит любую вершину `change/*`, включая ту, что упала на P7, или ветку, которую изменили между P7 и P9. Сам скрипт защищает refspec, URL и FF, но не содержимое пакета.
- Ожидалось: `pr-publish.sh` сам выполняет минимальную пост-проверку (`manifest.commit`, `manifest.archive`) либо принимает `--expect-tip <sha>` из JSON `pr-build`. Или в DESIGN явно названа граница «блокировка — прозой».
- Фактически: граница нигде не названа.

### [WARN] [Полнота] REQ-PKG-23: подтверждение приёма `--from-order` в `gate_mode: auto` (`[директива]`) не прописано в `start.md`
- Где: `commands/start.md:22` (шаг 1б (iii) — только про `--from-issue`); DESIGN, `start.md` (iii): «`gate_mode: auto` (директива) **и** `--from-issue` → AskUserQuestion».
- Суть: SPEC и DESIGN требуют, чтобы в `auto` приём заказа через `--from-order` (файл или конверт `directive`) подтверждал пользователь. В прозе команды это есть только для `--from-issue`. Частично перекрывается общим правилом протокола (`sdx/protocol.md:215`: директива в `auto` не принимается дефолтом), но шаг команды его не операционализирует, а тест `[26]` проверяет `AskUserQuestion` лишь в блоке 1б целиком.
- Ожидалось: в (iii) добавлено «при `gate_mode: auto` и `--from-order` — `AskUserQuestion` (`[директива]`)».

### [WARN] [Когерентность] В `auto` на P5 часть WARN принимается молча с тегом `[триаж]`
- Где: `commands/pr.md:24` (P5: «прочие WARN принимаются как `[триаж]`»); PLAN, «Отклонения C» («сверх DESIGN»).
- Суть: протокол определяет `[триаж]` как **явный** акт пользователя по находке. Здесь им помечено авто-принятие `adr.registry`/`tests`/`attrs.export`/`mandate.lint` без вопроса, а REQ-PKG-26 требует «явного подтверждения» именно для `adr.registry`. Частично смягчено тем, что P8 показывает список принятых WARN и в любом режиме спрашивает «Отправить?». Решения нет в DESIGN.
- Ожидалось: решение внесено в DESIGN/протокол с другой меткой (например, «авто-дефолт, раскрыт на P8»), либо `adr.registry` выведен из авто-принятия.

### [WARN] [Корректность] Символы C1 (U+0080…U+009F, кроме U+0085) в путях и `--notes` попадают в `CHANGE.yaml` как есть, и узел не разберёт манифест
- Где: `sdx/hooks/lib/pr-lib.sh:239` (`pr_files`: `[[:cntrl:]]` под `LC_ALL=C` ловит только C0/DEL), `pr_clean` (вырезает только U+2028/2029/0085), `sdx/hooks/pr-build.sh:174` (`sc`: `jq tojson` оставляет C1 неэкранированными).
- Суть: `yaml.safe_load` узла (`manifest_of`) отвергает непечатаемые символы C1 (`ReaderError`) и даёт `reject manifest`. При этом `pr-check post` на `miniyaml` проходит, то есть зеркало ослаблено. Для `protocol.yaml` автор диапазон учёл (`protocol-export.sh`, `cl`: `\u007f-\u009f`), для манифеста — нет. Случай экзотический (имена файлов, ручной `--notes`).
- Ожидалось: `pr_files` отвергает пути с байтами C1 (как с управляющими символами), `pr_clean`/`sc` вырезают C1. Тест с путём, содержащим U+0086.

### [WARN] [Корректность/Тесты] `test-sdx-stage [43]` и мутант `STRAY-FALSE` пишут и удаляют `$PWD/false` в каталоге запуска, то есть в чекауте
- Где: `sdx/hooks/test-sdx-stage.sh:1089`, `:1096`, `:1127`.
- Суть: `run_stage` не меняет каталог. Мутант по замыслу создаёт файл `false` в cwd, а под `verify-cmd.sh` cwd — корень репозитория. Сьют безусловно делает `rm -f "$PWD/false"`, то есть удаляет и пользовательский файл с таким именем. Это нарушает норму «сьюты не пишут в чекаут», которую соблюдают все новые сьюты.
- Ожидалось: блок `[43]` и мутант запускаются из `cd "$(mktemp -d)"` (подоболочка), проверка `[ ! -e false ]` — там же.

### [WARN] [Полнота] В поставке исправление DEBT-046 (`sdx-stage.sh`) и удаление файла `false`, не прослеживаемые к SPEC/DESIGN
- Где: `sdx/hooks/sdx-stage.sh:364` (текст отказа), удалённый `false` (diff), `test-sdx-stage [43]`; DESIGN «`sdx-stage.sh` … не меняются»; PLAN, «Отклонения — Оркестратор», T80.
- Суть: правка маленькая и обоснованная (ветка `DEBT-046` в бэклоге есть), но DESIGN прямо обещает «`sdx-stage.sh` не меняется». Решение есть только в PLAN, в SPEC/DESIGN/`change_note` его нет. Это scope creep, хоть и задокументированный.
- Ожидалось: строка в DESIGN («Обратная совместимость», отступы) или в дельтах `mo-interop`/релизных заметках с отсылкой к DEBT-046, плюс закрытие записи DEBT-046 на Closeout.

### [WARN] [Полнота] Двуязычных релизных заметок 2.5.0 в поставке нет (REQ-PKG-33)
- Где: нет `docs/history/releases/v2.5.0-notes.md` (DESIGN, список файлов и «Перечень правок документов»). Есть только черновик в каталоге сессии (`release_notes_draft.md`), публикация запланирована как PLAN C3 на Closeout.
- Суть: REQ-PKG-33 требует заметки как часть поставки. Перенос на Closeout допустим, но сейчас требование не закрыто.
- Ожидалось: на Closeout заметки (русский блок, `---`, английский; «Границы» с непроверенным, DEBT-046) публикуются, C3 отмечается.

### [WARN] [Полнота] Поведенческие критерии проверены только прозой: нужен ручной сценарий
- Где: критерий 8 (без подтверждения push не выполняется ни в `standard`, ни в `auto`), REQ-PKG-13, паритет с живым `audit()`, `gh` на реальном GitHub, хук области на командные строки `/sdx:pr`, проза `archive.md` → `pr.md`. В `MANUAL_TEST.md` это случаи 1, 2, 4, 5 (результаты пока не заполнены).
- Суть: автотесты закрепляют только текст (`test-mo-prose [20]`) и транслитерацию оракулом. Это видимое, а не доказанное покрытие.
- Ожидалось: квитирование пользователем либо заполнение случаев 1/2/4/5 до гейта.

### [WARN] [Когерентность] Сниппет — не «полный текст §6», а надмножество: §6 плюс добавочное предложение
- Где: `sdx/templates/claude-md-snippet.md:11`; `test-mo-prose [22]` (`chk_snippet_interop` проверяет вхождение `grep -F`); DESIGN «сниппет = текст §6 (сравнение …)»; PLAN «Отклонения T70–T74».
- Суть: REQ-PKG-32 говорит «абзац заменяется полным текстом §6». Фактически это §6 плюс предложение про `PYTHONDONTWRITEBYTECODE=1` и `self_deploy`. Содержательно это сохраняет нормы 2.4.0, но расходится с буквой SPEC/DESIGN, а сторож ослаблен до проверки вхождения.
- Ожидалось: поправка SPEC/DESIGN («§6 + сохранённые нормы 2.4.0») или вынос добавки отдельным пунктом сниппета.

### [WARN] [Когерентность] Дельта `docs/specs/mo-interop.md` пересказывает REQ-PKG-36 иначе, чем SPEC
- Где: `docs/specs/mo-interop.md:179` («REQ-PKG-36 — полный прогон тестов в пределах таймаута stop-gate (цель ≤ 150 с)»).
- Суть: в SPEC (поправка К-10) REQ-PKG-36 звучит как «при полном прогоне > 150 с допускается параллельный раннер `SDX_VERIFY_JOBS`». Постоянный документ передаёт другой смысл: критерий приёмки вместо разрешённого рычага.
- Ожидалось: формулировка, совпадающая с SPEC (плюс «не понадобился, 117,7 с»).

### [WARN] [Когерентность] `CONTRIBUTING-MO.md` неточно указывает, где лежит шаблон
- Где: `sdx/templates/CONTRIBUTING-MO.md:7` («шаблон `CHANGE.template.yaml` (sim-kit, лежит рядом с этим документом в поставке)»).
- Суть: шаблон лежит в `sdx/mo/CHANGE.template.yaml`, документ — в `sdx/templates/`. DESIGN требует ссылку на `sdx/mo/CHANGE.template.yaml`. Если человек скопирует документ к заказчику, он будет искать шаблон рядом.
- Ожидалось: явный путь `sdx/mo/CHANGE.template.yaml` плагина (или «приложите шаблон рядом при копировании»).

### [INFO] [Корректность] Рабочая копия эталона sim-kit ушла к 0.9.3: в `audit()` появились проверки, которых нет в зеркале 0.9.1
- Где: `sim-kit/core/dev.py:386–410` (`work_paths` по умолчанию `.claude/sessions/**`, `docs_in_repo.work`, `docs_in_repo.none` с уровнем `return`, `adr` для `final` **и** `full`). Оракул `lib/pkg-fixture.sh pkg_oracle` и `pr-check.sh` транслитерируют 0.9.1.
- Суть: контракт сессии — 0.9.1, это не находка. При перевендоринге `pr-check` нужно дополнить: при `none` документы в пакете → WARN/FAIL, `work_paths`. `manifest.adr` уже проверяется для `final|full`, что строже 0.9.1 и совпадает с 0.9.3.

### [INFO] [Корректность] Осознанные ослабления зеркала `audit()`
- Где: `pr-check.sh:329` (`manifest.adr` — WARN, у узла `return`), нет проверки секретов в **диффе** (у узла `secrets` = `reject`; Q-13 SPEC); `commitment` по реестру узла и `mandate.repo` проверить нельзя.
- Суть: решения приняты в SPEC (REQ-26, Q-13). Замечу, что `DEFAULT_REDACT` исполнителю доступен (тот же набор, что `REDACT` вендорённого `mesh_endpoint.py`, оракул его использует), так что зеркало `secrets` по диффу технически возможно — кандидат в IDEA.

### [INFO] [Когерентность] Поиск реестра ADR уже, чем §7 `MO-INTEROP.md`
- Где: `lib/pr-lib.sh` `pr_registry` (`docs/DECISIONS.md` либо единственный `docs/**/{DECISIONS,decisions}*.md`); `MO-INTEROP.md:127` («имя файла не фиксируется — любой путь из `docs_paths`»).
- Суть: соответствует дефолту Q-7 SPEC. Проекты с реестром вида `docs/adr/0001-*.md` получат `WARN adr.registry`, `adr: []`, и узел вернёт пакет.

### [INFO] [Безопасность] Для именованного remote не нейтрализованы `remote.<name>.mirror` и `push.recurseSubmodules`
- Где: `sdx/hooks/pr-publish.sh:128` (`-c push.followTags=false -c push.default=nothing` есть, `-c push.recurseSubmodules=no` нет; при `remote.<n>.mirror=true` git выставляет флаг force).
- Суть: явный refspec и предварительная FF-проверка через `ls-remote` практически закрывают риск. Это оборона в глубину, не дыра.

### [INFO] [Когерентность] Мелкая редактура носителей
- `docs/DECISIONS.md:991`/`:993`: после ADR-022 два разделителя `---` подряд.
- `sdx/protocol.md:476`: «шаги 6–8 отмечаются `(n/a, мандат)` (в команде `/sdx:pr` — `(n/a, пакет)`)» при «Вариант „пакет“ — `bridge` (любой определённый `delivery`)». По смыслу совпадает с `archive.md`/ADR-022, но формулировка смешивает `bridge:offer` с пакетом.
- `pr-check.sh:329`: текст «adr пуст при docs_in_repo: final» выводится и при `full`.

### [INFO] [Тесты] `test-mo-inventory [13]` закрепляет `SIMKIT_VERSION = 0.9.1` и хеш шаблона второй копией
- Где: `sdx/hooks/test-mo-inventory.sh:251`, `:259`.
- Суть: PROC-028 п.2 («число только в `SIMKIT_VERSION`») касается документов, не тестов, и в документах числа нет. Но при перевендоринге этот блок придётся править вручную, а хеш дублирует `SIMKIT_SHA256`.

### [INFO] [Когерентность] `order-import.sh` без локального мандата принимает заказ (rc 0, предупреждение)
- Где: `sdx/hooks/order-import.sh` `oi_mandate_check`; PLAN, «Отклонения A». В DESIGN сверка с мандатом описана как обязательная (код 3).
- Суть: защищено шагом `start.md` 1б (i) (без `pr-mode OK` — отказ до вызова скрипта). Расхождение скрипта с DESIGN задокументировано только в PLAN.

### [INFO] [Корректность] Подтверждённые сильные места (свежим взглядом)
- `pr-build.sh`: дерево squash берётся из вершины `sdx/<sid>` либо из `merge-tree --write-tree` (только с `--allow-diverged`). Манифест собирается через временный `GIT_INDEX_FILE`, `commit-tree -p head`, `update-ref <new> <old|нули>`. Перед сборкой есть отказы: каталог сессии в дереве, корневой `CHANGE.yaml` в коде, пустой дифф, секрет в путях/заголовке/notes. `archive_sha256` считается от `head` с закреплённым `tar.umask`. Ключи и их порядок берутся из вендорённого шаблона, неизвестный ключ ведёт к отказу.
- `pr-publish.sh`: публикуется только `change/*`, refspec `B:B` без `+`, `GIT_ALLOW_PROTOCOL`, `GIT_TERMINAL_PROMPT=0`, `BatchMode`, whitelist URL (отказ на `ext::`/`fd::`/ведущий `-`/пробел), prod-guard на синтезированной команде, `--dry-run` без сети. Учётные данные вырезаются (`pr_url_show`, `scrub`), `gh` вызывается с аргументами массивом, тело PR проверяется на секреты до сети.
- Чужие данные (заказ, issue, трейлеры, мандат) проходят `pr_clean`/`jq tojson`/алфавит `safe`. `eval` нет, у заказа есть лимит 64 КиБ.
- `protocol.yaml`: пять списков всегда, у `decisions[]` поля `{id,what,why}` непусты по построению. Схема проверяется оракулом `protocol_check()` (сверено с `dev.py:589–607`).
- Структура снимка `order.yaml` и поля, которые читает `order-import`, сверены с `dev.py order()` (`action`, `format`, `commitment{id,kind,title,requirements,due,…}`, `executor`, `mandate`, `mandate_digest`, `repo{id,url,base}`, `deliver{branch,delivery}`).
