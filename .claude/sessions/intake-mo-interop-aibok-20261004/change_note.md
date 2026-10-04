# change_note — intake-mo-interop-aibok-20261004

**Что.** Разбор трёх записок об интеропе SDX ↔ мета-оркестратор (МО) и обзора AIBoK 1.0 в записи бэклога
(`no_code`: Discovery-lite → Business Spec/Technical Design свёрнуты сюда → Verification → Closeout).

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

**Проверка для Verification (ось когерентности, трёхсторонне).** Новые записи не противоречат существующим:
`FEAT-015` ↔ `FEAT-007` (частный случай inbox), `IDEA-002` (внешний fanout), `PROC-020` (хук из установленной
копии); `PROC-028` ↔ `DEBT-005`/ADR-008 (версия в одном месте), `PROC-027` (сторож инвентаря). Тип `intake`
не подменил `grooming` (frontmatter существующих записей без изменений — проверяемо `git diff` по строкам `^[a-z]+:`).
