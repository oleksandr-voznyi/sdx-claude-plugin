---
id: DEBT-017
type: debt
status: open
priority: normal
wave: null
source: fresh-eyes ревью сессии fw-session-types-20260720 (отложено пользователем)
session: null
links: [PROC-002, ADR-017, ADR-014]
---

# DEBT-017. Перечисления треков в `agents/qa.md`, `developer.md`, `devops.md` не включают `doc`

## Суть
Сессия `fw-session-types-20260720` добавила трек `doc` в перечисления `agents/reviewer.md`,
`lead-dev.md` и `tech-writer.md`, но три оставшихся агента с такими же перечислениями не
были затронуты — они отсутствовали в списке компонентов дизайна. Утверждения этих файлов
без упоминания `doc` формально не ложны, но перечень треков в них неполон.

Отдельно: `agents/qa.md:26` утверждает, что на треке `patch` Verification **опционален** —
это прямо противоречит ADR-014 и `sdx/protocol.md`, где лёгкая верификация на `patch`
обязательна. Дефект предсуществующий, к треку `doc` отношения не имеет, но обнаружен
тем же ревью.

## Рекомендация
Одной правкой: дописать `doc` в перечисления треков `agents/qa.md`, `agents/developer.md`,
`agents/devops.md` и исправить утверждение про опциональность Verification на `patch`
в `agents/qa.md` в соответствии с ADR-014.
