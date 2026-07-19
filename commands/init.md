---
argument-hint: [--existing]
description: Инициализация SDX фреймворка в существующем проекте.
---

Ты выполняешь роль Session Manager в рамках SDX фреймворка. Твоя задача — инициализировать текущий проект для работы с SDX-плагином. Сам фреймворк (команды `/sdx:*`, субагенты, enforcement-хуки, протокол) поставляется плагином и в проект НЕ копируется — здесь разворачивается только **per-project** слой.

Аргументы: $ARGUMENTS

Инструкции:
1. Убедись, что создана структура папок:
   - `.claude/sessions/`
   - `.claude/sdx/` (per-project конфиги enforcement-слоя, см. шаг 2c)
   - `docs/specs/`
   - `docs/designs/`
   - `docs/history/plans/`
   - `docs/backlog/` (трекаемый бэклог проекта, ADR-015: файл-на-запись с YAML frontmatter + индекс `README.md`; создай индекс с пустыми таблицами по образцу из `${CLAUDE_PLUGIN_ROOT}/sdx/templates/backlog-readme.md`, если его ещё нет)
2. Убедись, что проект является git-репозиторием (иначе выполни `git init`). Сессии SDX работают в модели **«сессия = ветка `sdx/<id>` в основном рабочем дереве» + версионируемые артефакты** (ADR-012): каталог `.claude/sessions/` в норме НЕ игнорируется целиком — его содержательные файлы (`session_state.json`, `session.log`, `SPEC.md`/`DESIGN.md`/`PLAN.md` и т.д.) трекаются на ветке сессии `sdx/<id>`. Убедись, что корневой `.gitignore` содержит ТОЧЕЧНЫЕ (targeted) паттерны, а не широкий игнор каталога:
   ```gitignore
   # SDX: эфемерные scratch-файлы enforcement-слоя (loop-guard, буфер верификации).
   #      НЕ версионируются ни при каких условиях (REQ-SESS-2).
   .claude/sessions/*/.stopgate.*

   # SDX: переносимые бандлы import/export (транспортные артефакты).
   .sdx/bundles/

   # Локальные настройки Claude Code.
   .claude/settings.local.json
   ```
   Если в `.gitignore` присутствует широкий паттерн `.claude/sessions/` (старая модель) — удали его и замени на приведённые выше targeted-паттерны.
2a. Проверь зависимость enforcement-слоя: `jq` должен быть доступен (без него `prod-guard` уходит в fail-closed, а `stage-gate` — в fail-open). Если `jq` отсутствует — предупреди пользователя установить его.
2b. **Детект legacy-копии фреймворка.** Если в проекте обнаружены `.claude/commands/sdx/` или SDX-агенты в `.claude/agents/` (старая модель «копировать `.claude/` в каждый проект») — сообщи пользователю и предложи удалить их: команды и агенты теперь поставляет плагин, а локальные копии создадут дубли и разъедутся по версиям. Per-project файлы (`.claude/sdx/*.conf`, `*.allow`, `verify-cmd.sh`, `.claude/sessions/`) — НЕ трогай, они остаются.
2c. **Per-project конфиги enforcement-слоя.** Разложи шаблоны из плагина (только если файлов ещё нет — существующие НЕ перезаписывай):
   - `${CLAUDE_PLUGIN_ROOT}/sdx/templates/prod-guard.conf` → `.claude/sdx/prod-guard.conf`
   - `${CLAUDE_PLUGIN_ROOT}/sdx/templates/stage-gate.allow` → `.claude/sdx/stage-gate.allow`
   - `${CLAUDE_PLUGIN_ROOT}/sdx/templates/verify-cmd.sh.template` — если у проекта есть тест-команда, которую stop-gate не определит автодетектом (composer test / npm test / phpunit), создай из шаблона исполняемый `.claude/sdx/verify-cmd.sh`.
2d. **prod-guard для проектов с прод-средой:** спроси у пользователя, есть ли у проекта боевая (prod) среда.
   - Если **да** — заполни `.claude/sdx/prod-guard.conf` реальными паттернами (прод-хосты, флаги окружения, деплой-команды; по одному ERE на строку) и НЕ считай init завершённым, пока conf не заполнен. Помни: пустой conf = нет защиты, а `prod-guard` покрывает только инструмент `Bash`.
   - Если **нет** — явно зафиксируй в отчёте об инициализации `prod-guard: (n/a)` и оставь conf пустым (одни комментарии).
3. Если указан флаг `--existing`:
   - Вызови субагента `architect` (инструмент Task) для анализа текущего кода.
   - Сгенерируй базовые `SPEC.md` и `DESIGN.md` в `docs/`, описывающие текущее состояние.
4. **CLAUDE.md проекта.** Предложи пользователю добавить в CLAUDE.md проекта краткий SDX-блок (готовый текст: `${CLAUDE_PLUGIN_ROOT}/sdx/templates/claude-md-snippet.md`) — он несёт правило коллизий триады и языковую политику, действующие и вне команд `/sdx:*`. Добавляй ТОЛЬКО с явного согласия пользователя; существующее содержимое CLAUDE.md не изменяй и не удаляй.
5. Запиши отчет об инициализации в `docs/sdx-init-report.md`.

Протокол сессий: прочитай (Read) `${CLAUDE_PLUGIN_ROOT}/sdx/protocol.md`
