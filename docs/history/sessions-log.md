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

## 2026-07-20 — fw-readme-en-20260720 (feature, трек patch, gate_mode auto)

**Цель:** FEAT-001 (фидбек пользователя 2026-07-20) — англоязычная точка входа для GitHub-аудитории: репо публичен, но вся пользовательская документация была только на русском.

**Сделано:**
- **`README.en.md`** (новый): полный английский перевод канонического README, взаимные ссылки RU↔EN, нота о рабочем языке плагина (русский, CLAUDE.md §1) со ссылкой на FEAT-002.
- **GitHub:** About репозитория переведён на английский (`gh repo edit`); заметки релизов v1.0.0/v1.0.1/v1.1.0/v1.2.0 дополнены секцией **English** (двуязычные, `gh release edit`).
- Попутная актуализация README (обе версии): 14 команд (+`backlog`), `docs/backlog/` в списке per-project слоя — дрейф после v1.2.0.
- **Бэклог:** FEAT-001 закрыта этой сессией; заведена FEAT-002 «Мультиязычность плагина: ревизия и улучшения (адаптивность, команда управления языковыми предпочтениями)» (open).

**Верификация (лёгкая обязательная, ADR-014):** GATE PASS (fresh-eyes `reviewer`: change_note + diff 184 строки): 0 FAIL, 0 WARN, 2 INFO (приняты); посекционная эквивалентность RU↔EN подтверждена, «14 команд» сверено с составом `commands/`. Тесты хуков 5/5.

**Затронутые документы:** `README.en.md` (новый), `README.md`, `docs/backlog/` (FEAT-001, FEAT-002 новые; README-индекс).

**Ветка:** `sdx/fw-readme-en-20260720` → слита в `main`.

## 2026-07-20 — fw-stagegate-winpath-20260720 (bug, трек standard, gate_mode auto)

**Цель:** BUG-006 (полевой репорт Windows-сессии) — stage-gate блокировал запись не-md файлов в `.claude/sessions/**`: `file_path` приходит с backslash-разделителями, срезка префикса `$CLAUDE_PROJECT_DIR` и slash-глобы allow-листа не срабатывали (проходил только `*.md`); рабочий процесс обходили через shell.

**Сделано:**
- **`sdx/hooks/stage-gate.sh`**: нормализация `\` → `/` в `target` и `proj` до вычисления `rel` и всех глобов (pure-bash, семантика гейта не изменена). TDD: сценарий 9 (backslash-путь сессии → allow; без фикса красный) и 10 (backslash-путь кода → deny, guard от расширения гейта); сьют 10/10, все 5 сьютов хуков зелёные. Регистр буквы диска (`C:`/`c:`) — вне скоупа (нет репро). Псевдокод в `docs/designs/phase1-enforcement-routing.md` актуализирован.
- **`sdx/protocol.md`**: секция «Непрерывное улучшение (рекомендации по ходу сессии)» (PROC-007) — оркестратор обязан озвучивать трение (workaround, ложное срабатывание хука, лишняя церемония) и предлагать `/sdx:backlog add`; молчаливый обход запрещён. Правило сработало в этой же сессии: stage-gate заблокировал бамп версии на Closeout (`.claude-plugin/` вне built-in allow) — решено штатно, паттерн `.claude-plugin/*` в `.claude/sdx/stage-gate.allow` мета-репо.
- **Бэклог:** BUG-006 и PROC-007 закрыты этой сессией; IDEA-007 «Автоматический пуш записей бэклога в GitHub Issues» (open, low).
- **Версия плагина:** 1.2.0 → 1.2.1 (фикс требует `/plugin marketplace update sdx` у пользователей).

**Верификация:** GATE PASS (fresh-eyes `reviewer`, контракт изоляции: change_note + diff): 0 FAIL, 0 WARN, 2 INFO (приняты); нетавтологичность сценария 9 и claim «вне скоупа» по остальным хукам подтверждены ревьюером. Ограничение: backslash-пути эмулированы на Unix — нужна проверка репортером на нативной Windows после обновления плагина.

**Затронутые документы:** `sdx/hooks/{stage-gate.sh,test-stage-gate.sh}`, `sdx/protocol.md`, `docs/designs/phase1-enforcement-routing.md`, `docs/backlog/` (BUG-006, PROC-007, IDEA-007 новые; README-индекс), `.claude-plugin/plugin.json`, `.claude/sdx/stage-gate.allow`.

**Ветка:** `sdx/fw-stagegate-winpath-20260720` → слита в `main`.

## 2026-07-20 — fw-dogfood-verifycmd-20260720 (refactor, трек standard, gate_mode auto)

**Цель:** DEBT-004 (wave 4, аудит A6) — мета-проект «не доедал свой корм»: в `sdx/hooks/` 5
тест-сьютов (56 юнит-тестов), но stop-gate на SDX-сессиях фреймворка молчал (нет
`verify-cmd.sh`, автодетект пуст), допущение «у мета-проекта нет тестов» устарело.

**Сделано:**
- **`.claude/sdx/verify-cmd.sh`** (новый, исполняемый): раннер всех `sdx/hooks/test-*.sh` —
  глоб (новые сьюты подхватываются автоматически), guard пустого глоба (громкий exit 1 вместо
  тихого no-op), все сьюты прогоняются даже при красном, сводка, exit 1 при любом провале.
  Полный прогон ~9 с. Stop-gate теперь активен на SDX-сессиях самого фреймворка (dogfooding) —
  подтверждено end-to-end на этой же сессии.
- **`commands/verify.md`**: примечание о stop-gate переформулировано генерически («проект без
  известной тест-команды» вместо «мета-проект без тест-сьюта»).
- **Датированные поправки DEBT-004**: ADR-4 и связанные места `docs/designs/phase1-enforcement-routing.md`
  (вкл. заметку [ОТЛОЖЕНО] про pre-commit — WARN-1 ревьюера, доправлен в сессии), допущение №4
  и REQ-GATE-2 в `docs/specs/phase1-enforcement-routing.md`. Механизм no-op-деградации не
  менялся — остаётся safe-by-default для проектов без тест-команды.
- **Косметика комментариев** (логика не тронута): `sdx/hooks/stop-gate.sh`,
  `sdx/templates/verify-cmd.sh.template` — «meta-project» → генерические формулировки.
- **Бэклог:** DEBT-004 закрыта этой сессией (в резолюции уточнены факты записи: 56 тестов,
  путь `sdx/hooks/`); заведена DEBT-013 «У раннера verify-cmd.sh нет собственного автотеста»
  (open, low — из WARN-2 qa).
- **Версия плагина:** 1.2.1 → 1.2.2 (изменён контент плагина — нужен `/plugin marketplace update sdx`).

**Верификация:** GATE PASS (qa + fresh-eyes `reviewer`, контракт изоляции: change_note +
diff 216 строк): 0 FAIL, 2 WARN — WARN-1 доправлен в сессии, WARN-2 → DEBT-013; краевые случаи
раннера (красный сьют → exit 1, пустой глоб → exit 1) проверены qa в изолированной копии;
56/56 тестов зелёные.

**Затронутые документы:** `.claude/sdx/verify-cmd.sh` (новый), `commands/verify.md`,
`docs/specs/phase1-enforcement-routing.md`, `docs/designs/phase1-enforcement-routing.md`,
`sdx/hooks/stop-gate.sh` (комментарий), `sdx/templates/verify-cmd.sh.template` (комментарий),
`docs/backlog/` (DEBT-004 closed, DEBT-013 новая; README-индекс), `.claude-plugin/plugin.json`.

**Ветка:** `sdx/fw-dogfood-verifycmd-20260720` → слита в `main`.

---

## 2026-07-20 — `fw-stage-guard-20260720` (трек `full`, тип refactor)

**Цель:** DEBT-001 — весь enforcement держался на самодекларируемом поле `stage`, которое
модель могла переписать в обход `/sdx:next`. Вместе с ним закрыт DEBT-011 (недоспецифицированный
`/sdx:backtrack`): спроектировать единственного писателя `stage` невозможно, не зафиксировав
правила отката.

**Решение (ADR-016):** введён `sdx/hooks/sdx-stage.sh` — единственный легитимный писатель
`stage` (подкоманды `init|next|backtrack|retrack`), проверяющий объективные гейт-условия по
машиночитаемой матрице «трек → упорядоченные этапы → гейт-артефакты» внутри самого скрипта
(`protocol.md` стал человекочитаемой проекцией, sanity-тест сверяет их по трём трекам с учётом
порядка). Прямая правка поля блокируется PreToolUse-хуком `sdx/hooks/stage-write-guard.sh`.
Резолюция сессии по имени ветки вынесена в общую `sdx/hooks/lib/resolve-session.sh` (три
потребителя). Шесть прозаических путей записи `stage` в командах сведены к вызову скрипта;
вход в Closeout из `archive.md` — цикл `next` с проверкой фактического значения, а не доверие
коду возврата.

**Верификация:** GATE PASS с **шестого** прохода fresh-eyes (`reviewer`, контракт изоляции:
SPEC+DESIGN + diff ~3000 строк), возврат на Execution после первого. Закрыто 8 блокирующих
находок. Существенные: deny-хук не ловил штатную форму правки (`Edit` меняет значение, а не
ключ — детекция переписана на «применить правку и сравнить распарсенное значение»); `archive.md`
начинал Closeout-чек-лист, не дойдя до `Closeout` (регресс гейта ADR-014); `retrack` принимал
regex как имя этапа и писал в state мусор; **храповик `retrack`** — потолок выводился из позиции
`stage`, и парой команд можно было подняться мимо всех гейтов, поэтому правило переписано на
**evidence-based** (цель допустима, только если гейт-артефакты всех предшествующих ей этапов
фактически существуют), а ранговая шкала удалена. Итог: 9 сьютов, 131 сценарий, зелёные;
нетавтологичность тестов подтверждена мутациями.

**Границы (названы явно, не обещаны сверх фактического):** закрыт случайный обход, не
намеренный — правка через `Bash` остаётся (DEBT-003), как и прямой вызов скрипта. Доказательством
гейта служит факт наличия непустого артефакта, а не его качество: файл-заглушка проходит.
Баннер `<!-- SDX-OUTDATED -->` сигнализирует человеку и агенту, но **не блокирует** гейты.

**Затронутые документы:** `sdx/hooks/` (`sdx-stage.sh`, `stage-write-guard.sh`,
`lib/resolve-session.sh` + четыре тест-сьюта — новые; `stage-gate.sh`, `stop-gate.sh` —
переведены на общий резолвер), `hooks/hooks.json`, шесть `commands/*.md`, `sdx/protocol.md`,
`docs/DECISIONS.md` (ADR-016), `docs/specs/stage-transition-guard.md`,
`docs/designs/stage-transition-guard.md`, `docs/history/plans/fw-stage-guard-20260720.md`,
`docs/backlog/` (DEBT-001 и DEBT-011 closed; новые DEBT-014, DEBT-015, DEBT-016, PROC-008),
`.claude-plugin/plugin.json` (1.2.2 → 1.3.0).

**Отложено за пределы сессии:** `/plugin marketplace update sdx` — активация нового deny-хука
в рантайме выполняется после закрытия сессии по решению пользователя (иначе хук вмешался бы в
собственный Closeout).

**Ветка:** `sdx/fw-stage-guard-20260720` → слита в `main`.

---

## 2026-07-20 — fw-session-types-20260720 (трек full, тип feature)

**Цель:** PROC-002 — работа над бэклогом (груминг), ретроспектива завершённых сессий, разбор инцидентов и новых требований делались вне процесса SDX без структурированного входа/выхода. Ввести четыре новых типа сессии (`grooming`, `retro`, `postmortem`, `intake`) с единым лёгким треком `doc` и прослеживаемым выходом в бэклог.

**Решение (ADR-017):** новый трек `doc` (Discovery → Update → Verification лёгкая → Closeout) с четырьмя типами сессий, единый гейт-артефакт `change_note.md`, обязательная fresh-eyes верификация без `qa`. Четыре новые строки в `SDX_STAGE_MATRIX` описывают трек данными, логика переходов не менялась (трек полностью укладывается в существующий контракт). Для `retro`/`postmortem`/`intake` — постоянные документы разбора в `docs/history/{retro,postmortem,intake}/` и шаблоны. Тип сессии не параметр матрицы — остаётся описательным; различие `intake` ↔ `grooming` (create vs update над бэклогом) держится текстом инструкций и ADR, не кодом скрипта. Четвёртый тип `intake` добавлен пользователем на backtrack-цикле (обнаружен недостаток на возврате с Technical Design на Business Spec этой же сессии).

**Верификация:** GATE PASS со второго прохода fresh-eyes (`reviewer`), возврат на Execution после первого (три WARN о когерентности документов; все устранены до гейта). Блокирующая находка первого прохода (FAIL) — контракт содержимого `change_note.md` и правило «правки бэклога на `Update`» не были явно зафиксированы в доступном рантайм-источнике, только в сессионном DESIGN.md. Исправлено переносом в `sdx/protocol.md`. Итог: **144/144 юнит-теста** (9 сьютов), расширен сценарий 34, добавлены 13 сценариев для трека `doc`; мутации подтверждают нетавтологичность.

**Затронутые документы:** `docs/specs/session-types-doc-track.md` (новый), `docs/designs/session-types-doc-track.md` (новый), `sdx/hooks/sdx-stage.sh` (4 строки матрицы, единственная процедурная правка — 17 строк трек-зависимой диагностики FAIL-гейта), `sdx/hooks/test-sdx-stage.sh` (сценарий 34 → `doc`, +13 новых), `sdx/protocol.md`, `commands/{start,next,verify,archive,retrack,init}.md`, `sdx/templates/{retro,postmortem,intake}.md` (новые), `agents/reviewer.md`, `CLAUDE.md`, `docs/DECISIONS.md` (ADR-017), `docs/designs/stage-transition-guard.md`, `docs/history/plans/fw-session-types-20260720.md`, `docs/backlog/` (PROC-002 closed, PROC-009 новая — отложена, 5 прочих в бэклог), `.claude-plugin/plugin.json` (1.3.0 → 1.4.0).

**Архитектурное свойство:** ключевое решение — описать новый трек данными (4 строки матрицы), логика переходов не требует расширения; единственная процедурная правка вскрыла ранее скрытый дефект (FAIL-диагностика захардкожена на несуществующий этап `Execution`). Тип не видит матрица; все различия между типами держатся инструкциями (`start.md`, шаблон `intake.md`, ADR) и fresh-eyes верификацией, не enforcement-кодом.

**Ветка:** `sdx/fw-session-types-20260720` → слита в `main`.

---

## `fw-reconcile-20260720` — `/sdx:reconcile`: сверка легаси-структур с актуальным форматом

**Трек:** `standard`. **Цель:** закрыть две повторяющиеся боли — незакрытые задачи и техдолг
из легаси-материала проекта (файлы памяти, старые заметки, аудиты, брошенные каталоги
сессий) не попадают в бэклог при подключении SDX; старые структуры хранения не приводятся к
формату, который фреймворк принял в новых версиях. Обе решались вручную по просьбе
пользователя каждый раз заново.

**Решение.** Новая команда `/sdx:reconcile` (скан → извлечение → дедупликация по смыслу →
перенос в `docs/backlog/` неотделимо с пометкой источника → приведение форматов → отчёт →
маркер версии), три режима (интерактивный / `--scan-only` / `--auto` с предохранителями).
Источники НИКОГДА не удаляются — рядом ставится маркер `<!-- SDX-MIGRATED: → <ID> (<дата>) -->`,
который и делает повторный скан идемпотентным. Автовызов из `/sdx:init` после миграции;
`/sdx:start` сверяет `.claude/sdx/sdx-version` с версией плагина и при расхождении предлагает
сверку. Политика «приводить накопленное к актуальному формату после подключения SDX и после
каждого обновления версии» зафиксирована разделом `sdx/protocol.md`.

**Верификация.** Четыре круга fresh-eyes ревью: 10 WARN → 1 FAIL / 5 WARN → 4 WARN → 4 WARN,
итог PASS, тест-сьюты 144/144 без изменений (поставка прозаическая, `sdx/hooks/**` не
затронуты). Дважды исправление находки вводило новый дефект — сначала автономный коммит в
пути согласия, затем коммит на основной ветке вопреки branch-first (ADR-009). Итоговое
решение — `/sdx:start` реконсиляцию инлайн не выполняет вовсе, а останавливается и просит
запустить команду отдельно — сняло оба нарушения и сделало обе ветви шага терминальными.
Урок зафиксирован в `docs/specs/reconcile-legacy-formats.md`: для прозаических инструкций
исправление находки требует такого же ревью, как исходная поставка.

**Затронутые документы:** `commands/reconcile.md` (новый), `commands/init.md`,
`commands/start.md`, `sdx/protocol.md`, `CLAUDE.md`, `README.md`, `README.en.md`,
`docs/specs/reconcile-legacy-formats.md` (новый), `docs/backlog/` (новая `DEBT-021`),
`.claude-plugin/plugin.json` (1.4.0 → 1.5.0).

**Отложено:** разовая расстановка маркеров `SDX-MIGRATED` в уже мигрированных вручную
источниках этого репозитория — `DEBT-021`.

**Ветка:** `sdx/fw-reconcile-20260720` → слита в `main`.

---

## `fw-reconcile-debt-20260720` — закрытие DEBT-021 и DEBT-022

**Трек:** `standard`, тип `refactor`. **Цель:** закрыть две записи бэклога, порождённые первым
реальным прогоном `/sdx:reconcile --scan-only` — обе про один механизм, поэтому одной сессией.

**DEBT-022 — бандлы получили определённое поведение.** Список источников команды не называл
`.sdx/bundles/` ни как источник, ни как исключение. Выбран вариант «сканировать»: `/sdx:import`
покрывает случай «бандл принят в работу», но не «бандл лежит и забыт», а риск потери порождает
именно второй (ровно история находки `C1`/`DEBT-008`, где бандл долго был единственной полной
спецификацией Фаз 2–4). Введено **третье поведение источника**: бандлы сканируются, но маркеры
в них НЕ пишутся — бандл переносим, и маркер со ссылкой на локальный `DEBT-0NN` в чужом проекте
бессмыслен; идемпотентность держится на дедупликации по смыслу. Кандидатами из бандла являются
только отложенные требования и открытые вопросы, но никогда срезы `SPEC`/`DESIGN`, код и тесты.

**DEBT-021 — маркеры проставлены.** В `docs/audit-2026-07-01-recommendations.md` добавлены 23
маркера `SDX-MIGRATED`, по одному на находку `A1`–`E4`, с датой фактической миграции
(2026-07-19), а не датой расстановки. Дифф — чистые вставки (23/0), исходный текст снапшота не
тронут. Повторный скан репозитория теперь отсекает мигрированное механически, а не суждением
модели.

**Верификация.** Fresh-eyes ревью — PASS, 0 FAIL, 4 WARN; маппинг 23 маркеров сверен ревьюером
независимо по полям `source` (23/23, расхождений нет). Три WARN закрыты в том же круге, четвёртый
(`status: open` у самих записей) дефектом не был — это работа Closeout. Тест-сьюты 144/144 без
изменений: поставка прозаическая.

**Урок.** Верификация показала цену введения третьего поведения: инвариант «перенос ⇒ пометка»
пришлось обмягчить ВЕЗДЕ, где он формулировался абсолютно (шаг 7 команды и раздел политики
протокола), а не только там, где вводилось исключение. Исключение, добавленное в одном месте,
оставляет ложные абсолютные утверждения в остальных.

**Затронутые документы:** `commands/reconcile.md`, `sdx/protocol.md`,
`docs/specs/reconcile-legacy-formats.md`, `docs/audit-2026-07-01-recommendations.md`,
`docs/backlog/` (DEBT-021 и DEBT-022 closed), `.claude-plugin/plugin.json` (1.5.0 → 1.5.1).

**Ветка:** `sdx/fw-reconcile-debt-20260720` → слита в `main`.

---

## 2026-07-21 — feat-vibe-track-20260720 (feature, трек full)

**Цель:** `PROC-004` — режим экстремального прототипирования: реализация «в один промпт» без церемонии и без инкрементальных коммитов, с обязательной легализацией перед мёржем.

**Сделано:**
- Пятый профиль флоу `vibe` описан **одной строкой** матрицы `vibe|Prototype|-|no` — процедурный код `sdx-stage.sh` не изменён ни на строку. Отсутствие собственного `Closeout` у трека и есть enforcement «нет мёржа без легализации»: инвариант выражен формой данных, а не проверкой в коде.
- Новый тип сессии `proto`, жёстко привязанный к треку на `/sdx:start` (прецедент ADR-017), и новая стадия `Prototype`.
- Новая команда `/sdx:proto` — гейт принятия/отклонения: baseline-снимок `prototype_baseline.txt` (git-ревизия + поимённый список untracked до попытки), точечный откат ТОЛЬКО по вычисленному списку, безусловный `AskUserQuestion` даже при `gate_mode: auto`. `git clean -fd`/`checkout .`/`reset --hard` не применяются нигде; при недоказуемом baseline — fail-closed.
- Легализация — `/sdx:retrack standard|full`: spec-after реверс-инжиниринг (guard ADR-016 смотрит файлы на диске, а не git, поэтому работает с некоммиченным кодом), первый коммит кода прототипа и пост-проверка REQ-VIBE-7 ДО смены трека.
- `stage-gate.sh` — две строки (`Execution|Deployment|Prototype`). `stop-gate.sh` — **ноль правок**: прозрачность на `Prototype` следует из существующей логики и зафиксирована регрессионным сценарием [13], который покраснеет при попытке «на всякий случай» добавить стадию в enforcement-ветку. `archive-verify.sh` и нумерация инвариантов 1/5/6 не тронуты.
- Найденный на Discovery конкретный риск: while-цикл входа в Closeout (`commands/archive.md`) предполагал, что у любого трека последний активный этап — `Closeout`; `vibe` первым это нарушил. Защита сделана трек-агностичной (детект по форме stdout `OK no-op <stage>`), попутно исчез паразитный коммит при вызове `/sdx:archive` на уже-`Closeout` сессии.
- Исчерпывающий проход по всем восьми `agents/*.md` — прямое противодействие `DEBT-017` (в прецеденте ADR-017 пропустили qa/developer/devops). В `agents/qa.md` попутно устранено противоречие с ADR-014 (строка «на `patch` Verification опционален»).
- ADR-018: именованное исключение из ADR-005/REQ-SESS-1 строго в границах стадии `Prototype`, снимается первым коммитом кода при легализации.

**Верификация:** четыре раунда fresh-eyes ревью. Раунды 2 и 3 вернули **FAIL** (ADR-018 приписывал guard'у ADR-016 проверку, которой тот не делает; `DESIGN.md` разошёлся с фактическим текстом команд) — оба устранены. Финал — PASS, 0 FAIL, 5 WARN: 3 квитированы (`DEBT-023`, `DEBT-024`, `DEBT-025`), 2 fail-open (GNU-зависимость `xargs -d`, пути с `"`/`\`) устранены по решению пользователя без пятого раунда, проверены исполнением. Тесты: 9/9 сьютов, 166 сценариев; мутационные проверки подтверждают нетавтологичность сценариев REQ-VIBE-8.

**Затронутые документы:** `docs/specs/vibe-prototyping-track.md`, `docs/designs/vibe-prototyping-track.md`, `docs/history/plans/feat-vibe-track-20260720.md`, `docs/DECISIONS.md` (ADR-018), `sdx/protocol.md`, `CLAUDE.md`, `README.md`/`README.en.md`, `docs/designs/stage-transition-guard.md`.

**Бэклог:** `PROC-004` закрыт. Заведены `DEBT-023` (дифф новых файлов на гейте), `DEBT-024` (инвариант ADR-001 сужен дважды без пометки), `DEBT-025` (ручной прогон `vibe` не выполнен), `PROC-011` (синхронизация DESIGN только после финализации кода — дважды была корневой причиной FAIL).

**Версия плагина:** `1.5.1 → 1.6.0` (MINOR: новый трек + тип + команда + ADR, ломающих изменений контракта нет).

**Ветка:** `sdx/feat-vibe-track-20260720` → слита в `main`.

---

## 2026-07-22 — fix-track-consistency-20260722 (refactor, трек patch)

**Цель:** `DEBT-017` (+`DEBT-018`, `DEBT-019`) — три текстовых consistency-фикса фреймворка из отложенных находок ревью `fw-session-types-20260720`, без изменения логики/контрактов.

**Сделано:**
- **DEBT-017** — трек `doc` дописан в перечисления `agents/qa.md`, `agents/developer.md`, `agents/devops.md` с явной (не)ролью агента (на `doc` кода нет → все трое не вызываются); стиль сверен с уже-поправленными `reviewer.md`/`lead-dev.md`/`tech-writer.md`. Вторая часть DEBT-017 (ложное «Verification опционален на `patch`») правки не потребовала — устранена ранее попутной правкой `feat-vibe-track-20260720`; подтверждено fresh-eyes ревью фактом (`qa.md` читается «обязателен в лёгком объёме»).
- **DEBT-018** — строка `doc` таблицы треков в `README.md`/`README.en.md` помечена «(жёстко привязаны, без триажа)» симметрично `vibe`; сверх исходной «полустроки» добавлена поясняющая блок-цитата «триаж vs жёсткая 1:1» в оба README.
- **DEBT-019** — doc-оговорки пп. 2/3 Closeout продублированы в `commands/archive.md` (простой вариант; системный рефактор устранения дублирования сознательно не делался ради точечности патча).

**Верификация:** трек `patch`, лёгкий объём (ADR-014). Тест-пол зелёный (9/9 hook-сьютов). Fresh-eyes `reviewer` (оси корректности/когерентности против `change_note.md`) — PASS, 0 FAIL, 1 WARN. WARN (поставка DEBT-018 шире контракта — добавленная блок-цитата) квитирован в interactive дозаписью контракта `change_note.md`, в бэклог не выделялся. Коллизий триады нет.

**Затронутые документы:** `agents/qa.md`, `agents/developer.md`, `agents/devops.md`, `README.md`, `README.en.md`, `commands/archive.md`. Отдельного переноса в `docs/specs/`/`docs/designs/` нет: правки — сами постоянные файлы фреймворка, алайнят инструкции к уже принятым ADR-014/017, SPEC/DESIGN-дельты не порождают.

**Бэклог:** `DEBT-017`, `DEBT-018`, `DEBT-019` закрыты. Новых записей не заведено (WARN квитирован).

**Ветка:** `sdx/fix-track-consistency-20260722` → слита в `main`.

---

## 2026-07-22 — fix-diff-computation-contract-20260722 (bug, трек standard)

**Цель:** `BUG-004` (wave 5) — устранить противоречие «кто вычисляет diff поставки»: `verify.md` возлагал вычисление на оркестратора, `reviewer.md` — на самого ревьюера через Bash (двойная токенизация + дыра в изоляции: Bash даёт доступ к `session.log`).

**Сделано:**
- **verify.md** шаг 4 — оркестратор материализует diff **редиректом в файл** `.claude/sessions/<id>/delivery.diff` (не через контекст); шаг 5 передаёт ревьюеру **путь**, не текст. Снимает исключение ADR-005 о двойной токенизации.
- **reviewer.md** — из frontmatter `tools:` изъят `Bash` (`Read, Write, Glob, Grep`): контракт изоляции стал **enforcement**, а не прозой (нет инструмента → физически нет доступа к `session.log`/произвольному git). «Вход»/«Инструкция 2» переписаны на чтение файла.
- Смежный дефект когерентности, найденный на Discovery: `reviewer.md` хардкодил `git diff main...`, тогда как фреймворк резолвит основную ветку динамически (`default-branch.sh`, REQ-BRANCH-3, ADR-010). Хардкод `main` удалён.
- `delivery.diff` объявлен эфемерным буфером: targeted-паттерн `.claude/sessions/*/delivery.diff` добавлен в корневой `.gitignore` и seed-блок `commands/init.md` (REQ-SESS-2, как `.stopgate.*`).
- `sdx/protocol.md` (раздел «Fresh-eyes: контракт изоляции») приведён в соответствие — триада «протокол ↔ `verify.md` ↔ `reviewer.md`» когерентна (сама ось BUG-004).

**Верификация (standard):** `qa` — регресс 9/9 hook-сьютов зелёные (поставка не трогает `sdx/hooks/*.sh`), gitignore-паттерн проверен исполнением (`git check-ignore`); новых автотестов не требуется (prose/config-контракты вне тест-пола). Fresh-eyes `reviewer` (против `change_note.md`) — **PASS, 0 FAIL, 0 WARN**. Особенность: сессия верифицировалась уже по новому контракту (diff подан файлом, ревьюер без `Bash`) — живая самопроверка правки. Коллизий триады нет.

**Затронутые документы:** `commands/verify.md`, `agents/reviewer.md`, `commands/init.md`, `sdx/protocol.md`, `.gitignore`. Отдельного переноса в `docs/specs/`/`docs/designs/` нет: правки — сами постоянные файлы фреймворка; `docs/designs/phase1-enforcement-routing.md:521` (изоляция reviewer) — phase-scoped и не противоречит новому контракту, оставлен как есть.

**Бэклог:** `BUG-004` закрыт. Новых записей не заведено (WARN отсутствовал).

**Ветка:** `sdx/fix-diff-computation-contract-20260722` → слита в `main`.

---

## 2026-07-25 — fix-archive-verify-exec-bit-20260725 (bug, трек patch)

**Цель:** `BUG-008` (полевой репорт из проекта cortexdev) — `/sdx:archive` на шаге 7 выдавал ложный `[FAIL] ветка sdx/<id> не слита в .` при фактически слитой ветке: `archive-verify.sh:13` исполнял `lib/default-branch.sh`, а в средах, где установщик плагина срезает режимы (наблюдено: все 18 `sdx/hooks/**/*.sh` с правами `0600`), подстановка возвращала пустую строку, и пустой `$def` уходил в `git branch --merged`.

**Сделано:**
- **`archive-verify.sh`** — резолвер вызывается через `bash "$here/lib/default-branch.sh"` (форма, уже принятая в `commands/archive.md`/`verify.md`); добавлен явный отказ `[FAIL] не удалось определить основную ветку` до всех проверок и до деструктива — пустой ref больше не уходит в git молча (ср. DEBT-010).
- **`hooks/hooks.json`** — все пять регистраций (`preflight`, `stage-gate`, `stage-write-guard`, `prod-guard`, `stop-gate`) переведены с прямого исполнения на `bash "${CLAUDE_PLUGIN_ROOT}"/…`. **Это не было в исходном репорте** — найдено fresh-eyes ревью (см. «Верификация»).
- **`sdx/hooks/test-hook-wiring.sh`** (новый сьют) — инвариант формы вызова как enforcement: каждая регистрация идёт через `bash`, каждый referenced-скрипт существует; сценарий `[4]` демонстрирует, что инвариант несущий (`0600` + прямой вызов → `exit 126`, через `bash` → `0`).
- **`sdx/protocol.md`** — инвариант формы вызова назван явно в «Enforcement-слое»; описание `archive-verify` дополнено новым путём отказа.
- **`docs/designs/session-worktree-model.md`** — псевдокод `archive-verify` синхронизирован с кодом (перестал быть эталоном дефекта); два устаревших пути `.claude/sdx/hooks/` → `${CLAUDE_PLUGIN_ROOT}`.
- Режимы четырёх тестов (`test-prod-guard`, `test-stage-gate`, `test-stage-write-guard`, `test-stop-gate`) выровнены на `100755`.

**Верификация (patch, лёгкий объём):** два прогона. **Первый — FAIL 1 / WARN 3:** ревьюер опроверг центральное утверждение репорта и артефактов «`archive-verify.sh` — единственная точка, зависящая от бита `x`»: боевая проводка `hooks/hooks.json` вызывает пять скриптов прямым исполнением (проверено: копия `stage-gate.sh` с `0600` → `Permission denied`, `exit 126`). То есть первая редакция фикса чинила одну точку из шести, а пять остальных — детерминированный enforcement-слой — умирали молча, невидимо для пользователя (класс DEBT-010); вывод репорта «остальной слой работает штатно» был следствием невидимости отказа, а не наблюдением. Сессия возвращена на Execution через `/sdx:backtrack`, фикс расширен, артефакты приведены к фактам. **Второй — PASS, 0 FAIL / 5 WARN**, все квитированы. Ревьюер выполнил мутационные проверки на копиях вне репозитория: откат каждой правки по отдельности даёт свой красный сценарий (покрытие независимое, не тавтологичное). Регрессия: `test-archive-verify.sh` 24/24, полный сьют 10/10.

**Решение по треку:** трек `patch` принят явно, несмотря на WARN ревьюера об адекватности (прецеденты BUG-006/BUG-004 — тот же профиль на `standard`). Обоснование: логика хуков, их порядок и контракты не менялись — только форма вызова и синхронизация документов с кодом; fresh-eyes ревью пройдено в полном объёме.

**Затронутые документы:** `sdx/hooks/archive-verify.sh`, `hooks/hooks.json`, `sdx/hooks/test-archive-verify.sh`, `sdx/hooks/test-hook-wiring.sh` (новый), `sdx/protocol.md`, `docs/designs/session-worktree-model.md`. Отдельного переноса в `docs/specs/` нет: правки — сами постоянные файлы фреймворка (та же конвенция, что в `fix-track-consistency-20260722` и `fix-diff-computation-contract-20260722`).

**Бэклог:** `BUG-008` закрыт. Заведены `DEBT-026` (`stop-gate` определяет тест-команду по биту `x` — смена семантики, не формы вызова) и `DEBT-027` (легаси-пути `.claude/sdx/hooks/` в постоянных документах) из квитированных WARN 2/3.

**Требует действия после мёржа:** `/plugin marketplace update sdx` — правка `hooks/hooks.json` действует только в установленной копии плагина.

**Замечено (не оформлено записью):** установленный плагин `1.6.0` отставал от `main` — у `reviewer` в нём ещё присутствовал `Bash`, изъятый BUG-004. Контракт изоляции ревьюера до обновления плагина держится на прозе, а не на enforcement.

**Ветка:** `sdx/fix-archive-verify-exec-bit-20260725` → слита в `main`.

---

## 2026-07-26 — feat-audit-agent-20260726 (feature, трек full)

**Цель:** ввести целостную ревизию проекта «как есть»: субагент-аудитор на модельном тире `fable`, read-only команда комплексного аудита по векторам с отчётом (сильные стороны / проблемы / риски с реагированием / рекомендации) и отдельную процедуру разбора отчёта в бэклог.

**Сделано:**
- **ADR-019** (`docs/DECISIONS.md`) — одно решение на всю поставку: четвёртый тир модели, агент, команда, тип сессии. Ключевое, что ADR обязан был закрыть, — **граница `fable` vs `opus`**: ADR-008 закрепил за `opus` «оценочное суждение», а аудит тоже оценочное суждение, поэтому без явной границы карта тиров становилась неоднозначной. Граница проведена по трём наблюдаемым признакам роли: есть ли материализованный эталон, гейтит ли вердикт машинно, каков охват. `opus` — верификационное суждение (эталон задан извне, вердикт блокирует, охват — дельта сессии), `fable` — ревизионное (эталона нет, вердикт информационный, охват — проект целиком). Помечено как нормативная классификация ролей, а не измеренная разница способностей.
- **`agents/auditor.md`** — девятый субагент, `model: fable`, `tools: Read, Write, Glob, Grep` (без `Bash` и `Edit`: read-only здесь enforcement, а не обещание). Девять векторов (`ARCH`/`TRIAD`/`TRACE`/`CODE`/`TEST`/`DOCS`/`DEPLOY`/`SEC`/`PROC`), **три исхода на вектор** — находки, чисто, неприменимо. Один вызов = один вектор, свой выходной файл.
- **`commands/audit.md`** — команда вне сессий: precheck незавершённых прогонов, детерминированный слой с предикатами применимости, параллельный фан-аут двумя волнами, проверки консистентности с однократным перевызовом, склейка одним действием в `docs/history/audit/audit-<дата>[-N].md`, удаление каталога прогона.
- **Тип сессии `audit`** на существующем треке `doc`. `SDX_STAGE_MATRIX` и `sdx-stage.sh` **не изменены ни на строку** — матрица ключуется треком, а не типом, что проверено по коду и радикально сжало поставку: детерминированный слой не тронут вовсе (178 тестов зелёные, `sdx/hooks/**` и `hooks/hooks.json` отсутствуют в diff).
- **Второй тип трека `doc` без постоянного документа разбора**, наравне с `grooming`. Этим снята коллизия каталога `docs/history/audit/`: по прецеденту ADR-017 туда лёг бы документ разбора, а `REQ-AUDIT-7` требует складывать туда отчёты прогонов. Разведено не переименованием, а устранением сущности — предмет разбора у `audit` уже является постоянным документом, второй был бы разбором разбора.
- Правки: `sdx/protocol.md` (8 точек + новый раздел «Аудит проекта и его триаж»), шесть команд, `CLAUDE.md`, оба README, шаблон `claude-md-snippet.md`, `.gitignore`, постоянная спека `docs/specs/session-types-doc-track.md` (пятый тип трека `doc`). Версия `1.6.1 → 1.7.0`.
- **Заодно закрыт `BUG-007`** — санкционированное расширение скоупа: `/sdx:init` теперь кладёт заглушку во все четыре каталога `docs/history/`, а не только в новый.

**Верификация (два прогона ревью, между ними откат до Technical Design):**

Первый прогон — **2 FAIL**. (1) Run-id существовал в трёх несовместимых формах: команда писала идентификатор каталога с меткой времени, а `source` записей бэклога и протокол ждали форму имени отчёта — детерминированный слой дедупликации искал бы строку, которой в бэклоге нет, при формально корректном коде. (2) `DESIGN.md` описывал старый контракт маркера и при этом утверждал «содержательных отклонений нет», а через Closeout уезжал в `docs/designs/` навсегда. Второй прогон — **PASS, 0 FAIL**; из девяти WARN семь исправлены (хвосты ремедиации, включая ссылки на несуществующие `REQ-DOC-6`/`REQ-DOC-15` вместо `REQ-DOC-5`/`REQ-DOC-4`), два квитированы пользователем.

**Ручные прогоны вместо автотестов (харнеса для прозаических команд нет) — нашли четыре дефекта, невидимых при чтении:**
1. **Находка-фантом.** Вектор `DOCS` сообщил, что в `CLAUDE.md` нет агента `auditor`, тира `fable` и типа `audit` — при том, что все три там были. Соседняя находка того же вектора про `sdx/protocol.md` оказалась верна: значит протокол агент прочитал с диска, а `CLAUDE.md` взял из **копии, автоматически инжектированной в его контекст** (снимок на момент старта). В контракт агента добавлено правило «источник фактов — только диск»; вектор перепрогнан с тем же манифестом и той же моделью — фантом исчез, число настоящих находок выросло с 10 до 12. Это доказательство фикса, а не совпадение.
2. **Строка-маркер без счётчика `problems=`** — число проблем приходилось получать вычитанием, из-за чего проверка консистентности не могла сверить сумму по разделам, хотя выглядела так, будто может.
3. **Пропущенный ignore-паттерн:** `.sdx/audit-runs/` был добавлен в `.gitignore` самого плагина, но не в блок, который `/sdx:init` кладёт в проект-потребитель — каталог прогона висел бы untracked и уехал бы в коммит первым `git add -A`.
4. **Лишняя запись:** шаг 7 команды создавал файл-заглушку рядом с отчётом, что противоречило `REQ-AUDIT-3` («единственная запись — отчёт и каталог под него») и было бессмысленно, поскольку каталог непуст из-за самого отчёта.

**Первый реальный отчёт аудита:** `docs/history/audit/audit-2026-07-26.md` — 92 находки на девяти векторах (29 сильных сторон, 26 проблем, 21 риск, 16 рекомендаций), все девять векторов применимы. Деградационный прогон в проекте-потребителе без триады дал шесть `N/A` с предметными причинами и три применимых вектора — то есть отсутствие спецификаций не выдаётся за дефект. Протокол обоих прогонов, включая честный перечень непройденных ветвей, был внесён в репозиторий по замечанию ревью (доказательства T-19 лежали вне репозитория и исчезли бы вместе с временным каталогом).

**Затронутые документы:** `docs/specs/audit-agent-and-command.md`, `docs/designs/audit-agent-and-command.md`, `docs/specs/session-types-doc-track.md`, `docs/DECISIONS.md` (ADR-019), `docs/history/plans/feat-audit-agent-20260726.md`, `docs/history/audit/audit-2026-07-26.md`.

**Бэклог:** закрыт `BUG-007`. Новые: `DEBT-028` (тип сессии `audit` не подтверждён исполнением — REQ-AUDIT-9..15 держатся только на прозе; закрывается первым реальным триажем, который нужен всё равно), `DEBT-029` (не исполнялись исход `CLEAN`, правило `-N` и штатная конфигурация инструментов агента), `DEBT-030` (значение `model` во frontmatter не валидируется ничем — тихий сбой в рантайме, класс `DEBT-010`), `IDEA-008` (инструмент сравнения прогонов).

**Что осталось непроверенным исполнением и почему:** тип сессии `audit` целиком — внутри сессии-поставки это невозможно по построению, `/sdx:start` требует чистого дерева и новой ветки. Штатная конфигурация инструментов агента — оба прогона шли обходным путём, потому что установленная копия плагина (1.6.1) отставала от поставки (1.7.0), и векторные агенты технически имели `Bash`, которого у штатного `auditor` нет. Предписание использовать его только на чтение не нарушил никто, но это наблюдение «не стал», а не гарантия «не может».

**Следующий шаг:** `/plugin marketplace update sdx`, затем `/sdx:start audit docs/history/audit/audit-2026-07-26.md` — триаж 92 находок, который одновременно закроет `DEBT-028`.

---

## 2026-08-31 — sdx-runtime-rethink-20260830 (intake, трек doc)

**Цель:** разобрать внешний стратегический материал по переосмыслению SDX (архив `sdx-2.0.zip`: документ разбора, 26 готовых записей бэклога, вспомогательный раскладчик) и превратить его в записи `docs/backlog/`. Реализация ничего из разобранного в скоуп не входила — `intake` порождает записи, а не выполняет их.

**Сделано:**
- **26 новых записей бэклога** (23 `open`, 3 `deferred`), бэклог 59 → 85 записей; ещё две (`PROC-022`, `DEBT-032`) добавлены на Closeout, итого 87. Содержательно — пять волн: (1) основание — self-test enforcement-слоя как условие автономии, понятие «прогон» вместо «сессии», машиночитаемый реестр задач, журнал, который пишет харнесс; (2) сокращения — треки 5→1 шкала + два режима, enforcement по необратимости вместо порядка этапов, субагенты 9→2, тиры 4→2, delta-first, инверсия ADR-014; (3) полномочия и цикл — классы риска действий, `deny`→`ask`/`defer`, HITL-inbox, Stop-хук как тик планировщика; (4) карта освоенности областей (`declared` + проекция `observed` над журналом), асимметричная выдача полномочий, храповик знания; (5) контрактные гейты, позиционирование SDX как design-time двойника ядра, обрыв ЖЦ на L5.
- **21 существующая запись** получила обратные ссылки — правились только поля `links`, тела не тронуты. Приоритеты, волны и статусы существующих записей не менялись: это зона `grooming`.
- **Индекс `README.md`** перестроен целиком по документированному правилу сортировки (таблица уже дрейфанула: `DEBT-028` с `priority: high` стоял ниже записей `normal`), названия строк синхронизированы с заголовками записей, в преамбулу добавлено происхождение новых записей и оговорка о несведённых шкалах волн (1–5 разбора против 8–10 накопленных).
- **Постоянный документ разбора:** `docs/history/intake/sdx-runtime-rethink-20260830.md`.

**Что триаж поймал во входном материале** (три дефекта — причина, по которой пришедший в архиве `split-backlog.sh` не исполнялся, а записи раскладывались разбором):
1. `IDEA-009`/`IDEA-010`/`IDEA-011` пришли со `status: open`, но с разделом `## Резолюция`, текст которой у всех трёх — обоснование отсрочки. Конвенция однозначна: `## Резолюция` есть у всех закрытых, у 6 из 7 отложенных и ровно у нуля открытых. Переведены в `deferred`.
2. `IDEA-006` объявлена дополняемой, но ни одна из 26 новых записей на неё не ссылалась. Связана с `PROC-015` в обе стороны.
3. Входной документ недосчитал бэклог: «38 записей» против фактических 59. Открытые и отложенные (26 и 7) сошлись точно, недосчитаны закрытые.

**Дедупликация (три слоя):** точный — 0 совпадений; семантический против 33 открытых/отложенных — 0 дублей, 21 смежная связь; семантический против 26 закрытых — **0 регрессов**. Три ссылки на закрытые записи квалифицированы поимённо: `BUG-001`/`BUG-006` (`PROC-013`) — переоценка класса дефекта, не его возврат; `DEBT-017` (`PROC-014`) — закрытая находка была о неполных перечислениях треков внутри файлов агентов, а запись предлагает удалить сами файлы.

**Верификация — три круга fresh-eyes, 17 находок, 16 устранены правкой:**

Круг 1 — PASS, 9 WARN. Круг 2 — **FAIL**: ремедиация первого круга сама породила дефект. Пометив основания записей волн 1–3 как «взято из внешнего материала, из репозитория непроверяемо», я включил в этот перечень способность хука `Stop` отказать в завершении хода — факт, который репозиторий использует в трёх местах (`hooks/hooks.json`, `sdx/hooks/stop-gate.sh`, протокол) и на котором стоит весь `stop-gate`. Ложное утверждение о собственном репозитории уезжало в постоянную запись бэклога. Блок снят из `FEAT-005` целиком, в `FEAT-004`/`FEAT-006` перечни сужены до фактически внешнего: событий `PostToolUse`/`SessionEnd`/`PreCompact` в репозитории нет, а `permissionDecision` используется строго со значением `deny` — значит допущением остаются значения `allow`/`ask`/`defer`, семантика `defer` в `-p` и приоритет решений.

Круг 3 — PASS, 5 WARN, из них четыре устранены уже после получения `PASS` (гейт ими не блокировался, но они уходили бы в постоянные документы). Существенная из них: `PROC-014` объясняла read-only у субагента `auditor` «отсутствием инструментов записи», тогда как `agents/auditor.md` даёт `tools: Read, Write, Glob, Grep` — механизм в отсутствии `Bash` и `Edit`. Два предыдущих круга это пропустили.

**Квитировано пользователем (единственная неустранённая находка):** сессия типа `intake` выполнила две операции, которые протокол приписывает типу `audit` — дополнила существующие записи связями и провела слой сверки против закрытых. Практика признана нормой, поставка не откатывалась; развилка вынесена в `PROC-022`.

**Затронутые документы:** `docs/backlog/` (28 новых записей, 23 изменённые, индекс), `docs/history/intake/sdx-runtime-rethink-20260830.md`.

**Бэклог:** 26 записей разбора + на Closeout `PROC-022` (границы типа `intake` против `audit` — квитированный WARN) и `DEBT-032` (п.4 Closeout-чек-листа требует пометки `session: <id>` на порождённых записях, тогда как конвенция бэклога отводит `session` под закрывшую сессию, а происхождение — под `source`; проверено: все четыре записи, заведённые на прошлом Closeout, несут `session: null`). Закрытых этой сессией записей нет — `intake` их не производит.

**Следующий шаг:** `grooming`-сессия. Семь открытых вопросов перечислены в документе разбора; ключевые — судьба десяти записей, закрываемых сносом машинерии треков (`deferred` против `open`), повышение приоритета `DEBT-010`, на которой стоит `FEAT-014`, сведение двух шкал волн в одну и атомарность связки `PROC-012`…`PROC-018`.
