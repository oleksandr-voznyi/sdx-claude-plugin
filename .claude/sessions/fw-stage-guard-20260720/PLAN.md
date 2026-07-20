# Implementation Plan: Детерминированный владелец поля `stage` (DEBT-001 + DEBT-011)

> Вход: `DESIGN.md` (856 строк, этот же каталог сессии), `SPEC.md` (критерии приёмки,
> REQ-*). Развилки, подтверждённые на гейте Technical Design (зафиксированы как жёсткие
> ограничения этого плана, не предмет пересмотра Execution):
> 1. `init`-подкоманда `sdx-stage.sh` — единственный писатель первичного `session_state.json`
>    для `/sdx:start`/`/sdx:import` (не `Write`).
> 2. Рефакторинг `stage-gate.sh`/`stop-gate.sh` на `lib/resolve-session.sh` — **обязателен**
>    в этой сессии (в DESIGN был помечен «рекомендовано, не блокирует» — здесь блокирует).
> 3. Маркировка outdated при `backtrack` — HTML-баннер первой строкой файла (как в DESIGN).
> 4. Версия плагина `1.2.2` → `1.3.0`.

## Статус реализации
0% — план не начат.

---

## Замечание по самоприменению (важно для порядка исполнения)

Эта сессия сама подпадёт под новый deny-хук `stage-write-guard.sh` — но **не сразу** после
того, как он попадёт в `hooks/hooks.json` на ветке `sdx/fw-stage-guard-20260720`. Рантайм
Claude Code исполняет хуки из **установленной (кэшированной) копии плагина**
(`~/.claude/plugins/cache/sdx/sdx/<version>/…`), а не из рабочего дерева репозитория —
активация требует явного `/plugin marketplace update sdx` (см. T-29), возможно с рестартом
CLI. Это отличается от исходной формулировки риска 3 в `DESIGN.md` («попадёт под деном сразу
после Execution, как только хук окажется подключён через `hooks.json`») — уточнение
согласовано с пользователем на Task Planning и отражено ниже: команды `/sdx:*` (T-20–T-25)
переписываются на `sdx-stage.sh` **до** активации плагина (T-28–T-29), поэтому к моменту,
когда деном реально станет активен (для этой или любой другой открытой сессии), легитимный
путь уже существует и не требует обхода. До T-29 текущая сессия продолжает переходить между
этапами прежним прозаическим `Edit`-путём — это безопасно и ожидаемо, не баг.

---

## Чек-лист задач

### Блок A — Общая библиотека `lib/resolve-session.sh` (обязательный рефакторинг, решение #2)

---

- [ ] **[CODE] T-01. Создать `sdx/hooks/lib/resolve-session.sh`**

  **Файл:** `sdx/hooks/lib/resolve-session.sh`

  **Что сделать:** Реализовать точно по псевдокоду DESIGN.md §«Общая библиотека
  `sdx/hooks/lib/resolve-session.sh`»: функция `resolve_sid <proj>`, читает
  `git -C "$proj" branch --show-current`, при ветке `sdx/*` печатает `sid` на stdout, иначе
  пустую строку. Файл **sourceable**, не самостоятельный CLI (в отличие от
  `lib/default-branch.sh`, который исполняется как подпроцесс) — не должен содержать
  побочных эффектов при `source`, не должен исполнять код на верхнем уровне кроме
  определения функции.

  **Definition of Done:**
  - `bash -n sdx/hooks/lib/resolve-session.sh` без ошибок.
  - `bash -c '. sdx/hooks/lib/resolve-session.sh; type resolve_sid'` подтверждает, что
    `resolve_sid` определена как функция (побочных эффектов от `source` нет).

  **REQ:** инфраструктурная задача, не привязана к конкретному REQ; закрывает дублирование,
  отмеченное Discovery в `stage-gate.sh`/`stop-gate.sh`, используется T-16 (write-guard).

---

- [ ] **[TEST] T-02. Создать `sdx/hooks/test-resolve-session.sh`**

  **Файл:** `sdx/hooks/test-resolve-session.sh`

  **Что сделать:** По стилю `test-default-branch.sh` (temp git-репо, `setup`/`cleanup`,
  `pass`/`fail`), но с адаптацией под sourceable-библиотеку — вызывать так:
  `bash -c '. "$1"/lib/resolve-session.sh; resolve_sid "$2"' _ "$SCRIPT_DIR" "$TMPPROJ"`.
  Сценарии:
  1. Ветка `sdx/test-abc` → `resolve_sid` печатает `test-abc`.
  2. Ветка `main` → `resolve_sid` печатает пустую строку.
  3. Ветка `sdx/` (без суффикса, граничный случай) → печатает пустую строку (проверить, что
     `${branch#sdx/}` не производит мусор из пустого id — если поведение неоднозначно,
     задокументировать как принятое, не баг).

  **Definition of Done:**
  - `bash sdx/hooks/test-resolve-session.sh` → `exit 0`, `ALL PASSED`.

  **REQ:** покрывает T-01.

---

- [ ] **[CODE] T-03. Рефакторинг `stage-gate.sh` на `lib/resolve-session.sh`**

  **Файл:** `sdx/hooks/stage-gate.sh`

  **Что сделать:** Заменить inline-блок (строки 27–32 текущего файла: `branch="$(git -C
  "$proj" branch --show-current ...)"; case "$branch" in sdx/*) sid=... ;; *) exit 0 ;; esac`)
  на `. "$here/lib/resolve-session.sh"; sid="$(resolve_sid "$proj")"; [ -z "$sid" ] && exit 0`
  (добавить `here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` в начало скрипта, если
  его ещё нет). Поведение не меняется — только источник резолюции `sid`. Остальной скрипт
  (allow-list, стадии, Windows-нормализация) не трогать.

  **Definition of Done:**
  - `bash -n sdx/hooks/stage-gate.sh` без ошибок.
  - `bash sdx/hooks/test-stage-gate.sh` → `exit 0`, все 10 существующих сценариев PASS
    без изменения самого теста (регресс-критерий неломки).

  **REQ:** не привязано к конкретному REQ (поведение-сохраняющий рефакторинг), обязательно
  по решению пользователя #2.

---

- [ ] **[CODE] T-04. Рефакторинг `stop-gate.sh` на `lib/resolve-session.sh`**

  **Файл:** `sdx/hooks/stop-gate.sh`

  **Что сделать:** Аналогично T-03 — заменить inline-блок (строки 9–13 текущего файла) на
  вызов `resolve_sid`. Поведение (loop-guard, green-run cache, autodetect команды) не
  меняется.

  **Definition of Done:**
  - `bash -n sdx/hooks/stop-gate.sh` без ошибок.
  - `bash sdx/hooks/test-stop-gate.sh` → `exit 0`, все существующие сценарии PASS без
    изменения теста.

  **REQ:** не привязано к конкретному REQ, обязательно по решению пользователя #2.

---

### Блок B — `sdx/hooks/sdx-stage.sh` (единственный писатель `stage`)

> Все задачи блока B редактируют один и тот же файл — **строго последовательны**, не
> параллелизуемы между собой. Могут выполняться параллельно с Блоком A (разные файлы).
> **Примечание по DESIGN:** §«Обработка ошибок» явно фиксирует, что `sdx-stage.sh`
> принимает `sid` явным аргументом и **не резолвит ветку вообще** (симметрично
> `archive-verify.sh`) — фраза в §«Общая библиотека» о том, что резолвер «используется
> обоими новыми скриптами», трактуется в пользу более специфичного §«Обработка ошибок»:
> `sdx-stage.sh` **не использует** `lib/resolve-session.sh` (ему нечего резолвить — `sid`
> дан вызывающей стороной). Если Execution сочтёт иначе — зафиксировать явно и обновить
> этот план перед стартом Блока B.

---

- [ ] **[CODE] T-05. `sdx-stage.sh` — скелет: матрица, `write_stage()`, jq-guard, диспетчер**

  **Файл:** `sdx/hooks/sdx-stage.sh` (новый)

  **Что сделать:** По DESIGN.md §«Механика записи `stage` (атомарность)» и §«Матрица
  "трек → этапы → гейт-артефакты"»:
  - Шебанг, `set -uo pipefail`.
  - Проверка `command -v jq` в самом начале, до разбора подкоманды — при отсутствии:
    `exit 2` с сообщением на русском (текст из DESIGN §«Поведение без jq»).
  - Heredoc `SDX_STAGE_MATRIX` — **дословно** как в DESIGN (17 строк данных).
  - Вспомогательные функции чтения матрицы: список активных этапов трека в порядке строк,
    артефакт+`fail_marker` по (`track`,`stage`), индекс этапа в порядке трека.
  - `write_stage()` — точно по DESIGN.md §«Механика записи»: `mktemp "${state}.XXXXXX"` в
    той же директории, `jq --arg s "$new" '.stage = $s'` во временный файл, `mv` — атомарная
    замена; отказ на любом шаге → `exit 2`, `rm -f` временного файла, оригинал не тронут.
  - Диспетчер `case "$1" in init|next|backtrack|retrack) ...; *) exit 2 с usage;; esac` —
    подкоманды на этом шаге могут быть заглушками (`echo "not implemented" >&2; exit 2`),
    реализуются в T-07/T-09/T-11/T-13.
  - **Не** подключать `lib/resolve-session.sh` (см. примечание к блоку выше).

  **Definition of Done:**
  - `bash -n sdx/hooks/sdx-stage.sh` без ошибок.
  - Скрипт **не** зарегистрирован ни в `hooks/hooks.json`, ни в `commands/*.md` на этом шаге
    (не ломает ничего, даже будучи неполным).

  **REQ:** REQ-STAGE-1, REQ-STAGE-3.

---

- [ ] **[TEST] T-06. `test-sdx-stage.sh` — каркас + sanity-сверка матрицы с `protocol.md`**

  **Файл:** `sdx/hooks/test-sdx-stage.sh` (новый)

  **Что сделать:** Каркас по стилю `test-stage-gate.sh` (`pass`/`fail`, `mktemp -d`,
  `setup_sdx_repo`), плюс хелпер `run_stage <args...>` (`CLAUDE_PROJECT_DIR="$TMPPROJ" bash
  "$SCRIPT" <args...>`, не stdin JSON — обычный CLI). Реализовать сценарий 19 из DESIGN
  тест-плана: извлечь из `sdx/protocol.md` (уже существующая таблица, строки ~51–55) имена
  этапов трека `full` из ячейки `Discovery → ... → Closeout` (`grep`+`sed` разбор `→`-цепочки),
  сравнить как множество с этапами `full` из `SDX_STAGE_MATRIX` скрипта. **Не зависит** от
  T-26 (сноска в `protocol.md` появится позже, но сама таблица уже существует сейчас).

  **Definition of Done:**
  - `bash sdx/hooks/test-sdx-stage.sh` → `exit 0`; сценарий 19 (единственный на этом шаге) —
    `PASS`.

  **REQ:** REQ-STAGE-3 (риск 2 — компромисс sanity-проверки, не гарантия).

---

- [ ] **[CODE] T-07. `sdx-stage.sh init` — первичная установка**

  **Файл:** `sdx/hooks/sdx-stage.sh`

  **Что сделать:** По DESIGN.md §«`init` — первичная установка». Контракт:
  `sdx-stage.sh init <sid> <type> <track> <stage> <gate_mode> <git_branch>`.
  - Требует отсутствия `session_state.json` — если файл уже есть, `exit 2` (защита от
    повторной инициализации).
  - Валидирует, что `<stage>` — первый активный этап `<track>` в матрице (иначе `exit 2`).
  - Создаёт `.claude/sessions/<sid>/session_state.json` целиком (`session_id`, `type`,
    `track`, `stage`, `gate_mode`, `git_branch`, `artifacts: []`, `history: []`) —
    схема **не меняется** (REQ-COMPAT-1), новых полей не добавлять.
  - Атомарно (в том же ходе) дописывает `[START] Инициализация сессии <sid> (трек: <track>)`
    в `session.log` (создаёт файл, если его ещё нет).
  - Успех: `stdout` — `OK - -> <stage>`, `exit 0`.

  **Definition of Done:**
  - `bash -n sdx/hooks/sdx-stage.sh` без ошибок.
  - Ручная проверка (или прогон T-08 сразу после) подтверждает создание файла и лог-строки.

  **REQ:** REQ-STAGE-1, REQ-COMPAT-1.

---

- [ ] **[TEST] T-08. `test-sdx-stage.sh` — сценарии 1–2 (`init`)**

  **Файл:** `sdx/hooks/test-sdx-stage.sh`

  **Что сделать:** Добавить сценарии из DESIGN тест-плана:
  1. `init` на пустом каталоге сессии создаёт `session_state.json` + строку `[START]` в
     `session.log`, `exit 0`, stdout содержит `OK - ->`.
  2. Повторный `init` на уже существующий файл → `exit 2`, файл байт-в-байт не изменён
     (сравнить контрольную сумму/содержимое до и после).

  **Definition of Done:**
  - `bash sdx/hooks/test-sdx-stage.sh` → `exit 0`, сценарии 1–2 `PASS` (плюс ранее
    добавленный сценарий 19).

  **REQ:** покрывает T-07.

---

- [ ] **[CODE] T-09. `sdx-stage.sh next` — forward-переход**

  **Файл:** `sdx/hooks/sdx-stage.sh`

  **Что сделать:** По DESIGN.md §«`next` — forward-переход». Контракт: `sdx-stage.sh next
  <sid>`. Без явной цели — скрипт сам вычисляет следующий активный этап трека из матрицы.
  - Гейт **уходящего** (текущего) этапа: артефакт из матрицы для (`track`,`stage`) должен
    существовать и быть непустым; если `fail_marker=yes` — дополнительно отсутствие
    `^### \[FAIL\]` в артефакте (формат `reviewer`). `artifact="-"` → гейт пройден
    автоматически (объективно непроверяем, см. DESIGN «Матрица»).
  - Гейт не пройден → `exit 1`, stderr называет (а) чего не хватает, (б) какой командой
    исправить — по образцу примеров DESIGN §«stdout/stderr».
  - Текущий этап — последний активный в треке → следующий шаг — `Closeout`; если текущий
    этап уже `Closeout` (терминальный) → `exit 0` no-op (файл не трогается).
  - Успех: `write_stage()` + атомарная запись `[STAGE_CHANGE]` в `session.log`; stdout
    `OK <old> -> <new>`.

  **Definition of Done:**
  - `bash -n sdx/hooks/sdx-stage.sh` без ошибок.

  **REQ:** REQ-STAGE-2, REQ-STAGE-4 (терминальный no-op), REQ-STAGE-5,
  REQ-CLOSEOUT-ENTRY-1 (Closeout — обычная последняя строка матрицы, без спецкода).

---

- [ ] **[TEST] T-10. `test-sdx-stage.sh` — сценарии 3–7 (`next`)**

  **Файл:** `sdx/hooks/test-sdx-stage.sh`

  **Что сделать:** Добавить сценарии:
  3. Гейт пройден (`context_report.md` существует/непуст, `track=full`,
     `stage=Discovery`) → `stage → Business Spec`, `[STAGE_CHANGE]` в логе.
  4. Гейт НЕ пройден (артефакт отсутствует) → `exit 1`, `stage` не меняется, stderr
     называет артефакт+команду.
  5. `verification_report.md` существует, но содержит `### [FAIL]` → `exit 1` (маркер),
     сообщение отсылает к `/sdx:backtrack --to Execution`.
  6. Переход `Verification → Closeout` на треке `patch` — тот же гейт-путь, что
     `Verification → Deployment` на `full` (подтверждает унификацию, без ветвления по
     треку в коде).
  7. Текущий этап — терминальный `Closeout` → `exit 0` no-op.

  **Definition of Done:**
  - `bash sdx/hooks/test-sdx-stage.sh` → `exit 0`, сценарии 1–7, 19 `PASS`.

  **REQ:** покрывает T-09.

---

- [ ] **[CODE] T-11. `sdx-stage.sh backtrack` + `mark_outdated()`**

  **Файл:** `sdx/hooks/sdx-stage.sh`

  **Что сделать:** По DESIGN.md §«Backward-переход» — правила (исполнимая форма REQ-BACKTRACK-1)
  и механика `mark_outdated()` (HTML-баннер, решение #3):
  - Контракт: `sdx-stage.sh backtrack <sid> <target>`.
  - `target` не входит ни в один трек матрицы → `exit 1`, «имя не распознано».
  - `target` не активен в ТЕКУЩЕМ треке → `exit 1`, «нужна смена трека — /sdx:retrack».
  - `target == current` → `exit 0` no-op (файл не трогается, включая `mtime`).
  - `index(target) > index(current)` в порядке трека → `exit 1`, «не откат — используй
    /sdx:next».
  - Иначе: без проверки гейт-артефактов уходящего этапа — `write_stage(target)` +
    `[STAGE_CHANGE]` в лог.
  - `mark_outdated()` — HTML-комментарий-баннер **первой строкой** файла (текст точно по
    DESIGN, включая идемпотентность через `grep -q '<!-- SDX-OUTDATED'` в первых 200
    байтах). Скоуп: артефакты этапов **строго после** `target` (эксклюзивно) до текущего
    этапа включительно; артефакт самого `target`-этапа НЕ метится. Для каждого помеченного
    файла — строка `OUTDATED: <path>` на stdout.

  **Definition of Done:**
  - `bash -n sdx/hooks/sdx-stage.sh` без ошибок.

  **REQ:** REQ-BACKTRACK-1, REQ-BACKTRACK-2, REQ-STAGE-4 (no-op/невалидное имя).

---

- [ ] **[TEST] T-12. `test-sdx-stage.sh` — сценарии 8–14 (`backtrack`)**

  **Файл:** `sdx/hooks/test-sdx-stage.sh`

  **Что сделать:** Добавить сценарии:
  8. Цель активна и не позже текущей → `stage` меняется без проверки гейт-артефактов
     уходящего этапа (артефакт-гейт у фикстуры намеренно отсутствует).
  9. Цель = текущий этап → `exit 0` no-op, файл не тронут (`mtime`/содержимое неизменны).
  10. Цель не активна в треке → `exit 1`, «нужна смена трека — /sdx:retrack».
  11. Цель позже текущего этапа → `exit 1`, «не откат — используй /sdx:next».
  12. Нераспознанное имя этапа (опечатка) → `exit 1`, «имя не распознано».
  13. Маркировка outdated: откат `full` с `Task Planning` на `Technical Design` →
      `PLAN.md` (строго после target) получает баннер первой строкой; `DESIGN.md`
      (артефакт самого target) баннер НЕ получает; вывод содержит `OUTDATED: .../PLAN.md`.
  14. Повторная маркировка того же файла (второй `backtrack` на ту же/более раннюю цель)
      не дублирует баннер.

  **Definition of Done:**
  - `bash sdx/hooks/test-sdx-stage.sh` → `exit 0`, сценарии 1–14, 19 `PASS`.

  **REQ:** покрывает T-11.

---

- [ ] **[CODE] T-13. `sdx-stage.sh retrack` — пересчёт под новый трек**

  **Файл:** `sdx/hooks/sdx-stage.sh`

  **Что сделать:** По DESIGN.md §«`retrack` — пересчёт под новый трек» и §«Развилка: кто
  вычисляет цель retrack». Контракт: `sdx-stage.sh retrack <sid> <target>`. Вызывается
  **после** того, как `retrack.md` уже поправил `track` напрямую через `Edit` — подкоманда
  читает уже обновлённый `track` и неизменённый `stage`. Проверяет только «`target` активен
  в (новом) `track`»: не активен → `exit 1`. Активен → `write_stage(target)` +
  `[STAGE_CHANGE]`, **без** forward-гейта уходящего этапа (это не продвижение вперёд).

  **Definition of Done:**
  - `bash -n sdx/hooks/sdx-stage.sh` без ошибок.

  **REQ:** REQ-RETRACK-1.

---

- [ ] **[TEST] T-14. `test-sdx-stage.sh` — сценарии 15–16 (`retrack`)**

  **Файл:** `sdx/hooks/test-sdx-stage.sh`

  **Что сделать:** Добавить сценарии:
  15. `track` уже обновлён на `standard`; `target=Change` активен в `standard` → `stage`
      меняется без проверки forward-гейта (артефакт `change_note.md` намеренно отсутствует
      у фикстуры — переход всё равно успешен).
  16. `target` не активен в (уже обновлённом) новом треке → `exit 1`.

  **Definition of Done:**
  - `bash sdx/hooks/test-sdx-stage.sh` → `exit 0`, сценарии 1–16, 19 `PASS`.

  **REQ:** покрывает T-13.

---

- [ ] **[TEST] T-15. `test-sdx-stage.sh` — сценарии 17–18 (отсутствие `jq`, атомарность)**

  **Файл:** `sdx/hooks/test-sdx-stage.sh`

  **Что сделать:** Сквозные (cross-cutting) сценарии, применимые ко всем подкомандам —
  добавляются после того, как все 4 подкоманды (T-07/09/11/13) реализованы:
  17. Без `jq` в `$PATH` (переопределить `PATH` на каталог без `jq`, либо подставной
      `command -v`) — любая мутирующая подкоманда → `exit 2`, файл гарантированно не
      изменён (контрольная сумма до/после совпадает).
  18. Атомарность `write_stage`: искусственно сломать `mktemp`/`jq` (например, `PATH` без
      `jq`, что покрыто сценарием 17, либо неписуемый каталог сессии) → оригинал
      `session_state.json` остаётся валидным JSON с прежним `stage`; никаких временных
      файлов (`*.XXXXXX`-остатков) не остаётся в каталоге сессии после прогона.

  **Definition of Done:**
  - `bash sdx/hooks/test-sdx-stage.sh` → `exit 0`, все 19 сценариев `PASS` (полный тест-план
    DESIGN.md §«Тест-план» → `test-sdx-stage.sh» закрыт).

  **REQ:** REQ-STAGE-5 (jq fail-closed), инженерное требование атомарности из DESIGN
  §«Механика записи `stage`».

---

### Блок C — `sdx/hooks/stage-write-guard.sh` (deny-хук)

> Задачи блока C редактируют один файл — последовательны между собой; T-16 зависит от
> Блока A (T-01, использует `resolve_sid`). Может выполняться параллельно с Блоком B.

---

- [ ] **[CODE] T-16. `stage-write-guard.sh` — резолюция, карве-аут создания, jq fail-open, `Write`**

  **Файл:** `sdx/hooks/stage-write-guard.sh` (новый)

  **Что сделать:** По DESIGN.md §«Deny-хук `stage-write-guard.sh`», подразделы «Резолюция
  сессии и цели», «Первичное создание — не блокируется», «Отсутствие `jq`», «`Write`
  (точный путь)»:
  - Читает stdin (`input="$(cat)"`), `deny()` — тот же `jq -Rs .`-паттерн экранирования,
    что `stage-gate.sh`.
  - `target="$(... .tool_input.file_path ...)"`; пусто → `exit 0`. Нормализация `\`→`/`
    для `target`/`proj` (BUG-006-паттерн).
  - `. "$here/lib/resolve-session.sh"; sid="$(resolve_sid "$proj")"`; пусто → `exit 0`
    (REQ-DENY-3, вне ветки `sdx/*`).
  - `state="$proj/.claude/sessions/${sid}/session_state.json"`; `target != state` →
    `exit 0` (специфичен ИМЕННО этому файлу, сравнение по точному пути, не basename).
  - `[ -f "$state" ] || exit 0` — карве-аут: файла ещё нет → это создание, не правка
    (REQ-DENY-2, defense-in-depth поверх того, что `init` уже не идёт через `Write`).
  - Проверка `jq`: **после** проверки, что операция вообще касается `$state` (порядковая
    оптимизация как у `prod-guard.sh`) — при отсутствии `jq`: **fail-open**, `exit 0` +
    громкое предупреждение в stderr (REQ-DENY-4, асимметрия с `sdx-stage.sh` осознанная).
  - Для `Write`: точный путь — `content` → парсинг как JSON → `new_stage`; невалидный JSON
    → `deny` («не могу доказать, что stage не меняется»); `new_stage != old_stage` → `deny`
    с сообщением из DESIGN; иначе `exit 0`.

  **Definition of Done:**
  - `bash -n sdx/hooks/stage-write-guard.sh` без ошибок.
  - Скрипт **не** зарегистрирован в `hooks/hooks.json` на этом шаге.

  **REQ:** REQ-DENY-1, REQ-DENY-2, REQ-DENY-3, REQ-DENY-4 (частично — `Write`-путь).

---

- [ ] **[CODE] T-17. `stage-write-guard.sh` — огрублённый путь `Edit`/`MultiEdit`**

  **Файл:** `sdx/hooks/stage-write-guard.sh`

  **Что сделать:** По DESIGN.md §«`Edit`/`MultiEdit` (огрублённый путь)»: регэксп
  `STAGE_KEY_RE='"stage"[[:space:]]*:'`, функция `touches_stage()`. Для `Edit`:
  `new_string` из `.tool_input.new_string`; совпадение → `deny`. Для `MultiEdit`:
  `.tool_input.edits[]?.new_string` построчно; хоть одно совпадение → `deny` для всей
  пачки целиком (симметрично трактовке `stage-gate.sh` одиночного `file_path`). Ложные
  срабатывания (реформатирование без изменения значения) и теоретический
  ложноотрицательный случай — **намеренно принятое** поведение, не чинить (см. DESIGN
  «Ложноположительные случаи»).

  **Definition of Done:**
  - `bash -n sdx/hooks/stage-write-guard.sh` без ошибок.

  **REQ:** REQ-DENY-1, REQ-DENY-2 (довершение).

---

- [ ] **[TEST] T-18. `test-stage-write-guard.sh` — все 10 сценариев**

  **Файл:** `sdx/hooks/test-stage-write-guard.sh` (новый)

  **Что сделать:** По стилю `test-stage-gate.sh` (JSON на stdin через `run_hook`), 10
  сценариев из DESIGN тест-плана:
  1. `Edit` меняет `"stage"` → `deny`.
  2. `Write` полным содержимым с изменённым `.stage` → `deny`.
  3. `Edit`/`Write`, меняющие ТОЛЬКО `track`/`gate_mode`/`artifacts`/`history` → пропуск.
  4. `Write`, создающий ещё не существующий на диске `session_state.json` → пропуск
     (карве-аут REQ-DENY-2).
  5. Вне ветки `sdx/*` (на `main`) → пропуск.
  6. `session_state.json` по ДРУГОМУ пути (не текущей сессии, напр. `docs/session_state.json`)
     → пропуск (сравнение по точному пути, не basename).
  7. `MultiEdit`, где хотя бы один `edits[].new_string` содержит `"stage":` → `deny` для
     всей операции, даже если остальные правки легитимны.
  8. Без `jq` в `$PATH`, операция реально правит `stage` существующей сессии → пропуск
     (`exit 0`) + предупреждение в stderr, НЕ `deny` (REQ-DENY-4).
  9. `Edit` с `new_string`, содержащим `"stage"` не как JSON-ключ (напр. `"note": "next
     stage: TBD"`) → **документируем ожидаемый false positive** (`deny`) как контракт, не
     баг — комментарий в тесте ссылается на DESIGN.md.
  10. Backslash-путь (Windows-style) к `session_state.json` → деном срабатывает так же, как
      с forward-slash (BUG-006-паттерн).

  **Definition of Done:**
  - `bash sdx/hooks/test-stage-write-guard.sh` → `exit 0`, все 10 сценариев `PASS`.

  **REQ:** покрывает T-16, T-17 (REQ-DENY-1..4 целиком).

---

### Блок D — Проводка `hooks/hooks.json`

---

- [x] **[INFRA] T-19. `hooks/hooks.json` — третья запись `stage-write-guard.sh`; `chmod +x`**

  **Файлы:** `hooks/hooks.json`, `sdx/hooks/stage-write-guard.sh`

  **Что сделать:**
  - Добавить третью запись в **существующий** matcher `PreToolUse` / `Write|Edit|MultiEdit`
    (после `stage-gate.sh`, порядок внутри массива не влияет на исход):
    `{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}\"/sdx/hooks/stage-write-guard.sh" }`.
  - `chmod +x sdx/hooks/stage-write-guard.sh` — **обязательно**: hooks.json вызывает файл
    напрямую (без явного `bash`-префикса), как и существующие `stage-gate.sh`/`stop-gate.sh`/
    `prod-guard.sh`.
  - `sdx-stage.sh` **не требует** `chmod +x` — команды всегда вызывают его через явный
    `bash "${CLAUDE_PLUGIN_ROOT}/sdx/hooks/sdx-stage.sh" ...` (тот же паттерн, что
    `archive-verify.sh`, который тоже не исполняемый напрямую).

  **Definition of Done:**
  - `python3 -c "import json,sys; json.load(sys.stdin)" < hooks/hooks.json` — валидный JSON.
  - `grep -c "stage-write-guard.sh" hooks/hooks.json` → `1`.
  - `ls -la sdx/hooks/stage-write-guard.sh` показывает бит `x`.
  - **Примечание (см. «Замечание по самоприменению» выше):** это изменение НЕ активирует
    хук для текущей запущенной CLI-сессии немедленно — активация только через T-29.

  **REQ:** делает REQ-DENY-1 технически исполнимым (проводка).

---

### Блок E — Изменения в командах `/sdx:*` (Execution)

> Каждая задача зависит от соответствующей подкоманды `sdx-stage.sh` (T-07/T-09/T-11/T-13).
> Не требуют отдельных TEST-задач (правки прозы команд, не исполняемый код) — проверяются
> вручную/интеграционно на Verification (`qa`/`reviewer` этой сессии).

---

- [x] **[DOC] T-20. `commands/start.md` — шаг 5 → `sdx-stage.sh init`; удалить шаг 7**

  **Файл:** `commands/start.md`

  **Что сделать:** По DESIGN.md §«`commands/start.md`». Шаг 5 («Инициализируй
  `session_state.json`... и seed `session.log`») заменяется вызовом
  `bash "${CLAUDE_PLUGIN_ROOT}/sdx/hooks/sdx-stage.sh" init "<session_id>" "<type>" "<track>"
  "<стартовый stage>" "<gate_mode>" "sdx/<session_id>"`. Шаг 7 («Запиши в лог `[START]`»)
  удаляется целиком (пишет `init`). Шаг 6 (коммит) не меняется по содержанию — коммитит
  оба файла, созданных скриптом.

  **Definition of Done:**
  - `grep -c "sdx-stage.sh" commands/start.md` → `≥ 1`.
  - Прежний текст шага 7 (запись `[START]` вручную) отсутствует.

  **REQ:** REQ-STAGE-1, REQ-COMPAT-1. Зависит от T-07.

---

- [x] **[DOC] T-21. `commands/import.md` — шаг 2 → `sdx-stage.sh init`**

  **Файл:** `commands/import.md`

  **Что сделать:** По DESIGN.md §«`commands/import.md»`. Шаг 2 заменяется вызовом
  `sdx-stage.sh init <id> import <track> Discovery <gate_mode> sdx/<id>` (track по
  умолчанию `full`, стартовый этап — первый активный этап `full`-матрицы; для варианта
  `standard` — первый активный этап `standard`). Строка `[START] Импорт фичи...` из
  прежнего шага 2 удаляется. **Решение Task Planning:** опциональный `--note`-аргумент
  `init` (упомянутый в DESIGN как «Execution решает») **не реализуется** — общий текст
  `[START] Инициализация сессии...` из `init` достаточен и для `import`; кастомизация
  сообщения не требуется ни одним REQ. Если понадобится позже — оформить отдельной
  `IDEA`-записью бэклога, не расширять эту задачу.

  **Definition of Done:**
  - `grep -c "sdx-stage.sh" commands/import.md` → `≥ 1`.
  - Прежний текст «Запиши `[START] Импорт фичи...`» отсутствует.

  **REQ:** REQ-STAGE-1, REQ-COMPAT-1. Зависит от T-07.

---

- [x] **[DOC] T-22. `commands/next.md` — укоротить гейт-прозу; шаг 4 → `sdx-stage.sh next`**

  **Файл:** `commands/next.md`

  **Что сделать:** По DESIGN.md §«`commands/next.md`». Шаг 3 (полный список прозаических
  гейт-условий по этапам) укорачивается до формулировки DESIGN («Объективно проверяемая
  часть гейта... проверяется автоматически вызовом `sdx-stage.sh next`... Смысловые
  условия... остаются твоим суждением ДО вызова»). Шаг 4 заменяется вызовом `bash
  "${CLAUDE_PLUGIN_ROOT}/sdx/hooks/sdx-stage.sh" next "<session_id>"`. При коде `0` —
  текст коммита/лога берётся из `OK <old> -> <new>` в stdout (лог уже записан скриптом).
  При `1`/`2` — шаг 5 (сообщение пользователю, `[ERROR]` в лог) берёт текст из stderr
  скрипта дословно, не формулирует заново.

  **Definition of Done:**
  - `grep -c "sdx-stage.sh" commands/next.md` → `≥ 1`.
  - Прежний построчный список гейт-условий по этапам (существование/непустота/FAIL)
    заменён краткой ссылкой на скрипт.

  **REQ:** REQ-STAGE-2, REQ-STAGE-4, REQ-STAGE-5, REQ-CLOSEOUT-ENTRY-1 (архив тоже вызывает
  `next`). Зависит от T-09.

---

- [x] **[DOC] T-23. `commands/backtrack.md` — шаги 1–5 → один вызов `sdx-stage.sh backtrack`**

  **Файл:** `commands/backtrack.md`

  **Что сделать:** По DESIGN.md §«`commands/backtrack.md`». Шаги 1–5 заменяются вызовом
  `bash "${CLAUDE_PLUGIN_ROOT}/sdx/hooks/sdx-stage.sh" backtrack "<session_id>" "<stage>"`.
  Шаг 6 («сообщи, какие файлы требуют актуализации») заполняется из строк `OUTDATED:
  <path>` stdout скрипта — не догадка. Прежний шаг 5 («обнули `PLAN.md`») **удаляется
  полностью** — REQ-BACKTRACK-2 отменяет зануление.

  **Definition of Done:**
  - `grep -c "sdx-stage.sh" commands/backtrack.md` → `≥ 1`.
  - Текст «обнули PLAN.md» / «перемести в бэкап» отсутствует в файле.

  **REQ:** REQ-BACKTRACK-1, REQ-BACKTRACK-2. Зависит от T-11.

---

- [x] **[DOC] T-24. `commands/retrack.md` — шаг 4 на подшаги + вызов `sdx-stage.sh retrack`**

  **Файл:** `commands/retrack.md`

  **Что сделать:** По DESIGN.md §«`commands/retrack.md`». Шаг 4 разбивается на подшаги:
  (1) определение целевого `stage` прежним прозаическим правилом (без изменений); (2)
  правка `track` (и `gate_mode` при эскалации) через `Edit`, как и раньше — легитимно,
  деном не блокирует; (3) вызов `bash "${CLAUDE_PLUGIN_ROOT}/sdx/hooks/sdx-stage.sh" retrack
  "<session_id>" "<target-stage>"`. Шаг 5 (лог «Смена трека...») остаётся, но пишется в ОДНОМ
  Bash-ходе вместе с вызовом скрипта (`echo ... >> session.log && bash sdx-stage.sh
  retrack ...`), не отдельным round-trip.

  **Definition of Done:**
  - `grep -c "sdx-stage.sh" commands/retrack.md` → `≥ 1`.
  - Шаг 4 явно содержит 3 подшага (определение цели / правка track / вызов скрипта).

  **REQ:** REQ-RETRACK-1. Зависит от T-13.

---

- [x] **[DOC] T-25. `commands/archive.md` — шаг 2 (вход в Closeout) → `sdx-stage.sh next`**

  **Файл:** `commands/archive.md`

  **Что сделать:** По DESIGN.md §«`commands/archive.md`». Вторая половина шага 2 («Затем
  переведи `stage` в `Closeout`, запиши `[STAGE_CHANGE]`») заменяется вызовом `bash
  "${CLAUDE_PLUGIN_ROOT}/sdx/hooks/sdx-stage.sh" next "<session_id>"`. Явный трек-specific
  гейт-текст («на треке patch: `verification_report.md` без FAIL») **удаляется как
  отдельная прозаическая проверка** — это тот же самый унифицированный гейт
  `Verification→Closeout`, который `next`-подкоманда уже проверяет для всех треков без
  ветвления. При отказе (`exit 1`) — реле сообщения скрипта, Closeout не начинается, чек-лист
  не печатается. Дисклоуз `auto_decisions.md` (gate_mode auto) остаётся прозаическим шагом
  ДО вызова скрипта, без изменений.

  **Definition of Done:**
  - `grep -c "sdx-stage.sh" commands/archive.md` → `≥ 1`.
  - Отдельная прозаическая проверка «на треке patch: verification_report.md без FAIL»
    в шаге 2 отсутствует (заменена вызовом скрипта).

  **REQ:** REQ-CLOSEOUT-ENTRY-1. Зависит от T-09 (та же подкоманда `next`).

---

### Блок F — Documentation (этап SDX Documentation, после завершения Execution)

> Выполняется на этапе **Documentation** этой сессии (после `/sdx:next` из Execution), а
> не в рамках Execution. Требует, чтобы все задачи блоков A–E были завершены и
> `verify-cmd.sh` (полный прогон `test-*.sh`, включая T-02/06/08/10/12/14/15/18) зелёный —
> это тест-пол `stop-gate.sh` на стадии Execution этой сессии (дог-фудинг, DEBT-004).

---

- [x] **[DOC] T-26. `sdx/protocol.md` — раздел «Механизм перехода этапов», уточнения**

  **Файл:** `sdx/protocol.md`

  **Что сделать:** По DESIGN.md §«Изменения в документации фреймворка» → `protocol.md`:
  - Новый раздел **«Механизм перехода этапов (`sdx-stage.sh`)»** после «Гейты (Gates)», до
    «Авторежим гейтов»: 4 подкоманды, коды возврата, ссылка на матрицу как источник истины
    (без дублирования её текстом — REQ-STAGE-3).
  - Раздел «Гейты (Gates)» — уточнение: механическая часть enforced `sdx-stage.sh`,
    scope-check остаётся прозаическим суждением оркестратора.
  - Раздел «Enforcement-слой (хуки)» — новый пункт **`stage-write-guard`** по образцу
    существующих (`PreToolUse Write|Edit|MultiEdit`; узкая деном-граница на `stage`;
    fail-open без `jq`; безопасен для `.claude/**`/`track`/`gate_mode`).
  - Таблица треков (строки ~51–55) — сноска: «Машиночитаемый источник истины порядка
    этапов и гейт-артефактов — матрица внутри `sdx/hooks/sdx-stage.sh`; эта таблица —
    человекочитаемая проекция, не источник для скрипта».

  **Definition of Done:**
  - `grep -c "Механизм перехода этапов" sdx/protocol.md` → `1`.
  - `grep -c "stage-write-guard" sdx/protocol.md` → `≥ 1`.
  - После правки: `bash sdx/hooks/test-sdx-stage.sh` (сценарий 19) по-прежнему `PASS`
    (сноска не должна сломать grep/sed-разбор таблицы).

  **REQ:** REQ-STAGE-3 (документирование), общее описание REQ-DENY-*.

---

- [x] **[DOC] T-27. `docs/DECISIONS.md` — новая запись ADR-016**

  **Файл:** `docs/DECISIONS.md`

  **Что сделать:** Вставить ADR-016 после ADR-015, тем же форматом (Контекст/Решение/
  Обоснование/Инварианты/Связь) — по черновику DESIGN.md §«ADR-016 (проект...)». Финальный
  номер подтвердить по факту (если между Technical Design и Closeout в `main` появился
  другой ADR — исключить коллизию номеров).

  **Definition of Done:**
  - `grep -c "^## ADR-016" docs/DECISIONS.md` → `1`.
  - Запись содержит все 5 подразделов (Контекст/Решение/Обоснование/Инварианты/Связь).

  **REQ:** документирует REQ-STAGE-1..5, REQ-BACKTRACK-1..2, REQ-RETRACK-1,
  REQ-CLOSEOUT-ENTRY-1, REQ-DENY-1..4.

---

### Блок G — Deployment (этап SDX Deployment, после Verification)

> Выполняется **после** прохождения `/sdx:verify` (гейт Verification закрыт, `FAIL`-находок
> нет) — по протоколу Deployment следует за Verification, не за Documentation напрямую.

---

- [ ] **[INFRA] T-28. `.claude-plugin/plugin.json` — bump версии `1.2.2` → `1.3.0`**

  **Файл:** `.claude-plugin/plugin.json`

  **Что сделать:** Изменить `"version": "1.2.2"` на `"version": "1.3.0"` (minor bump —
  новая возможность enforcement-слоя, не патч). `marketplace.json` не трогать (`source:
  "./"`, версии не хранит).

  **Definition of Done:**
  - `grep '"version": "1.3.0"' .claude-plugin/plugin.json` → найдено.
  - `python3 -c "import json; json.load(open('.claude-plugin/plugin.json'))"` — валидный JSON.

  **REQ:** DESIGN §«Версия плагина», решение пользователя #4.

---

- [ ] **[INFRA] T-29. Активация плагина: `/plugin marketplace update sdx`**

  **Что сделать:** Не файловое изменение (без коммита) — операционный шаг. После T-28
  (версия закоммичена на ветку сессии) выполнить `/plugin marketplace update sdx`, чтобы
  установленная (кэшированная) копия плагина подхватила `sdx-stage.sh`,
  `stage-write-guard.sh` и новую запись `hooks/hooks.json`. Если хуки не активируются в
  текущем процессе CLI — потребуется рестарт CLI (тот же caveat, что был у B1 в плане
  `fw-enforce-route-20260627`). **После этого шага** дальнейшие правки `.stage` в ЛЮБОЙ
  открытой SDX-сессии (включая, если она ещё не закрыта, саму `fw-stage-guard-20260720`)
  идут через `sdx-stage.sh` — прямой `Edit`/`Write` поля `stage` будет заблокирован
  деном. Так как команды (Блок E) уже переписаны на `sdx-stage.sh` к этому моменту —
  самоблокировки не происходит.

  **Definition of Done:**
  - Установленная копия плагина (`~/.claude/plugins/cache/sdx/sdx/1.3.0/` или актуальный
    путь) содержит `sdx/hooks/sdx-stage.sh`, `sdx/hooks/stage-write-guard.sh` и запись
    `stage-write-guard.sh` в `hooks/hooks.json` — проверить листингом каталога кэша.
  - Одно ручное подтверждение: пробная безобидная правка `session_state.json` через `Edit`
    (например, дублирующая правка поля `track` на то же значение — non-`stage` поле) на
    тестовой ветке `sdx/*` проходит без деном; аналогичная попытка изменить `stage`
    блокируется.

  **REQ:** делает REQ-DENY-1..4 фактически действующими для рантайма (активация,
  не код).

---

## Зависимости между задачами

```
Блок A (независим от B/C по файлам):
  T-01 → T-02
  T-01 → T-03 (stage-gate refactor)
  T-01 → T-04 (stop-gate refactor)
  T-03, T-04 — независимы друг от друга

Блок B (один файл sdx-stage.sh — строго последовательно; не зависит от Блока A):
  T-05 → T-06 → T-07 → T-08 → T-09 → T-10 → T-11 → T-12 → T-13 → T-14 → T-15

Блок C (один файл stage-write-guard.sh — последовательно; зависит от T-01):
  T-01 → T-16 → T-17 → T-18

Блок D (зависит от завершения Блока C):
  T-16, T-17, T-18 → T-19

Блок E (каждая команда зависит от своей подкоманды sdx-stage.sh; не зависит от Блока D):
  T-07 → T-20 (start.md)
  T-07 → T-21 (import.md)
  T-09 → T-22 (next.md)
  T-11 → T-23 (backtrack.md)
  T-13 → T-24 (retrack.md)
  T-09 → T-25 (archive.md)

Блок F (после ВСЕХ задач A–E, на этапе Documentation):
  {T-01..T-25} → T-26 → T-27

Блок G (после Verification, на этапе Deployment):
  T-27 → [/sdx:verify: FAIL-находок нет] → T-28 → T-29
```

**Критический путь:** T-05 → T-06 → T-07 → T-08 → T-09 → T-10 → T-11 → T-12 → T-13 → T-14
→ T-15 (Блок B, самый длинный из-за строгой последовательности одного файла) → T-25/T-22
(зависят от T-09) → T-26 → T-27 → [Verification] → T-28 → T-29.

Блок A (T-01–T-04) и Блок C (T-16–T-18, зависит только от T-01) можно вести параллельно с
Блоком B без коллизий файлов — они не пересекаются с `sdx-stage.sh`.

---

## Порядок исполнения

1. **T-01** — `lib/resolve-session.sh`
2. **T-02** — тест библиотеки
3. **T-03, T-04** (параллельно) — рефакторинг `stage-gate.sh`, `stop-gate.sh`
4. **T-05 → T-15** (строго последовательно, один файл) — `sdx-stage.sh` целиком, с тестами
   на каждом шаге (TDD: тестовая подзадача сразу после соответствующей кодовой)
   — *может идти параллельно с шагами 1–3*
5. **T-16 → T-18** (после T-01) — `stage-write-guard.sh` целиком, с тестами
   — *может идти параллельно с шагом 4*
6. **T-19** — проводка `hooks/hooks.json` + `chmod +x` (после T-16–T-18)
7. **T-20, T-21** (параллельно, оба зависят от T-07) — `start.md`, `import.md`
8. **T-22, T-25** (параллельно, оба зависят от T-09) — `next.md`, `archive.md`
9. **T-23** (зависит от T-11) — `backtrack.md`
10. **T-24** (зависит от T-13) — `retrack.md`
11. **Прогон полного `verify-cmd.sh`** (глоб `test-*.sh`) — зелёный прогон обязателен перед
    переходом дальше (stop-gate этой же сессии это и так enforced).
12. **`/sdx:next`** (Execution → Documentation этой сессии, штатным прозаическим путём —
    деном ещё не активен, см. «Замечание по самоприменению»).
13. **T-26** — `sdx/protocol.md`
14. **T-27** — `docs/DECISIONS.md` (ADR-016)
15. **`/sdx:next`** (Documentation → Verification) → **`/sdx:verify`** (не часть этого
    PLAN.md — отдельный процесс `qa`/`reviewer`).
16. После зелёного Verification: **`/sdx:next`** (Verification → Deployment).
17. **T-28** — bump версии `plugin.json`
18. **T-29** — `/plugin marketplace update sdx` (+ возможный рестарт CLI)
19. **`/sdx:next`** (Deployment → Closeout) → `/sdx:archive`.

---

## Риски исполнения

1. **Самоблокировка хуком.** Не актуальна сразу после T-19 (рантайм читает установленную
   копию плагина, не рабочее дерево) — актуальна только после T-29. Порядок этого плана
   (Блок E — команды переписаны на `sdx-stage.sh` — идёт строго ДО Блока G — активация)
   гарантирует, что к моменту, когда деном реально станет активен, легитимный путь уже
   существует для всех шести команд. Если T-29 будет выполнен раньше времени (до
   завершения Блока E) кем-то вручную — текущая сессия рискует не суметь сделать
   `/sdx:next` прозаическим Edit-путём; в этом случае восстановление — через `Bash`
   (`jq`/`sed -i` in-place, DEBT-003, легитимный эскейп-хетч) до завершения Блока E.
2. **Ложное срабатывание deny на легитимных правках `session_state.json`.** `retrack.md`
   правит `track`/`gate_mode` через `Edit` в том же файле, где лежит `stage` — сценарий 3
   `test-stage-write-guard.sh` (T-18) — обязательная защита от регрессии этого пути;
   прогнать его до T-19 (wiring), не после.
3. **Регресс существующих `test-stage-gate.sh`/`test-stop-gate.sh`.** T-03/T-04 —
   поведение-сохраняющий рефакторинг; DoD каждой задачи требует зелёного прогона
   СУЩЕСТВУЮЩЕГО (неизменённого) теста — любое расхождение результата сценария 1–10
   (stage-gate) или loop-guard/cache-сценариев (stop-gate) — сигнал регресса, не
   принимать коммит.
4. **Ложноположительный сценарий 9 write-guard (касание подстроки `"stage"` не как
   JSON-ключ).** Задокументированный, принятый компромисс (DESIGN явно фиксирует) — тест
   T-18 сценарий 9 ФИКСИРУЕТ его как контракт, не как баг для починки. Не пытаться
   «улучшить» точность регэкспа сверх контракта DESIGN в рамках этой сессии.
5. **Рассинхронизация матрицы `sdx-stage.sh` и таблицы `protocol.md`.** Sanity-тест
   (сценарий 19, T-06/T-26) — грубый детектор (множество названий этапов трека `full`), не
   гарантия полного соответствия порядка. Остаётся открытым риском по DESIGN — не
   переусердствовать с попыткой закрыть его полным парсером в этой сессии (вне скоупа).
6. **Дог-фудинг stop-gate на самой этой сессии (DEBT-004).** `.claude/sdx/verify-cmd.sh`
   этого репозитория прогоняет ВСЕ `sdx/hooks/test-*.sh` глобом — новые тестовые файлы
   (T-02/06/08/10/12/14/15/18) автоматически становятся частью тест-пола `stop-gate.sh` для
   стадий Execution/Verification этой же сессии. Красный прогон любого нового теста
   заблокирует `Stop` — это ожидаемое поведение (стоп-гейт работает штатно), не повод
   отключать/обходить его.
7. **Асимметрия деградации без `jq` — не перепутать направление.** `sdx-stage.sh` —
   fail-closed (`exit 2`, файл не тронут); `stage-write-guard.sh` — fail-open (`exit 0` +
   громкое предупреждение). Тесты T-15 (сценарий 17) и T-18 (сценарий 8) проверяют РАЗНЫЕ
   коды возврата для двух скриптов при одинаковом отсутствии `jq` — при реализации по
   аналогии друг с другом легко перепутать знак.
8. **Параллелизация ограничена файловыми границами.** Блок B (`sdx-stage.sh`) и Блок C
   (`stage-write-guard.sh`) — каждый последовательная цепочка коммитов одного файла;
   попытка распараллелить задачи ВНУТРИ одного блока (например, T-07 и T-09 одновременно)
   создаст конфликт правок одного файла — не делать.
