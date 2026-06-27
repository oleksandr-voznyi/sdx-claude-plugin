# Implementation Plan: SDX Enforcement & Routing — Фаза 1

## Статус реализации
100% — Все 19 задач Фазы 1 выполнены. Тесты E1–E4: 22/22 PASS.

---

## Чек-лист задач

### Блок A — Скрипты хуков

---

- [x] **[CODE] A1. Создать `stage-gate.sh` — PreToolUse-хук заморозки кода**

  **Файл:** `.claude/sdx/hooks/stage-gate.sh`

  **Что сделать:** Реализовать скрипт точно по псевдокоду из DESIGN.md §«stage-gate.sh».
  Ключевые контракты:
  - Читать stdin (`input="$(cat)"`), получать `tool_input.file_path` через `jq`.
  - Определять активную сессию через git-ветку (`sdx/<id>`); вне `sdx/*` → `exit 0`.
  - Читать `.stage` из `session_state.json`; стадии `Execution`/`Deployment` → `exit 0`.
  - Always-allow: `docs/*`, `.claude/*`, `*.md` → `exit 0`.
  - Опциональный `stage-gate.allow` (glob per line, `#`-комментарии).
  - Блокировка: JSON `permissionDecision:"deny"` на stdout + `exit 0` (НЕ `exit 2`).
  - `deny()` экранирует reason через `jq -Rs .`.
  - Отсутствие `session_state.json` или пустой `.stage` → `exit 0` (no-op).

  **Definition of Done:**
  - Файл создан; `bash -n .claude/sdx/hooks/stage-gate.sh` завершается без ошибок.
  - `shellcheck` (если доступен) не выдаёт ошибок уровня error.

---

- [x] **[CODE] A2. Создать `stop-gate.sh` — Stop-хук тест-пола**

  **Файл:** `.claude/sdx/hooks/stop-gate.sh`

  **Что сделать:** Реализовать скрипт по псевдокоду из DESIGN.md §«stop-gate.sh».
  Ключевые контракты:
  - Определять сессию через ветку; вне `sdx/*` → `exit 0`.
  - Применять только в стадиях `Execution`/`Verification` (или при `SDX_STOP_GATE=1`).
  - Loop-guard: файл `.stopgate.count` в папке сессии; после 3 красных → `exit 0` + очистка файла + сообщение в stderr.
  - Autodetect тест-команды: `verify-cmd.sh` (исполняемый), `composer.json`, `package.json`, `phpunit.xml`.
  - Нет команды → `exit 0` (no-op; обязательно для мета-проекта).
  - Красный прогон → хвост 20 строк в stderr + `exit 2`.
  - Зелёный → очистка `.stopgate.count` + `exit 0`.

  **Definition of Done:**
  - Файл создан; `bash -n .claude/sdx/hooks/stop-gate.sh` без ошибок.

---

- [x] **[CODE] A3. Создать `prod-guard.sh` — PreToolUse-хук Bash**

  **Файл:** `.claude/sdx/hooks/prod-guard.sh`

  **Что сделать:** Реализовать по псевдокоду из DESIGN.md §«prod-guard.sh».
  Ключевые контракты:
  - Читать stdin, получать `tool_input.command` через `jq`.
  - Нет команды → `exit 0`.
  - Нет `prod-guard.conf` → `exit 0` (opt-in, нет защиты).
  - Каждая строка конфига (кроме пустых и `#`-комментариев) — extended-regex паттерн.
  - Совпадение `grep -Eiq` → JSON `permissionDecision:"deny"` + `exit 0`.
  - Нет совпадений → `exit 0`.

  **Definition of Done:**
  - Файл создан; `bash -n .claude/sdx/hooks/prod-guard.sh` без ошибок.

---

- [x] **[CODE] A4. Создать `archive-verify.sh` — Closeout-скрипт инвариантов 1/5/6**

  **Файл:** `.claude/sdx/hooks/archive-verify.sh`

  **Что сделать:** Реализовать по псевдокоду из DESIGN.md §«archive-verify.sh».
  Ключевые контракты:
  - Принимать `$1` = `session_id`; при отсутствии — завершиться с ошибкой (`?`).
  - Инвариант 1: `git status --porcelain` непуст → `[FAIL]` в stderr, `fail=1`.
  - Инвариант 5: ветка `sdx/<id>` существует и НЕ слита в `main` → `[FAIL]`, `fail=1`.
  - Если `fail != 0` → `[ABORT]` в stderr + `exit 1` (необратимые действия НЕ выполняются).
  - Инвариант 6: `rm -rf "$sdir"`, проверить `[ -d "$sdir" ]`, удалить ветку (`git branch -d`).
  - При успехе: `[OK]`-сообщение на stdout.

  **Definition of Done:**
  - Файл создан; `bash -n .claude/sdx/hooks/archive-verify.sh` без ошибок.

---

- [x] **[INFRA] A5. Создать конфигурационные файлы-шаблоны (3 файла)**

  **Файлы:**
  - `.claude/sdx/prod-guard.conf` — пустой шаблон с комментариями-примерами паттернов.
  - `.claude/sdx/stage-gate.allow` — пустой шаблон с glob-примерами.
  - `.claude/sdx/verify-cmd.sh.template` — шаблон verify-команды, **без `chmod +x`** (не исполняемый).

  **Что сделать:** Создать файлы с содержимым точно по DESIGN.md §«prod-guard.conf»,
  §«stage-gate.allow», §«verify-cmd.sh.template». Убедиться, что `verify-cmd.sh.template`
  НЕ имеет бита исполнения — это намеренный no-op для мета-проекта (ADR-4).

  **Definition of Done:**
  - Все 3 файла существуют.
  - `[ -x .claude/sdx/verify-cmd.sh.template ] && echo FAIL || echo OK` → `OK`.
  - Файл `prod-guard.conf` не содержит активных (неза­комментированных) паттернов.

---

### Блок B — Проводка settings.json

---

- [x] **[INFRA] B1. Создать `.claude/settings.json` — project-level проводка хуков**

  **Файл:** `.claude/settings.json`

  **Что сделать:** Создать JSON-файл с проводкой трёх хуков точно по схеме из DESIGN.md
  §«Проводка `.claude/settings.json`»:
  - `PreToolUse` / matcher `Write|Edit|MultiEdit` → `stage-gate.sh`.
  - `PreToolUse` / matcher `Bash` → `prod-guard.sh`.
  - `Stop` → `stop-gate.sh`.
  - Пути через `$CLAUDE_PROJECT_DIR/.claude/sdx/hooks/<script>.sh`.
  - `SubagentStop` НЕ проводится (ADR-2).

  **Caveat (зафиксировать в файле как комментарий невозможно в JSON, но учесть в тесте):**
  Project-level `settings.json` считывается Claude Code при старте сессии. Для гарантированной
  активации хуков после создания файла может потребоваться перезапуск Claude Code CLI.

  **Definition of Done:**
  - Файл создан; `python3 -c "import json,sys; json.load(sys.stdin)" < .claude/settings.json`
    завершается без ошибок (валидный JSON).
  - Структура содержит оба `PreToolUse`-матчера и секцию `Stop`.

---

- [x] **[INFRA] B2. Установить права исполнения на хуки (`chmod +x`)**

  **Команда:** `chmod +x .claude/sdx/hooks/stage-gate.sh .claude/sdx/hooks/stop-gate.sh .claude/sdx/hooks/prod-guard.sh .claude/sdx/hooks/archive-verify.sh`

  **Что сделать:** Выполнить Bash-команду chmod. Prod-guard.conf в этот момент пустой (нет
  активных паттернов) → prod-guard не заблокирует операцию. Stage-gate: chmod — Bash, не
  Write/Edit, гейт не применяется.

  **Definition of Done:**
  - `ls -la .claude/sdx/hooks/*.sh` показывает бит `x` для всех 4 файлов.
  - `[ -x .claude/sdx/verify-cmd.sh.template ] && echo FAIL || echo OK` → `OK` (шаблон остался неисполняемым).

---

### Блок C — Model routing агентов

---

- [x] **[CODE] C1. `reviewer.md` — добавить `model: claude-opus-4-8` во frontmatter**

  **Файл:** `.claude/agents/reviewer.md`

  **Что сделать:** Вставить строку `model: claude-opus-4-8` в YAML frontmatter между
  существующими полями `tools:` и закрывающим `---`. Не трогать остальной текст файла.

  **Definition of Done:**
  - `grep "^model:" .claude/agents/reviewer.md` выводит `model: claude-opus-4-8`.
  - Число строк frontmatter увеличилось на 1; тело файла не изменилось.

---

- [x] **[CODE] C2. `tech-writer.md` — добавить `model: claude-haiku-4-5` во frontmatter**

  **Файл:** `.claude/agents/tech-writer.md`

  **Что сделать:** Аналогично C1. Вставить `model: claude-haiku-4-5`.

  **Definition of Done:**
  - `grep "^model:" .claude/agents/tech-writer.md` выводит `model: claude-haiku-4-5`.

---

- [x] **[CODE] C3. Оставшиеся 6 агентов — добавить `model: claude-sonnet-4-6` во frontmatter**

  **Файлы:** `.claude/agents/architect.md`, `.claude/agents/ba.md`,
  `.claude/agents/lead-dev.md`, `.claude/agents/developer.md`,
  `.claude/agents/qa.md`, `.claude/agents/devops.md`

  **Что сделать:** В каждом файле вставить строку `model: claude-sonnet-4-6` в YAML
  frontmatter. Все 6 файлов — идентичная операция.

  **Definition of Done:**
  - `grep -l "^model: claude-sonnet-4-6" .claude/agents/*.md | wc -l` → `6`.
  - Все 8 агентских файлов содержат поле `model`; `effort` не добавлен ни в один.

---

### Блок D — Текстовые дельты команд/протокола/CLAUDE.md

---

- [x] **[DOC] D1. `protocol.md` — добавить раздел «Enforcement-слой (хуки)»**

  **Файл:** `.claude/sdx/protocol.md`

  **Что сделать:** Вставить новый раздел `## Enforcement-слой (хуки)` после раздела
  «Гейты (Gates)» (или в конец, если такого раздела нет). Текст раздела — точно по
  DESIGN.md §«`.claude/sdx/protocol.md` — `[ADDED]` раздел». Включает описание всех
  4 хуков, механизм блокировки, скоуп, деградацию.

  **Definition of Done:**
  - `grep -c "Enforcement-слой" .claude/sdx/protocol.md` → `1`.
  - Раздел содержит подпункты: stage-gate, stop-gate, prod-guard, archive-verify.

---

- [x] **[DOC] D2. `archive.md` — добавить пункт 6 (вызов archive-verify.sh)**

  **Файл:** `.claude/commands/sdx/archive.md`

  **Что сделать:** После существующего пункта 5 (Слияние) добавить новый пункт 6 вызова
  `archive-verify.sh` и перенумеровать текущие пункты 6 и 7 в 7 и 8. Текст нового пункта
  — по DESIGN.md §«`.claude/commands/sdx/archive.md` — `[MODIFIED]`». Пункты прозы
  «чистое дерево / удаление файлов сессии», которые дублируют скрипт, пометить
  «enforced `archive-verify.sh`».

  **Definition of Done:**
  - `grep "archive-verify.sh" .claude/commands/sdx/archive.md` выводит строку с вызовом.
  - Чек-лист содержит пункт с `bash .claude/sdx/hooks/archive-verify.sh <session_id>`.

---

- [x] **[DOC] D3. `verify.md` — добавить примечание о stop-gate в шаг 2**

  **Файл:** `.claude/commands/sdx/verify.md`

  **Что сделать:** В описание шага 2 («Корректность исполнением») добавить примечание
  о stop-gate точно по DESIGN.md §«`.claude/commands/sdx/verify.md` — `[MODIFIED]`».
  Примечание объясняет: stop-gate обеспечивает детерминированный пол; `qa` отвечает за
  суждение поверх зелёного прогона; в мета-проекте stop-gate прозрачен (no-op).

  **Definition of Done:**
  - `grep -c "stop-gate" .claude/commands/sdx/verify.md` → `≥ 1`.

---

- [x] **[DOC] D4. `CLAUDE.md` — §2 model-note, §3 Closeout ссылка на archive-verify**

  **Файл:** `CLAUDE.md`

  **Что сделать:** Два точечных изменения по DESIGN.md §«`CLAUDE.md` — `[MODIFIED]`»:

  1. **§2 «Ролевая модель»** — добавить строку о модельной раскладке субагентов:
     `reviewer → Opus, tech-writer → Haiku, остальные → Sonnet`; `effort` не используется
     (не поддерживается в frontmatter).

  2. **§3, Closeout (этап 9)** — в описание чек-листа вместо прозы «удаление файлов
     сессии» добавить ссылку: «инварианты 1/5/6 enforced скриптом
     `.claude/sdx/hooks/archive-verify.sh` (вызывается `/sdx:archive` после мёржа)».

  **Definition of Done:**
  - `grep "archive-verify.sh" CLAUDE.md` → строка найдена.
  - `grep "claude-opus-4-8\|Opus" CLAUDE.md` → строка о модельной раскладке найдена.

---

### Блок E — Тесты enforcement-поведения

---

- [x] **[TEST] E1. Создать `test-stage-gate.sh` — unit-тест stage-gate**

  **Файл:** `.claude/sdx/hooks/test-stage-gate.sh`

  **Сценарии (из критериев приёмки REQ-GATE-1):**

  1. **Блокировка вне Execution:** подготовить temp git-репо с веткой `sdx/test-sg`,
     `session_state.json` с `"stage": "Task Planning"`. Вызвать `stage-gate.sh` с stdin
     `{"tool_input":{"file_path":"<proj>/src/app.js"}}`. Ожидать: stdout содержит
     `"permissionDecision":"deny"`; exit 0.

  2. **Пропуск .md-файла вне Execution:** тот же контекст, путь `docs/PLAN.md`.
     Ожидать: stdout пуст; exit 0.

  3. **Пропуск .claude/-файла вне Execution:** путь `.claude/settings.json`.
     Ожидать: stdout пуст; exit 0.

  4. **Прозрачность вне SDX-ветки:** та же структура, но ветка `main`.
     Ожидать: stdout пуст; exit 0.

  5. **Разрешение на стадии Execution:** ветка `sdx/test-sg`, `"stage":"Execution"`,
     путь `src/app.js`. Ожидать: stdout пуст; exit 0.

  6. **stage-gate.allow расширяет пропуск:** добавить `database/migrations/*` в allow-файл.
     Путь `database/migrations/001.sql`, стадия `Task Planning`. Ожидать: stdout пуст; exit 0.

  **Definition of Done:**
  - `bash .claude/sdx/hooks/test-stage-gate.sh` завершается exit 0 и печатает `PASS` по
    каждому сценарию (или суммарное `ALL PASSED`).

---

- [x] **[TEST] E2. Создать `test-stop-gate.sh` — unit-тест stop-gate**

  **Файл:** `.claude/sdx/hooks/test-stop-gate.sh`

  **Сценарии (из критериев приёмки REQ-GATE-2):**

  1. **No-op без тест-команды (мета-проект):** temp git-репо, ветка `sdx/test-stop`,
     `session_state.json` с `"stage":"Execution"`. Нет `verify-cmd.sh`, нет `composer.json`,
     `package.json`, `phpunit.xml`. Вызвать `stop-gate.sh`. Ожидать: exit 0.

  2. **Прозрачность вне Execution/Verification:** stage `Task Planning`. Ожидать: exit 0.

  3. **Прозрачность вне SDX-ветки:** ветка `main`. Ожидать: exit 0.

  4. **Loop-guard на 3 красных:** Подготовить `verify-cmd.sh` (исполняемый), всегда
     возвращающий exit 1. Запустить stop-gate трижды — первые 3 раза exit 2. Запустить
     четвёртый раз — ожидать exit 0 (loop-guard сработал, сообщение в stderr).

  **Definition of Done:**
  - `bash .claude/sdx/hooks/test-stop-gate.sh` → exit 0, все сценарии пройдены.

---

- [x] **[TEST] E3. Создать `test-prod-guard.sh` — unit-тест prod-guard**

  **Файл:** `.claude/sdx/hooks/test-prod-guard.sh`

  **Сценарии (из критериев приёмки REQ-PROD-1):**

  1. **Нет `prod-guard.conf` → exit 0 (no-op):** `CLAUDE_PROJECT_DIR` указывает на
     temp-каталог без файла. Команда `deploy production`. Ожидать: stdout пуст; exit 0.

  2. **Пустой `prod-guard.conf` → exit 0 (opt-in нет защиты):** файл создан, только
     комментарии. Команда `deploy production`. Ожидать: stdout пуст; exit 0.

  3. **Совпадение с паттерном → блокировка:** конф содержит `deploy.*(prod|production)`.
     Команда `deploy.sh production`. Ожидать: stdout содержит `"permissionDecision":"deny"`;
     exit 0.

  4. **Несовпадение с паттерном → exit 0:** та же конфигурация, команда `ls -la`.
     Ожидать: stdout пуст; exit 0.

  **Definition of Done:**
  - `bash .claude/sdx/hooks/test-prod-guard.sh` → exit 0, все сценарии пройдены.

---

- [x] **[TEST] E4. Создать `test-archive-verify.sh` — unit-тест archive-verify**

  **Файл:** `.claude/sdx/hooks/test-archive-verify.sh`

  **Сценарии (из критериев приёмки REQ-CLOSEOUT-1):**

  1. **Abort при грязном дереве:** создать temp git-репо, добавить незакоммиченный файл.
     Вызвать `archive-verify.sh test-sid`. Ожидать: stderr содержит `[FAIL]`; exit 1;
     каталог сессии НЕ удалён.

  2. **Abort при неслитой ветке:** чистое дерево, создать ветку `sdx/test-sid`, не
     сливать в main. Ожидать: stderr содержит `[FAIL]`; exit 1; каталог НЕ удалён.

  3. **Успех при выполненных инвариантах:** чистое дерево, ветка `sdx/test-sid` слита в
     main (или не существует). Ожидать: stdout содержит `[OK]`; exit 0; каталог сессии
     удалён (`[ ! -d .claude/sessions/test-sid ]`); ветка `sdx/test-sid` удалена.

  **Definition of Done:**
  - `bash .claude/sdx/hooks/test-archive-verify.sh` → exit 0, все сценарии пройдены.

---

- [x] **[TEST] E5. Создать `MANUAL_TEST.md` — интеграционные сценарии с Claude Code**

  **Файл:** `.claude/sessions/fw-enforce-route-20260627/MANUAL_TEST.md`

  **Что сделать:** Задокументировать сценарии, требующие живого Claude Code (не покрытые
  bash-тестами), в формате пошаговой инструкции:

  1. **stage-gate `blockingError` в Claude Code:**
     - Активировать сессию на ветке `sdx/<id>`, stage = `Task Planning`.
     - Попросить Claude записать файл `src/test.js` (любой текст).
     - Ожидаемый результат: Claude получает `blockingError` с reason
       «SDX stage-gate: запись в код заблокирована...»; ход не прерывается.
     - Попросить Claude записать `docs/notes.md` — должна пройти без ошибок.

  2. **stop-gate удержание хода при красном прогоне (проект с тест-сьютом):**
     - Только для проекта-потребителя с настроенным `verify-cmd.sh`.
     - Настроить `verify-cmd.sh` на возврат exit 1. Запустить ход агента в стадии Verification.
     - Ожидаемый результат: ход не завершается; агент видит stderr с хвостом теста.
     - Исправить тесты (exit 0); повторить — ход завершается штатно.

  3. **Перезапуск Claude Code CLI после активации `settings.json`:**
     - Создать `settings.json` (задача B1).
     - Подтвердить активацию хуков: перезапустить Claude Code CLI; повторить сценарий 1.

  **Definition of Done:**
  - Файл создан в папке сессии.
  - Каждый сценарий содержит: предусловие, шаги, ожидаемый результат.

---

## Зависимости между задачами

```
A1 ─┐
A2 ─┤
A3 ─┼─→ B2 (chmod +x требует наличия файлов)
A4 ─┤
A5 ─┘

B1 (settings.json) → [рестарт CLI для активации] → E5 (интеграционные тесты)

A1 → E1 (тест stage-gate требует скрипта)
A2 → E2 (тест stop-gate требует скрипта)
A3 → E3 (тест prod-guard требует скрипта)
A4 → E4 (тест archive-verify требует скрипта)

C1, C2, C3 — независимы от блоков A, B (все пути под .claude/**)
D1, D2, D3, D4 — независимы от A, B, C (*.md или .claude/**)

B1 → B2 (chmod логичен после появления скриптов и settings.json)
```

**Критический путь:** A1→A4 + A5 → B1 → B2 → E1→E5 (тесты)

**Нет самоблокировки (ADR-5):** Все артефакты Фазы 1 лежат под `.claude/**` или являются
`*.md`. Stage-gate always-allow: `case "$rel" in docs/*|.claude/*|*.md) exit 0`. Значит,
даже при уже активном settings.json все задачи блоков A→D проходят без блокировки.
Настоящая сессия находится в стадии Execution — gate и так открыт. Двойная гарантия.

---

## Порядок исполнения

1. **A1** — `stage-gate.sh`
2. **A2** — `stop-gate.sh`
3. **A3** — `prod-guard.sh`
4. **A4** — `archive-verify.sh`
5. **A5** — конфигурационные шаблоны (3 файла)
6. **B1** — `settings.json` (с этого момента хуки подключены в конфигурации)
7. **B2** — `chmod +x` (с этого момента хуки физически исполняемы)
8. **C1** — `reviewer.md` → `model: claude-opus-4-8`
9. **C2** — `tech-writer.md` → `model: claude-haiku-4-5`
10. **C3** — 6 агентов → `model: claude-sonnet-4-6`
11. **D1** — `protocol.md` (раздел Enforcement-слой)
12. **D2** — `archive.md` (пункт 6 + перенумерация)
13. **D3** — `verify.md` (примечание о stop-gate)
14. **D4** — `CLAUDE.md` (§2 model-note, §3 Closeout)
15. **E1** — `test-stage-gate.sh` + прогон
16. **E2** — `test-stop-gate.sh` + прогон
17. **E3** — `test-prod-guard.sh` + прогон
18. **E4** — `test-archive-verify.sh` + прогон
19. **E5** — `MANUAL_TEST.md`

**Примечание к шагу 6/7:** После создания `settings.json` и chmod для гарантированной
активации хуков в текущей сессии Claude Code может потребоваться перезапуск CLI.
Bash-тесты (E1–E4) не требуют активного Claude Code — они тестируют логику скриптов
напрямую через `bash`. Интеграционный тест (E5) выполняется вручную после рестарта.

---

## Гейт перед Execution

Пользователь подтверждает следующее до начала реализации:

1. **Порядок установки принят:** скрипты → settings.json → chmod → агенты/доки → тесты.
2. **Рестарт CLI понятен:** после создания `settings.json` (шаг 6) потребуется перезапуск
   сессии Claude Code для активации хуков; это ожидаемое поведение.
3. **Мета-проект: stop-gate no-op:** `prod-guard.conf` остаётся пустым шаблоном,
   `verify-cmd.sh` не создаётся — stop-gate прозрачен. Принято.
4. **`effort` не добавляется:** поле не поддерживается во frontmatter субагентов (ADR-3).
5. **19 задач в плане:** [CODE]: 7, [INFRA]: 3, [DOC]: 4, [TEST]: 5.
