---
id: DEBT-051
type: debt
status: open
priority: normal
wave: null
source: session (sdx/feat-017-mo-change-package-20261031), Verification 2026-10-31
session: null
links: [FEAT-017, DEBT-047, DEBT-045, FEAT-018]
---

# DEBT-051. Ручной сценарий сдачи пакетом не выполнен: живой `audit()` узла, `gh` на GitHub, хук при `deny` на команды `/sdx:pr`, `archive_sha256` между версиями git

## Суть
Поставка `FEAT-017` (2.5.0) доказана автотестами (25 сьютов), сквозным QA на фикстуре и python-оракулом `audit()`; восемь
случаев `docs/history/experiments/mo-change-package-manual-test-2026-10-31.md` требуют живого узла МО, реального GitHub или
другой версии git и по решению пользователя 2026-10-31 записаны как **НЕ ПРОВЕРЕНО**: живой `./mo change audit` на пакете
`/sdx:pr`; `gh pr create` на реальном репозитории; поведение вендорённого хука при `mandate.on_write: deny` на командные
строки `/sdx:pr` (git-plumbing); `archive_sha256` между версиями git; реальный `mesh_endpoint.py pull` для `--from-order
<msg_id>`; доставка `protocol.yaml` узлу; поведение модели по `pr.md` в `auto`.

## Рекомендация
Пройти на пилоте `dobro` (сначала `bare`, затем GitHub — ответ владельца МО 28.10) первой живой сдачей; результаты — в тот же
файл эксперимента; расхождения — `BUG-`записями. Закрывать вместе с `DEBT-047`/`DEBT-045`.
