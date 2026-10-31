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
#  [Port] portability of pr-build.sh (BUG-010) + red side; no python/eval/checkout/worktree
#  [Mut] mutation runs (copies of pr-build.sh + lib/ in a temp dir, anchors "# PKG-*")
# Env: PR_BUILD_ONLY="B7 B9" selects blocks; PR_BUILD_UNDER_TEST=<script> (mutants); PR_BUILD_NESTED=1 (no mutation
# section); PR_BUILD_B7="chg empty" (mutation runs: only these B7 cases).
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
  BOUT="$(bash "${SUTX:-$SUT}" --sid s1 --proj "$wc" "$@" 2>"$TMP/stderr")"; BRC=$?
  BERR="$(cat "$TMP/stderr")"
}
jv() { printf '%s' "$BOUT" | jq -r "$1" 2>/dev/null; }
gw() { git -C "$WC" "$@"; }
mand_edit() {   # <sed expr>: edit the (untracked) mandate of the current copy
  sed "$1" "$WC/.mesh/mandate.yaml" > "$WC/.mesh/mandate.new" && mv "$WC/.mesh/mandate.new" "$WC/.mesh/mandate.yaml"
}
# fx_set_sfile <wc> <session file name> <file|none>: rebuild the history of sdx/s1 with another version of one session
# file (or without it) by plumbing; the code and the closing commit keep their trees
fx_set_sfile() {
  local wc="$1" name="$2" src="$3" idx="$TMP/idx.$$" b c1 c2 c3
  b="$(git -C "$wc" rev-parse refs/heads/dev)"
  rebuild() {   # <rev> <parent>: the tree of <rev> with the file replaced -> commit
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
fx_set_order() { fx_set_sfile "$1" order.yaml "$2"; }
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
blk_B7() {
echo "[B7] refusals"
b7on() { [ -z "${PR_BUILD_B7:-}" ] && return 0; case " $PR_BUILD_B7 " in *" $1 "*) return 0 ;; esac; return 1; }   # PR_BUILD_B7="chg empty": only these cases (mutation runs)
refuse() {   # <label> <expected rc> <expected stderr fragment> [args]
  local label="$1" erc="$2" frag="$3"; shift 3
  run_build "$WC" "$@"
  eq "B7 $label: rc" "$BRC" "$erc"
  has "B7 $label: stderr names the reason" "$BERR" "$frag"
  eq "B7 $label: no change/* branch created" "$(gw for-each-ref --format='%(refname)' 'refs/heads/change/*')" ""
}
b7on exec && newfx && {
  mand_edit 's/^  executor: .*/  executor: client-harness:kitgroup/'
  refuse "executor with ':'" 1 "executor: недопустимые символы ':'"
}
b7on commit && newfx && {
  fx_set_order "$WC" none
  bad65="$(printf 'a%.0s' $(seq 1 65))"
  for c in "a..b" "-lead" "has space" "$bad65"; do
    refuse "commitment '${c:0:12}'" 1 "commitment:" --commitment "$c" --title T --base-name dev
  done
}
b7on secret && newfx && refuse "secret in the title" 1 "title: похоже на секрет" --title 'password: hunter2'
b7on ctl && newfx && {
  fx_commit "$WC" "src/mod1/$(printf 'x\ty')" "ctl"
  refuse "control character in a path" 1 "files:"
}
b7on chg && newfx && {
  fx_commit "$WC" CHANGE.yaml "stray"
  refuse "CHANGE.yaml in the code" 1 "CHANGE.yaml"
}
b7on empty && newfx && {
  t="$(printf 'revert\n' | gw commit-tree "refs/heads/dev^{tree}" -p refs/heads/sdx/s1)"; gw reset -q --hard "$t"
  refuse "empty diff" 1 "пуст"
}
b7on sess && newfx && {
  gw checkout -q refs/heads/sdx/s1~1 -- .claude/sessions/s1 && gw commit -q -m "session dir back"
  refuse "session directory in the tree" 1 "каталог сессии"
}
b7on nomandate && newfx && { rm -f "$WC/.mesh/mandate.yaml" "$WC/.mesh/endpoint.yaml"; refuse "no mandate" 1 "мандат"; }
b7on noendpoint && newfx && { rm -f "$WC/.mesh/endpoint.yaml"; refuse "mandate without endpoint.yaml" 1 "endpoint.yaml"; }
b7on branch && newfx && { gw checkout -q dev; refuse "wrong branch" 1 "текущая ветка"; }
b7on ident && newfx && {
  gw config --local --unset user.name; gw config --local --unset user.email; gw config --local user.useConfigOnly true
  refuse "no user.name/user.email" 2 "user."
}
b7on usage1 && newfx && { BOUT="$(bash "$SUT" --proj "$WC" 2>&1)"; BRC=$?; eq "B7 no --sid: rc 2 (usage)" "$BRC" "2"; }
b7on usage2 && newfx && { BOUT="$(bash "$SUT" --sid s1 --proj "$WC" --bogus 2>&1)"; BRC=$?; eq "B7 unknown flag: rc 2 (usage)" "$BRC" "2"; }
}

# ---------------------------------------------------------------------------------------------------- [B9]
blk_B9() {
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
  eq "B9 base..head is only the session's change (no foreign file)" "$(gw diff --name-only "$(gw rev-parse refs/heads/dev)" "$head" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')" "docs/DECISIONS.md docs/specs/mod1.md package-lock.json src/mod1/a.js"
  has "B9 head's tree carries dev's own advance" "$(gw show "$head:src/core/b.js" 2>/dev/null)" "b=2"
}
newfx && {
  dev_advance "$WC" src/mod1/a.js "a=conflict"
  run_build "$WC" --allow-diverged
  eq "B9 merge conflict: rc 1" "$BRC" "1"
  has "B9 conflict message tells to merge dev into the session branch" "$BERR" "слейте"
  eq "B9 nothing created on a conflict" "$(gw for-each-ref --format='%(refname)' 'refs/heads/change/*')" ""
}
}

# ---------------------------------------------------------------------------------------------------- [B8a]
blk_B8a() {
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
}

# manifest helpers: mf_load <wc> <tip> loads CHANGE.yaml of the tip with miniyaml; mf <key> prints a scalar, mfl <key> a list
mf_load() { git -C "$1" show "$2:CHANGE.yaml" > "$TMP/m.yaml" 2>/dev/null; my_load "$TMP/m.yaml"; }
mf() { _my_scalar "change.$1"; printf '%s' "$MY_S"; }
mfl() { _my_list "change.$1"; printf '%s' "$MY_L"; }
REG_ADR="docs/DECISIONS.md#ADR-099"
BR=change/C-ACME-001-ex1

# ---------------------------------------------------------------------------------------------------- [B1]
blk_B1() {
echo "[B1] golden path"
newfx && {
  run_build "$WC"
  eq "B1 rc 0" "$BRC" "0"
  eq "B1 stdout is one JSON object with the documented keys" "$(jv 'keys|join(",")')" "adr,archive_sha256,base,base_ref,branch,commitment,diverged,docs,executor,head,resubmit,scope_touched,tip,touches_shared,warnings"
  head="$(jv .head)"; tip="$(jv .tip)"; dev="$(gw rev-parse refs/heads/dev)"
  eq "B1 branch" "$(jv .branch)" "$BR"
  eq "B1 the ref points to the tip" "$(gw rev-parse "refs/heads/$BR")" "$tip"
  eq "B1 tip^ == head" "$(gw rev-parse "$tip^" 2>/dev/null)" "$head"
  eq "B1 head's parent == base" "$(gw rev-parse "$head^" 2>/dev/null)" "$dev"
  eq "B1 base..head is exactly one commit" "$(gw rev-list --count "$dev..$head")" "1"
  eq "B1 its subject is 'C: title'" "$(gw log -n1 --format=%s "$head")" "C-ACME-001: Feature mod1"
  eq "B1 JSON base == dev" "$(jv .base)" "$dev"
  eq "B1 JSON base_ref" "$(jv .base_ref)" "refs/heads/dev"
  eq "B1 JSON commitment/executor" "$(jv '.commitment+"/"+.executor')" "C-ACME-001/ex1"
  eq "B1 JSON resubmit/diverged false" "$(jv '(.resubmit|tostring)+"/"+(.diverged|tostring)')" "false/false"
  oracle_expect "B1 oracle audit() -> approve" "$WC" "$BR" "approve"
  # built-in negative: the same oracle on a damaged package is NOT approve
  pkg_craft_bad_bad_archive "$WC" change/damaged >/dev/null 2>&1
  oracle_of "$WC" change/damaged
  if [ "$ORACLE" = SKIP ]; then :; elif [ "$ORACLE" != approve ]; then pass "B1 negative: the oracle rejects a damaged package ($ORACLE)"; else fail "B1 negative" "the oracle approved a damaged package"; fi
}
}

# ---------------------------------------------------------------------------------------------------- [B2]
blk_B2() {
echo "[B2] plumbing invariants"
newfx && {
  snap() { { gw symbolic-ref HEAD; gw status --porcelain; gw ls-files -s; gw rev-parse refs/heads/sdx/s1 refs/heads/dev; gw for-each-ref --format='%(refname)' refs/heads refs/tags; } 2>&1; }
  before="$(snap)"
  run_build "$WC"
  after="$(snap)"
  eq "B2 rc 0" "$BRC" "0"
  # the only change in refs/heads is the new package branch
  eq "B2 HEAD, status, index and the other refs are unchanged (the new branch aside)" "$(printf '%s\n' "$after" | grep -vxF "refs/heads/$BR")" "$before"
  eq "B2 no CHANGE.yaml on disk" "$(find "$WC" -name CHANGE.yaml -not -path '*/.git/*' | wc -l | tr -d ' ')" "0"
  eq "B2 the working tree is clean" "$(gw status --porcelain)" ""
  eq "B2 tip tree = head tree + exactly one blob (CHANGE.yaml)" "$(gw diff-tree -r --name-status "$(jv .head)" "$(jv .tip)" | tr '\t' ' ')" "A CHANGE.yaml"
  eq "B2 the new ref is the only addition" "$(gw for-each-ref --format='%(refname)' refs/heads | grep -c "^refs/heads/change/")" "1"
  eq "B2 no stray temporary index left in TMPDIR by the run" "$(ls "${TMPDIR:-/tmp}"/sdx-pr-idx.* 2>/dev/null | wc -l | tr -d ' ')" "0"
}
}

# ---------------------------------------------------------------------------------------------------- [B3]
blk_B3() {
echo "[B3] archive_sha256"
newfx && {
  run_build "$WC"
  head="$(jv .head)"; asha="$(jv .archive_sha256)"
  eq "B3 JSON archive_sha256 is 64 hex" "$(printf '%s' "$asha" | grep -cE '^[0-9a-f]{64}$')" "1"
  eq "B3 manifest carries the same value" "$(mf_load "$WC" "$(jv .tip)"; mf archive_sha256)" "$asha"
  eq "B3 = sha256(git archive --format=tar head) in the fixture" "$(gw archive --format=tar "$head" | _pkg_sha256)" "$asha"
  git clone -q "$WC" "$TMP/clone3" >/dev/null 2>&1
  eq "B3 = the same sum recomputed in an INDEPENDENT clone" "$(git -C "$TMP/clone3" archive --format=tar "$head" 2>/dev/null | _pkg_sha256)" "$asha"
  eq "B3 != the sum over the tip (the manifest commit is not part of the identity)" "$([ "$(gw archive --format=tar "$(jv .tip)" | _pkg_sha256)" != "$asha" ] && echo differs)" "differs"
}
}

# ---------------------------------------------------------------------------------------------------- [B4]
blk_B4() {
echo "[B4] scope_touched (generated files included) and touches_shared"
newfx && {
  run_build "$WC"
  mf_load "$WC" "$(jv .tip)"
  eq "B4 scope_touched = all changed paths incl. package-lock.json" "$(mfl scope_touched | tr '\n' ' ')" "docs/DECISIONS.md docs/specs/mod1.md package-lock.json src/mod1/a.js"
  eq "B4 JSON scope_touched is the count" "$(jv .scope_touched)" "4"
  eq "B4 touches_shared true (package-lock.json is a shared path)" "$(mf touches_shared)" "true"
  eq "B4 JSON touches_shared" "$(jv .touches_shared)" "true"
}
newfx && {
  sed '/^    shared_paths:/{N;s/.*/    shared_paths: []/;}' "$WC/.mesh/mandate.yaml" > "$WC/.mesh/m.new" && mv "$WC/.mesh/m.new" "$WC/.mesh/mandate.yaml"
  run_build "$WC"
  mf_load "$WC" "$(jv .tip)"
  eq "B4 touches_shared false when no shared path is touched" "$(mf touches_shared)" "false"
  eq "B4 ... the lock file is still listed in scope_touched" "$(mfl scope_touched | grep -c '^package-lock.json$')" "1"
}
}

# ---------------------------------------------------------------------------------------------------- [B5]
blk_B5() {
echo "[B5] adr, spec, verify, docs"
newfx && {
  run_build "$WC"
  mf_load "$WC" "$(jv .tip)"
  eq "B5 adr = the heading added to the registry" "$(mfl adr)" "$REG_ADR"
  eq "B5 JSON adr" "$(jv '.adr|join(",")')" "$REG_ADR"
  eq "B5 spec = path@short sha" "$(mf spec | sed 's/@[0-9a-f]*$/@H/')" "docs/specs/mod1.md@H"
  eq "B5 the spec sha is a commit of sdx/s1" "$(gw cat-file -t "$(mf spec | sed 's/.*@//')" 2>/dev/null)" "commit"
  eq "B5 verify.tests pass (verification_report.md says 'Итог: PASS')" "$(mf_load "$WC" "$(jv .tip)"; _my_scalar change.verify.tests; printf '%s' "$MY_S")" "pass"
  eq "B5 verify.report points into the branch history" "$(_my_scalar change.verify.report; printf '%s' "$MY_S" | sed 's/@[0-9a-f]*:/@R:/')" "sdx/s1@R:.claude/sessions/s1/verification_report.md"
  eq "B5 docs = changed files under docs_paths" "$(mfl docs | tr '\n' ' ')" "docs/DECISIONS.md docs/specs/mod1.md"
  eq "B5 history_ref" "$(mf history_ref)" "executor:sdx/s1"
  has "B5 notes name the session" "$(mf notes)" "s1"
  eq "B5 JSON docs is the count" "$(jv .docs)" "2"
}
newfx && {   # registry not changed by the session
  gw checkout -q dev -- docs/DECISIONS.md && gw commit -q -m "registry untouched"
  run_build "$WC"
  mf_load "$WC" "$(jv .tip)"
  eq "B5 registry not changed -> adr: []" "$(mfl adr)" ""
  eq "B5 ... and the manifest notes say so" "$(printf '%s' "$(mf notes)" | grep -c 'реестр')" "1"
  eq "B5 ... docs no longer lists the registry" "$(mfl docs | tr '\n' ' ')" "docs/specs/mod1.md"
}
newfx && {   # docs_in_repo: none
  sed 's/^  docs_in_repo: .*/  docs_in_repo: none/' "$WC/.mesh/mandate.yaml" > "$WC/.mesh/m.new" && mv "$WC/.mesh/m.new" "$WC/.mesh/mandate.yaml"
  run_build "$WC"
  mf_load "$WC" "$(jv .tip)"
  eq "B5 docs_in_repo: none -> adr: []" "$(mfl adr)" ""
  eq "B5 ... rc 0" "$BRC" "0"
}
newfx && {   # no spec in the change
  gw checkout -q dev -- docs/specs/mod1.md && gw commit -q -m "spec untouched"
  run_build "$WC"
  mf_load "$WC" "$(jv .tip)"
  eq "B5 no spec in the change -> the key is omitted" "$(my_exists change.spec && echo present || echo omitted)" "omitted"
}
newfx && {   # verification report without PASS
  printf '# V\nИтог: FAIL\n' > "$TMP/vr.md"; fx_set_sfile "$WC" verification_report.md "$TMP/vr.md"
  run_build "$WC"
  mf_load "$WC" "$(jv .tip)"; _my_scalar change.verify.tests
  eq "B5 report without 'Итог: PASS' -> verify.tests unknown" "$MY_S" "unknown"
}
newfx && {   # no verification report at all
  fx_set_sfile "$WC" verification_report.md none
  run_build "$WC"
  mf_load "$WC" "$(jv .tip)"; _my_scalar change.verify.tests; t="$MY_S"; _my_scalar change.verify.report
  eq "B5 no report -> verify.tests unknown, verify.report empty" "$t/$MY_S" "unknown/"
}
}

# ---------------------------------------------------------------------------------------------------- [B11]
blk_B11() {
echo "[B11] the package does not carry the session"
newfx && {
  run_build "$WC"
  lst="$(gw ls-tree -r --name-only "$(jv .tip)")"
  eq "B11 no .claude/sessions/ in the tip tree" "$(printf '%s\n' "$lst" | grep -c '^\.claude/sessions/')" "0"
  eq "B11 no protocol.yaml anywhere in the tip tree" "$(printf '%s\n' "$lst" | grep -cE '(^|/)protocol\.yaml$')" "0"
  eq "B11 tip tree has CHANGE.yaml at the root" "$(printf '%s\n' "$lst" | grep -cx 'CHANGE.yaml')" "1"
}
}

# ---------------------------------------------------------------------------------------------------- [B6]
yaml_json() {   # <file> -> JSON of yaml.safe_load on stdout; rc 77 without python3/PyYAML (the oracle)
  command -v python3 >/dev/null 2>&1 || return 77
  python3 -I -B -c 'import sys, json
try:
    import yaml
except ImportError:
    sys.exit(77)
print(json.dumps(yaml.safe_load(open(sys.argv[1], encoding="utf-8")), ensure_ascii=False))' "$1"
}
blk_B6() {
echo "[B6] escaping: hostile values survive the round trip through miniyaml and yaml.safe_load"
HOSTILE_NOTES=$'Say "hi" \\ back: colon # hash \'q\' {} - dash [x] Привет\nsecond line'
HOSTILE_PATH="src/mod1/q\"b\\c: d #e 'f' {g} - h Привет.js"
newfx && {
  fx_commit "$WC" "$HOSTILE_PATH" "x" "hostile path"
  run_build "$WC" --title $'Say "hi" \\ back: colon # hash\nsecond' --notes "$HOSTILE_NOTES"
  eq "B6 rc 0 with hostile title, notes and path" "$BRC" "0"
  tip="$(jv .tip)"
  eq "B6 the commit subject is the title with the newline folded to a space" "$(gw log -n1 --format=%s "$(jv .head)")" 'C-ACME-001: Say "hi" \ back: colon # hash second'
  mf_load "$WC" "$tip"
  eq "B6 miniyaml reads the notes (newline folded to a space)" "$(mf notes)" 'Say "hi" \ back: colon # hash '"'q'"' {} - dash [x] Привет second line'
  eq "B6 miniyaml reads the hostile path back unchanged" "$(mfl scope_touched | grep -cxF -- "$HOSTILE_PATH")" "1"
  eq "B6 mandate_digest of digits stays a string for miniyaml" "$(mf mandate_digest)" "123456789012"
  gw show "$tip:CHANGE.yaml" > "$TMP/hostile.yaml"
  yaml_json "$TMP/hostile.yaml" > "$TMP/hostile.json" 2>/dev/null; yrc=$?
  if [ "$yrc" = 77 ]; then info "yaml.safe_load oracle skipped: python3 with PyYAML is absent (NOT passed, only skipped)"
  else
    eq "B6 yaml.safe_load: notes equal the miniyaml value" "$(jq -r .change.notes "$TMP/hostile.json")" "$(mf notes)"
    eq "B6 yaml.safe_load: the hostile path is intact" "$(jq -r --arg p "$HOSTILE_PATH" '[.change.scope_touched[] | select(. == $p)] | length' "$TMP/hostile.json")" "1"
    eq "B6 yaml.safe_load: mandate_digest is a string, not a number" "$(jq -r '.change.mandate_digest | type' "$TMP/hostile.json")" "string"
    eq "B6 yaml.safe_load: touches_shared is a boolean" "$(jq -r '.change.touches_shared | type' "$TMP/hostile.json")" "boolean"
    eq "B6 yaml.safe_load: format is the number 1" "$(jq -r '.change.format' "$TMP/hostile.json")" "1"
  fi
}
}

# ---------------------------------------------------------------------------------------------------- [B10]
mk_plugin() {   # <dir>: a copy of the script under test with its lib/ and the vendored template -> SUTX
  mkdir -p "$1/hooks" "$1/mo" && cp -Rp "$(dirname "$SUT")/lib" "$1/hooks/lib" && cp "$SUT" "$1/hooks/pr-build.sh" \
    && cp "$ROOT/sdx/mo/CHANGE.template.yaml" "$1/mo/CHANGE.template.yaml"
}
blk_B10() {
echo "[B10] template-driven generation"
tpl_keys() { grep -E '^  [a-z0-9_]+:' "$1" | sed 's/^  \([a-z0-9_]*\):.*/\1/' | tr '\n' ' '; }
newfx && {
  run_build "$WC"
  eq "B10 keys and order of the manifest = keys of the vendored template" "$(gw show "$(jv .tip):CHANGE.yaml" > "$TMP/man10.yaml"; tpl_keys "$TMP/man10.yaml")" "$(tpl_keys "$ROOT/sdx/mo/CHANGE.template.yaml")"
  eq "B10 first line says format 1" "$(head -n1 "$TMP/man10.yaml" | grep -c 'format 1')" "1"
  eq "B10 the root key is 'change:'" "$(sed -n '2p' "$TMP/man10.yaml")" "change:"
  eq "B10 every string value is double-quoted (digest included)" "$(grep -cE '^  (commitment|executor|mandate_digest|base|head|archive_sha256|history_ref|notes|spec): "' "$TMP/man10.yaml")" "9"
}
newfx && {
  mk_plugin "$TMP/plug10a" && printf '  extra_field: x\n' >> "$TMP/plug10a/mo/CHANGE.template.yaml"
  SUTX="$TMP/plug10a/hooks/pr-build.sh" run_build "$WC"
  eq "B10 template with an unknown key: rc 1" "$BRC" "1"
  has "B10 ... 'обновите плагин' and the key named" "$BERR" "extra_field"
  has "B10 ... tells to update the plugin" "$BERR" "обновите плагин"
  eq "B10 ... nothing created" "$(gw for-each-ref --format='%(refname)' 'refs/heads/change/*')" ""
}
newfx && {
  mk_plugin "$TMP/plug10b" && grep -v '^  adr:' "$TMP/plug10b/mo/CHANGE.template.yaml" > "$TMP/plug10b/t.new" && mv "$TMP/plug10b/t.new" "$TMP/plug10b/mo/CHANGE.template.yaml"
  SUTX="$TMP/plug10b/hooks/pr-build.sh" run_build "$WC"
  eq "B10 template without 'adr': rc 0" "$BRC" "0"
  eq "B10 ... the manifest has no adr key" "$(gw show "$(jv .tip):CHANGE.yaml" 2>/dev/null | grep -c '^  adr:')" "0"
  eq "B10 ... and keeps the other keys" "$(gw show "$(jv .tip):CHANGE.yaml" 2>/dev/null | grep -c '^  docs:')" "1"
}
}

# ---------------------------------------------------------------------------------------------------- [B12]
blk_B12() {
echo "[B12] the manifest commit sits on head"
newfx && {
  run_build "$WC"
  head="$(jv .head)"; tip="$(jv .tip)"
  eq "B12 the tip's only parent is head (not base)" "$(gw rev-list --parents -n1 "$tip" | cut -d' ' -f2-)" "$head"
  eq "B12 ... which is not the base" "$([ "$head" != "$(jv .base)" ] && echo differs)" "differs"
  eq "B12 the manifest commit changes exactly one file: CHANGE.yaml" "$(gw diff-tree -r --name-only "$head" "$tip")" "CHANGE.yaml"
  eq "B12 its subject" "$(gw log -n1 --format=%s "$tip")" "SDX: CHANGE.yaml (C-ACME-001)"
  eq "B12 the manifest names the head" "$(mf_load "$WC" "$tip"; mf head)" "$head"
}
}

# ---------------------------------------------------------------------------------------------------- [B8]
blk_B8() {
echo "[B8] race on the package ref (compare-and-swap)"
mk_shim() {   # <dir> <wc> <target-sha>: a fake git that creates the ref behind pr-build's back at the manifest commit
  mkdir -p "$1"
  {
    printf '#!/usr/bin/env bash\nreal=%s\n' "$(command -v git)"
    printf 'case " $* " in *" commit-tree "*)\n  n=$(cat "%s/n" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "%s/n"\n' "$1" "$1"
    printf '  [ "$n" = 2 ] && "$real" -C "%s" update-ref refs/heads/%s "%s" ;;\nesac\nexec "$real" "$@"\n' "$2" "$BR" "$3"
  } > "$1/git"
  chmod +x "$1/git"
}
newfx && {
  dev="$(gw rev-parse refs/heads/dev)"; mk_shim "$TMP/shim1" "$WC" "$dev"
  OLDPATH="$PATH"; PATH="$TMP/shim1:$PATH"; run_build "$WC"; PATH="$OLDPATH"
  eq "B8 a ref created in between: rc 1" "$BRC" "1"
  has "B8 ... the message names the compare-and-swap" "$BERR" "CAS"
  eq "B8 ... the foreign value is not overwritten" "$(gw rev-parse "refs/heads/$BR")" "$dev"
}
newfx && {
  pkg_craft_good "$WC" "$BR" >/dev/null 2>&1; old="$PKG_TIP"; dev="$(gw rev-parse refs/heads/dev)"; mk_shim "$TMP/shim2" "$WC" "$dev"
  OLDPATH="$PATH"; PATH="$TMP/shim2:$PATH"; run_build "$WC" --resubmit; PATH="$OLDPATH"
  eq "B8 re-submission raced: rc 1" "$BRC" "1"
  eq "B8 ... the ref keeps the foreign value" "$(gw rev-parse "refs/heads/$BR")" "$dev"
}
}

# ---------------------------------------------------------------------------------------------------- [Port]
blk_Port() {
echo "[Port] portability (BUG-010) and the absence of forbidden constructs in pr-build.sh"
FORBID='tim''eout|map''file|declare -''A|[$]\{[a-zA-Z_]+,,\}|%''N|readlink -''f|real''path|[A-Za-z_]=\(|\[@\]'
if grep -nE "$FORBID" "$SUT" >/dev/null 2>&1; then fail "pr-build.sh portability" "forbidden: $(grep -nE "$FORBID" "$SUT" | head -3)"; else pass "pr-build.sh has no bash-4-only construct, no arrays, no GNU-only calls"; fi
sed 's/^here=/mapfile -t x < \/dev\/null; here=/' "$SUT" > "$TMP/port-mut.sh"
if ! cmp -s "$SUT" "$TMP/port-mut.sh" && grep -qE "$FORBID" "$TMP/port-mut.sh"; then pass "red side: the same grep flags a mutant with a bash-4 construct"; else fail "red side of the portability grep" "mutant not flagged"; fi
if grep -nE 'py''thon|(^|[^_[:alnum:]])ev''al([^_[:alnum:]]|$)|check''out|work''tree' "$SUT" >/dev/null 2>&1; then fail "pr-build.sh forbidden words" "$(grep -nE 'py''thon|(^|[^_[:alnum:]])ev''al([^_[:alnum:]]|$)|check''out|work''tree' "$SUT" | head -3)"; else pass "no python / eval / checkout / worktree in pr-build.sh"; fi
}

# @@TAIL@@
# ---------------------------------------------------------------------------------------------------- [Mut]
blk_Mut() {
[ -z "${PR_BUILD_NESTED:-}" ] || return 0
echo "[Mut] mutation runs: each mutant (a copy of pr-build.sh + lib/ + the template in a temp dir) must differ from the original and turn its block red"
MUTDIR="$TMP/mut"; mkdir -p "$MUTDIR"
OWNED="sdx/hooks/pr-build.sh sdx/hooks/lib sdx/mo"
ST_BEFORE="$(git -C "$ROOT" status --porcelain -- $OWNED)"
MUT_NAMES=""
# mutate <name> <sed expr> <blocks> [b7 cases]: start a nested run of this suite against the mutated script (in the background)
mutate() {
  local name="$1" expr="$2" only="$3" b7="${4:-}" d="$MUTDIR/$1"
  mk_plugin "$d" || { fail "[Mut] $name" "cannot copy the script under test"; return; }
  sed "$expr" "$SUT" > "$d/hooks/pr-build.sh"
  if cmp -s "$SUT" "$d/hooks/pr-build.sh"; then fail "[Mut] $name" "mutant is identical to the original (anchor missing?)"; return; fi
  MUT_NAMES="$MUT_NAMES $name"
  ( PR_BUILD_NESTED=1 PR_BUILD_ONLY="$only" PR_BUILD_B7="$b7" SCEN_MIN=1 PR_BUILD_UNDER_TEST="$d/hooks/pr-build.sh" bash "${BASH_SOURCE[0]}" > "$d/out.txt" 2>&1 ) &
}
mutate PKG-PLUMB          's|   # PKG-PLUMB|; printf "%s\\n" "$manifest" > "$proj/CHANGE.yaml"   # PKG-PLUMB|' "B2"
mutate PKG-ARCHIVE        '/# PKG-ARCHIVE/s/"\$head" | pr_sha256/"$srcsha" | pr_sha256/' "B3"
mutate PKG-SCOPE-TOUCHED  's|^scope_files="\$PR_FILES"|scope_files="$(printf "%s\\n" "$PR_FILES" \| grep -v lock)"|' "B4"
mutate PKG-SHARED         '/# PKG-SHARED/s/ts=true/ts=false/' "B4"
mutate PKG-QUOTE          's|def q: tojson;|def q: "\\"" + . + "\\"";|' "B6"
mutate PKG-NOCHANGEYAML   '/# PKG-NOCHANGEYAML/s/&& die 1 "[^"]*"/\&\& true/' "B7" "chg"
mutate PKG-EMPTY          '/# PKG-EMPTY/s/|| die 1 "[^"]*"/|| true/' "B7" "empty"
mutate PKG-CAS            '/# PKG-CAS/s/"\$tip" "\$zero"/"$tip"/' "B8"
mutate PKG-ANCESTOR       '/# PKG-ANCESTOR/s/if git -C "\$proj" merge-base --is-ancestor "\$PR_BASE_SHA" "\$srcsha"; then/if true; then/' "B9"
mutate PKG-TEMPLATE-KEYS  '/# PKG-TEMPLATE-KEYS/s/\*) die 1 "[^"]*" ;;/*) : ;;/' "B10"
mutate PKG-TIPPARENT      '/# PKG-TIPPARENT/s/-p "\$head"/-p "$PR_BASE_SHA"/' "B12"
wait
for name in $MUT_NAMES; do
  out="$(cat "$MUTDIR/$name/out.txt" 2>/dev/null)"
  if printf '%s\n' "$out" | grep -q 'FAIL:'; then
    first="$(printf '%s\n' "$out" | grep -m1 'FAIL:' | cut -c1-110)"
    pass "[Mut] мутант $name → красный (ожидаемо): ${first#  FAIL: }"
  else
    fail "[Mut] $name" "the distinguishing block stayed green on the mutant (the check proves nothing)"
  fi
done
eq "[Mut] the checkout (pr-build.sh, lib/, sdx/mo) is untouched by the mutation runs" "$(git -C "$ROOT" status --porcelain -- $OWNED)" "$ST_BEFORE"
}

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
run_blocks B7 B9 B8a B1 B2 B3 B4 B5 B6 B10 B12 B8 B11 Port Mut

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
