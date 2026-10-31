---
id: DEBT-050
type: debt
status: open
priority: normal
wave: null
source: session (sdx/feat-017-mo-change-package-20261031), Verification 2026-10-31
session: null
links: [FEAT-017, PROC-028, FEAT-018]
---

# DEBT-050. Дрейф эталона: sim-kit 0.9.3 добавил проверки `audit()`, которых нет в зеркале `pr-check` (вендорён тег 0.9.1)

## Суть
`sdx/hooks/pr-check.sh` зеркалит формальные проверки `dev.py audit()` вендорённой версии (см. `SIMKIT_VERSION`). Рабочая копия
sim-kit на 2026-10-31 — 0.9.3: в `audit()` появились `docs_in_repo.none` (документы в пакете при `none` → `return`),
`docs_in_repo.work`/`work_paths`, требование `adr` и при `full`. На `docs_in_repo: none` с документами в пакете `pr-check`
даёт PASS, узел ≥ 0.9.2 вернёт пакет. По SPEC поведение верное (эталон — вендорённая версия), но при первом пилоте узел будет
новее плагина.

## Рекомендация
Перевендорить тег 0.9.3 по PROC-028 (отдельная сессия: `mesh_endpoint.py`, `devagent_hook.py`, `MO-INTEROP.md`,
`CHANGE.template.yaml`) и дополнить `pr-check` зеркалом новых проверок с красными сторонами (`pkg_craft_bad_*` в
`lib/pkg-fixture.sh`, оракул `pkg_oracle` обновить по `audit()` 0.9.3).
