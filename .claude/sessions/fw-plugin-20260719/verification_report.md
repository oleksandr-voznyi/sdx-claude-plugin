# Verification Report: fw-plugin-20260719

## Сводка
- Трек: standard
- Итог: **PASS** (нет находок FAIL)
- Находки: FAIL: 0, WARN: 2, INFO: 1
- Артефакт-контракт: `change_note.md` (SPEC.md/DESIGN.md для standard-трека слиты в него).

## Матрица трассируемости
| Решение (change_note) | Реализация (файл) | Проверка | Когерентность | Статус |
|------------------------|-------------------|----------|----------------|--------|
| Бизнес: дистрибуция через плагин, репо = плагин+marketplace | `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, README, CLAUDE.md | jq-валид, `sdx@sdx` согласован | ok | OK |
| Бизнес: неймспейс команд сохранён (`/sdx:*`) | `commands/*.md` (плоская структура), plugin `name: sdx` | 13 команд на месте | ok | OK |
| Бизнес: per-project слой (docs/, sessions/, конфиги) | `commands/init.md`, README, CLAUDE.md §6 | пути консистентны | ok | OK |
| Тех.1: root-as-plugin (manifest/marketplace/commands/agents/hooks/sdx) | структура репо (см. ls) | все каталоги существуют | ok | OK |
| Тех.2: пути `${CLAUDE_PLUGIN_ROOT}/sdx/...`, замена `@`-инлайна на Read | 12 команд + 6 агентов + protocol.md | нет остаточных `.claude/sdx/protocol\|hooks` в контенте плагина | ok | OK |
| Тех.3: hook-скрипты по логике не меняются (project-файлы из `$CLAUDE_PROJECT_DIR`, соседи через `BASH_SOURCE`) | `sdx/hooks/*.sh` (100% rename) | 5 тест-сьютов зелёные (6/9/8/13/18) | ok | OK |
| Тех.4: `/sdx:init` переписан под плагин + legacy-детект | `commands/init.md` (new) | шаги 2b/2c/4 присутствуют | ok | OK |
| Тех.5: догфудинг — удаление `.claude/{commands,agents,sdx/…}`, очистка settings.json | diff + `.claude/` дерево | commands/agents отсутствуют, settings.json = только `_comment`, остались per-project `prod-guard.conf`/`stage-gate.allow` (0 активных строк) | ok | OK |
| Тех.6: CLAUDE.md вне плагина, сниппет для целей | `sdx/templates/claude-md-snippet.md`, init.md шаг 4 | файл существует, init предлагает | ok | OK |
| Тех.7: README (назначение/установка/структура/per-project) | `README.md` (new) | все разделы присутствуют | ok | OK |

## Ось: Полнота (completeness)
- OK: все 3 бизнес- и 7 технических решений прослежены в diff (см. матрицу).
- OK: обратная проверка на scope creep — каждый изменённый/новый файл прослеживается к решению из `change_note.md`. Незаявленных изменений не обнаружено. `.gitignore` в diff не трогался (change_note допускал «при необходимости»).
- OK: заявленные счётчики совпадают с деревом — 13 команд, 8 агентов, `sdx/templates/*` (4 шаблона), hook-скрипты + тесты перенесены полностью.

## Ось: Корректность (correctness)
- OK: JSON-манифесты валидны (jq): `plugin.json`, `marketplace.json`, `hooks/hooks.json`, `.claude/settings.json`.
- OK: идентичность имён — marketplace `name: sdx`, плагин `name: sdx`, `source: "./"` → install-строка `sdx@sdx` согласована в README/CLAUDE.md/settings.json.
- OK: `hooks/hooks.json` разводит SessionStart/PreToolUse(Write|Edit|MultiEdit + Bash)/Stop на `"${CLAUDE_PLUGIN_ROOT}"/sdx/hooks/{preflight,stage-gate,prod-guard,stop-gate}.sh`; пути и матчеры совпадают с прежней проводкой из удалённого `.claude/settings.json`; кавычки экранированы корректно (устойчивость к пробелам в пути).
- OK: hook-скрипты читают per-project файлы из `$CLAUDE_PROJECT_DIR/.claude/{sdx,sessions}/…` (prod-guard, stage-gate, stop-gate, archive-verify), а соседей — через `$(dirname "${BASH_SOURCE[0]}")` (archive-verify → `lib/default-branch.sh`). Логика не менялась — подтверждено фактическим прогоном 5 тест-сьютов: 54/54 passed после релокации.
- OK: нет битых ссылок — все `${CLAUDE_PLUGIN_ROOT}/sdx/...` цели существуют в дереве (`sdx/protocol.md`, `sdx/hooks/*`, `sdx/hooks/lib/default-branch.sh`, `sdx/templates/{prod-guard.conf,stage-gate.allow,verify-cmd.sh.template,claude-md-snippet.md}`).
- OK: остаточные `.claude/sdx/…` в контенте — это ссылки на **per-project** слой целевого проекта (README, init.md, protocol.md, CLAUDE.md §6), а не на перенесённые файлы плагина. Корректны.

## Ось: Когерентность (coherence)
- OK: триада описаний согласована — CLAUDE.md §6 (плагинная структура), README «Состав плагина», `sdx/protocol.md` (Enforcement-слой: скрипты плагином, проводка `hooks/hooks.json`, конфиги в `.claude/sdx/` цели) описывают одну и ту же модель распределения plugin ↔ per-project.
- OK: `.claude/settings.json` низведён до пояснительного `_comment`, указывающего на переезд проводки в плагин — не противоречит `hooks/hooks.json`.
- OK: догфудинг непротиворечив — мета-репо содержит только per-project слой (`.claude/{sdx,sessions}/`), команды/агенты/протокол удалены; enforcement в самом репо неактивен до установки плагина (зафиксировано в README и change_note).

### [WARN] [Корректность] Опора на подстановку `${CLAUDE_PLUGIN_ROOT}` в bash, исполняемом оркестратором
- Где: `commands/archive.md:37,41`, `commands/verify.md:22` (`def=$(bash "${CLAUDE_PLUGIN_ROOT}/sdx/hooks/lib/default-branch.sh")`)
- Суть: для hooks.json подстановка гарантирована рантаймом хуков. Но команды `archive`/`verify` эмитят bash-сниппеты, которые исполняет основная сессия. Если в конкретной версии Claude Code `${CLAUDE_PLUGIN_ROOT}` не подставляется в тело slash-команды до передачи в shell (а переменная не экспортирована в окружение оркестратора), путь схлопнется в `/sdx/hooks/...` и вызов упадёт.
- Ожидалось / Фактически: change_note (Риски) явно квитирует это допущение для агентов («деградация мягкая»), но для bash-вызовов в `archive`/`verify` мягкой деградации нет — это жёсткий вызов скрипта. Не проверяемо в этом окружении. Требуется квитирование пользователем (ручная проверка `/sdx:archive` п.6-7 и `/sdx:verify` шаг 4 на реальном инстансе плагина).

### [WARN] [Когерентность] Расхождение флага `--scope user` в install-строках
- Где: `README.md:12` (`/plugin install sdx@sdx` — флаг только в комментарии и в CLI-форме строкой ниже) против `CLAUDE.md:5` и `settings.json` (`/plugin install sdx@sdx --scope user`)
- Суть: слэш-форма в README не несёт `--scope user` в самой команде; user-scope (обслуживание всех проектов) — ключевое обещание фичи. Функционально покрыто комментарием, но нейминг/инструкция дрейфует между документами.
- Ожидалось / Фактически: единая install-инструкция во всех документах. Косметика, не блокирует.

### [INFO] [Корректность] plugin.json без явных полей путей commands/agents/hooks
- Где: `.claude-plugin/plugin.json`
- Суть: манифест полагается на конвенцию авто-дискавери каталогов `commands/`, `agents/`, `hooks/hooks.json` (они присутствуют в стандартных местах). Это штатно для плагинов Claude Code; отмечено как контрольная точка, не дефект.

## Вердикт
**PASS.** Поставка полно и когерентно реализует все решения `change_note.md`; корректность hook-слоя подтверждена фактическим прогоном тестов (54/54) после релокации, манифесты валидны и согласованы, битых ссылок нет. Две находки **WARN** требуют квитирования пользователем: (1) рантайм-подстановка `${CLAUDE_PLUGIN_ROOT}` в bash-вызовах команд `archive`/`verify` не верифицируема статически; (2) косметический дрейф флага `--scope user` в README. Ни одна находка не блокирует гейт.

## Резолюция WARN (эмпирическая проверка на живом инстансе, 2026-07-19)
- **WARN-1 (подстановка `${CLAUDE_PLUGIN_ROOT}` в теле команд)** — СНЯТ. Плагин установлен (`sdx@sdx`, scope user); headless-прогон `/sdx:status` в постороннем проекте показал подстановку literal-пути (`/home/archi/Code/sdx.cld/sdx/protocol.md` — для локального marketplace корень плагина указывает на исходный репозиторий). Хук-проводка также работает: stage-gate из hooks.json плагина заблокировал запись `smoke_probe.py` на стадии Verification с корректным deny-сообщением.
- **WARN-2 (README: scope в слэш-форме install)** — ИСПРАВЛЕН (уточнение про выбор scope user в диалоге).
