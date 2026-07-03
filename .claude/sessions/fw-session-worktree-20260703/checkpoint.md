# Checkpoint — fw-session-worktree-20260703

**Дата среза:** 2026-07-03 · **Тип:** refactor · **Трек:** full · **Стадия:** Task Planning (завершена) → следующая **Execution**

## Цель сессии
Рефакторинг работы с сессиями SDX по находкам аудита **C7 + C2** (+ доп. требование пользователя):
- **C7** — версионировать содержательные артефакты сессии в ветке `sdx/<id>` (снять `.claude/sessions/` из `.gitignore`); после мёржа файлов сессии нет в основной ветке.
- **C2** — перевести сессии на **git worktree** (одна сессия = свой worktree); `/sdx:switch` без слепого `git add -A`.
- **REQ-BRANCH** — автоопределение основной ветки (`main`/`master`/иная) без правок под проект.

## Что сделано (пройденные этапы)
- **Discovery** (`context_report.md`): подтверждены C7/C2 на уровне кода; эмпирика §8 — `CLAUDE_PROJECT_DIR` фиксируется на каталоге запуска CLI (worst-case допущение). Доп. §6a — точки хардкода `main`.
- **Business Spec** (`SPEC.md`, approved): REQ-SESS-1..4, REQ-WT-1..5, REQ-BRANCH-1..4.
- **Technical Design** (`DESIGN.md`): решения по 8+1 вопросам; ADR-009 (worktree + tracked, **вариант A**: `git rm` каталога сессии коммитом на ветке ДО мёржа, `--no-ff`), ADR-010 (автоветка). Псевдокод `lib/default-branch.sh` и переписанного `archive-verify.sh`. Точная дельта `.gitignore`. Регресс: `verify.md` исключает `.claude/sessions/**` из fresh-eyes diff.
- **Task Planning** (`PLAN.md`): 23 задачи, 5 слоёв.

## На чём остановились
Гейт Task Planning пройден. **Следующий шаг — Execution** (TDD через субагента `developer`).

Критический путь: T1→T2 (default-branch + тесты) → T5/T6/T7→T8 (archive-verify + тесты) → T9 (зелёный сьют) → T10/T12 (start/archive) → T13/T14 (verify/init) → T17 (protocol) → T19 (греп-проверка `main`) → T20 (эмпирика REQ-WT-1) → T21/T22 (сквозные на master/дефолт).
Параллелизуемо: T3‖T1-T2; T5/T6/T7; команды T10/T11/T13/T14/T15 (T12 ждёт T10); T16‖T18.

## Ключевые решения к соблюдению в Execution
1. **Вариант A** удаления: `git rm -r .claude/sessions/<id>` коммитом на ветке до мёржа; merged основная ветка чиста, история — через merge-DAG.
2. `.gitignore`: снять широкий `.claude/sessions/`; добавить `.sdx/worktrees/`, `.claude/sessions/*/.stopgate.*`.
3. `archive-verify.sh`: `def=$(lib/default-branch.sh)` вместо `main`; инвариант 6 = «каталог сессии НЕ tracked в дереве основной ветки»; `git worktree remove` вместо активного `rm -rf` (rm остаётся страховкой).
4. `lib/default-branch.sh`: `origin/HEAD` → `init.defaultBranch` → эвристика `main`/`master`; безопасен без remote.
5. **Не трогать** `stage-gate.sh`/`stop-gate.sh`/`prod-guard.sh`/`preflight.sh` (worktree-совместимы/нейтральны); только T4 — проверить, что `.stopgate.*` покрыт новым `.gitignore`.
6. `/sdx:switch` → инструкция запустить CLI в каталоге worktree (§8), не in-process checkout.

## Открытые риски
- **[High] Допущение о `CLAUDE_PROJECT_DIR`** (линчпин): дизайн корректен под worst-case; приёмочная задача **T20** верифицирует связку worktree↔хук на реальном харнессе в Execution.
- Регресс `test-archive-verify.sh` (все 6 сценариев на gitignore-допущении) — обязательная переработка (T5).

## Самозакрытие текущей сессии (T23, важно на Closeout)
Эта сессия создана в СТАРОЙ модели (её каталог сейчас gitignored, worktree нет). Closeout — **гибридный, вручную**: перенос дельт `SPEC.md`/`DESIGN.md` в `docs/`, `git worktree remove` = **n/a**, удаление `.claude/sessions/<id>/` обычным `git rm`/`rm`. ADR-009 фиксирует cutover: последняя сессия старой модели.

## Восстановление
После `/clear` → `/sdx:status`; читать: `checkpoint.md` (этот файл), `PLAN.md` (задачи), `DESIGN.md` (решения/псевдокод), `SPEC.md` (REQ), при необходимости `context_report.md` (§8 про CLAUDE_PROJECT_DIR).
