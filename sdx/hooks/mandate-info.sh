#!/usr/bin/env bash
# SDX mandate-info (FEAT-016, REQ-MAND-3, 5, 23, 23a, 26): CLI the /sdx:* commands call via Bash.
# Read-only everywhere (closeout-check only inspects git state). The mandate (.mesh/mandate.yaml) is the
# node's DATA: every value that reaches stdout is quoted/sanitised by lib/mandate.sh (display) or reduced
# to a safe alphabet (closeout-mode). No python is run here except the `import yaml` PRESENCE probe of `status`.
#
#   bash mandate-info.sh mode [proj]                  on | orphan | none
#   bash mandate-info.sh show [proj]                  mandate report (on) | one warning line (orphan) | nothing
#   bash mandate-info.sh status [proj]                one "МО: ..." line for /sdx:status
#   bash mandate-info.sh closeout-mode [proj]         standard | bridge | bridge:offer | undefined:<delivery> | error:<reason>
#   bash mandate-info.sh closeout-check <sid> [proj]  OK/FAIL lines; rc 0 | 1
# proj defaults to ${CLAUDE_PROJECT_DIR:-.}. rc 0 everywhere except closeout-check (0/1) and usage errors (2).
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -f "$here/lib/mandate.sh" ]; then
  echo "SDX mandate-info: lib/mandate.sh плагина не найдена." >&2
  exit 2
fi
. "$here/lib/mandate.sh"

usage() {
  echo "SDX mandate-info: использование: mandate-info.sh <mode|show|status|closeout-mode|closeout-check> [args]" >&2
  exit 2
}

# safe <str> <max>: reduce a value to [A-Za-z0-9._-] (anything else -> '?'), at most <max> chars
safe() { printf '%s' "$1" | LC_ALL=C sed 's/[^A-Za-z0-9._-]/?/g' | cut -c1-"$2"; }

sub="${1:-}"
[ -n "$sub" ] || usage
shift

case "$sub" in
  mode)
    proj="${1:-${CLAUDE_PROJECT_DIR:-.}}"
    mandate_mode "$proj"
    ;;

  show)
    proj="${1:-${CLAUDE_PROJECT_DIR:-.}}"
    case "$(mandate_mode "$proj")" in
      on) mandate_report "$proj" "SDX mandate:" ;;
      orphan) mandate_orphan_line "SDX mandate:" ;;
    esac
    ;;

  status)
    proj="${1:-${CLAUDE_PROJECT_DIR:-.}}"
    ep=нет; mn=нет; e_ow="—"; m_ow="—"; wr="—"; vu="—"; dg="—"
    [ -f "$proj/.mesh/endpoint.yaml" ] && { ep=есть; e_ow="$(mandate_raw_on_write "$proj/.mesh/endpoint.yaml")"; }
    [ -f "$proj/.mesh/mandate.yaml" ] && { mn=есть; m_ow="$(mandate_raw_on_write "$proj/.mesh/mandate.yaml")"; }
    case "$(mandate_mode "$proj")" in
      on) rejim="включён" ;;
      orphan) rejim="«мандат без endpoint не действует»" ;;
      *) rejim="выключен" ;;
    esac
    if [ "$ep" = есть ]; then
      if [ "$e_ow" = deny ] || [ "$m_ow" = deny ]; then wr=deny; else wr=notice; fi
    fi
    jq_s=нет; py_s=нет; yaml_s=нет
    command -v jq >/dev/null 2>&1 && jq_s=есть
    if command -v python3 >/dev/null 2>&1; then
      py_s=есть
      PYTHONDONTWRITEBYTECODE=1 python3 -c 'import yaml' >/dev/null 2>&1 && yaml_s=есть
    fi
    if [ "$mn" = есть ]; then
      if mandate_load "$proj"; then
        _my_scalar mandate.valid_until && { _my_q "$MY_S"; vu="$MY_QV"; }
        _my_scalar mandate.digest && { _my_q "$MY_S"; dg="$MY_QV"; }
      else
        vu="не_разобран"; dg="не_разобран"
      fi
    fi
    printf '%s\n' "МО: endpoint.yaml=$ep; mandate.yaml=$mn; режим мандата=$rejim; on_write: endpoint=$e_ow mandate=$m_ow (обёртка берёт $wr); jq=$jq_s python3=$py_s PyYAML=$yaml_s; valid_until=$vu digest=$dg"
    ;;

  closeout-mode)
    proj="${1:-${CLAUDE_PROJECT_DIR:-.}}"
    if [ "$(mandate_mode "$proj")" != on ]; then echo standard; exit 0; fi
    if ! mandate_load "$proj"; then
      reason="${MANDATE_ERR//[[:cntrl:]]/}"
      echo "error:${reason:0:160}"
      exit 0
    fi
    _my_scalar mandate.delivery
    case "$MY_S" in
      artifact.offer) echo bridge:offer ;;   # MAND-BRIDGE
      pr|branch) echo bridge ;;
      "") echo "undefined:unset" ;;
      *) echo "undefined:$(safe "$MY_S" 40)" ;;
    esac
    ;;

  closeout-check)
    sid="${1:-}"
    case "$sid" in ""|*[!A-Za-z0-9._-]*) usage ;; esac
    proj="${2:-${CLAUDE_PROJECT_DIR:-.}}"
    bad=0
    ok() { printf 'OK %s\n' "$1"; }
    no() { printf 'FAIL %s\n' "$1"; bad=1; }
    if ! git -C "$proj" rev-parse --git-dir >/dev/null 2>&1; then
      no "$proj не git-репозиторий"
      exit 1
    fi
    cur="$(git -C "$proj" rev-parse --abbrev-ref HEAD 2>/dev/null)"
    if [ "$cur" = "sdx/$sid" ]; then ok "текущая ветка sdx/$sid"; else no "текущая ветка '$cur', ожидается sdx/$sid"; fi
    dirty="$(git -C "$proj" status --porcelain -- . ':!.mesh' 2>/dev/null)"
    if [ -z "$dirty" ]; then ok "рабочее дерево чистое"; else no "рабочее дерево не чистое (изменённых путей: $(printf '%s\n' "$dirty" | grep -c .))"; fi   # MAND-CHECK-TREE
    insess="$(git -C "$proj" ls-tree -r --name-only HEAD -- ".claude/sessions/$sid/" 2>/dev/null)"
    if [ -z "$insess" ]; then ok "каталог сессии .claude/sessions/$sid/ отсутствует в HEAD"; else no "каталог сессии .claude/sessions/$sid/ ещё в HEAD (путей: $(printf '%s\n' "$insess" | grep -c .))"; fi   # MAND-CHECK-SESSION
    exit "$bad"
    ;;

  *) usage ;;
esac
exit 0
