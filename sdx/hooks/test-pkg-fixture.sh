#!/usr/bin/env bash
# Self-test of the shared test helper sdx/hooks/lib/pkg-fixture.sh and of its python oracle (FEAT-017).
#
# lib/pkg-fixture.sh gives the FEAT-017 suites (test-pr-build/-pr-check/-pr-publish) one fixture repository for a
# change package, "fake package" factories built by plumbing INDEPENDENT of pr-build.sh, and `pkg_oracle`: a
# transliteration of the formal checks of audit() of the meta-orchestrator node (sim-kit core/dev.py:340-424 — read as
# data, never imported or run). A helper that has no red side of its own proves nothing, hence this suite:
#   [F1] the template: bare remote, clone, session history "session -> code -> git rm -r session", mandate files,
#        a controllable test command, a clean tree, local identity            (green + structure)
#   [F2] pkg_fixture_copy is fast and independent (a change in the copy is invisible to the template and its remote)
#   [F3] the oracle: pkg_craft_good -> approve; every pkg_craft_bad_<kind> -> the expected verdict and check ids
#   [F4] built-in negatives: a substituted oracle verdict turns the comparison red
#   [F5] no python3/PyYAML -> rc 77 (the suites print INFO and skip, never PASS)
#   [F6] portability of lib/pkg-fixture.sh (BUG-010) + red side; no __pycache__ left in the checkout
# python3 + PyYAML appear ONLY as the oracle (INFO-skip when absent).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="${PKG_FIXTURE_LIB_UNDER_TEST:-$SCRIPT_DIR/lib}"
export PYTHONDONTWRITEBYTECODE=1

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
info() { echo "  INFO: $1"; }

echo "=== test-pkg-fixture.sh ==="
echo ""

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FX_OK=0
if [ -f "$LIB/pkg-fixture.sh" ]; then
  # shellcheck disable=SC1091
  . "$LIB/pkg-fixture.sh" && FX_OK=1
fi
have() { [ "$FX_OK" = 1 ] && declare -F "$1" >/dev/null 2>&1; }
# shellcheck disable=SC1091
. "$LIB/miniyaml.sh"; . "$LIB/mandate.sh"

eq() {  # <label> <got> <expected>
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "got [$2] expected [$3]"; fi
}

# ---------------------------------------------------------------------------------------------------- [F1]
echo "[F1] the template repository"
if have pkg_fixture_template; then
  t0="$(date +%s)"
  pkg_fixture_template "$TMP"; rc=$?
  t1="$(date +%s)"
  eq "template: pkg_fixture_template rc" "$rc" "0"
  if [ $((t1 - t0)) -le 1 ]; then pass "template built in $((t1 - t0))-$((t1 - t0 + 1)) s (<= 1 s budget at 1 s clock resolution)"; else fail "template build time" "$((t1 - t0)) s"; fi
else
  fail "template: pkg_fixture_template" "lib/pkg-fixture.sh or the function is missing"
fi
TPL="${PKG_FIXTURE_TEMPLATE:-/nonexistent}"
WC="$TPL/wc"
eq "template: remote.git is bare" "$(git -C "$TPL/remote.git" rev-parse --is-bare-repository 2>/dev/null)" "true"
eq "template: remote has dev" "$(git -C "$TPL/remote.git" for-each-ref --format='%(refname)' 2>/dev/null)" "refs/heads/dev"
eq "template: branches of the clone" "$(git -C "$WC" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null | tr '\n' ' ')" "dev sdx/s1 "
eq "template: HEAD is sdx/s1" "$(git -C "$WC" symbolic-ref HEAD 2>/dev/null)" "refs/heads/sdx/s1"
eq "template: remote-tracking origin/dev exists" "$(git -C "$WC" rev-parse --verify -q refs/remotes/origin/dev >/dev/null 2>&1 && echo yes)" "yes"
eq "template: working tree clean" "$(st="$(git -C "$WC" status --porcelain 2>&1)" && [ -z "$st" ] && echo clean || echo "dirty-or-missing")" "clean"
eq "template: session history subjects" "$(git -C "$WC" log --format=%s refs/heads/sdx/s1 2>/dev/null | tr '\n' '|')" "s1 close|s1 code|s1 session|base|"
eq "template: session directory absent at the tip" "$(git -C "$WC" cat-file -e 'refs/heads/sdx/s1:README.md' 2>/dev/null && { git -C "$WC" cat-file -e 'refs/heads/sdx/s1:.claude/sessions/s1' 2>/dev/null && echo present || echo absent; })" "absent"
for f in session_state.json order.yaml decisions_log.md verification_report.md change_note.md; do
  eq "template: $f present one commit before the tip" "$(git -C "$WC" cat-file -e "refs/heads/sdx/s1~1:.claude/sessions/s1/$f" 2>/dev/null && echo yes || echo no)" "yes"
done
eq "template: verification_report says PASS" "$(git -C "$WC" show 'refs/heads/sdx/s1~1:.claude/sessions/s1/verification_report.md' 2>/dev/null | grep -c 'Итог: PASS')" "1"
eq "template: the change touches code, lock file, registry and spec" "$(git -C "$WC" diff --name-only dev refs/heads/sdx/s1 2>/dev/null | tr '\n' ' ')" "docs/DECISIONS.md docs/specs/mod1.md package-lock.json src/core/b.js src/mod1/a.js "
eq "template: the registry gained ADR-099" "$(git -C "$WC" diff -U0 dev refs/heads/sdx/s1 -- docs/DECISIONS.md 2>/dev/null | grep -c '^+## ADR-099')" "1"
eq "template: local identity is configured" "$(git -C "$WC" config --local user.name 2>/dev/null)/$(git -C "$WC" config --local user.email 2>/dev/null)" "fixture/fixture@example.invalid"
eq "template: mandate mode is on" "$(mandate_mode "$WC")" "on"
if mandate_load "$WC"; then
  _my_scalar mandate.executor; eq "template: mandate executor" "$MY_S" "ex1"
  _my_scalar mandate.digest; eq "template: mandate digest" "$MY_S" "123456789012"
  _my_scalar mandate.delivery; eq "template: mandate delivery" "$MY_S" "pr"
  _my_scalar mandate.docs_in_repo; eq "template: mandate docs_in_repo" "$MY_S" "final"
  eq "template: mandate branches" "$MANDATE_BRANCHES" "change/*"
  eq "template: mandate paths" "$MANDATE_PATHS" "src/mod1/**"
  eq "template: mandate shared_paths" "$MANDATE_SHARED" "package-lock.json"
  eq "template: mandate docs_paths" "$MANDATE_DOCS" "docs/**"
else fail "template: mandate_load" "$MANDATE_ERR"; fi
eq "template: the test command is controllable (exit 0 by default, PKG_VERIFY_EXIT=1 -> 1)" "$(a="$(cd "$WC" 2>/dev/null && bash .claude/sdx/verify-cmd.sh >/dev/null 2>&1; echo $?)"; b="$(cd "$WC" 2>/dev/null && PKG_VERIFY_EXIT=1 bash .claude/sdx/verify-cmd.sh >/dev/null 2>&1; echo $?)"; echo "$a/$b")" "0/1"
if my_load <(git -C "$WC" show 'refs/heads/sdx/s1~1:.claude/sessions/s1/order.yaml' 2>/dev/null) 2>/dev/null; then
  _my_scalar order.commitment.id; eq "template: the order snapshot is readable by miniyaml (commitment)" "$MY_S" "C-ACME-001"
else
  git -C "$WC" show 'refs/heads/sdx/s1~1:.claude/sessions/s1/order.yaml' > "$TMP/order.yaml" 2>/dev/null; my_load "$TMP/order.yaml"
  _my_scalar order.commitment.id; eq "template: the order snapshot is readable by miniyaml (commitment)" "$MY_S" "C-ACME-001"
fi
_my_scalar order.repo.url; eq "template: the order's repo.url is the template's remote" "$MY_S" "$TPL/remote.git"
eq "template: pkg_fixture_template is idempotent (reuses the template)" "$(have pkg_fixture_template && { pkg_fixture_template "$TMP/other" >/dev/null 2>&1; echo "$PKG_FIXTURE_TEMPLATE"; })" "$TPL"

# ---------------------------------------------------------------------------------------------------- [F2]
echo "[F2] pkg_fixture_copy: fast and independent"
if have pkg_fixture_copy; then
  t0="$(date +%s)"; pkg_fixture_copy "$TMP/c1"; rc=$?; t1="$(date +%s)"
  eq "copy: rc" "$rc" "0"
  [ $((t1 - t0)) -le 1 ] && pass "copy made in <= 1 s" || fail "copy time" "$((t1 - t0)) s"
  eq "copy: PKG_WC" "${PKG_WC:-}" "$TMP/c1/wc"
  eq "copy: PKG_REMOTE" "${PKG_REMOTE:-}" "$TMP/c1/remote.git"
  git -C "$TMP/c1/wc" branch -q probe 2>/dev/null
  eq "copy: a branch made in the copy is invisible to the template" "$(git -C "$WC" rev-parse --verify -q refs/heads/probe >/dev/null 2>&1 && echo seen || echo hidden)" "hidden"
  eq "copy: origin points to the copy's own remote" "$(git -C "$TMP/c1/wc" remote get-url origin 2>/dev/null)" "$TMP/c1/remote.git"
  git -C "$TMP/c1/wc" push -q "$TPL/remote.git" refs/heads/dev:refs/heads/probe >/dev/null 2>&1
  eq "copy: a push to the template's URL lands in the copy's remote (insteadOf)" "$(git -C "$TMP/c1/remote.git" rev-parse --verify -q refs/heads/probe >/dev/null 2>&1 && echo copy || echo none)" "copy"
  eq "copy: the template's remote is untouched" "$(git -C "$TPL/remote.git" for-each-ref --format='%(refname)' 2>/dev/null)" "refs/heads/dev"
  pkg_fixture_copy "$TMP/c2" >/dev/null 2>&1
  eq "copy: a second copy has no trace of the first" "$(git -C "$TMP/c2/wc" rev-parse --verify -q refs/heads/probe >/dev/null 2>&1 && echo seen || echo clean)" "clean"
  eq "copy: working tree clean" "$(git -C "$TMP/c2/wc" status --porcelain 2>/dev/null)" ""
else
  for t in rc time PKG_WC PKG_REMOTE branch origin insteadOf remote second clean; do fail "copy: $t" "pkg_fixture_copy missing"; done
fi

# ---------------------------------------------------------------------------------------------------- [F3]
echo "[F3] the oracle (python transliteration of audit(), formal checks only)"
KINDS="extra_commit foreign_file bad_archive out_of_scope shared_undeclared session_dir format2 manifest_in_head fake_scope secret_notes wrong_commitment wrong_executor wrong_digest bad_branch no_adr"
expected_of() {
  case "$1" in
    good) echo "approve" ;;
    extra_commit|foreign_file) echo "reject manifest.commit" ;;
    bad_archive) echo "reject archive_sha256" ;;
    out_of_scope|session_dir) echo "reject scope" ;;
    shared_undeclared) echo "return shared.declared" ;;
    format2) echo "reject format" ;;
    manifest_in_head) echo "return archive_sha256" ;;
    fake_scope) echo "approve" ;;           # audit() recomputes scope_touched itself: the oracle is blind to it by design
    secret_notes) echo "reject secrets" ;;
    wrong_commitment) echo "reject commitment" ;;
    wrong_executor) echo "reject mandate" ;;
    wrong_digest) echo "return mandate.digest" ;;
    bad_branch) echo "reject branch" ;;
    no_adr) echo "return adr" ;;
  esac
}
# craft_and_audit <oracle-fn> <wc> <kind> -> the oracle's answer on stdout
craft_and_audit() {
  local fn="$1" w="$2" k="$3" b="change/t-$3"
  if [ "$k" = good ]; then pkg_craft_good "$w" "$b" >/dev/null 2>&1; else "pkg_craft_bad_$k" "$w" "$b" >/dev/null 2>&1; fi
  [ "$k" = bad_branch ] && b="${PKG_BRANCH_MADE:-$b}"
  "$fn" "$w" "$b" 2>/dev/null
}
# oracle_table <oracle-fn> -> number of mismatches vs expected_of (echoes details to stderr-free stdout lines "MISMATCH ...")
oracle_table() {
  local fn="$1" w="$2" k got exp bad=0
  for k in good $KINDS; do
    got="$(craft_and_audit "$fn" "$w" "$k")"; exp="$(expected_of "$k")"
    if [ "$got" != "$exp" ]; then echo "MISMATCH $k got [$got] expected [$exp]"; bad=$((bad + 1)); fi
  done
  echo "BAD $bad"
}
ORACLE_RC=0
if have pkg_oracle; then
  pkg_fixture_copy "$TMP/o1" >/dev/null 2>&1
  pkg_oracle "${PKG_WC:-$TMP/o1/wc}" no-such-branch >/dev/null 2>&1; ORACLE_RC=$?
else ORACLE_RC=1; fi
if [ "$ORACLE_RC" = 77 ]; then
  info "oracle skipped: python3 with PyYAML is absent (F3 comparisons are NOT passed, only skipped)"
elif have pkg_craft_good && have pkg_oracle; then
  res="$(oracle_table pkg_oracle "$TMP/o1/wc")"
  for k in good $KINDS; do
    if printf '%s\n' "$res" | grep -q "^MISMATCH $k "; then fail "oracle: $k" "$(printf '%s\n' "$res" | grep "^MISMATCH $k ")"
    else pass "oracle: $k -> $(expected_of "$k")"; fi
  done
else
  for k in good $KINDS; do fail "oracle: $k" "pkg_craft_good/pkg_craft_bad_*/pkg_oracle missing"; done
fi
# the oracle reads the package, not the branch name: a missing ref is an error, not "approve"
if have pkg_oracle && [ "$ORACLE_RC" != 77 ]; then
  out="$(pkg_oracle "$TMP/o1/wc" no-such-branch 2>/dev/null)"; rc=$?
  if [ "$out" != "approve" ] && [ "$rc" -ne 77 ]; then pass "oracle: a missing branch is not approved ($out)"; else fail "oracle: missing branch" "got [$out] rc=$rc"; fi
fi

# ---------------------------------------------------------------------------------------------------- [F4]
echo "[F4] built-in negatives: a substituted verdict turns the comparison red"
if [ "$ORACLE_RC" != 77 ] && have pkg_craft_good && have pkg_oracle; then
  always_approve() { echo approve; }
  res="$(oracle_table always_approve "$TMP/o1/wc")"
  bad="$(printf '%s\n' "$res" | sed -n 's/^BAD //p')"
  if [ -n "$bad" ] && [ "$bad" -ge 10 ]; then pass "an oracle that always says approve mismatches on $bad of 16 packages"; else fail "negative: always-approve oracle" "BAD=[$bad]"; fi
  never_approve() { echo "reject x"; }
  res="$(oracle_table never_approve "$TMP/o1/wc")"
  printf '%s\n' "$res" | grep -q '^MISMATCH good ' && pass "an oracle that never approves mismatches on the good package" || fail "negative: never-approve oracle" "no mismatch on good"
else
  info "F4 skipped: oracle unavailable"
fi

# ---------------------------------------------------------------------------------------------------- [F5]
echo "[F5] no python3/PyYAML -> rc 77 (INFO-skip in the suites)"
if have pkg_oracle; then
  PKG_PYTHON=/nonexistent/python3 pkg_oracle "$TMP/o1/wc" x >/dev/null 2>&1; rc=$?
  eq "oracle: missing interpreter -> rc 77" "$rc" "77"
else fail "oracle: missing interpreter" "pkg_oracle missing"; fi

# ---------------------------------------------------------------------------------------------------- [F6]
echo "[F6] portability of lib/pkg-fixture.sh (BUG-010); no bytecode left behind"
FORBID='tim''eout|map''file|declare -''A|[$]\{[a-zA-Z_]+,,\}|%''N|readlink -''f|real''path'
if [ -f "$LIB/pkg-fixture.sh" ]; then
  if grep -nE "$FORBID" "$LIB/pkg-fixture.sh" >/dev/null 2>&1; then fail "lib/pkg-fixture.sh portability" "forbidden: $(grep -nE "$FORBID" "$LIB/pkg-fixture.sh" | head -3)"
  else pass "lib/pkg-fixture.sh: no GNU-only/bash4-only constructs"; fi
  cp "$LIB/pkg-fixture.sh" "$TMP/port-mut.sh"; printf 'ma''pfile -t xs <<<""\n' >> "$TMP/port-mut.sh"
  if ! cmp -s "$LIB/pkg-fixture.sh" "$TMP/port-mut.sh" && grep -qE "$FORBID" "$TMP/port-mut.sh"; then pass "red side: the same grep flags a mutant with a bash4 construct"
  else fail "red side of the portability grep" "mutant not flagged"; fi
  if bash -n "$LIB/pkg-fixture.sh" 2>/dev/null; then pass "lib/pkg-fixture.sh: bash -n"; else fail "lib/pkg-fixture.sh: bash -n" "syntax error"; fi
else
  fail "lib/pkg-fixture.sh portability" "file missing"; fail "red side of the portability grep" "file missing"; fail "lib/pkg-fixture.sh: bash -n" "file missing"
fi
leftover="$(find "$ROOT" -name __pycache__ -not -path '*/.git/*' 2>/dev/null | head -3)"
if [ -z "$leftover" ]; then pass "no __pycache__ in the checkout"; else fail "no __pycache__ in the checkout" "found: $leftover"; fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
