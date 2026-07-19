# DESIGN: Дистрибуция SDX как плагина Claude Code

Статус: действующий (сессия fw-plugin-20260719, 2026-07-19). Основание — ADR-013 (`docs/DECISIONS.md`), спека — `docs/specs/plugin-distribution.md`.

## Структура (root-as-plugin)
Корень репозитория — одновременно плагин и marketplace:

```
.claude-plugin/plugin.json        # манифест: name=sdx (даёт неймспейс /sdx:*), version, метаданные
.claude-plugin/marketplace.json   # marketplace "sdx", один плагин, source: "./"
commands/*.md                     # 13 команд (плоско: подкаталоги вложенных неймспейсов не создают)
agents/*.md                       # 8 субагентов (frontmatter: name, description, tools, model-алиас тира)
hooks/hooks.json                  # проводка SessionStart/PreToolUse/Stop
sdx/protocol.md                   # протокол сессий
sdx/hooks/*.sh (+ lib/, test-*)   # скрипты enforcement-слоя и их тесты
sdx/templates/                    # шаблоны per-project слоя: prod-guard.conf, stage-gate.allow,
                                  #   verify-cmd.sh.template, claude-md-snippet.md
```

## Модель путей
Два корня, разведённые по ответственности:
- **`${CLAUDE_PLUGIN_ROOT}`** — файлы фреймворка. Подставляется рантаймом в markdown команд/агентов и в `hooks/hooks.json` (подтверждено эмпирически: для локального marketplace резолвится в исходный репозиторий, для удалённого — в кэш-копию `~/.claude/plugins/cache/...`). Использования: ссылки на `sdx/protocol.md`, вызовы `bash "${CLAUDE_PLUGIN_ROOT}/sdx/hooks/{archive-verify.sh, lib/default-branch.sh}"`, команды хуков в hooks.json (в кавычках — пути могут содержать пробелы).
- **`$CLAUDE_PROJECT_DIR`** — данные проекта. Hook-скрипты читают из него per-project конфиги (`.claude/sdx/*`) и состояние сессий (`.claude/sessions/<id>/`); соседние скрипты резолвят через `$(dirname BASH_SOURCE)`. Логика скриптов при плагинизации не менялась — только местоположение.

Ссылки на протокол в командах — текстовой инструкцией Read, а не `@`-инжектом: `@`-меншен не гарантирует подстановку `${...}`, а инлайн ~220 строк протокола в каждый вызов дорог.

## Решения и границы
- **CLAUDE.md не поставляется плагином** (рантайм его не автозагружает). Переносимый минимум правил (триада, языковая политика, роли) — в `sdx/templates/claude-md-snippet.md`; `/sdx:init` предлагает добавить блок `<!-- SDX:BEGIN/END -->` в CLAUDE.md проекта только с согласия пользователя.
- **Обновления**: правки фреймворка попадают в проекты через `/plugin marketplace update sdx` (для локального marketplace содержимое читается из исходного репо — команды/протокол подхватываются без переустановки; версия в `plugin.json` бампается при значимых изменениях).
- **Граница enforcement**: user-scope установка включает хуки во всех проектах; безопасность обеспечивают существующие свойства скриптов (no-op вне `sdx/*`-веток, opt-in конфиги) — REQ-PLUGIN-4.
- **Кэш-копия плагина** содержит и `docs/` репозитория (безвредный балласт: `.git`, `.claude/` в кэш не попадают).

## Верификация модели (fw-plugin-20260719)
- 54/54 юнит-тестов хуков зелёные после релокации.
- Headless-прогон в постороннем проекте: `/sdx:status` доступен, `${CLAUDE_PLUGIN_ROOT}` подставлен.
- Stage-gate из `hooks/hooks.json` плагина заблокировал запись в код на стадии Verification в мета-репозитории.
