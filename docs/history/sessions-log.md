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
