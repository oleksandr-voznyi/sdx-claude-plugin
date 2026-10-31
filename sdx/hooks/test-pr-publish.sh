#!/usr/bin/env bash
# Tests for sdx/hooks/pr-publish.sh (FEAT-017, REQ-PKG-10, 14, 15, 16, 18, 35).
# pr-publish.sh pushes the built package branch change/<C>-<executor> to the remote (the order's repo.url, --remote, or origin)
# by an EXPLICIT refspec and, for a github host with the gh CLI, opens a pull request. The user's confirmation is the job of
# the /sdx:pr command BEFORE the call; the script protects itself anyway: only change/*, never a force/all/mirror/tags push,
# a whitelist of URL schemes, prod-guard on the synthesised `git push`, fast-forward only.
# Fixture: lib/pkg-fixture.sh (one template per run, cp -Rp per block, hermetic git). The "remote" is a local bare repository
# (the order's repo.url resolves to it by an insteadOf rule); the gh CLI is a stub in PATH that records its argv.
#
#  [P1] push into a local bare as repo.url: exactly one new ref refs/heads/change/<C>-<exec>, no sdx/s1, no tags; JSON; remote_sha == tip
#  [P2] hostile config (push.default=matching, remote.origin.push=+refs/heads/*, push.followTags=true + annotated tags) -> still only change/*
#  [P3] not fast-forward -> rc 1; repeat of an already pushed package -> rc 0, already:true; a fast-forward continuation goes without force
#  [P4] hosting detection: github.com URLs -> github, local path -> bare, the order's hint and --hosting win
#  [P5] gh stub: list then create with the exact argv; body content; no gh -> degraded gh-missing; unauthenticated; PR exists; gh fails
#  [P6] refusals: a non-change branch, ext:: / -o... / spaced URL, no remote, prod-guard.conf with `git push`
#  [P7] credentials of https://u:p@host/x.git never reach stdout / stderr / JSON (--dry-run)
#  [Port] portability of pr-publish.sh (BUG-010), no force/all/mirror/tags/+refspec; red side
#  [Mut] mutation runs (copies of pr-publish.sh + lib/ + prod-guard.sh in a temp dir, anchors "# PKG-P-*")
# Env: PR_PUBLISH_ONLY="P1 P3" selects blocks; PR_PUBLISH_UNDER_TEST=<script> (mutants); PR_PUBLISH_NESTED=1 (no mutation section).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUT="${PR_PUBLISH_UNDER_TEST:-$SCRIPT_DIR/pr-publish.sh}"
export PYTHONDONTWRITEBYTECODE=1
unset EMAIL GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL SDX_MANDATE_TODAY

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
info() { echo "  INFO: $1"; }
want() { [ -z "${PR_PUBLISH_ONLY:-}" ] && return 0; case " $PR_PUBLISH_ONLY " in *" $1 "*) return 0 ;; esac; return 1; }
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "got [$2] expected [$3]"; fi; }
has() { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "[$3] not in [$2]" ;; esac; }
hasnt() { case "$2" in *"$3"*) fail "$1" "[$3] found in [$2]" ;; *) pass "$1" ;; esac; }

echo "=== test-pr-publish.sh ==="
echo ""

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/pkg-fixture.sh"
. "$SCRIPT_DIR/lib/miniyaml.sh"
if ! pkg_fixture_template "$TMP"; then echo "FATAL: cannot build the fixture template" >&2; exit 2; fi
BR=change/C-ACME-001-ex1

NFX=0
newfx() {   # -> WC, REM: a fresh copy of the template (sdx/s1 checked out) and its bare remote
  NFX=$((NFX + 1))
  pkg_fixture_copy "$TMP/fx$NFX" || { fail "fixture copy" "pkg_fixture_copy failed"; return 1; }
  WC="$PKG_WC"; REM="$PKG_REMOTE"
}
gw() { git -C "$WC" "$@"; }
build_pkg() {   # <wc> [pr-build args]: a package from pr-build.sh -> TIP, HEAD_SHA
  local out w="$1"; shift
  out="$(bash "$SCRIPT_DIR/pr-build.sh" --sid s1 --proj "$w" "$@" 2>"$TMP/build.err")" || { fail "pr-build for the fixture" "$(cat "$TMP/build.err")"; return 1; }
  TIP="$(printf '%s' "$out" | jq -r .tip)"; HEAD_SHA="$(printf '%s' "$out" | jq -r .head)"
}
run_pub() {   # <wc> [args] -> POUT PERR PRC
  local wc="$1"; shift
  POUT="$(bash "${SUTX:-$SUT}" --sid s1 --proj "$wc" "$@" 2>"$TMP/stderr")"; PRC=$?
  PERR="$(cat "$TMP/stderr")"
}
jv() { printf '%s' "$POUT" | jq -r "$1" 2>/dev/null; }
remote_refs() { git -C "$1" for-each-ref --format='%(refname)' | tr '\n' ' ' | sed 's/ $//'; }
fx_set_order() {   # <wc> <order.yaml file>: rebuild sdx/s1 with another order snapshot
  local wc="$1" src="$2" idx="$TMP/idx.$$" b c1 c2 c3 bl
  b="$(git -C "$wc" rev-parse refs/heads/dev)"; bl="$(git -C "$wc" hash-object -w "$src")"
  rebuild() {
    rm -f "$idx"; GIT_INDEX_FILE="$idx" git -C "$wc" read-tree "$1"
    GIT_INDEX_FILE="$idx" git -C "$wc" update-index --add --cacheinfo "100644,$bl,.claude/sessions/s1/order.yaml"
    local t; t="$(GIT_INDEX_FILE="$idx" git -C "$wc" write-tree)"
    printf 'rebuilt\n' | git -C "$wc" commit-tree "$t" -p "$2"
  }
  c1="$(rebuild refs/heads/sdx/s1~2 "$b")"; c2="$(rebuild refs/heads/sdx/s1~1 "$c1")"
  c3="$(printf 'close\n' | git -C "$wc" commit-tree "refs/heads/sdx/s1^{tree}" -p "$c2")"
  git -C "$wc" reset -q --hard "$c3"; rm -f "$idx"
}
order_with() {   # <wc> <sed expr>: edit the order snapshot of the session history
  git -C "$1" show refs/heads/sdx/s1~1:.claude/sessions/s1/order.yaml | sed "$2" > "$TMP/order-var.yaml"
  fx_set_order "$1" "$TMP/order-var.yaml"
}

# ---------------------------------------------------------------------------------------------------- [P1]
blk_P1() {
echo "[P1] push into a local bare repository (repo.url of the order)"
newfx && {
  build_pkg "$WC" || return 0
  eq "P1 before: the remote has dev only" "$(remote_refs "$REM")" "refs/heads/dev"
  run_pub "$WC"
  eq "P1 rc 0" "$PRC" "0"
  eq "P1 the remote gained exactly one ref: change/<C>-<exec>" "$(remote_refs "$REM")" "refs/heads/change/C-ACME-001-ex1 refs/heads/dev"
  eq "P1 no sdx/* on the remote" "$(git -C "$REM" for-each-ref --format='%(refname)' 'refs/heads/sdx/*' | wc -l | tr -d ' ')" "0"
  eq "P1 no tags on the remote" "$(git -C "$REM" for-each-ref --format='%(refname)' refs/tags | wc -l | tr -d ' ')" "0"
  eq "P1 JSON branch" "$(jv .branch)" "$BR"
  eq "P1 JSON pushed" "$(jv .pushed)" "true"
  eq "P1 JSON already" "$(jv .already)" "false"
  eq "P1 JSON remote_sha == tip" "$(jv .remote_sha)" "$TIP"
  eq "P1 the remote ref == tip" "$(git -C "$REM" rev-parse "refs/heads/$BR")" "$TIP"
  eq "P1 JSON keys" "$(jv 'keys|join(",")')" "already,branch,degraded,hosting,instruction,pr,pushed,remote,remote_sha" 
  eq "P1 local bare -> hosting bare, no PR" "$(jv '.hosting+"/"+(.pr|tostring)')" "bare/null"
  eq "P1 the working tree and HEAD are untouched" "$(gw status --porcelain)$(gw symbolic-ref HEAD)" "refs/heads/sdx/s1"
}
}

# ---------------------------------------------------------------------------------------------------- [P2]
blk_P2() {
echo "[P2] hostile git configuration cannot widen the push"
newfx && {
  build_pkg "$WC" || return 0
  gw config push.default matching
  gw config remote.origin.push '+refs/heads/*:refs/heads/*'
  gw config push.followTags true
  git -C "$WC" -c user.name=t -c user.email=t@t.t tag -a -m "on head" t-head "$HEAD_SHA"
  git -C "$WC" -c user.name=t -c user.email=t@t.t tag -a -m "on session" t-sess refs/heads/sdx/s1
  run_pub "$WC" --remote origin
  eq "P2 rc 0" "$PRC" "0"
  eq "P2 only change/* was added (and dev stays)" "$(remote_refs "$REM")" "refs/heads/change/C-ACME-001-ex1 refs/heads/dev"
  eq "P2 no tags on the remote (followTags is neutralised)" "$(git -C "$REM" for-each-ref --format='%(refname)' refs/tags | wc -l | tr -d ' ')" "0"
  eq "P2 dev on the remote is the original" "$(git -C "$REM" rev-parse refs/heads/dev)" "$(gw rev-parse refs/remotes/origin/dev)"
}
}

# ---------------------------------------------------------------------------------------------------- [P3]
blk_P3() {
echo "[P3] fast-forward only; idempotence"
newfx && {   # a foreign commit already sits on the remote branch
  build_pkg "$WC" || return 0
  foreign="$(printf 'foreign\n' | gw commit-tree "refs/heads/dev^{tree}")"
  git -C "$WC" push -q "$REM" "$foreign:refs/heads/$BR" >/dev/null 2>&1
  run_pub "$WC"
  eq "P3 non-fast-forward: rc 1" "$PRC" "1"
  has "P3 ... our own message (not git's)" "$PERR" "не предок"
  eq "P3 the foreign commit is intact" "$(git -C "$REM" rev-parse "refs/heads/$BR")" "$foreign"
}
newfx && {   # repeat of an already pushed package; then a fast-forward continuation (re-submission)
  build_pkg "$WC" || return 0; first="$TIP"
  run_pub "$WC"; eq "P3 first push rc 0" "$PRC" "0"
  run_pub "$WC"
  eq "P3 repeat: rc 0" "$PRC" "0"
  eq "P3 repeat: already true, pushed true" "$(jv '(.already|tostring)+"/"+(.pushed|tostring)')" "true/true"
  eq "P3 repeat: remote_sha is the tip" "$(jv .remote_sha)" "$first"
  printf 'a=3\n' >> "$WC/src/mod1/a.js"; gw commit -q -am "round 2"
  build_pkg "$WC" --resubmit || return 0; second="$TIP"
  run_pub "$WC"
  eq "P3 re-submission: rc 0, no force" "$PRC" "0"
  eq "P3 re-submission: the remote moved to the new tip" "$(git -C "$REM" rev-parse "refs/heads/$BR")" "$second"
  eq "P3 re-submission: the old tip is an ancestor of the new one (a fast-forward chain)" "$(git -C "$REM" merge-base --is-ancestor "$first" "$second" && echo yes)" "yes"
  eq "P3 re-submission: JSON already false" "$(jv .already)" "false"
}
}

# ---------------------------------------------------------------------------------------------------- [P4]
blk_P4() {
echo "[P4] hosting detection (no network: --dry-run)"
host_of() {   # <label> <expected> [args]
  local label="$1" exp="$2"; shift 2
  run_pub "$WC" --dry-run "$@"
  eq "P4 $label" "$(jv .hosting)" "$exp"
}
newfx && {
  build_pkg "$WC" || return 0
  host_of "https://github.com/o/r.git -> github" github --remote https://github.com/o/r.git
  host_of "git@github.com:o/r.git -> github" github --remote git@github.com:o/r.git
  host_of "ssh://git@github.com/o/r.git -> github" github --remote ssh://git@github.com/o/r.git
  host_of "a local path -> bare" bare --remote "$REM"
  host_of "another host -> bare" bare --remote https://git.example.com/o/r.git
  host_of "--hosting github overrides the detection" github --hosting github --remote "$REM"
  host_of "--hosting bare overrides the detection" bare --hosting bare --remote https://github.com/o/r.git
}
newfx && {   # the hint of the order wins over the host name
  order_with "$WC" 's|^    base: "dev"$|    base: "dev"\n    hosting: "bare"|'
  build_pkg "$WC" || return 0
  host_of "the order's hint 'bare' beats github.com" bare --remote https://github.com/o/r.git
}
newfx && {
  order_with "$WC" 's|^    base: "dev"$|    base: "dev"\n    hosting: "github"|'
  build_pkg "$WC" || return 0
  host_of "the order's hint 'github' beats a local path" github --remote "$REM"
}
}

# ---------------------------------------------------------------------------------------------------- [P6]
blk_P6() {
echo "[P6] refusals"
refuse() {   # <label> <stderr fragment> [args]: rc 1, the fragment, nothing pushed, no marker file
  local label="$1" frag="$2"; shift 2
  run_pub "$WC" "$@"
  eq "P6 $label: rc 1" "$PRC" "1"
  has "P6 $label: the reason is named" "$PERR" "$frag"
  eq "P6 $label: nothing was pushed" "$(remote_refs "$REM")" "refs/heads/dev"
  eq "P6 $label: no marker file" "$(ls "$WC/MARK" 2>/dev/null | wc -l | tr -d ' ')" "0"
}
newfx && {
  build_pkg "$WC" || return 0
  refuse "ext:: remote helper" "недопустимый remote/URL" --remote "ext::sh -c 'touch $WC/MARK'"
  refuse "-oProxyCommand" "недопустимый remote/URL" --remote "-oProxyCommand=touch $WC/MARK"
  refuse "URL with a space" "недопустимый remote/URL" --remote "https://x.example/a b.git"
  refuse "fd:: helper" "недопустимый remote/URL" --remote "fd::3"
  refuse "unknown remote name" "недопустимый remote/URL" --remote "no-such-remote"
  refuse "an invalid commitment on the command line" "commitment:" --commitment "x/../sdx"
}
newfx && {   # no repo.url in the order and no remote origin
  git -C "$WC" show refs/heads/sdx/s1~1:.claude/sessions/s1/order.yaml | sed '/^    url: /d' > "$TMP/order-nourl.yaml"
  fx_set_order "$WC" "$TMP/order-nourl.yaml"
  gw remote remove origin
  build_pkg "$WC" || return 0
  refuse "no repo.url and no remote" "недопустимый remote/URL"
}
newfx && {   # prod-guard.conf with a push pattern
  build_pkg "$WC" || return 0
  mkdir -p "$WC/.claude/sdx"; printf 'git push\n' > "$WC/.claude/sdx/prod-guard.conf"
  refuse "prod-guard.conf blocks git push" "prod-guard"
}
newfx && {   # defence in depth: a branch outside change/* (the library is patched to compute it)
  mkdir -p "$TMP/patched/hooks" && cp -Rp "$SCRIPT_DIR/lib" "$TMP/patched/hooks/lib" && cp "$SUT" "$TMP/patched/hooks/pr-publish.sh" && cp "$SCRIPT_DIR/prod-guard.sh" "$TMP/patched/hooks/prod-guard.sh"
  git -C "$WC" show refs/heads/sdx/s1~1:.claude/sessions/s1/order.yaml | sed '/^  deliver:/,$d' > "$TMP/order-nodel.yaml"
  fx_set_order "$WC" "$TMP/order-nodel.yaml"
  build_pkg "$WC" || return 0
  for nb in main sdx/s1; do
    sed "s|PR_BRANCH=\"change/\$PR_C-\$PR_EXEC\"|PR_BRANCH=\"$nb\"|" "$SCRIPT_DIR/lib/pr-lib.sh" > "$TMP/patched/hooks/lib/pr-lib.sh"
    git -C "$WC" branch -q -f "$nb" "$TIP" 2>/dev/null || true
    SUTX="$TMP/patched/hooks/pr-publish.sh" run_pub "$WC"
    eq "P6 branch '$nb' is refused: rc 1" "$PRC" "1"
    has "P6 branch '$nb': only change/* is published" "$PERR" "change/"
    eq "P6 branch '$nb': nothing was pushed" "$(remote_refs "$REM")" "refs/heads/dev"
  done
}
}

# ---------------------------------------------------------------------------------------------------- [P7]
blk_P7() {
echo "[P7] credentials of a URL never reach the output"
newfx && {
  build_pkg "$WC" || return 0
  both="$TMP/p7.out"
  bash "$SUT" --sid s1 --proj "$WC" --dry-run --remote "https://usr:s3cr3tpw@git.example.com/o/r.git" > "$both" 2>&1; rc=$?
  eq "P7 --dry-run: rc 0" "$rc" "0"
  eq "P7 the password is not in stdout/stderr" "$(grep -c 's3cr3tpw' "$both")" "0"
  eq "P7 the user name is not there either" "$(grep -c 'usr:' "$both")" "0"
  eq "P7 the URL is shown without credentials" "$(jq -r .remote < <(grep '^{' "$both"))" "https://git.example.com/o/r.git"
  bash "$SUT" --sid s1 --proj "$WC" --remote "https://usr:s3cr3tpw@127.0.0.1:1/o/r.git" > "$both" 2>&1; rc=$?
  eq "P7 a failing push to the same URL: rc 1" "$rc" "1"
  eq "P7 ... and the password is still not in the output" "$(grep -c 's3cr3tpw' "$both")" "0"
}
}

# @@TAIL@@
# ---- the blocks are independent (each builds its own fixture copy): run them concurrently, print in the declared order ----
run_blocks() {
  local b
  for b in "$@"; do
    want "$b" || continue
    ( TMP="$TMP/blk-$b"; mkdir -p "$TMP"; "blk_$b" ) > "$TMP/out-$b.txt" 2>&1 &
  done
  wait
  for b in "$@"; do
    want "$b" || continue
    cat "$TMP/out-$b.txt"
    PASS_COUNT=$((PASS_COUNT + $(grep -c "^  PASS: " "$TMP/out-$b.txt")))
    FAIL_COUNT=$((FAIL_COUNT + $(grep -c "^  FAIL: " "$TMP/out-$b.txt")))
  done
}
run_blocks P1 P2 P3 P4 P6 P7

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
