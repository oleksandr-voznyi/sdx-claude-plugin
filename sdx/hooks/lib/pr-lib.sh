#!/usr/bin/env bash
# sdx/hooks/lib/pr-lib.sh — shared library of the change-package pipeline (FEAT-017, /sdx:pr).
# Sourced, not executed. bash 3.2 (BUG-010): only constructs of the oldest supported bash and POSIX userland —
# no associative arrays, no array builtins at all (lists are newline-separated strings), no case-conversion
# expansions, no GNU-only sed/cp/stat flags; LC_ALL=C for awk/glob.
# No interpreters other than bash/awk/sed/jq/git in this file. Everything read from an order, a mandate, a
# session log or a git path is DATA: it is validated, cleaned (pr_clean) or quoted before it is shown, and is
# never executed. Anchors "# PKG-*" are mutation-run labels (see test-mandate-lib.sh).
#
# FROZEN after the foundation track of FEAT-017: pr-build.sh, pr-check.sh, pr-publish.sh, order-import.sh,
# protocol-export.sh and mandate-info.sh only CALL these functions. Convention: a function returns a string in a
# documented PR_* variable (no subshell per call) and signals failure with rc 1 + PR_ERR "<field>: <reason>".
#
#   --- pure ---
#   pr_valid_id <s>             rc 0 iff ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$, no "..", not ending in "." or ".lock"
#   pr_clean <s> [max=200]      PR_CLEAN: tab/newline -> space, other C0/DEL/U+2028/U+2029/U+0085 removed, trimmed, cut
#   pr_has_secret <s>           rc 0 iff the text looks like "<secret-word> [:=]" (mirror of REDACT[0], mesh_endpoint.py)
#   pr_sha256                   stdin -> hex digest on stdout (sha256sum | shasum -a 256; neither -> rc 2)
#   pr_url_ok <url>             rc 0 iff the URL is on the whitelist of schemes (ssh/https/http/file, scp form, absolute path)
#   pr_url_show <url>           PR_URLS: the URL without credentials (for output and trailers)
#   pr_hosting <url> [hint]     PR_HOSTING: github | bare (a valid hint of the order wins)
#   --- git / session history (arguments: project dir, session id) ---
#   pr_session_rev <proj> <sid> PR_SESS_REV: the commit where .claude/sessions/<sid>/ still exists
#   pr_sess_cat <proj> <sid> <name>   file of the session at PR_SESS_REV on stdout
#   pr_order_load <proj> <sid>  PR_O_* from the order snapshot (empty without a snapshot)
#   pr_base_ref <proj> <name>   PR_BASE_REF / PR_BASE_SHA / PR_BASE_DRIFT
#   pr_files <proj> <a> <b>     PR_FILES: changed paths of a..b (-z); a control character in a path -> rc 1
#   pr_scope_eval               PR_OUT / PR_SHARED / PR_DOCSF / PR_SESSF / PR_DOCS_OUTSIDE from $PR_FILES + the loaded mandate
#   pr_registry <proj> <base> <head>  PR_REG_PATH / PR_REG_STATE (one|none|ambiguous) / PR_REG_ANCHORS
#   pr_resolve <proj> <sid> [--commitment C] [--title T] [--base-name B]   PR_C PR_EXEC PR_BRANCH PR_TITLE PR_BASE_* ...

_PR_HERE="${BASH_SOURCE[0]%/*}"
. "$_PR_HERE/miniyaml.sh"
. "$_PR_HERE/mandate.sh"
. "$_PR_HERE/test-cmd.sh"

# pr_valid_id <s>
pr_valid_id() {
  local LC_ALL=C s="$1"
  [ -n "$s" ] && [ "${#s}" -le 64 ] || return 1
  case "$s" in *[!A-Za-z0-9._-]*) return 1 ;; esac        # PKG-ID: closed alphabet (no ':' '/' space newline unicode)
  case "$s" in [A-Za-z0-9]*) ;; *) return 1 ;; esac
  case "$s" in *..*|*.|*.lock) return 1 ;; esac           # PKG-ID: no '..', no trailing '.' / '.lock' (git ref rules)
  return 0
}

# pr_clean <s> [max=200] -> PR_CLEAN
pr_clean() {
  local s="$1" max="${2:-200}" u2028=$'\342\200\250' u2029=$'\342\200\251' u0085=$'\302\205'
  s="$(printf '%s' "$s" | LC_ALL=C tr '\t\n' '  ' | LC_ALL=C tr -d '\001-\037\177')"
  _my_rep "$s" "$u2028" ""; _my_rep "$MY_REP" "$u2029" ""; _my_rep "$MY_REP" "$u0085" ""; s="$MY_REP"
  while [ "${s# }" != "$s" ]; do s="${s# }"; done
  while [ "${s% }" != "$s" ]; do s="${s% }"; done
  if _my_trunc "$s" "$max"; then s="$MY_TRUNC"; fi
  while [ "${s% }" != "$s" ]; do s="${s% }"; done
  PR_CLEAN="$s"
}

# pr_has_secret <s>: the ERE mirrors REDACT[0] of the vendored mesh_endpoint.py (line 35)
pr_has_secret() {
  printf '%s\n' "$1" | LC_ALL=C grep -Eiq '(password|passwd|pwd|secret|token|api[_-]?key|client[_-]?secret)"?[[:space:]]*[:=]'   # PKG-SECRET
}

# pr_sha256: stdin -> hex digest
pr_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  else return 2; fi
}

# pr_url_ok <url>: whitelist. ssh:// https:// http:// file://, the scp form user@host:path, an absolute local path.
# Refused: ext:: fd:: transport:: (remote helpers run commands), a leading '-' (option injection), a host that starts
# with '-', whitespace/control characters, anything else (ftp://, relative paths).
pr_url_ok() {
  local LC_ALL=C u="$1" rest auth host user
  [ -n "$u" ] || return 1
  case "$u" in -*) return 1 ;; esac
  case "$u" in *[[:space:]]*|*[[:cntrl:]]*) return 1 ;; esac
  case "$u" in
    ssh://*|https://*|http://*|file://*)                      # PKG-URL-WL
      rest="${u#*://}"; [ -n "$rest" ] || return 1
      auth="${rest%%/*}"; host="${auth##*@}"
      case "$host" in -*) return 1 ;; esac
      return 0 ;;
    /*) return 0 ;;
    *://*|*::*) return 1 ;;
    *@*:*)
      user="${u%%@*}"; host="${u#*@}"; host="${host%%:*}"
      [ -n "$user" ] && [ -n "$host" ] && [ -n "${u#*:}" ] || return 1
      case "$user" in *[!A-Za-z0-9._-]*) return 1 ;; esac
      case "$host" in *[!A-Za-z0-9._-]*|-*) return 1 ;; esac
      return 0 ;;
  esac
  return 1
}

# pr_url_show <url> -> PR_URLS: credentials removed. http(s): the whole userinfo (a token may stand alone);
# ssh://: only "user:pass@" (a bare user is not a secret). The scp form and local paths carry none.
pr_url_show() {
  local u="$1" scheme rest auth tail info
  PR_URLS="$u"
  case "$u" in
    http://*|https://*|ssh://*)
      scheme="${u%%://*}"; rest="${u#*://}"; auth="${rest%%/*}"; tail="${rest#"$auth"}"
      case "$auth" in
        *@*)
          info="${auth%@*}"
          if [ "$scheme" != ssh ] || [ "${info#*:}" != "$info" ]; then
            PR_URLS="$scheme://${auth##*@}$tail"
          fi ;;
      esac ;;
  esac
  return 0
}

# pr_hosting <url> [hint] -> PR_HOSTING (github | bare). A valid hint from the order wins; otherwise the host
# github.com (any scheme or the scp form) means github; everything else, local paths included, is bare.
pr_hosting() {
  local u="$1" rest auth host
  case "${2:-}" in github|bare) PR_HOSTING="$2"; return 0 ;; esac
  PR_HOSTING=bare
  case "$u" in /*) return 0 ;; esac
  rest="$u"; case "$u" in *://*) rest="${u#*://}" ;; esac
  auth="${rest%%/*}"; auth="${auth##*@}"; host="${auth%%:*}"
  host="$(printf '%s' "$host" | LC_ALL=C tr 'A-Z' 'a-z')"
  [ "$host" = github.com ] && PR_HOSTING=github
  return 0
}

# ===================================================================================================
# Session history (D-5): after Closeout step 5 the session directory is gone from the working tree and from
# the tip of sdx/<sid>; its files are read from the last commit that still had it.
# ===================================================================================================

# _pr_sid_ok <sid>: closed alphabet, no leading '.', no '..' (a sid reaches git paths and ref names)
_pr_sid_ok() {
  case "$1" in ""|.*|*..*|*[!A-Za-z0-9._-]*) return 1 ;; esac
  return 0
}

# pr_session_rev <proj> <sid> -> PR_SESS_REV: tip of sdx/<sid> if the session directory is still there, else the
# parent of the commit that removed session_state.json. rc 1 (PR_ERR) when the directory never existed.
pr_session_rev() {
  local proj="$1" sid="$2" ref tip del path
  PR_SESS_REV=""; PR_ERR=""
  _pr_sid_ok "$sid" || { PR_ERR="session: недопустимый идентификатор сессии"; return 1; }
  ref="refs/heads/sdx/$sid"
  tip="$(git -C "$proj" rev-parse --verify -q "$ref^{commit}" 2>/dev/null)" || { PR_ERR="session: нет ветки sdx/$sid"; return 1; }
  path=".claude/sessions/$sid/session_state.json"
  if git -C "$proj" cat-file -e "$tip:$path" 2>/dev/null; then
    PR_SESS_REV="$tip"; return 0
  fi
  del="$(git -C "$proj" log -n1 --format=%H --diff-filter=D "$ref" -- "$path" 2>/dev/null)"   # PKG-SESSREV
  [ -n "$del" ] || { PR_ERR="session: каталог сессии не найден в истории sdx/$sid"; return 1; }
  PR_SESS_REV="$(git -C "$proj" rev-parse --verify -q "$del^" 2>/dev/null)" || { PR_SESS_REV=""; PR_ERR="session: у коммита удаления нет родителя"; return 1; }
  return 0
}

# pr_sess_cat <proj> <sid> <name>: a (flat-named) file of the session at PR_SESS_REV, on stdout. The revision is
# recomputed on every call (the branch moves between pipeline steps). rc 1 if the session or the file is absent.
pr_sess_cat() {
  local proj="$1" sid="$2" name="$3"
  case "$name" in ""|*/*|.*) PR_ERR="session: недопустимое имя файла"; return 1 ;; esac
  pr_session_rev "$proj" "$sid" || return 1
  git -C "$proj" cat-file -e "$PR_SESS_REV:.claude/sessions/$sid/$name" 2>/dev/null || { PR_ERR="session: файла $name нет в сессии"; return 1; }
  git -C "$proj" show "$PR_SESS_REV:.claude/sessions/$sid/$name" 2>/dev/null
}

# pr_order_load <proj> <sid>: the order snapshot (order.yaml in OUR format, written by order-import.sh) ->
# PR_O_COMMIT PR_O_TITLE PR_O_REQS PR_O_DUE PR_O_BASE PR_O_URL PR_O_HOSTING PR_O_BRANCH PR_O_DELIVERY PR_O_EXEC PR_O_DIGEST
# PR_O_REPO PR_O_SOURCE PR_O_SOURCE_REF. rc 0 loaded | 1 no snapshot (all empty) | 2 unreadable (PR_ERR).
# The caller's loaded document (MY_NORM, e.g. the mandate) is preserved.
pr_order_load() {
  local proj="$1" sid="$2" tmp saved rc
  PR_O_COMMIT=""; PR_O_TITLE=""; PR_O_REQS=""; PR_O_DUE=""; PR_O_BASE=""; PR_O_URL=""; PR_O_HOSTING=""
  PR_O_BRANCH=""; PR_O_DELIVERY=""; PR_O_EXEC=""; PR_O_DIGEST=""; PR_O_REPO=""; PR_O_SOURCE=""; PR_O_SOURCE_REF=""
  tmp="$(mktemp "${TMPDIR:-/tmp}/sdx-pr-order.XXXXXX")" || { PR_ERR="order: не удалось создать временный файл"; return 2; }
  if ! pr_sess_cat "$proj" "$sid" order.yaml > "$tmp" 2>/dev/null; then rm -f "$tmp"; PR_ERR=""; return 1; fi
  saved="$MY_NORM"
  my_load "$tmp"; rc=$?
  rm -f "$tmp"
  if [ "$rc" -ne 0 ]; then MY_NORM="$saved"; PR_ERR="order.yaml: $MY_ERR"; return 2; fi
  _my_scalar order.commitment.id; PR_O_COMMIT="$MY_S"
  _my_scalar order.commitment.title; PR_O_TITLE="$MY_S"
  _my_scalar order.commitment.requirements; PR_O_REQS="$MY_S"
  _my_scalar order.commitment.due; PR_O_DUE="$MY_S"
  _my_scalar order.repo.base; PR_O_BASE="$MY_S"
  _my_scalar order.repo.url; PR_O_URL="$MY_S"
  _my_scalar order.repo.hosting; PR_O_HOSTING="$MY_S"
  _my_scalar order.repo.id; PR_O_REPO="$MY_S"
  _my_scalar order.deliver.branch; PR_O_BRANCH="$MY_S"
  _my_scalar order.deliver.delivery; PR_O_DELIVERY="$MY_S"
  _my_scalar order.executor; PR_O_EXEC="$MY_S"
  _my_scalar order.mandate_digest; PR_O_DIGEST="$MY_S"
  _my_scalar order.source; PR_O_SOURCE="$MY_S"
  _my_scalar order.source_ref; PR_O_SOURCE_REF="$MY_S"
  MY_NORM="$saved"
  return 0
}

# ===================================================================================================
# Base branch, changed files, scope
# ===================================================================================================

# pr_base_ref <proj> <name> -> PR_BASE_REF, PR_BASE_SHA, PR_BASE_DRIFT (1 iff the local and the remote-tracking
# branch both exist and differ), PR_BASE_REMOTE_SHA. The local branch wins (the session is cut from it); origin is
# tried first among remotes. No fetch here: the network belongs to pr-publish only. rc 1 + PR_ERR "base: ...".
pr_base_ref() {
  local proj="$1" name="$2" lsha rsha="" rref="" r x
  PR_BASE_REF=""; PR_BASE_SHA=""; PR_BASE_DRIFT=0; PR_BASE_REMOTE_SHA=""; PR_ERR=""
  case "$name" in ""|-*) PR_ERR="base: недопустимое имя ветки"; return 1 ;; esac
  git check-ref-format "refs/heads/$name" 2>/dev/null || { PR_ERR="base: недопустимое имя ветки"; return 1; }
  lsha="$(git -C "$proj" rev-parse --verify -q "refs/heads/$name^{commit}" 2>/dev/null)"
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    if x="$(git -C "$proj" rev-parse --verify -q "refs/remotes/$r/$name^{commit}" 2>/dev/null)"; then rsha="$x"; rref="refs/remotes/$r/$name"; break; fi
  done <<< "$(printf 'origin\n'; git -C "$proj" remote 2>/dev/null | grep -vx origin)"
  if [ -n "$lsha" ]; then
    PR_BASE_REF="refs/heads/$name"; PR_BASE_SHA="$lsha"
    if [ -n "$rsha" ]; then PR_BASE_REMOTE_SHA="$rsha"; [ "$rsha" = "$lsha" ] || PR_BASE_DRIFT=1; fi
  elif [ -n "$rsha" ]; then
    PR_BASE_REF="$rref"; PR_BASE_SHA="$rsha"; PR_BASE_REMOTE_SHA="$rsha"
  else
    PR_ERR="base: ветка $name не найдена (ни локальной, ни remote-tracking)"; return 1
  fi
  return 0
}

# pr_files <proj> <a> <b> -> PR_FILES: paths changed between two revisions, one per line. Read with -z (no quoting of
# non-ASCII names); renames are not detected (both paths are listed, deterministic regardless of diff.renames).
# A control character in a path is refused: the manifest cannot carry it (rc 1, PR_ERR "files: ...").
pr_files() {
  local LC_ALL=C proj="$1" a="$2" b="$3" raw chk
  PR_FILES=""; PR_ERR=""
  git -C "$proj" rev-parse --verify -q "$a^{commit}" >/dev/null 2>&1 && git -C "$proj" rev-parse --verify -q "$b^{commit}" >/dev/null 2>&1 \
    || { PR_ERR="files: неизвестная ревизия"; return 1; }
  raw="$(git -C "$proj" -c core.quotepath=off diff --no-renames --name-only -z "$a" "$b" -- 2>/dev/null | tr '\0' '\001')"
  _my_rep "$raw" $'\001' ""; chk="$MY_REP"
  case "$chk" in *[[:cntrl:]]*) PR_ERR="files: путь с управляющим символом (в манифест не попадает)"; return 1 ;; esac   # PKG-PATH-CTRL
  _my_rep "$raw" $'\001' $'\n'; PR_FILES="${MY_REP%$'\n'}"
  return 0
}

# pr_scope_eval: input $PR_FILES + the last mandate_load; mirrors the scope part of audit() of the node (DEV:383-390):
#   PR_OUT          outside paths U shared_paths U docs_paths (only when scope.paths is non-empty: empty = no restriction)
#   PR_SHARED       matches shared_paths (the manifest must declare touches_shared)
#   PR_DOCSF        matches docs_paths (the "docs" list of the manifest)
#   PR_SESSF        under .claude/sessions/ (a leak of the session directory into the change)
#   PR_DOCS_OUTSIDE under docs/ but not covered by docs_paths (docs_in_repo: final, REQ-PKG-27)
pr_scope_eval() {
  local f
  PR_OUT=""; PR_SHARED=""; PR_DOCSF=""; PR_SESSF=""; PR_DOCS_OUTSIDE=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in .claude/sessions/*) PR_SESSF="$PR_SESSF${PR_SESSF:+$'\n'}$f" ;; esac
    if [ -n "$MANDATE_PATHS" ] && ! mandate_in_union "$f"; then PR_OUT="$PR_OUT${PR_OUT:+$'\n'}$f"; fi
    if [ -n "$MANDATE_SHARED" ] && mandate_match_list "$f" "$MANDATE_SHARED"; then PR_SHARED="$PR_SHARED${PR_SHARED:+$'\n'}$f"; fi
    if mandate_match_list "$f" "$MANDATE_DOCS"; then
      PR_DOCSF="$PR_DOCSF${PR_DOCSF:+$'\n'}$f"
    else
      case "$f" in docs/*) PR_DOCS_OUTSIDE="$PR_DOCS_OUTSIDE${PR_DOCS_OUTSIDE:+$'\n'}$f" ;; esac
    fi
  done <<< "$PR_FILES"
  return 0
}

# pr_registry <proj> <base> <head>: the decision registry touched by the change; reads $PR_FILES (changed paths).
#   PR_REG_STATE  one | none | ambiguous      PR_REG_PATH  the file (state one)      PR_REG_CAND  candidates (ambiguous)
#   PR_REG_ANCHORS  "<file>#<TOKEN>" per heading added by the diff, TOKEN = first [A-Z]+-[0-9]+ of the heading
# docs/DECISIONS.md has priority; otherwise exactly one changed docs/**/{DECISIONS,decisions}*.md (default of Q-7).
pr_registry() {
  local LC_ALL=C proj="$1" base="$2" head="$3" f b n=0 cand="" reg="" h tok a
  PR_REG_PATH=""; PR_REG_STATE=none; PR_REG_ANCHORS=""; PR_REG_CAND=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ "$f" = docs/DECISIONS.md ]; then reg="$f"; continue; fi
    case "$f" in
      docs/*) b="${f##*/}"
              case "$b" in DECISIONS*.md|decisions*.md) n=$((n + 1)); cand="$cand${cand:+$'\n'}$f" ;; esac ;;
    esac
  done <<< "$PR_FILES"
  if [ -n "$reg" ]; then PR_REG_STATE=one; PR_REG_PATH="$reg"
  elif [ "$n" -eq 1 ]; then PR_REG_STATE=one; PR_REG_PATH="$cand"
  elif [ "$n" -gt 1 ]; then PR_REG_STATE=ambiguous; PR_REG_CAND="$cand"; fi
  [ "$PR_REG_STATE" = one ] || return 0
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    tok="$(printf '%s\n' "$h" | grep -oE '[A-Z]+-[0-9]+' | head -n1)"
    [ -n "$tok" ] || continue
    a="$PR_REG_PATH#$tok"
    case $'\n'"$PR_REG_ANCHORS"$'\n' in *$'\n'"$a"$'\n'*) ;; *) PR_REG_ANCHORS="$PR_REG_ANCHORS${PR_REG_ANCHORS:+$'\n'}$a" ;; esac
  done <<< "$(git -C "$proj" diff -U0 --no-renames "$base" "$head" -- "$PR_REG_PATH" 2>/dev/null | grep '^+#')"
  return 0
}
