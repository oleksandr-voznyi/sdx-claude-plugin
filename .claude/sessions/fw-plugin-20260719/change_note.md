# Change Note — fw-plugin-20260719

## Цель
Упаковать SDX-фреймворк в **плагин Claude Code**, чтобы вести SDD в разных проектах на одном сервере без тиражирования файлов фреймворка (`/plugin marketplace add <этот-репо> && /plugin install sdx@sdx --scope user` — и команды `/sdx:*` доступны во всех проектах).

## Бизнес-решения
- Дистрибуция фреймворка меняется с «копировать `.claude/` в каждый проект» на «один плагин, установленный на уровне пользователя». Репозиторий `sdx.cld` становится одновременно плагином и его marketplace.
- Пространство имён команд сохраняется: плагин с `name: sdx` даёт те же вызовы `/sdx:start`, `/sdx:next` и т.д. — переучивание не требуется.
- В каждом целевом проекте остаётся только **per-project** слой: каталог `docs/` (specs/designs/history), артефакты сессий `.claude/sessions/<id>/` и опциональные конфиги enforcement (`.claude/sdx/prod-guard.conf`, `stage-gate.allow`, `verify-cmd.sh`). Их разворачивает `/sdx:init`.

## Технические решения
1. **Корень репозитория = плагин** (root-as-plugin):
   - `.claude-plugin/plugin.json` — манифест (`name: sdx`);
   - `.claude-plugin/marketplace.json` — marketplace `sdx` с единственным плагином `source: "./"`;
   - `commands/*.md` — 13 команд (перенос из `.claude/commands/sdx/`, плоская структура: неймспейс даёт имя плагина, подкаталоги вложенных неймспейсов не создают);
   - `agents/*.md` — 8 субагентов (перенос из `.claude/agents/`);
   - `hooks/hooks.json` — проводка SessionStart/PreToolUse/Stop через `${CLAUDE_PLUGIN_ROOT}` (перенос из `.claude/settings.json`);
   - `sdx/` — protocol.md, hook-скрипты с тестами, шаблоны per-project конфигов (перенос из `.claude/sdx/`).
2. **Пути внутри контента**: все ссылки `.claude/sdx/protocol.md` и `bash .claude/sdx/hooks/...` в командах/агентах заменяются на `${CLAUDE_PLUGIN_ROOT}/sdx/...` (переменная подставляется в markdown команд/агентов и в hooks.json). Вместо `@`-инлайна протокола — явная инструкция Read (инлайн 200+ строк в каждый вызов команды дорог, а подстановка `${...}` внутри `@`-меншена не гарантирована).
3. **Hook-скрипты не меняются по логике**: project-файлы они и так читают из `$CLAUDE_PROJECT_DIR/.claude/sdx/` (per-project конфиги) и `$CLAUDE_PROJECT_DIR/.claude/sessions/` (сессии), соседей — через `$(dirname BASH_SOURCE)`. Меняется только их местоположение (внутрь плагина) и источник проводки (hooks.json плагина вместо settings.json проекта).
4. **`/sdx:init` переписан под плагин**: больше не «скопировать `.claude/`», а: создать `docs/`-структуру и `.claude/sessions/`, targeted-паттерны `.gitignore`, разложить шаблоны конфигов enforcement из `${CLAUDE_PLUGIN_ROOT}/sdx/templates/`, проверить `jq`, опрос про prod-среду (как раньше), плюс детект legacy-копии фреймворка (`.claude/commands/sdx/` в проекте) с предложением удалить во избежание дублирования команд.
5. **Мета-репозиторий сам переходит на плагин** (догфудинг): `.claude/commands/`, `.claude/agents/`, `.claude/sdx/{protocol.md,hooks/,verify-cmd.sh.template}` удаляются; `.claude/settings.json` очищается от hook-проводки; остаются per-project `.claude/sdx/prod-guard.conf` и `stage-gate.allow` (в этом репо — пустые/комментарии, protection opt-out осознанно). До установки плагина в этом репо enforcement-слой неактивен — зафиксировано в README.
6. **CLAUDE.md не входит в плагин** (плагины его не автозагружают): переносимый минимум правил живёт в командах и `protocol.md`; для целевых проектов плагин везёт готовый сниппет `sdx/templates/claude-md-snippet.md`, который `/sdx:init` предлагает добавить в CLAUDE.md проекта (с согласия пользователя).
7. **README.md** в корне: назначение, установка (marketplace add + install --scope user), структура плагина, per-project слой.

## Затронутые файлы
- Перенос: `.claude/commands/sdx/*` → `commands/*`; `.claude/agents/*` → `agents/*`; `.claude/sdx/{protocol.md,hooks/**,verify-cmd.sh.template}` → `sdx/**`.
- Новые: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `hooks/hooks.json`, `sdx/templates/*`, `README.md`.
- Правки: тексты команд/агентов (пути), `protocol.md` (раздел enforcement/проводка), `CLAUDE.md` (структура проекта), `.claude/settings.json`, `.gitignore` (при необходимости).

## Риски / допущения
- Подстановка `${CLAUDE_PLUGIN_ROOT}` в markdown команд и агентов — подтверждена документацией Claude Code (см. Discovery). Если в какой-то версии не подставится в агентах, деградация мягкая: агент увидит literal-строку и не найдёт protocol.md; команды передают субагентам пути явно.
- Плагин, установленный из локального marketplace, кэшируется копией: после правок фреймворка нужен `/plugin marketplace update sdx` (зафиксировано в README).
- Один плагин на пользователя означает: хуки плагина активны во всех проектах. Скрипты safe-by-default (no-op вне веток `sdx/*` и без конфигов) — свойство сохранено, проверяется тестами hook-скриптов.
