# Verification Report: fw-session-inplace-20260705

- Трек: standard; ревьюер: fresh-eyes `reviewer` (Task, контракт изоляции соблюдён).
- Автотесты хуков: `test-archive-verify.sh` 18/18, `test-stop-gate.sh` 13/13,
  `test-stage-gate.sh` 8/8, `test-default-branch.sh` 6/6 — все зелёные, логика хуков не менялась.
- Итог: **PASS** (FAIL: 0, WARN: 1).

## Находки

### [WARN] [Когерентность] Постоянные SPEC/DESIGN описывают worktree-модель как действующую
`docs/specs/session-worktree-model.md` и `docs/designs/session-worktree-model.md` декларируют
worktree-модель без пометки о пересмотре ADR-012 — триада рассинхронизирована для свежего
читателя. Не блокирует гейт (ADR-012 — авторитетная запись разворота, прецедент ADR-008).
**Квитирование:** закрывается на Closeout этой же сессии — баннер пересмотра в оба документа
+ новый постоянный спек `docs/specs/session-inplace-model.md`.

Информационно: комментарий `stop-gate.sh:71` «worktree-safe» анахроничен, но не вводит в
заблуждение (per-session кэш корректен и в in-place-модели).

## Проверено фактически
- Хуки резолвят сессию по `git branch --show-current` (`stage-gate.sh:23`, `stop-gate.sh:9`) —
  in-place-модель работает без правок enforcement-логики.
- `archive-verify.sh`: блок `git worktree remove` условный → no-op без worktree (legacy compat).
- Вариант A сохранён: `git rm -r` на ветке строго ДО мёржа; scope creep в diff не обнаружен;
  затронутые файлы 1:1 совпадают с change_note.
