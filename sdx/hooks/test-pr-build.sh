#!/usr/bin/env bash
# Tests for sdx/hooks/pr-build.sh (FEAT-017, REQ-PKG-5..10, 12, 18, 19, 26).
# pr-build.sh squashes the session branch sdx/<sid> into ONE commit (the "head" of the package), then writes
# CHANGE.yaml as a separate last commit on top of it, all by git plumbing: no checkout, no write to the
# working tree or the real index; the only new ref is refs/heads/change/<C>-<executor>.
# Fixture: lib/pkg-fixture.sh (one template per run, cp -Rp per block, hermetic git). python3/PyYAML appear
# ONLY as the independent oracle `pkg_oracle` (a transliteration of audit() of the node) — INFO-skip, never PASS.
#
#  [B1]  golden path: rc 0, JSON, tip^ == head, head's parent == base, exactly one commit base..head with subject "C: title",
#        oracle -> approve; built-in negative: the oracle on a damaged package is not approve
#  [B2]  plumbing: HEAD, branch, `git status`, `git ls-files -s` unchanged; no CHANGE.yaml on disk; tip tree = head tree + one blob
#  [B3]  archive_sha256 == sha256(git archive --format=tar head) recomputed in an INDEPENDENT clone and in the fixture
#  [B4]  scope_touched includes the generated lock file; touches_shared true / false
#  [B5]  adr (registry changed / not / docs_in_repo none), spec present / absent, verify.tests pass / unknown
#  [B6]  escaping: hostile title -> manifest parsed by miniyaml and by yaml.safe_load (oracle) to the same values
#  [B7]  refusals (executor with ':', hostile C, secret in title, control char in a path, CHANGE.yaml in code, empty diff,
#        session directory in the tree, no mandate, mandate without endpoint.yaml, wrong branch, no git identity)
#  [B8a] re-submission before the manifest: existing change/* -> rc 3 NEED resubmit; --resubmit -> parent = old tip;
#        a non-package change/* -> rc 1;  [B8] race on the ref (CAS)
#  [B9]  diverged base: rc 3 NEED allow-diverged; with the flag the diff base..head is only the session's; conflict -> rc 1
#  [B10] template-driven generation: keys and order of the manifest = keys of sdx/mo/CHANGE.template.yaml
#  [B11] the package tree has no .claude/sessions/ and no protocol.yaml
#  [B12] the manifest commit's parent is head (not base) and it changes exactly one file
#  [Mut] mutation runs (copies of pr-build.sh + lib/ in a temp dir, anchors "# PKG-*")
# Env: PR_BUILD_ONLY="B7 B9" selects blocks; PR_BUILD_UNDER_TEST=<script> (mutants); PR_BUILD_NESTED=1 (no mutation
# section); SCEN_MIN=1 (mutation runs: only the distinguishing block, set by the parent).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUT="${PR_BUILD_UNDER_TEST:-$SCRIPT_DIR/pr-build.sh}"
export PYTHONDONTWRITEBYTECODE=1
unset EMAIL GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL SDX_MANDATE_TODAY

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
info() { echo "  INFO: $1"; }
want() { [ -z "${PR_BUILD_ONLY:-}" ] && return 0; case " $PR_BUILD_ONLY " in *" $1 "*) return 0 ;; esac; return 1; }
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "got [$2] expected [$3]"; fi; }
has() { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "[$3] not in [$2]" ;; esac; }

echo "=== test-pr-build.sh ==="
echo ""

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/pkg-fixture.sh"
. "$SCRIPT_DIR/lib/miniyaml.sh"
if ! pkg_fixture_template "$TMP"; then echo "FATAL: cannot build the fixture template" >&2; exit 2; fi
ZERO=0000000000000000000000000000000000000000

NFX=0
newfx() {   # -> WC: a fresh copy of the template (sdx/s1 checked out)
  NFX=$((NFX + 1))
  pkg_fixture_copy "$TMP/fx$NFX" || { fail "fixture copy" "pkg_fixture_copy failed"; return 1; }
  WC="$PKG_WC"
}
run_build() {   # <wc> [args] -> BOUT BERR BRC
  local wc="$1"; shift
  BOUT="$(bash "$SUT" --sid s1 --proj "$wc" "$@" 2>"$TMP/stderr")"; BRC=$?
  BERR="$(cat "$TMP/stderr")"
}
jv() { printf '%s' "$BOUT" | jq -r "$1" 2>/dev/null; }
gw() { git -C "$WC" "$@"; }
mand_edit() {   # <sed expr>: edit the (untracked) mandate of the current copy
  sed "$1" "$WC/.mesh/mandate.yaml" > "$WC/.mesh/mandate.new" && mv "$WC/.mesh/mandate.new" "$WC/.mesh/mandate.yaml"
}
# fx_set_order <wc> <file|none>: rebuild the history of sdx/s1 with another order.yaml snapshot (or without one) by plumbing
fx_set_order() {
  local wc="$1" src="$2" idx="$TMP/idx.$$" b t1 t2 t3 c1 c2 c3
  b="$(git -C "$wc" rev-parse refs/heads/dev)"
  rebuild() {   # <rev> <parent>: the tree of <rev> with the order replaced -> commit
    rm -f "$idx"
    GIT_INDEX_FILE="$idx" git -C "$wc" read-tree "$1"
    if [ "$src" = none ]; then GIT_INDEX_FILE="$idx" git -C "$wc" update-index --force-remove .claude/sessions/s1/order.yaml
    else
      local bl; bl="$(git -C "$wc" hash-object -w "$src")"
      GIT_INDEX_FILE="$idx" git -C "$wc" update-index --add --cacheinfo "100644,$bl,.claude/sessions/s1/order.yaml"
    fi
    local t; t="$(GIT_INDEX_FILE="$idx" git -C "$wc" write-tree)"
    printf 'rebuilt\n' | git -C "$wc" commit-tree "$t" -p "$2"
  }
  c1="$(rebuild refs/heads/sdx/s1~2 "$b")"; c2="$(rebuild refs/heads/sdx/s1~1 "$c1")"
  c3="$(printf 'close\n' | git -C "$wc" commit-tree "refs/heads/sdx/s1^{tree}" -p "$c2")"
  git -C "$wc" reset -q --hard "$c3"; rm -f "$idx"
}
# fx_commit <wc> <path> <content> [msg]: a commit on the checked-out branch
fx_commit() {
  mkdir -p "$(dirname "$1/$2")"; printf '%s\n' "$3" > "$1/$2"
  git -C "$1" add -A -- . >/dev/null 2>&1; git -C "$1" commit -q -m "${4:-fx}"
}
dev_advance() {   # <wc> <file> <line>: dev moves on after sdx/s1 was cut
  git -C "$1" checkout -q dev && printf '%s\n' "$3" >> "$1/$2" && git -C "$1" commit -q -am "dev moves" && git -C "$1" checkout -q sdx/s1
}
oracle_of() {   # <wc> <branch> -> ORACLE (approve | ...) or "SKIP"
  ORACLE="$(pkg_oracle "$1" "$2" 2>/dev/null)"; local rc=$?
  if [ "$rc" = 77 ]; then ORACLE=SKIP; fi
}
ORACLE_INFO=0
oracle_expect() {   # <label> <wc> <branch> <expected>
  oracle_of "$2" "$3"
  if [ "$ORACLE" = SKIP ]; then
    if [ "$ORACLE_INFO" = 0 ]; then info "oracle skipped: python3 with PyYAML is absent (oracle comparisons are NOT passed, only skipped)"; ORACLE_INFO=1; fi
  else eq "$1" "$ORACLE" "$4"; fi
}

# ---------------------------------------------------------------------------------------------------- [B7]
if want B7; then
echo "[B7] refusals"
refuse() {   # <label> <expected rc> <expected stderr fragment> [args]
  local label="$1" erc="$2" frag="$3"; shift 3
  run_build "$WC" "$@"
  eq "B7 $label: rc" "$BRC" "$erc"
  has "B7 $label: stderr names the reason" "$BERR" "$frag"
  eq "B7 $label: no change/* branch created" "$(gw for-each-ref --format='%(refname)' 'refs/heads/change/*')" ""
}
newfx && {
  mand_edit 's/^  executor: .*/  executor: client-harness:kitgroup/'
  refuse "executor with ':'" 1 "executor: недопустимые символы ':'"
}
newfx && {
  fx_set_order "$WC" none
  bad65="$(printf 'a%.0s' $(seq 1 65))"
  for c in "a..b" "-lead" "has space" "$bad65"; do
    refuse "commitment '${c:0:12}'" 1 "commitment:" --commitment "$c" --title T --base-name dev
  done
}
newfx && refuse "secret in the title" 1 "title: похоже на секрет" --title 'password: hunter2'
newfx && {
  fx_commit "$WC" "src/mod1/$(printf 'x\ty')" "ctl"
  refuse "control character in a path" 1 "files:"
}
newfx && {
  fx_commit "$WC" CHANGE.yaml "stray"
  refuse "CHANGE.yaml in the code" 1 "CHANGE.yaml"
}
newfx && {
  t="$(printf 'revert\n' | gw commit-tree "refs/heads/dev^{tree}" -p refs/heads/sdx/s1)"; gw reset -q --hard "$t"
  refuse "empty diff" 1 "пуст"
}
newfx && {
  fx_commit "$WC" .claude/sessions/s1/session_state.json '{"stage":"Closeout"}'
  refuse "session directory in the tree" 1 "каталог сессии"
}
newfx && { rm -f "$WC/.mesh/mandate.yaml" "$WC/.mesh/endpoint.yaml"; refuse "no mandate" 1 "мандат"; }
newfx && { rm -f "$WC/.mesh/endpoint.yaml"; refuse "mandate without endpoint.yaml" 1 "endpoint.yaml"; }
newfx && { gw checkout -q dev; refuse "wrong branch" 1 "текущая ветка"; }
newfx && {
  gw config --local --unset user.name; gw config --local --unset user.email; gw config --local user.useConfigOnly true
  refuse "no user.name/user.email" 2 "user."
}
newfx && { BOUT="$(bash "$SUT" --proj "$WC" 2>&1)"; BRC=$?; eq "B7 no --sid: rc 2 (usage)" "$BRC" "2"; }
newfx && { BOUT="$(bash "$SUT" --sid s1 --proj "$WC" --bogus 2>&1)"; BRC=$?; eq "B7 unknown flag: rc 2 (usage)" "$BRC" "2"; }
fi

# ---------------------------------------------------------------------------------------------------- [B9]
if want B9; then
echo "[B9] diverged base"
newfx && {
  dev_advance "$WC" src/core/b.js "b=2"
  run_build "$WC"
  eq "B9 dev moved on: rc 3" "$BRC" "3"
  has "B9 NEED allow-diverged on stderr" "$BERR" "NEED allow-diverged"
  eq "B9 nothing created without the flag" "$(gw for-each-ref --format='%(refname)' 'refs/heads/change/*')" ""
  run_build "$WC" --allow-diverged
  eq "B9 with --allow-diverged: rc 0" "$BRC" "0"
  head="$(jv .head)"
  eq "B9 head's parent is the CURRENT dev" "$(gw rev-parse "$head^" 2>/dev/null)" "$(gw rev-parse refs/heads/dev)"
  eq "B9 base..head is only the session's change (no foreign file)" "$(gw diff --name-only "$(gw rev-parse refs/heads/dev)" "$head" 2>/dev/null | tr '\n' ' ')" "docs/DECISIONS.md docs/specs/mod1.md package-lock.json src/mod1/a.js "
  has "B9 head's tree carries dev's own advance" "$(gw show "$head:src/core/b.js" 2>/dev/null)" "b=2"
}
newfx && {
  dev_advance "$WC" src/mod1/a.js "a=conflict"
  run_build "$WC" --allow-diverged
  eq "B9 merge conflict: rc 1" "$BRC" "1"
  has "B9 conflict message tells to merge dev into the session branch" "$BERR" "слейте"
  eq "B9 nothing created on a conflict" "$(gw for-each-ref --format='%(refname)' 'refs/heads/change/*')" ""
}
fi

# ---------------------------------------------------------------------------------------------------- [B8a]
if want B8a; then
echo "[B8a] re-submission before the manifest"
BR=change/C-ACME-001-ex1
newfx && {
  pkg_craft_good "$WC" "$BR" >/dev/null 2>&1; old="$PKG_TIP"
  run_build "$WC"
  eq "B8a existing change/*: rc 3" "$BRC" "3"
  has "B8a NEED resubmit on stderr" "$BERR" "NEED resubmit"
  eq "B8a the old tip is untouched" "$(gw rev-parse "refs/heads/$BR")" "$old"
  run_build "$WC" --resubmit
  eq "B8a with --resubmit: rc 0" "$BRC" "0"
  eq "B8a the new head's parent is the previous tip" "$(gw rev-parse "$(jv .head)^" 2>/dev/null)" "$old"
}
newfx && {
  gw branch "$BR" dev
  run_build "$WC"; eq "B8a non-package change/* without the flag: rc 1" "$BRC" "1"
  has "B8a message: not an SDX package" "$BERR" "не пакет SDX"
  run_build "$WC" --resubmit; eq "B8a non-package change/* with the flag: rc 1" "$BRC" "1"
  eq "B8a the foreign branch is untouched" "$(gw rev-parse "refs/heads/$BR")" "$(gw rev-parse refs/heads/dev)"
}
fi

# @@TAIL@@
echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
