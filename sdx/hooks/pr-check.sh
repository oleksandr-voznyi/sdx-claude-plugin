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
# emit <STATUS> <id> <text>: the text is DATA-adjacent (it quotes mandate, order and manifest values): a text with control characters or
# Unicode line separators goes through pr_clean; a clean one (the common case) is printed as is — no fork per line
emit() {
  local LC_ALL=C t="$3"
  case "$t" in
    *[[:cntrl:]]*|*$'\342\200\250'*|*$'\342\200\251'*|*$'\302'*) pr_clean "$t" 300; t="$PR_CLEAN" ;;
    *) [ ${#t} -le 300 ] || { pr_clean "$t" 300; t="$PR_CLEAN"; } ;;
  esac
  printf '%s %s: %s\n' "$1" "$2" "$t"
}
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
closeout_state
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
  local b
  check_mandate
  if printf '%s' "$PR_DIGEST" | grep -Eq '^[0-9a-f]{12}$'; then ok mandate.digest "$PR_DIGEST"; else fail mandate.digest "в мандате нет digest из 12 hex-знаков"; fi
  _my_scalar mandate.history
  if [ "$MY_S" = executor ] && [ "$PR_DOCS_MODE" = none ]; then
    warn mandate.lint "history: executor вместе с docs_in_repo: none — lint узла такой мандат отвергает"
  fi
  if [ -n "$res_err" ] && [ "$res_url_err" != 1 ]; then return 0; fi
  ok base.ref "$PR_BASE_REF"
  if git -C "$proj" merge-base --is-ancestor "$PR_BASE_SHA" "$srcsha" 2>/dev/null; then
    PRE_ANC=1; ok base.ancestor "sdx/$sid вырезана от $PR_BASE_NAME"
  else
    PRE_ANC=0; warn base.ancestor "sdx/$sid вырезана не от текущей $PR_BASE_NAME — потребуется --allow-diverged"
  fi
  if [ "$PR_BASE_DRIFT" = 1 ]; then warn base.remote-drift "локальная $PR_BASE_NAME отличается от remote-tracking (пакет строится от локальной)"
  else ok base.remote-drift "расхождения локальной и remote-tracking нет"; fi
  if git -C "$proj" rev-parse --verify -q "refs/heads/$PR_BRANCH" >/dev/null 2>&1; then
    warn branch.exists "пакет $PR_BRANCH уже собран — повторная сдача (--resubmit)"
  else ok branch.exists "ветки $PR_BRANCH ещё нет"; fi
}

# _flist <newline list> -> FLIST: "a, b, c (+N)"
_flist() {
  local n=0 out="" f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    n=$((n + 1))
    [ "$n" -gt 3 ] || out="$out${out:+, }$f"
  done <<< "$1"
  [ "$n" -le 3 ] || out="$out (+$((n - 3)))"
  FLIST="$out"
}

# _tree_files <base sha> <tree>: PR_FILES of base..tree (the predicted diff of a diverged base); rc 1 on a control character
_tree_files() {
  local LC_ALL=C raw chk
  PR_FILES=""
  raw="$(git -C "$proj" -c core.quotepath=off diff --no-renames --name-only -z "$1" "$2" -- 2>/dev/null | tr '\0' '\001')"
  _my_rep "$raw" $'\001' ""; chk="$MY_REP"
  case "$chk" in *[[:cntrl:]]*) PR_ERR="files: путь с управляющим символом (в манифест не попадает)"; return 1 ;; esac
  _my_rep "$raw" $'\001' $'\n'; PR_FILES="${MY_REP%$'\n'}"
  return 0
}

# the PREDICTED diff and everything judged by it
pre_diff() {
  local mt tree n a r url_res rem rn found
  PR_FILES=""
  if [ "${PRE_ANC:-0}" = 1 ]; then
    pr_files "$proj" "$PR_BASE_SHA" "$srcsha" || { fail diff.predict "$PR_ERR"; return 0; }
  else
    mt="$(git -C "$proj" merge-tree --write-tree "$PR_BASE_SHA" "$srcsha" 2>/dev/null)" \
      || { fail diff.predict "слияние $PR_BASE_NAME и sdx/$sid даёт конфликт или git < 2.38 — дифф пакета не предсказать"; return 0; }
    tree="$(printf '%s\n' "$mt" | head -n1)"
    _tree_files "$PR_BASE_SHA" "$tree" || { fail diff.predict "$PR_ERR"; return 0; }
  fi
  n="$(printf '%s\n' "$PR_FILES" | grep -c .)"
  if [ "$n" -gt 0 ]; then ok diff.nonempty "файлов в дельте: $n"; else fail diff.nonempty "дельта base..head пуста — сдавать нечего"; fi
  pr_scope_eval
  if [ -n "$PR_OUT" ]; then _flist "$PR_OUT"; fail diff.scope "вне области мандата (paths ∪ shared_paths ∪ docs_paths): $FLIST"   # PKG-C-SCOPE
  else ok diff.scope "все пути в области мандата"; fi
  if [ -n "$PR_SESSF" ]; then _flist "$PR_SESSF"; fail diff.session "в дифф попали пути каталога сессии: $FLIST"
  else ok diff.session "каталога сессии в диффе нет"; fi
  if [ "$PR_DOCS_MODE" = none ]; then
    note docs.final "docs_in_repo: none — состав документов не проверяется"
  elif [ -n "$PR_DOCS_OUTSIDE" ]; then _flist "$PR_DOCS_OUTSIDE"; fail docs.final "документы вне docs_paths при docs_in_repo: final: $FLIST"   # PKG-C-DOCS-FINAL
  else ok docs.final "документы пакета входят в docs_paths"; fi
  if [ "$PR_DOCS_MODE" = none ]; then
    note adr.registry "docs_in_repo: none — реестр решений не проверяется"
  else
    pr_registry "$proj" "$PR_BASE_SHA" "$srcsha"
    case "$PR_REG_STATE" in
      one)
        if mandate_match_list "$PR_REG_PATH" "$MANDATE_DOCS"; then ok adr.registry "реестр $PR_REG_PATH изменён и входит в docs_paths"
        else warn adr.registry "реестр $PR_REG_PATH вне docs_paths мандата (по ответу МО §3 п.3 узел его не примет в составе документов)"; fi ;;
      ambiguous) _flist "$PR_REG_CAND"; warn adr.registry "реестр решений неоднозначен: $FLIST" ;;
      *) warn adr.registry "реестр решений за сессию не менялся (adr манифеста будет пуст)" ;;   # PKG-C-ADR
    esac
  fi
  if [ -n "$PR_SHARED" ]; then _flist "$PR_SHARED"; note shared.note "touches_shared: true — слияние такого пакета решает человек: $FLIST"; fi
  a="$(git -C "$proj" rev-parse --git-path info/attributes 2>/dev/null)"
  case "$a" in /*) ;; *) a="$proj/$a" ;; esac
  if { [ -f "$a" ] && grep -Eq 'export-(ignore|subst)' "$a"; } || git -C "$proj" show "$srcsha:.gitattributes" 2>/dev/null | grep -Eq 'export-(ignore|subst)'; then
    warn attrs.export "в атрибутах git есть export-ignore/export-subst: сумма git archive у узла может не совпасть с archive_sha256"
  else ok attrs.export "export-ignore / export-subst нет"; fi
  if [ "$res_url_err" = 1 ]; then :   # url.scheme is already reported by the resolution
  elif [ -z "$PR_URL" ]; then note url.scheme "repo.url в заказе не задан — push пойдёт в remote origin (или --remote)"
  elif pr_url_ok "$PR_URL"; then
    pr_url_show "$PR_URL"; ok url.scheme "$PR_URLS"
    url_res="$(git -C "$proj" ls-remote --get-url "$PR_URL" 2>/dev/null)"
    found=0
    while IFS= read -r rn; do
      [ -n "$rn" ] || continue
      rem="$(git -C "$proj" remote get-url "$rn" 2>/dev/null)"
      if [ "$rem" = "$url_res" ] || [ "$rem" = "$PR_URL" ]; then found=1; break; fi
    done <<< "$(git -C "$proj" remote 2>/dev/null)"
    if [ "$found" = 1 ]; then ok url.origin-drift "repo.url заказа совпадает с настроенным remote $rn"
    else warn url.origin-drift "repo.url заказа ($PR_URLS) не совпадает ни с одним настроенным remote — push пойдёт в URL заказа"; fi
  else fail url.scheme "repo.url: недопустимая схема или символы"; fi
}

# the project tests again (REQ-PKG-11 з): the session cache is gone after Closeout step 5, so the runner is run afresh.
# Last, and only when nothing above failed. A diverged base means the working tree is not the package: then a pass is only a WARN.
pre_tests() {
  local tmo="" cand out rc secs
  [ "$nfail" -eq 0 ] || return 0
  if [ "$no_tests" = 1 ]; then note tests "--no-tests: повторный прогон тестов пропущен по запросу пользователя"; return 0; fi
  test_cmd_resolve "$proj"
  if [ -z "$TC_CMD" ]; then note tests "тест-команды в проекте нет — прогон пропущен"; return 0; fi
  for cand in "tim""eout" "gtim""eout"; do
    if command -v "$cand" >/dev/null 2>&1; then tmo="$cand"; break; fi
  done
  secs="${SDX_VERIFY_TIMEOUT:-180}"
  if [ -n "$tmo" ]; then out="$(cd "$proj" && "$tmo" "$secs" bash -c "$TC_CMD" 2>&1)"; rc=$?
  else
    note tests "утилиты ограничения времени нет (macOS без coreutils) — прогон без лимита"
    out="$(cd "$proj" && bash -c "$TC_CMD" 2>&1)"; rc=$?
  fi
  if [ "$rc" -ne 0 ]; then   # PKG-C-TESTS
    fail tests "тест-команда проекта ($TC_KIND) завершилась кодом $rc"
    { echo "pr-check: tests: хвост вывода (rc=$rc):"; printf '%s\n' "$out" | tail -n 15 | LC_ALL=C tr -d '\000-\010\013-\037\177'; } >&2
  elif [ "${PRE_ANC:-0}" != 1 ]; then
    warn tests "тест-команда зелёная, но прогон не относится к пакету (рабочее дерево ≠ дерево пакета: base расходится)"
  else
    ok tests "тест-команда проекта ($TC_KIND) зелёная"
  fi
}

# the built package (post): reads refs/heads/<branch>, its CHANGE.yaml, and judges the package by the same formal checks
# as audit() of the node
phase_post() {
  local tip mtmp man_text parents changed asha mb mb2 f bad
  tip="$(git -C "$proj" rev-parse --verify -q "refs/heads/$PR_BRANCH^{commit}" 2>/dev/null)"
  if [ -z "$tip" ]; then fail pkg.ref "ветка $PR_BRANCH не собрана (сначала pr-build)"; return 0; fi
  [ "$phase" != post ] || check_mandate   # `post` alone repeats these: the branch and the term may have changed since the confirmations
  mtmp="$(mktemp "${TMPDIR:-/tmp}/sdx-pr-man.XXXXXX")" || { echo "pr-check: не удалось создать временный файл" >&2; exit 2; }
  if ! git -C "$proj" show "$tip:CHANGE.yaml" > "$mtmp" 2>/dev/null; then rm -f "$mtmp"; fail manifest.parse "в корне вершины $PR_BRANCH нет CHANGE.yaml"; return 0; fi
  man_text="$(cat "$mtmp")"
  if ! my_load "$mtmp"; then rm -f "$mtmp"; fail manifest.parse "CHANGE.yaml не разобран: $MY_ERR"; mandate_load "$proj"; return 0; fi
  rm -f "$mtmp"
  if ! my_exists change; then fail manifest.parse "в CHANGE.yaml нет корневого ключа change"; mandate_load "$proj"; return 0; fi
  _my_scalar change.format; M_FORMAT="$MY_S"
  _my_scalar change.commitment; M_C="$MY_S"
  _my_scalar change.executor; M_EXEC="$MY_S"
  _my_scalar change.mandate_digest; M_DIGEST="$MY_S"
  _my_scalar change.head; M_HEAD="$MY_S"
  _my_scalar change.archive_sha256; M_ASHA="$MY_S"
  _my_scalar change.touches_shared; M_SHARED="$MY_S"
  _my_list change.scope_touched; M_SCOPE="$MY_L"
  _my_list change.adr; M_ADR="$MY_L"
  mandate_load "$proj"   # my_load replaced the loaded document: restore the mandate (MANDATE_* stayed, MY_NORM did not)
  ok manifest.parse "CHANGE.yaml в корне вершины разобран"

  if [ "$M_FORMAT" = 1 ]; then ok manifest.format "format: 1"; else fail manifest.format "change.format должен быть 1, а не '$M_FORMAT'"; fi
  if [ -z "$M_HEAD" ]; then
    fail manifest.head "в манифесте нет head (голова кода, над которой стоит коммит манифеста)"
    M_HEAD="$tip"
  elif ! printf '%s' "$M_HEAD" | grep -Eq '^[0-9a-f]{40}$' || ! git -C "$proj" cat-file -e "$M_HEAD^{commit}" 2>/dev/null; then
    fail manifest.head "head '$M_HEAD' не является коммитом репозитория"; return 0
  fi
  parents="$(git -C "$proj" rev-list --parents -n1 "$tip" 2>/dev/null | cut -d' ' -f2-)"
  changed="$(git -C "$proj" diff --name-only "$M_HEAD" "$tip" 2>/dev/null)"
  if [ "$parents" = "$M_HEAD" ] && [ "$changed" = CHANGE.yaml ]; then   # PKG-C-TIPCOMMIT
    ok manifest.commit "вершина — один коммит поверх head, меняет только CHANGE.yaml"
  else
    fail manifest.commit "поверх head должен стоять ровно один коммит с единственным файлом CHANGE.yaml (родитель вершины: ${parents:-—}; изменено: ${changed:-ничего})"
  fi
  if git -C "$proj" cat-file -e "$M_HEAD:CHANGE.yaml" 2>/dev/null; then fail manifest.headtree "в дереве head есть корневой CHANGE.yaml (манифест внутри кода)"
  else ok manifest.headtree "в дереве head нет CHANGE.yaml"; fi
  if [ "$M_C" = "$PR_C" ] && [ "$M_EXEC" = "$PR_EXEC" ] && [ "$M_DIGEST" = "$PR_DIGEST" ]; then
    ok manifest.identity "commitment, executor, mandate_digest совпадают с заказом и мандатом"
  else
    fail manifest.identity "commitment/executor/mandate_digest манифеста ('$M_C'/'$M_EXEC'/'$M_DIGEST') не совпадают с заказом и мандатом ('$PR_C'/'$PR_EXEC'/'$PR_DIGEST')"
  fi
  # the identity of the delivery: recomputed from head, as the node does (DEV:391-394)
  asha="$(git -C "$proj" -c tar.umask=0002 archive --format=tar "$M_HEAD" 2>/dev/null | pr_sha256)"
  if [ -n "$M_ASHA" ] && [ "$M_ASHA" = "$asha" ]; then ok manifest.archive "archive_sha256 совпадает с пересчётом от head"   # PKG-C-ARCHIVE
  else fail manifest.archive "archive_sha256 манифеста ('${M_ASHA:-—}') не совпадает с пересчётом от head ('${asha:-—}')"; fi
  # the declared list of touched files against the real diff merge-base(head, base)..head; touches_shared against shared_paths
  mb="$(git -C "$proj" merge-base "$M_HEAD" "$PR_BASE_SHA" 2>/dev/null)"
  if [ -z "$mb" ]; then fail manifest.scope "у head и $PR_BASE_NAME нет общего предка"
  elif ! pr_files "$proj" "$mb" "$M_HEAD"; then fail manifest.scope "$PR_ERR"
  else
    if [ "$(printf '%s\n' "$M_SCOPE" | LC_ALL=C sort -u | grep .)" = "$(printf '%s\n' "$PR_FILES" | LC_ALL=C sort -u | grep .)" ]; then
      ok manifest.scope "scope_touched совпадает с диффом base..head"
    else
      fail manifest.scope "scope_touched манифеста не совпадает с фактическим диффом base..head (в манифесте $(printf '%s\n' "$M_SCOPE" | grep -c .), в диффе $(printf '%s\n' "$PR_FILES" | grep -c .))"
    fi
    pr_scope_eval
    if [ -n "$PR_SHARED" ] && [ "$M_SHARED" != true ]; then   # PKG-C-SHARED
      _flist "$PR_SHARED"; fail manifest.shared "пакет правит shared_paths ($FLIST), а touches_shared в манифесте не true"
    elif [ -z "$PR_SHARED" ] && [ "$M_SHARED" = true ]; then note manifest.shared "touches_shared: true, хотя shared_paths пакет не задевает"
    else ok manifest.shared "touches_shared согласован с shared_paths"; fi
    if [ "$PR_DOCS_MODE" = none ]; then
      note manifest.adr "docs_in_repo: none — adr не требуется"
    else
      bad=""
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        case $'\n'"$PR_FILES"$'\n' in *$'\n'"${f%%#*}"$'\n'*) ;; *) bad="$bad ${f%%#*}" ;; esac
      done <<< "$M_ADR"
      if [ -z "$M_ADR" ]; then warn manifest.adr "adr пуст при docs_in_repo: final — запись в реестр решений обязательна (REQ-PKG-26)"
      elif [ -n "$bad" ]; then warn manifest.adr "файл реестра из adr не изменён в пакете:$bad"
      else ok manifest.adr "adr указывает на изменённый в пакете реестр"; fi
    fi
  fi
  if pr_has_secret "$man_text"; then fail manifest.secret "в тексте CHANGE.yaml есть то, что похоже на секрет"; else ok manifest.secret "секретов в манифесте не найдено"; fi
  # the package itself: base..tip without the manifest
  mb2="$(git -C "$proj" merge-base "$tip" "$PR_BASE_SHA" 2>/dev/null)"
  if [ -z "$mb2" ] || ! pr_files "$proj" "$mb2" "$tip"; then fail pkg.nonempty "${PR_ERR:-у пакета и $PR_BASE_NAME нет общего предка}"; return 0; fi
  PR_FILES="$(printf '%s\n' "$PR_FILES" | grep -vx 'CHANGE.yaml')"
  if [ -n "$PR_FILES" ]; then ok pkg.nonempty "файлов в пакете: $(printf '%s\n' "$PR_FILES" | grep -c .)"; else fail pkg.nonempty "пакет без изменений кода"; fi
  pr_scope_eval
  if [ -n "$PR_SESSF" ]; then _flist "$PR_SESSF"; fail pkg.session "в пакете каталог сессии: $FLIST"; else ok pkg.session "каталога сессии в пакете нет"; fi
  if [ -n "$PR_OUT" ]; then _flist "$PR_OUT"; fail pkg.scope "в пакете файлы вне области мандата: $FLIST"; else ok pkg.scope "все файлы пакета в области мандата"; fi
}

case "$phase" in
  pre) phase_pre; pre_diff; pre_tests ;;
  post) phase_post ;;
  all) phase_pre; pre_diff; pre_tests; if [ "$nfail" -eq 0 ]; then phase_post; fi ;;
esac
finish
