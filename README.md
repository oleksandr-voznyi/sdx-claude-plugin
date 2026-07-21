# SDX — Spec-Driven X для Claude Code

[![Release](https://img.shields.io/github/v/release/oleksandr-voznyi/sdx-claude-plugin?label=%D0%B2%D0%B5%D1%80%D1%81%D0%B8%D1%8F)](https://github.com/oleksandr-voznyi/sdx-claude-plugin/releases)

🇬🇧 [English version](README.en.md)

SDX — фреймворк Spec-Driven Development (SDD) для Claude Code, упакованный как **плагин**: жизненный цикл сессий (`/sdx:start` → … → `/sdx:archive`), ролевые субагенты, адаптивные треки церемонии и детерминированный enforcement-слой на хуках. Один установленный плагин обслуживает все проекты на машине — тиражировать файлы фреймворка по проектам не нужно.

## Установка

Репозиторий одновременно является marketplace и плагином; канонический источник — GitHub: `https://github.com/oleksandr-voznyi/sdx-claude-plugin.git` (public — доступ по https, ключи не нужны).

**Рекомендуемый способ — bootstrap-скрипт** (идемпотентен; ставит `jq`, регистрирует marketplace, устанавливает плагин user-scope во все проекты машины, включает автообновление при старте сессии):

```bash
git clone --depth 1 https://github.com/oleksandr-voznyi/sdx-claude-plugin.git /tmp/sdx-plugin \
  && /tmp/sdx-plugin/scripts/sdx-migrate.sh \
  && rm -rf /tmp/sdx-plugin
```

Вручную то же самое:

```bash
claude plugin marketplace add https://github.com/oleksandr-voznyi/sdx-claude-plugin.git
claude plugin install sdx@sdx --scope user
# автообновление при старте сессии: extraKnownMarketplaces.sdx.autoUpdate=true в ~/.claude/settings.json
```

Обновления подтягиваются автоматически при старте сессии (`autoUpdate: true`); форс — `/plugin marketplace update sdx`. У потребителей обновление плагина срабатывает по бампу `version` в `plugin.json` — поднимайте его при каждом значимом релизе. Каждый бамп сопровождается тегом `vX.Y.Z` на коммите бампа и GitHub-релизом (`gh release create vX.Y.Z --title … --notes …`) — история версий видна на [странице релизов](https://github.com/oleksandr-voznyi/sdx-claude-plugin/releases).

## Миграция проекта со старой (vendored) версии SDX

В корне проекта со старой копией фреймворка запустите `scripts/sdx-migrate.sh` (при отсутствии legacy-детекта — с флагом `--project`): скрипт удалит legacy-файлы фреймворка (`.claude/commands/sdx/`, SDX-агенты в `.claude/agents/`, `.claude/sdx/{protocol.md,hooks/}`), снимет старую hook-проводку из `.claude/settings.json` проекта и объявит в нём зависимость (`extraKnownMarketplaces` + `enabledPlugins: {"sdx@sdx": true}`), не тронув per-project слой (`.claude/sessions/`, конфиги `.claude/sdx/`, `docs/`). Изменения остаются незакоммиченными — проверьте, закоммитьте, затем выполните `/sdx:init` для сверки структуры.

## Подключение проекта

В целевом проекте выполните `/sdx:init` (для существующей кодовой базы — `/sdx:init --existing`). Команда разворачивает **per-project слой** — единственное, что живёт в самом проекте:

- `docs/specs/`, `docs/designs/`, `docs/history/plans/`, `docs/backlog/` — постоянные документы триады и трекаемый бэклог;
- `.claude/sessions/<id>/` — артефакты активных сессий (версионируются на ветке `sdx/<id>`);
- `.claude/sdx/` — конфиги enforcement-слоя: `prod-guard.conf` (блок-паттерны прод-команд), `stage-gate.allow` (доп. allowlist записи до гейта Execution), `verify-cmd.sh` (тест-команда для stop-gate), `sdx-version` (маркер версии плагина, на которой проект последний раз сверен — пишет исключительно `/sdx:reconcile`, сверяет `/sdx:start`);
- targeted-паттерны в `.gitignore` и (по желанию) SDX-блок в CLAUDE.md проекта.

## Состав плагина

| Путь | Содержимое |
|------|------------|
| `commands/` | 16 команд `/sdx:*` (start, next, status, switch, retrack, backtrack, checkpoint, verify, manual, proto, archive, init, export, import, backlog, reconcile) |
| `agents/` | 8 субагентов: `ba`, `architect`, `lead-dev`, `developer`, `qa`, `reviewer`, `tech-writer`, `devops` |
| `hooks/hooks.json` | Проводка enforcement-слоя (SessionStart / PreToolUse / Stop) |
| `sdx/protocol.md` | Протокол сессий: состояние, треки, гейты, Closeout, import/export |
| `sdx/hooks/` | Скрипты хуков (stage-gate, stop-gate, prod-guard, preflight, archive-verify) и их тесты (`test-*.sh`) |
| `sdx/templates/` | Шаблоны per-project конфигов и SDX-блока для CLAUDE.md |

Хуки safe-by-default: вне ветки `sdx/<id>` и без per-project конфигов они прозрачны (no-op), поэтому user-scope установка не мешает проектам, не использующим SDX.

## Адаптивные треки (профили флоу)

Жизненный цикл SDX масштабируется под размер задачи: каждая сессия проходит по одному из **пяти адаптивных треков**, определяющих активные этапы и гейты.

| Трек | Назначение | Типы сессий | Этапы |
|------|-----------|-----------|-------|
| **patch** | Багфикс или точечная правка без изменения логики | `bug` | Execution → Verification → Closeout |
| **standard** | Малая фича или рефактор | `feature`, `refactor` | Discovery → Change → Execution → Verification → Closeout |
| **full** | Крупная фича, затрагивающая контракты или архитектуру | `feature`, `refactor`, `init`, `import` | Discovery → Business Spec → Technical Design → Task Planning → Execution → Documentation → Verification → Deployment → Closeout |
| **doc** | Процессная работа без кода: груминг бэклога, ретроспектива, разбор инцидентов, обработка новых требований | `grooming`, `retro`, `postmortem`, `intake` | Discovery → Update → Verification → Closeout |
| **vibe** | Экстремальное прототипирование: быстрая проверка гипотезы кодом без TDD/`PLAN.md`/коммитов до явного решения | `proto` (жёстко привязан, без триажа) | Prototype (без `Closeout`) |

### Трек `doc` и его типы сессий

Трек `doc` предназначен для работы над самим бэклогом и процессом SDX. Все четыре типа сессий проходят одинаковые этапы; отличие — в содержании входа и выхода:

- **`grooming`** — пересмотр существующих записей бэклога: актуализация статусов, приоритетов, волн. Это **перераспределение** атрибутов уже имеющихся записей.
- **`retro`** — разбор завершённых сессий за период: выявление паттернов и выводы, оформляемые новыми записями бэклога.
- **`postmortem`** — разбор инцидента (production, процессный сбой, дефект): хронология, корневая причина, план действий.
- **`intake`** — обработка нового значительного блока внешних требований (эпик, пачка багрепортов, продуктовый материал): разложение на записи бэклога. Это **создание** новых записей из внешнего материала.

**Ключевое отличие `intake` от `grooming`:** `intake` стоит по потоку выше и занимается **порождением** новых записей из внешнего материала, а `grooming` затем **перераспределяет** приоритеты и волны среди уже накопленного. Оба типа работают с одним и тем же `docs/backlog/`, но в разных направлениях операций.

Каждая doc-сессия обязана произвести минимум одно видимое изменение бэклога и пройти лёгкую верификацию. Для `retro`, `postmortem` и `intake` дополнительно создаётся постоянный документ разбора в `docs/history/`.

### Трек `vibe` и обязательная легализация

Трек `vibe` — режим экстремального прототипирования (ADR-018): единственный тип сессии — `proto`, и привязка `proto → vibe` жёсткая и безусловная (без диалога о выборе трека) — аналогично тому, как все четыре типа `doc` закреплены за своим треком, в отличие от `patch`/`standard`/`full`, где тип — лишь стартовая гипотеза, а трек определяется триажем.

На стадии `Prototype` код пишется одним непрерывным проходом: без `PLAN.md`, без `change_note.md` и — единственное именованное исключение из нормы инкрементальных коммитов (ADR-005) — без промежуточных коммитов. По завершении гейт `/sdx:proto` безусловно запрашивает решение пользователя: **отклонить** прототип (точечный откат к baseline-снимку рабочего дерева) либо **принять** и легализовать сессию через `/sdx:retrack standard|full`. У `vibe` нет собственного `Closeout`: сессия этого трека не может быть закрыта и замёржена в основную ветку без легализации (REQ-VIBE-8) — `/sdx:archive` останавливается на такой сессии и направляет к `/sdx:proto`/`/sdx:retrack`.

## Правила и документация

- Процесс, треки, гейты и контракт закрытия сессий: `sdx/protocol.md`.
- Архитектурные решения фреймворка (ADR): `docs/DECISIONS.md`.
- История развития: `docs/history/`.

Требование: `jq` в PATH (используется хуками; проверяется preflight-хуком при старте сессии).
