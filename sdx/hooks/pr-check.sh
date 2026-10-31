#!/usr/bin/env bash
# sdx/hooks/pr-check.sh — deterministic check of a change package before publication (FEAT-017, /sdx:pr,
# REQ-PKG-8, 11, 12, 26, 27). The analogue of `closeout-check` of the bridge: any FAIL blocks the push.
# It MIRRORS the formal checks of audit() of the node (manifest.commit, scope, archive_sha256, adr, branch,
# mandate.valid, nonempty, shared.declared); the live audit() is never called by the plugin.
#
#   bash pr-check.sh --sid <sid> [--phase pre|post|all] [--proj DIR] [--commitment C] [--title T] [--base-name B] [--no-tests]
#   stdout: "OK|FAIL|WARN|NOTE <id>: <text>" lines, the last one "PR-CHECK PASS" | "PR-CHECK WARN <n>" | "PR-CHECK FAIL <n>"
#   rc: 0 PASS | 3 WARN only (the user must confirm) | 1 FAIL | 2 usage / environment      --phase defaults to all
#
# Phase pre  — before the build: closeout state, ids, branch name vs scope.branches, the mandate, the base, a PREDICTED
#              diff (git diff or, for a diverged base, the tree of merge-tree), docs, registry, URL, the project tests.
# Phase post — after the build: reads refs/heads/<branch> and its CHANGE.yaml (manifest, commit shape, archive, scope).
# Every value of the mandate / order / manifest reaches the output through pr_clean (data, not instructions).
# bash 3.2, no arrays; no interpreters other than bash/awk/sed/jq/git. Anchors "# PKG-C-*" are mutation-run labels.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -f "$here/lib/pr-lib.sh" ]; then echo "pr-check: lib/pr-lib.sh плагина не найдена." >&2; exit 2; fi
. "$here/lib/pr-lib.sh"

usage() { echo "pr-check: использование: pr-check.sh --sid <sid> [--phase pre|post|all] [--proj DIR] [--commitment C] [--title T] [--base-name B] [--no-tests]" >&2; exit 2; }

sid=""; proj="${CLAUDE_PROJECT_DIR:-.}"; phase=all; a_c=""; a_t=""; a_b=""; no_tests=0
while [ $# -gt 0 ]; do
  case "$1" in
    --sid|--proj|--phase|--commitment|--title|--base-name)
      [ $# -ge 2 ] || usage
      case "$1" in --sid) sid="$2" ;; --proj) proj="$2" ;; --phase) phase="$2" ;; --commitment) a_c="$2" ;; --title) a_t="$2" ;; *) a_b="$2" ;; esac
      shift 2 ;;
    --no-tests) no_tests=1; shift ;;
    *) usage ;;
  esac
done
[ -n "$sid" ] || usage
case "$phase" in pre|post|all) ;; *) usage ;; esac
command -v git >/dev/null 2>&1 || { echo "pr-check: git не найден" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "pr-check: jq не найден" >&2; exit 2; }
git -C "$proj" rev-parse --git-dir >/dev/null 2>&1 || { echo "pr-check: $proj не git-репозиторий" >&2; exit 2; }
proj="$(cd "$proj" && pwd)"

nfail=0; nwarn=0
emit() { pr_clean "$3" 300; printf '%s %s: %s\n' "$1" "$2" "$PR_CLEAN"; }
ok() { emit OK "$1" "$2"; }
note() { emit NOTE "$1" "$2"; }
fail() { emit FAIL "$1" "$2"; nfail=$((nfail + 1)); }
warn() { emit WARN "$1" "$2"; nwarn=$((nwarn + 1)); }
finish() {
  if [ "$nfail" -gt 0 ]; then echo "PR-CHECK FAIL $nfail"; exit 1; fi
  if [ "$nwarn" -gt 0 ]; then echo "PR-CHECK WARN $nwarn"; exit 3; fi
  echo "PR-CHECK PASS"; exit 0
}

# closeout_state: the three checks of `mandate-info.sh closeout-check` (branch, clean tree, no session directory in HEAD),
# proxied as they are and given ids. Used by `pre` and (repeated: the state may change between confirmations) by `post`.
closeout_state() {
  local l st txt cid
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    st="${l%% *}"; txt="${l#* }"
    case "$txt" in
      "текущая ветка"*) cid=closeout.branch ;;
      "рабочее дерево"*) cid=closeout.tree ;;       # PKG-C-TREE
      "каталог сессии"*) cid=closeout.session ;;    # PKG-C-SESSION
      *) cid=closeout.state ;;
    esac
    if [ "$st" = OK ]; then ok "$cid" "$txt"; else fail "$cid" "$txt"; fi
  done <<< "$(bash "$here/mandate-info.sh" closeout-check "$sid" "$proj" 2>/dev/null)"
}

# ---- who, what, from where (pr_resolve; the mandate is loaded by it) ----
set --
[ -z "$a_c" ] || set -- "$@" --commitment "$a_c"
[ -z "$a_t" ] || set -- "$@" --title "$a_t"
[ -z "$a_b" ] || set -- "$@" --base-name "$a_b"
res_err=""; res_url_err=0
case "$phase" in pre|all) closeout_state ;; esac
if ! pr_resolve "$proj" "$sid" "$@"; then
  res_err="$PR_ERR"
  case "$res_err" in
    commitment:*) rid=id.commitment ;;
    executor:*) rid=id.executor ;;
    branch:*|deliver.branch:*) rid=branch.name ;;
    base:*) rid=base.ref ;;
    title:*) rid=id.title ;;
    repo.url:*) rid=url.scheme; res_url_err=1 ;;
    mandate:*) rid=mandate.load ;;
    session:*) rid=session.ref ;;
    *) rid=resolve ;;
  esac
  fail "$rid" "$res_err"
  [ "$res_url_err" = 1 ] || finish   # a refused URL does not stop the other checks (everything else is resolved by then)
else
  ok id.commitment "$PR_C"; ok id.executor "$PR_EXEC"; ok branch.name "$PR_BRANCH"
fi

src="refs/heads/sdx/$sid"
srcsha="$(git -C "$proj" rev-parse --verify -q "$src^{commit}" 2>/dev/null)"
if [ -z "$srcsha" ]; then fail session.ref "нет ветки sdx/$sid"; finish; fi

# mandate-level checks shared by both phases
check_mandate() {
  local p
  if [ -n "$MANDATE_BRANCHES" ]; then
    p=""
    while IFS= read -r b; do
      [ -n "$b" ] || continue
      if mandate_fnmatch "$PR_BRANCH" "$b"; then p=1; break; fi
    done <<< "$MANDATE_BRANCHES"
    if [ -n "$p" ]; then ok branch.scope "имя $PR_BRANCH входит в scope.branches"; else fail branch.scope "имя $PR_BRANCH не входит в scope.branches мандата"; fi   # PKG-C-BRANCH
  else
    note branch.scope "scope.branches в мандате не задан — узел имя ветки не проверяет"
  fi
  _my_scalar mandate.valid_until
  if mandate_expired; then fail mandate.valid "мандат истёк (valid_until=$MY_S)"; else ok mandate.valid "valid_until=${MY_S:-—}"; fi   # PKG-C-EXPIRED
}

phase_pre() {
  local anc b
  check_mandate
  if printf '%s' "$PR_DIGEST" | grep -Eq '^[0-9a-f]{12}$'; then ok mandate.digest "$PR_DIGEST"; else fail mandate.digest "в мандате нет digest из 12 hex-знаков"; fi
  _my_scalar mandate.history
  if [ "$MY_S" = executor ] && [ "$PR_DOCS_MODE" = none ]; then
    warn mandate.lint "history: executor вместе с docs_in_repo: none — lint узла такой мандат отвергает"
  fi
  if [ -n "$res_err" ] && [ "$res_url_err" != 1 ]; then return 0; fi
  ok base.ref "$PR_BASE_REF"
  if git -C "$proj" merge-base --is-ancestor "$PR_BASE_SHA" "$srcsha" 2>/dev/null; then
    anc=1; ok base.ancestor "sdx/$sid вырезана от $PR_BASE_NAME"
  else
    anc=0; warn base.ancestor "sdx/$sid вырезана не от текущей $PR_BASE_NAME — потребуется --allow-diverged"
  fi
  if [ "$PR_BASE_DRIFT" = 1 ]; then warn base.remote-drift "локальная $PR_BASE_NAME отличается от remote-tracking (пакет строится от локальной)"
  else ok base.remote-drift "расхождения локальной и remote-tracking нет"; fi
  if git -C "$proj" rev-parse --verify -q "refs/heads/$PR_BRANCH" >/dev/null 2>&1; then
    warn branch.exists "пакет $PR_BRANCH уже собран — повторная сдача (--resubmit)"
  else ok branch.exists "ветки $PR_BRANCH ещё нет"; fi
}

case "$phase" in
  pre) phase_pre ;;
  all) phase_pre ;;
esac
finish
