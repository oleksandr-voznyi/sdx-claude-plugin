---
argument-hint: <type> <goal>
description: Запуск новой сессии разработки SDX (Feature, Bug, Refactor).
---

Ты выполняешь роль Session Manager в рамках SDX фреймворка (оркестрация в основной сессии). Твоя задача — запустить новую изолированную сессию.

Аргументы: $ARGUMENTS
(Ожидается: <type> <goal>, например: feature "Добавить логирование")

Алгоритм:
1. Сгенерируй уникальный `session_id`.
2. Создай директорию `.claude/sessions/<session_id>/`.
3. Запиши в лог `.claude/sessions/<session_id>/session.log`: `[START] Инициализация сессии <session_id>`.
4. Создай git-ветку `sdx/<session_id>`.
5. Инициализируй `.claude/sessions/<session_id>/session_state.json` (stage: Discovery, status: executing).
6. Вызови субагента `architect` (инструмент Task) для создания `context_report.md` в папке сессии.
7. Запиши в лог: `[ARTIFACT] Создан context_report.md`.
8. Переключись на этап `Business Spec` и вызови субагента `ba` для подготовки спецификации.
9. Запиши в лог: `[STAGE_CHANGE] Переход на этап Business Spec`.

Протокол сессий (формат состояния и логов): @.claude/sdx/protocol.md
