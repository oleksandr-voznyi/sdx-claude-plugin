#!/usr/bin/env bash
# Unit tests for archive-verify.sh (REQ-CLOSEOUT-1, REQ-SESS-3/4, REQ-WT-5, REQ-BRANCH-2).
# Runs self-contained: creates temporary git repos (and, for worktree scenarios, real
# git worktrees), exercises the script, cleans up.
# Usage: bash .claude/sdx/hooks/test-archive-verify.sh
# NOTE: CLAUDE_PROJECT_DIR must be exported or inlined with the bash invocation.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/archive-verify.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

TMPPROJ=""
SID="test-sid"

# write_gitignore <dir>: targeted-паттерны из DESIGN (ADR-009) — worktree-каталоги и
# stopgate-эфемерка игнорируются точечно; содержательные артефакты сессии НЕ игнорируются
# (модель tracked-artifacts, ADR-009).
write_gitignore() {
  cat > "$1/.gitignore" <<'EOF'
.sdx/worktrees/
.claude/sessions/*/.stopgate.*
.sdx/bundles/
.claude/settings.local.json
EOF
}

# setup_clean_repo: init git repo with a tracked targeted .gitignore (no widescale
# ignore of .claude/sessions/). Content in the session dir is tracked explicitly by
# each scenario, not hidden by gitignore.
setup_clean_repo() {
  TMPPROJ="$(mktemp -d)"
  git -C "$TMPPROJ" init -q
  git -C "$TMPPROJ" config user.email "test@test.com"
  git -C "$TMPPROJ" config user.name "Test"
  write_gitignore "$TMPPROJ"
  git -C "$TMPPROJ" add .gitignore
  git -C "$TMPPROJ" commit -q -m "init"
  git -C "$TMPPROJ" branch -M main 2>/dev/null || true
}

# track_and_commit <session-dir-relative-path> <message>: stage+commit an already
# populated session directory on the CURRENT branch of $TMPPROJ.
track_and_commit() {
  git -C "$TMPPROJ" add "$1"
  git -C "$TMPPROJ" commit -q -m "$2"
}

cleanup() {
  [ -n "$TMPPROJ" ] && rm -rf "$TMPPROJ"
  TMPPROJ=""
}

echo "=== test-archive-verify.sh ==="
echo ""

# ---- Scenario 1: abort on dirty working tree ----
echo "[1] Abort on dirty working tree (invariant 1)"
setup_clean_repo
# Session dir tracked+committed (does not itself dirty the tree)...
mkdir -p "$TMPPROJ/.claude/sessions/$SID"
printf '{"stage":"Execution"}' > "$TMPPROJ/.claude/sessions/$SID/session_state.json"
track_and_commit ".claude/sessions/$SID" "sdx($SID): init session state"
# ...but an unrelated untracked file dirties the tree.
printf 'dirty\n' > "$TMPPROJ/dirty.txt"

stderr_file="$(mktemp)"
ec=0
CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK" "$SID" >/dev/null 2>"$stderr_file" || ec=$?
stderr_content="$(cat "$stderr_file")"
rm -f "$stderr_file"

if [ "$ec" -eq 1 ] && printf '%s' "$stderr_content" | grep -q "\[FAIL\]"; then
  pass "exit 1, stderr contains [FAIL]"
else
  fail "Expected exit 1 + [FAIL] in stderr" "ec=$ec stderr='$stderr_content'"
fi
# Session dir must NOT have been deleted (abort before destructive actions).
if [ -d "$TMPPROJ/.claude/sessions/$SID" ]; then
  pass "session dir preserved (no premature deletion)"
else
  fail "Session dir was deleted despite FAIL" ""
fi
cleanup

# ---- Scenario 2: abort on unmerged branch ----
echo "[2] Abort on unmerged branch (invariant 5)"
setup_clean_repo
# Session content lives only on sdx/<id> (tracked there), not yet merged into main.
git -C "$TMPPROJ" checkout -q -b "sdx/$SID"
mkdir -p "$TMPPROJ/.claude/sessions/$SID"
printf '{"stage":"Execution"}' > "$TMPPROJ/.claude/sessions/$SID/session_state.json"
track_and_commit ".claude/sessions/$SID" "sdx($SID): init session state"
git -C "$TMPPROJ" checkout -q main
# main has clean tree, no session dir yet (branch not merged).

stderr_file="$(mktemp)"
ec=0
CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK" "$SID" >/dev/null 2>"$stderr_file" || ec=$?
stderr_content="$(cat "$stderr_file")"
rm -f "$stderr_file"

if [ "$ec" -eq 1 ] && printf '%s' "$stderr_content" | grep -q "\[FAIL\]"; then
  pass "exit 1, stderr contains [FAIL]"
else
  fail "Expected exit 1 + [FAIL] in stderr" "ec=$ec stderr='$stderr_content'"
fi
# Branch must NOT have been deleted (abort before destructive actions).
if git -C "$TMPPROJ" branch | grep -q "sdx/$SID"; then
  pass "branch sdx/$SID preserved (no premature deletion)"
else
  fail "Branch sdx/$SID was deleted despite FAIL" ""
fi
cleanup

# ---- Scenario 3: success — variant A executed, all invariants satisfied ----
echo "[3] Success: tracked session dir git-rm'd pre-merge (variant A), branch merged -> [OK]"
setup_clean_repo
git -C "$TMPPROJ" checkout -q -b "sdx/$SID"
mkdir -p "$TMPPROJ/.claude/sessions/$SID"
printf '{"stage":"Execution"}' > "$TMPPROJ/.claude/sessions/$SID/session_state.json"
track_and_commit ".claude/sessions/$SID" "sdx($SID): init session state"
# Variant A (ADR-009): git rm -r on the branch BEFORE merging into main.
git -C "$TMPPROJ" rm -rq ".claude/sessions/$SID"
git -C "$TMPPROJ" commit -q -m "sdx($SID): drop session artifacts pre-merge"
git -C "$TMPPROJ" checkout -q main
git -C "$TMPPROJ" merge -q --no-ff "sdx/$SID" -m "Merge sdx/$SID"

stdout_file="$(mktemp)"
ec=0
CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK" "$SID" >"$stdout_file" 2>/dev/null || ec=$?
stdout_content="$(cat "$stdout_file")"
rm -f "$stdout_file"

if [ "$ec" -eq 0 ] && printf '%s' "$stdout_content" | grep -q "\[OK\]"; then
  pass "exit 0, stdout contains [OK]"
else
  fail "Expected exit 0 + [OK] in stdout" "ec=$ec stdout='$stdout_content'"
fi
if [ ! -e "$TMPPROJ/.claude/sessions/$SID" ]; then
  pass "session dir absent on main (variant A pre-merge git rm)"
else
  fail "Session dir unexpectedly present on main" ""
fi
if ! git -C "$TMPPROJ" branch | grep -q "sdx/$SID"; then
  pass "branch sdx/$SID deleted"
else
  fail "Branch sdx/$SID was NOT deleted" ""
fi
cleanup

# ---- Scenario 4: branch absent -> fail-closed, no deletion (R-5/FND-5a) ----
echo "[4] Branch absent -> [FAIL] (merge unprovable)"
setup_clean_repo
# No sdx/test-sid branch created at all; no session content anywhere.

stderr_file="$(mktemp)"
ec=0
CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK" "$SID" >/dev/null 2>"$stderr_file" || ec=$?
stderr_content="$(cat "$stderr_file")"
rm -f "$stderr_file"

if [ "$ec" -eq 1 ] && printf '%s' "$stderr_content" | grep -q "\[FAIL\]"; then
  pass "exit 1, stderr contains [FAIL] (branch absent)"
else
  fail "Expected exit 1 + [FAIL] in stderr" "ec=$ec stderr='$stderr_content'"
fi
cleanup

# ---- Scenario 5: branch-absent override allows completion (R-5) ----
echo "[5] Branch absent + SDX_ARCHIVE_NO_BRANCH_OK=1 -> [OK]"
setup_clean_repo
# No branch, no session content on main -> invariant 6 trivially satisfied.

stdout_file="$(mktemp)"
ec=0
SDX_ARCHIVE_NO_BRANCH_OK=1 CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK" "$SID" >"$stdout_file" 2>/dev/null || ec=$?
stdout_content="$(cat "$stdout_file")"
rm -f "$stdout_file"

if [ "$ec" -eq 0 ] && printf '%s' "$stdout_content" | grep -q "\[OK\]"; then
  pass "override completes with [OK]"
else
  fail "Expected [OK] under override" "ec=$ec stdout='$stdout_content'"
fi
cleanup

# ---- Scenario 6: anchored match ignores suffix branches (R-5/FND-5b) ----
echo "[6] Unmerged sdx/<id> + merged sdx/<id>-suffix -> [FAIL] (grep -qx anchored)"
setup_clean_repo
# Unmerged target branch.
git -C "$TMPPROJ" checkout -q -b "sdx/$SID"
git -C "$TMPPROJ" commit -q --allow-empty -m "unmerged target"
git -C "$TMPPROJ" checkout -q main
# A *merged* decoy branch whose name has sdx/<id> as a prefix.
git -C "$TMPPROJ" checkout -q -b "sdx/${SID}-decoy"
git -C "$TMPPROJ" commit -q --allow-empty -m "decoy work"
git -C "$TMPPROJ" checkout -q main
git -C "$TMPPROJ" merge -q --no-ff "sdx/${SID}-decoy" -m "Merge decoy"

stderr_file="$(mktemp)"
ec=0
CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK" "$SID" >/dev/null 2>"$stderr_file" || ec=$?
stderr_content="$(cat "$stderr_file")"
rm -f "$stderr_file"

if [ "$ec" -eq 1 ] && printf '%s' "$stderr_content" | grep -q "не слита"; then
  pass "unmerged target not masked by merged suffix branch"
else
  fail "Expected [FAIL] 'не слита' for unmerged target" "ec=$ec stderr='$stderr_content'"
fi
if git -C "$TMPPROJ" branch | grep -q "sdx/$SID"; then
  pass "branch sdx/$SID preserved"
else
  fail "Branch sdx/$SID was deleted despite unmerged target" ""
fi
cleanup

# ==== Worktree scenarios (7, 8, 9) ====

WTDIR=""

# setup_worktree_repo <default_branch>: repo with tracked targeted .gitignore on
# <default_branch>, plus a real `git worktree add -b sdx/<id>` checkout with a
# tracked+committed session dir inside it.
setup_worktree_repo() {
  local default_branch="$1"
  TMPPROJ="$(mktemp -d)"
  git -C "$TMPPROJ" init -q -b "$default_branch"
  git -C "$TMPPROJ" config user.email "test@test.com"
  git -C "$TMPPROJ" config user.name "Test"
  write_gitignore "$TMPPROJ"
  git -C "$TMPPROJ" add .gitignore
  git -C "$TMPPROJ" commit -q -m "init"

  WTDIR="$TMPPROJ/.sdx/worktrees/$SID"
  git -C "$TMPPROJ" worktree add -q -b "sdx/$SID" "$WTDIR" >/dev/null
  mkdir -p "$WTDIR/.claude/sessions/$SID"
  printf '{"stage":"Execution"}' > "$WTDIR/.claude/sessions/$SID/session_state.json"
  git -C "$WTDIR" add ".claude/sessions/$SID"
  git -C "$WTDIR" commit -q -m "sdx($SID): init session state"
}

wt_cleanup() {
  cleanup
  WTDIR=""
}

# ---- Scenario 7: worktree happy path — variant A + merge + [OK] + worktree removed ----
echo "[7] Worktree happy path: variant A pre-merge git rm, merge, worktree removed, branch deleted"
setup_worktree_repo main
# Variant A: git rm -r on the branch (in the worktree) BEFORE merging.
git -C "$WTDIR" rm -rq ".claude/sessions/$SID"
git -C "$WTDIR" commit -q -m "sdx($SID): drop session artifacts pre-merge"
git -C "$TMPPROJ" checkout -q main
git -C "$TMPPROJ" merge -q --no-ff "sdx/$SID" -m "Merge sdx/$SID"

stdout_file="$(mktemp)"
ec=0
CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK" "$SID" >"$stdout_file" 2>/dev/null || ec=$?
stdout_content="$(cat "$stdout_file")"
rm -f "$stdout_file"

if [ "$ec" -eq 0 ] && printf '%s' "$stdout_content" | grep -q "\[OK\]"; then
  pass "exit 0, stdout contains [OK]"
else
  fail "Expected exit 0 + [OK] in stdout" "ec=$ec stdout='$stdout_content'"
fi
if ! git -C "$TMPPROJ" worktree list | grep -q "$WTDIR"; then
  pass "worktree removed (absent from git worktree list)"
else
  fail "Worktree still present in git worktree list" ""
fi
if [ ! -d "$WTDIR" ]; then
  pass "worktree directory removed from disk"
else
  fail "Worktree directory still on disk" ""
fi
if ! git -C "$TMPPROJ" branch | grep -q "sdx/$SID"; then
  pass "branch sdx/$SID deleted"
else
  fail "Branch sdx/$SID was NOT deleted" ""
fi
wt_cleanup

# ---- Scenario 8: pre-merge git rm skipped -> invariant 6 [FAIL], worktree NOT removed ----
echo "[8] Skipped pre-merge git rm: session dir merged tracked -> invariant 6 [FAIL], worktree preserved"
setup_worktree_repo main
# NOTE: no git rm step — session dir merges into main still tracked (variant A violated).
git -C "$TMPPROJ" checkout -q main
git -C "$TMPPROJ" merge -q --no-ff "sdx/$SID" -m "Merge sdx/$SID"

stderr_file="$(mktemp)"
ec=0
CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK" "$SID" >/dev/null 2>"$stderr_file" || ec=$?
stderr_content="$(cat "$stderr_file")"
rm -f "$stderr_file"

if [ "$ec" -eq 1 ] && printf '%s' "$stderr_content" | grep -q "\[FAIL\]"; then
  pass "exit 1, stderr contains [FAIL] (invariant 6)"
else
  fail "Expected exit 1 + [FAIL] in stderr" "ec=$ec stderr='$stderr_content'"
fi
if git -C "$TMPPROJ" worktree list | grep -q "$WTDIR"; then
  pass "worktree preserved (not removed on FAIL)"
else
  fail "Worktree was removed despite FAIL" ""
fi
wt_cleanup

# ---- Scenario 9: master repository — invariant 5 passes on master without override ----
echo "[9] git init -b master: full variant-A cycle passes invariant 5 on master (no override)"
setup_worktree_repo master
git -C "$WTDIR" rm -rq ".claude/sessions/$SID"
git -C "$WTDIR" commit -q -m "sdx($SID): drop session artifacts pre-merge"
git -C "$TMPPROJ" checkout -q master
git -C "$TMPPROJ" merge -q --no-ff "sdx/$SID" -m "Merge sdx/$SID"

stdout_file="$(mktemp)"
ec=0
CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK" "$SID" >"$stdout_file" 2>/dev/null || ec=$?
stdout_content="$(cat "$stdout_file")"
rm -f "$stdout_file"

if [ "$ec" -eq 0 ] && printf '%s' "$stdout_content" | grep -q "\[OK\]"; then
  pass "exit 0, stdout contains [OK] (default branch resolved to master, no override needed)"
else
  fail "Expected exit 0 + [OK] on master without SDX_ARCHIVE_NO_BRANCH_OK" "ec=$ec stdout='$stdout_content'"
fi
wt_cleanup

# ==== Deployment-robustness scenarios (10, 11) — BUG-008 ====

STRIPDIR=""
HOOK_COPY=""

# make_hook_copy: copy archive-verify.sh + lib/ into a temp dir, mirroring an install
# that did not preserve the exec bit (observed: all sdx/hooks/**/*.sh delivered 0600).
# Sets STRIPDIR and HOOK_COPY; caller runs the copy through `bash`, as /sdx:archive does.
# Assigns globals directly — a `$(...)` call would run this in a subshell and leave
# STRIPDIR empty in the caller.
make_hook_copy() {
  STRIPDIR="$(mktemp -d)"
  mkdir -p "$STRIPDIR/lib"
  cp "$HOOK" "$STRIPDIR/archive-verify.sh"
  cp "$SCRIPT_DIR/lib/"*.sh "$STRIPDIR/lib/"
  chmod 0600 "$STRIPDIR/archive-verify.sh" "$STRIPDIR/lib/"*.sh
  HOOK_COPY="$STRIPDIR/archive-verify.sh"
}

strip_cleanup() {
  cleanup
  [ -n "$STRIPDIR" ] && rm -rf "$STRIPDIR"
  STRIPDIR=""; HOOK_COPY=""
}

# setup_merged_repo: clean repo where the full variant-A cycle is already complete — the state
# in which archive-verify must report [OK]. Shared by scenarios 10 and 11.
setup_merged_repo() {
  setup_clean_repo
  git -C "$TMPPROJ" checkout -q -b "sdx/$SID"
  mkdir -p "$TMPPROJ/.claude/sessions/$SID"
  printf '{"stage":"Execution"}' > "$TMPPROJ/.claude/sessions/$SID/session_state.json"
  track_and_commit ".claude/sessions/$SID" "sdx($SID): init session state"
  git -C "$TMPPROJ" rm -rq ".claude/sessions/$SID"
  git -C "$TMPPROJ" commit -q -m "sdx($SID): drop session artifacts pre-merge"
  git -C "$TMPPROJ" checkout -q main
  git -C "$TMPPROJ" merge -q --no-ff "sdx/$SID" -m "Merge sdx/$SID"
}

# ---- Scenario 10: lib/*.sh without the exec bit -> resolver still works (BUG-008) ----
echo "[10] lib/*.sh delivered без бита x: default branch still resolves -> [OK]"
setup_merged_repo
make_hook_copy

out_file="$(mktemp)"; err_file="$(mktemp)"
ec=0
CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK_COPY" "$SID" >"$out_file" 2>"$err_file" || ec=$?
stdout_content="$(cat "$out_file")"; stderr_content="$(cat "$err_file")"
rm -f "$out_file" "$err_file"

if [ "$ec" -eq 0 ] && printf '%s' "$stdout_content" | grep -q "\[OK\]"; then
  pass "exit 0 + [OK] despite non-executable lib/*.sh"
else
  fail "Expected exit 0 + [OK] with stripped exec bit" "ec=$ec stdout='$stdout_content' stderr='$stderr_content'"
fi
# The regression signature: resolver output empty -> 'in .' / malformed object name.
if printf '%s' "$stdout_content" | grep -q "слита в main"; then
  pass "default branch name present in output (not empty)"
else
  fail "Default branch name missing from [OK] line" "stdout='$stdout_content'"
fi
if ! printf '%s' "$stderr_content" | grep -qi "permission denied\|malformed object name"; then
  pass "no Permission denied / malformed object name on stderr"
else
  fail "Exec-bit dependency still present" "stderr='$stderr_content'"
fi
strip_cleanup

# ---- Scenario 11: resolver yields nothing -> explicit [FAIL], no destructive action ----
echo "[11] default-branch.sh returns empty -> explicit [FAIL], branch preserved"
setup_merged_repo
make_hook_copy
# Resolver that succeeds but prints nothing — stands in for any future way of ending up
# with an empty $def. Without the guard this reaches git as an empty ref.
printf '#!/usr/bin/env bash\nexit 0\n' > "$STRIPDIR/lib/default-branch.sh"

err_file="$(mktemp)"
ec=0
CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK_COPY" "$SID" >/dev/null 2>"$err_file" || ec=$?
stderr_content="$(cat "$err_file")"
rm -f "$err_file"

if [ "$ec" -eq 1 ] && printf '%s' "$stderr_content" | grep -q "не удалось определить основную ветку"; then
  pass "exit 1 with cause-naming [FAIL] (not a bogus 'не слита')"
else
  fail "Expected [FAIL] about the default branch" "ec=$ec stderr='$stderr_content'"
fi
if ! printf '%s' "$stderr_content" | grep -q "не слита"; then
  pass "no misleading 'не слита' verdict"
else
  fail "Emitted misleading merge verdict on empty \$def" "stderr='$stderr_content'"
fi
if git -C "$TMPPROJ" branch | grep -q "sdx/$SID"; then
  pass "branch sdx/$SID preserved (abort before destructive actions)"
else
  fail "Branch deleted despite FAIL" ""
fi
strip_cleanup

# ---- Scenario 12: invariant 1 is self-diagnosing. The message must name the offending paths,
#      and for untracked ones point at the likely cause. Motivation: a consumer whose project
#      predates a new targeted .gitignore pattern (this happened with the self-test cache) got
#      "рабочее дерево не чистое" and went looking for uncommitted edits that did not exist. ----
echo "[12] Invariant 1 names the offending paths and hints at /sdx:reconcile for untracked ones"
setup_clean_repo
touch "$TMPPROJ/some-untracked-artifact"
out="$(CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK" test-sid 2>&1 || true)"
has_path=0; has_hint=0
case "$out" in *"some-untracked-artifact"*) has_path=1 ;; esac
case "$out" in *"/sdx:reconcile"*) has_hint=1 ;; esac
if [ "$has_path" -eq 1 ] && [ "$has_hint" -eq 1 ]; then
  pass "message lists the path and names /sdx:reconcile as the likely fix"
else
  fail "invariant 1 message is not self-diagnosing" "path listed: $has_path, reconcile hint: $has_hint"
fi
cleanup

# ---- Scenario 13: the hint is specific to untracked files, not printed for a tracked edit —
#      otherwise it would misdirect on the ordinary "you forgot to commit" case. ----
echo "[13] A tracked modification triggers invariant 1 WITHOUT the untracked hint"
setup_clean_repo
printf 'changed\n' >> "$TMPPROJ/.gitignore"
out="$(CLAUDE_PROJECT_DIR="$TMPPROJ" bash "$HOOK" test-sid 2>&1 || true)"
if printf '%s' "$out" | grep -q 'не чистое' && ! printf '%s' "$out" | grep -q '/sdx:reconcile'; then
  pass "tracked edit reported without the untracked-specific hint"
else
  fail "hint shown for a tracked modification" "would misdirect the ordinary forgot-to-commit case"
fi
cleanup

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "ALL PASSED"
  exit 0
else
  exit 1
fi
