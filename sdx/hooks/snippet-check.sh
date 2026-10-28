#!/usr/bin/env bash
# SDX snippet-check (FEAT-016, REQ-MAND-25): compare the SDX:BEGIN..SDX:END block of a project's CLAUDE.md with the
# plugin's template block. Read-only: it never writes (replacing the block is the orchestrator's job, with consent).
#
#   bash snippet-check.sh <CLAUDE.md> [template]
#     template defaults to templates/claude-md-snippet.md beside this plugin's hooks/ directory
#     (path derived from BASH_SOURCE).
# stdout (one word), rc 0:
#   ABSENT  no markers at all (or the file does not exist)
#   BROKEN  an unpaired / reversed / repeated marker (more than one block, no END, no BEGIN)
#   OK      the block equals the template block up to CRLF and trailing whitespace
#   STALE   the block differs from the template block
# rc 2: usage error or an unusable template. Text outside the markers is ignored.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
file="${1:-}"
[ -n "$file" ] || { echo "SDX snippet-check: использование: snippet-check.sh <CLAUDE.md> [шаблон]" >&2; exit 2; }
tpl="${2:-$here/../templates/claude-md-snippet.md}"
[ -f "$tpl" ] || { echo "SDX snippet-check: шаблон не найден: $tpl" >&2; exit 2; }

# extract <file>: first line "ABSENT" | "BROKEN" | "BLOCK"; for BLOCK the normalised block text follows
extract() {
  LC_ALL=C awk '
    { sub(/\r$/, ""); sub(/[ \t]+$/, "") }
    /<!-- SDX:BEGIN/ { nb++; if (inb) broken = 1; inb = 1 }
    inb { blk = blk $0 "\n" }
    /<!-- SDX:END/ { ne++; if (!inb) broken = 1; inb = 0 }
    END {
      if (nb == 0 && ne == 0) { print "ABSENT"; exit }
      if (broken || inb || nb != 1 || ne != 1) { print "BROKEN"; exit }
      print "BLOCK"; printf "%s", blk
    }' "$1"
}

tblk="$(extract "$tpl")"
case "$tblk" in
  BLOCK*) ;;
  *) echo "SDX snippet-check: в шаблоне нет ровно одного блока SDX:BEGIN..SDX:END: $tpl" >&2; exit 2 ;;
esac
if [ ! -f "$file" ]; then echo ABSENT; exit 0; fi
blk="$(extract "$file")"
case "$blk" in
  ABSENT|BROKEN) echo "$blk"; exit 0 ;;
esac
if [ "$blk" = "$tblk" ]; then echo OK; else echo STALE; fi   # SC-CMP
exit 0
