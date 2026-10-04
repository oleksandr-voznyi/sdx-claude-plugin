# sdx/mo — вендорённые инструменты лист-сессии мета-оркестратора (МО)

Источник истины — **не этот репозиторий**, а sim-kit (`aibok/agentico/meta-orchestrator/sim-kit/core/`):
`mesh_endpoint.py` (почтовый ящик `.mesh/`: `send` / `pull` / `inbox --json` / `leases`), `devagent_hook.py`
(PreToolUse-хук: запись в `exec_paths` без аренды МО → `notice` / блок), `MO-INTEROP.md` (правила интеропа).
Версия выпуска — `SIMKIT_VERSION`; идентичность копии — `SIMKIT_SHA256` (`sha256sum -c SIMKIT_SHA256`).

Правила — `sdx/protocol.md`, «Вендорённые компоненты (`sdx/mo/`)» (PROC-028, поправка к ADR-013):
локальные правки запрещены — дефект уходит запиской в `agentico/reviews/`, плагин ждёт выпуска;
обновление — осознанный шаг отдельной сессией, не в `gate_mode: auto`; сторож — `sdx/hooks/test-mo-inventory.sh`.
Плагин вызывает эти файлы только через обёртки `sdx/hooks/mo-hook.sh` и `sdx/hooks/mo-session.sh`
(`PYTHONDONTWRITEBYTECODE=1`, трансляция `exit 2` в JSON `permissionDecision: "deny"`).
