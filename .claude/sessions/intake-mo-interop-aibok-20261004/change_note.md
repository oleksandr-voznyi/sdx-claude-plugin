# change_note — intake-mo-interop-aibok-20261004

**Что.** Разбор трёх записок об интеропе SDX ↔ мета-оркестратор (МО) и обзора AIBoK 1.0 в записи бэклога
(`no_code`: Discovery-lite → Business Spec/Technical Design свёрнуты сюда → Verification → Closeout).

**Вход (состав внешнего материала, фактически взятого в разбор — требование `sdx/protocol.md` к `change_note.md` при `no_code`).**
1. `~/Downloads/изменения в SDX для работы с мета-оркестратором (МО).md` — записка владельца МО 04.10.2026.
2. `<aibok>/agentico/reviews/SDX-MO-interop-reply-2026-10-04.md` — ответ SDX.
3. `<aibok>/agentico/reviews/SDX-MO-interop-review-2026-10-04.md` — разбор ответа, выпуск sim-kit 0.7.3.
4. Для сверки: `<aibok>/agentico/meta-orchestrator/sim-kit/core/MO-INTEROP.md` (0.7.3), `~/Downloads/AIBoK-Overview-1.0-RU.pdf`.
Все — вне репозитория (`PROC-009`); границы разбора — `intake.md` сессии.

**Зачем.** Над стендами систем под SDX появляется МО; sim-kit 0.7.3 выпущен по ответу SDX и уже описывает
плагинную модель интеропа. Бэклог плагина должен содержать поставку и её предпосылку до того, как начнётся
feature-сессия.

**Затронутые файлы.**
- `docs/backlog/FEAT-015-mo-interop-plugin-model.md` — новая.
- `docs/backlog/PROC-028-simkit-vendoring-policy.md` — новая.
- `docs/backlog/FEAT-006-authority-model-risk-classes.md`, `PROC-021-sdx-as-design-time-twin.md`,
  `DEBT-031-lifecycle-stops-at-l5.md` — раздел `## Уточнения разбора`, атрибуты frontmatter не тронуты.
- `docs/backlog/README.md` — две строки в «Открытые».
- `.claude/sessions/intake-mo-interop-aibok-20261004/intake.md` — документ разбора (на Closeout →
  `docs/history/intake/`).

**Решения.**
- Отдельная запись «ADR-отображение SDX ↔ AIBoK» не заведена — дубль `PROC-021`; новое дописано туда.
- Пересмотр атрибутов `FEAT-006` не выполнен — зона `grooming`; передан открытым вопросом.
- Входные записки в репозиторий не копировались (приватные пути `aibok`/MOVE.IO); ссылки путями, адрес для
  входа — `PROC-009`.

**Круг 2 (после fresh-eyes круга 1: 0 FAIL / 12 WARN, все приняты к исправлению — `decisions_log.md`).**
Правки: `FEAT-015` п.2 (bash-обёртка вместо голого `python3`; ADR-013 вместо `PROC-020`; настоящая связь с
`PROC-020`), п.7 (`directive` — не `[контракт]`; выбор между восьмым тегом и откладыванием; «в этой же сессии» →
открытый вопрос 5), п.8 (`prod-guard` fail-closed только при настроенной защите; «второй PEP, не граница»),
критерии приёмки, «Зависимости» (пин по `VERSION`+sha256; `IDEA-002`/`FEAT-007` без натяжки; `DEBT-031`),
определение `exec_paths`; `PROC-028` (priority → high как условие входа; `DEBT-006` вместо `DEBT-005`; исключение
из ADR-013 названо; sha256 вместо `RELEASES`; `PROC-020`; без тега `[контракт]`); три раздела «Уточнения разбора»
(строка о `PROC-022`; оговорки «Зависимости и порядок не пересматриваются» / «посылка не снимается»);
`README.md` (строка `PROC-028` в группе high); `intake.md` (относительные пути, приоритет, скоуп); этот файл (вход).

**Проверка для Verification (ось когерентности, трёхсторонне).** Новые записи не противоречат существующим:
`FEAT-015` ↔ `FEAT-007` (частный случай inbox), `IDEA-002` (внешний fanout), `PROC-020` (хук из установленной
копии); `PROC-028` ↔ `DEBT-005`/ADR-008 (версия в одном месте), `PROC-027` (сторож инвентаря). Тип `intake`
не подменил `grooming` (frontmatter существующих записей без изменений — проверяемо `git diff` по строкам `^[a-z]+:`).
