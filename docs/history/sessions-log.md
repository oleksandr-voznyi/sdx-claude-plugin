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

---

## 2026-08-31 — grooming-sdx-2-0-20260831 (grooming, трек doc)

**Цель:** разрешить семь открытых вопросов, оставленных разбором `intake sdx-runtime-rethink-20260830`, с привлечением двух документов, поданных пользователем на вход сессии: `Constructor-concept.md` (концепция конструктора ИИ-сервисов вокруг durable-оркестратора) и `AIBoK-structure.md` (свод знаний по ИИ-трансформации).

**Что концепция изменила, а не подтвердила** — четыре вещи, из-за которых груминг нельзя было провести на одном бэклоге:
1. **Формат спецификаций процессов — первая позиция Фазы 0 Конструктора** (1–2 месяца) и одновременно его открытый вопрос №1, где SDX назван кандидатом наравне с BPMN-расширением и собственным DSL. `PROC-016` в волне 5 стоял позже решения, ради которого нужен, — поднят в волну 3 и до `high`.
2. **Триада прозаична, а формат обязан компилироваться** («декларативная спецификация с компиляцией в код workflow», «версионирование, миграции запущенных экземпляров»). `PROC-021` этого условия выполнимости не называла; условие внесено в её тело.
3. **Концепция сохраняет stage-gates как обязательный механизм** (evals в stage-gates как условие релиза; AIBoK KA-9, артефакт 16, приложение E). Это не противоречит `PROC-013` — объекты разные, — но совпадение имён обязано быть разведено в ADR волны 2, иначе «сняли stage-gate» прочитается как отказ от гейтов приёмки. Требование внесено в тело `PROC-013`.
4. **У SDX есть вторая роль, не зависящая от вопроса №1** — агентная среда разработки адаптеров и клиентских спецификаций как ответ на риск нехватки команды. Она стоит на волнах 1/3/4, то есть половина плана защищена бизнес-моделью независимо от судьбы `PROC-021`.

**Решения (семь вопросов):** десять записей машинерии → `deferred`, каждая с персональной резолюцией (восемь ждут волну 2, две — `BUG-005` и `DEBT-007` — волну 1, где их предмет снимает `PROC-019`, а не снос); `DEBT-010` → `high`, волна 1, вместе с `DEBT-026` как живым экземпляром того же класса; обе шкалы волн сведены в одну 1–7 среди открытых и отложенных, у закрытых поле не трогалось; **атомарный набор сноса**: `PROC-018` заменён на `FEAT-006` (перенос из волны 3 закрывает окно «снят `stage-gate`, замены ещё нет», которое запись сама признавала), объём волны 2 сведён с семи записей до четырёх, `PROC-014`/`PROC-015` выведены в волну 7; `IDEA-005` поднята в `open`/`high`/волна 6 предусловием **`PROC-014`**, а не волны сноса — обоснование `PROC-012` структурное и проверяется чтением, обоснование `PROC-014` эмпирическое и чтением не проверяется; пороги `FEAT-010` оставлены `DESIGN`-этапу; `ADR-014` — новый ADR с пометкой «пересматривает», по прецеденту `ADR-012`/`ADR-009`.

**Верификация — шесть кругов fresh-eyes, шесть `FAIL`.** Это худший показатель среди всех сессий проекта, и четыре из шести `FAIL` внесла сама ремедиация:
1. **Круг 1** — тип `grooming` исполнил create-путь: сессия завела новую запись из внешнего материала, что `sdx/protocol.md` и `ADR-017` запрещают дословно. По решению пользователя запись снята, содержание внесено в тело `PROC-021`, вопрос передан будущей `intake`-сессии.
2. **Круги 2–4** — один класс: значение поля или формулировка изменены, а зависящий от них текст оставлен прежним. Проза оставляла `PROC-014` в волне 6 при `wave: 7`; введённая этой же сессией конвенция требовала обоснования у 21 записи, а получили его 9; `PROC-012` повторно свела все десять отложенных к ожиданию волны 2 — регресс находки, закрытой двумя кругами ранее.
3. **Круг 5** — другой класс: автоматический перенос длинных строк применил прозаическое правило ширины к строке данных и разорвал `links:` во frontmatter `PROC-012`. Построчное извлечение вернуло бы 9 идентификаторов из 17 и потеряло `BUG-005` — ровно ту связь, ради машиночитаемости которой предыдущий круг правил `links`.
4. **Круг 6** — `PASS`, 0 `FAIL`. Два оставшихся WARN оказались неверными утверждениями в тексте самой поставки и были исправлены, а не квитированы.

**Урок для практики.** Содержательные решения груминга были готовы после первого круга; пять кругов ушли на дефекты ремедиации. Общий признак: правка вносилась точечно, в одном месте, тогда как утверждение о поле живёт в нескольких. Дешёвый контрмеханизм — сплошная сверка «каждое утверждение о поле против фактического значения» ПЕРЕД вызовом ревьюера, а не после; будучи применённой перед кругом 6, она дала ноль расхождений и цепочка прервалась.

**Квитировано пользователем:** конвенция раздела `## Решения груминга` в `docs/backlog/README.md` переведена из предписывающей формы в описательную — груминг перестаёт закреплять правилом операцию (дописывание тел записей), легитимность которой сам же поставил под вопрос записью `PROC-022` часом ранее.

**Затронутые документы:** `docs/backlog/` — 26 файлов: 25 записей и индекс. Смен `status` 12, `priority` 5, `wave` 14, `links` 2; новых и удалённых записей 0. Постоянного документа разбора тип `grooming` не производит.

**Состояние бэклога:** 87 записей — 43 `open`, 18 `deferred`, 26 `closed`. По волнам среди открытых: 1→7, 2→4, 3→5, 4→5, 5→4, 6→1, 7→2, без волны 15.

**Передано дальше (грумингом не решается по границам типа):**
- **Сессия `intake`** по `Constructor-concept.md` и `AIBoK-structure.md`: запись о разрыве «прозаическая триада ↔ компилируемый формат спецификаций процессов» (черновик подготовлен, содержание продублировано в теле `PROC-021`); тройное дублирование конвенции бэклога — `docs/backlog/README.md`, `commands/backlog.md` и шаблон `sdx/templates/backlog-readme.md`, из которого `/sdx:init` тиражирует расхождение в новые проекты; расхождение шкал в `FEAT-009` (agent-readiness систем 0–4 против спектра автономии AIBoK из шести уровней); отсутствие SLA и делегирования в `FEAT-007` против AIBoK KA-6.
- **`PROC-022`** остаётся открытой: эта сессия дала ей второй прецедент, но не решение.
- **Коллизия протокола, обнаруженная на Closeout.** П.4 чек-листа предписывает заводить `DEBT-`/`IDEA-`записи под неквитированные WARN «на любом треке включая `doc`», а `sdx/protocol.md` безусловно запрещает типу `grooming` создавать новые записи. Для этой сессии коллизия не сработала — все WARN квитированы, — но она реальна и не разрешена. Смежно с `PROC-022` и `DEBT-032`.

---

## 2026-08-31 — intake-constructor-concept-20260831 (intake, трек doc)

**Цель:** оформить хвост находок груминга `grooming-sdx-2-0-20260831` — пять пунктов, которые он обнаружил при сверке бэклога с `Constructor-concept.md` и `AIBoK-structure.md`, но завести записями не мог: тип `grooming` новых записей не создаёт.

**Сделано:** три новые записи и два уточнения существующих. Бэклог 87 → 90 (46 `open`, 18 `deferred`, 26 `closed`). Смен `status`/`priority`/`wave` — ноль: зона `grooming` не тронута.
- **`PROC-023`** (high, волна 1) — триада прозаична, а формат спецификаций процессов обязан компилироваться. Дизайн-срез, не реализация: достижим ли компилируемый формат из триады, какой ценой, и честная альтернатива, при которой SDX остаётся средой разработки, а языком процессов становится отдельный формат.
- **`PROC-024`** (normal) — коллизия: п.4 Closeout-чек-листа требует заводить `DEBT-`/`IDEA-`записи под неквитированные WARN «на любом треке включая `doc`», а протокол безусловно запрещает типу `grooming` создавать записи. Латентна, пока WARN квитируются; обнаружена рассуждением, а не инцидентом.
- **`DEBT-033`** (normal) — конвенция тела записи бэклога описана в шести местах и разошлась; верны две редакции из шести, причём одна из верных — спецификация `REQ-BL-1`, то есть источник истины уже существует. `/sdx:init` тиражирует одну из устаревших в каждый новый проект.
- **Уточнения:** `FEAT-009` — столбец «Режим» в шкале освоенности является второй, ни на что не отображённой шкалой, тогда как AIBoK §1.1 даёт готовый спектр автономии из шести уровней; освоенность про область, автономия про агента, и таблица неявно утверждает однозначность отображения. `FEAT-007` — делегирование названо в `## Суть`, но не спроектировано в `## Рекомендация`; «дедлайн» подменяет SLA (момент времени вместо политики на его наступление); каналы предъявления карточки не поставлены как вопрос.

**Входные документы в репозиторий не копировались** — сознательное отступление от прецедента разбора `sdx-runtime-rethink-20260830`. Причина: концепция содержит экономическую модель, распределение долей выручки и go-to-market, а репозиторий публичный; коммит оставил бы это в истории навсегда. Цена названа в документе разбора: воспроизводимость ниже, цитаты проверяемы только по исходникам вне репозитория. Смежно с `PROC-009`, где вопрос «что делать, когда вход нельзя версионировать» даже не поставлен.

**Верификация — шесть кругов, пять `FAIL`, четыре из пяти внесла сама ремедиация.** Показательны два механизма:
1. **Черновик, переживший чужие правки.** Запись `PROC-023` создавалась из черновика, сохранённого во время предыдущей сессии. Черновик унёс редакции двух утверждений, исправленных позже на кругах ревью того груминга («ровно один машиночитаемый артефакт», атрибуция «§6 и §8»), и обе ошибки въехали в новую запись дословно. Одна дала `FAIL`, вторую автор нашёл собственной сверкой до вызова круга.
2. **Правка в части носителей.** Один и тот же состав дал `FAIL` трижды: утверждение исправлялось в записи бэклога и не исправлялось в `intake.md`, либо наоборот. На круге 5 исправленными оказались оба эфемерных документа сессии, а неисправленной — постоянная запись, утверждавшая противоположное.

Круг 4 вскрыл, что и сама находка `DEBT-033` была занижена втрое: носителей конвенции не три, а шесть, и одна из копий уже верна — что меняло и вывод, и рекомендацию, построенную над множеством из трёх файлов.

**Урок, дополняющий записанный грумингом.** Механическая сверка «каждое утверждение против всех его копий» перед вызовом ревьюера действительно сокращает класс, но не закрывает его: на круге 6 два `WARN` лежали ровно в её предмете и не были найдены, потому что искались заранее придуманные шаблоны, а не все утверждения. Честная формулировка: сверка сокращает, ревьюер остаётся несущим слоем, а не подтверждающим. Отдельный вывод — **черновик, переживающий сессию, опаснее отсутствия черновика**: он консервирует состояние до чужих исправлений и не несёт следа о том, что состояние устарело.

**Квитировано пользователем:** объём операций шире границ типа (правки тел двух записей, `links` девяти, добровольный слой сверки против закрытых, отводимый `audit`) — третий прецедент подряд одной неясности, предмет открытых `PROC-022` и `PROC-024`; волна 1 у `PROC-023` назначена по внешнему сроку Фазы 0, а не по семантике шкалы, заданной грумингом.

**Затронутые документы:** `docs/backlog/` — 14 файлов (3 новых, 10 с правкой `links`, индекс); 30 добавленных связей; `docs/history/intake/intake-constructor-concept-20260831.md`.

**Что осталось открытым:** `PROC-022`, `PROC-024`, `DEBT-032`, `DEBT-033` — узел из четырёх записей вокруг п.4 Closeout-чек-листа и границ трёх типов над бэклогом. Груминг должен решить, чинить их по одной или переписать пункт целиком вместе с определениями типов. Полный самостоятельный разбор обоих документов концепции (KA-10, KA-11, часть VII бэклог не затрагивает вовсе) в скоуп не входил и остаётся отдельной работой.

---

## 2026-09-01 — design-spec-format-feasibility-20260901 (feature, трек standard)

**Цель:** закрыть `PROC-023` — ответить, достижим ли компилируемый формат спецификаций процессов из триады SDX, к моменту выбора формата в Фазе 0 Конструктора.

**Выход:** `docs/designs/spec-format-feasibility.md`. Кода поставка не содержит.

**Ответ, отличный от ожидавшегося записью.** Триада компилируемым языком процессов не станет, и компилятор тут ни при чём: у неё другой предмет описания. Триада описывает *изменение системы*; определение процесса описывает *повторяемый долгоживущий процесс*. Между ними нет трансформации, как её нет между техническим заданием и BPMN. Хуже: delta-first (`PROC-017`, волна 2) уводит SDX **дальше** от процессной формы, тогда как `PROC-021` (волна 5) предполагает движение к ней — по этой оси волны тянут в разные стороны, и груминг её не рассматривал.

**Кандидат на вклад существует и это не триада** — схема задачи `FEAT-003` (id, проверяемые предусловия, эффект, `verify`, класс риска, обратимость и компенсация). Построчное сопоставление с «единым контрактом инструмента» M4 концепции: два требования из четырёх покрыты, «схема» (интерфейсная сигнатура) не покрыта вовсе, «идемпотентность» присутствует не полем, а явным ограничением в разделе «Границы». То есть **кандидат с названными пробелами**, а не готовый вклад — и проверяемым предложение делают именно названные пробелы.

**Измеренная трассируемость (побочный, но самый цитируемый результат).** Из 120 требований `REQ-` **52 не упомянуты ни одним производным артефактом** — ни дизайном, ни планом, ни командой, ни агентом, ни хуком. У одиннадцати областей из тринадцати непокрыты **все** требования: `REQ-RECON-*` 13 из 13, `REQ-AUTO-*` 6 из 6, `REQ-BL-*` 6 из 6, `REQ-INPLACE-*` 3 из 3 и шесть одиночных. При этом они реализованы: авторежим работает, бэклог используется, `/sdx:reconcile` написана. **Разрыв в связи, а не в коде** — требование, реализованное без ссылки, неотличимо от забытого. Это предмет `PROC-016`, теперь с числом.

**Верификация — пять кругов, четыре `FAIL`, и все четыре в измерительной части.** Аналитическая часть (§3–§5) подтверждалась без единого замечания все пять кругов подряд. Причина асимметрии оказалась содержательной: репозиторий пишет идентификаторы требований **пятью формами** — простой, перечислением `REQ-A-1/2/3`, диапазоном `REQ-A-1..5`, двусоставным именем области `REQ-CLOSEOUT-ENTRY-1` и буквенным подномером `REQ-AUDIT-16б`, — и каждый круг вскрывал очередную. Отдельно на четвёртом круге выяснилось, что метрика «упомянуто где-либо в репозитории» **самоопровергающаяся**: под ней покрытие равно 120 из 120, потому что отчёт аудита перечисляет непрослеживаемые требования диапазонами в составе находки, измеряющей ровно этот феномен. Область измерения перебазирована на объединение пяти каталогов производных артефактов.

**Урок, дополняющий два предыдущих.** Показательно, что за четыре пересчёта менялись почти все числа, кроме величины **52** и таблицы кучности — устойчивой оказалась ровно та величина, на которой стоит вывод. Практическое правило: если измерение служит выводу, проверять надо не число, а его устойчивость к смене метода; число, меняющееся при каждом уточнении метода, выводу служить не может.

**Два вынужденных отклонения, оба квитированы:** субагент `qa` не вызывался (трек `standard` его предписывает, но кода нет — сьют прогнан, 10 из 10, артефакта прогона в сессии нет); таблица §4 опирается на поля записей `FEAT-006`/`FEAT-008`, которые спроектированы, но не реализованы.

**Затронутые документы:** `docs/designs/spec-format-feasibility.md` (новый), `docs/backlog/PROC-023` (закрыта), `docs/backlog/PROC-025` (новая), индекс бэклога.

**Бэклог:** закрыта `PROC-023`. Новая `PROC-025` — в номенклатуре из одиннадцати типов сессий нет исследования: работы, производящей документ и не производящей кода. Зазор вынудил взять тип «ближайший, а не верный» и отступить от буквы `/sdx:verify`; рекомендация — решать вместе с `PROC-012`, который своей «одной шкалой с опциональными артефактами» закрывает зазор сам.

**Следствия для бэклога, оформление которых — зона `grooming`:** `PROC-021` сужается (одно из восьми соответствий неверно, семь не исследовались); `FEAT-003` получает второе, внешнее обоснование и подтверждается в волне 1; `DEBT-031` в суженной редакции перестаёт быть блокирующей; раздел «Внешнее подтверждение» записи `PROC-017` половинчат — цитата концепции подтверждает версионирование, но не миграцию.

---

## 2026-09-01 — refactor-tracks-collapse-20260901 (refactor, трек full)

**Цель:** реализовать `PROC-012` и `PROC-013` — снести машинерию адаптивных треков и enforcement порядка процесса, чтобы удешевить последующие доработки волны 1. Скоуп сознательно сужен пользователем: `PROC-017` (delta-first) и `FEAT-006` (модель полномочий) вне периметра, окно между сносом `stage-gate` и приходом замещающего механизма принято осознанно.

**Итог: 56 файлов, +1599 / −3360** — чистое сокращение фреймворка на 1761 строку. Версия `1.7.0 → 2.0.0` (ломающая смена схемы состояния и состава команд). Решение зафиксировано **ADR-020**.

**Что снесено:** хуки `stage-gate.sh` (76) и `stage-write-guard.sh` (353) с тестами (216+494) и per-project конфигом; команды `/sdx:retrack` (172) и `/sdx:backtrack` (25); heredoc-матрица `SDX_STAGE_MATRIX` и её sanity-сценарии; forward-skip guard; поле `track` в `session_state.json`. **Что не тронуто:** слой, охраняющий необратимое — `prod-guard`, `archive-verify` и (за единственным вынужденным исключением ниже) `stop-gate`.

**Что построено вместо:** одна каноническая шкала из девяти этапов (`SDX_STAGE_TABLE`, четыре столбца: этап, гейт-артефакт, проверка `FAIL`, складываемость) плюс два ортогональных булевых флага `no_code`/`no_gates`. `sdx-stage.sh` — 522 → ~410 строк, две подкоманды вместо четырёх (`init`, `next [--to]`). Активность этапа перестала быть свойством трека и стала эмерджентной: флаги сужают детерминированно, объём дельты — прозаическим суждением оркестратора на каждом гейте.

**Инвариант ADR-018 сохранён механически, а не переписан в прозу.** Прежде «прототип нельзя закрыть без легализации» держалось формой данных — у трека `vibe` просто не было строки `Closeout` в матрице. Замена того же класса: `no_gates == true` ограничивает активный набор до `{Execution}` приоритетным условием, исполняемым раньше разбора аргументов. Логика spec-after реверс-инжиниринга (~120 строк) перенесена из удаляемой `retrack.md` в `commands/proto.md` **до** удаления донора — иначе исчезла бы безвозвратно.

**Одно вынужденное исключение из «слой необратимого не трогается».** Коллизию нашёл `architect` на Technical Design и остановился, а не решил молча: после сноса `no_gates`-сессия работает на `stage == "Execution"` — том же имени, на котором `stop-gate` включает тест-пол, — и снос **побочным эффектом отменил бы** иммунитет прототипирования к тест-полу. Architect рекомендовал принять как усиление; я рекомендовал обратное и пользователь согласился: хук научен читать `no_gates` (одно условие), поведение ADR-018 сохранено дословно. Контракт при этом был возвращён на Business Spec и дополнен `REQ-ENF-2`, а не поправлен задним числом.

**Верификация — два круга fresh-eyes плюс отдельный прогон `qa`, оба круга `PASS`, 19 находок.**

`qa` нашёл два дефекта **экспериментом на дискриминацию**, а не чтением: (1) тест на взаимоисключение флагов оставался зелёным при отключении проверяемого кода — срабатывало соседнее условие с другим сообщением; (2) **реальный дефект** — `next` без `--to` на пустом или отсутствующем `.stage` молча «лечил» состояние переходом на `Discovery` вместо диагностики. Первопричина: асимметрия AWK-паттернов, где `$1==s` совпадал с пустой ведущей строкой heredoc, а `$1{...}` её пропускал. Отягчало то, что эта же поставка снимает `stage-write-guard`, то есть прямая правка состояния больше ничем не защищена.

Круг 1 ревью (11 WARN) вскрыл **поведенческий дефект**: `REQ-SCALE-4` объявлен «безусловным», а на `next --to` не проверялся — `--to "Execution"` на `no_code`-сессии проходил молча. Круг 2 (8 WARN) подтвердил правку и нашёл то, что все предыдущие проходы пропустили: **шаблоны `sdx/templates/{retro,postmortem,intake}.md` ссылались на раздел протокола, которого больше нет**, а они копируются в каталог каждой будущей `no_code`-сессии; в карте правок документации их не было вовсе.

**Урок, продолжающий два предыдущих.** Сплошная сверка остатков (задача T-33) нашла два пропуска, которые тридцать три предыдущие задачи не заметили: `.claude-plugin/plugin.json` описывал плагин через «adaptive tracks» и снятый хук, а `preflight.sh` предупреждал пользователя о деградации хука, которого больше нет. Оба — пользовательские поверхности. Вывод для будущих сносов: **манифест и стартовые предупреждения не находятся грепом по предметной терминологии** — они говорят о системе своими словами, и их надо проверять отдельным пунктом плана, а не полагаться на сквозной поиск.

**Отдельная ирония, зафиксированная как факт:** правя код на этапе Verification, `developer` не смог использовать `Edit` — его блокировал устаревший `stage-gate` из **установленной** копии плагина, то есть ровно тот хук, который эта поставка сносит. Пришлось идти через `Bash`, задокументированным обходом `DEBT-003`.

**Бэклог:** закрыты девять записей — `PROC-012`, `PROC-013` (частично: доля `FEAT-006` вне периметра) и семь, чей предмет исчез вместе со сносом (`DEBT-003`, `DEBT-009`, `DEBT-014`, `DEBT-015`, `DEBT-016`, `DEBT-024`, `DEBT-025`). `DEBT-023` намеренно оставлена (`REQ-LEGAL-4`), `BUG-005` и `DEBT-007` ждут `PROC-019`. Новые: `DEBT-034` (новая машинерия не подтверждена ни одной живой сессией — класс `DEBT-028`, но цена выше: через неё проходит каждая сессия), `DEBT-035` (два инварианта флагов enforced только прозой; не новое ограничение, но заметное после сноса).

**Что осталось непроверенным исполнением и почему.** Поставка исполнялась под **установленной копией плагина 1.7.0**, а не под правленым деревом: команды `/sdx:*` этой сессии резолвились в старый код. Это не упущение — иначе сессия меняла бы механизм собственного надзора по ходу работы (`PROC-020`). Доказательная база: 103 сценария сьюта с проверкой ключевых на дискриминацию плюс прямые прогоны на временных фикстурах. Связка «команда → новый `sdx-stage.sh` → состояние» целиком не исполнялась ни разу — это `DEBT-034`.

**Затронутые документы:** `docs/specs/stage-scale-and-mode-flags.md`, `docs/designs/stage-scale-and-mode-flags.md`, `docs/DECISIONS.md` (ADR-020), `docs/history/plans/refactor-tracks-collapse-20260901.md`, `sdx/protocol.md`, `CLAUDE.md`, оба README, 13 команд, 9 агентов, 4 шаблона, `.claude-plugin/plugin.json`.

**Следующий шаг:** `/plugin marketplace update sdx` — первая сессия на 2.0.0 закроет `DEBT-034` и станет сквозной проверкой того, что построено.

---

## 2026-09-01 — fix-stop-gate-exec-bit-20260901 (bug, дельта свёрнута в `change_note.md`)

**Цель:** закрыть `DEBT-026` — `stop-gate` определял тест-команду проверкой бита выполнения, и потеря бита при установке молча снимала тест-пол. Первая сессия волны 1 и первая сессия, реально прошедшая по машинерии `ADR-020`.

**Итог: 8 файлов, +237 / −18.** Версия плагина `2.0.0 → 2.1.0`. `test-stop-gate.sh` 14 → 20 сценариев, полный прогон 8/8 сьютов.

**Запись бэклога оказалась права в выводе и неправа в обосновании.** `DEBT-026` просил убедиться, что снятие бита нигде не задокументировано как способ выключить раннер, и сообщал, что просмотр двух файлов такой конвенции не нашёл. Сверка по всему репозиторию нашла её в двух других местах: `ADR-4` и шапка `verify-cmd.sh.template` («HOW TO ACTIVATE: cp … ; chmod +x …»). Discovery остановился на коллизии триады, решение принял пользователь.

**Аргумент, решивший коллизию, не содержался ни в записи, ни в ADR.** Обоснование `ADR-4` — «проверка `[ -x ]` гарантирует, что неисполняемый `.template` не подхватится» — **фактически неверно**: проверка идёт по пути `verify-cmd.sh`, шаблон называется `verify-cmd.sh.template` и не попадает ни под `[ -x ]`, ни под `[ -f ]`. От подхвата защищает **имя файла**, а не режим. Бит нёс не ту нагрузку, которую ему приписывал ADR, а цену имел реальную (`BUG-008`: установщик разворачивает всё как `0600`). `ADR-4` получил поправку с явным признанием ошибки в исходном обосновании — не тихую замену условия.

**Второй круг fresh-eyes нашёл регрессию, внесённую правками по замечаниям первого круга.** Первая редакция исполняла раннер безусловно как `bash <путь>`. До правки `bash -c "$path"` делал `execve`, ядро читало shebang — раннер на python или zsh с битом `x` работал; безусловный `bash` дал бы такому проекту **постоянно красный пол**, молча. Ирония точная: починка одной тихой смены поведения вносила другую. Исправлено разведением двух вопросов, которые правка до этого смешивала: **действует ли пол** решает наличие файла, **как вызвать раннер** решает бит (исполняемый — напрямую по своему shebang'у, неисполняемый — как bash). Оба пути держат пол; ни один не спрашивает режим о том, enforce'ить ли вообще.

**Пять находок за два круга, четыре исправлены, одна квитирована.** Круг 1: отсутствие стража у инварианта «шаблон исключается именем файла», ставшего единственной защитой (сценарий `[18]`); смягчение риска, покрывающее только новые установки, но не апгрейд-путь (буллет-находка в `/sdx:reconcile` по прецеденту орфан-конфига `stage-gate.allow`). Круг 2: регрессия с shebang'ом; оговорка `reconcile.md`, выведенная в единственном числе под один файл и потому исключавшая новый буллет; **инертность смягчения без бампа версии** — `/sdx:reconcile` предлагается только при расхождении маркера `.claude/sdx/sdx-version` с версией плагина, поэтому без `2.0.0 → 2.1.0` потребитель, уже сверившийся на 2.0.0, не получил бы предложения и семантика сменилась бы молча. Бамп здесь — несущая часть смягчения, а не косметика.

**Каждый новый сценарий проверен мутацией на дискриминацию,** а не принят по зелёному прогону: `-f` → `-x` красит `[15]`/`[16]`; подмена прямого вызова на `bash -c` красит `[17]`; расширение условия до глоба `verify-cmd.sh*` красит ровно `[18]`; возврат к безусловному `bash "$runner"` красит ровно `[19]`. Субагент `qa` независимо подтвердил дискриминацию тем же приёмом и проверил ветку автодетекта вручную.

**Побочно закрыта находка `SEC5` аудита `audit-2026-07-26`** — путь проекта подставлялся в интерпретируемую шелл-строку `bash -c "$cmd"`: путь с пробелом расщеплялся, путь с метасимволами интерпретировался. Своей записи бэклога у находки не было; закрыта как неотделимая часть п.1 рекомендации `DEBT-026`, сценарий `[17]`.

**Два наблюдения о состоянии бэклога, не связанных с целью сессии.** Первое: `BUG-003`, которым волна 1 должна была начаться, оказался **протухшим** — дефект снят `ADR-012` за четыре дня до аудита, который его завёл, а груминг поднял запись до `high` и перенёс в волну 1, не сверив с кодом. Закрыта резолюцией отдельной веткой до старта этой сессии; механизм промаха оформлен записью `PROC-026`. Второе: отчёт `docs/history/audit/audit-2026-07-26.md` (92 находки) **не разобран** — ни одна запись бэклога не ссылается на него как на `source`, хотя лог сессий называл триаж следующим шагом; отслежено `DEBT-028`.

**Затронутые документы:** `sdx/hooks/stop-gate.sh`, `sdx/hooks/test-stop-gate.sh`, `sdx/templates/verify-cmd.sh.template`, `commands/init.md`, `commands/reconcile.md`, `sdx/protocol.md`, `docs/designs/phase1-enforcement-routing.md` (поправка к `ADR-4`), `docs/specs/phase1-enforcement-routing.md` (поправка к `REQ-GATE-2`), `.claude-plugin/plugin.json`.

**Бэклог:** закрыта `DEBT-026`. Новые: `DEBT-036` (ветка автодетекта тест-команды без автотестов — квитированный WARN). Вне сессии, до её старта: `BUG-003` закрыта как протухшая, заведена `PROC-026`. Дополнена `DEBT-034` — подтверждены три пункта из шести, запись остаётся `open`.

**Что осталось непроверенным исполнением:** правка `stop-gate.sh` не действовала на саму эту сессию — хук резолвился из установленной копии плагина, а не из правленого дерева (`PROC-020`, тот же механизм, что и в предыдущей поставке). Доказательная база — 20 сценариев сьюта с мутационной проверкой ключевых. Ветка автодетекта проверена вручную, но не автотестами (`DEBT-036`).

---

## 2026-09-01 — feat-enforcement-selftest-20260901 (feature, полный цикл SPEC/DESIGN/PLAN)

**Цель:** закрыть `FEAT-014` (self-test enforcement-слоя) и `DEBT-010` (тихая деградация хуков не видна пользователю) — груминг предписал делать их одной волной: одно даёт машинное доказательство живости слоя, другое предъявляет его человеку.

**Итог: 12 файлов, +1535 строк дельты.** Новый хук `sdx/hooks/selftest.sh` второй записью `SessionStart`, новый сьют `test-selftest.sh` (36 сценариев), новый статический сьют `test-init-patterns.sh`, шаг 5 «Здоровье enforcement» в `/sdx:status`. Прогон 10/10 сьютов.

**Discovery обнаружил, что постановка записи частично не стоит на земле — и это определило всю поставку.** Контракт `FEAT-014` («отсутствие доказанной живости = автономия недоступна») подключить не к чему: автономии нет (`FEAT-009`/`FEAT-010` — волна 4), классов риска нет (`FEAT-006` — волна 2, `permissionDecision` эмитируется ровно с одним значением `deny`), журнала прогона нет (`FEAT-004`). Просимые записью `allow`/`ask`-кейсы — словарь будущего. А класс `BUG-008`, которым запись обоснована, поведенческий self-test **не ловит вовсе**: он вызывает хуки как `bash <путь>`, ровно как штатная проводка, и потому нечувствителен к биту `x`.

Пользователь выбрал полный объём, **честно помеченный**. Отсюда область `REQ-LIMIT-*` — три требования об **отсутствии ложных обещаний**, с приёмкой через grep по текстам, и сценарий `[T21]`, который **прибивает неспособность**: при `chmod 0600` проба обязана остаться `pass`. Тест, фиксирующий границу, а не возможность.

**Пять кругов fresh-eyes: три блокирующих дефекта в коде, два в текстах.** Все три кодовых — одного класса: *поставка вела себя правильно в этом репозитории и неправильно за его пределами*, и каждый раз слепое пятно было в фикстурах, не отличавших свой случай от чужого.

1. **Круг 1.** Сценарий `T13` писал в `.stopgate.*` живой сессии и затирал файл, который `stop-gate` держал открытым на запись в том же прогоне: `.stopgate.out` обрывался на баннере `[T13]`, а именно его `tail -20` показывается пользователю на красном прогоне. Поставка про видимость деградации ломала диагностику слоя.
2. **Круг 2.** Паттерн `.claude/sdx/.cache/` был добавлен в `.gitignore` этого репо и не добавлен в канонический список `/sdx:init`. У любого потребителя новый хук создавал untracked-файл, а `archive-verify` инвариантом 1 проверяет `git status --porcelain` — **упал бы каждый `/sdx:archive`**. Здесь всё было зелено потому, что `.gitignore` правился руками.
3. **Круг 3.** Хук безусловно создавал кэш в **любом** проекте, где сработал `SessionStart`, включая никогда не видевшие `/sdx:init`, — при том что оба README обещают обратное, а три соседних хука следов не оставляют по построению.

**Урок, ради которого стоит перечитывать эту запись.** Слепое пятно каждый раз было не в коде, а в **фикстурах**: голый `mktemp -d` неотличим от чужого проекта, поэтому тесты структурно не могли поймать ни один из трёх дефектов. Починка дефекта без починки фикстуры оставляла бы дыру открытой — поэтому вместе с гардом были перестроены восемь фикстур, чтобы они выражали «это SDX-проект», а не полагались на прежнюю снисходительность кода.

**Круг 4 поймал ошибку в тексте, внесённом по замечанию круга 1.** Ревьюер круга 1 сообщил, что sentinel `ABSENT` не срабатывает; утверждение было принято на веру и записано в `DESIGN` как «поправка». Эксперимент опроверг: скрипт работает под `set -uo pipefail`, ненулевой статус любого звена конвейера делает ненулевым весь конвейер, sentinel срабатывает штатно. Ошибка прожила два круга. Отзыв оставлен в `DESIGN` явным блоком, а не удалён: утверждение о поведении не стоит ничего, пока не предъявлено исполнением, — включая утверждения ревьюера и оркестратора.

**Круг 5 — `PASS`, и четыре из семи его WARN снова про точность утверждений:** «на порядок дешевле» при фактических 4.5× (порядок даёт измеренная величина, не порог); механизм отказа на BSD, заявленный как факт без прогона; «вынесено записью бэклога» в прошедшем времени при отсутствующей записи; семь позиций поставки, описанных только в статусном абзаце `PLAN` — включая `commands/reconcile.md`, единственную, которая **правит файл пользователя**.

**Тест-пол сработал вживую впервые за обе сессии на новой машинерии:** `stop-gate` вернул `exit 2` и не дал завершить ход, пока фоновый субагент был на середине правки и прогон показывал 9/10. Ровно то поведение, ради которого он существует.

**Затронутые документы:** `sdx/hooks/{selftest.sh,test-selftest.sh,test-init-patterns.sh,test-hook-wiring.sh,test-archive-verify.sh,archive-verify.sh}`, `hooks/hooks.json`, `commands/{status.md,init.md,reconcile.md}`, `sdx/protocol.md`, `README.md`, `README.en.md`, `CLAUDE.md`, `.gitignore`, `docs/specs/enforcement-selftest-and-health.md`, `docs/designs/enforcement-selftest-and-health.md`, `docs/history/plans/feat-enforcement-selftest-20260901.md`.

**Бэклог:** закрыты `FEAT-014` и `DEBT-010`. Новые: `BUG-009` (нечисловой `.stopgate.count` роняет `stop-gate` кодом 1 — тест-пол исчезает молча; побочная находка), `BUG-010` (непереносимость `date +%s%N` и `timeout` за пределы GNU — на macOS хук не выполняется вовсе), `DEBT-037` (живая проводка `SessionStart` не исполнялась ни разу). Волна 1 сократилась до трёх записей: `FEAT-003`, `FEAT-004`, `PROC-019` — связанная цепочка, где kill-test является приёмочным критерием всей волны.

**Что осталось непроверенным исполнением:** проводка хука по реальному событию (`DEBT-037`) — сессия исполнялась под установленной копией плагина, а не под правленым деревом (`PROC-020`). Закрывается наблюдением после `/plugin marketplace update sdx`, и шаг 2 этого наблюдения — заведомо чужой проект: единственная проверка обещания обоих README.

---

## 2026-09-02/03 — proc-run-as-durable-unit-20260902 (feature, полный цикл SPEC/DESIGN/PLAN)

**Предмет переопределён Discovery, и это главное, что стоит унести из записи.** `PROC-019`
утверждала, что состояние прогона недолговечно целиком: падение CLI требует человека, чтобы
восстановить смысл работы. Живой kill-test на закрытой сессии
(`docs/history/experiments/kill-test-2026-09-02.md`) опроверг это наполовину. Состояние **задач**
уже durable — оно выводится из закоммиченных `session_state.json`, чек-боксов `PLAN.md` и строк
`[STAGE_CHANGE]`. Недолговечны **решения человека**: в `gate_mode: interactive` решение, принятое
на стоп-рубрике, не фиксировалось нигде, потому что `auto_decisions.md` заводится исключительно
при `gate_mode: auto`. Это единственное, что нельзя вывести заново с диска.

Отсюда — отказ от реестра задач (`FEAT-003`), который был запланирован волной 1 как предпосылка:
он дублировал бы то, что git уже хранит. Поставлены `decisions_log.md` (ленивый append-only
журнал, четыре поля, семь тегов по стоп-рубрике, батчинг в уже происходящий коммит) и
`/sdx:resume`.

**Четыре круга fresh-eyes, семь блокирующих находок — и четыре из них были регрессиями правок
предыдущего круга.** Распределение FAIL по кругам: 2 → 2 → 2 → 1.

1. **Круг 1.** Композиция `/sdx:resume` читала последнюю строку `session.log`, а не последний
   `[STAGE_CHANGE]`: `grep -l` печатает имя файла, поэтому `tail -1` брал хвост файла. Дефект
   срабатывал ровно в целевом сценарии — после смерти CLI последней строкой лога штатно
   оказывается `[ERROR]`. Тест не различал корректную и дефектную форму, потому что фикстура
   заканчивалась строкой `[STAGE_CHANGE]` в формате, которого реальный писатель не производит.
2. **Круг 2.** Фолбэк исправленной строки оказался мёртв вне `pipefail`: статус конвейера равен
   статусу `tail`, а `tail -1` на пустом входе возвращает `0`. **Граничный тест был зелёным
   потому, что сьют объявляет `set -uo pipefail`, которого в среде исполнения команды нет** —
   тест доказывал свойство своей среды и выдавал его за свойство поставки.
3. **Круг 3.** Предписание записать решение жило внутри ветки `- Если "auto":`: в `interactive` —
   режиме по умолчанию и первом адресате требования — команда о записи не говорила ничего. От
   `gate_mode` зависело само НАЛИЧИЕ инструкции. Отягчало то, что структурный маркер греплил
   именно auto-формулировку и **тем закреплял дефект как эталон**.
4. **Круг 4.** Гард чистого дерева был безусловным, из-за чего `/sdx:resume` оказывалась
   непригодной для сессий с `no_gates == true`: у прототипа некоммиченный код — санкционированное
   состояние. При этом текст объявлял свой гард симметричным `commands/switch.md`, где эта
   оговорка есть.

**Урок, ради которого стоит перечитывать эту запись.** Дважды подряд дефект сидел не в
измеряемом, а **в самом критерии измерения**: регулярка `check_dec` браковала корректные записи с
многословным именем этапа (`(этап: Technical Design)`) — и пережила шесть красных веток, потому
что все шесть проверяли, ловит ли помощник брак, и ни одна — пропускает ли он годное. Критерий
измерения нужно проверять в обе стороны так же, как тест, и сверять с соседними критериями того
же документа, а не только с системой.

**Ручной прогон исполнен не автором — и это оказалось содержательно, а не церемониально.** Восемь
шагов отданы свежим агентам в роли Session Manager, каждому на своей одноразовой фикстуре, БЕЗ
подсказки, что ожидается запись в журнал: проверялась достаточность прозы, а автор, знающий
ожидаемый ответ, такую проверку провести не может. Две категории — `[контракт]` и `[ручной-шаг]` —
не имеют инструкции ни в одном файле `commands/`, их источник только раздел протокола; обе
прошли, агенты вывели необходимость записи сами. Один из них вдобавок отказался трактовать
пользовательское «гейт не блокируем» как отмену правила и записал шаг `Failed`, положив решение
рядом с оговоркой. Симметрия `auto`/`interactive` продемонстрирована исполнением: в `auto` агент
остановился на `FAIL` и автоквитировал `WARN` — два журнала остались непересекающимися.

**Затронутые документы:** `commands/{resume.md,next.md,verify.md,proto.md,status.md}`,
`sdx/hooks/{test-resume-contract.sh,test-sdx-stage.sh,sdx-stage.sh}`, `sdx/protocol.md`,
`docs/DECISIONS.md` (поправка ADR-014), `docs/designs/stage-scale-and-mode-flags.md`,
`README.md`, `README.en.md`, `CLAUDE.md`. Постоянные:
`docs/specs/decision-journal-and-resume.md`, `docs/designs/decision-journal-and-resume.md`,
`docs/designs/decision-journal-discovery.md`,
`docs/history/experiments/kill-test-2026-09-02.md`,
`docs/history/plans/proc-run-as-durable-unit-20260902.md`.

**Бэклог.** Закрыты `PROC-019`, `DEBT-038`, `DEBT-007` (расщеплена), `BUG-005`. Пересмотрены:
`FEAT-003` (волна 1 → 3, обоснование сменено с durability на машиночитаемость для `FEAT-005`),
`FEAT-004` (расщеплена — наблюдательная половина остаётся, «решение запрошено/получено»
поглощено `PROC-019`), `IDEA-004` (посылка переписана: `/sdx:resume` не читает `checkpoint.md`
вовсе, поэтому рекомендация записи читается наоборот; статус оставлен `deferred` решением
пользователя). Новые: `DEBT-039` (`status` без писателя), `DEBT-040` (сценарии мутируют
собственные хелперы), `DEBT-041` (anti-overclaim линт направленный), `PROC-027` (у перечней
состава системы нет сторожа — третье расхождение подряд).

**Волна 1 закрыта полностью.** Побочно вскрылось, что **отсрочка «до волны N» не имеет срока
годности**: `DEBT-007` и `BUG-005` ждали волну 1, и когда та закрылась, перечитать их было
некому. У `BUG-005` предпосылка вообще оказалась неверной — `.claude/sessions/` не в `.gitignore`
уже с `ADR-012`, проверка занимала одну команду `git check-ignore`. Это второй прецедент
`PROC-026` (груминг пересматривает атрибуты, не сверяя с кодом), дописан туда же.

**Что осталось непроверенным исполнением.** Приёмочные критерии #4, #5, #6, #10 требуют вызова
`/sdx:resume` настоящей слэш-командой — сессия, вводящая команду, этого сделать не может
(`PROC-020`: команды резолвятся из установленной копии плагина). Проверены data-layer композиции,
сопоставление развилки с журналом и структура прозы с доказанными красными сторонами; не
наблюдалась сама последовательность «смерть процесса → вызов команды → продолжение». Отдельно:
правки круга 4 независимым кругом ревью не проверялись — пятый круг не запускался по решению
пользователя.
