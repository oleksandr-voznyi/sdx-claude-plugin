# Change Note — fw-backlog-20260719 (E2: формализация бэклога)

## Цель (бизнес-решения)
Бэклог фреймворка живёт неструктурированно (`docs/audit-2026-07-01-recommendations.md` +
roadmap в gitignored-бандле): нет ID, трассировки, команд просмотра и планирования волн.
Вводим постоянный трекаемый бэклог как штатный артефакт фреймворка.

1. **Хранилище**: `docs/backlog/` — один файл на запись, машиночитаемый YAML frontmatter
   (интеграционная точка будущего плагина портфельного управления) + индекс `README.md`
   (таблица: id / type / status / priority / wave / title).
2. **Схема frontmatter** (обязательные поля):
   ```yaml
   id: DEBT-001          # <PREFIX>-<NNN>, сквозная нумерация внутри типа
   type: debt            # feat | bug | debt | idea | proc
   status: open          # open | in-progress | closed | deferred
   priority: normal      # high | normal | low
   wave: 7               # номер волны планирования или null
   source: audit-2026-07-01 (A3)   # происхождение записи
   session: null         # сессия, закрывшая/работающая (sdx/<id>)
   links: [ADR-014]      # связанные ADR/находки/записи
   ```
   Тело: `## Суть` и `## Рекомендация` (свободная проза, язык — русский).
3. **Префиксы ID**: `FEAT-` (новая функциональность), `BUG-` (дефекты/противоречия),
   `DEBT-` (техдолг/дрейф/недоспецификация), `IDEA-` (roadmap-идеи), `PROC-` (процессные
   изменения). Имя файла: `<ID>-<slug>.md`.
4. **Команда `/sdx:backlog`** (`commands/backlog.md`): без аргументов — таблица-список;
   фильтры `--status/--type/--wave`; `<ID>` — деталь записи; `add` — создание записи
   интервью с пользователем. Read-only по чужим записям, сессии не требует.
5. **Closeout-интеграция**: пункт 4 чек-листа расширяется — вместе с глобальным логом
   актуализируется бэклог (закрытые находки → `status: closed` + `session`; отложенные
   решения и неквитированные WARN → новые DEBT/IDEA-записи). Нумерация пунктов чек-листа
   НЕ меняется (инварианты 1/5/6 зашиты в `archive-verify.sh` и ADR — ренумерация запрещена).
6. **Миграция**: все находки A*–E* аудита переносятся в `docs/backlog/` с сохранением
   статусов и содержимого; файл аудита остаётся историческим снапшотом с баннером-указателем.
   Волны/приоритеты открытых записей — из таблицы «Приоритизированный план сессий».
7. **ADR-015** в `docs/DECISIONS.md`: бэклог как артефакт фреймворка.

## Технические решения
- `/sdx:init` дополняется созданием `docs/backlog/` в целевых проектах (шаблонов не требуется —
  структуру создаёт команда; README-индекс генерируется).
- `CLAUDE.md` §6: `docs/backlog/` добавляется в описание per-project слоя.
- `sdx/protocol.md`: правка формулировки п.4 Closeout-чек-листа.
- Enforcement-хуки не затрагиваются (бэклог — прозаический слой; `docs/**` всегда открыт stage-gate).

## Маппинг миграции (audit → backlog)
| Аудит | ID | type | status | priority | wave | session |
|-------|----|------|--------|----------|------|---------|
| A1 | BUG-001 | bug | closed | — | — | fw-enforce-a1a2-20260703 |
| A2 | BUG-002 | bug | closed | — | — | fw-enforce-a1a2-20260703 |
| C2 | BUG-003 | bug | open | normal | 8 | — |
| B3 | BUG-004 | bug | open | normal | 5 | — |
| C7 | BUG-005 | bug | open | normal | 9 | — |
| A3 | DEBT-001 | debt | open | high | 7 | — |
| A4 | DEBT-002 | debt | closed | — | — | fw-econ-a4d1-20260703 |
| A5 | DEBT-003 | debt | open | normal | 10 | — |
| A6 | DEBT-004 | debt | open | normal | 4 | — |
| B1 | DEBT-005 | debt | closed | — | — | fw-model-aliases-20260702 |
| B2 | DEBT-006 | debt | closed | — | — | fw-model-aliases-20260702 |
| B4 | DEBT-007 | debt | open | normal | 10 | — |
| C1 | DEBT-008 | debt | open | high | 2 | — |
| C4 | DEBT-009 | debt | open | normal | 10 | — |
| C5 | DEBT-010 | debt | open | normal | 10 | — |
| C6 | DEBT-011 | debt | open | normal | 10 | — |
| D1 | DEBT-012 | debt | closed | — | — | fw-econ-a4d1-20260703 |
| D2 | IDEA-001 | idea | deferred | low | — | — |
| C3 | PROC-001 | proc | closed | — | — | fw-auto-gates-20260719 |
| E1 | PROC-002 | proc | open | normal | — | — |
| E2 | PROC-003 | proc | in-progress | high | — | fw-backlog-20260719 |
| E3 | PROC-004 | proc | open | normal | — | — |
| E4 | PROC-005 | proc | closed | — | — | fw-auto-gates-20260719 |

## Затронутые файлы (заполняется по ходу Execution)
- `docs/backlog/` — 23 записи + `README.md` (индекс)
- `commands/backlog.md` — новая команда
- `sdx/protocol.md`, `commands/archive.md` — Closeout п.4
- `commands/init.md`, `CLAUDE.md` — структура `docs/backlog/`
- `docs/DECISIONS.md` — ADR-015
- `docs/audit-2026-07-01-recommendations.md` — баннер миграции
