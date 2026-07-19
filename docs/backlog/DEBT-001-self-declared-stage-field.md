---
id: DEBT-001
type: debt
status: open
priority: high
wave: 7
source: audit-2026-07-01 (A3)
session: null
links: []
---

# DEBT-001. Весь enforcement держится на самодекларируемом поле `stage`

## Суть
`stage-gate`/`stop-gate` читают `stage` из `session_state.json`, который лежит под
`.claude/**` (always-allow). Модель, которую гейт ограничивает, может при деградации
контекста записать `stage: Execution` в обход `/sdx:next` — и заморозка кода исчезает.
Это тот самый класс «инвариант-в-прозе», который Фаза 1 объявила ненадёжным.

## Рекомендация
Детерминированный скрипт перехода `sdx-stage.sh <session> <new-stage>`,
который сам проверяет гейт-артефакты (выход из Verification — только при существующем
`verification_report.md` без FAIL и т.д.) и единственный пишет `stage`; плюс
PreToolUse-deny на `Write|Edit` в `session_state.json` (правки состояния — только через
скрипт по Bash). Закрывает случайный обход, не претендуя на защиту от намеренного.
