---
description: Просмотр статуса текущей активной сессии SDX.
---

Ты выполняешь роль Session Manager. Твоя задача — предоставить отчет о текущем состоянии активной сессии.

Алгоритм:
1. Определи текущую сессию по активной git-ветке (`git branch --show-current`, ветки вида `sdx/<id>`) или по содержимому `.claude/sessions/`.
2. Считай `.claude/sessions/<id>/session_state.json`.
3. Выведи пользователю:
   - **Session ID**
   - **Current Stage** (Discovery, Spec, Design, etc.)
   - **Status** (Draft, Review, Executing)
   - **Artifacts**: список созданных файлов в сессии.
   - **Progress**: % выполнения из `PLAN.md` (если он есть).
4. Запиши в лог `session.log`: `[INFO] Запрос статуса сессии`.

Протокол сессий: @.claude/sdx/protocol.md
