---
id: DEBT-052
type: debt
status: open
priority: low
wave: null
source: session (sdx/feat-017-mo-change-package-20261031), Verification 2026-10-31
session: null
links: [FEAT-017, DEBT-004, DEBT-013]
---

# DEBT-052. Параллельный раннер `.claude/sdx/verify-cmd.sh` (`SDX_VERIFY_JOBS`) без автотеста; бюджет stop-gate 180 с тонок под нагрузкой

## Суть
Полный прогон dogfood-сьютов (25) вырос до 190+ с последовательно под нагрузкой хоста; по К-10 (FEAT-017) в
`.claude/sdx/verify-cmd.sh` добавлен параллельный раннер (`xargs -P`, по умолчанию 2 при ≥ 4 ядрах, `SDX_VERIFY_JOBS=1` —
последовательно), 127–152 с при load 5–16. Раннер проверен вручную на трёх фиктивных сьютах (порядок вывода, `Summary`, rc),
автотеста нет; класс `DEBT-013` (раннер без автотеста). Запас до предела stop-gate (180 с) остаётся тонким.

## Рекомендация
Сьют `test-verify-cmd.sh` на фиктивных сьютах (jobs 1/2/3, красный → rc 1, порядок вывода, потерянный `.rc` → FAIL) с красной
стороной; либо вынести тяжёлые мутационные блоки в `SCEN_MIN` по умолчанию и гонять полный набор только по `SDX_VERIFY_FULL=1`.
