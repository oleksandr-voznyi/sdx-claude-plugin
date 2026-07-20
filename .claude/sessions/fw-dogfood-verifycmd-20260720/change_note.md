# Change Note — fw-dogfood-verifycmd-20260720

**Бэклог:** DEBT-004 (wave 4). **Трек:** standard. **Тип:** refactor.

## Проблема (бизнес-контекст)

Допущение «у мета-проекта SDX нет тест-сьюта → stop-gate деградирует в no-op» (ADR-4
дизайна Фазы 1, SPEC Фазы 1, примечание в `commands/verify.md`) устарело: в `sdx/hooks/`
лежат 5 тест-сьютов (`test-*.sh`, суммарно 56 юнит-тестов, полный прогон ~9 секунд,
все зелёные), и ничто не запускает их автоматически. Регресс хуков ловится только
вручную; stop-gate на SDX-сессиях самого фреймворка молчит.

## Discovery (факты)

- Тесты: `sdx/hooks/test-{archive-verify,default-branch,prod-guard,stage-gate,stop-gate}.sh`;
  каждый самодостаточен (создаёт временные git-репо), печатает `Results: N passed, M failed`
  и возвращает exit 0/1. Суммарно 18+6+9+10+13 = 56 тестов, прогон ~9 с (< таймаута
  stop-gate 180 с и рекомендованных ~30 с).
- stop-gate (`sdx/hooks/stop-gate.sh:33`) первым приоритетом берёт исполняемый
  `$proj/.claude/sdx/verify-cmd.sh`; сейчас в `.claude/sdx/` мета-проекта его нет →
  автодетект пуст → no-op.
- `.claude/sdx/*`-конфиги трекаются в git (prod-guard.conf, stage-gate.allow уже tracked).
- Устаревшее утверждение зафиксировано в: `commands/verify.md:17` (примечание),
  `docs/designs/phase1-enforcement-routing.md` (ADR-4, строки 66, 295, 422, 473, 490, 553),
  `docs/specs/phase1-enforcement-routing.md` (строки 39, 108, 170 — допущение №4),
  комментарии `sdx/hooks/stop-gate.sh:43` и `sdx/templates/verify-cmd.sh.template:10`.

## Решение (техническое)

1. **Создать исполняемый `.claude/sdx/verify-cmd.sh`** (per-project конфиг мета-проекта):
   последовательно запускает все `sdx/hooks/test-*.sh`, падает (exit 1), если хоть один
   сьют красный; печатает сводку. Поддержка `--fast` не нужна — полный прогон ~9 с.
   Эффект: stop-gate становится активен на SDX-сессиях фреймворка (dogfooding),
   регресс хуков ловится детерминированно на каждом завершении хода в
   Execution/Verification.
2. **`commands/verify.md`** — переформулировать примечание: no-op-деградация остаётся
   общим свойством проектов без тест-команды, но привязка «мета-проект = без тестов»
   убирается (мета-проект теперь сам под stop-gate).
3. **`docs/designs/phase1-enforcement-routing.md`** — датированная поправка к ADR-4 и
   связанным местам: допущение «нет тест-сьюта» закрыто DEBT-004, мета-проект использует
   `verify-cmd.sh`. Механизм no-op-деградации НЕ меняется (остаётся safe-by-default для
   произвольных проектов).
4. **`docs/specs/phase1-enforcement-routing.md`** — та же датированная поправка к
   допущению №4 и связанным формулировкам.
5. **Косметика комментариев**: `stop-gate.sh:43` и `verify-cmd.sh.template:10` —
   формулировку «required for meta-project» заменить на общую («projects without a test
   command»), поведение кода не меняется.

## Границы

- Логика хуков НЕ меняется (только комментарии) — публичные контракты не затронуты.
- no-op-деградация stop-gate для проектов без тестов остаётся спроектированным поведением.
- Тесты уже существуют и зелёные; новые тесты не пишутся (изменений логики нет).

## Затронутые файлы

- `.claude/sdx/verify-cmd.sh` (новый, исполняемый)
- `commands/verify.md`
- `docs/designs/phase1-enforcement-routing.md`
- `docs/specs/phase1-enforcement-routing.md`
- `sdx/hooks/stop-gate.sh` (комментарий)
- `sdx/templates/verify-cmd.sh.template` (комментарий)

## Ссылки

- Коммит Execution: `7e81c31` — verify-cmd.sh + правки verify.md, поправки DEBT-004 в
  specs/designs (phase1-enforcement-routing), косметика комментариев stop-gate.sh и шаблона.
- Прогон `.claude/sdx/verify-cmd.sh`: 5/5 сьютов, 56/56 тестов, exit 0 (~9 с).
