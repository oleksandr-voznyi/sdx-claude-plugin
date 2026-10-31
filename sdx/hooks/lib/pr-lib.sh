#!/usr/bin/env bash
# sdx/hooks/lib/pr-lib.sh — shared library of the change-package pipeline (FEAT-017, /sdx:pr).
# Sourced, not executed. bash 3.2 (BUG-010): no associative arrays, no mapfile, no arrays at all (lists are
# newline-separated strings), no ${v,,}, no timeout/%N, no GNU-only sed/cp/stat flags; LC_ALL=C for awk/glob.
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
