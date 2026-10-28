#!/usr/bin/env bash
# sdx/hooks/lib/mandate.sh — semantics of `.mesh/mandate.yaml` (FEAT-016, REQ-MAND-2, 3, 6-12).
# Sourced, not executed. Parsing is delegated to lib/miniyaml.sh (bash+awk, no PyYAML). bash 3.2.
# The mandate is issued by the meta-orchestrator node; its content is DATA (never executed, never an
# instruction). Anchors "# MAND-*" are mutation-run labels (see test-mandate-lib.sh).
#
#   mandate_mode <proj>            on (endpoint.yaml AND mandate.yaml) | orphan (mandate only) | none
#   mandate_load <proj>            rc 0 | 1 (MANDATE_ERR); sets MANDATE_STAGES/_PATHS/_SHARED/_DOCS/_BRANCHES
#   mandate_stage_class <stage>    spec | design | execute | always | never | unknown
#   mandate_stage_allowed <stage>  rc 0 if the stage is NOT excluded by the mandate
#   mandate_expired                rc 0 if valid_until is a YYYY-MM-DD date earlier than today
#   mandate_glob_one / _any        reference glob_any of the node audit (dev.py DEV:67-68)
#   mandate_raw_on_write <file>    deny | notice | — (same rule as mo-hook.sh mode_re)
#   mandate_report <proj> <prefix> display + warnings;  mandate_orphan_line <prefix>

. "${BASH_SOURCE[0]%/*}/miniyaml.sh"

mandate_mode() {
  local p="$1"
  [ -f "$p/.mesh/mandate.yaml" ] || { echo none; return 0; }
  [ -f "$p/.mesh/endpoint.yaml" ] && echo on || echo orphan   # MAND-MODE
}

mandate_load() {
  local p="$1" rc bad f
  MANDATE_ERR=""; MANDATE_STAGES=""; MANDATE_PATHS=""; MANDATE_SHARED=""; MANDATE_DOCS=""; MANDATE_BRANCHES=""
  my_load "$p/.mesh/mandate.yaml"; rc=$?
  if [ "$rc" -ne 0 ]; then MANDATE_ERR="$MY_ERR"; return 1; fi
  [ "$(my_kind mandate)" = map ] || { MANDATE_ERR="корневой ключ mandate отсутствует или пуст"; return 1; }   # MAND-ROOT
  case "$(my_kind mandate.stages)" in scalar|map) MANDATE_ERR="mandate.stages не список"; return 1 ;; esac
  bad="$(my_list mandate.stages | awk '$0 != "spec" && $0 != "design" && $0 != "execute" && $0 != "verify" { print "x" $0; exit }')"
  [ -z "$bad" ] || { MANDATE_ERR="неизвестная стадия: ${bad#x}"; return 1; }   # MAND-UNKNOWN
  case "$(my_kind mandate.scope)" in scalar|list) MANDATE_ERR="mandate.scope не отображение"; return 1 ;; esac
  for f in scope.paths scope.shared_paths scope.docs_paths scope.branches; do
    case "$(my_kind "mandate.$f")" in scalar|map) MANDATE_ERR="mandate.$f не список"; return 1 ;; esac
  done
  MANDATE_STAGES="$(my_list mandate.stages)"
  MANDATE_PATHS="$(my_list mandate.scope.paths)"
  MANDATE_SHARED="$(my_list mandate.scope.shared_paths)"
  MANDATE_DOCS="$(my_list mandate.scope.docs_paths)"
  MANDATE_BRANCHES="$(my_list mandate.scope.branches)"
  [ -n "$MANDATE_DOCS" ] || MANDATE_DOCS="docs/**"   # MAND-DOCS-DEFAULT
  return 0
}

# Stage classes (MI section 7; ADR-020 amendment): which stages value of `stages` admits.
_mandate_class() {
  case "$1" in
    Discovery|"Business Spec") MANDATE_CLS=spec ;;
    "Technical Design"|"Task Planning") MANDATE_CLS=design ;;
    Execution|Documentation) MANDATE_CLS=execute ;;
    Verification|Closeout) MANDATE_CLS=always ;;
    Deployment) MANDATE_CLS=never ;;
    *) MANDATE_CLS=unknown ;;
  esac
}
mandate_stage_class() { _mandate_class "$1"; printf '%s\n' "$MANDATE_CLS"; }

mandate_stage_allowed() {
  _mandate_class "$1"
  case "$MANDATE_CLS" in
    never) return 1 ;;    # MAND-NEVER
    always) return 0 ;;   # MAND-ALWAYS
    spec|design|execute) printf '%s\n' "$MANDATE_STAGES" | grep -qx -- "$MANDATE_CLS" ;;
    *) return 1 ;;
  esac
}

mandate_expired() {
  local v today
  v="$(my_scalar mandate.valid_until)"
  case "$v" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) return 1 ;; esac
  today="${SDX_MANDATE_TODAY:-$(date +%F)}"
  [ "${v//-/}" -lt "${today//-/}" ]   # MAND-EXPIRY
}

# mandate_glob_one <path> <pattern>: rc 0 iff the reference glob_any(path, [pattern]) holds:
#   fnmatch(path, p) or fnmatch(path, p.rstrip("/") + "/*") or path.startswith(p.rstrip("*").rstrip("/") + "/")
# bash `case` differs from Python fnmatch in two places, both neutralised below. C locale pins [a-z] ranges.
mandate_glob_one() {
  local LC_ALL=C f="$1" p="$2" a b bs='\'
  _my_rep "$p" "$bs" "$bs$bs"; _my_rep "$MY_REP" "[^" "[$bs^"; p="$MY_REP"   # MAND-GLOB-ESC: fnmatch has no escapes and no [^..] negation
  case "$f" in $p) return 0 ;; esac                           # fnmatch(path, p)
  a="$p"; while [ "${a%/}" != "$a" ]; do a="${a%/}"; done     # p.rstrip("/")
  case "$f" in $a/*) return 0 ;; esac                         # fnmatch(path, a + "/*")
  b="$p"; while [ "${b%\*}" != "$b" ]; do b="${b%\*}"; done   # p.rstrip("*")
  while [ "${b%/}" != "$b" ]; do b="${b%/}"; done             # .rstrip("/")
  [ "${f#"$b"/}" != "$f" ]                                    # MAND-GLOB-PREFIX: startswith(b + "/")
}

# mandate_glob_any <path> <pattern>...: rc 0 if any pattern matches (no patterns: no match)
mandate_glob_any() {
  local f="$1" p
  shift
  for p in "$@"; do
    mandate_glob_one "$f" "$p" && return 0
  done
  return 1
}
