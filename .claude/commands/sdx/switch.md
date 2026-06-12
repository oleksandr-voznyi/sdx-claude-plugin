---
argument-hint: <session_id>
description: Переключение между активными SDX сессиями.
---

Ты выполняешь роль Session Manager. Твоя задача — переключить рабочее окружение на другую сессию.

Аргументы: $1
(Ожидается: <session_id>)

Алгоритм:
1. Проверь наличие директории `.claude/sessions/$1/`.
2. Выполни `git add -A && git commit -m "sdx: auto-save session before switch"` в текущей ветке.
3. Выполни `git checkout sdx/$1`.
4. Загрузи состояние из `.claude/sessions/$1/session_state.json`.
5. Запиши в лог новой сессии: `[START] Переключение на сессию $1`.
6. Подтверди пользователю успешное переключение.

Протокол сессий: @.claude/sdx/protocol.md
