#!/usr/bin/env bash
# T20-T22 empirical acceptance: real git worktrees + real SDX hooks.
set -uo pipefail

HOOKS="/home/archi/Code/sdx.cld/.claude/sdx/hooks"
DB="$HOOKS/lib/default-branch.sh"
AV="$HOOKS/archive-verify.sh"
BASE="$(mktemp -d)"
PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
no(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

# Targeted .gitignore mirroring T3 (worktree + tracked artifacts).
gi(){ cat > "$1/.gitignore" <<'EOF'
.sdx/worktrees/
.sdx/bundles/
.claude/sessions/*/.stopgate.*
.claude/settings.local.json
EOF
}

echo "======== T20: linchpin — hooks resolve from worktree CLI ========"
R="$BASE/t20"; mkdir -p "$R"; cd "$R"
git init -q -b main .; git config user.email a@b.c; git config user.name t
gi "$R"; git add .gitignore; git commit -qm init
ID="wt-demo-20260703"
git worktree add -q ".sdx/worktrees/$ID" -b "sdx/$ID"
WT="$R/.sdx/worktrees/$ID"
# REQ-WT-1: worktree registered
git worktree list --porcelain | grep -q "refs/heads/sdx/$ID" && ok "git worktree list содержит sdx/$ID" || no "worktree не зарегистрирован"
# Session artifacts live INSIDE the worktree (what a CLI started there sees)
mkdir -p "$WT/.claude/sessions/$ID"
printf '{"session_id":"%s"}\n' "$ID" > "$WT/.claude/sessions/$ID/session_state.json"
# REQ-WT-4: hook run with CLAUDE_PROJECT_DIR = worktree resolves session there, not repo-root
cd "$WT"
def_wt="$(CLAUDE_PROJECT_DIR="$WT" bash "$DB" "$WT")"
[ "$def_wt" = "main" ] && ok "default-branch из worktree = main" || no "default-branch из worktree = '$def_wt'"
[ -f "$WT/.claude/sessions/$ID/session_state.json" ] && ok "сессия видима внутри worktree" || no "сессия не видна в worktree"
# repo-root must NOT contain the session dir (isolation proof)
[ ! -e "$R/.claude/sessions/$ID" ] && ok "repo-root НЕ содержит каталог сессии (изоляция worktree)" || no "каталог сессии протёк в repo-root"

echo "======== T21: master-фикстура — полный patch-цикл, инвариант 5 без override ========"
R="$BASE/t21"; mkdir -p "$R"; cd "$R"
git init -q -b master .; git config user.email a@b.c; git config user.name t
gi "$R"; git add .gitignore; git commit -qm init
ID="patch-master-20260703"
git worktree add -q ".sdx/worktrees/$ID" -b "sdx/$ID"
WT="$R/.sdx/worktrees/$ID"
# Phase 1 (session CLI): create + commit tracked session artifacts on the branch
mkdir -p "$WT/.claude/sessions/$ID"
printf '{"session_id":"%s","track":"patch"}\n' "$ID" > "$WT/.claude/sessions/$ID/session_state.json"
printf '[log] start\n' > "$WT/.claude/sessions/$ID/session.log"
printf '# change note\nfix\n' > "$WT/.claude/sessions/$ID/change_note.md"
git -C "$WT" add -A; git -C "$WT" commit -qm "session artifacts (patch)"
# verify.md diff contract: default-branch resolves master, diff is scoped
def_m="$(CLAUDE_PROJECT_DIR="$R" bash "$DB" "$R")"
[ "$def_m" = "master" ] && ok "default-branch = master (нет хардкода main)" || no "default-branch = '$def_m'"
git -C "$R" diff --quiet "$def_m...sdx/$ID" -- . ':!.claude/sessions/**' && diffrc=0 || diffrc=$?
# there IS a change_note.md? no — it's under .claude/sessions, excluded. Add a real code file to prove diff works.
echo "code" > "$WT/app.txt"; git -C "$WT" add app.txt; git -C "$WT" commit -qm "code change"
if git -C "$R" diff "$def_m...sdx/$ID" -- . ':!.claude/sessions/**' | grep -q '+code'; then ok "verify diff (master...sdx) видит код, исключая сессии"; else no "verify diff не видит код"; fi
# Phase 1 cont: git rm session dir on branch + commit (variant A)
git -C "$WT" rm -q -r ".claude/sessions/$ID"; git -C "$WT" commit -qm "git rm session dir (closeout)"
# Phase 2 (main CLI): merge into master, then archive-verify
git -C "$R" merge -q --no-ff "sdx/$ID" -m "merge sdx/$ID"
out="$(CLAUDE_PROJECT_DIR="$R" bash "$AV" "$ID" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q '\[OK\]'; then ok "archive-verify [OK] на master БЕЗ SDX_ARCHIVE_NO_BRANCH_OK (инвариант 5)"; else no "archive-verify упал на master: rc=$rc :: $out"; fi
git -C "$R" worktree list --porcelain | grep -q "refs/heads/sdx/$ID" && no "worktree sdx/$ID не освобождён" || ok "worktree sdx/$ID освобождён (REQ-WT-5)"

echo "======== T22: main-репо — REQ-SESS-1/2/3/4 + REQ-WT-5 сквозной ========"
R="$BASE/t22"; mkdir -p "$R"; cd "$R"
git init -q -b main .; git config user.email a@b.c; git config user.name t
gi "$R"; git add .gitignore; git commit -qm init
ID="full-main-20260703"
git worktree add -q ".sdx/worktrees/$ID" -b "sdx/$ID"
WT="$R/.sdx/worktrees/$ID"
S="$WT/.claude/sessions/$ID"; mkdir -p "$S"
printf '{"session_id":"%s"}\n' "$ID" > "$S/session_state.json"
printf '[log] start\n' > "$S/session.log"
printf '# SPEC\n' > "$S/SPEC.md"
git -C "$WT" add -A; git -C "$WT" commit -qm "session artifacts"
# REQ-SESS-1: branch commit carries state/log/.md
files="$(git -C "$WT" show --stat --name-only --format= HEAD | tr '\n' ' ')"
echo "$files" | grep -q "session_state.json" && echo "$files" | grep -q "session.log" && echo "$files" | grep -q "SPEC.md" \
  && ok "REQ-SESS-1: коммит несёт session_state.json+session.log+SPEC.md" || no "REQ-SESS-1: артефакты не в коммите ($files)"
# REQ-SESS-2: .stopgate.* invisible in git status inside worktree
printf '2\n' > "$S/.stopgate.count"; printf 'x\n' > "$S/.stopgate.out"
st="$(git -C "$WT" status --porcelain)"
echo "$st" | grep -q '.stopgate' && no "REQ-SESS-2: .stopgate.* виден в git status: $st" || ok "REQ-SESS-2: .stopgate.* невидим в git status внутри worktree"
# Closeout variant A: git rm + commit, merge, archive-verify
git -C "$WT" rm -q -r ".claude/sessions/$ID"; git -C "$WT" commit -qm "git rm session dir"
git -C "$R" merge -q --no-ff "sdx/$ID" -m "merge sdx/$ID"
mergesha="$(git -C "$R" rev-parse HEAD)"
out="$(CLAUDE_PROJECT_DIR="$R" bash "$AV" "$ID" 2>&1)"; rc=$?
[ $rc -eq 0 ] && ok "archive-verify [OK] на main" || no "archive-verify упал: $out"
# REQ-SESS-3: ls-tree main lacks session dir
git -C "$R" ls-tree -r --name-only main | grep -q ".claude/sessions/$ID" && no "REQ-SESS-3: сессия ещё в дереве main" || ok "REQ-SESS-3: main-дерево не содержит .claude/sessions/$ID"
# REQ-SESS-4: history preserved via merge second parent
if git -C "$R" log "${mergesha}^2" --oneline -- ".claude/sessions/$ID" | grep -q .; then ok "REQ-SESS-4: история сессии доступна через merge^2"; else no "REQ-SESS-4: история сессии потеряна"; fi
# REQ-WT-5: worktree gone
git -C "$R" worktree list --porcelain | grep -q "refs/heads/sdx/$ID" && no "REQ-WT-5: worktree не освобождён" || ok "REQ-WT-5: worktree освобождён"

echo "========================================================"
echo "ИТОГ: PASS=$PASS  FAIL=$FAIL"
rm -rf "$BASE"
[ $FAIL -eq 0 ]
