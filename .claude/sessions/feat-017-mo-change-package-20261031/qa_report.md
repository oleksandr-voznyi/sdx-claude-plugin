# QA report: feat-017-mo-change-package-20261031 (2.5.0, /sdx:pr)

Дата: 2026-10-31. Роль: qa (корректность исполнением). В репозиторий ничего не менялось; все мутанты и сквозные прогоны — во временных копиях (scratchpad), `__pycache__` в плагине нет, `git status` чекаута чист (кроме `verification_report.md` ревьюера, появившегося параллельно).

## 1. Полный прогон

`bash .claude/sdx/verify-cmd.sh`: `Summary: 25/25 suites passed`, 0 failed.
Время (предел stop-gate 180 с, критерий SPEC/DESIGN «с запасом» <= 150 с без нагрузки):
- прогон 1: 171,9 с real (load average ~7-16 от фоновых процессов хоста) — запас 8 с;
- прогон 2: 149,4 с real (load ~6-10).
Замер в `verify-cmd.sh` (117,7 с при load 0,7) воспроизводится только на тихой машине; под нагрузкой запас тонкий (см. вывод В-3).

## 2. Матрица критериев A1-A16 (порядок записи в SPEC «Критерии приемки»)

| № | Критерий | Доказательство исполнением | Оценка |
|---|---|---|---|
| A1 | Пакет `/sdx:pr` проходит зеркало формальных проверок `audit()` | `test-pr-build` B1 (python-оракул `pkg_oracle` -> `approve`, встроенный негатив), `test-pr-check` C4, C6 (паритет оракул/`pr-check`); мой сквозной прогон: оракул `approve`. Живой `audit()` не запускается (ручной п.1 DESIGN) | покрыто; живой audit — только ручной |
| A2 | Красные стороны pre/post блокируют push | `test-pr-check` C2 (11 причин pre), C5 (13 `pkg_craft_bad_*`), C6; свои мутанты MC1a/b, MC3-MC6, MC9 убиты; сквозной: `diff.scope` FAIL, `mandate.valid` FAIL, `docs.final` FAIL | покрыто |
| A3 | `CHANGE.yaml` не пишется в дерево; дерево чистое, ветка `sdx/<sid>` | `test-pr-build` B2 (+ `PKG-PLUMB`), B12; сквозной: HEAD/status/ls-files -s/ветка совпали до и после, `find` CHANGE.yaml пуст | покрыто |
| A4 | `archive_sha256` = sha256(git archive head), воспроизводим в независимом клоне | `test-pr-build` B3 (+ `PKG-ARCHIVE`); сквозной (r6): пересчёт в независимом `git clone` совпал (`2db81493...`) | покрыто |
| A5 | `touches_shared` оба исхода, `scope_touched` включает сгенерированное | B4 (+ `PKG-SHARED`, `PKG-SCOPE-TOUCHED`), C5 `shared_undeclared`; сквозной: `package-lock.json` в `scope_touched`, `touches_shared: true` | покрыто |
| A6 | `protocol.yaml`: пять списков, `decisions[]` с `id/what/why`, пустые источники -> пустые списки, в `change/*` файла нет | `test-protocol-export` X1-X4, X6, X8; B11 (дерево пакета без `.claude/sessions/` и `protocol.yaml`); сквозной: `python3 -I` + `yaml.safe_load` — ключи done/decisions/questions/verified/deltas есть, непустые `id/what/why` в обоих форматах журнала; `git ls-tree` пакета чист | покрыто |
| A7 | `adr: true/false` по упоминанию ADR | X5 (+ `PKG-X-ADR`), мутант MX5 убит; сквозной: запись «ADR-022» -> `true`, без -> `false` | покрыто |
| A8 | Нет push без подтверждения; явный refspec; `sdx/*` не уходит | refspec/NOFOLLOW/FF/URL: `test-pr-publish` P1-P3, P6 (+ мутанты), мой MP1 (убран guard `change/*`) убит; сквозной: на удалённой стороне только `change/...` и `dev`, тегов нет. Подтверждение пользователя — ТОЛЬКО проза: пин `test-mo-prose [20]` («в любом gate_mode», `AskUserQuestion`) + ручной п.5 | refspec — исполнением; подтверждение — только проза/ручной |
| A9 | `github` без `gh`: push + одна строка, не отказ; с `gh` — PR против `repo.base` | `test-pr-publish` P5 a-g (argv-стаб `gh`); сквозной (реальный push, PATH без `gh`, `--hosting github`): rc 0, `degraded: gh-missing`, `instruction`, ветка на remote. Живой `gh` — только ручной п.2 | покрыто стабом; живой GitHub — ручной |
| A10 | `--from-order` (файл и конверт), `commitment` в `session_state.json`/`order.yaml`, digest-несовпадение останавливает, `--from-issue` без `gh` отказывает | `test-order-import` O1-O7 (+ мутанты MO2-MO4 убиты); сквозной: `from-file` (дамп `yaml.safe_dump` с переносами) -> `--out order.yaml` -> `stamp-state` (остальные ключи сохранены). `--from-msg` с реальным `mesh_endpoint.py` — только ручной п.6 | покрыто; живой канал — ручной |
| A11 | `none`: `(n/a)`, дельты в `protocol.yaml`; `final`: нет документов вне `docs_paths`, `adr` непуст и в пакете; реестр вне/не менявшийся — предупреждение | B5, C2 (`docs.final`), C3 (`adr.registry`) (+ `PKG-C-ADR`, `PKG-C-DOCS-FINAL`); сквозной: реестр не менялся -> `WARN adr.registry` rc 3 и `adr: []`; реестр вне `docs_paths` -> FAIL `diff.scope`+`docs.final`, WARN `adr.registry`. Часть «`(n/a)` в Closeout» — проза | покрыто; проза Closeout — пины |
| A12 | Без мандата `/sdx:pr` — одна строка отказа; прочее как в 2.4.0 | `test-mandate-scope [M]` pr-mode (+ мутанты `PKG-PRMODE-*`, MM1-MM3 убиты); сквозной: `REFUSE no-mandate` rc 1, `pr-build/-check/-publish` без мандата rc 1 с причиной; все 25 сьютов 2.4.0 зелёные | покрыто |
| A13 | `artifact.offer` и `patch|worktree`: мост 2.4.0 сохранён; в `artifact.offer` нет поля `change` | `test-mandate-scope` closeout-mode, `test-mo-prose [12][12b][19]`; сквозной: `closeout-mode` = `bridge:offer`/`undefined:patch`/`undefined:worktree`, `pr-mode` REFUSE `delivery:<d>`. «Нет поля `change` в `artifact.offer`» — ни одного исполняемого теста (оффер формирует проза/`mesh_endpoint.py`) | мост — покрыто; «нет поля change» — только проза/ручной |
| A14 | `CHANGE.template.yaml` в `sdx/mo/`, хеш, сторож, `CONTRIBUTING-MO.md` не ломает | `test-mo-inventory` (c)/(d)/(e), `test-mo-prose [27]`; `sha256sum -c SIMKIT_SHA256` — 4xOK; sha256 вендорённого файла = sha256 из тега sim-kit-0.9.1 (`346d2e6e...`) | покрыто |
| A15 | Протокол/archive/ADR/сниппет/devops/README/CLAUDE.md/версия согласованы; сторожа прозы зелёные | `test-mo-prose [17][19]-[27]` (с красными сторонами на повреждённых копиях), `test-snippet-check`, `test-hook-wiring` — зелёные. Это сверка текста; поведение модели по `pr.md` исполнением не проверяется | покрыто пинами; поведение — ручной п.5 |
| A16 | Прогон укладывается в таймаут stop-gate с запасом; новые сьюты без внешнего sim-kit и живого `audit()` | 171,9 с и 149,4 с (см. §1); `grep` внешних путей в новых сьютах (`aibok`/`meta-orchestrator`) — только комментарий в `test-pkg-fixture.sh`; `audit()` реализован как независимый python-оракул | выполнено с тонким запасом при нагрузке |

## 3. Собственные мутанты (временные копии `sdx/`, harness в scratchpad; сьюты запускались в режиме NESTED без собственных мутационных секций)

Итог: 42 мутанта; убито 39, выжило 3 (из них 1 эквивалентный, 1 низкая значимость, 1 реальная дыра покрытия). Таблица: мутация -> какой сьют покраснел (первый FAIL).

| Скрипт | Мутант | Исход |
|---|---|---|
| pr-build | MB1 манифест без `archive_sha256` | убит: `test-pr-build` B1 (оракул `return archive_sha256`), `test-pr-check` C4 |
| pr-build | MB2 `verify.tests` всегда `pass` | убит: B5 |
| pr-build | MB3 `adr` считается при `docs_in_repo: none` | убит: B5 |
| pr-build | MB4 убрана проверка «каталог сессии в дереве» | убит: B7 |
| pr-build | MB5 повторная сдача: родитель = base, а не прежняя вершина | убит: B8a |
| pr-build | MB6 тема head без заголовка | убит: B1 |
| pr-build | MB7 `mbase = PR_BASE_SHA` вместо `merge-base(head, base)` | ВЫЖИЛ: дыра покрытия, см. §5 Д-1 |
| pr-build | MB8 `--resubmit` не требуется | убит: B8a |
| pr-check | MC1a post не проверяет `tip^ == head` | убит: C5 `extra_commit` |
| pr-check | MC1b post не проверяет «единственный файл CHANGE.yaml» (посторонний файл между head и вершиной/в манифест-коммите) | убит: C5 `foreign_file` |
| pr-check | MC3 `attrs.export` WARN -> OK | убит: C3 |
| pr-check | MC4 `pkg.session` FAIL -> OK | убит: C5 `session_dir` |
| pr-check | MC5 `manifest.headtree` FAIL -> OK | убит: C5 `manifest_in_head` |
| pr-check | MC6 `format: 1` не проверяется | убит: C5 `format2` |
| pr-check | MC9 `manifest.shared` FAIL -> NOTE | убит: C5 `shared_undeclared` |
| lib/mandate | MC7 граница срока `-lt` -> `-le` | убит: `test-mandate-lib` L6 «today» (`test-pr-check`/`test-pr-build` границу не ловят — и не обязаны) |
| lib/pr-lib | MC8 `pr_url_ok` не отвергает `*::*` | выжил: ЭКВИВАЛЕНТ (дальше отсекает алфавит `user` и общий `return 1`); избыточная страховка, не дыра |
| pr-publish | MP1 убран guard «только `change/*`» (пушит `main`/`sdx/*`) | убит: P6 `branch` |
| pr-publish | MP3 убрана проверка секрета в теле PR | убит: P5f |
| pr-publish | MP4 `--dry-run` всё равно пушит | убит: P4 |
| pr-publish | MP6 для `bare` нет `instruction` | ВЫЖИЛ: низкая значимость — SPEC требует инструкцию только при деградации `github`; тест `bare` проверяет лишь набор ключей JSON |
| pr-publish | MP7 детект «уже отправлено» отключён | убит: P3 |
| pr-publish | MP8 `gh pr create` без `--base` | убит: P5a (argv) |
| pr-publish | MP9 учётные данные URL не вычищаются | убит: P7 |
| protocol-export | MX1 теряет `questions[]` | убит: X1 |
| protocol-export | MX2 id с D-0 | убит: X1 |
| protocol-export | MX3 `done` включает невыполненные задачи | убит: X8 |
| protocol-export | MX4 счёт матрицы по первой колонке | убит: X8 |
| protocol-export | MX5 `adr` по слову ADR без номера | убит: X2 |
| protocol-export | MX6 теряется `stage` | убит: X1 |
| protocol-export | MX7 теряются `alternatives` | убит: X1 |
| protocol-export | MX8 дедупликация deltas выключена | убит: X8 |
| order-import | MO1 `pr_valid_id` принимает `/` | убит: `test-order-import` O6 (`test-pr-build` остаётся зелёным — там нет такого сценария для `/`; ловит O6) |
| order-import | MO2 `stamp-state` стирает прочие ключи | убит: O7 |
| order-import | MO3 `action: work.order` не обязателен | убит: O6 |
| order-import | MO4 остаётся только последняя `MISMATCH`-строка | убит: O5 |
| order-import | MO5 секрет в заказе не отвергается | убит: O6 |
| mandate-info | MM1 `closeout-mode` без мандата даёт `bridge` | убит: `test-mandate-scope [M]` |
| mandate-info | MM2 `pr-mode` пропускает `orphan` | убит: [M] |
| mandate-info | MM3 `docs_in_repo` по умолчанию `none` | убит: [M] |
| mandate-info | MM4 `pr-status` не чистит URL-алфавит | убит: [M] |
| mandate-info | MM5 `pr-mode` принимает `artifact.offer` | убит: [M] |

## 4. Сквозной прогон на фикстуре вне чекаута

Фикстура: `lib/pkg-fixture.sh` (bare `remote.git`, `wc`, ветка `sdx/s1`), мандат `delivery: pr`, `docs_in_repo: final`, `scope.paths`, `docs_paths`; сессия откатана на момент до шага 5 Closeout (каталог сессии в дереве), `order.yaml` получен из `yaml.safe_dump` заказа узла.

| Шаг | Ожидалось | Получено | Итог |
|---|---|---|---|
| `order-import.sh from-file ... --out order.yaml` | JSON заказа, снимок | rc 0, `commitment C-ACME-001`, `sid_infix`, `warnings: []`; перенос длинных строк склеен | PASS |
| `order-import.sh stamp-state` | `commitment` в `session_state.json`, остальные ключи целы | `OK commitment C-ACME-001`, `stage/type` сохранены | PASS |
| `protocol-export.sh --sid` (оба формата журнала) | пять списков, `decisions[].id/what/why` непусты | `python3 -I`+`safe_load`: done/decisions(2)/questions(2)/verified/deltas; D-1 (формат A, `alternatives`), D-2 (формат B, `adr: true`) | PASS |
| `pr-check.sh --phase pre` | PASS | `PR-CHECK PASS`, rc 0, 22 OK + NOTE `shared.note` | PASS |
| `pr-build.sh --sid` | rc 0, JSON, ветка `change/C-ACME-001-ex1` | rc 0; `adr: ["docs/DECISIONS.md#ADR-099"]`, `touches_shared: true` | PASS |
| `pr-check.sh --phase post` | PASS | 20 проверок OK, rc 0 | PASS |
| `pkg_oracle` | `approve` | `approve` | PASS |
| HEAD/индекс/статус/ветка фикстуры после сборки; `CHANGE.yaml` на диске | не изменились / нет файла | совпали / `find` пуст | PASS |
| дерево пакета без `.claude/sessions/` и `protocol.yaml` | чисто | чисто | PASS |
| `pr-publish.sh --dry-run` | JSON, `pushed: false`, без сети | `pushed:false`, `remote_sha:null`, hosting `bare` | PASS |
| `pr-publish.sh` (реальный push в локальный bare = `repo.url`) | на remote только `change/...` (+`dev`), без тегов, `remote_sha == tip` | `refs/heads/change/C-ACME-001-ex1`, `dev`; тегов нет; `instruction` для bare; remote шаблона не тронут | PASS |
| `mandate-info.sh pr-status` | строка по служебному коммиту с трейлерами | до коммита `PR: не сдан`; после `sdx(s1): pr submitted change/...` — строка с `branch/head/tip/remote/hosting`, учётные данные URL убраны | PASS |
| Негатив: файл вне области | `pr-check` FAIL `diff.scope` | `FAIL diff.scope: ... src/core/b.js`, rc 1 | PASS |
| Негатив: реестр ADR не менялся при `final` | WARN | `WARN adr.registry` (pre), `WARN manifest.adr` (post), rc 3, `adr: []` | PASS |
| Негатив: реестр вне `docs_paths` | WARN/FAIL по DESIGN | `FAIL diff.scope`, `FAIL docs.final`, `WARN adr.registry`, rc 1 | PASS |
| Негатив: истёкший мандат (`SDX_MANDATE_TODAY`) | FAIL | `FAIL mandate.valid` | PASS |
| Негатив: повторный `pr-build` без `--resubmit` | rc 3 `NEED resubmit` | rc 3, `NEED resubmit: ...` | PASS |
| Негатив: расходящийся `base` без флага | rc 3 `NEED allow-diverged` | rc 3 | PASS |
| `pr-publish` на ветке `sdx/*` | rc 1 | текущая ветка `sdx/s1` — штатное состояние: публикуется ветка из заказа (`change/*`), rc 0. Отказ для не-`change/*` ветки достижим только подменой библиотеки (guard `case change/*`), проверен мутантом MP1/сьютом P6 (патч-копия библиотеки, rc 1) | PASS (формулировка задачи уточнена) |
| `github` + нет `gh` (реальный push) | `degraded: gh-missing` + `instruction`, rc 0 | совпало | PASS |
| Без мандата: `pr-mode`; `pr-build/-check/-publish` | `REFUSE no-mandate` rc 1 | совпало; сообщение «режим мандата не включён» | PASS |
| `pr-mode` при `artifact.offer`/`patch`/`worktree`/`branch` | REFUSE `delivery:<d>` / OK для `branch` | совпало; `closeout-mode`: `bridge:offer`/`undefined:*`/`bridge` | PASS |
| Независимый клон: `archive_sha256` | равенство | равно | PASS |
| Повторная сдача + ушедший вперёд `dev` (`--resubmit --allow-diverged`) | пакет только с изменениями сессии, post PASS | rc 0, но `pr-check post` FAIL `pkg.scope: foreign.txt`, оракул `reject scope` | FAIL (дефект Д-1; fail-closed) |
| `docs_in_repo: none` + документы в пакете | сьют/DESIGN: не проверяется | `PR-CHECK PASS`, оракул 0.9.1 `approve`; узел >= 0.9.2 вернёт (`docs_in_repo.none`) | PASS по DESIGN; риск Р-1 |

## 5. Дефекты и риски (не чинились)

**Д-1 (средний; fail-closed, потери данных нет). Повторная сдача после ухода `dev` вперёд даёт пакет с чужими изменениями.**
Шаги воспроизведения (фикстура `lib/pkg-fixture.sh`, копия):
1. `pr-build.sh --sid s1` и `pr-publish.sh` — первая сдача.
2. В локальной `dev` закоммитить чужой файл (`foreign.txt`), вернуться на `sdx/s1`, добавить коммит в `src/mod1/a.js`.
3. `pr-build.sh --sid s1` -> rc 3 `NEED allow-diverged`; `pr-build.sh --sid s1 --resubmit --allow-diverged` -> rc 0, `base` в манифесте = старая база (`71089f3`), `scope_touched` = 5 файлов, включая `foreign.txt`.
4. `pr-check.sh --phase post` -> `FAIL pkg.scope: foreign.txt`; `pkg_oracle` -> `reject scope`.
Причина: при `--resubmit` родитель head — прежняя вершина (цепочка к старой базе), а дерево = `merge-tree(новая dev, sdx/s1)`; `merge-base(head, dev)` остаётся старой базой, и дифф `base..head` содержит чужие изменения `dev`. Это противоречит DESIGN «пакет всегда строится от актуального локального base; узел пересчитывает merge-base сам». Защита работает (post FAIL блокирует push), но ссылка `change/*` в локальном репо уже перезаписана негодным пакетом, а пользователю нужен ручной откат/ребейз. Мутант MB7 (`mbase = PR_BASE_SHA`) в сьютах выживает, т.е. сценарий resubmit x ушедший base тестами (B8 x B9) не покрыт.
Рекомендация: тест B8xB9 и решение (либо при resubmit+diverged родитель = актуальная база, т.е. отказ с инструкцией, либо pre-фаза `pr-check` должна предупреждать/блокировать).

**Р-1 (риск/дрейф эталона). `pr-check` зеркалит `audit()` 0.9.1; рабочая копия sim-kit теперь 0.9.3** (`dev.py:340-430` отличается от тега 0.9.1): новые проверки `docs_in_repo.none` (документы из `docs_paths` в пакете при `none` -> `return`), `docs_in_repo.work` (`work_paths`), `adr` для `docs_in_repo: full`. На `none` с документами в дельте `pr-check` даёт PASS, а узел >= 0.9.2 вернёт пакет. По SPEC/DESIGN (0.9.1 как данные) поведение верное; нужна запись в бэклог при подъёме версии вендоринга.

**Н-1 (низкий). Покрытие.** (а) MP6: инструкция для `bare` не утверждается тестом (в SPEC требуется только при деградации `github`); (б) «нет поля `change` в `artifact.offer`» (A13) и подтверждение push пользователем (A8) проверяются только прозой/ручным сценарием; (в) `verified[]` в `protocol.yaml` читает только маркированные строки `## Сводка` (`- ...`); мой первый прогон с немаркированным «Итог: PASS» дал `verified: []` — формат реального отчёта `reviewer` (с маркерами) подходит, но отчёт в другом виде молча даёт пустой раздел (по построению, не ошибка).

## 6. Выводы

1. Корректность исполнением подтверждена: 25/25 сьютов, сквозной прогон «заказ -> экспорт -> pre -> build -> post -> оракул -> publish -> pr-status» зелёный, негативы дают предусмотренные исходы и коды возврата.
2. Мутационная сила новых сьютов высокая: 39 из 42 независимых мутантов убиты; выжившие — эквивалентный (MC8), низкозначимый (MP6) и одна реальная дыра (MB7 -> Д-1).
3. Время прогона 149-172 с при нагрузке хоста против предела 180 с и критерия <= 150 с: запас тонкий; рычаг DESIGN К-10 (`SDX_VERIFY_JOBS`) остаётся резервом.
4. Остаётся ручным (не исполнено в этом этапе): живой `audit()` узла, живой `gh pr create`, `./mo work protocol`, хук `devagent_hook.py`, проза `pr.md` в обоих `gate_mode`, реальный `mesh_endpoint.py pull`, git другой версии (см. `MANUAL_TEST.md`, DESIGN «Ручной сценарий»).
