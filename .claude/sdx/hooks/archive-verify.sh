#!/usr/bin/env bash
# SDX archive-verify (REQ-CLOSEOUT-1): enforce Closeout invariants 1, 5, 6
# under the in-place branch + tracked-artifacts model (ADR-012) and dynamic
# default branch (ADR-010). Called from /sdx:archive AFTER the session branch
# has been merged into the default branch, from the repo root CLI. The
# conditional worktree-removal block below is legacy compat for pre-ADR-012
# sessions that still live in a separate worktree.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
proj="${CLAUDE_PROJECT_DIR:-.}"
sid="${1:?session_id required}"
sdir="$proj/.claude/sessions/$sid"
def="$("$here/lib/default-branch.sh" "$proj")"      # ADR-010: no hardcoded 'main'
fail=0

# Invariant 1: main worktree clean (session files already git-rm'd on branch pre-merge,
#              variant A -> nothing dirty here).
if [ -n "$(git -C "$proj" status --porcelain)" ]; then
  echo "[FAIL] рабочее дерево не чистое — есть незакоммиченные изменения." >&2; fail=1
fi

# Invariant 5: branch sdx/<id> provably merged into the DEFAULT branch.
if git -C "$proj" rev-parse --verify "sdx/$sid" >/dev/null 2>&1; then
  # Exact name match (-qx): avoid matching sdx/<id>-suffix branches.
  if ! git -C "$proj" branch --merged "$def" --format='%(refname:short)' | grep -qx "sdx/$sid"; then
    echo "[FAIL] ветка sdx/$sid не слита в $def." >&2; fail=1
  fi
elif [ "${SDX_ARCHIVE_NO_BRANCH_OK:-0}" != "1" ]; then
  # Branch absent: merge is UNPROVABLE. A branch deleted while unmerged would lose
  # the only trace of the session, so refuse to delete without explicit operator
  # confirmation (set SDX_ARCHIVE_NO_BRANCH_OK=1 to override in /sdx:archive).
  echo "[FAIL] ветка sdx/$sid отсутствует — слияние недоказуемо; деструктив отменён. (SDX_ARCHIVE_NO_BRANCH_OK=1 для оверрайда)" >&2
  fail=1
fi

# Invariant 6 (variant A): session dir MUST be absent from the default-branch tree.
# Its presence means the git-rm-before-merge step (Closeout) was skipped -> block.
if [ -e "$sdir" ] && git -C "$proj" ls-files --error-unmatch "$sdir" >/dev/null 2>&1; then
  echo "[FAIL] каталог сессии всё ещё tracked в дереве $def — пропущен коммит 'git rm' до мёржа (вариант A)." >&2
  fail=1
fi

# Abort before any destructive action if any invariant above is violated.
[ "$fail" -ne 0 ] && { echo "[ABORT] Closeout не завершён — устраните FAIL и повторите." >&2; exit 1; }

# Post-checks passed -> штатное освобождение worktree (REQ-WT-5) вместо rm -rf.
# Обнаружение пути worktree по ветке (хук не хардкодит .sdx/worktrees/).
wt="$(git -C "$proj" worktree list --porcelain \
        | awk -v b="refs/heads/sdx/$sid" '
            /^worktree /{p=substr($0,10)} /^branch /{if($2==b) print p}')"
if [ -n "$wt" ]; then
  git -C "$proj" worktree remove --force "$wt" 2>/dev/null \
    || { echo "[FAIL] не удалось освободить worktree $wt" >&2; exit 1; }
fi
# Страховка: физического каталога артефактов в основном дереве быть не должно.
if [ -d "$sdir" ]; then
  rm -rf "$sdir"
  [ -d "$sdir" ] && { echo "[FAIL] не удалось удалить остаточный $sdir" >&2; exit 1; }
fi

# Delete the merged branch (safe -d: only if merged; no-op if already gone).
git -C "$proj" branch -d "sdx/$sid" >/dev/null 2>&1 || true

echo "[OK] Closeout-инварианты выполнены: дерево чистое, ветка слита в $def, worktree/сессия $sid освобождены."
