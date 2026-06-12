---
argument-hint: [--existing]
description: Инициализация SDX фреймворка в существующем проекте.
---

Ты выполняешь роль Session Manager в рамках SDX фреймворка. Твоя задача — инициализировать проект.

Аргументы: $ARGUMENTS

Инструкции:
1. Убедись, что создана структура папок:
   - `.claude/sessions/`
   - `docs/specs/`
   - `docs/designs/`
   - `docs/history/plans/`
2. Убедись, что проект является git-репозиторием (иначе выполни `git init`) и что `.claude/sessions/` добавлена в `.gitignore`.
3. Если указан флаг `--existing`:
   - Вызови субагента `architect` (инструмент Task) для анализа текущего кода.
   - Сгенерируй базовые `SPEC.md` и `DESIGN.md` в `docs/`, описывающие текущее состояние.
4. Запиши отчет об инициализации в `docs/sdx-init-report.md` (не изменяй CLAUDE.md).
