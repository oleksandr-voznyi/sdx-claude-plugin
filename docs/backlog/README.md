# Бэклог фреймворка SDX

Каталог `docs/backlog/` — постоянный трекаемый бэклог фреймворка. Каждая запись — отдельный
файл `<ID>-<slug>.md` с машиночитаемым YAML frontmatter (интеграционная точка будущего плагина
портфельного управления) и телом в свободной прозе (`## Суть`, `## Рекомендация`, для закрытых/
отложенных записей — `## Резолюция`). В части записей встречается раздел `## Решения груминга`
с указанием сессии первой строкой: им сессия типа `grooming` объясняет, почему сменила
атрибуты записи, когда обоснование не несёт `## Резолюция`. Имя раздела повторяемое —
несколько грумингов дописывают его, а не плодят новые заголовки. Это **описание сложившейся
практики, а не норма**: вправе ли `grooming` вообще дописывать тела записей — открытый вопрос
`PROC-022`, и правило появится здесь после его решения, а не до. Идентификатор строится
по схеме `<PREFIX>-<NNN>` со
сквозной нумерацией внутри префикса: `FEAT-` (новая функциональность), `BUG-` (дефекты/
противоречия), `DEBT-` (техдолг, дрейф документов, недоспецификация), `IDEA-` (roadmap-идеи),
`PROC-` (процессные изменения).

Каждая запись имеет статус (`open` — не начата, `in-progress` — в работе, `closed` — закрыта
с указанием закрывшей сессии, `deferred` — сознательно отложена), приоритет (`high|normal|low`)
и, для запланированных записей, номер `wave` — волны планирования сессий доработок (меньший
номер — ближе по очереди; `null` — волна ещё не назначена). Поле `links` перечисляет связанные
ADR (`docs/DECISIONS.md`) и другие записи бэклога.

Для просмотра используйте команду `/sdx:backlog`: без аргументов — таблица-список (эквивалент
таблиц ниже), с фильтрами `--status/--type/--wave` — выборка, с `<ID>` — деталь записи, `add` —
создание новой записи интервью с пользователем. Закрытие сессии (`/sdx:archive`) актуализирует
бэклог: закрытые находки получают `status: closed` + `session`, а отложенные решения и
неквитированные WARN-находки Verification оформляются новыми записями `DEBT-`/`IDEA-`.

Записи мигрированы из исторического снапшота `docs/audit-2026-07-01-recommendations.md`
(ревизия фреймворка от 2026-07-01) с сохранением статусов и содержимого находок A*–E*.

Записи `FEAT-003`…`FEAT-014`, `PROC-012`…`PROC-021`, `DEBT-031`, `IDEA-009`…`IDEA-011` порождены
разбором `intake sdx-runtime-rethink-20260830` (переосмысление SDX в контексте `AIBoK-structure.md`
и `Constructor-concept.md`: durable-механики, модель полномочий, карта освоенности областей).
Груминг `grooming-sdx-2-0-20260831` свёл нумерацию волн этого разбора (1–5) и нумерацию ранее
накопленных записей (8–10) в **одну шкалу 1–7** среди открытых и
отложенных записей: волны 8–10 у них упразднены, десять записей, живущих в снимаемой машинерии
треков, переведены в
`deferred` (восемь ждут волну 2, две — `BUG-005` и `DEBT-007` — волну 1, где их предмет снимает
`PROC-019`), а уцелевшие получили места на новой шкале. Волна 1 — основание (durable-механики
и живость enforcement), 2 — атомарный снос с заменой, 3 — контракт и цикл, 4 — освоенность областей,
5 — позиционирование и жизненный цикл, 6 — процедура абляции как предусловие, 7 — внутренняя
экономика (субагенты, тиры), отделённая от атомарного набора и измеряемая, а не декларируемая.
У **закрытых** записей поле `wave` не трогалось: их значения принадлежат прежним шкалам, отражают
историю планирования на момент закрытия и вне этой истории не интерпретируются.

Записи `PROC-023`, `PROC-024` и `DEBT-033` порождены разбором
`intake intake-constructor-concept-20260831` — вторым разбором тех же двух документов
(`Constructor-concept.md`, `AIBoK-structure.md`), оформившим находки, которые предшествующий
груминг обнаружил, но завести не мог по границам своего типа.

## Открытые

| ID | type | status | priority | wave | Название |
|----|------|--------|----------|------|----------|
| FEAT-006 | feat | open | high | 2 | [Модель полномочий: классы риска действий, `deny` → `ask`/`defer`](FEAT-006-authority-model-risk-classes.md) |
| PROC-017 | proc | open | high | 2 | [Delta-first: дельта — первичный артефакт, мёрж механический](PROC-017-delta-first-artifacts.md) |
| FEAT-003 | feat | open | high | 3 | [Реестр задач прогона как источник истины вместо прозаического `PLAN.md`](FEAT-003-run-task-ledger.md) |
| FEAT-004 | feat | open | high | 3 | [Журнал прогона пишет харнесс, а не модель](FEAT-004-harness-written-journal.md) |
| FEAT-005 | feat | open | high | 3 | [Stop-хук как тик планировщика прогона](FEAT-005-stop-hook-scheduler-tick.md) |
| PROC-016 | proc | open | high | 3 | [Гейт по контракту вместо гейта по существованию](PROC-016-contract-gates-instead-of-existence.md) |
| PROC-020 | proc | open | high | 3 | [Инвариант: агент не автономен в прогоне, меняющем механизм собственного надзора](PROC-020-no-autonomy-over-own-supervision.md) |
| FEAT-009 | feat | open | high | 4 | [Карта освоенности областей проекта (`declared` + `observed`)](FEAT-009-area-readiness-map.md) |
| FEAT-010 | feat | open | high | 4 | [Асимметричная выдача полномочий](FEAT-010-asymmetric-authority-function.md) |
| IDEA-005 | idea | open | high | 6 | [Процедура lean-аудита и правило «инвариант-в-прозе → хук» (REQ-LEAN-1)](IDEA-005-lean-audit-procedure.md) |
| DEBT-028 | debt | open | high | null | [Тип сессии `audit` не подтверждён исполнением: REQ-AUDIT-9..15 держатся только на прозе](DEBT-028-audit-session-type-unexercised.md) |
| DEBT-034 | debt | open | high | null | [Единая шкала этапов не подтверждена ни одной живой сессией](DEBT-034-stage-scale-unexercised-by-live-session.md) |
| FEAT-015 | feat | open | high | null | [Интероп с мета-оркестратором (МО) в плагинной модели: канал `.mesh/`, хук `exec_paths`, режим `devops`](FEAT-015-mo-interop-plugin-model.md) |
| PROC-028 | proc | open | high | null | [Политика вендоринга sim-kit в плагин: версия, обновление, запрет локальных правок](PROC-028-simkit-vendoring-policy.md) |
| FEAT-007 | feat | open | normal | 3 | [Асинхронный HITL-inbox](FEAT-007-async-hitl-inbox.md) |
| FEAT-012 | feat | open | normal | 3 | [Карточка HITL в форме допущений, а не запроса разрешения](FEAT-012-hitl-card-as-assumptions.md) |
| FEAT-008 | feat | open | normal | 4 | [Компенсации и бюджет прогона](FEAT-008-compensations-and-run-budget.md) |
| FEAT-011 | feat | open | normal | 4 | [Храповик знания: остановка обязана произвести долговременный артефакт](FEAT-011-knowledge-ratchet.md) |
| FEAT-013 | feat | open | normal | 4 | [Инвалидация `observed` при смене версии и изменении области мимо SDX](FEAT-013-observed-invalidation.md) |
| DEBT-031 | debt | open | normal | 5 | [Жизненный цикл обрывается на L5: нет Operate / Evolve / Retire](DEBT-031-lifecycle-stops-at-l5.md) |
| IDEA-010 | idea | open | normal | 5 | [Карта освоенности как продуктовый артефакт диагностики](IDEA-010-readiness-map-as-product-artifact.md) |
| PROC-018 | proc | open | normal | 5 | [Авторежим гейтов по умолчанию (инверсия ADR-014)](PROC-018-auto-gate-mode-by-default.md) |
| PROC-021 | proc | open | normal | 5 | [Позиционирование SDX как design-time двойника ядра Конструктора](PROC-021-sdx-as-design-time-twin.md) |
| PROC-014 | proc | open | normal | 7 | [Субагенты: девять → два](PROC-014-subagents-nine-to-two.md) |
| DEBT-029 | debt | open | normal | null | [Три ветки `/sdx:audit` не исполнялись: исход `CLEAN`, правило `-N`, штатная конфигурация инструментов агента](DEBT-029-audit-run-unexercised-branches.md) |
| DEBT-030 | debt | open | normal | null | [Значение `model` во frontmatter агентов не валидируется ничем — тихий сбой в рантайме](DEBT-030-agent-model-tier-not-validated.md) |
| DEBT-033 | debt | open | normal | null | [Конвенция тела записи бэклога описана в шести местах и разошлась; верны две редакции из шести](DEBT-033-backlog-body-convention-scattered.md) |
| DEBT-035 | debt | open | normal | null | [Два инварианта флагов enforced только прозой команд](DEBT-035-flag-invariants-prose-only.md) |
| FEAT-002 | feat | open | normal | null | [Мультиязычность плагина: ревизия и улучшения](FEAT-002-plugin-multilingual-support.md) |
| PROC-006 | proc | open | normal | null | [Публичность и трекшн: путь к программе Claude for Open Source](PROC-006-oss-publicity-traction.md) |
| PROC-008 | proc | open | normal | null | [Длинный DESIGN.md — систематический источник дрейфа при итеративной доработке](PROC-008-long-design-drift.md) |
| PROC-009 | proc | open | normal | null | [Структурированное размещение входящих артефактов проекта](PROC-009-incoming-artifacts-placement.md) |
| PROC-010 | proc | open | normal | null | [Параллельные субагенты Execution пишут в общие файлы сессии без protocol'а разрешения гонок](PROC-010-parallel-subagents-shared-session-files.md) |
| PROC-011 | proc | open | normal | null | [Синхронизацию DESIGN с кодом нельзя вести параллельно с правкой кода](PROC-011-design-sync-after-code-not-parallel.md) |
| PROC-022 | proc | open | normal | null | [Границы типа `intake`: вправе ли он дополнять существующие записи и вести слой сверки против закрытых](PROC-022-intake-vs-audit-backlog-operations.md) |
| PROC-024 | proc | open | normal | null | [Коллизия: п.4 Closeout требует заводить записи там, где тип `grooming` их создавать не вправе](PROC-024-closeout-record-creation-vs-grooming-ban.md) |
| PROC-025 | proc | open | normal | null | [В номенклатуре типов сессий нет исследования: работа, производящая документ и не производящая кода](PROC-025-no-session-type-for-research.md) |
| PROC-026 | proc | open | normal | null | [Груминг пересматривает атрибуты записи, не сверяя её с кодом](PROC-026-grooming-without-code-verification.md) |
| PROC-027 | proc | open | normal | null | [У поверхностей, пересказывающих состав системы, нет сторожа](PROC-027-inventory-drift-unguarded.md) |
| PROC-015 | proc | open | low | 7 | [Тиры моделей: четыре → два](PROC-015-model-tiers-four-to-two.md) |
| BUG-009 | bug | open | normal | null | [Нечисловой `.stopgate.count` роняет `stop-gate` кодом 1 — тест-пол исчезает молча](BUG-009-stop-gate-nonnumeric-counter.md) |
| BUG-010 | bug | open | normal | null | [`selftest.sh` и его проводка непереносимы за пределы GNU-окружения](BUG-010-selftest-platform-portability.md) |
| DEBT-036 | debt | open | normal | null | [Ветка автодетекта тест-команды в `stop-gate` не покрыта автотестами](DEBT-036-stop-gate-autodetect-branch-untested.md) |
| DEBT-040 | debt | open | normal | null | [Часть сценариев мутирует хелперы, написанные внутри самого сьюта](DEBT-040-tests-mutate-own-helpers.md) |
| DEBT-039 | debt | open | low | null | [Поле `status` в схеме `session_state.json` объявлено без писателя](DEBT-039-session-state-status-no-writer.md) |
| DEBT-041 | debt | open | low | null | [Anti-overclaim-линт направленный: ловит один порядок слов из двух](DEBT-041-overclaim-lint-directional.md) |
| DEBT-013 | debt | open | low | null | [У раннера `.claude/sdx/verify-cmd.sh` нет собственного автотеста](DEBT-013-verify-cmd-runner-no-autotest.md) |
| DEBT-020 | debt | open | low | null | [Каталоги разборов без индекса; формулировка ADR-017 разошлась с фактом](DEBT-020-history-review-dirs-no-index.md) |
| DEBT-027 | debt | open | low | null | [Постоянные документы ссылаются на доплагинный путь `.claude/sdx/hooks/`](DEBT-027-legacy-hook-paths-in-permanent-docs.md) |
| DEBT-032 | debt | open | low | null | [П.4 Closeout-чек-листа требует поля `session` там, где конвенция бэклога отводит `source`](DEBT-032-closeout-session-field-convention-drift.md) |
| IDEA-007 | idea | open | low | null | [Автоматический пуш записей бэклога в GitHub Issues](IDEA-007-backlog-github-issues-sync.md) |
| DEBT-023 | debt | deferred | normal | null | [Гейт `/sdx:proto` не показывает содержимое новых файлов прототипа](DEBT-023-proto-gate-new-files-diff.md) |
| IDEA-002 | idea | deferred | normal | null | [Fanout-контур: stateless-задачи по портфелю репозиториев (REQ-LANE-1)](IDEA-002-fanout-contour.md) |
| IDEA-003 | idea | deferred | normal | null | [Self-improving loop: стоимостный сигнал в Closeout (REQ-LOOP-1)](IDEA-003-self-improving-loop.md) |
| IDEA-004 | idea | deferred | normal | null | [Расщепление назначения /sdx:checkpoint (REQ-CHECKPOINT-1)](IDEA-004-checkpoint-dual-purpose.md) |
| IDEA-009 | idea | deferred | normal | null | [Калибровка постановщика по расхождению `declared` / `observed`](IDEA-009-declarant-calibration.md) |
| IDEA-001 | idea | deferred | low | null | [REQ-CACHE-1 (Фаза 2) остаётся актуальным](IDEA-001-req-cache-1-deterministic-context-order.md) |
| IDEA-006 | idea | deferred | low | null | [Опциональный escalate-тир параллельного Execution](IDEA-006-parallel-escalate-tier.md) |
| IDEA-008 | idea | deferred | low | null | [Инструмент сравнения прогонов аудита (тренд находок во времени)](IDEA-008-audit-run-comparison.md) |
| IDEA-011 | idea | deferred | low | null | [Внешний тикер для автономного пробуждения прогона](IDEA-011-external-ticker-for-run-wakeup.md) |

## Закрытые

| ID | Название | Сессия закрытия |
|----|----------|------------------|
| DEBT-007 | [Мёртвые поля в `session_state.json`](DEBT-007-dead-fields-session-state.md) | `proc-run-as-durable-unit-20260902` (расщеплена: `status` → `DEBT-039`) |
| BUG-005 | [Противоречие: ADR-005 ↔ `.claude/sessions/` в `.gitignore`](BUG-005-sessions-gitignore-adr005-contradiction.md) | `proc-run-as-durable-unit-20260902` (предпосылка неверна; фактически снято `ADR-012`) |
| PROC-019 | [«Прогон» как durable-единица работы вместо «сессии»](PROC-019-run-as-durable-unit.md) | `proc-run-as-durable-unit-20260902` |
| DEBT-038 | [Поля `artifacts` и `history` в `session_state.json` объявлены и мертвы](DEBT-038-session-state-dead-fields.md) | `proc-run-as-durable-unit-20260902` |
| DEBT-037 | [Живая проводка `SessionStart` → `selftest.sh` не исполнялась ни разу](DEBT-037-selftest-live-wiring-unverified.md) | — (закрыта наблюдением вне сессии, плагин 2.2.0) |
| FEAT-014 | [Self-test enforcement-слоя как условие входа в автономный режим](FEAT-014-enforcement-selftest-autonomy-precondition.md) | `feat-enforcement-selftest-20260901` |
| DEBT-010 | [Тихая деградация хуков не видна пользователю](DEBT-010-silent-hook-degradation-invisible.md) | `feat-enforcement-selftest-20260901` |
| DEBT-026 | [`stop-gate` определяет тест-команду по биту выполнения — потеря бита молча снимает тест-пол](DEBT-026-stop-gate-verify-cmd-exec-bit.md) | `fix-stop-gate-exec-bit-20260901` |
| BUG-003 | [`/sdx:switch` делает `git add -A` с авто-коммитом](BUG-003-switch-git-add-a-autocommit.md) | — (сверка с кодом вне сессии; дефект снят `1ade803`, ADR-012) |
| PROC-012 | [Треки: пять → одна шкала + два режима](PROC-012-tracks-collapse.md) | `refactor-tracks-collapse-20260901` |
| PROC-013 | [Enforcement по необратимости, а не по порядку этапов](PROC-013-enforcement-by-irreversibility.md) | `refactor-tracks-collapse-20260901` |
| DEBT-003 | [Обход stage-gate через Bash не зафиксирован как граница](DEBT-003-stage-gate-bash-bypass-undocumented.md) | `refactor-tracks-collapse-20260901` |
| DEBT-009 | [Discovery на standard-треке не имеет определённого артефакта](DEBT-009-discovery-standard-no-artifact.md) | `refactor-tracks-collapse-20260901` |
| DEBT-014 | [stage-gate на Verification не пускает тесты хуков](DEBT-014-stage-gate-blocks-hook-tests.md) | `refactor-tracks-collapse-20260901` |
| DEBT-015 | [Пробелы тестового покрытия stage-enforcement](DEBT-015-stage-guard-coverage-gaps.md) | `refactor-tracks-collapse-20260901` |
| DEBT-016 | [stage-write-guard.sh не разрешает сегмент `..` в пути](DEBT-016-stage-write-guard-parent-segment.md) | `refactor-tracks-collapse-20260901` |
| DEBT-024 | [Инвариант ADR-001 «трек не привязан к типу» сужен дважды без пометки](DEBT-024-adr-001-invariant-narrowed-twice.md) | `refactor-tracks-collapse-20260901` |
| DEBT-025 | [Ручной прогон трека vibe не выполнен — покрытие видимое](DEBT-025-vibe-manual-test-not-executed.md) | `refactor-tracks-collapse-20260901` |
| PROC-023 | [Триада SDX прозаична, а формат спецификаций процессов обязан компилироваться](PROC-023-triad-prose-vs-compilable-spec.md) | `design-spec-format-feasibility-20260901` |
| BUG-007 | [`/sdx:init` создаёт каталоги разборов без файлов-заглушек](BUG-007-init-history-dirs-no-placeholder.md) | `feat-audit-agent-20260726` |
| BUG-008 | [Зависимость от бита выполнения: ложный FAIL Closeout + тихая смерть enforcement-слоя](BUG-008-archive-verify-exec-bit-dependency.md) | `fix-archive-verify-exec-bit-20260725` |
| BUG-004 | [Противоречие verify.md ↔ reviewer.md: кто вычисляет diff](BUG-004-diff-computation-mismatch.md) | `fix-diff-computation-contract-20260722` |
| DEBT-017 | [Перечисления треков в `agents/qa.md`/`developer.md`/`devops.md` не включают `doc`](DEBT-017-agent-track-enumerations-incomplete.md) | `fix-track-consistency-20260722` |
| DEBT-018 | [Столбец «Типы сессий» в README стирает жёсткость привязки типа к треку `doc`](DEBT-018-readme-track-type-binding-blurred.md) | `fix-track-consistency-20260722` |
| DEBT-019 | [doc-специфика пп. 2/3 Closeout не продублирована в `archive.md`](DEBT-019-archive-checklist-doc-specifics-partial.md) | `fix-track-consistency-20260722` |
| DEBT-021 | [Уже мигрированные вручную источники не помечены `SDX-MIGRATED`](DEBT-021-migrated-sources-unmarked.md) | `fw-reconcile-debt-20260720` |
| DEBT-022 | [`/sdx:reconcile` не определяет поведение для `.sdx/bundles/`](DEBT-022-reconcile-bundles-not-in-scan-list.md) | `fw-reconcile-debt-20260720` |
| PROC-004 | [Режим экстремального прототипирования (vibe)](PROC-004-vibe-prototyping-mode.md) | `feat-vibe-track-20260720` |
| PROC-002 | [Груминг / ретроспектива / постмортем как типы сессий](PROC-002-grooming-retro-postmortem-session-types.md) | `fw-session-types-20260720` |
| DEBT-001 | [Весь enforcement держится на самодекларируемом поле `stage`](DEBT-001-self-declared-stage-field.md) | `fw-stage-guard-20260720` |
| DEBT-011 | [`/sdx:backtrack` недоспецифицирован](DEBT-011-backtrack-underspecified.md) | `fw-stage-guard-20260720` |
| DEBT-004 | [Мета-проект имеет тест-сьют, но не «доедает свой корм»](DEBT-004-meta-project-no-dogfood-tests.md) | `fw-dogfood-verifycmd-20260720` |
| FEAT-001 | [Англоязычная документация для GitHub-аудитории](FEAT-001-english-docs-github.md) | `fw-readme-en-20260720` |
| BUG-006 | [stage-gate на Windows блокирует не-md файлы в .claude/sessions](BUG-006-stage-gate-windows-backslash-paths.md) | `fw-stagegate-winpath-20260720` |
| PROC-007 | [Активные рекомендации по улучшению в ходе реальных сессий](PROC-007-proactive-improvement-recommendations.md) | `fw-stagegate-winpath-20260720` |
| BUG-001 | [Stage-gate блокирует qa и developer на стадии Verification — КРИТИЧНО](BUG-001-stage-gate-blocks-verification-writes.md) | `fw-enforce-a1a2-20260703` |
| BUG-002 | [Prod-guard fail-closed блокирует весь Bash даже без сконфигурированной защиты](BUG-002-prod-guard-failclosed-blocks-bash.md) | `fw-enforce-a1a2-20260703` |
| DEBT-002 | [Stop-gate гоняет полный тест-сьют на каждом завершении хода](DEBT-002-stop-gate-full-suite-per-stop.md) | `fw-econ-a4d1-20260703` |
| DEBT-005 | [Сработало обязательство обновить раскладку моделей на новое поколение](DEBT-005-model-generation-upgrade-obligation.md) | `fw-model-aliases-20260702` |
| DEBT-006 | [Раскладка моделей продублирована в трёх местах](DEBT-006-model-layout-duplicated.md) | `fw-model-aliases-20260702` |
| DEBT-008 | [Roadmap Фаз 2–4 живёт в gitignored-файле — риск потери](DEBT-008-roadmap-gitignored-risk.md) | `fw-roadmap-20260720` |
| DEBT-012 | [`@protocol.md` инжектится каждой командой](DEBT-012-protocol-injected-every-command.md) | `fw-econ-a4d1-20260703` |
| PROC-001 | [У patch-трека нет ни одного слоя проверки по умолчанию](PROC-001-patch-track-no-default-verification.md) | `fw-auto-gates-20260719` |
| PROC-003 | [Формализация бэклога: структура, префиксы, команды, волны](PROC-003-backlog-formalization.md) | `fw-backlog-20260719` |
| PROC-005 | [Авторежим: смягчение пользовательских гейтов по запросу (фидбек 2026-07-19)](PROC-005-auto-mode-gate-softening.md) | `fw-auto-gates-20260719` |
