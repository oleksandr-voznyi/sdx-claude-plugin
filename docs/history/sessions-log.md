# Журнал сессий SDX (глобальный лог знаний)

Краткие итоги завершённых сессий. Детали — в `docs/specs/`, `docs/designs/`, `docs/history/plans/`.

---

## 2026-06-27 — fw-enforce-route-20260627 (refactor, трек full)

**Цель:** Фаза 1 бандла `sdx-efficiency-automation-2026` — enforcement-пол (хуки) + per-agent model routing.

**Сделано:**
- Enforcement-слой из 4 детерминированных хуков (`.claude/sdx/hooks/`): `stage-gate` (заморозка кода до Execution), `stop-gate` (тест-пол под Verification), `prod-guard` (блок прод-команд, opt-in), `archive-verify` (Closeout-инварианты 1/5/6). Проводка — `.claude/settings.json`.
- Механизм блокировки PreToolUse — JSON `permissionDecision:"deny"` (НЕ deprecated `exit 2`); подтверждено на бинарнике Claude Code 2.1.195.
- Per-agent model routing во frontmatter 8 агентов: `reviewer`→`claude-opus-4-8`, `tech-writer`→`claude-haiku-4-5`, остальные→`claude-sonnet-4-6`. Политика эскалации архитектора на Opus 4.8 для проектных решений — задокументирована в `architect.md`.
- Текстовые дельты: `protocol.md` (раздел «Enforcement-слой»), `CLAUDE.md` (§2 model-note, §3 Closeout→archive-verify), `archive.md`, `verify.md`.

**Верификация:** GATE PASS (fresh-eyes на Opus), 0 FAIL; 2 WARN устранены (баг loop-guard stop-gate на no-op-пути + покрытие зелёного пути). 23/23 unit-теста хуков зелёные.

**Затронутые документы:** `docs/specs/phase1-enforcement-routing.md`, `docs/designs/phase1-enforcement-routing.md`, `docs/history/plans/fw-enforce-route-20260627.md`.

**Отложено (Фазы 2–4):** REQ-LANE-1 (fanout), REQ-LOOP-1 (self-improving), REQ-CACHE-1, REQ-LEAN-1, REQ-CHECKPOINT-1, parallel escalate-тир.

**Ветка:** `sdx/fw-enforce-route-20260627` → слита в `main`.

---

## 2026-07-02 — fw-model-aliases-20260702 (refactor, трек standard)

**Цель:** Находки аудита B1+B2 — уход от протухающего пина поколения моделей и дедупликация раскладки.

**Сделано:**
- Frontmatter 8 агентов переведён с конкретных model ID на алиасы тиров: `reviewer`→`opus`, `tech-writer`→`haiku`, остальные→`sonnet` (шесть агентов автоматически поднялись на актуальное поколение рабочего тира).
- `CLAUDE.md` §2 — конкретные ID заменены принципом раскладки по тирам; источник истины — frontmatter агентов.
- `architect.md` — политика эскалации переписана в терминах тиров (`opus` на Technical Design).
- `docs/DECISIONS.md` — ADR-008 (алиасы вместо пина поколения; трейд-офф «меньше контроля» принят, инварианты зафиксированы). Отменяет решение DESIGN Фазы 1 «полные ID пиннят поколение».
- В ветке также впервые заверсионирован аудит-бэклог `docs/audit-2026-07-01-recommendations.md` (14 находок, план сессий доработок); статусы B1/B2 закрыты.

**Верификация:** PASS fresh-eyes (`reviewer` на алиасе `opus`): 0 FAIL, 2 WARN — оба квитированы правкой контракта (`change_note.md`), не молчаливым принятием. Регрессия: 4/4 тест-сьюта хуков зелёные.

**Затронутые документы:** `.claude/agents/*.md` (8), `CLAUDE.md`, `docs/DECISIONS.md` (ADR-008), `docs/audit-2026-07-01-recommendations.md`.

**Ветка:** `sdx/fw-model-aliases-20260702` → слита в `main`.

---

## 2026-07-03 — fw-enforce-a1a2-20260703 (bug, трек standard)

**Цель:** Находки аудита A1+A2 — два дефекта enforcement-слоя (приоритет #1 бэклога).

**Сделано:**
- **A1** (`stage-gate.sh`): на стадии Verification открыты тестовые каталоги (`tests/**`, `test/**`, `spec/**`, вкл. вложенные) — узаконена роль `qa` (пишет интеграционные тесты на Verification). Не-тестовый код остаётся заморожен; правки FAIL-находок — через `/sdx:backtrack --to Execution`. Со-локованные тесты — через per-project `stage-gate.allow`. Выбрана предпочтительная модель из рекомендации → `qa.md`/`verify.md` править не потребовалось.
- **A2** (`prod-guard.sh`): проверка `prod-guard.conf` (наличие + скан активного паттерна) поднята выше проверки `jq`. На проекте без сконфигурированной защиты отсутствие `jq` больше не блокирует каждую Bash-команду; fail-closed сохранён для проектов с заполненным conf.
- Тесты: `test-stage-gate.sh` (+2: Verification allow/deny), `test-prod-guard.sh` (+2: no-op без jq при отсутствии/пустоте conf).

**Верификация:** PASS fresh-eyes (`reviewer` на `opus`): 0 FAIL, 2 WARN — оба квитированы (WARN-1 `spec/` оставлен осознанно; WARN-2 дописан в контракт). Прогон всех сьютов хуков: 35 passed, 0 failed.

**Затронутые документы:** `.claude/sdx/protocol.md` (§Enforcement — stage-gate/prod-guard), `docs/designs/phase1-enforcement-routing.md` (§Доработки после Фазы 1), `docs/audit-2026-07-01-recommendations.md` (A1/A2 → закрыто).

**Замечено (в бэклог):** C7 — `.claude/sessions/` в `.gitignore` противоречит ADR-005 (инкрементальные коммиты сессии); файлы сессии этой сессии жили только локально. Отдельная сессия рефакторинга (в связке с C2).

**Ветка:** `sdx/fw-enforce-a1a2-20260703` → слита в `main`.

---

## 2026-07-03 — fw-session-worktree-20260703 (refactor, трек full)

**Цель:** Находки аудита C7+C2 + новое требование автоопределения основной ветки. Три связанных дефекта: (C7) ADR-005 обещал инкрементальные коммиты артефактов, но `.claude/sessions/` был в `.gitignore` — коммит невозможен; (C2) `/sdx:switch` делал слепой `git add -A && commit` в общем дереве; хардкод `main` как имени основной ветки в хуках/командах.

**Сделано:**
- **Модель «сессия = worktree = ветка» (ADR-009).** Одна сессия = git worktree в gitignored `.sdx/worktrees/<id>/` на ветке `sdx/<id>`; содержательные артефакты версионируются, `.stopgate.*` игнорируются точечным паттерном. Closeout по **варианту A**: `git rm -r` каталога сессии коммитом НА ВЕТКЕ до мёржа `--no-ff` → основная ветка не видит файлы сессии даже мимолётно, но история достижима через merge-DAG.
- **Автоопределение основной ветки (ADR-010).** Новый `lib/default-branch.sh`: `origin/HEAD` → `init.defaultBranch` → эвристика `main`/`master` → last-resort. Переиспользуется хуками и prose-командами. Хардкод `main` устранён.
- **`archive-verify.sh` переработан:** резолв ветки через хелпер, инвариант 6 = каталог сессии не tracked в дереве основной ветки, освобождение через `git worktree remove --force` вместо `rm -rf`.
- **Команды `/sdx:*`:** `start` (worktree add + seed-commit + хендофф), `switch` (навигация через `git worktree list`, [REMOVED] авто-коммит), `archive` (двухфазный вариант A), `verify` (динамический diff + исключение `.claude/sessions/**`), `init` (targeted-паттерны), `status` (листинг worktree), `next`/`checkpoint` (явные commit-шаги артефактов).

**Верификация:** PASS fresh-eyes (`reviewer`, контракт изоляции): 0 FAIL, 3 WARN + 1 INFO. WARN-1 (`next`/`checkpoint` не коммитили) и WARN-2 (висячая ссылка `--phase2`) — устранены; WARN-3/INFO квитированы. Юнит-сьют хуков: 49 passed (default-branch 6, archive-verify 18, stop-gate 8, stage-gate 8, prod-guard 9). Эмпирическая приёмка на реальных worktree/`master`-репо: 14/14 (линчпин REQ-WT-1, инвариант 5 на `master`, REQ-SESS/WT сквозной).

**Затронутые документы:** `docs/specs/session-worktree-model.md` (новый), `docs/designs/session-worktree-model.md` (новый), `docs/DECISIONS.md` (ADR-009/010 + реконсиляция §Процессные соглашения под ADR-010/`--no-ff`), `docs/designs/phase1-enforcement-routing.md` (§Доработки — archive-verify переработан), `.claude/sdx/protocol.md` (модель сессии/Enforcement/Closeout под вариант A), `CLAUDE.md §6`, `.gitignore`.

**Примечание:** Эта сессия — **последняя в старой (не-worktree) модели**: велась в основном дереве, каталог был gitignored до этой правки. Closeout выполнен по гибридной процедуре (`closeout_prep.md`): `git worktree remove` = n/a, удаление каталога — обычным `git rm`. Начиная со следующей сессии действует worktree-модель.

**Ветка:** `sdx/fw-session-worktree-20260703` → слита в `main`.

---

## 2026-07-03 — fw-econ-a4d1-20260703 (refactor, трек standard)

**Цель:** Две находки аудита: A4 (stop-gate гоняет полный тест-сьют на каждом `Stop`, даже без изменений кода) и D1 (полный `@protocol.md` инжектится каждой командой — лишние токены). Первая сессия под worktree-моделью (ADR-009).

**Сделано:**
- **A4 — green-run cache в stop-gate (ADR-011).** `stop-gate.sh` сверяет отпечаток рабочего дерева (`git rev-parse HEAD` + md5 от `git status --porcelain`) с отпечатком последнего зелёного прогона в `.stopgate.ok`; при неизменном дереве повторный `Stop` пропускается без перезапуска verify. Проверка размещена после резолва verify-команды и до инкремента loop-guard (кэш-хит не крутит `.stopgate.count`). Запись только при зелёном прогоне; красный кэш не пишет. `SDX_STOP_GATE=1` обходит чтение кэша, но зелёный форс обновляет `.stopgate.ok`. Семантика гейта (пол под красным) сохранена.
- **D1 — тонкие команды ссылаются на протокол текстом.** Снят `@`-инжект `protocol.md` у `status`, `checkpoint`, `switch`, `backtrack` (заменён текстовой ссылкой); `@`-инжект сохранён у `start`, `next`, `archive`, `verify`, `retrack`, `export`, `import`, `manual`.

**Верификация:** PASS. Корректность-исполнением (`qa`) + fresh-eyes (`reviewer`, контракт изоляции): 0 FAIL. Первичные 3 WARN (пробелы покрытия граничных веток A4) закрыты по решению пользователя дополнительными тестами `[10]`–`[12]` (bypass `SDX_STOP_GATE=1` + запись форсом, отсутствие `.stopgate.ok` под красным, кэш-хит не трогает loop-guard). Юнит-сьют `test-stop-gate.sh`: **13 passed, 0 failed**.

**Затронутые документы:** `docs/DECISIONS.md` (ADR-011), `docs/designs/phase1-enforcement-routing.md` (контракт stop-gate + green-run cache), `docs/specs/phase1-enforcement-routing.md` (REQ-GATE-2 критерий), `.claude/sdx/protocol.md` (Enforcement-слой, stop-gate), `docs/audit-2026-07-01-recommendations.md` (A4/D1 → закрыто). Код: `.claude/sdx/hooks/stop-gate.sh`, `.claude/sdx/hooks/test-stop-gate.sh`, `.claude/commands/sdx/{status,checkpoint,switch,backtrack}.md`.

**Ветка:** `sdx/fw-econ-a4d1-20260703` → слита в `main`.

## 2026-07-05 — fw-session-inplace-20260705 (refactor, трек standard)

**Цель:** Запрос пользователя — worktree-модель (ADR-009) операционно тяжела (хендофф на отдельный CLI при старте, два CLI на Closeout); упростить до непрерывной работы в одном CLI, сохранив «данные сессии на ветке, но не в main».

**Сделано:**
- Новая модель «сессия = ветка `sdx/<id>` в основном рабочем дереве, один CLI на весь цикл» (**ADR-012**): `/sdx:start` = `checkout -b` без хендоффа; `/sdx:switch` = `checkout` с гардом чистого дерева (без авто-коммита); `/sdx:archive` — однофазный чек-лист в одном CLI.
- Сохранено из ADR-009: версионирование артефактов на ветке (REQ-SESS-1..4), вариант A (`git rm -r` до мёржа), инварианты archive-verify 1/5/6, ADR-010. Снято: REQ-WT-1/3/4/5.
- Хуки: ноль правок логики (резолв сессии по имени ветки уже был); в `archive-verify.sh` — только комментарий, условный `worktree remove` оставлен как legacy compat.
- Текстовые дельты: `protocol.md` (модель, Closeout), `start/switch/archive/status/init/verify.md`, `CLAUDE.md` §6, баннеры пересмотра в `docs/specs|designs/session-worktree-model.md`.

**Верификация:** GATE PASS (fresh-eyes, 0 FAIL, 1 WARN — дрейф постоянных SPEC/DESIGN, закрыт баннерами на Closeout). Тесты хуков: 18+13+8+6 — все зелёные. Сессия сама прошла весь цикл в одном CLI (догфуд новой модели).

**Затронутые документы:** `docs/specs/session-inplace-model.md` (новый), `docs/DECISIONS.md` (ADR-012), баннеры в `session-worktree-model.md` (spec+design).

**Ветка:** `sdx/fw-session-inplace-20260705` → слита в `main`.

## 2026-07-19 — fw-plugin-20260719 (refactor, трек standard)

**Цель:** Запрос пользователя — собрать SDX в виде плагина Claude Code, чтобы вести SDD в разных проектах на одном сервере без тиражирования фреймворка.

**Сделано:**
- Root-as-plugin (**ADR-013**): корень репо = плагин `sdx` + локальный marketplace (`.claude-plugin/{plugin,marketplace}.json`); установка `/plugin marketplace add <репо>` → `/plugin install sdx@sdx --scope user`.
- Перенос из `.claude/` в корень: `commands/` (13), `agents/` (8), `hooks/hooks.json` (проводка вместо `.claude/settings.json`), `sdx/{protocol.md, hooks/**, templates/}`. Пути фреймворка в контенте — `${CLAUDE_PLUGIN_ROOT}/sdx/...`; ссылки на протокол — текстовым Read вместо `@`-инжекта.
- `/sdx:init` переписан под per-project слой: структура `docs/`+`.claude/`, targeted-`.gitignore`, раскладка шаблонов конфигов enforcement, детект legacy-копий фреймворка, опциональный SDX-блок в CLAUDE.md проекта (`sdx/templates/claude-md-snippet.md`).
- Новые доки: `README.md` (установка/состав), `docs/specs/plugin-distribution.md` (REQ-PLUGIN-1..6), `docs/designs/plugin-distribution.md`; CLAUDE.md §6 переписан под плагинную модель.
- Плагин установлен на машину (scope user) и проверен вживую.

**Верификация:** GATE PASS (fresh-eyes `reviewer`: 0 FAIL, 2 WARN — оба закрыты: подстановка `${CLAUDE_PLUGIN_ROOT}` подтверждена эмпирически headless-прогоном `/sdx:status` в постороннем проекте; README-косметика исправлена). Тесты хуков после релокации: 6+8+9+13+18 = **54 passed, 0 failed**. Stage-gate из hooks.json плагина вживую заблокировал запись в код на стадии Verification.

**Затронутые документы:** `docs/DECISIONS.md` (ADR-013), `docs/specs/plugin-distribution.md` (новый), `docs/designs/plugin-distribution.md` (новый), `README.md` (новый), `CLAUDE.md` (§1/2/3/6), `sdx/protocol.md` (§Enforcement — проводка/пути).

**Ветка:** `sdx/fw-plugin-20260719` → слита в `main`.

## 2026-07-19 — fw-migrate-20260719 (feature, трек patch)

**Цель:** Перевод дистрибуции на GitHub и автоматизация раскатки: репо `sdx-claude-plugin` (private, `git@github.com:oleksandr-voznyi/sdx-claude-plugin.git`), скрипт массовой миграции серверов/проектов.

**Сделано:** папка разработки переименована в `sdx-claude-plugin`, репо создано и запушено; добавлен идемпотентный `scripts/sdx-migrate.sh` (jq → marketplace из GitHub → install user-scope → `extraKnownMarketplaces.sdx` c `autoUpdate: true` + `enabledPlugins` в `~/.claude/settings.json` → миграция проекта: удаление vendored-файлов, снятие legacy hook-проводки с сохранением кастомных хуков, объявление зависимости в project settings; без авто-коммита). README: установка с GitHub, раздел миграции, правило бампа `version`. Версия плагина 1.0.0 → 1.0.1.

**Верификация:** прогон на фикстурном legacy-проекте — legacy удалён, кастомный агент/хук и per-project слой сохранены, settings корректно трансформированы; машинная часть выполнила реальную чистую установку с GitHub (scope user, autoUpdate включён).

**Ветка:** `sdx/fw-migrate-20260719` → слита в `main`.

## 2026-07-19 — fw-auto-gates-20260719 (feature, трек standard)

**Цель:** Бэклог E4 (авторежим гейтов по фидбеку реального использования) + C3 (у patch-трека не было ни одного обязательного слоя независимой проверки).

**Сделано:**
- **Авторежим гейтов (ADR-014):** поле `gate_mode: interactive|auto` в `session_state.json` (opt-in: `/sdx:start --auto` или предложение на Discovery/Change-гейте). При `auto` прозаические подтверждения принимают дефолты с фиксацией каждой развилки в трек-независимом `auto_decisions.md`; единственная обязательная остановка — дисклоуз на входе в Closeout (WARN первыми, одно подтверждение). Стоп-рубрика (закрытый список): коллизии триады, FAIL/красный тест-пол, внешние контракты/схемы данных, деструктив/prod-guard, эскалация трека (сбрасывает авто), `/sdx:manual`. Ключевой инвариант: детерминированные хуки `gate_mode` не читают — enforcement не смягчается.
- **Обязательная лёгкая верификация patch (C3):** Verification — активный этап patch-трека независимо от `gate_mode` (регрессионный тест + fresh-eyes против `change_note.md`, без вызова `qa`); `/sdx:archive` не начинает чек-лист без `verification_report.md` без FAIL.
- Инвариант ADR-004 «WARN требует явного квитирования» уточнён: в авто — отложенное квитирование через дисклоуз.
- Правки только прозы: `sdx/protocol.md`, `commands/{start,next,verify,archive,retrack}.md`, `CLAUDE.md` §3/§4, ADR-014. Хуки не менялись (регрессия 54/54 зелёные).

**Верификация:** GATE PASS (fresh-eyes `reviewer` на `opus`, контракт изоляции: change_note + diff 269 строк): 0 FAIL, 2 WARN, 1 INFO. Полная матрица трассируемости (10 решений, 8 файлов). WARN квитированы явным решением пользователя: F1 (противоречие verify.md шаг 1↔2 про qa на patch) — закрыт правкой поставки; F2 (дисклоуз как гейт входа vs «пункт чек-листа» контракта) — закрыт правкой контракта с обоснованием (сохранение нумерации чек-листа 1–8).

**Затронутые документы:** `docs/specs/gate-mode-auto.md` (новый, REQ-AUTO-1..6, REQ-WARN-1, REQ-PATCHV-1/2), `docs/DECISIONS.md` (ADR-014), `docs/audit-2026-07-01-recommendations.md` (E4/C3 → закрыто), `CLAUDE.md`, `sdx/protocol.md`.

**Замечено (догфуд):** stage-gate корректно заблокировал бамп версии `plugin.json` на стадии Closeout (json ≠ always-allow) — бамп 1.0.1→1.1.0 выполнен post-merge отдельным chore-коммитом; обход через Bash сознательно не использован (граница A5).

**Ветка:** `sdx/fw-auto-gates-20260719` → слита в `main`.

## 2026-07-19 — fw-backlog-20260719 (feature, трек standard, gate_mode auto)

**Цель:** Бэклог E2 — формализация бэклога: структура, префиксы, команды, волны.

**Сделано:**
- **Трекаемый бэклог (ADR-015):** каталог `docs/backlog/` — файл-на-запись с машиночитаемым YAML frontmatter (`id`, `type`, `status`, `priority`, `wave`, `source`, `session`, `links`; интеграционная точка будущего плагина портфельного управления), префиксы ID `FEAT-`/`BUG-`/`DEBT-`/`IDEA-`/`PROC-`, статусы `open|in-progress|closed|deferred`, индекс `README.md` (таблицы «Открытые»/«Закрытые»).
- **Команда `/sdx:backlog`** (`commands/backlog.md`): список / фильтры `--status/--type/--wave` / деталь `<ID>` / `add` (интервью, автономер, обновление индекса); сессии не требует.
- **Closeout-интеграция:** п.4 чек-листа (`sdx/protocol.md`, `commands/archive.md`) расширен актуализацией бэклога (закрытые записи → `closed`+`session`; отложенное и неквитированные WARN → новые `DEBT-`/`IDEA-`записи). Нумерация пунктов/инвариантов 1/5/6 сознательно не менялась.
- **Миграция:** все 23 находки A*–E* аудита 2026-07-01 перенесены с сохранением статусов (маппинг в поле `source`); файл аудита — исторический снапшот с баннером. `/sdx:init` создаёт `docs/backlog/` из нового шаблона `sdx/templates/backlog-readme.md`; `CLAUDE.md` §3/§6 актуализированы.
- Первая сессия, пройденная в `gate_mode: auto` от `/sdx:start --auto` до дисклоуза: 8 дефолтов в `auto_decisions.md`, одна остановка (дисклоуз перед Closeout) — механизм ADR-014 отработал штатно.

**Верификация:** GATE PASS (fresh-eyes `reviewer`, контракт изоляции: change_note + diff 960 строк): 0 FAIL, 2 WARN, 5 INFO; маппинг 23/23 сверен пофайлово. Обе WARN устранены до гейта (Closeout-нарратив `CLAUDE.md` §3; дублированное тело IDEA-001) — отложенного квитирования не потребовалось. Регрессия хуков: 5/5 сьютов зелёные (enforcement не затрагивался).

**Затронутые документы:** `docs/backlog/` (новый, 23 записи + индекс), `docs/specs/backlog-formalization.md` (новый, REQ-BL-1..6), `docs/DECISIONS.md` (ADR-015), `commands/backlog.md` (новая), `commands/{archive,init}.md`, `sdx/protocol.md`, `sdx/templates/backlog-readme.md` (новый), `CLAUDE.md`, `docs/audit-2026-07-01-recommendations.md` (баннер миграции).

**Ветка:** `sdx/fw-backlog-20260719` → слита в `main`.

## 2026-07-20 — fw-roadmap-20260720 (refactor, трек patch, gate_mode auto)

**Цель:** DEBT-008 (бывш. C1) — roadmap Фаз 2–4 жил только в gitignored-бандле `.sdx/bundles/upgrade_2026-06-27/` — один `rm`/clone уничтожал единственную полную спецификацию отложенных требований.

**Сделано:**
- **`docs/specs/phases-2-4-deferred.md`** (новый): полные формулировки REQ-LANE-1, REQ-CACHE-1, REQ-LOOP-1, REQ-CHECKPOINT-1, REQ-LEAN-1 и escalate-тира + их дизайн-срезы из бандла (§2.6–2.11), анти-требования (NOOP-PLANMODE/NOOP-TEAMS), критерии приёмки; раздел «Примечания актуализации» помечает устаревшее (model ID → алиасы ADR-008, пути хуков → плагин ADR-013, снапшот биллинга/TTL).
- **IDEA-002…IDEA-006** в `docs/backlog/` — трекинг-записи на каждое отложенное требование (все `deferred`); `IDEA-001` перелинкована на спеку; спека Фазы 1 ссылается на новую (раздел «Отложено»).
- Бандл остаётся локальным справочным артефактом (gitignored) — риск потери снят промоутом.

**Верификация (лёгкая обязательная, ADR-014):** GATE PASS (fresh-eyes `reviewer`: change_note + diff 294 строки): 0 FAIL, 1 WARN (разнобой статусов IDEA `open`/`deferred`) — устранена до гейта унификацией в `deferred`; сверка «перенос, не пересказ» с первоисточником подтверждена. Тесты хуков 5/5.

**Затронутые документы:** `docs/specs/phases-2-4-deferred.md` (новый), `docs/backlog/` (IDEA-002…006 новые; IDEA-001, DEBT-008, README), `docs/specs/phase1-enforcement-routing.md`.

**Ветка:** `sdx/fw-roadmap-20260720` → слита в `main`.
