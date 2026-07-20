# Бэклог фреймворка SDX

Каталог `docs/backlog/` — постоянный трекаемый бэклог фреймворка. Каждая запись — отдельный
файл `<ID>-<slug>.md` с машиночитаемым YAML frontmatter (интеграционная точка будущего плагина
портфельного управления) и телом в свободной прозе (`## Суть`, `## Рекомендация`, для закрытых/
отложенных записей — `## Резолюция`). Идентификатор строится по схеме `<PREFIX>-<NNN>` со
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

## Открытые

| ID | type | status | priority | wave | Название |
|----|------|--------|----------|------|----------|
| BUG-004 | bug | open | normal | 5 | [Противоречие verify.md ↔ reviewer.md: кто вычисляет diff](BUG-004-diff-computation-mismatch.md) |
| BUG-003 | bug | open | normal | 8 | [`/sdx:switch` делает `git add -A` с авто-коммитом](BUG-003-switch-git-add-a-autocommit.md) |
| BUG-005 | bug | open | normal | 9 | [Противоречие: ADR-005 требует инкрементальных коммитов сессии ↔ `.claude/sessions/` в `.gitignore`](BUG-005-sessions-gitignore-adr005-contradiction.md) |
| DEBT-003 | debt | open | normal | 10 | [Обход stage-gate через Bash не зафиксирован как граница](DEBT-003-stage-gate-bash-bypass-undocumented.md) |
| DEBT-007 | debt | open | normal | 10 | [Мёртвые поля в `session_state.json`](DEBT-007-dead-fields-session-state.md) |
| DEBT-009 | debt | open | normal | 10 | [Discovery на standard-треке не имеет определённого артефакта](DEBT-009-discovery-standard-no-artifact.md) |
| DEBT-010 | debt | open | normal | 10 | [Тихая деградация хуков не видна пользователю](DEBT-010-silent-hook-degradation-invisible.md) |
| PROC-002 | proc | open | normal | null | [Груминг / ретроспектива / постмортем как типы сессий](PROC-002-grooming-retro-postmortem-session-types.md) |
| DEBT-014 | debt | open | normal | null | [stage-gate на Verification не пускает тесты хуков](DEBT-014-stage-gate-blocks-hook-tests.md) |
| DEBT-015 | debt | open | normal | null | [Пробелы тестового покрытия нового stage-enforcement](DEBT-015-stage-guard-coverage-gaps.md) |
| PROC-008 | proc | open | normal | null | [Длинный DESIGN.md — систематический источник дрейфа](PROC-008-long-design-drift.md) |
| PROC-009 | proc | open | normal | null | [Структурированное размещение входящих артефактов проекта](PROC-009-incoming-artifacts-placement.md) |
| PROC-004 | proc | open | normal | null | [Режим экстремального прототипирования (vibe)](PROC-004-vibe-prototyping-mode.md) |
| FEAT-002 | feat | open | normal | null | [Мультиязычность плагина: ревизия и улучшения](FEAT-002-plugin-multilingual-support.md) |
| PROC-006 | proc | open | normal | null | [Публичность и трекшн: путь к программе Claude for Open Source](PROC-006-oss-publicity-traction.md) |
| IDEA-007 | idea | open | low | null | [Автоматический пуш записей бэклога в GitHub Issues](IDEA-007-backlog-github-issues-sync.md) |
| DEBT-013 | debt | open | low | null | [У раннера `.claude/sdx/verify-cmd.sh` нет собственного автотеста](DEBT-013-verify-cmd-runner-no-autotest.md) |
| DEBT-016 | debt | open | low | null | [`stage-write-guard.sh` не разрешает сегмент `..` в пути](DEBT-016-stage-write-guard-parent-segment.md) |
| IDEA-002 | idea | deferred | normal | null | [Fanout-контур: stateless-задачи по портфелю репозиториев (REQ-LANE-1)](IDEA-002-fanout-contour.md) |
| IDEA-003 | idea | deferred | normal | null | [Self-improving loop: стоимостный сигнал в Closeout (REQ-LOOP-1)](IDEA-003-self-improving-loop.md) |
| IDEA-004 | idea | deferred | normal | null | [Расщепление назначения /sdx:checkpoint (REQ-CHECKPOINT-1)](IDEA-004-checkpoint-dual-purpose.md) |
| IDEA-005 | idea | deferred | normal | null | [Процедура lean-аудита и правило «инвариант-в-прозе → хук» (REQ-LEAN-1)](IDEA-005-lean-audit-procedure.md) |
| IDEA-006 | idea | deferred | low | null | [Опциональный escalate-тир параллельного Execution](IDEA-006-parallel-escalate-tier.md) |
| IDEA-001 | idea | deferred | low | null | [REQ-CACHE-1 (Фаза 2) остаётся актуальным](IDEA-001-req-cache-1-deterministic-context-order.md) |

## Закрытые

| ID | Название | Сессия закрытия |
|----|----------|------------------|
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
