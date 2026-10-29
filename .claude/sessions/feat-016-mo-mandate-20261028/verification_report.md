# Verification Report: feat-016-mo-mandate-20261028 (круг 3, fresh-eyes)

## Сводка
- Объём: полный (SPEC/DESIGN/PLAN), no_code: нет, no_gates: нет
- Вход: SPEC.md (с «Поправками по коллизиям DESIGN», круги 1–2), DESIGN.md, PLAN.md, decisions_log.md, qa_report.md, delivery.diff (против main, без каталога сессии); эталон `sdx/mo/MO-INTEROP.md` §7, `sdx/mo/devagent_hook.py`, `sim-kit/core/dev.py`; нормы — protocol.md, DECISIONS.md, docs/specs|designs/mo-interop.md, CLAUDE.md, README×2, бэклог FEAT-016.
- Итог: **FAIL**
- Находки: FAIL: 1, WARN: 4, INFO: 5
- По осям:
  - **Полнота** — OK. У всех REQ-MAND-1…33 (вкл. 11a, 23a, 23b) и критериев 1–21 есть реализация в diff и видимое тестовое покрытие (автотест или grep-инвариант); ручные части (критерии 3-канал, 14-Л, 16-проза, 21) честно помечены «НЕ ПРОВЕРЕНО»/процесс. Scope creep нет; мелкие расширения сверх DESIGN записаны в PLAN «Отклонения» (INFO-1).
  - **Корректность** — OK по коду: гейт стадий, `start-stage`/`active-set`, `mandate-scope.sh`, `closeout-mode` (`bridge`/`bridge:offer`/`undefined:*`/`error:*`), `MAND-MODE2` + `MAND-PYYAML`, охрана `mandate.yaml`, `suites-gen.sh` (форма вызова как у stop-gate) соответствуют SPEC с поправками; у новых ветвлений есть красные стороны. Отрицательные инварианты `[12b]` различают, но узко (WARN-2).
  - **Когерентность** — FAIL: нормативные поставляемые носители (протокол, ADR-020/021, README×2, CLAUDE.md, `archive.md`, `next.md`, `devops.md`, дельты `docs/specs|designs`, бэклог FEAT-016) по мосту Closeout и однократному офферу согласованы; но сессионные носители-контракт и носители, которые уйдут в постоянные документы на Closeout (DESIGN.md, MANUAL_TEST.md, release_notes_draft.md), сохраняют старые формулировки, прямо противоречащие коду (FAIL-1). Плюс дрейф «вместо пакета» для `bridge:offer` (WARN-1).
- Проверено отдельно по постановке: (1) FAIL-1/WARN-1 круга 2 закрыты во всех нормативных носителях diff — да; в сессионных — нет (FAIL-1). (2) `[12b]` красная сторона есть для `archive.md`/`protocol.md` (offer-once) и для шести носителей (stale-фраза); для `devops.md` красной стороны нет (WARN-2). (3) Отображение стадий, Verification/Closeout всегда, Deployment исключён, два режима `on_write` + PyYAML при `deny` из мандата, охрана `mandate.yaml`, предупреждения по каталогам, `docs_in_repo`/`--planned`, форма `cmd` — согласованы в поставке (исключения — WARN-1, WARN-3). (4) Обратная совместимость: без `mandate.yaml` новые ветки за предикатом «оба файла»; названные исключения (suites.yaml, status/сниппет, К-4, usage-строка К-10) задокументированы; правки прежних сьютов — только фикстурные строки (не утверждения). (5) Номер вендорённой версии (`0.9.0`/`0.9.1`) в `sdx/protocol.md` и `docs/DECISIONS.md` отсутствует (grep пуст). (6) Полнота в обе стороны — OK.

Покрытие ниже — **видимое** (выведено из чтения diff и qa_report), а не доказательство исполнением.

## Матрица трассируемости
| Требование / критерий | Реализация (файл) | Тест | Когерентность | Статус |
|---|---|---|---|---|
| REQ-MAND-1, 15, 31 / кр.1 (без мандата как 2.3.x) | `sdx-stage.sh` `_mandate_try` (предикат «оба файла», ленивый source); `mo-hook.sh` MAND-MODE2/PYYAML за `-f`; `mo-session.sh` `mnote`/`mand_show`; `mandate-scope.sh` ранний `exit 0` | `test-sdx-stage [M30]`, прежние [1]–[32] без правок утверждений; `test-mo-session` сц.1–9; `test-mandate-scope (1)` | дрейф формулировки «как 2.3.x» в протоколе (WARN-3) | WARN |
| REQ-MAND-2, 3 / кр.2 (два файла; orphan) | `lib/mandate.sh` `mandate_mode`, `mandate_orphan_line`; `mo-session.sh` MAND-ORPHAN; `mandate-info.sh show` | `L7`, `test-mo-session [10]` + мутанты `no-orphan`/`orphan-two-lines`, `[M30]` | ok | OK |
| REQ-MAND-4 (+К-2) / кр.3 | `mandate_report`, `mo-session.sh` `mand_show` (вкл. вырожденную ветку) | `test-mo-session [11][12]`, `L8` + мутанты | ok (DESIGN :284/:473 устарел — FAIL-1) | OK |
| REQ-MAND-5, 6 (К-1), 7 / кр.4 | `commands/start.md` 1а; `mandate_report` предупреждения по каждому каталогу, срок | `L8`/`L8w`, `[M] show`, `test-mo-prose [14]` | ok | OK |
| REQ-MAND-8, 9 / кр.5 | `mandate_stage_allowed` (always/never), `is_skipped` MAND-SKIP | `L4`, `[M31][M32][M33][M36]`, мутанты `MAND-NEVER/ALWAYS/SKIP/EXCL` | ok | OK |
| REQ-MAND-9 (оффер один раз, ДЛ-1) | проза: протокол «Deployment под МО», «Мост Closeout»; `archive.md` 2а; `next.md`; `devops.md`; CLAUDE.md §3; ADR-020 | `test-mo-prose [12b]` (archive/protocol/devops) | поставка ok; DESIGN :290/:545, release notes — старое (FAIL-1) | FAIL (через FAIL-1) |
| REQ-MAND-10 / кр.7 | `lib/miniyaml.sh`, `mandate_load` | `L1`–`L3`, `L2` паритет `safe_load`, `[M35]` | граница F1 названа в SPEC/протоколе/дельте | OK |
| REQ-MAND-11 / кр.6, 8 | `sdx-stage.sh` MAND-TO, init-проверка, `cmd_start_stage` | `[M32][M34][M37][M38]`, мутант `MAND-TO` | ok | OK |
| REQ-MAND-11a, 28 | ADR-020/021 поправки 2026-10-28; протокол «Активность этапа» | `test-mo-prose [15][16]` | ok | OK |
| REQ-MAND-12, 13, 14 / кр.9, 10 | `mandate-scope.sh`, `mandate_glob_one` (формула `dev.py:69`), `--planned`; `verify.md` 6а | `test-mandate-scope (1)–(10)`, `L5` (42 случая + оракул), мутанты; `[18]` правило `--planned` | ok | OK |
| REQ-MAND-16 (+PyYAML при deny из мандата) / кр.11 | `mo-hook.sh` MAND-MODE2, MAND-PYYAML | `[2m]`, `[2y]`, `[8i]`, мутанты `MAND-MODE2`, `MAND-PYYAML` | ok (протокол, ADR-021 п.6, дельты) | OK |
| REQ-MAND-17 (+К-4) / кр.12 | `is_mailbox_file` 3-й параметр, MO-GUARD-MANDATE | `[7m]`, мутанты `MAND-GUARD-MANDATE`, `MAND-NAME` | ok | OK |
| REQ-MAND-18–21 (+поправка формы cmd) / кр.13, 14 | `lib/test-cmd.sh` (SG-EXEC/SG-BASH), `suites-gen.sh`, `tests/suites.yaml` (`./.claude/sdx/verify-cmd.sh`), `init.md` 2в, `reconcile.md` (е) | `test-suites-gen` (1)–(10), близнец stop-gate, мутанты `SG-*`; `[18]`; live `run_suites` — НЕ ПРОВЕРЕНО | формат совпадает с `dev.py run_suites` (стр. 292–308); DESIGN :198/:347/:363/:416 устарел (FAIL-1) | OK |
| REQ-MAND-22 / кр.15 | `agents/devops.md` подпункт «Мандат», п.3 | `test-mo-prose [10]` | ok | OK |
| REQ-MAND-23, 23a, 23b (+поправки кругов 1–2) / кр.16 | `mandate-info.sh closeout-mode/closeout-check`; `archive.md` 2а; протокол «Мост Closeout» | `[M]` (`cm offer → bridge:offer`, мутант `MAND-BRIDGE`), `test-mo-prose [12][12b]` | поставка ok, кроме «вместо пакета» (WARN-1); DESIGN/MANUAL_TEST/release notes — старое (FAIL-1) | FAIL (через FAIL-1) |
| REQ-MAND-24, 25 / кр.17 | сниппет; `snippet-check.sh`; `reconcile.md` (ж) | `test-snippet-check`, `test-mo-prose [11][18]` | ok | OK |
| REQ-MAND-26 / кр.18 | `mandate-info.sh status`, `active-set` (`unknown:mandate`), `status.md` 5а | `[M39][M40]`, `[M] status`, `[18]` | ok | OK |
| REQ-MAND-27, 29 / кр.19 | протокол, README×2, CLAUDE.md, ADR-021 п.3, дельты, бэклог FEAT-016 | `test-mo-prose [9]`, `test-mo-inventory` | ok | OK |
| REQ-MAND-30 | `plugin.json` 2.4.0 (в `marketplace.json` версии нет) | `[17]` | релизные заметки — черновик устарел (FAIL-1) | OK (код) |
| REQ-MAND-32, 33 / кр.20 | комментарий `verify-cmd.sh`; без python в `sdx-stage.sh`/lib; `sdx/mo/*` не в diff | `L9`, полный прогон 114–124 с < 180 с (qa) | ok | OK |
| Кр.21 (не auto) | процесс | `gate_mode: interactive` (qa) | ok | OK |

## Находки

### [FAIL] [Когерентность] Сессионные носители не синхронизированы с поправками кругов 1–2: мост Closeout для `artifact.offer`, однократный оффер, форма `cmd`
- Где (старые формулировки, противоречащие коду и поправкам SPEC):
  - `DESIGN.md:418` — тест-спецификация `[M]`: «`closeout-mode` (`standard` без мандата **и при `artifact.offer`**…)», «Мутанты: `MAND-BRIDGE` (`bridge` и при `artifact.offer`)». Код (`mandate-info.sh:1126`) возвращает `bridge:offer`, тест (`test-mandate-scope.sh:364`) утверждает `bridge:offer`, мутант заменяет `bridge:offer` на `standard` — смысл инвертирован. Пометка круга 2 стоит только у D-8 (:22) и таблицы (:162).
  - `DESIGN.md:290` — «при мандате `artifact.offer` отправляется на `Execution`/`Verification` (ДЛ-1)» (описание `next.md`); `DESIGN.md:545` — перечень правок протокола: «`artifact.offer` — на `Execution`/`Verification`»; `DESIGN.md:292` — ветки `archive.md` только `standard`/`bridge`/`undefined`, без `bridge:offer`; `DESIGN.md:476` К-5 — «`artifact.offer` — штатный Closeout по SPEC».
  - `DESIGN.md:198, :347, :363, :416` — `TC_CMD`/dogfood/сценарий (1)(8) и мутант `SG-BASH` «`cmd: bash .claude/sdx/verify-cmd.sh`» безусловно; поправка SPEC REQ-MAND-18/19 и код (`lib/test-cmd.sh:1022`, `tests/suites.yaml:9` — `./.claude/sdx/verify-cmd.sh`) другие. Аналогично `DESIGN.md:284` (суффикс `mnote` «не прочитан») и `:473` (К-2 «следовать SPEC») против принятой К-2 и кода (`mo-session.sh`: «читается без python3 и показан ниже»).
  - `MANUAL_TEST.md:67` (случай 4) — «При `delivery: artifact.offer` чек-лист штатный». По `decisions_log` (2026-10-29 `[ручной-шаг]`) сценарий сохраняется в `docs/history/experiments/` — уйдёт в постоянные документы с неверным ожидаемым результатом.
  - `release_notes_draft.md:11` / `:38` (RU/EN) — «до `/sdx:pr` при `delivery: pr|branch` … При `artifact.offer` Closeout штатный» / «With `artifact.offer` Closeout is the standard one». Черновик публикуется на Closeout (C3) — неверное пользовательское утверждение о поведении 2.4.0.
- Суть: круг 2 (FAIL-1/WARN-1) закрыт в нормативных поставляемых файлах, но DESIGN (контракт триады; по дельте `docs/designs/mo-interop.md` — «полный дизайн» после Closeout) и два носителя, которые на Closeout станут постоянными/публичными, утверждают обратное коду. Прямое противоречие DESIGN ↔ Codebase.
- Ожидалось: в каждом месте — датированная пометка «(верификация круг 1/2, 2026-10-29: …)» или правка текста по поправкам SPEC (REQ-MAND-9/ДЛ-1, REQ-MAND-23, критерий 16, REQ-MAND-18/19, К-2); `MANUAL_TEST.md` случай 4 — ожидание `bridge:offer`/мост для любого `delivery`; релизные заметки RU/EN — «мост при любом определённом `delivery`, для `artifact.offer` — шаг отправки оффера один раз».
- Фактически: старые формулировки без пометок.

### [WARN] [Когерентность] `bridge:offer`: «вместо ручной сборки пакета» в `archive.md` против «шаг добавляется» / «ручная сборка пакета при любом `delivery`» в остальных носителях
- Где: `commands/archive.md` 2а («При `bridge:offer` … **вместо** ручной сборки пакета добавь шаг отправки оффера»); против SPEC поправка REQ-MAND-23 («`archive.md` **добавляет** шаг отправки»), протокол «Мост Closeout» (шаг отправки «добавляется к шагам 1–5», следующее предложение о пакете `change/<C>-<exec>` без оговорки), ADR-021 поправка п.5 и дельта `docs/designs/mo-interop.md` («Мост Closeout при любом определённом `delivery` … — ручная сборка пакета до `/sdx:pr`»).
- Суть: исполняемая инструкция и нормы расходятся в том, собирается ли пакет `change/<C>-<exec>` при `artifact.offer`.
- Ожидалось: одна формулировка во всех носителях (по смыслу `archive.md` — при `bridge:offer` пакет не собирается, отправляется оффер — нормы уточнить; либо наоборот).

### [WARN] [Корректность] Инварианты `[12b]` различают, но узко
- Где: `sdx/hooks/test-mo-prose.sh:3242–3251, 3366–3377` (diff).
- Суть: (а) `chk_offer_once_devops` вызывается только `expect_ok`, красной стороны для `devops.md` нет (у `archive.md`/`protocol.md` есть — sed `уже отправлен`→`zz-removed`); (б) однократность оффера не закреплена для `CLAUDE.md` §3, `commands/next.md`, ADR-020, бэклога FEAT-016 — носителей, где формулировка тоже менялась; (в) отрицательный инвариант ловит только литерал `delivery: pr|branch` — фразы вида «при `artifact.offer` Closeout штатный» / «`artifact.offer` — штатный» (ровно те, что остались в FAIL-1) им не ловятся; его красная сторона — дописывание того же литерала (по построению красная, проверяет функцию, а не охват).
- Ожидалось: красная сторона для `devops.md`; `chk_offer_once` для `next.md`/`CLAUDE.md`/ADR-020; второй отрицательный шаблон (`artifact\.offer[^|]*штатн`, `standard one`) по нормативным носителям.

### [WARN] [Когерентность] «Без `mandate.yaml` — как 2.3.x» в протоколе и README без оговорки К-4
- Где: `sdx/protocol.md` «МО-хук» (абзац признаков: «без `mandate.yaml` всё, что описано в этом подразделе, — как в 2.3.x»), тот же подраздел ниже: охрана `mandate.yaml` «безусловна при наличии `endpoint.yaml`»; `README.md`/`README.en.md` «без `mandate.yaml` поведение прежнее» / «behavior is unchanged».
- Суть: при `endpoint.yaml` без мандата `Write` в `.mesh/mandate.yaml` теперь блокируется (К-4, третье названное исключение REQ-MAND-1) — протокол в одном абзаце утверждает и «как 2.3.x», и новое поведение; README исключения не называют (дельта `docs/specs` называет все).
- Ожидалось: «как в 2.3.x, кроме безусловной охраны `mandate.yaml` (К-4)» в протоколе; в README — «кроме названных исключений».

### [WARN] [Когерентность] Тела REQ-MAND-23 и критерия 16 в SPEC не помечены как заменённые
- Где: `SPEC.md:70` (заголовок «только `delivery: pr|branch`», «При `delivery: artifact.offer` … Closeout — штатный»), `SPEC.md:110` (критерий 16 «при `artifact.offer` … Closeout штатный»).
- Суть: замена есть только в разделе «Поправки» (:171, :173); REQ-MAND-9 при этом исправлен в теле с пометкой. Читатель тела (и перенос SPEC в `docs/history/` на Closeout) видит противоречие без отсылки. Дельта `docs/specs/mo-interop.md` уже корректна.
- Ожидалось: в теле REQ-MAND-23 и критерия 16 — отсылка «см. Поправки (круг 1 WARN-1 / круг 2 FAIL-1)».

### [INFO] [Полнота] Решения сверх DESIGN, записанные только в PLAN «Отклонения»
- `closeout-check` исключает `.mesh/` из проверки чистоты дерева (`mandate-info.sh:1146`; PLAN откл. 9) — в протоколе/`archive.md` сказано «дерево чистое» без оговорки; `mand_show` и при отказе `pull`; `active-set` → `unknown:mandate` (в `status.md` описано). Не противоречие, но нормативные тексты не называют `.mesh`-исключение.

### [INFO] [Когерентность] DESIGN «Обратная совместимость», строка «команды»
- `DESIGN.md:456`: «`start-stage` без мандата возвращает входной этап (если он не исключён `no_code`/`no_gates`, иначе — прежний отказ делает `init`)»; фактически `cmd_start_stage` идёт вперёд мимо `no_code`-исключённого этапа (и протокол так и описывает). На путях `start.md`/`import.md` не проявляется (`no_code`-типы стартуют с `Discovery`).

### [INFO] [Когерентность] Протокол «Область на `/sdx:verify`» не упоминает исключение `docs_in_repo: none` из `--planned`
- Правило есть в `commands/verify.md` 6а и закреплено `[18]`; протокол перечисляет переносы без этой оговорки. Отсылки достаточно.

### [INFO] [Корректность] Дефолт `docs_paths`
- `dev.py:384` берёт `sc.docs_paths or policy().docs_paths or ["docs/**"]`; SDX при пустом/отсутствующем — сразу `docs/**`. Узел при выдаче всегда проставляет `docs_paths` (`dev.py:529`), практическое расхождение — только на рукописном мандате.

### [INFO] [Процесс] PLAN и decisions_log хранят старые формулировки как историю
- `PLAN.md:109, :262, :459` (T12, T33, строка критерия 16), `decisions_log.md:3` — исторические записи, заменены последующими записями/«Отклонениями»; находкой не считаются.
