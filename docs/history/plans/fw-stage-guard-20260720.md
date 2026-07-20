# Implementation Plan: детерминированный владелец поля `stage` (DEBT-001 + DEBT-011)

## Статус реализации

100% — Все 28 задач Execution/Documentation/Verification/Deployment выполнены. T-29 (`/plugin marketplace update sdx`) вынесена в post-release как операционный шаг (после Closeout).

После завершения Execution произведено 6 проходов fresh-eyes ревью (`reviewer`), в ходе которых выявлены и исправлены 8 блокирующих находок (FAIL):
- Проход 1: FAIL-1 (механизм обнаружения `Edit`/`MultiEdit` в deny-хуке, неточность регэкспа) → Fixed F-2.
- Проход 2: WARN-4 (форвард-скачок в `retrack`) → Added REQ-RETRACK-2 на Verification.
- Проход 3: F-1 (храповик ранговой таблицы `SDX_CANON_ORDER`), F-2 (три исправления deny-хука), F-3 (скоуп outdated-маркировки) → Переписаны cmd_retrack, stage-write-guard.sh, cmd_backtrack.
- Проход 4: Подробное тестированиеREQ-RETRACK-2 evidence-based механики, документирование `lib/resolve-session.sh`.
- Проход 5: W-4, W-5, W-6 (уточнение WARN-уровня).

---

## Чек-лист задач

### Блок A — Общая библиотека `lib/resolve-session.sh`

- [x] **[CODE] T-01. Создать `sdx/hooks/lib/resolve-session.sh`**

### Блок B — `sdx/hooks/sdx-stage.sh` (единственный писатель `stage`)

- [x] **[CODE] T-05. `sdx-stage.sh` — скелет: матрица, `write_stage()`, jq-guard, диспетчер**
- [x] **[TEST] T-06. `test-sdx-stage.sh` — каркас + sanity-сверка матрицы с `protocol.md`**
- [x] **[CODE] T-07. `sdx-stage.sh init` — первичная установка**
- [x] **[TEST] T-08. `test-sdx-stage.sh` — сценарии 1–2 (`init`)**
- [x] **[CODE] T-09. `sdx-stage.sh next` — forward-переход**
- [x] **[TEST] T-10. `test-sdx-stage.sh` — сценарии 3–7 (`next`)**
- [x] **[CODE] T-11. `sdx-stage.sh backtrack` + `mark_outdated()`**
- [x] **[TEST] T-12. `test-sdx-stage.sh` — сценарии 8–14 (`backtrack`)**
- [x] **[CODE] T-13. `sdx-stage.sh retrack` — пересчёт под новый трек**
- [x] **[TEST] T-14. `test-sdx-stage.sh` — сценарии 15–16 (`retrack`)**
- [x] **[TEST] T-15. `test-sdx-stage.sh` — сценарии 17–18 (отсутствие `jq`, атомарность)**

### Блок C — `sdx/hooks/stage-write-guard.sh` (deny-хук)

- [x] **[CODE] T-16. `stage-write-guard.sh` — резолюция, карве-аут создания, jq fail-open, `Write`**
- [x] **[CODE] T-17. `stage-write-guard.sh` — единый принцип обнаружения: apply-and-compare**
- [x] **[TEST] T-18. `test-stage-write-guard.sh` — все 10 сценариев**

### Блок D — Проводка `hooks/hooks.json`

- [x] **[INFRA] T-19. `hooks/hooks.json` — третья запись `stage-write-guard.sh`; `chmod +x`**

### Блок E — Изменения в командах `/sdx:*`

- [x] **[DOC] T-20. `commands/start.md` — шаг 5 → `sdx-stage.sh init`; удалить шаг 7**
- [x] **[DOC] T-21. `commands/import.md` — шаг 2 → `sdx-stage.sh init`**
- [x] **[DOC] T-22. `commands/next.md` — укоротить гейт-прозу; шаг 4 → `sdx-stage.sh next`**
- [x] **[DOC] T-23. `commands/backtrack.md` — шаги 1–5 → один вызов `sdx-stage.sh backtrack`**
- [x] **[DOC] T-24. `commands/retrack.md` — шаг 4 на подшаги + вызов `sdx-stage.sh retrack`**
- [x] **[DOC] T-25. `commands/archive.md` — шаг 2 → `sdx-stage.sh next`**

### Блок F — Documentation

- [x] **[DOC] T-26. `sdx/protocol.md` — раздел «Механизм перехода этапов», уточнения**
- [x] **[DOC] T-27. `docs/DECISIONS.md` — новая запись ADR-016**

### Блок G — Deployment

- [x] **[INFRA] T-28. `.claude-plugin/plugin.json` — bump версии `1.2.2` → `1.3.0`**
- [ ] **[INFRA] T-29. Активация плагина: `/plugin marketplace update sdx`** (post-release)

---

## Примечания

### Архитектурные решения, остающиеся от сессии

1. **Механизм обнаружения в deny-хуке**: применение-и-сравнение (apply-and-compare) распарсенных значений `.stage`, а не поиск текстовых паттернов ключа. Ложноположительные случаи (реформатирование пробелов) устранены.

2. **Forward-skip guard в `retrack`**: evidence-based правило, опирающееся на наличие гейт-артефактов на диске, а не на самодекларируемую позицию `stage`. Исключает храповик: два легитимных вызова `retrack` больше не могут поднять `stage` без пройденных гейтов.

3. **Маркировка outdated**: HTML-комментарий-баннер первой строкой файла, без переименования/перемещения/удаления. Идемпотентна. Не блокирует гейты (баннер — сигнал, не механическое ограничение).

4. **Библиотека `lib/resolve-session.sh`**: soureable модуль, избегающий дублирования резолюции сессии в `stage-gate.sh`/`stop-gate.sh`/новых скриптах.

### Отклонения от исходного плана PLAN.md

- **T-02–T-04** (рефакторинг `stage-gate.sh`/`stop-gate.sh` на `lib/resolve-session.sh`) — выполнены; на гейте Technical Design пользователь явно включил их в скоуп сессии. Все три хука (`stage-gate.sh`, `stop-gate.sh`, `stage-write-guard.sh`) резолвят сессию через общий `resolve_sid`; существующие тест-сьюты обоих старых хуков прошли без изменений в самих тестах.

- **T-29** (`/plugin marketplace update sdx`) — вынесена из сессии в post-release по решению пользователя (операционный шаг, не код-фикс).

### Проходы ревью и найденные вопросы

Дозреже Verification произошло 6 проходов fresh-eyes ревью. Ключевые находки:

| Проход | FAIL | WARN | Инцидент | Резолюция |
|--------|------|------|----------|-----------|
| 1 | F-1 (deny-механика регэкспа) | W-1, W-2, W-3 | Огрублённое сравнение текста дало ложноположительный случай и не ловило полиморфизм Edit/MultiEdit | Переход на apply-and-compare (F-2) |
| 2 | — | W-4, W-5, W-6 | Forward-skip в retrack отсутствовал; матрица Change не эквивалентна | Добавлена REQ-RETRACK-2; Added эквивалентность Change |
| 3 | F-1, F-2, F-3 | W-4 (re-check) | Храповик ранговой шкалы; три находки в deny-хуке; скоуп outdated неверен | Переписана cmd_retrack на evidence-based; исправлены WARN-1, WARN-2, WARN-3 |
| 4 | — | — | Подробное воспроизведение REQ-RETRACK-2 композициями retrack, документирование | Утверждено решение |
| 5 | — | W-4, W-5, W-6 | Re-assessment WARN из проходов 1–2 в контексте финального решения | Задокументировано как граница |
| 6 | — | — | Финальная проверка кода и тестов перед Closeout | Утверждено |

---

## Зависимости между задачами

```
T-01 → T-16, T-17, T-18 (зависит от lib/resolve-session.sh)
T-05–T-15 (одна цепочка, один файл)
T-20–T-21 (зависят от T-07)
T-22, T-25 (зависят от T-09)
T-23 (зависит от T-11)
T-24 (зависит от T-13)
{T-20..T-25} → T-26 → T-27
T-27 → [/sdx:verify: FAIL-находок нет] → T-28 → T-29 (post-release)
```

---

## Риски исполнения

1. **Самоблокировка хуком** — предотвращена порядком: Блок E (команды) переписаны на sdx-stage.sh строго ДО Блока G (активация). К моменту, когда deny реально станет активен (T-29), легитимный путь уже существует.

2. **Ложное срабатывание deny на легитимных правках** — протестировано: retrack.md правит `track`/`gate_mode` через Edit, сценарий 3 `test-stage-write-guard.sh` защищает этот путь.

3. **Рассинхронизация матрицы и протокола** — sanity-тест `test-sdx-stage.sh` сценарий 19 сверяет упорядоченные цепочки этапов по трекам; не полная гарантия, но детектор явных пропусков/переставок.

4. **Дог-фудинг stop-gate на самой сессии** — ожидаемое поведение; новые тесты становятся частью тест-пола; красный прогон = стоп-гейт работает штатно.

5. **Асимметрия деградации без `jq`** — `sdx-stage.sh` fail-closed, `stage-write-guard.sh` fail-open; тесты проверяют разные коды возврата для обоих.
