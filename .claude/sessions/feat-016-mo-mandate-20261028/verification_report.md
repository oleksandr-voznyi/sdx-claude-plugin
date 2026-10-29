# Verification Report: feat-016-mo-mandate-20261028 (круг 6, fresh-eyes)

## Сводка
- Объём: полный (SPEC/DESIGN/PLAN), `no_code`: нет, `no_gates`: нет, `gate_mode`: interactive
- Вход: `SPEC.md` (с «Поправками по коллизиям DESIGN»), `DESIGN.md` (датированные пометки кругов 1–4), `PLAN.md` («Отклонения», круги 1–5), `decisions_log.md`, `MANUAL_TEST.md`, `release_notes_draft.md`, `upstream_note_draft.md`, `qa_report.md`, `delivery.diff` (целиком, 4610 строк). Эталон: `sdx/mo/MO-INTEROP.md` §7, `sdx/mo/devagent_hook.py`, `sim-kit/core/dev.py`. Нормы: `sdx/protocol.md`, `docs/DECISIONS.md`, `docs/specs|designs/mo-interop.md`, `CLAUDE.md`, README×2, `docs/backlog/FEAT-016-…`.
- Итог: **FAIL** (одна находка FAIL)
- Находки: FAIL: 1, WARN: 2, INFO: 5
- По осям:
  - **Полнота:** OK. Каждое требование REQ-MAND-1…33, 11a, 23a, 23b и критерии 1–21 прослежены в diff (код или проза) и в тестах. Ручные части (критерий 3 — канал, 7 — живой дамп, 14 — `run_suites`, 16 — проза моста) вынесены в `MANUAL_TEST.md`, все случаи помечены «НЕ ПРОВЕРЕНО». Scope creep не видно: каждый изменённый файл (включая `docs/backlog/README.md` и комментарий `verify-cmd.sh`) трассируется к REQ-MAND-29/32.
  - **Корректность:** по чтению diff поведение скриптов соответствует SPEC/DESIGN с поправками. Новых расхождений кода с контрактом не найдено. Остаётся одна WARN по фикстуре `MANUAL_TEST` (случай 4).
  - **Когерентность:** 1 FAIL — релизные заметки утверждают, что хук не охраняет запись через `Bash` вне области мандата, а вендорённый хук её охраняет. 1 WARN — разметка заметок. Нормативные носители (протокол ↔ ADR-020/021 ↔ команды ↔ `docs/specs|designs` ↔ CLAUDE.md ↔ README×2) между собой и с кодом не противоречат.

Покрытие ниже выведено чтением diff и тестов. Это видимое (apparent) покрытие, а не доказанное. Тесты в этом круге не запускались (у ревьюера нет `Bash`); данные о прогоне — из `qa_report.md` и `PLAN.md` (раздел «Отклонения»).

### Проверка закрытия находок круга 5
| Пункт | Состояние | Где |
|---|---|---|
| FAIL-1: фикстура `MANUAL_TEST` без корня `mandate:` и без `on_write: deny` | **закрыто** | `MANUAL_TEST.md:14–30`: корень `mandate:`, поля вложены, `on_write: deny`, пояснение о `dev.py mandate_yaml()`. Форма совпадает с `dev.py:531` (`yaml.safe_dump({"mandate": m})`). По чтению `miniyaml.sh` разбирается: комментарий после `deny` срезается, flow-списки допустимы. Остался побочный дефект — см. WARN-2 |
| WARN-1: хвост остатка правки в EN-заметках | **закрыто** | `release_notes_draft.md:35` — «…is refused (`sdx-stage.sh`, `[ERROR]` logged).» без хвоста; пара RU :6 / EN :35 симметрична |
| WARN-2: два «кроме» в `docs/designs/mo-interop.md` | **закрыто** | diff :453 — одно перечисление: «с единственным перечнем исключений REQ-MAND-1: проверки наличия файлов, (а), (б), `from.kit`/`version-skew`, К-4» |
| INFO-3: отсылки REQ-MAND-14/16 к поправкам | **закрыто** | `SPEC.md:52` («см. поправку К-3 — `--planned`»), `:57` («см. поправку круга 1 — PyYAML при `deny` из мандата») |
| INFO-6: `MAND-PYYAML` в заметках | **закрыто по существу**, разметка испорчена | `release_notes_draft.md:16` / `:45` — пункт добавлен, но с префиксом `#-` (см. WARN-1) |
| (3) Число вендорённой версии в протоколе/DECISIONS | **отсутствует** | `grep 0\.9\.[0-9]` по `sdx/protocol.md` и `docs/DECISIONS.md` — совпадений нет. Протокол ссылается на `SIMKIT_VERSION`, поправки ADR пишут только линии «0.7.x»/«0.9» |

## Матрица трассируемости
| Требование / критерий | Реализация (файл) | Тест | Когерентность | Статус |
|---|---|---|---|---|
| REQ-MAND-1 / кр.1 (без мандата — как 2.3.x; исключения (а), (б), К-4) | гейт «оба файла»: `sdx-stage.sh` `_mandate_try` (diff :1461), `mo-hook.sh` MAND-MODE2 (:1339), `mo-session.sh` (:1393–1415), `mandate-scope.sh` (:1200) | `test-sdx-stage` [M30], `test-mo-session` [12c] + мутант `mnote-always`, `test-mo-hook` [2m]/[7m], `test-mandate-scope` (1) | протокол :4529, README×2, ADR-021 п.(3), `docs/specs` :487, `docs/designs` :453 — К-4 названо единообразно | OK |
| REQ-MAND-2 (два файла) | `mandate_mode` (:519) | L7, [2m], [M] mode | ok | OK |
| REQ-MAND-3 / кр.2 (orphan — одна строка) | `mandate_orphan_line`, MAND-ORPHAN (:1393), `mandate-info show` | `test-mo-session` [10] + мутанты; [M] show orphan | ok | OK |
| REQ-MAND-4 / кр.3 (показ на SessionStart, К-2) | `mand_show` (:1398), `mandate_report` (:678) | [11], [12]–[12d] + мутанты | ярлык суффикса — INFO-1 | OK |
| REQ-MAND-5 / кр.4 (показ на `/sdx:start`) | `start.md` 1а (:238), `mandate-info.sh show` | [M] show on, `test-mo-prose` [14] | ok | OK |
| REQ-MAND-6 (по каталогу, К-1) | `mandate_report` (:699–704) | L8w, [11] | DESIGN :149 помечен | OK |
| REQ-MAND-7 (истёк) | `mandate_expired` (:586), строка в `mandate-scope` (:1272) | L6, (10) | ok | OK |
| REQ-MAND-8/9 / кр.5 (сужение, `Deployment` never) | `_mandate_class`, `mandate_stage_allowed` (:564–584), `is_skipped` (:1487, :1540) | L4, [M31]–[M33], [M36], мутанты | протокол «Активность этапа» (:4490), ADR-020 (:296), CLAUDE.md §3 (:38), `next.md` (:194) — согласованы | OK |
| REQ-MAND-10 / кр.7 (fail-closed, формы) | `miniyaml.sh`, `mandate_load` (:537) | L1–L3, [M35] | граница F1 названа в SPEC, протоколе (:4551), `docs/specs` (:495) | OK |
| REQ-MAND-11 / кр.6, 8 (`--to`, `init`, `start-stage`) | `sdx-stage.sh` (:1502–1530, :1552–1584) | [M34], [M37], [M38], мутант MAND-TO | протокол (:4510–4517), `start.md`, `import.md` | OK |
| REQ-MAND-11a, 28 (ADR-020/021) | `docs/DECISIONS.md` (:296, :321) | `test-mo-prose` [16] | ok | OK |
| REQ-MAND-12…15 / кр.9, 10 | `mandate-scope.sh`, `verify.md` 6а (:278–284) | `test-mandate-scope` (1)–(10) + мутанты; `test-mo-prose` [13], [18] | протокол «Область на /sdx:verify» (:4557) | OK |
| REQ-MAND-16 / кр.11 (более строгий режим, MAND-PYYAML) | `mo-hook.sh` (:1338–1339, :1372–1376) | [2m], [2y], [8i], мутанты | протокол (:4530), ADR-021 п.(6), дельты | OK |
| REQ-MAND-17 / кр.12 (охрана `mandate.yaml`) | `is_mailbox_file` + MO-GUARD-MANDATE (:1365) | [7m] + мутанты | ok | OK |
| REQ-MAND-18…21 / кр.13, 14 | `lib/test-cmd.sh`, `suites-gen.sh`, `tests/suites.yaml` (:4599 `./.claude/sdx/verify-cmd.sh`, бит 100755), `init.md` 2в, `reconcile.md` (е) | `test-suites-gen` (1)–(10), близнец, мутанты; `test-mo-prose` [18]; ручной случай 3 | ok | OK |
| REQ-MAND-22 / кр.15 (`devops`) | `agents/devops.md` (:113, :122, :128) | `test-mo-prose` [10], [12b] | ok | OK |
| REQ-MAND-23/23a/23b / кр.16 (мост при любом `delivery`) | `mandate-info.sh closeout-mode/check` (:1116–1151), `archive.md` 2а (:138–142), протокол (:4569) | [M] cm/cc + мутанты; `test-mo-prose` [12], [12b]; ручной случай 4 | шаг 0 согласован с `closeout-check` | OK |
| REQ-MAND-24/25 / кр.17 | сниппет (:4583), `snippet-check.sh`, `reconcile.md` (ж) | `test-snippet-check`, `test-mo-prose` [11], [18] | ok | OK |
| REQ-MAND-26 / кр.18 | `mandate-info.sh status`, `active-set` (:1591), `status.md` 5а | [M] status, [M39], [M40], `test-mo-prose` [18] | ok | OK |
| REQ-MAND-27, 29 / кр.19 | протокол, `docs/designs|specs`, README×2, CLAUDE.md, бэклог | `test-mo-prose` [9], `test-mo-inventory` | ok (INFO-2, INFO-3) | OK |
| REQ-MAND-30 (2.4.0, заметки) | `plugin.json` 2.4.0; `marketplace.json` без версии; `release_notes_draft.md` | `test-mo-prose` [17] | заметки противоречат хуку — FAIL-1; разметка — WARN-1 | FAIL |
| REQ-MAND-31…33 / кр.20 | `verify-cmd.sh` (комментарий), `sdx/mo/*` без правок (нет в diff) | полный прогон (`qa_report` §1; PLAN, «Отклонения» З.1) | ok | OK |
| Кр.21 (не `auto`) | `gate_mode: interactive` | — (процесс) | ok | OK |
| Ручной сценарий | `MANUAL_TEST.md` | — | фикстура годится не для всех случаев — WARN-2 | WARN |

## Находки

### [FAIL] [Когерентность] Релизные заметки утверждают, что запись через `Bash` вне области мандата хуком не охраняется
- Где: `release_notes_draft.md:23` (RU), `:52` (EN) — раздел «Границы / Boundaries».
- Суть: в заметках сказано: «Запись через текст `Bash` вне области мандата хуком не охраняется (мягкая граница, как в эталоне)» / «Writes via `Bash` text outside the mandate scope are not guarded by the hook». Код утверждает обратное:
  - вендорённый хук разбирает команды `Bash` на цели записи: `devagent_hook.py:194–213` (`collect()`, ветка `tool == "Bash"`, `seg_targets`);
  - блок области мандата применяет это к любому инструменту, включая `Bash`: `:216–242`, при `mandate.on_write: deny` — `DENY [MO-scope]`, `exit 2`;
  - обёртка `mo-hook.sh` передаёт хуку и `Bash` (matcher `Bash|Write|Edit|MultiEdit|NotebookEdit`; охрана `.mesh/*` — только для Write-семейства, хук вызывается для всех).
  С кодом согласуются протокол — граница (б) «хук sim-kit разбирает `Bash` по образцу guard МО… best-effort» (diff :4541) — и `MANUAL_TEST.md` случай 5 (:80): «запись вне области — отказ `mo-hook`». Похоже, заметки пересказали другую границу: SPEC «Границы» и протокол «Границы подраздела» (4) / (а) говорят о **`Bash`-путях к `.mesh/*`** (подмена `mandate.yaml` через `>`, `sed -i`, `git checkout`), а не о записи вне области. Заметки публикуются на Closeout (C3). В нынешнем виде они говорят пользователю, что под `deny` запись через `Bash` пройдёт, а на деле она будет остановлена.
- Ожидалось: RU/EN симметрично, например: «Запись через `Bash` вне области мандата хук останавливает best-effort — разбором текста команды (граница (б), обходится, например, интерпретатором); `Bash`-пути к `.mesh/*` (`>`, `sed -i`, `git checkout`) обёртка не охраняет — подмену мандата обнаруживает узел по `mandate_digest`».
- Фактически: «не охраняется» — противоречит вендорённому хуку, протоколу (б) и `MANUAL_TEST` случаю 5.

### [WARN] [Когерентность] Разметка пункта `MAND-PYYAML` в заметках испорчена
- Где: `release_notes_draft.md:16` (RU), `:45` (EN).
- Суть: обе строки начинаются с `#-`. Это не элемент списка и не заголовок (после `#` нет пробела); в Markdown строка отрисуется абзацем с литералом «#- …». К тому же пункт отделён пустой строкой от списка «Что изменилось / What changed» и визуально выпадает из него.
- Ожидалось: `- **`mo-hook.sh` (PyYAML при `deny` из мандата).** …` — элементом списка, без пустой строки перед ним (или влить его в пункт «`mo-hook.sh`» :9 / :38).

### [WARN] [Корректность] Общая фикстура `MANUAL_TEST` не годится для случая 4 без правки, а это не сказано явно
- Где: `MANUAL_TEST.md:14–29` (фикстура) против случая 4 (:65) и случая 1 (:37).
- Суть: (1) В случае 4 предусловие — «`stages` включает `verify`», а в фикстуре `stages: [spec, design, execute]`. (2) В фикстуре `on_write: deny`, `scope.paths: [src/**]`, `docs_paths: [docs/**]`, то есть `.claude/sessions/` вне области. По `devagent_hook.py:216–242` хук заблокирует (`DENY [MO-scope]`) каждую запись артефактов сессии. Случай 4 («довести сессию до Closeout») на такой фикстуре не проходит, а тестировщик получит ложный отрицательный результат. Комментарий «для прочих случаев можно notice» — необязательная подсказка, а не условие случая. (3) В ожидаемом результате случая 1 (а) не упомянута строка «ВНИМАНИЕ: область мандата не покрывает .claude/sessions/», которую `mandate_report` на этой фикстуре напечатает (diff :699–704). Это ожидаемое поведение, но тестировщик может принять его за дефект.
- Ожидалось: в случае 4 явно задать вариант фикстуры: `on_write: notice` (или `.claude/sessions/**` в `docs_paths`) и `verify` в `stages`. В случае 1 (а) упомянуть ожидаемое предупреждение области.

### [INFO] [Когерентность] Суффикс `mnote` ссылается на «строки SDX mandate», а `mo-session` печатает с префиксом `SDX mo-session:`
- Где: `sdx/hooks/mo-session.sh` (diff :1410).
- Суть: префикс `SDX mandate:` есть только у `mandate-info.sh show`; на SessionStart строки мандата идут с префиксом `$P` = `SDX mo-session:`. Не исправлено с круга 5. Это расхождение формулировки, поведение не затронуто.

### [INFO] [Когерентность] `docs/designs/mo-interop.md` п.2 трёх слоёв: «Без файла — `exit 0`, пустой вывод»
- Где: diff :433.
- Суть: при двух признаках «без файла» читается двояко: если `mandate.yaml` есть, а `endpoint.yaml` нет, `mo-session` печатает одну строку (REQ-MAND-3). Ожидается: «без `endpoint.yaml` (и без `mandate.yaml`)». Не исправлено с круга 5.

### [INFO] [Когерентность] Критерий приёмки в записи бэклога — без оговорки К-4 и со ссылкой на «2.3.0»
- Где: `docs/backlog/FEAT-016-…md`, «Критерии приёмки» (diff :395–396).
- Суть: «неотличимо от 2.3.0» без исключения К-4 (охрана `mandate.yaml`), тогда как SPEC пишет «2.3.x» и называет исключения. Запись поправляется на Closeout (C2), это не блокер; при правке стоит добавить К-4.

### [INFO] [Корректность] Резервные ветки `mo-session.sh` при отсутствии `lib/mandate.sh` тестом не покрыты
- Где: MAND-ORPHAN, ветка `|| printf …` (diff :1393); `mand_show`, ветка `else say "… не показан …"` (:1401).
- Суть: фикстурный корень `test-mo-session.sh` всегда получает обе lib. Риск низкий: каждая ветка — одна строка. Не изменилось с круга 5.

### [INFO] [Когерентность] Исторические формулировки PLAN
- Где: `PLAN.md:459` (таблица покрытия, кр.16: «`artifact.offer` и без мандата — штатный»), T12/T33/T39.
- Суть: оставлены сознательно как история (PLAN, «Круг 3», INFO-5). Актуальную норму несут SPEC «Поправки» и раздел «Отклонения». С кодом не противоречат.
