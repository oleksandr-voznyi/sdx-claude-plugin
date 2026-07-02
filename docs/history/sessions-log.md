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
