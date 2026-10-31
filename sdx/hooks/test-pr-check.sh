#!/usr/bin/env bash
# Tests for sdx/hooks/pr-check.sh (FEAT-017, REQ-PKG-8, 11, 12, 26, 27).
# pr-check.sh is the deterministic check before publication (the analogue of closeout-check of the bridge). It MIRRORS the
# formal checks of audit() of the node (sim-kit core/dev.py:340-424); the live audit() is never called by the plugin.
# Phase `pre` (before the build) predicts the diff; phase `post` reads the built branch refs/heads/change/<C>-<exec>.
# Output: "OK|FAIL|WARN|NOTE <id>: <text>" lines and a last line "PR-CHECK PASS" | "PR-CHECK WARN <n>" | "PR-CHECK FAIL <n>";
# rc 0 PASS | 3 WARN only | 1 FAIL | 2 usage/environment.
# Fixture: lib/pkg-fixture.sh (one template per run, cp -Rp per block, hermetic git). Packages for `post` are built by
# pr-build.sh (green side) and by pkg_craft_bad_<kind> (red side, plumbing independent of pr-build). python3/PyYAML appear
# ONLY as the independent oracle `pkg_oracle` (a transliteration of audit()) — INFO-skip, never PASS.
#
#  [C1] `pre` green: rc 0, PR-CHECK PASS, test stub exit 0
#  [C2] `pre` blocks (rc 1, each its own FAIL id)
#  [C3] `pre` asks for confirmation (rc 3, WARN ids); docs_in_repo: none -> the registry is not checked
#  [C4] `post` green on a package from pr-build.sh + the oracle says approve
#  [C5] `post` red sides on pkg_craft_bad_<kind> packages
#  [C6] parity with the oracle: oracle != approve <=> pr-check post != PASS (where the oracle covers the check); a table
#       "package -> expected ids"; built-in negative: a substituted oracle verdict turns the comparison red
#  [C7] `all` = pre then post (only when pre has no FAIL); --no-tests; hostile mandate values cleaned in the output
#  [Port] portability of pr-check.sh (BUG-010) + red side
#  [Mut] mutation runs (copies of pr-check.sh + lib/ + mandate-info.sh in a temp dir, anchors "# PKG-C-*")
# Env: PR_CHECK_ONLY="C2 C3" selects blocks; PR_CHECK_UNDER_TEST=<script> (mutants); PR_CHECK_NESTED=1 (no mutation section);
# PR_CHECK_CASES="tree session" (mutation runs: only these cases of the block).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUT="${PR_CHECK_UNDER_TEST:-$SCRIPT_DIR/pr-check.sh}"
export PYTHONDONTWRITEBYTECODE=1
unset EMAIL GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL SDX_MANDATE_TODAY PKG_VERIFY_EXIT

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
info() { echo "  INFO: $1"; }
want() { [ -z "${PR_CHECK_ONLY:-}" ] && return 0; case " $PR_CHECK_ONLY " in *" $1 "*) return 0 ;; esac; return 1; }
# case_on <name>: in a mutation run only the named cases of a block are executed
case_on() { [ -z "${PR_CHECK_CASES:-}" ] && return 0; case " $PR_CHECK_CASES " in *" $1 "*) return 0 ;; esac; return 1; }
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "got [$2] expected [$3]"; fi; }
has() { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "[$3] not in [$2]" ;; esac; }
hasnt() { case "$2" in *"$3"*) fail "$1" "[$3] found in [$2]" ;; *) pass "$1" ;; esac; }

echo "=== test-pr-check.sh ==="
echo ""

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/pkg-fixture.sh"
. "$SCRIPT_DIR/lib/miniyaml.sh"
if ! pkg_fixture_template "$TMP"; then echo "FATAL: cannot build the fixture template" >&2; exit 2; fi
BR=change/C-ACME-001-ex1

NFX=0
newfx() {   # -> WC: a fresh copy of the template (sdx/s1 checked out)
  NFX=$((NFX + 1))
  pkg_fixture_copy "$TMP/fx$NFX" || { fail "fixture copy" "pkg_fixture_copy failed"; return 1; }
  WC="$PKG_WC"
}
run_check() {   # <wc> [args] -> COUT CERR CRC (stdout, stderr, rc)
  local wc="$1"; shift
  COUT="$(bash "${SUTX:-$SUT}" --sid s1 --proj "$wc" "$@" 2>"$TMP/stderr")"; CRC=$?
  CERR="$(cat "$TMP/stderr")"
}
gw() { git -C "$WC" "$@"; }
mand_edit() { sed "$1" "$WC/.mesh/mandate.yaml" > "$WC/.mesh/mandate.new" && mv "$WC/.mesh/mandate.new" "$WC/.mesh/mandate.yaml"; }
last_line() { printf '%s\n' "$COUT" | tail -n1; }
# line_of <STATUS> <id>: the output line "STATUS id: ..." if present
line_of() { printf '%s\n' "$COUT" | grep -m1 "^$1 $2:"; }
expect_line() {   # <label> <STATUS> <id>
  if [ -n "$(line_of "$2" "$3")" ]; then pass "$1: $2 $3"; else fail "$1: $2 $3" "no such line in [$(printf '%s' "$COUT" | tr '\n' '|' | cut -c1-400)]"; fi
}
fx_set_sfile() {   # <wc> <session file name> <file|none>: rebuild the history of sdx/s1 with another version of one session file
  local wc="$1" name="$2" src="$3" idx="$TMP/idx.$$" b c1 c2 c3
  b="$(git -C "$wc" rev-parse refs/heads/dev)"
  rebuild() {
    rm -f "$idx"
    GIT_INDEX_FILE="$idx" git -C "$wc" read-tree "$1"
    if [ "$src" = none ]; then GIT_INDEX_FILE="$idx" git -C "$wc" update-index --force-remove ".claude/sessions/s1/$name"
    else
      local bl; bl="$(git -C "$wc" hash-object -w "$src")"
      GIT_INDEX_FILE="$idx" git -C "$wc" update-index --add --cacheinfo "100644,$bl,.claude/sessions/s1/$name"
    fi
    local t; t="$(GIT_INDEX_FILE="$idx" git -C "$wc" write-tree)"
    printf 'rebuilt\n' | git -C "$wc" commit-tree "$t" -p "$2"
  }
  c1="$(rebuild refs/heads/sdx/s1~2 "$b")"; c2="$(rebuild refs/heads/sdx/s1~1 "$c1")"
  c3="$(printf 'close\n' | git -C "$wc" commit-tree "refs/heads/sdx/s1^{tree}" -p "$c2")"
  git -C "$wc" reset -q --hard "$c3"; rm -f "$idx"
}
fx_commit() {   # <wc> <path> <content> [msg]
  mkdir -p "$(dirname "$1/$2")"; printf '%s\n' "$3" > "$1/$2"
  git -C "$1" add -A -- . >/dev/null 2>&1; git -C "$1" commit -q -m "${4:-fx}"
}
dev_advance() {   # <wc> <file> <line>
  git -C "$1" checkout -q dev && printf '%s\n' "$3" >> "$1/$2" && git -C "$1" commit -q -am "dev moves" && git -C "$1" checkout -q sdx/s1
}

# ---------------------------------------------------------------------------------------------------- [C1]
if want C1; then
echo "[C1] pre: green"
newfx && {
  run_check "$WC" --phase pre
  eq "C1 rc 0" "$CRC" "0"
  eq "C1 last line" "$(last_line)" "PR-CHECK PASS"
  for id in closeout.branch closeout.tree closeout.session id.commitment id.executor branch.name branch.scope mandate.valid mandate.digest base.ref base.ancestor branch.exists diff.nonempty diff.scope diff.session docs.final adr.registry url.scheme url.origin-drift tests; do
    expect_line "C1" OK "$id"
  done
  expect_line "C1 touches_shared is a note, not a block" NOTE shared.note
  eq "C1 every line has a known status prefix" "$(printf '%s\n' "$COUT" | grep -cvE '^(OK|FAIL|WARN|NOTE) [a-z.-]+: |^PR-CHECK ')" "0"
  eq "C1 the check wrote nothing (status clean, no new refs)" "$(gw status --porcelain)$(gw for-each-ref --format='%(refname)' 'refs/heads/change/*')" ""
}
fi

# ---------------------------------------------------------------------------------------------------- [C2]
if want C2; then
echo "[C2] pre: blocks"
blocks() {   # <case> <label> <FAIL id> : after the scenario was prepared in $WC
  local cs="$1" label="$2" id="$3"; shift 3
  run_check "$WC" --phase pre "$@"
  eq "C2 $label: rc 1" "$CRC" "1"
  expect_line "C2 $label" FAIL "$id"
  eq "C2 $label: last line says FAIL" "$(last_line | cut -d' ' -f1-2)" "PR-CHECK FAIL"
}
case_on tree && newfx && { echo dirt >> "$WC/README.md"; blocks tree "dirty working tree" closeout.tree; }
case_on session && newfx && {
  gw checkout -q refs/heads/sdx/s1~1 -- .claude/sessions/s1 && gw commit -q -m "session dir back"
  blocks session "session directory still in HEAD" closeout.session
}
case_on branch && newfx && { gw checkout -q dev; blocks branch "wrong current branch" closeout.branch; }
case_on executor && newfx && { mand_edit 's/^  executor: .*/  executor: client-harness:kitgroup/'; blocks executor "invalid executor" id.executor; }
case_on scopebr && newfx && { mand_edit 's|^    - change/\*|    - feat/*|'; blocks scopebr "branch name outside scope.branches" branch.scope; }
case_on expired && newfx && { SDX_MANDATE_TODAY=2100-01-01 blocks expired "expired mandate" mandate.valid; }
case_on scope && newfx && { fx_commit "$WC" src/core/b.js "b=outside"; blocks scope "file outside the scope" diff.scope; }
case_on docsfinal && newfx && {
  mand_edit 's|^    - docs/\*\*|    - docs/specs/**|'
  blocks docsfinal "document outside docs_paths under final" docs.final
}
case_on empty && newfx && {
  t="$(printf 'revert\n' | gw commit-tree "refs/heads/dev^{tree}" -p refs/heads/sdx/s1)"; gw reset -q --hard "$t"
  blocks empty "empty diff" diff.nonempty
}
case_on tests && newfx && {
  gw update-index --assume-unchanged .claude/sdx/verify-cmd.sh
  printf '#!/usr/bin/env bash\necho "boom: assertion failed in suite X"\nexit 1\n' > "$WC/.claude/sdx/verify-cmd.sh"
  blocks tests "red test stub" tests
  has "C2 tests: the tail of the red output is on stderr" "$CERR" "boom: assertion failed in suite X"
}
case_on url && newfx && {
  git -C "$WC" show refs/heads/sdx/s1~1:.claude/sessions/s1/order.yaml | sed 's|^    url: .*|    url: "ext::sh -c touch% MARK"|' > "$TMP/order-ext.yaml"
  fx_set_sfile "$WC" order.yaml "$TMP/order-ext.yaml"
  blocks url "repo.url with a remote helper" url.scheme
  eq "C2 url: nothing was executed (no MARK file)" "$(ls "$WC/MARK" "$PWD/MARK" 2>/dev/null | wc -l | tr -d ' ')" "0"
}
case_on digest && newfx && { mand_edit "/^  digest: /d"; blocks digest "no digest in the mandate" mandate.digest; }
fi

# ---------------------------------------------------------------------------------------------------- [C3]
if want C3; then
echo "[C3] pre: confirmation needed"
warns() {   # <label> <WARN id>...
  local label="$1"; shift
  run_check "$WC" --phase pre
  eq "C3 $label: rc 3" "$CRC" "3"
  for id in "$@"; do expect_line "C3 $label" WARN "$id"; done
  eq "C3 $label: no FAIL line" "$(printf '%s\n' "$COUT" | grep -c '^FAIL ')" "0"
  eq "C3 $label: last line says WARN" "$(last_line | cut -d' ' -f1-2)" "PR-CHECK WARN"
}
case_on ancestor && newfx && { dev_advance "$WC" src/core/b.js "b=2"; warns "diverged base" base.ancestor tests; }
case_on exists && newfx && { pkg_craft_good "$WC" "$BR" >/dev/null 2>&1; warns "branch exists" branch.exists; }
case_on adr && newfx && { gw checkout -q dev -- docs/DECISIONS.md && gw commit -q -m "registry untouched"; warns "registry not changed" adr.registry; }
case_on regpath && newfx && {
  mand_edit 's|^    - docs/\*\*|    - docs/specs/**|'
  run_check "$WC" --phase pre
  expect_line "C3 registry outside docs_paths" WARN adr.registry
  expect_line "C3 ... and (same fact, K-12) the document outside docs_paths blocks" FAIL docs.final
}
case_on drift && newfx && { gw update-ref refs/remotes/origin/dev "$(gw rev-parse refs/heads/sdx/s1)"; warns "remote-tracking drift" base.remote-drift; }
case_on attrs && newfx && { printf '*.md export-ignore\n' > "$WC/.git/info/attributes"; warns "export-ignore" attrs.export; }
case_on lint && newfx && { mand_edit 's/^  docs_in_repo: .*/  docs_in_repo: none/'; warns "history: executor + docs_in_repo: none" mandate.lint; }
case_on none && newfx && {
  gw checkout -q dev -- docs/DECISIONS.md && gw commit -q -m "registry untouched"
  mand_edit 's/^  docs_in_repo: .*/  docs_in_repo: none/; s/^  history: .*/  history: repo/'
  run_check "$WC" --phase pre
  eq "C3 docs_in_repo none: rc 0 although the registry is untouched" "$CRC" "0"
  eq "C3 docs_in_repo none: no adr.registry WARN" "$(printf '%s\n' "$COUT" | grep -c '^WARN adr.registry')" "0"
}
fi

# @@TAIL@@
echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
