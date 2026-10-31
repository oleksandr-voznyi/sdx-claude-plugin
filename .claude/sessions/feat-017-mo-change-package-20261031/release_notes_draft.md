# Релизные заметки v2.5.0 (черновик, не опубликован)

> Накопительные заметки 2.5.0 (предыдущий выпуск 2.4.0 опубликован); публикация — по явной просьбе (практика репозитория), итоговый файл — `docs/history/releases/v2.5.0-notes.md` на Closeout. Подготовлено сессией `feat-017-mo-change-package-20261031`.

Релиз 2.5.0 за 2026-10-30 … 2026-10-31: сдача изменения пакетом под мандатом МО. Команда `/sdx:pr` заменяет ручной мост Closeout для `delivery: pr|branch` и становится вторым вариантом Closeout («мёрж» / «пакет»).

### Что изменилось

- **`/sdx:pr` — пакет изменения (FEAT-017, ADR-022).** В режиме мандата с `delivery: pr|branch` те же шаги 1–5 чек-листа Closeout, а вместо слияния в основную ветку собирается ветка `change/<C>-<executor>`: один squash-коммит кода и отдельный последний коммит с корневым `CHANGE.yaml` (по вендорённому `CHANGE.template.yaml`). Сборка — чистый git-plumbing: рабочее дерево, индекс и ветка `sdx/<id>` не трогаются, ветка пишется одним `update-ref` с проверкой старого значения; повторная сдача — fast-forward-цепочка, без `--force`; если за это время база ушла вперёд, новый `head` получает два родителя (прежняя вершина и новая база), так что `merge-base(head, dev)` равен новой базе, а между `head` и вершиной остаётся только `CHANGE.yaml` (в этом случае `head` — merge-коммит, а не squash; узел сливает его через `merge --squash`).
- **Проверка перед публикацией.** `pr-check.sh` (фазы `pre`/`post`) зеркалит формальные проверки `audit()` узла (`manifest.commit`, `scope`, `archive_sha256`, `adr`, `branch`, `mandate.valid`); `FAIL` блокирует push, `WARN` требует подтверждения.
- **Публикация.** `pr-publish.sh` отправляет только явный refspec ветки `change/*` после подтверждения пользователя **в любом `gate_mode`**; перед сетью скрипт сам запускает `pr-check --phase post --no-tests` (`FAIL` — отказ без push); `github` — push и `gh pr create`, при деградации (нет `gh`/авторизации, сбой `gh`) — push и одна строка инструкции; на `bare` инструкции «откройте PR» нет, в JSON-результате поле `ready` (пакет готов: ветка + `CHANGE.yaml`); `sdx/*` на хостинг не уходит. Результат сдачи фиксируется трейлерами `SDX-PR-*` служебного коммита на `sdx/<id>`, виден в `/sdx:status`.
- **`protocol.yaml`.** `protocol-export.sh` строит файл из существующих журналов сессии (читает оба формата записей `decisions_log.md`) по схеме `protocol_check()` узла.
- **Заказ.** `/sdx:start --from-order <файл|msg_id>` и `--from-issue <N>` (`order-import.sh`): `commitment` ложится в необязательное поле `session_state.json` и в снимок `order.yaml`; расхождение `mandate_digest` с локальным мандатом останавливает; `--from-issue` подтверждается пользователем в любом `gate_mode`.
- **`docs_in_repo`.** `none` — переносы в `docs/` отмечаются `(n/a)`; `final` трактуется как `full` (реестр решений проверяется по `docs_paths`).
- **Вендоринг и шаблоны.** `sdx/mo/CHANGE.template.yaml` — четвёртый вендорённый файл того же выпуска (хеш в `SIMKIT_SHA256`, три прежних файла не тронуты). `sdx/templates/CONTRIBUTING-MO.md` — «как сдать пакет» для репозиториев-заказчиков. Абзац сниппета `claude-md-snippet.md` заменён полным текстом §6 `MO-INTEROP.md` (`snippet-check.sh` сообщает `STALE` для проектов со старым блоком, `/sdx:reconcile` предлагает обновление).
- **Документы.** Протокол (два варианта Closeout, токен `bridge` помечен историческим), ADR-022 и поправка к ADR-021, `agents/devops.md`, README ×2, `CLAUDE.md`, дельты `mo-interop`.
- **Безопасность ввода.** `pr_clean` заменяет пробелом C0/C1 (U+0080…U+009F) и U+2028/U+2029 в заголовках и путях; снимок заказа `order.yaml` пишется первым вызовом `order-import.sh --out` из показанного и подтверждённого содержимого (источник — в частности issue — повторно не читается); в `auto` принятые WARN `/sdx:pr` фиксируются только в трейлере `SDX-PR-Ack` и раскрываются перед отправкой.
- **Раннер проверки.** `.claude/sdx/verify-cmd.sh` умеет параллельный запуск сьютов (`SDX_VERIFY_JOBS`, по умолчанию 2 при ≥4 ядрах, `1` — прежний последовательный путь): полный прогон под нагрузкой 192 с → 126,6 с.
- **Исправление.** `sdx-stage.sh`: обратные кавычки в тексте отказа создавали посторонний файл `false` в рабочем каталоге (DEBT-046); регрессионная проверка и мутант добавлены (проверка работает во временном проекте, не в рабочей копии).
- Тест-сьют: 19 → 25 сьютов (новые: `test-pkg-fixture`, `test-pr-build`, `test-pr-check`, `test-pr-publish`, `test-protocol-export`, `test-order-import`). `hooks/hooks.json`, `stop-gate.sh`, `archive-verify.sh`, `agents/reviewer.md` и три прежних файла `sdx/mo/` не изменены.

## Границы

- **Живой `audit()` узла не вызывается и не проверен:** паритет доказан транслитерацией формальных проверок (независимый оракул) и фикстурами; проверка на реальном узле — ручной сценарий сессии.
- **Узел версии 0.9.3 проверяет больше, чем вендорённый эталон (риск Р-1):** живой `audit()` смотрит `docs_in_repo.none/work` и `adr` при `full`; `pr-check` этого пока не зеркалит — перевендоринг и дополнение заведены как DEBT.
- **`gh` на реальном GitHub не проверен:** автотест проверяет argv стаба.
- **`archive_sha256` между версиями git** проверен на одной версии git; расхождение у узла — `reject` с причиной, не порча данных.
- **Хук области (`on_write: deny`) на командные строки `/sdx:pr`** не проверен исполнением; внутренние записи скриптов хуку `PreToolUse` не видны.
- **Канал доставки `protocol.yaml` при `history: executor`** вне SDX (вопрос владельцу МО); при `history: mo` узел читает файл из ветки `sdx/<id>` своего клона.
- **`--from-order` с реальным ящиком** (`mesh_endpoint.py pull`) и `--from-issue` на реальном issue не проверены.
- `gitlab`/`gitea` ведут себя как `bare`; `git merge-tree --write-tree` требует git ≥ 2.38 (иначе расходящаяся ветка не собирается автоматически); разбор заказа — подмножество YAML.
- Поле `change` в `artifact.offer` не добавляется (узел его не читает); headless-режим — FEAT-018.

---

Release 2.5.0, 2026-10-30 … 2026-10-31: delivering a change as a package under an MO mandate. The `/sdx:pr` command replaces the manual Closeout bridge for `delivery: pr|branch` and becomes the second Closeout variant ("merge" / "package").

### What changed

- **`/sdx:pr` — the change package (FEAT-017, ADR-022).** In mandate mode with `delivery: pr|branch` the same Closeout steps 1-5 apply, but instead of merging into the main branch a branch `change/<C>-<executor>` is built: one squash commit of the code and a separate last commit carrying the root `CHANGE.yaml` (following the vendored `CHANGE.template.yaml`). The build is pure git plumbing: the working tree, the index and the `sdx/<id>` branch are never touched, the branch is written by a single `update-ref` with a compare-and-swap on the old value; a re-submission is a fast-forward chain, never `--force`; if the base has moved on meanwhile, the new `head` gets two parents (the previous tip and the new base), so `merge-base(head, dev)` is the new base and only `CHANGE.yaml` lies between `head` and the tip (in that case `head` is a merge commit, not a squash; the node merges it with `merge --squash`).
- **Check before publication.** `pr-check.sh` (phases `pre`/`post`) mirrors the formal checks of the node's `audit()` (`manifest.commit`, `scope`, `archive_sha256`, `adr`, `branch`, `mandate.valid`); `FAIL` blocks the push, `WARN` needs confirmation.
- **Publication.** `pr-publish.sh` pushes only an explicit refspec of a `change/*` branch after the user's confirmation **in any `gate_mode`**; the script itself runs `pr-check --phase post --no-tests` before any network access (`FAIL` — refusal without a push); `github` — push plus `gh pr create`, on degradation (no `gh`/no auth, `gh` failure) — push and one instruction line; on `bare` there is no "open a PR" instruction, the JSON result carries `ready` (the package is ready: branch + `CHANGE.yaml`); `sdx/*` never leaves. The result is recorded in `SDX-PR-*` trailers of a service commit on `sdx/<id>` and shown by `/sdx:status`.
- **`protocol.yaml`.** `protocol-export.sh` builds the file from the existing session journals (it reads both record formats of `decisions_log.md`) following the node's `protocol_check()` schema.
- **Order.** `/sdx:start --from-order <file|msg_id>` and `--from-issue <N>` (`order-import.sh`): `commitment` goes to an optional `session_state.json` field and to the `order.yaml` snapshot; a `mandate_digest` mismatch with the local mandate stops the start; `--from-issue` is confirmed by the user in any `gate_mode`.
- **`docs_in_repo`.** `none` — transfers into `docs/` are marked `(n/a)`; `final` is treated as `full` (the decision registry is checked against `docs_paths`).
- **Vendoring and templates.** `sdx/mo/CHANGE.template.yaml` is the fourth vendored file of the same release (hash in `SIMKIT_SHA256`, the three earlier files untouched). `sdx/templates/CONTRIBUTING-MO.md` is a "how to deliver a package" note for customer repositories. The snippet paragraph of `claude-md-snippet.md` is replaced by the full text of section 6 of `MO-INTEROP.md` (`snippet-check.sh` reports `STALE` for projects with the old block, `/sdx:reconcile` offers the update).
- **Documents.** Protocol (two Closeout variants, the `bridge` token marked historical), ADR-022 and the ADR-021 amendment, `agents/devops.md`, both READMEs, `CLAUDE.md`, the `mo-interop` deltas.
- **Input safety.** `pr_clean` replaces C0/C1 (U+0080..U+009F) and U+2028/U+2029 with a space in titles and paths; the `order.yaml` snapshot is written by the first `order-import.sh --out` call from the content that was shown and confirmed (the source, in particular an issue, is not re-read); in `auto` the WARNs of `/sdx:pr` accepted by default are recorded only in the `SDX-PR-Ack` trailer and disclosed before the push.
- **Verification runner.** `.claude/sdx/verify-cmd.sh` can run suites in parallel (`SDX_VERIFY_JOBS`, default 2 on >=4 cores, `1` is the former sequential path): a full run under load went 192 s -> 126.6 s.
- **Fix.** `sdx-stage.sh`: backticks inside a refusal message created a stray file named `false` in the working directory (DEBT-046); a regression check and a mutant were added (the check runs in a temporary project, not in the working copy).
- Test suite: 19 -> 25 suites (new: `test-pkg-fixture`, `test-pr-build`, `test-pr-check`, `test-pr-publish`, `test-protocol-export`, `test-order-import`). `hooks/hooks.json`, `stop-gate.sh`, `archive-verify.sh`, `agents/reviewer.md` and the three earlier `sdx/mo/` files are unchanged.

## Boundaries

- **The live `audit()` of the node is neither called nor verified:** parity is shown by transliterating the formal checks (an independent oracle) and by fixtures; checking on a real node is a manual scenario of the session.
- **A node of version 0.9.3 checks more than the vendored reference (risk R-1):** the live `audit()` looks at `docs_in_repo.none/work` and `adr` under `full`; `pr-check` does not mirror this yet - re-vendoring and the extension are filed as DEBT.
- **`gh` on a real GitHub is not verified:** the automatic test checks the argv of a stub.
- **`archive_sha256` across git versions** was checked on a single git version; a mismatch on the node is a `reject` with a reason, not data corruption.
- **The scope hook (`on_write: deny`) on `/sdx:pr` command lines** is not verified by execution; internal writes of the scripts are not visible to the `PreToolUse` hook.
- **The delivery channel of `protocol.yaml` with `history: executor`** is outside SDX (a question to the MO owner); with `history: mo` the node reads the file from the `sdx/<id>` branch of its clone.
- **`--from-order` against a real mailbox** (`mesh_endpoint.py pull`) and `--from-issue` on a real issue are not verified.
- `gitlab`/`gitea` behave like `bare`; `git merge-tree --write-tree` needs git >= 2.38 (otherwise a diverged branch is not built automatically); the order is parsed as a YAML subset.
- The `change` field is not added to `artifact.offer` (the node does not read it); the headless mode is FEAT-018.
