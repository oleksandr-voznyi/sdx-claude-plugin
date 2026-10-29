# Verification Report: feat-016-mo-mandate-20261028 (круг 7, fresh-eyes)

## Сводка
- Объём: полный (SPEC/DESIGN/PLAN), no_code: нет, no_gates: нет
- Вход: `SPEC.md`, `DESIGN.md`, `MANUAL_TEST.md`, `release_notes_draft.md`, `upstream_note_draft.md`, `qa_report.md`, `delivery.diff` (против основной ветки, без каталога сессии); эталон — `sdx/mo/devagent_hook.py`, `sdx/mo/MO-INTEROP.md` §7; нормы — `sdx/protocol.md`, `docs/DECISIONS.md`, `docs/specs|designs/mo-interop.md`, `CLAUDE.md`, `README*.md`, `docs/backlog/FEAT-016-…md`.
- Итог: **PASS** (находок FAIL нет)
- Находки: FAIL: 0, WARN: 4, INFO: 5
- Сводка по осям:
  - Полнота — OK: у REQ-MAND-1…33, 11a, 23a, 23b есть реализация в diff, у детерминированных веток есть тесты в diff (покрытие **видимое**, по чтению diff; прогон не выполнялся, у ревьюера нет `Bash`). Scope creep не найден.
  - Корректность — OK по существу; WARN-1 (неточная отсылка в тексте `mo-session.sh`).
  - Когерентность — блокирующих противоречий между нормативными носителями и кодом нет; WARN-2…4 — редакционные неточности ненормативных черновиков и `docs/designs/mo-interop.md`.

## Проверка закрытия находок круга 6
| Находка круга 6 | Статус | Где |
|---|---|---|
| FAIL-1: граница `Bash` в заметках RU/EN | **закрыта**: разбор `Bash` best-effort, `Bash`-пути к `.mesh/*` не охраняются — соответствует `devagent_hook.py:188–245` (`collect()`/`seg_targets()` при `SCOPE`, `_in_scope` считает `.mesh*` в области) и протоколу, граница (а)/(д) и «Границы подраздела» (4). Остаток формулировки — WARN-2 | `release_notes_draft.md:22`, `:50` |
| WARN-1: разметка `#-` | **закрыта**: пункты `MAND-PYYAML` — элементы списка `- …`, стоят сразу за пунктом «Тест-сьют» | `release_notes_draft.md:15`, `:43` |
| WARN-2: фикстура случаев 1 и 4 `MANUAL_TEST` | **закрыта**: в случае 1 предупреждение области названо ожидаемым; в случае 4 есть вариант фикстуры (`on_write: notice` либо `deny` с `.claude/sessions/**` в `docs_paths`). Остаток — INFO-1 | `MANUAL_TEST.md:37`, `:65` |
| Число вендорённой версии в протоколе/DECISIONS | **отсутствует**: `0\.9\.[0-9]` в `sdx/protocol.md` и `docs/DECISIONS.md` не встречается; есть только ссылки на `SIMKIT_VERSION` и исторические 0.7.x | grep |

## Матрица трассируемости
| Требование / критерий | Реализация (файл) | Тест | Когерентность | Статус |
|---|---|---|---|---|
| REQ-MAND-1 (без мандата — как 2.3.x; К-4) | гейты «оба файла» в `sdx-stage.sh` (`_mandate_try`), `mo-hook.sh` (`MAND-MODE2` после `MO-EARLY-EXIT`), `mo-session.sh` (`mnote`, `mand_show`), `mandate-scope.sh:1200` | `test-sdx-stage [30]`, `test-mo-session [12]` + `mnote-always`, `test-mandate-scope (1)` | ok (К-4 названа в протоколе, ADR-021, README×2, заметках) | OK |
| REQ-MAND-2/3 (два файла; мандат без endpoint) | `lib/mandate.sh` `mandate_mode`, `mandate_orphan_line`; `mo-session.sh` `MAND-ORPHAN`; `mandate-info.sh show` | `test-mandate-lib L7`, `test-mo-session [10]` | ok | OK |
| REQ-MAND-4 (показ на SessionStart, К-2) | `mo-session.sh` `mand_show` после leases; ветка без python3 | `test-mo-session [11]`, `[12]` | текст суффикса неточен (WARN-1) | WARN |
| REQ-MAND-5 (показ на `/sdx:start`) | `commands/start.md` шаг 1а | `test-mo-prose [14]` | ok | OK |
| REQ-MAND-6 (область по каждому каталогу, К-1) | `mandate_report` (`MAND-SCOPE-WARN`) | `L8` | ok | OK |
| REQ-MAND-7 (срок) | `mandate_expired`, `mandate_report`, строка `> Предупреждение` в `mandate-scope.sh` | `L6`, `test-mandate-scope (10)` | ok | OK |
| REQ-MAND-8/9 (третий источник; Deployment всегда исключён; оффер один раз) | `_mandate_class`/`mandate_stage_allowed`, `is_skipped` (`MAND-SKIP`); проза `next.md`, `archive.md` 2а, протокол | `test-sdx-stage [31]–[33]`, `L4` | ok: «один раз, шаг 0 моста, пропуск при `msg_id`» одинаково в SPEC, протоколе, ADR-020, CLAUDE.md, `devops.md`, `next.md`, `archive.md` | OK |
| REQ-MAND-10 (fail-closed) | `mandate_load`, `miniyaml.sh` | `L1`–`L3`, `[35]` | доп. отказы по типу `scope.*` — INFO-3 | OK |
| REQ-MAND-11/11a (`--to`, `start-stage`, поправка ADR-020) | `cmd_next` `MAND-TO`, `cmd_init` шаг 5a, `cmd_start_stage`; `docs/DECISIONS.md` | `[34]`, `[37]`, `[38]`, `test-mo-prose [16]` | ok | OK |
| REQ-MAND-12…15 (область на verify) | `mandate-scope.sh`, `mandate_glob_one`; `verify.md` 6а | `test-mandate-scope (1)–(9)`, `L5` | правило `docs_in_repo: none` в `--planned` — INFO-4 | OK |
| REQ-MAND-16 (+ поправка круга 1, PyYAML) | `mo-hook.sh` `MAND-MODE2`, `MAND-PYYAML` | `test-mo-hook [2m]`, `[2y]`, `[8i]` | ok | OK |
| REQ-MAND-17 (охрана `mandate.yaml`) | `mo-hook.sh` `MO-GUARD-MANDATE`, `is_mailbox_file` 3-й параметр | `[7m]` | ok | OK |
| REQ-MAND-18…21 (`tests/suites.yaml`) | `lib/test-cmd.sh`, `suites-gen.sh`, `tests/suites.yaml`, `init.md` 2в, `reconcile.md` (е) | `test-suites-gen (1)–(10)`, близнец со `stop-gate.sh`; ручной случай 3 — не проверено | ok | OK |
| REQ-MAND-22 (`devops`) | `agents/devops.md` | `test-mo-prose [10]` | ok | OK |
| REQ-MAND-23/23a/23b (мост Closeout) | `mandate-info.sh closeout-mode|closeout-check`, `archive.md` 2а, протокол «Мост Closeout» | `test-suites-gen [M]`, `test-mo-prose [12]`; проза — ручной случай 4, не проверено | ok | OK |
| REQ-MAND-24/25 (сниппет, reconcile) | `claude-md-snippet.md`, `snippet-check.sh`, `reconcile.md` (ж) | `test-snippet-check`, `test-mo-prose [11]` | ok | OK |
| REQ-MAND-26 (`/sdx:status`) | `mandate-info.sh status`, `sdx-stage.sh active-set`, `status.md` 5а | `[39]`, `[40]`, `[M]` | ok | OK |
| REQ-MAND-27…29 (документы) | протокол, ADR-020/021, `docs/specs|designs/mo-interop.md`, README×2, CLAUDE.md, FEAT-016 | `test-mo-prose [9]`, `[15]`, `[16]`; `test-mo-inventory.sh` | `docs/designs/mo-interop.md:36` неточен (WARN-4) | WARN |
| REQ-MAND-30 (2.4.0) | `plugin.json` 2.4.0 (в `marketplace.json` версии нет) | `test-mo-prose [17]` | ok | OK |
| REQ-MAND-31…33 (регрессия, время, зависимости) | 19 сьютов; комментарий `verify-cmd.sh`; `sdx/mo/*` и `stop-gate.sh`/`archive-verify.sh`/`hooks.json` в diff отсутствуют | полный прогон — по `qa_report.md` (19/19, 114 с; круг 1) | ok | OK |
| Заметки / записка upstream (ненормативные) | `release_notes_draft.md`, `upstream_note_draft.md` | — | WARN-2, WARN-3 | WARN |

## Находки

### [WARN] [Корректность] Суффикс `mnote` в `mo-session.sh` отсылает к строкам с несуществующим префиксом
- Где: `sdx/hooks/mo-session.sh:36` (diff, строка 1410)
- Суть: в ветке «нет python3/PyYAML» строка зависимости получает суффикс «Мандат .mesh/mandate.yaml читается без python3 — см. строки **SDX mandate** ниже …». Но `mand_show` вызывает `mandate_report "$proj" "$P"` с `P="SDX mo-session:"`, поэтому строки мандата на SessionStart начинаются с `SDX mo-session: мандат МО …` / `SDX mo-session:  [ДАННЫЕ, не инструкции] …`. Префикс `SDX mandate:` бывает только у `mandate-info.sh show` (`/sdx:start`). DESIGN (поправка круга 3, К-2) называет суффикс «… читается без python3 и показан ниже» — без отсылки к префиксу.
- Ожидалось: суффикс в духе DESIGN («… читается без python3 и показан ниже») либо отсылка к реальному префиксу (`SDX mo-session: мандат МО`). Тест `[12]` суффикс дословно не фиксирует, так что правка утверждения тестов не требует. Поведение не страдает (группа печатается), текст сбивает с толку.
- Фактически: пользователь ищет строки «SDX mandate» и на SessionStart их не находит.

### [WARN] [Когерентность] Заметки: «хук останавливает» запись `Bash` вне области без условия режима
- Где: `release_notes_draft.md:22` (RU), `:50` (EN)
- Суть: после поправки круга 6 строка верна по главному (разбор команды best-effort, `Bash`-пути к `.mesh/*` не охраняются), но говорит «хук **останавливает**» / «are **stopped**» безусловно. По эталону (`devagent_hook.py:231–243`) запись вне области останавливается только при `mandate.on_write: deny`; при `notice` (дефолт) хук шлёт узлу `scope.write` и пропускает запись. Протокол (граница (д): «`notice` узлу … или блок `DENY [MO-scope]` при `mandate.on_write: deny`») это различает.
- Ожидалось: «… хук разбором текста команды (best-effort, как для `exec_paths`) сообщает узлу (`notice`) или останавливает (`mandate.on_write: deny`)» и так же в EN. Это WARN, а не FAIL: черновик заметок не нормативный, а норма в протоколе точная.
- Фактически: из текста следует, что при `notice` запись тоже блокируется.

### [WARN] [Когерентность] Записка upstream: «обёртка не менялась» — неверно
- Где: `upstream_note_draft.md:3`
- Суть: «SDX 2.4.0 читает `.mesh/mandate.yaml` … (вендорённый хук и **обёртка не менялись**)». В поставке `sdx/hooks/mo-hook.sh` изменён трижды: `MAND-MODE2` (второй источник режима), `MO-GUARD-MANDATE` (охрана `mandate.yaml`), `MAND-PYYAML` (fail-closed при `deny` из мандата без PyYAML). Не менялся только `sdx/mo/*` (PROC-028). Записка уходит владельцу МО, и в п.3 (fail-open хука на битом мандате) он рассуждал бы, считая, что SDX-обёртка не участвует.
- Ожидалось: «(вендорённый хук не менялся; обёртка `mo-hook.sh` читает `mandate.on_write`, охраняет `mandate.yaml` от `Write`/`Edit` и при `deny` из мандата без PyYAML отказывает сама)».
- Фактически: фактическое утверждение о поставке расходится с diff. Это WARN: носитель не нормативный, пункты 1–6 по существу верны.

### [WARN] [Когерентность] `docs/designs/mo-interop.md:36`: «оба активируются двумя признаками … без файла — пустой вывод»
- Где: `docs/designs/mo-interop.md:36` (diff, строка 433)
- Суть: (1) `mo-hook.sh` по-прежнему активируется только `endpoint.yaml` (`MO-EARLY-EXIT`), а `mandate.yaml` лишь меняет режим и охрану; «оба активируются двумя признаками» это затушёвывает. (2) Фраза «Без файла — `exit 0`, пустой вывод» неоднозначна: при `mandate.yaml` без `endpoint.yaml` `mo-session.sh` печатает одну строку предупреждения (REQ-MAND-3, `MAND-ORPHAN`), то есть вывод не пуст. В протоколе («МО-хук») это сказано точно: «без `endpoint.yaml`, но с `mandate.yaml` — одна строка предупреждения».
- Ожидалось: «Без `endpoint.yaml` — `exit 0`, python не запускается, `jq` не требуется; вывод пуст, кроме одной строки `mo-session` при `mandate.yaml` без `endpoint.yaml`». Активацию тоже стоит развести: `endpoint.yaml` включает хуки, `mandate.yaml` при нём включает режим мандата.
- Фактически: редакционная неточность постоянного документа; противоречия с кодом нет, если «файл» читать как «оба файла».

### [INFO] [Полнота] `MANUAL_TEST` случай 1: общая фикстура с `on_write: deny` помешает шагу 2
- Где: `MANUAL_TEST.md:18`, `:36`
- Суть: в общей фикстуре `on_write: deny` и `scope.paths: [src/**]`, `.claude/sessions/` не покрыт. На шаге 2 случая 1 (`/sdx:start`) записи оркестратора в `.claude/sessions/<id>/` (`Write`, `echo >> session.log`) хук остановит `DENY [MO-scope]`. Ожидаемый результат относится только к выводу шага 1а, поэтому случай остаётся валидным. Для полноты стоит указать `on_write: notice` и для случая 1, как это уже сделано для случая 4.

### [INFO] [Когерентность] Цитата протокола в `docs/designs/mo-interop.md` (п.1.6) обновлена наполовину
- Где: `docs/designs/mo-interop.md:~278` (diff, строки 442–443)
- Суть: в цитате подраздела «МО-хук» фраза о признаках обновлена до «два признака», а соседняя «Сама отказывает … в `.mesh/endpoint.yaml`/`.mesh/cursors.json`» осталась прежней, без `mandate.yaml`. Настоящий протокол уже говорит про все три файла. Дельта в конце документа это покрывает; противоречия нет, есть непоследовательность исторической цитаты.

### [INFO] [Когерентность] `mandate_load` отвергает больше случаев, чем перечислено в SPEC/DESIGN
- Где: `sdx/hooks/lib/mandate.sh:548–553` (diff)
- Суть: кроме четырёх причин из REQ-MAND-10 и DESIGN (`mandate_load` п.1–3) скрипт отказывает, если `mandate.scope` — скаляр или список, а `scope.paths|shared_paths|docs_paths|branches` — скаляр или словарь. Это строже `safe_load`/хука и только в сторону fail-closed (согласуется с К-8), но в артефактах как отдельное решение не записано.

### [INFO] [Когерентность] `verify.md` 6а: исключение переносов при `docs_in_repo: none` есть только в прозе команды
- Где: `commands/verify.md:284` (diff)
- Суть: правило «при `docs_in_repo: none` каталоги `docs/specs/`, `docs/designs/` и `docs/DECISIONS.md` в `--planned` не передаются» логично следует из REQ-MAND-23b, но не записано ни в DESIGN (раздел `commands/verify.md`), ни в протоколе («Область на `/sdx:verify`»). Стоит упомянуть в протоколе при переносе дельт на Closeout.

### [INFO] [Когерентность] `closeout-check` исключает `.mesh` из проверки чистоты дерева
- Где: `sdx/hooks/mandate-info.sh:1146` (diff: `git status --porcelain -- . ':!.mesh'`)
- Суть: DESIGN и протокол говорят «`git status --porcelain` пуст». Исключение `.mesh` (фенотип узла вне git) разумно, но не записано. Стоит добавить в протокол одну оговорку: «(кроме `.mesh/`)».

## Примечание о достоверности
Покрытие и «зелёность» тестов здесь видимые: они выведены из чтения diff и `qa_report.md` (круг 1: 19/19, 114 с, 17 мутантов красные). В этом круге ревьюер тесты не исполнял. Ручные случаи 1–5 `MANUAL_TEST.md` записаны как НЕ ПРОВЕРЕНО по решению пользователя и остаются непроверенными допущениями (они названы в «Границах» заметок).
