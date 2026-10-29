# Verification Report: feat-016-mo-mandate-20261028 (круг 5, fresh-eyes)

## Сводка
- Объём: полный (SPEC/DESIGN/PLAN), `no_code`: нет, `no_gates`: нет, `gate_mode`: interactive
- Вход: `SPEC.md` (с «Поправками по коллизиям DESIGN», круги 1–4), `DESIGN.md` (датированные пометки), `PLAN.md` («Отклонения», круги 1–4), `MANUAL_TEST.md`, `release_notes_draft.md`, `upstream_note_draft.md`, `qa_report.md`, `delivery.diff` (целиком); эталон: `sdx/mo/MO-INTEROP.md` §7, `sim-kit/core/dev.py`; нормы: `sdx/protocol.md`, `docs/DECISIONS.md`, `docs/specs|designs/mo-interop.md`, `CLAUDE.md`, README×2, `docs/backlog/FEAT-016-…`.
- Итог: **FAIL** (одна находка FAIL)
- Находки: FAIL: 1, WARN: 2, INFO: 7
- По осям:
  - Полнота: OK. Каждое требование REQ-MAND-1…33, 11a, 23a, 23b и критерии 1–21 прослежены в diff (код или проза) и в тестах; ручные части (критерии 3-канал, 7-живой дамп, 14-`run_suites`, 16-проза) вынесены в `MANUAL_TEST.md`, все случаи помечены «НЕ ПРОВЕРЕНО». Scope creep в diff не видно: каждый изменённый файл трассируется к требованию.
  - Корректность: 1 FAIL (фикстура `MANUAL_TEST.md` код отвергнет), 1 INFO по покрытию тестами. Поведение скриптов по чтению diff соответствует SPEC/DESIGN.
  - Когерентность: 2 WARN (редакционные: испорченная EN-строка в заметках, противоречивая фраза в `docs/designs`), остальное — INFO. Противоречий между нормативными носителями (протокол ↔ `archive.md` ↔ ADR ↔ код) не найдено.

Покрытие ниже выведено чтением diff и тестов, то есть оно видимое (apparent), а не доказанное. Прогон тестов в этом круге не выполнялся (инструмента `Bash` у ревьюера нет); данные о прогоне — из `qa_report.md` (круг 1) и `PLAN.md`.

### Проверка закрытия находок круга 4
| Пункт | Состояние | Где |
|---|---|---|
| Пометки DESIGN :149 (К-1), :433 (К-2), :472 (К-1) | закрыто | DESIGN :149, :433, :472 — датированные пометки «Поправка круга 4» стоят перед устаревшими формулировками |
| Пометка DESIGN о `MAND-PYYAML` | закрыто | DESIGN :254 (§`mo-hook.sh`), :389 (безопасность) |
| `MANUAL_TEST` случай 2: `start-stage` rc 0 | закрыто | `MANUAL_TEST.md:45` («rc 0 и следующий допустимый этап… (rc 2 даёт только `init`)») совпадает с `cmd_start_stage` (`sdx-stage.sh`, diff :1577–1583) |
| Заметки: оговорка К-4 и поведение `/sdx:start` | закрыто в RU; EN испорчен | `release_notes_draft.md:5–6` (RU) — ok; `:32` (EN) — ok по К-4; `:33` (EN) — остаток правки, см. WARN-1 |
| `docs/designs` «ни один байт» с оговоркой | оговорка есть, но фраза противоречит сама себе | diff :453, см. WARN-2 |
| Отсылки в телах REQ-MAND-1/4/6 и критерия 3 | закрыто | SPEC :29, :35, :37, :97 |
| Порядок оффера: шаг 0 моста до шага 1 | закрыто, согласовано | `commands/archive.md` 2а (diff :140) и протокол «Мост Closeout» (diff :4569) называют «шаг 0 — до шага 1»; это согласуется с `closeout-check` (`mandate-info.sh`, diff :1144–1150: чистое дерево, нет каталога сессии в `HEAD`): `msg_id` пишется в `change_note.md`/`DESIGN.md` до коммитов шага 1, а шаг 5 удаляет каталог |
| Суффикс `mnote` при недоступной lib | честен; ярлык неточен | `mo-session.sh` (diff :1410): «…(или сообщение о недоступной lib/mandate.sh)»; при отсутствии lib `mand_show` печатает «не показан: lib/mandate.sh плагина недоступна» (diff :1401). Ярлык «строки SDX mandate» не совпадает с префиксом вывода — INFO-1 |
| (3) Число вендорённой версии в протоколе/DECISIONS | отсутствует | grep `0\.9\.[0-9]` по `sdx/protocol.md` и `docs/DECISIONS.md` — совпадений нет; дельта `docs/specs` ссылается на `SIMKIT_VERSION` |

## Матрица трассируемости
| Требование / критерий | Реализация (файл) | Тест | Когерентность | Статус |
|---|---|---|---|---|
| REQ-MAND-1 / кр.1 (без мандата — как 2.3.x; исключения (а),(б), К-4) | гейт «оба файла»: `sdx-stage.sh` `_mandate_try` (diff :1461), `mo-hook.sh` MAND-MODE2 (:1339), `mo-session.sh` (:1393–1415), `mandate-scope.sh` (:1200) | `test-sdx-stage` [M30], `test-mo-session` [12c] + мутант `mnote-always`, `test-mo-hook` [2m] «no mandate.yaml», [7m.d], `test-mandate-scope` (1) | протокол :4529, README×2, ADR-021 п.(3), дельта `docs/specs` — К-4 названо; `docs/designs` :453 — WARN-2 | OK (WARN-2 по носителю) |
| REQ-MAND-2 (два файла) | `mandate_mode` (diff :519) | L7, [2m.orphan], [M] mode | ok | OK |
| REQ-MAND-3 / кр.2 (orphan — одна строка) | `mandate_orphan_line`, MAND-ORPHAN, `mandate-info show` | `test-mo-session` [10] + мутанты, [M] show orphan | ok | OK |
| REQ-MAND-4 / кр.3 (показ на SessionStart, К-2) | `mand_show` (diff :1398), `mandate_report` | [11], [11h], [12], [12b], [12d] + мутанты | DESIGN :284/:433 помечены; ярлык mnote — INFO-1 | OK |
| REQ-MAND-5 / кр.4 (показ на `/sdx:start`) | `start.md` 1а, `mandate-info.sh show` | [M] show on (равен `mandate_report`), `test-mo-prose` [14] | ok | OK |
| REQ-MAND-6 (по каталогу, К-1) | `mandate_report` (diff :699–704) | L8w, `test-mo-session` [11]/[11b] | DESIGN :149 помечен | OK |
| REQ-MAND-7 (истёк) | `mandate_expired`, строка в `mandate-scope` | L6, (10), [11b] | ok | OK |
| REQ-MAND-8/9 / кр.5 (сужение, Deployment never) | `_mandate_class`, `mandate_stage_allowed`, `is_skipped` (MAND-SKIP) | L4, [M31]–[M33], [M36], мутанты | протокол «Активность этапа», ADR-020, CLAUDE.md §3, `next.md` — согласованы | OK |
| REQ-MAND-10 / кр.7 (fail-closed, формы) | `miniyaml.sh`, `mandate_load` | L1–L3, [M35], [8] | граница F1 названа в SPEC/протоколе | OK |
| REQ-MAND-11 / кр.6, 8 (`--to`, `init`, `start-stage`) | `sdx-stage.sh` (diff :1502–1530, :1552–1584) | [M34], [M37], [M38], мутант MAND-TO | протокол (таблица читающих подкоманд), `start.md`, `import.md` | OK |
| REQ-MAND-11a, 28 (ADR-020/021) | `docs/DECISIONS.md` (diff :296, :321) | `test-mo-prose` [16] | ok | OK |
| REQ-MAND-12…15 / кр.9, 10 (область, `--planned`) | `mandate-scope.sh`, `verify.md` 6а | `test-mandate-scope` (1)–(10), мутанты; `test-mo-prose` [13], [18] | протокол «Область на /sdx:verify» | OK |
| REQ-MAND-16 / кр.11 (строже из двух, MAND-PYYAML) | `mo-hook.sh` (diff :1338–1339, :1372–1376) | [2m], [2y], [8i], мутанты MAND-MODE2/MAND-PYYAML | протокол, ADR-021 п.(6), дельты | OK |
| REQ-MAND-17 / кр.12 (охрана `mandate.yaml`) | `is_mailbox_file` + MO-GUARD-MANDATE (diff :1365) | [7m] + мутанты | ok | OK |
| REQ-MAND-18…21 / кр.13, 14 (`tests/suites.yaml`) | `lib/test-cmd.sh`, `suites-gen.sh`, `tests/suites.yaml`, `init.md` 2в, `reconcile.md` (е) | `test-suites-gen` (1)–(10), близнец, мутанты; `test-mo-prose` [18]; ручной случай 3 | ok | OK |
| REQ-MAND-22 / кр.15 (`devops`) | `agents/devops.md` | `test-mo-prose` [10], [12b] | ok | OK |
| REQ-MAND-23/23a/23b / кр.16 (мост, любой `delivery`) | `mandate-info.sh closeout-mode/check`, `archive.md` 2а, протокол | [M] cm/cc + мутанты; `test-mo-prose` [12], [12b]; ручной случай 4 | порядок шага 0 согласован | OK |
| REQ-MAND-24/25 / кр.17 (сниппет, reconcile) | сниппет, `snippet-check.sh`, `reconcile.md` (ж) | `test-snippet-check`, `test-mo-prose` [11], [18] | ok | OK |
| REQ-MAND-26 / кр.18 (`/sdx:status`) | `mandate-info.sh status`, `active-set`, `status.md` 5а | [M] status, [M39], [M40], `test-mo-prose` [18] | ok | OK |
| REQ-MAND-27, 29 / кр.19 (два признака, дельты) | протокол, `docs/designs|specs`, README×2, CLAUDE.md, бэклог | `test-mo-prose` [9], `test-mo-inventory` | `docs/designs` :453 — WARN-2 | WARN |
| REQ-MAND-30 (2.4.0, заметки) | `plugin.json`; `release_notes_draft.md` | `test-mo-prose` [17] | EN-строка испорчена — WARN-1 | WARN |
| REQ-MAND-31…33 / кр.20 (регресс, время, зависимости) | `verify-cmd.sh` (комментарий), `sdx/mo/*` без правок | полный прогон (`qa_report`, PLAN Отклонения З.1) | ok | OK |
| Кр.21 (не `auto`) | `session_state.json`: `interactive` | — (процесс) | ok | OK |
| Ручной сценарий (кр.3-канал, 7, 14, 16, 11–12 вживую) | `MANUAL_TEST.md` | — | фикстура противоречит коду — FAIL-1 | FAIL |

## Находки

### [FAIL] [Корректность/Когерентность] Общая фикстура `MANUAL_TEST.md` не является мандатом: нет корневого ключа `mandate:`
- Где: `.claude/sessions/feat-016-mo-mandate-20261028/MANUAL_TEST.md:12–27` (образец `FX/.mesh/mandate.yaml`); затрагивает ожидаемые результаты случаев 1 (:34), 2 (запасной путь «если не выдан узлом», :45–46), 4 (:67) и предусловие случая 5 (:72).
- Суть: образец написан полями верхнего уровня (`executor:`, `stages:`, `scope:` …). Код требует корень `mandate` (`lib/mandate.sh`, `mandate_load`, MAND-ROOT, diff :542–543: «корневой ключ mandate отсутствует или пуст»). Эталон пишет так же: `dev.py:531` `yaml.safe_dump({"mandate": m}, …)`. На этой фикстуре `/sdx:start` (шаг 1а) выведет «ВНИМАНИЕ: мандат … не разобран», `start-stage`/`next` откажут с rc 1, `closeout-mode` вернёт `error:…`. А `MANUAL_TEST.md` для неё обещает показ стадий и области (случай 1 (а)), зелёный мост (случай 4) и запись вне области под `deny` (случай 5). Кроме того, в образце нет `on_write`, а случай 5 требует `mandate.on_write: deny`. Документ, который по `decisions_log.md` сохраняется в `docs/history/experiments/` для первой живой сессии, получит ложный отрицательный результат или подтолкнёт к «исправлению» кода.
- Ожидалось: образец в форме эталона — `mandate:` и вложенные поля с отступом (как фикстуры `test-mo-session.sh write_mandate`); для случая 5 явно указать добавку `on_write: deny`.
- Фактически: плоский YAML без `mandate:`, без `on_write`.

### [WARN] [Когерентность] Английская часть заметок к релизу испорчена остатком правки
- Где: `release_notes_draft.md:33`
- Суть: фраза «…is refused (`sdx-stage.sh`, `[ERROR]` logged).sh` (`start-stage`, `[ERROR]` log entry).» — хвост `.sh` (`start-stage`, `[ERROR]` log entry).` остался от прежней редакции. Пара RU/EN несимметрична (RU :6 корректна). Текст публикуется на Closeout (C3).
- Ожидалось: «…is refused (`sdx-stage.sh`, `[ERROR]` logged).» без хвоста.

### [WARN] [Когерентность] Фраза «ни один новый байт» в `docs/designs/mo-interop.md` противоречит сама себе
- Где: `docs/designs/mo-interop.md`, раздел «Дельта FEAT-016», первый абзац (diff :453)
- Суть: «Без `mandate.yaml` ни один новый байт (кроме названных исключений REQ-MAND-1, включая К-4 — см. ниже) кода не выполняется (ленивая загрузка lib), кроме двух названных исключений (`tests/suites.yaml`, новое содержание `/sdx:status` и сниппета)». В одном предложении два «кроме»: первое включает К-4, второе говорит о «двух» исключениях. Читатель не поймёт, сколько исключений. Кроме того, без мандата код всё же выполняется: проверки `[ -f … ]` в `sdx-stage.sh`/`mo-hook.sh`, а в `mo-hook.sh` охрана `mandate.yaml` (К-4) — новый код, исполняемый безусловно. Правка круга 4 (WARN-2) по существу не закрыта.
- Ожидалось: одно перечисление, например: «Без `mandate.yaml` новый код не выполняется, кроме проверок наличия файлов и названных исключений REQ-MAND-1: (а) `tests/suites.yaml`, (б) новое содержание `/sdx:status` и сниппета, протокольные `from.kit`/`version-skew`, безусловная охрана `mandate.yaml` (К-4)».

### [INFO] [Когерентность] Суффикс `mnote` ссылается на «строки SDX mandate», а `mo-session` печатает префикс `SDX mo-session:`
- Где: `sdx/hooks/mo-session.sh` (diff :1410); DESIGN :284 (пометка круга 3 пересказывает суффикс как «…показан ниже»)
- Суть: префикс `SDX mandate:` бывает только у `mandate-info.sh show`. В выводе SessionStart строки мандата начинаются с `SDX mo-session: мандат МО …`. Ветку «lib недоступна» суффикс описывает честно. Пересказ в DESIGN на финальный текст не обновлён (расхождение формулировки, не поведения).
- Ожидалось (по желанию): «…см. строки «мандат МО» ниже…»; пометку DESIGN синхронизировать.

### [INFO] [Корректность] Резервные ветки `mo-session.sh` при отсутствии `lib/mandate.sh` тестом не покрыты
- Где: `mo-session.sh` MAND-ORPHAN, ветка `|| printf …` (diff :1393), и `mand_show`, ветка `else say "… не показан …"` (diff :1401)
- Суть: в `test-mo-session.sh` фикстурный корень всегда получает обе lib (diff :3489–3490). Инвариант «ровно одна строка» в резервной ветке orphan и сообщение «не показан» по видимому покрытию не проверяются. Риск низкий (ветки по одной строке).

### [INFO] [Когерентность] Тела REQ-MAND-14 и REQ-MAND-16 без отсылки к своим поправкам
- Где: `SPEC.md:52` (REQ-MAND-14 ↔ поправка К-3, :166), `SPEC.md:57` (REQ-MAND-16 ↔ поправка круга 1, :170)
- Суть: у REQ-MAND-1/4/6/23 и критериев 3/16 отсылки «см. поправку…» в теле есть, у этих двух — нет. Противоречия нет, раздел «Поправки» обязателен (PLAN «Условные обозначения»).

### [INFO] [Когерентность] Шаг 0 моста описан в конце длинного абзаца
- Где: `commands/archive.md` 2а (diff :140), протокол «Мост Closeout» (diff :4569)
- Суть: порядок назван явно («шаг 0, до шага 1») и согласован с `closeout-check`. Но в тексте этот шаг идёт после «Выполни шаги 1–5…», после `closeout-check` и после инструкции по сборке пакета. Последовательное чтение рискует выполнить 1–5 раньше, чем дойдёт до шага 0. Это читаемость, не противоречие.

### [INFO] [Когерентность] `docs/designs/mo-interop.md` п.2 трёх слоёв: «Без файла — `exit 0`, пустой вывод»
- Где: diff :433
- Суть: после поправки «двумя признаками» фраза «без файла» неоднозначна: при `mandate.yaml` без `endpoint.yaml` `mo-session` печатает одну строку (REQ-MAND-3). Ожидается уточнение: «без `endpoint.yaml` (и без `mandate.yaml`)».

### [INFO] [Полнота] Заметки к релизу не называют проверку PyYAML при `deny` из мандата
- Где: `release_notes_draft.md:9` / `:36`
- Суть: поведенческая поправка круга 1 (REQ-MAND-16, `MAND-PYYAML`) в «Что изменилось» не отражена, хотя протокол, ADR-021 п.(6) и дельты её несут.

### [INFO] [Когерентность] Критерий приёмки в записи бэклога без оговорки К-4
- Где: `docs/backlog/FEAT-016-…md`, строка «Критерии приёмки: без `mandate.yaml` … неотличимо от 2.3.0» (diff :395)
- Суть: по ДЛ-1 запись поправляется на Closeout (C2), поэтому это не блокер; при поправке стоит добавить исключение К-4.

### [INFO] [Когерентность] Исторические формулировки PLAN («`artifact.offer` и без мандата — штатный»)
- Где: `PLAN.md:459` (таблица покрытия, кр.16), T12/T33/T39
- Суть: формулировки кругов до 2 оставлены сознательно как история (PLAN, «Круг 3», INFO-5); актуальную норму несут SPEC «Поправки» и раздел «Отклонения». Противоречия с кодом не создают.
