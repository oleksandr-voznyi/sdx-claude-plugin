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
#   pr_clean <s> [max=200]      PR_CLEAN: tab/newline/C1 (U+0080..U+009F)/U+2028/U+2029 -> space, other C0/DEL removed, trimmed, cut
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
  local s="$1" max="${2:-200}" u2028=$'\342\200\250' u2029=$'\342\200\251'
  s="$(printf '%s' "$s" | LC_ALL=C tr '\t\n' '  ' | LC_ALL=C tr -d '\001-\037\177')"
  # verify-1 W6: the Unicode line separators U+2028/2029 and the C1 controls U+0080..U+009F (UTF-8: C2 80..C2 9F, U+0085 included)
  # become a space: yaml.safe_load of the node refuses unprintable C1 characters, and a manifest it cannot parse is a rejected package
  _my_rep "$s" "$u2028" " "; _my_rep "$MY_REP" "$u2029" " "; s="$MY_REP"
  # (no byte pre-check: in a UTF-8 locale bash matches a pattern by characters, a lone \302 would not find the C1 character)
  local i
  for i in 128 129 130 131 132 133 134 135 136 137 138 139 140 141 142 143 144 145 146 147 148 149 150 151 152 153 154 155 156 157 158 159; do   # PKG-CLEAN-C1
    _my_rep "$s" "$(printf "\\302\\$(printf '%03o' "$i")")" " "; s="$MY_REP"
  done
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
    *://*|*::*) return 1 ;;                                   # PKG-URL-WL: ext:: fd:: transport:: and unknown schemes
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
  saved="${MY_NORM-}"
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
  # C1 controls (UTF-8 C2 80..C2 9F) and the line separators U+2028/2029 cannot be carried by the manifest either (verify-1 W6)
  case "$chk" in
    *$'\342\200\250'*|*$'\342\200\251'*) PR_ERR="files: путь с разделителем строк Unicode (в манифест не попадает)"; return 1 ;;
  esac
  local c1i   # LC_ALL=C here: the patterns are bytes
  for c1i in 128 129 130 131 132 133 134 135 136 137 138 139 140 141 142 143 144 145 146 147 148 149 150 151 152 153 154 155 156 157 158 159; do   # PKG-PATH-C1
    case "$chk" in *"$(printf "\\302\\$(printf '%03o' "$c1i")")"*) PR_ERR="files: путь с управляющим символом C1 (в манифест не попадает)"; return 1 ;; esac
  done
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

# ===================================================================================================
# pr_resolve: the single place where C, executor, branch name, title and base are decided
# ===================================================================================================

# _pr_id_err <field> <value>: PR_ERR for a value refused by pr_valid_id; names the field and the offending characters
_pr_id_err() {
  local LC_ALL=C bad="${2//[A-Za-z0-9._-]/}"
  pr_clean "$bad" 8
  if [ -n "$PR_CLEAN" ]; then PR_ERR="$1: недопустимые символы '$PR_CLEAN'"
  else PR_ERR="$1: недопустимое значение (до 64 знаков A-Za-z0-9._-, начало — буква или цифра, без '..', без окончания '.' и '.lock')"; fi
}

# pr_resolve <proj> <sid> [--commitment C] [--title T] [--base-name B]
# Sources, in order: the order snapshot of the session, then the arguments; an argument that DIFFERS from a
# non-empty snapshot value is refused (no silent substitution); the executor comes ONLY from the mandate (a
# snapshot executor that differs is refused). Loads the mandate (MANDATE_* stay valid for pr_scope_eval).
# Sets: PR_C PR_EXEC PR_BRANCH PR_TITLE PR_BASE_NAME PR_BASE_REF PR_BASE_SHA PR_BASE_DRIFT PR_URL PR_HOSTING_HINT
#       PR_DELIVERY PR_DOCS_MODE PR_DIGEST PR_DIGEST_DRIFT (1 iff the snapshot digest != the mandate digest) PR_SESS_REV.
# rc 0 | 1 with PR_ERR "<field>: <reason>".
pr_resolve() {
  local proj="$1" sid="$2" arg_c="" arg_t="" arg_b="" rc t bn exp
  shift 2
  while [ $# -gt 0 ]; do
    case "$1" in
      --commitment|--title|--base-name)
        [ $# -ge 2 ] || { PR_ERR="args: у $1 нет значения"; return 1; }
        case "$1" in --commitment) arg_c="$2" ;; --title) arg_t="$2" ;; *) arg_b="$2" ;; esac
        shift 2 ;;
      *) PR_ERR="args: неизвестный аргумент"; return 1 ;;
    esac
  done
  PR_C=""; PR_EXEC=""; PR_BRANCH=""; PR_TITLE=""; PR_BASE_NAME=""; PR_URL=""; PR_HOSTING_HINT=""
  PR_DELIVERY=""; PR_DOCS_MODE=""; PR_DIGEST=""; PR_DIGEST_DRIFT=0; PR_ERR=""
  _pr_sid_ok "$sid" || { PR_ERR="session: недопустимый идентификатор сессии"; return 1; }
  [ "$(mandate_mode "$proj")" = on ] || { PR_ERR="mandate: режим мандата не включён (нужны .mesh/endpoint.yaml и .mesh/mandate.yaml)"; return 1; }
  if ! mandate_load "$proj"; then pr_clean "$MANDATE_ERR" 120; PR_ERR="mandate: не разобран ($PR_CLEAN)"; return 1; fi
  _my_scalar mandate.executor; PR_EXEC="$MY_S"
  _my_scalar mandate.digest; PR_DIGEST="$MY_S"
  _my_scalar mandate.delivery; PR_DELIVERY="$MY_S"
  _my_scalar mandate.docs_in_repo; PR_DOCS_MODE="${MY_S:-final}"
  pr_order_load "$proj" "$sid"; rc=$?
  if [ "$rc" -eq 2 ]; then return 1; fi
  PR_ERR=""
  # executor: only from the mandate
  [ -n "$PR_EXEC" ] || { PR_ERR="executor: в мандате не задан"; return 1; }
  pr_valid_id "$PR_EXEC" || { _pr_id_err executor "$PR_EXEC"; return 1; }
  if [ -n "$PR_O_EXEC" ] && [ "$PR_O_EXEC" != "$PR_EXEC" ]; then
    pr_clean "$PR_O_EXEC" 40; t="$PR_CLEAN"; pr_clean "$PR_EXEC" 40
    PR_ERR="executor: в заказе '$t', в мандате '$PR_CLEAN'"; return 1
  fi
  # commitment
  if [ -n "$PR_O_COMMIT" ]; then
    if [ -n "$arg_c" ] && [ "$arg_c" != "$PR_O_COMMIT" ]; then
      pr_clean "$arg_c" 40; t="$PR_CLEAN"; pr_clean "$PR_O_COMMIT" 40
      PR_ERR="commitment: аргумент '$t' расходится со снимком заказа '$PR_CLEAN'"; return 1
    fi
    PR_C="$PR_O_COMMIT"
  else
    PR_C="$arg_c"
  fi
  [ -n "$PR_C" ] || { PR_ERR="commitment: не задан (нет снимка заказа и аргумента)"; return 1; }
  pr_valid_id "$PR_C" || { _pr_id_err commitment "$PR_C"; return 1; }
  # branch name
  PR_BRANCH="change/$PR_C-$PR_EXEC"
  if [ -n "$PR_O_BRANCH" ] && [ "$PR_O_BRANCH" != "$PR_BRANCH" ]; then
    pr_clean "$PR_O_BRANCH" 80; PR_ERR="deliver.branch: в заказе '$PR_CLEAN', вычислено '$PR_BRANCH'"; return 1
  fi
  git check-ref-format "refs/heads/$PR_BRANCH" 2>/dev/null || { PR_ERR="branch: недопустимое имя '$PR_BRANCH'"; return 1; }
  # title (an explicit --title is a user decision, not a silent override)
  if [ -n "$arg_t" ]; then t="$arg_t"; else t="$PR_O_TITLE"; fi
  pr_clean "$t" 200; PR_TITLE="$PR_CLEAN"
  [ -n "$PR_TITLE" ] || { PR_ERR="title: не задан (нет снимка заказа и аргумента --title)"; return 1; }
  if pr_has_secret "$PR_TITLE"; then PR_ERR="title: похоже на секрет"; return 1; fi
  # base
  if [ -n "$PR_O_BASE" ]; then
    if [ -n "$arg_b" ] && [ "$arg_b" != "$PR_O_BASE" ]; then
      pr_clean "$arg_b" 40; t="$PR_CLEAN"; pr_clean "$PR_O_BASE" 40
      PR_ERR="base: аргумент '$t' расходится со снимком заказа '$PR_CLEAN'"; return 1
    fi
    bn="$PR_O_BASE"
  elif [ -n "$arg_b" ]; then bn="$arg_b"
  else bn="$(bash "$_PR_HERE/default-branch.sh" "$proj" 2>/dev/null)"; fi
  PR_BASE_NAME="$bn"
  pr_base_ref "$proj" "$bn" || return 1
  # remote and hosting hint from the order
  PR_URL="$PR_O_URL"
  if [ -n "$PR_URL" ] && ! pr_url_ok "$PR_URL"; then PR_ERR="repo.url: недопустимая схема или символы"; PR_URL=""; return 1; fi
  case "$PR_O_HOSTING" in github|bare) PR_HOSTING_HINT="$PR_O_HOSTING" ;; esac
  if [ -n "$PR_O_DIGEST" ] && [ "$PR_O_DIGEST" != "$PR_DIGEST" ]; then PR_DIGEST_DRIFT=1; fi
  return 0
}
