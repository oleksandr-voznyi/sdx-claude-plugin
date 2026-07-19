---
id: DEBT-003
type: debt
status: open
priority: normal
wave: 10
source: audit-2026-07-01 (A5)
session: null
links: []
---

# DEBT-003. Обход stage-gate через Bash не зафиксирован как граница

## Суть
У prod-guard граница честно задокументирована («покрывает только Bash»). У
stage-gate симметричная дыра: `echo > file`, `sed -i`, `tee` через Bash пишут код на любой
стадии — нигде не отмечено. Закрывать эвристиками по Bash-командам не стоит (хрупко).

## Рекомендация
Задокументировать границу в разделе «Enforcement-слой» `protocol.md` —
по тому же стандарту честности, что у prod-guard.
