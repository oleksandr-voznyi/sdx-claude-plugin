#!/usr/bin/env bash
# sdx/hooks/protocol-export.sh — protocol.yaml of a session built from its existing journals (FEAT-017, REQ-PKG-19..22).
# A CLI called by commands/pr.md through the Bash tool as `bash protocol-export.sh --sid <sid> ...`.
#
#   protocol-export.sh --sid <sid> [--proj DIR] [--out FILE|-] [--from-rev REV]
#
# bash 3.2 (BUG-010: no arrays, no bash-4 builtins), bash + awk + sed + jq + git only. The journals are DATA: awk extracts
# records into TSV, ONE jq call renders the YAML (every scalar through tojson, a JSON string is a YAML double-quoted
# scalar); nothing from a journal reaches a shell as code. set -e is deliberately not used.
set -uo pipefail

here="${BASH_SOURCE[0]%/*}"; [ "$here" != "${BASH_SOURCE[0]}" ] || here=.
command -v jq >/dev/null 2>&1 || { echo "protocol-export: jq не найден — экспорт невозможен (fail-closed)." >&2; exit 2; }
# shellcheck disable=SC1091
. "$here/lib/pr-lib.sh"

# ------------------------------------------------------------------------------------------------------------
# decisions_log.md -> TSV: kind \t tag \t stage \t title \t what \t why \t alts \t adr(0|1)
# Two formats are read (К-4): the NORMATIVE block of protocol.md ("### Развилка: [тег] название (этап: X)" followed by
# "- Вариант:" / "- Обоснование:" / "- Варианты:" lines, indented lines continue the field) and the ACTUAL one-line
# records of the journals ("- [YYYY-MM-DD ]<tag> text", tag from the closed set of eight, indented lines continue).
# Nothing is invented: for format B "what" is derived later (first sentence), "why" is the whole record. A record with
# neither what nor why is skipped with a note on stderr. Tabs, CR and line breaks inside values become spaces here.
# ------------------------------------------------------------------------------------------------------------
PX_DEC_AWK='
function clean(s) { gsub(/[\t\r]/, " ", s); return s }
function out(   a) {
  if (have) {
    if (what == "" && why == "") { printf "protocol-export: запись «%s» без полей «Вариант» и «Обоснование» пропущена\n", title > "/dev/stderr" }
    else {
      a = ((what " " why " " title " " alts) ~ /ADR-[0-9]+/) ? 1 : 0                    # PKG-X-ADR
      if (kind == "A") { if (what == "") what = title; if (why == "") why = what }
      print kind "\t" tag "\t" stage "\t" clean(title) "\t" clean(what) "\t" clean(why) "\t" clean(alts) "\t" a
    }
  }
  have = 0; what = why = alts = title = tag = stage = ""; cur = ""
}
function collect(v) { gsub(/^[ \t]+|[ \t]+$/, "", v); return v }
BEGIN { have = 0; kind = ""; cur = "" }
{ sub(/\r$/, "") }
/^### Развилка:/ {
  out(); have = 1; kind = "A"
  t = $0; sub(/^### Развилка:[ \t]*/, "", t)
  if (match(t, /^\[[^]]+\]/)) { tag = substr(t, 2, RLENGTH - 2); t = substr(t, RLENGTH + 1); sub(/^[ \t]+/, "", t) }
  if (match(t, /\(этап:[^)]*\)[ \t]*$/)) {
    stage = substr(t, RSTART, RLENGTH); sub(/^\(этап:[ \t]*/, "", stage); sub(/\)[ \t]*$/, "", stage)
    t = substr(t, 1, RSTART - 1)
  }
  title = collect(t); next
}
/^### / { out(); next }
/^- ([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] )?\[(триада|FAIL|контракт|деструктив|объём|ручной-шаг|триаж|директива)\]/ {   # PKG-X-FMTB
  out(); have = 1; kind = "B"
  t = $0; sub(/^- ([0-9]+-[0-9]+-[0-9]+ )?/, "", t)
  match(t, /^\[[^]]+\]/); tag = substr(t, 2, RLENGTH - 2)
  t = substr(t, RLENGTH + 1); sub(/^[ \t]+/, "", t)
  why = collect(t); what = ""; title = ""; cur = "b"; next
}
kind == "A" && have && /^- Вариант:/     { cur = "what"; v = $0; sub(/^- Вариант:[ \t]*/, "", v); what = collect(v); next }
kind == "A" && have && /^- Обоснование:/ { cur = "why";  v = $0; sub(/^- Обоснование:[ \t]*/, "", v); why = collect(v); next }
kind == "A" && have && /^- (Варианты|Альтернативы):/ { cur = "alts"; v = $0; sub(/^- [^:]+:[ \t]*/, "", v); alts = collect(v); next }
kind == "A" && have && /^- / { cur = ""; next }
kind == "A" && have && cur != "" && /^[ \t]+[^ \t]/ {
  v = collect($0)
  if (cur == "what") what = what " " v; else if (cur == "why") why = why " " v; else alts = alts " " v
  next
}
kind == "B" && have && cur == "b" && /^[ \t]+[^ \t]/ { why = why " " collect($0); next }
kind == "B" && have && cur == "b" && /^[^ \t]/ { out(); next }
END { out() }
'

px_decisions_tsv() { LC_ALL=C awk "$PX_DEC_AWK"; }

# ------------------------------------------------------------------------------------------------------------
# rendering: ONE jq call. Inputs are plain strings (--arg); the output is the YAML text.
# ------------------------------------------------------------------------------------------------------------
PX_JQ='
def cl: gsub("[\u0001-\u001f\u007f-\u009f  ￾￿]"; " ") | gsub("^ +"; "") | gsub(" +$"; "");
def q: tojson;
def lines($s): ($s | split("\n") | map(select(length > 0)));
def first_sentence: (index(". ")) as $i | if $i != null and $i < 200 then .[0:($i + 1)] elif length > 200 then .[0:200] else . end;
def lst($k; $a):
  if ($a | length) == 0 then "\($k): []"      # PKG-X-EMPTY
  else "\($k):\n" + ($a | map("  - " + q) | join("\n")) end;
(lines($dec) | map(split("\t"))
  | map({kind: .[0], tag: (.[1] | cl), stage: (.[2] | cl), title: (.[3] | cl), what: (.[4] | cl), why: (.[5] | cl), alts: (.[6] | cl), adr: (.[7] == "1")}
        | if .kind == "B" then .what = (.why | first_sentence) | .title = .what else . end)
  | to_entries | map(.value + {id: ("D-" + ((.key + 1) | tostring))})) as $d       # PKG-X-ID
| "# protocol.yaml — экспорт журналов сессии \($sid | cl)\($ver | if . == "" then "" else " (SDX " + . + ")" end). Источник правды — журналы сессии; файл производный.\n"
  + lst("done"; lines($done) | map(cl[0:120])) + "\n"
  + (if ($d | length) == 0 then "decisions: []" else "decisions:\n" + ($d | map(
      "  - id: \(.id | q)\n    what: \(.what | q)\n    why: \(.why | q)\n    alternatives: \(if .alts == "" then [] else [.alts] end | tojson)\n    adr: \(.adr)\n    tag: \(.tag | q)\n    stage: \(.stage | q)") | join("\n")) end) + "\n"
  + lst("questions"; $d | map(if .tag == "" then .title else "[" + .tag + "] " + .title end)) + "\n"
  + lst("verified"; lines($ver_l) | map(cl)) + "\n"
  + lst("deltas"; lines($dlt) | map(cl[0:80]))
  + "\n#COUNTS done \(lines($done) | length) decisions \($d | length) (adr \($d | map(select(.adr)) | length)) questions \($d | length) verified \(lines($ver_l) | length) deltas \(lines($dlt) | length)"
'

# px_cat <path relative to the project root>: the file on stdout (at most 1 MiB), rc 1 if absent or unreadable
px_cat() {
  [ -f "$PROJ/$1" ] && [ -r "$PROJ/$1" ] || return 1
  head -c 1048576 "$PROJ/$1"
}

# px_render: prints the YAML, then one line "#COUNTS ..." (split off by the caller)
px_render() {
  jq -rn --arg sid "$SID" --arg ver "$PX_VER" --arg dec "$DEC_TSV" --arg done "${DONE_L:-}" --arg ver_l "${VER_L:-}" --arg dlt "${DLT_L:-}" "$PX_JQ"
}

usage() {
  echo "использование: protocol-export.sh --sid <sid> [--proj DIR] [--out FILE|-] [--from-rev REV]" >&2
  exit 2
}

SID=""; PROJ="${CLAUDE_PROJECT_DIR:-.}"; OUTF=""; REV=""
while [ $# -gt 0 ]; do
  case "$1" in
    --sid|--proj|--out|--from-rev)
      [ $# -ge 2 ] || { echo "protocol-export: у $1 нет значения." >&2; exit 2; }
      case "$1" in --sid) SID="$2" ;; --proj) PROJ="$2" ;; --out) OUTF="$2" ;; *) REV="$2" ;; esac
      shift 2 ;;
    *) echo "protocol-export: неизвестный аргумент." >&2; usage ;;
  esac
done
[ -n "$SID" ] || usage
_pr_sid_ok "$SID" || { echo "protocol-export: sid: недопустимый идентификатор сессии." >&2; exit 2; }

SDIR=".claude/sessions/$SID"
PX_VER="$(jq -r '.version // empty' "$here/../../.claude-plugin/plugin.json" 2>/dev/null)"
case "$PX_VER" in *[!0-9A-Za-z.+-]*) PX_VER="" ;; esac

# ---- sources: an absent source is an empty list, not an error (REQ-PKG-21) ----
READ_ANY=0
DEC_TSV=""
if TXT="$(px_cat "$SDIR/decisions_log.md")"; then
  READ_ANY=1
  DEC_TSV="$(printf '%s\n' "$TXT" | px_decisions_tsv)"
fi
DONE_L=""; VER_L=""; DLT_L=""

# ---- rc 1 only when there is neither a readable source nor the session directory ----
if [ "$READ_ANY" = 0 ] && [ ! -d "$PROJ/$SDIR" ]; then
  echo "protocol-export: нет ни одного источника и каталога сессии $SDIR — экспортировать нечего." >&2
  exit 1
fi

RENDERED="$(px_render)" || { echo "protocol-export: не удалось сформировать protocol.yaml." >&2; exit 2; }
COUNTS="${RENDERED##*$'\n'#COUNTS }"
BODY="${RENDERED%$'\n'#COUNTS *}"
if [ -z "$OUTF" ]; then OUTF="$PROJ/$SDIR/protocol.yaml"; fi
if [ "$OUTF" = "-" ]; then
  printf '%s\n' "$BODY"
else
  dir="$(dirname "$OUTF")"
  [ -d "$dir" ] || { echo "protocol-export: каталог для записи не существует: $dir" >&2; exit 2; }
  tmp="$(mktemp "$OUTF.XXXXXX")" || { echo "protocol-export: не удалось создать временный файл рядом с $OUTF." >&2; exit 2; }
  printf '%s\n' "$BODY" > "$tmp" && mv "$tmp" "$OUTF" || { rm -f "$tmp"; echo "protocol-export: не удалось записать $OUTF." >&2; exit 2; }
fi
echo "protocol: $COUNTS" >&2
exit 0
