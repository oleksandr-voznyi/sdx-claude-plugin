---
id: PROC-004
type: proc
status: closed
priority: normal
wave: null
source: audit-2026-07-01 (E3)
session: feat-vibe-track-20260720
links: [ADR-005, ADR-017, ADR-018, REQ-SESS-1]
---

# PROC-004. Режим экстремального прототипирования (vibe)

## Суть
Нужен режим быстрой реализации фичи/эпика «в один промпт»: без церемонии спеков,
без инкрементальных коммитов (быстрый откат грязного дерева), но с обязательной
«легализацией» после утверждения прототипа — реверс-инжиниринг дельт в SPEC/DESIGN,
покрытие тестами, verify, и только затем мёрж.

## Рекомендация
Тип сессии `proto` с треком `vibe`: стадия Prototype (stage-gate открыт,
stop-gate off, дерево не коммитится — осознанное исключение из REQ-SESS-1); гейт утверждения
(отклонено → `git checkout/clean`, принято → обязательный ретрек в легализацию:
spec-after по образцу `/sdx:init --existing` → тесты qa → verify → Closeout).
Инвариант enforcement: сессия трека `vibe` не может пройти `/sdx:archive` без легализации.
ADR (исключение из ADR-005/REQ-SESS-1 фиксируется явно).

## Резолюция
Реализовано сессией `feat-vibe-track-20260720` (feature, трек `full`), ADR-018.

- Трек `vibe` описан **одной строкой** матрицы `vibe|Prototype|-|no` — процедурный код
  `sdx-stage.sh` не изменён. Отсутствие собственного `Closeout` у трека и есть enforcement
  требования «нет мёржа без легализации»: инвариант выражен формой данных, а не проверкой.
- Тип сессии `proto` жёстко привязан к треку на `/sdx:start` (прецедент ADR-017); вход в `vibe`
  через `/sdx:retrack` извне запрещён.
- Гейт принятия/отклонения — новая команда `/sdx:proto`: baseline-снимок
  (`prototype_baseline.txt`), поимённый откат по вычисленному списку, безусловный
  `AskUserQuestion` даже при `gate_mode: auto`. `git clean -fd`/`checkout .`/`reset --hard`
  не применяются нигде.
- Легализация — `/sdx:retrack standard|full`: spec-after реверс-инжиниринг, первый коммит кода
  прототипа и пост-проверка REQ-VIBE-7 до смены трека.
- Приостановление ADR-005/REQ-SESS-1 — именованное исключение строго в границах стадии
  `Prototype`, снимается первым коммитом кода при легализации.

Верификация: четыре раунда fresh-eyes ревью (два вернули FAIL и были устранены), финал —
PASS без FAIL; 9/9 тест-сьютов, 166 сценариев. Постоянные документы:
`docs/specs/vibe-prototyping-track.md`, `docs/designs/vibe-prototyping-track.md`,
`docs/history/plans/feat-vibe-track-20260720.md`.
