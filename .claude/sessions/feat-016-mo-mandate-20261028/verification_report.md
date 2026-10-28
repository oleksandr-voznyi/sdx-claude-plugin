# Verification Report: feat-016-mo-mandate-20261028 (круг 2, fresh-eyes)

## Сводка
- Объём: полный (SPEC/DESIGN/PLAN), no_code: нет, no_gates: нет
- Итог: **FAIL**
- Находки: FAIL: 1, WARN: 1, INFO: 9
- Вход: `SPEC.md` (с разделом «Поправки по коллизиям DESIGN», включая поправки круга 1), `DESIGN.md` (раздел «Компоненты» местами устарел — это известно), `PLAN.md` (в т.ч. «Круг 1 верификации»), `decisions_log.md`, `qa_report.md`, `delivery.diff` (40 файлов), эталон `sdx/mo/devagent_hook.py` и `sim-kit/core/dev.py` (`glob_any`, `run_suites`, `worktree`, `DELIVERY/HISTORY/DOCS`).
- Тесты я не запускал (у меня нет `Bash`). Покрытие в отчёте — **видимое** (выведено из чтения diff), а не доказанное прогоном. Опираюсь на зелёный прогон QA круга 1 (19/19).

### Сводка по осям
| Ось | Итог | Коротко |
|---|---|---|
| Полнота | OK, с замечаниями (INFO) | У всех REQ-MAND-1…33, 11a, 23a/23b видна реализация и автотест либо grep-инвариант. Ручная часть (критерии 3-канал, 7-реальный дамп, 14-Л, 16-живая проза) по решению пользователя отмечена «НЕ ПРОВЕРЕНО» (INFO-1). Scope creep существенного нет. |
| Корректность | OK, с одним WARN | FAIL круга 1 (PyYAML при `deny` из мандата) закрыт по существу, тест и мутант есть. Форма `cmd` в `tests/suites.yaml` для `run_suites` корректна при допущении о бите исполнения (INFO-2). Под мандатом не определено, в какой момент отправлять `artifact.offer` (WARN-1). |
| Когерентность | **FAIL** | Решение пользователя от 2026-10-29 «мост Closeout для любого `delivery`» дошло до кода, `archive.md`, контракта закрытия в протоколе, `devops.md` и дельт `docs/specs|designs`. В ADR-021 (поправка, п.5), в абзаце протокола «Три слоя», в README×2, в критерии 16 SPEC и в DESIGN по-прежнему стоит «мост при `pr|branch`», а в DESIGN и критерии 16 — «при `artifact.offer` Closeout штатный» (FAIL-1). |

### Закрытие находок круга 1 (проверено по diff)
| Находка круга 1 | Статус | Доказательство в diff |
|---|---|---|
| FAIL: `deny` из мандата при python3 без PyYAML | **закрыт** | `mo-hook.sh` `# MAND-PYYAML` (сам отдаёт JSON deny); `test-mo-hook.sh` `[2y]` a–d (a — красный без фикса, b/c — регресс, d — контроль) и мутант `MAND-PYYAML`; протокол («Политики отказа», абзац о `mo-hook`), ADR-021 поправка п.(6), дельты `docs/specs|designs` |
| WARN-1: мост при `artifact.offer` | **закрыт частично** | Код `closeout-mode` → `bridge:offer`, тест `cm offer`, мутант `MAND-BRIDGE`; `archive.md` 2а, протокол «Контракт закрытия», `devops.md`, `[12]` с `bridge:offer`. Не исправлены ADR-021, протокол «Три слоя», README×2, критерий 16 SPEC, DESIGN → **FAIL-1** |
| WARN-2: форма вызова раннера | **закрыт** | `lib/test-cmd.sh` (`# SG-EXEC`/`# SG-BASH`); `test-suites-gen.sh` `[1x]`; в `[7]` есть близнец с python-shebang под `sh -c` — так узел и вызывает (`shell=True`); мутанты `SG-EXEC`, `SG-NUM`; `tests/suites.yaml` = `./.claude/sdx/verify-cmd.sh` |
| WARN-3: `status.md` 5а | **закрыт** | Текст 5а совпадает с выводом `mandate-info.sh status`; закреплён `chk_status_mandate` с красными сторонами |
| WARN-4 / G1–G4: проза без инвариантов | **закрыт** | `test-mo-prose.sh` `[18]` (`reconcile.md` (е)/(ж), `init.md` 2в, `status.md` 5а, `next.md`, правило `--planned`); `chk_bridge` расширен `docs_in_repo`, `(n/a, docs_in_repo: none)`, строкой о ветке `sdx/<id>`; у каждого инварианта есть повреждённая копия |
| WARN-5: дельта `docs/specs` | **закрыт** | Исключения REQ-MAND-1 перечислены верно, числа версии нет (`SIMKIT_VERSION`) |
| WARN-6: «§6» в `FEAT-016` | **закрыт** | `source:` и п.3 ссылаются на §7; оставшиеся «`MI` §6» в `docs/*mo-interop.md` относятся к шаблону сниппета, это корректно |
| WARN-7: `CLAUDE.md` §3 | **закрыт** | Добавлен абзац «Третий сужающий источник — мандат МО» |
| WARN-8: ручная часть | **закрыт решением пользователя** | `MANUAL_TEST.md`: 5 случаев «НЕ ПРОВЕРЕНО» (ДЛ 2026-10-29). Фикстура `history` исправлена в L3/сиблинге, но в `test-mo-session.sh` осталась вне домена `dev.py` (INFO-6) |
| QA F1 | названная граница | SPEC «Границы», протокол «Разбор — подмножество YAML», дельта `docs/specs`; DEBT — на Closeout |
| QA F2 / F3 | **закрыты** | `SG-NUM` (`budget_min=3 vs 3`); `active-set` → `unknown:mandate` + `[M39]` + мутант `SDX-UNKNOWN` |

## Матрица трассируемости
| Требование / критерий | Реализация (файл) | Тест | Когерентность | Статус |
|---|---|---|---|---|
| REQ-MAND-1 (без мандата — как 2.3.x; исключения (а)(б), К-4, `from.kit`) / К1 | `sdx-stage.sh` `_mandate_try` (ленивая lib, только при обоих файлах); `mo-hook.sh` (`mode_from_mandate=0` без мандата); `mo-session.sh` (`mnote` пуст, `mand_show` возвращает сразу) | `[M30]`, `[2m.* / no mandate.yaml]`, `[7m.d]` (прежний текст отказа), `check_m12c` (строка «бит в бит») + мутант `mnote-always`, `test-mandate-scope (1)` | ok (дельта `docs/specs` перечисляет исключения; дельта `docs/designs` не называет К-4 — INFO-5) | OK |
| REQ-MAND-2/3 (два файла; orphan — одна строка) / К2 | `lib/mandate.sh` `mandate_mode`, `mandate_orphan_line`; `mo-session.sh` `# MAND-ORPHAN`; `mandate-info.sh show` | `[L7]`, `check_m10` (+мутанты `no-orphan`, `orphan-two-lines`), `[2m.orphan]`, `[M] show orphan` | ok; README: «без `endpoint.yaml` — no-op» (INFO-7) | OK |
| REQ-MAND-4/5 (показ на SessionStart и `/sdx:start`, маркер данных, К-2) / К3, К4 | `mandate_report`; `mo-session.sh` `mand_show`; `start.md` 1а | `[L8]`, `check_m11*`, `check_m12*`, мутанты `no-show`, `show-before-inbox`, `no-marker`; `[14]` | ok | OK |
| REQ-MAND-6/7 (область по каждому каталогу, К-1; срок) / К4 | `mandate_report` `# MAND-SCOPE-WARN`, `mandate_expired`; `mandate-scope.sh` (строка `> Предупреждение:`) | `[L8w]`, `[L6]`, `check_m11b`, `(10)`; мутанты `MAND-SCOPE-WARN`, `MAND-EXPIRY` | ok | OK |
| REQ-MAND-8/9 (третий источник, отображение, `Deployment` всегда) / К5 | `lib/mandate.sh` `_mandate_class`/`mandate_stage_allowed`; `sdx-stage.sh` `is_skipped` `# MAND-SKIP` | `[L4]`, `[M31]`, `[M33]`, `[M36]`; мутанты `MAND-NEVER/ALWAYS/EXCL/SKIP/DEPLOY` | ok (ADR-020 поправка, протокол «Активность этапа», `next.md`, `CLAUDE.md` §3); момент отправки оффера — WARN-1 | OK |
| REQ-MAND-10 (fail-closed, пустой `stages`, паритет `safe_load`) / К7 | `lib/miniyaml.sh`, `mandate_load` | `[L1]`, `[L1v]`, `[L2]` (оракул), `[L3]`, `[M35]`, `[M36]`; мутанты `MAND-ROOT/UNKNOWN/FLOW` | граница F1 названа | OK |
| REQ-MAND-11/11a (`--to`, `start-stage`, `no_gates`/`no_code`) / К6, К8 | `sdx-stage.sh` `# MAND-TO`, `cmd_start_stage`, шаг 5а `init`; `start.md`, `import.md` | `[M32]`, `[M34]`, `[M37]`, `[M38]`; мутант `MAND-TO` | ok (протокол «Механизм перехода»; INFO-8 про `start-stage` без мандата) | OK |
| REQ-MAND-12/13/15 (`diff ⊆ область`, FAIL/WARN, пустой `paths`) / К9 | `mandate-scope.sh`; `verify.md` 6а | `(1)–(5)`, `(7)–(9)`, `[L5]` (42 случая + оракул `glob_any`); мутанты `MAND-OUTSIDE/SHARED/EMPTY-PATHS/REPLACE/GLOB-*` | ok (сопоставление совпадает с `dev.py:69–70` формула в формулу) | OK |
| REQ-MAND-14 (переносы Closeout, К-3 `--planned`) / К10 | `mandate-scope.sh` `# MAND-PLANNED`; правило в `verify.md` 6а | `(6)`, мутант `MAND-PLANNED`; `chk_verify_planned` | INFO-4 (каталоги, `docs_in_repo: none`) | OK |
| REQ-MAND-16 (режим из двух файлов + PyYAML при `deny` из мандата) / К11 | `mo-hook.sh` `# MAND-MODE2`, `# MAND-PYYAML` | `[2m]`, `[2y]`, `[8i]`; мутанты `MAND-MODE2`, `MAND-PYYAML` | ok; INFO-3 (ADR «Отвергнуто») | OK |
| REQ-MAND-17 (охрана `mandate.yaml`, К-4) / К12 | `mo-hook.sh` `# MO-GUARD-MANDATE`, `is_mailbox_file` с 3-м аргументом | `[7m]` a–d; мутанты `MAND-GUARD-MANDATE`, `MAND-NAME` | ok | OK |
| REQ-MAND-18/19/20 (генерация, форма вызова, идемпотентность, `NOCMD`) / К13 | `lib/test-cmd.sh`, `suites-gen.sh`; `init.md` 2в, `reconcile.md` (е), шаг 10 | `[1]`, `[1x]`, `[2]–[7]`, мутанты `SG-*`; `[18]` | ok; INFO-2 (допущение о бите) | OK |
| REQ-MAND-21 (dogfood) / К14 | `tests/suites.yaml` (tracked, `./.claude/sdx/verify-cmd.sh`, `budget_min: 3`) | `[8]`, `[9]` (оракул `safe_load`); живой `run_suites` — «НЕ ПРОВЕРЕНО» (ДЛ, INFO-1) | ok | OK (Л — видимое) |
| REQ-MAND-22 (`devops`) / К15 | `agents/devops.md` подпункт «Мандат», п.3 «Инструкций» | `[10]` с красными сторонами | см. WARN-1 (момент отправки оффера) | OK |
| REQ-MAND-23/23a/23b (мост для любого `delivery`, `undefined`, `docs_in_repo`) / К16 | `mandate-info.sh` `closeout-mode`/`closeout-check`; `archive.md` 2а; протокол «Контракт закрытия» | `[M]` `cm offer/pr/branch/patch/worktree/unset/broken/hostile`, `closeout-check` ×5; мутанты `MAND-BRIDGE/CHECK-*`; `[12]` | **дрейф**: ADR-021 (5), протокол «Три слоя», README×2, критерий 16, DESIGN | **FAIL** (FAIL-1) |
| REQ-MAND-24/25 (сниппет, `reconcile` (ж)) / К17 | `claude-md-snippet.md`; `snippet-check.sh`; `reconcile.md` (ж) | `[11]`, `test-snippet-check.sh` (+ мутант `SC-CMP`), `[18]` | ok | OK |
| REQ-MAND-26 (`/sdx:status`) / К18 | `mandate-info.sh status`, `sdx-stage.sh active-set`; `status.md` 5а | `[M] status` (снимок дерева, без `__pycache__`), `[M39]`, `[M40]`, `[18]` | ok | OK |
| REQ-MAND-27/28/29 (два признака, ADR, дельты, бэклог) / К19 | протокол, `docs/designs|specs/mo-interop.md`, README×2, `CLAUDE.md`, `DECISIONS.md`, `FEAT-016` | `[9]`, `[15]`, `[16]`; `test-mo-inventory.sh` (по QA) | ok (числа вендорённой версии в протоколе/ADR нет — проверено grep; `0.9.1` только в бэклоге, как требует REQ-MAND-29) | OK |
| REQ-MAND-30 (2.4.0) / К19 | `plugin.json` 2.4.0; в `marketplace.json` версии нет | `[17]` + красная сторона | релизные заметки — на Closeout (C3) | OK |
| REQ-MAND-31/32/33 (регресс, время, зависимости) / К20 | `verify-cmd.sh` (комментарий), lib без python, `sdx/mo/*` не тронуты (в diff нет) | `[L9]`, `[P]`, мутационные секции; прогон QA 114 с | ok; INFO-9 (запас времени) | OK |
| К21 (не `auto`) | процесс | — (QA и T51 сверили `gate_mode: interactive`) | ok | OK (процесс) |

## Находки

### [FAIL] [Когерентность] Решение «мост Closeout для любого `delivery`» дошло не до всех нормативных носителей: в ADR-021, протоколе и README по-прежнему «мост при `pr|branch`», в DESIGN и критерии 16 — «при `artifact.offer` Closeout штатный»
- Где:
  - `docs/DECISIONS.md`, ADR-021, поправка 2026-10-28, п.(5): «Мост Closeout при `delivery: pr|branch` — ручная сборка пакета…» (diff стр. 320);
  - `sdx/protocol.md`, «Три слоя границы области»: «Мост Closeout (`delivery: pr|branch`) — см. „Контракт закрытия сессии“» (diff стр. 4504). Абзац «Мост Closeout при мандате» в том же файле (diff стр. 4514) говорит «любой определённый `delivery` (`pr|branch|artifact.offer`)», то есть **протокол противоречит сам себе**;
  - `README.md` / `README.en.md`, абзац «Версия 2.4.0»: «Closeout при `delivery: pr|branch` оставляет ветку сессии узлу МО» / «Closeout with `delivery: pr|branch` leaves the session branch…» (diff стр. 95 / 74);
  - `SPEC.md`, критерий 16: «Closeout при мандате с `delivery: pr|branch` … при `artifact.offer` и без мандата Closeout штатный». Поправка REQ-MAND-23 круга 1 критерий не поправила;
  - `DESIGN.md` D-8 («при мандате `pr|branch` не вызывается») и таблица CLI `closeout-mode` (стр. 162: «`standard` (нет режима мандата или `delivery: artifact.offer`)») — прямо противоречат коду;
  - мелочь в коде: шапка `sdx/hooks/mandate-info.sh` (diff стр. 1038) перечисляет исходы `standard | bridge | undefined | error` без `bridge:offer`.
- Суть: по решению пользователя (`decisions_log.md` 2026-10-29) и по поправке REQ-MAND-23 мост действует при любом определённом `delivery`, а слияния в `main` под мандатом нет никогда. Код (`closeout-mode` → `bridge:offer`), `archive.md` 2а, контракт закрытия в протоколе, `devops.md` и дельты `docs/specs|designs` с этим согласны. Постоянные носители — ADR-021 (после Closeout это запись решения), абзац «Три слоя» протокола и README×2 (пользовательская документация) — описывают прежнюю, более узкую область моста, а носители сессии (критерий 16, DESIGN) прямо утверждают прежнее поведение. Читатель ADR или README по-прежнему вправе думать, что при `artifact.offer` идёт штатный Closeout со слиянием в `main`. Это та самая коллизия, ради которой был WARN-1 круга 1: по существу она закрыта в коде и прозе команд, но не в триаде. `test-mo-prose.sh [12]` проверяет только `archive.md` и протокол на наличие токенов, поэтому устаревшую формулировку «(`delivery: pr|branch`)» рядом с правильной он не ловит.
- Ожидалось: во всех носителях одна формулировка — «мост при любом определённом `delivery` (`pr|branch|artifact.offer`; для `artifact.offer` — `bridge:offer` и отправка оффера), слияния в `main` под мандатом нет; `standard` — только без режима мандата». Для этого:
  - ADR-021 п.(5) поправить датированной строкой (или дописать «поправка 2026-10-29»);
  - в протоколе «Три слоя» убрать «(`delivery: pr|branch`)»;
  - README×2 согласованно поправить;
  - в SPEC переписать критерий 16 (или пометить его как заменённый поправкой REQ-MAND-23);
  - в DESIGN пометить D-8 и строку таблицы `closeout-mode` как заменённые поправкой (DESIGN уходит в `docs/history/`);
  - в шапке `mandate-info.sh` добавить `bridge:offer`;
  - желательно добавить в `test-mo-prose.sh` отрицательный инвариант: в протоколе, README×2 и ADR-021 нет «мост…`pr|branch`» без `artifact.offer`.
- Фактически: шесть носителей описывают прежнюю область моста, два из них (DESIGN, критерий 16) — прямо противоположное поведение.

### [WARN] [Корректность/Когерентность] WARN-1. Момент отправки `artifact.offer` под мандатом определён двояко: на `Execution`/`Verification` или на шаге моста Closeout (риск двойной отправки)
- Где: SPEC REQ-MAND-9 / ДЛ-1, ADR-020 (поправка), протокол «`Deployment` под МО», `commands/next.md`, `CLAUDE.md` §3 — «`artifact.offer` при мандате отправляется на `Execution`/`Verification`». При этом поправка REQ-MAND-23, `commands/archive.md` 2а («При `bridge:offer` … добавь шаг отправки оффера: упакуй артефакт и отправь `artifact.offer` узлу»), протокол «Мост Closeout» и `agents/devops.md` («оффер отправляется на шаге Closeout-моста (`/sdx:archive`, `bridge:offer`)»).
- Суть: ни один носитель не говорит, что Closeout-шаг выполняется «если оффер ещё не отправлен на `Execution`/`Verification`», и не говорит обратного. Оркестратор, который следует `next.md`, отправит оффер на `Verification`, а затем `archive.md` велит отправить его ещё раз. Неясно, какой `msg_id` считать окончательным. Детерминированной стороны у этого нет (это проза), поэтому WARN, а не FAIL.
- Ожидалось: одна норма. Например: «на Closeout-мосту оффер отправляется, только если он не был отправлен на `Execution`/`Verification` (`msg_id` уже есть в `change_note.md`/`DESIGN.md`)». Либо закрепить единственную точку отправки. Затем синхронизировать `archive.md`, `devops.md`, протокол и SPEC.
- Фактически: две точки отправки без связки между ними.

### [INFO] [Полнота] INFO-1. Ручная часть приёмки не исполнялась (решение пользователя)
- Где: `MANUAL_TEST.md` (5 случаев «НЕ ПРОВЕРЕНО»), `decisions_log.md` 2026-10-29.
- Суть: для критериев 3 (канал SessionStart), 7 (дамп, порождённый `dev.py mandate_yaml()`; L3 написан вручную), 14 (Л: живой `run_suites`) и 16 (живая проза моста) покрытие только видимое. Пользователь принял это решение, DEBT — на Closeout. Повторного квитирования не требуется. Фиксирую, чтобы покрытие не выдавалось за доказанное.

### [INFO] [Корректность] INFO-2. Форма `cmd` в `tests/suites.yaml` для `dev.py run_suites` — корректна при названном допущении
- Где: `lib/test-cmd.sh:12` (`[ -x … ] && TC_CMD="./.claude/sdx/verify-cmd.sh"`); `tests/suites.yaml`; эталон `dev.py:153–162` (`worktree`: `git clone` зеркала → `checkout`), `dev.py:307,318` (`subprocess.run(cmd, shell=True, cwd=wt)`), `dev.py:662` (CI-workflow: `subprocess.call(..., shell=True)` из корня чекаута).
- Суть: узел исполняет `cmd` через `/bin/sh -c` в корне клона. `./.claude/sdx/verify-cmd.sh` сработает, если в клоне у файла стоит бит исполнения. `git clone`/`checkout` восстанавливает бит из **режима в индексе** (`100755`), когда на узле `core.fileMode=true` (по умолчанию в Linux). В этом репозитории `verify-cmd.sh` хранится как `100755` (заголовок diff), значит dogfood-файл корректен. **Допущение:** генератор смотрит бит в **рабочем дереве** (`-x`), а не режим в индексе. У проекта с `core.fileMode=false` (Windows/WSL, некоторые ФС) локальный бит может не совпадать с закоммиченным режимом. Тогда `suites.yaml` получит `./…`, а у узла скрипт окажется неисполняемым (rc 126), или наоборот. `--check` такой дрейф не видит. `[7]` проверяет форму под `sh -c`, но не сохранение бита через `git clone`.
- Рекомендация (не блокирует): брать режим из `git ls-files -s .claude/sdx/verify-cmd.sh`, если файл tracked; либо назвать допущение в протоколе / `init.md` 2в.

### [INFO] [Когерентность] INFO-3. ADR-021 «Отвергнуто: предпроверка PyYAML на каждый вызов» и новая проверка `# MAND-PYYAML`
- Где: `docs/DECISIONS.md` ADR-021 «Отвергнуто» и поправка п.(6); `mo-hook.sh` `# MAND-PYYAML`.
- Суть: при `deny` из мандата обёртка теперь на **каждом** вызове инструмента запускает дополнительный `python3 -c 'import yaml'` — это ровно отвергнутая альтернатива, только в узком режиме. Поправка (6) решение описывает, но с пунктом «Отвергнуто» его не согласует (не сказано: «сужение: только при `deny` из мандата, цена принята»). Стоит дописать одну фразу.

### [INFO] [Корректность] INFO-4. Правило `--planned` передаёт каталоги и не учитывает `docs_in_repo: none` (перенос с круга 1, не исправлялось)
- Где: `commands/verify.md` 6а; `mandate-scope.sh` (`mandate_in_union "docs/specs/"`).
- Суть: при узком `docs_paths` вида `docs/specs/*.md` каталог `docs/specs/` не совпадёт с шаблоном, и будет ложный `FAIL`. При `docs_in_repo: none` переносы помечаются `(n/a)`, но всё равно передаются в `--planned`. С дефолтом `docs/**` не проявляется.

### [INFO] [Когерентность] INFO-5. Дельта `docs/designs/mo-interop.md` называет «два исключения» и не называет К-4
- Где: diff стр. 444 («кроме двух названных исключений (`tests/suites.yaml`, новое содержание `/sdx:status` и сниппета)»).
- Суть: безусловная охрана `mandate.yaml` при `endpoint.yaml` (К-4) — тоже исполняемое отличие от 2.3.x без мандата. Дельта `docs/specs` его называет, дельта дизайна — нет.

### [INFO] [Полнота] INFO-6. Фикстура `test-mo-session.sh` вне домена значений `dev.py`
- Где: `test-mo-session.sh` `write_mandate` (diff стр. 3456: `history: linear`, `docs_in_repo: true`); `dev.py:25–26` (`HISTORY = {executor, mo, both}`, `DOCS = {final, full, none}`).
- Суть: WARN-8 (1) исправлен в L3 и сиблинг-фикстуре, но не здесь. На показ это не влияет, но фикстура не соответствует форме, которую выдаёт узел.

### [INFO] [Когерентность] INFO-7. README×2: «без `endpoint.yaml` — no-op»
- Где: README/README.en, абзац «Хуки safe-by-default».
- Суть: при `mandate.yaml` без `endpoint.yaml` `mo-session` печатает одну строку (REQ-MAND-3). Перенос с круга 1.

### [INFO] [Когерентность] INFO-8. `start-stage` без мандата при `no_code=true` продвигает этап, а прежний `init` отказывал (перенос с круга 1)
- Где: `sdx-stage.sh` `cmd_start_stage`; `[M38]` («no mandate, no_code: start-stage Execution -> Verification»); `start.md` («без мандата это тот же `stage`»).
- Суть: через `start.md` путь недостижим (`no_code`-типы стартуют с `Discovery`), наблюдаемого изменения нет. Но фраза в `start.md` неточна.

### [INFO] [Корректность] INFO-9. Прочие мелочи, перенесённые с круга 1
- `closeout-check` исключает `.mesh/` из проверки чистоты дерева (`mandate-info.sh` `git status -- . ':!.mesh'`), а `archive.md` и протокол говорят просто «дерево чистое».
- Суффикс `mnote` в `mo-session.sh` пишет «показан ниже» и тогда, когда мандат не разобран (следующая строка это поясняет).
- `mandate_expired` распознаёт только `YYYY-MM-DD`.
- Время полного прогона 114–124 с под нагрузкой при пределе 180 с; `budget_min: 3` в dogfood-файле — та же граница для узла.
- Переносимость на bash 3.2 подтверждена эмуляцией (`BASH_COMPAT`), а не настоящим 3.2.
- Сьюты, судя по diff, пишут только в `mktemp -d` (мутанты — в копиях; `[8]` dogfood только читает; `[M] status` сверяет снимок `$ROOT/sdx`). Это видимое, а не доказанное отсутствие записи в чекаут.

## Оси — итог
- **Полнота:** OK. Каждое REQ-MAND имеет видимую реализацию и тест или grep-инвариант с красной стороной; новые проверки круга 1 (`[2y]`, `[1x]`, `[18]`, `[M39]` unknown, `cm offer`) имеют мутанты или повреждённые копии. Ручные критерии — «НЕ ПРОВЕРЕНО» по решению пользователя (INFO-1).
- **Корректность:** OK, кроме WARN-1. Сопоставление путей совпадает с `dev.py glob_any`; форма `cmd` пригодна для `run_suites` при допущении INFO-2; обратная совместимость (REQ-MAND-1 с исключениями (а), (б), К-4, `from.kit`) видна в коде и закреплена тестами `[M30]`, `[7m.d]`, `check_m12c`, `(1)`.
- **Когерентность:** **FAIL** (FAIL-1). Мост Closeout описан по-разному в ADR-021, протоколе (внутреннее противоречие), README×2, критерии 16 и DESIGN. ADR-021 п.7 для `endpoint.yaml` без мандата не противоречит: поправка к п.7 и абзац «`Deployment` под МО» прямо ограничивают норму случаем без мандата. Числа вендорённой версии в протоколе и `DECISIONS.md` нет.
