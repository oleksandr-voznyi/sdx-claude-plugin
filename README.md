# SDX — Spec-Driven X для Claude Code

SDX — фреймворк Spec-Driven Development (SDD) для Claude Code, упакованный как **плагин**: жизненный цикл сессий (`/sdx:start` → … → `/sdx:archive`), ролевые субагенты, адаптивные треки церемонии и детерминированный enforcement-слой на хуках. Один установленный плагин обслуживает все проекты на машине — тиражировать файлы фреймворка по проектам не нужно.

## Установка

Репозиторий одновременно является marketplace и плагином; канонический источник — GitHub: `git@github.com:oleksandr-voznyi/sdx-claude-plugin.git` (private — на машине нужен ssh-ключ/deploy key с правом чтения).

**Рекомендуемый способ — bootstrap-скрипт** (идемпотентен; ставит `jq`, регистрирует marketplace, устанавливает плагин user-scope во все проекты машины, включает автообновление при старте сессии):

```bash
git clone --depth 1 git@github.com:oleksandr-voznyi/sdx-claude-plugin.git /tmp/sdx-plugin \
  && /tmp/sdx-plugin/scripts/sdx-migrate.sh \
  && rm -rf /tmp/sdx-plugin
```

Вручную то же самое:

```bash
claude plugin marketplace add git@github.com:oleksandr-voznyi/sdx-claude-plugin.git
claude plugin install sdx@sdx --scope user
# автообновление при старте сессии: extraKnownMarketplaces.sdx.autoUpdate=true в ~/.claude/settings.json
```

Обновления подтягиваются автоматически при старте сессии (`autoUpdate: true`); форс — `/plugin marketplace update sdx`. У потребителей обновление плагина срабатывает по бампу `version` в `plugin.json` — поднимайте его при каждом значимом релизе.

## Миграция проекта со старой (vendored) версии SDX

В корне проекта со старой копией фреймворка запустите `scripts/sdx-migrate.sh` (при отсутствии legacy-детекта — с флагом `--project`): скрипт удалит legacy-файлы фреймворка (`.claude/commands/sdx/`, SDX-агенты в `.claude/agents/`, `.claude/sdx/{protocol.md,hooks/}`), снимет старую hook-проводку из `.claude/settings.json` проекта и объявит в нём зависимость (`extraKnownMarketplaces` + `enabledPlugins: {"sdx@sdx": true}`), не тронув per-project слой (`.claude/sessions/`, конфиги `.claude/sdx/`, `docs/`). Изменения остаются незакоммиченными — проверьте, закоммитьте, затем выполните `/sdx:init` для сверки структуры.

## Подключение проекта

В целевом проекте выполните `/sdx:init` (для существующей кодовой базы — `/sdx:init --existing`). Команда разворачивает **per-project слой** — единственное, что живёт в самом проекте:

- `docs/specs/`, `docs/designs/`, `docs/history/plans/` — постоянные документы триады;
- `.claude/sessions/<id>/` — артефакты активных сессий (версионируются на ветке `sdx/<id>`);
- `.claude/sdx/` — конфиги enforcement-слоя: `prod-guard.conf` (блок-паттерны прод-команд), `stage-gate.allow` (доп. allowlist записи до гейта Execution), `verify-cmd.sh` (тест-команда для stop-gate);
- targeted-паттерны в `.gitignore` и (по желанию) SDX-блок в CLAUDE.md проекта.

## Состав плагина

| Путь | Содержимое |
|------|------------|
| `commands/` | 13 команд `/sdx:*` (start, next, status, switch, retrack, backtrack, checkpoint, verify, manual, archive, init, export, import) |
| `agents/` | 8 субагентов: `ba`, `architect`, `lead-dev`, `developer`, `qa`, `reviewer`, `tech-writer`, `devops` |
| `hooks/hooks.json` | Проводка enforcement-слоя (SessionStart / PreToolUse / Stop) |
| `sdx/protocol.md` | Протокол сессий: состояние, треки, гейты, Closeout, import/export |
| `sdx/hooks/` | Скрипты хуков (stage-gate, stop-gate, prod-guard, preflight, archive-verify) и их тесты (`test-*.sh`) |
| `sdx/templates/` | Шаблоны per-project конфигов и SDX-блока для CLAUDE.md |

Хуки safe-by-default: вне ветки `sdx/<id>` и без per-project конфигов они прозрачны (no-op), поэтому user-scope установка не мешает проектам, не использующим SDX.

## Правила и документация

- Процесс, треки, гейты и контракт закрытия сессий: `sdx/protocol.md`.
- Архитектурные решения фреймворка (ADR): `docs/DECISIONS.md`.
- История развития: `docs/history/`.

Требование: `jq` в PATH (используется хуками; проверяется preflight-хуком при старте сессии).
