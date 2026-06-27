#!/usr/bin/env bash
# SDX archive-verify (REQ-CLOSEOUT-1): enforce Closeout invariants 1, 5, 6.
# Usage: archive-verify.sh <session_id>
# Called from /sdx:archive AFTER the session branch has been merged into main.
# Exits 0 on success (all invariants satisfied), 1 on any failure (destructive
# actions are NOT performed until invariants 1 and 5 are both satisfied).
set -uo pipefail

proj="${CLAUDE_PROJECT_DIR:-.}"
sid="${1:?session_id required}"
sdir="$proj/.claude/sessions/$sid"
fail=0

# Invariant 1: working tree must be clean (no uncommitted changes).
if [ -n "$(git -C "$proj" status --porcelain)" ]; then
  echo "[FAIL] рабочее дерево не чистое — есть незакоммиченные изменения." >&2
  fail=1
fi

# Invariant 5: branch sdx/<id> must be provably merged into main before any
# destructive action (R-5/FND-5).
if git -C "$proj" rev-parse --verify "sdx/$sid" >/dev/null 2>&1; then
  # Exact name match (-qx): avoid matching sdx/<id>-suffix branches.
  if ! git -C "$proj" branch --merged main --format='%(refname:short)' | grep -qx "sdx/$sid"; then
    echo "[FAIL] ветка sdx/$sid не слита в main." >&2
    fail=1
  fi
elif [ "${SDX_ARCHIVE_NO_BRANCH_OK:-0}" != "1" ]; then
  # Branch absent: merge is UNPROVABLE. A branch deleted while unmerged would lose
  # the only trace of the session, so refuse to delete without explicit operator
  # confirmation (set SDX_ARCHIVE_NO_BRANCH_OK=1 to override in /sdx:archive).
  echo "[FAIL] ветка sdx/$sid отсутствует — слияние недоказуемо; деструктив отменён. Подтвердите вручную (SDX_ARCHIVE_NO_BRANCH_OK=1), если ветка была удалена после слияния." >&2
  fail=1
fi

# Abort before any destructive action if invariants 1 or 5 are violated.
if [ "$fail" -ne 0 ]; then
  echo "[ABORT] Closeout не завершён — устраните FAIL и повторите." >&2
  exit 1
fi

# Invariant 6: delete session directory and verify removal (historically skipped step).
rm -rf "$sdir"
if [ -d "$sdir" ]; then
  echo "[FAIL] не удалось удалить $sdir" >&2
  exit 1
fi

# Delete the merged branch (no-op if already removed).
git -C "$proj" branch -d "sdx/$sid" >/dev/null 2>&1 || true

echo "[OK] Closeout-инварианты выполнены: дерево чистое, ветка слита, сессия $sid удалена."
