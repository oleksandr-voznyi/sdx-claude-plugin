---
id: FEAT-017
type: feat
status: closed
priority: high
wave: null
source: intake intake-mo-dev-control-20261028 (записка владельца МО `SDX-MO-dev-control-note-2026-10-26.md` §2.2, §2.3, §2.10, §2.11; ответ SDX `SDX-MO-dev-control-reply-2026-10-28.md` §2; sim-kit 0.9.0 `CHANGE.template.yaml`, `core/dev.py audit()`, `policy/dev.yaml`; отзыв MOVE.IO `MOVEIO-dev-control-reply-2026-10-26.md` §2.2)
session: feat-017-mo-change-package-20261031
links: [FEAT-016, FEAT-018, FEAT-015, PROC-028, PROC-019, ADR-012, ADR-009]
---

# FEAT-017. Сдача пакетом изменения (плагин 2.5.0): `/sdx:pr` как второй вариант Closeout, `CHANGE.yaml`, экспорт `protocol.yaml`, `--from-order`

## Суть
Под мандатом МО исполнитель не сливает в `main`: он сдаёт **пакет изменения** — ветку `change/<C>-<executor>` с манифестом
`CHANGE.yaml` (формат 1: `commitment`, `executor`, `mandate_digest`, `base`/`head`, `archive_sha256`, `scope_touched`,
`touches_shared`, `spec`, `verify`, `adr`, `docs`, `history_ref`) **отдельным последним коммитом** поверх головы кода; узел
проверяет его `dev.py audit()` (формат, обязательство, мандат и дайджест, ветка, область, `shared.declared`, сумма архива,
секреты, `adr` изменён в пакете, «контракт раньше кода», наборы тестов, LLM-ревью) и сливает сам (`change.merge`). Заказ
приходит директивой `work.order` в `.mesh/inbox/` или issue хостинга; обязательство `C-…` попадает в имя ветки, коммиты,
манифест. Концепция 0.3 (§2.10 записки) добавляет `protocol.yaml` сессии (`done`, `decisions[] {id, what, why, alternatives,
adr}`, `questions[]`, `verified[]`, `deltas[]`), чьи записи `adr: true` выводятся в реестр решений проекта.

Позиция SDX (ответная записка §2): `/sdx:pr` — **второй вариант Closeout**, не параллельный механизм. Шаги 1–5 чек-листа
(коммиты, перенос дельт по `docs_in_repo`, архив плана, бэклог, `git rm -r` каталога сессии) — те же; вместо шага 6
«мёрж в main» — squash ветки `sdx/<sid>` без каталога сессии в `change/<C>-<exec>` + коммит манифеста. `protocol.yaml` —
**экспорт** существующих журналов (`decisions_log.md` → `decisions[]`, `verification_report.md` → `verified[]`,
`change_note.md`/`SPEC.md` → `deltas[]`, заданные вопросы → `questions[]`), не новый артефакт: триада и `PROC-019` остаются
единственным источником. `--work-dir` не вводится: состояние сессии не покидает клон узла по построению (ADR-012).

## Рекомендация
Feature-сессия после `FEAT-016` и после ответа владельца МО на §5 ответной записки (префикс `change/`, словарь стадий,
`docs/DECISIONS.md` в `docs_paths`, хостинг пилота). Состав:

1. **`/sdx:pr`** (`commands/pr.md`): требует `mandate.yaml` с `delivery: pr|branch`; чек-лист Closeout шаги 1–5 →
   `archive-verify`-аналог для пакета (дерево чистое, каталога сессии нет, `diff ⊆ scope`, stop-gate зелёный) →
   `git checkout -b change/<C>-<exec> <base>` + squash → сборка `CHANGE.yaml` из шаблона → отдельный коммит манифеста →
   push и PR через `gh` (GitHub); без хостинга (`bare`) — только ветка + манифест. `archive_sha256 = sha256(git archive
   --format=tar <head>)`, `scope_touched` = `git diff --name-only base..head` включая сгенерированное, `touches_shared` по
   `shared_paths`, `adr` — файл реестра, изменённый в пакете (`docs/DECISIONS.md` SDX), `history_ref: executor:sdx/<sid>`.
   `artifact.offer` (П1) получает поле `change` с тем же манифестом.
2. **Экспорт `protocol.yaml`** в каталог сессии на Closeout/`/sdx:pr` из `decisions_log.md` (восемь тегов → `decisions[]`,
   `adr: true` для записей, перенесённых в `docs/DECISIONS.md`), `verification_report.md`, `change_note.md`/`SPEC.md`;
   `questions[]` — из вопросов, заданных пользователю (`AskUserQuestion`) по журналу. Файл уезжает с каталогом сессии
   (`history: mo` — остаётся в клоне узла).
3. **`/sdx:start --from-order <order.yaml>`** и `--from-issue <N>` (`gh issue view`): цель, требования, область, срок,
   способ сдачи — из заказа; `commitment` в `session_state.json`, имя ветки сессии и коммиты; показ `scope` на старте.
4. **`CHANGE.template.yaml`** — четвёртый вендорённый файл `sdx/mo/` (`PROC-028`: хеш в `SIMKIT_SHA256`, сторож
   инвентаря); **`sdx/mo/CONTRIBUTING-MO.md`** — текст SDX «как сдать изменение» для чужих харнесов (П5), нейтральный к
   инструменту.
5. **`docs_in_repo`** на Closeout/`/sdx:pr`: `full` — перенос дельт как сейчас; `final` — только в `docs_paths` мандата
   (документация модуля и реестр решений); `none` — перенос пропускается, дельты остаются в `protocol.yaml` сессии.
6. **Документы/протокол**: Closeout-контракт с двумя вариантами (мёрж / пакет); ADR о пакете как втором варианте
   Closeout (п.1 снимает мост `FEAT-016` п.7); абзац сниппета — полный текст §2.6 записки (замена временного предложения
   `FEAT-016` п.8); `agents/devops.md`; README.

Критерии приёмки: пакет, собранный `/sdx:pr` в фикстурном репозитории, проходит `dev.py audit()` локальной копии sim-kit
0.9.0 без `reject`/`return` по формальным проверкам (формат, манифест-коммит, область, `archive_sha256`, `adr`);
`protocol.yaml` валиден по схеме концепции; при `docs_in_repo: final` в пакете нет файлов вне `docs_paths` среди документов;
без мандата команда отказывает одной строкой.

## Уточнения по итогам проектирования (сессия `feat-017-mo-change-package-20261031`, 2026-10-31)
- `CONTRIBUTING-MO.md` живёт в `sdx/templates/`, а не в `sdx/mo/` (собственный текст SDX, не вендорённый файл).
- Поле `change` в `artifact.offer` **не добавляется**: узел его не читает (вопрос владельцу МО — записка upstream, К-18).
- `docs_in_repo: final` трактуется как `full`; реестр решений проверяется по `docs_paths`.
- `protocol.yaml` до узла командой не доставляется; при `history: executor` канал вне SDX.
- `status` записи (`closed`, `session`) выставляется на Closeout (C2), не здесь.

## Резолюция
Закрыта сессией `feat-017-mo-change-package-20261031` (2026-10-31), плагин 2.5.0. Поставлено: `/sdx:pr` — второй вариант
Closeout (шаги 1–4 → экспорт `protocol.yaml` → шаг 5 → squash в `change/<C>-<exec>` от `base` → `CHANGE.yaml` plumbing-коммитом
без записи в рабочее дерево → `pr-check` pre/post (зеркало формальных проверок `audit()`) → подтверждение → `pr-publish`
(только явный refspec `change/*`, без force, prod-guard, пост-проверка до сети; `bare` — ветка + манифест, `github` — `gh pr
create`, без `gh` — деградация); экспорт `protocol.yaml` (пять списков, оба формата журнала); `/sdx:start --from-order
<файл|msg_id>` и `--from-issue <N>` (снимок показывается целиком и подтверждается, повторного чтения нет; `commitment` в
`session_state.json`); `docs_in_repo` (`none` → переносы n/a; `final` = `full`); вендоринг `CHANGE.template.yaml` (К-1 —
датированное отступление от PROC-028), `sdx/templates/CONTRIBUTING-MO.md`; классификация Closeout «мёрж / пакет / мост /
undefined» в шести носителях; ADR-022; `.claude/sdx/verify-cmd.sh` с параллельным раннером (`SDX_VERIFY_JOBS`). Отклонения от
записи: п.1 — `artifact.offer` без поля `change` (узел его игнорирует); повторная сдача при ушедшей базе — `head` с двумя
родителями (merge-коммит, не squash; `merge-base(head, dev)` = новая база); п.2 — доставка `protocol.yaml` узлу при `history:
executor` — вне SDX (upstream-записка). Не проверено исполнением (`DEBT-051`): живой `audit()` узла, `gh` на GitHub, хук при
`deny` на команды `/sdx:pr`, `archive_sha256` между версиями git, реальный `pull` ящика. Риск дрейфа эталона (`DEBT-050`):
sim-kit уже 0.9.3 с новыми проверками `audit()`.
