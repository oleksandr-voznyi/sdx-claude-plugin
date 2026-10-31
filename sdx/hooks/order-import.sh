#!/usr/bin/env bash
# sdx/hooks/order-import.sh — acceptance of a work order (FEAT-017, REQ-PKG-23..25, 10). A CLI called by
# commands/start.md through the Bash tool as `bash order-import.sh <subcommand> ...`; it never touches git state.
#
#   order-import.sh from-file  <path>        [--proj DIR] [--out FILE]
#   order-import.sh from-msg   <msg_id>      [--proj DIR] [--out FILE] [--inbox-json FILE]
#   order-import.sh from-issue <N> [--repo owner/repo] [--proj DIR] [--out FILE]
#   order-import.sh list                     [--proj DIR] [--inbox-json FILE]
#   order-import.sh stamp-state --sid <sid> --commitment <C> [--proj DIR]
#   order-import.sh unfold <path>            (internal: the order-unfold stage on stdout; used by the tests)
#
# bash 3.2 (BUG-010: no arrays, no mapfile, ...), bash + awk + sed + jq + git only; the order text is DATA: it is
# unfolded, parsed by miniyaml (a YAML subset), validated and cleaned, and never reaches a shell as code.
# set -e is deliberately not used: every failure is handled where it happens.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v jq >/dev/null 2>&1 || { echo "order-import: jq не найден — приём заказа невозможен (fail-closed)." >&2; exit 2; }
# shellcheck disable=SC1091
. "$here/lib/pr-lib.sh"

# ------------------------------------------------------------------------------------------------------------
# order-unfold (D-9, К-8). yaml.safe_dump folds long plain / single-quoted scalars (width 80) onto continuation lines
# indented deeper than their key; miniyaml reads one line per value. This awk stage joins such continuations with ONE
# space (as the YAML folding rule does). THE BOUNDARY (named here and in docs/specs/mo-interop.md): joined = plain and
# single-quoted scalars of "key: value" and "- value" lines whose continuation is indented deeper than the key / dash.
# Refused with the marker "#UNFOLD-ERR" (-> rc 1): a double-quoted scalar not closed on its line (PyYAML emits those
# for values with line breaks) and an empty line INSIDE a value. Left to miniyaml (which refuses them): block scalars,
# anchors, tags, flow dictionaries, lists of dictionaries ("- key: v" lines are never joined). A comment line that
# is indented deeper than an open scalar counts as its continuation (the dumper never emits such a comment).
# ------------------------------------------------------------------------------------------------------------
OI_UNFOLD_AWK='
function ind_of(s) { match(s, /^ */); return RLENGTH }
function flush() { if (have) print cur; have = 0; open = 0 }
function die(msg) { print "#UNFOLD-ERR: " msg " (строка " NR ")"; err = 1; exit }
# dq_closed(v): the double-quoted scalar v (first char is the quote) is closed on this line
function dq_closed(v,   i, n, ch) {
  n = length(v); i = 2
  while (i <= n) { ch = substr(v, i, 1); if (ch == "\\") { i += 2; continue } if (ch == "\"") return 1; i++ }
  return 0
}
function sq_closed(v,   i, n, ch) {
  n = length(v); i = 2
  while (i <= n) { ch = substr(v, i, 1); if (ch == "\047") { if (substr(v, i + 1, 1) == "\047") { i += 2; continue } return 1 } i++ }
  return 0
}
BEGIN { have = 0; open = 0; cind = 0; pend = 0; err = 0 }
{
  line = $0
  if (line ~ /^[ \t]*$/) { if (open) pend = 1; next }
  ind = ind_of(line); body = substr(line, ind + 1)
  if (open && ind > cind) {                                   # PKG-O-UNFOLD: the continuation of an open value
    if (pend) die("пустая строка внутри значения")
    sub(/[ \t]+$/, "", cur); sub(/[ \t]+$/, "", body)
    cur = cur " " body
    next
  }
  flush(); pend = 0
  if (body ~ /^#/) { print line; next }
  val = ""
  if (body ~ /^[A-Za-z0-9_-]+:([ \t]|$)/) { val = body; sub(/^[A-Za-z0-9_-]+:[ \t]*/, "", val) }
  else if (body ~ /^-([ \t]|$)/) { val = body; sub(/^-[ \t]*/, "", val); if (val ~ /^[A-Za-z0-9_-]+:([ \t]|$)/) val = "" }
  cur = line; have = 1
  if (val == "" || val ~ /^#/) next
  c = substr(val, 1, 1)
  if (index("[{|>&*!%@`", c) > 0) next
  if (c == "\"") { if (!dq_closed(val)) die("двойные кавычки с переносом строки не поддерживаются"); next }
  cind = ind
  if (c == "\047") { open = !sq_closed(val); next }
  open = 1
}
END { if (!err) flush() }
'

# oi_unfold: stdin (CR already removed) -> stdout
oi_unfold() { LC_ALL=C awk "$OI_UNFOLD_AWK"; }

OI_MAX=65536           # the size limit of an order text (bytes)
OI_TMP=""
oi_cleanup() { [ -n "$OI_TMP" ] && rm -rf "$OI_TMP"; }
trap oi_cleanup EXIT
oi_tmpdir() { [ -n "$OI_TMP" ] && return 0; OI_TMP="$(mktemp -d "${TMPDIR:-/tmp}/sdx-order-import.XXXXXX")" || { echo "order-import: не удалось создать временный каталог." >&2; exit 2; }; }

refuse() { echo "order-import: $1" >&2; exit 1; }

# oi_size_ok <file>: refuse a file over the limit
oi_size_ok() {
  local n
  n="$(wc -c < "$1" 2>/dev/null | tr -d ' ')"
  [ -n "$n" ] && [ "$n" -le "$OI_MAX" ] || refuse "заказ больше 64 КиБ — отказ"
}

# oi_load_yaml <file>: unfold + miniyaml; sets OI_MODE=yaml
oi_load_yaml() {
  oi_tmpdir
  LC_ALL=C tr -d '\r' < "$1" | oi_unfold > "$OI_TMP/unfolded.yaml"
  if grep -q '^#UNFOLD-ERR' "$OI_TMP/unfolded.yaml"; then
    pr_clean "$(grep -m1 '^#UNFOLD-ERR' "$OI_TMP/unfolded.yaml")" 160
    refuse "order: ${PR_CLEAN#\#UNFOLD-ERR: }"
  fi
  my_load "$OI_TMP/unfolded.yaml"
  case $? in
    0) ;;
    *) pr_clean "$MY_ERR" 160; refuse "order: не разобран ($PR_CLEAN)" ;;
  esac
  OI_MODE=yaml
}

# oi_get <path>: OI_V (a scalar's text; a list is joined by "; ") and OI_K (scalar|list|map|absent)
oi_get() {
  local out
  OI_V=""; OI_K=absent
  if [ "$OI_MODE" = json ]; then
    out="$(jq -r --arg p "$1" '(try getpath($p | split(".")) catch null) as $v
      | if $v == null then "absent\n"
        elif ($v | type) == "string" or ($v | type) == "number" or ($v | type) == "boolean" then "scalar\n" + ($v | tostring)
        elif ($v | type) == "array" then (if ([$v[] | type] | all(. == "string" or . == "number")) then "list\n" + ($v | map(tostring) | join("; ")) else "map\n" end)
        else "map\n" end' "$OI_DOC" 2>/dev/null)"
    OI_K="${out%%$'\n'*}"; OI_V="${out#*$'\n'}"
    [ "$OI_V" = "$out" ] && OI_V=""
  else
    _my_kind "$1"; OI_K="$MY_K"
    case "$OI_K" in
      scalar) _my_scalar "$1"; OI_V="$MY_S" ;;
      list) _my_list "$1"; OI_V="${MY_L//$'\n'/; }" ;;
      null) OI_K=absent ;;
    esac
  fi
  return 0
}

# oi_need_scalar <path>: like oi_get, but a map (or, unless <list-ok>, a list) is refused
oi_need_scalar() {
  oi_get "$1"
  case "$OI_K" in
    map) refuse "$1: ожидается значение, а не вложенная структура" ;;
    list) [ "${2:-}" = list-ok ] || refuse "$1: ожидается значение, а не список" ;;
  esac
}

# oi_read_doc <file>: JSON ({ first) or YAML
oi_read_doc() {
  local first
  [ -f "$1" ] && [ -r "$1" ] || refuse "файл заказа не читается: $(pr_clean "$1" 120; printf '%s' "$PR_CLEAN")"
  oi_size_ok "$1"
  first="$(LC_ALL=C tr -d ' \t\r\n' < "$1" | head -c1)"
  if [ "$first" = "{" ]; then
    jq -e 'type == "object"' "$1" >/dev/null 2>&1 || refuse "order: JSON не разобран"
    oi_tmpdir
    jq 'if (.action == null and ((.body | type) == "object")) then .body else . end' "$1" > "$OI_TMP/doc.json" 2>/dev/null || refuse "order: JSON не разобран"
    OI_DOC="$OI_TMP/doc.json"; OI_MODE=json
  else
    oi_load_yaml "$1"
  fi
}

OI_WARN=""
oi_warn() { OI_WARN="$OI_WARN${OI_WARN:+$'\n'}$1"; }

# oi_clean_field <label> <path> <max> [list-ok]: O_V = the cleaned value; a warning when it was cut
oi_clean_field() {
  local full
  oi_need_scalar "$2" "${4:-}"
  pr_clean "$OI_V" 100000; full="$PR_CLEAN"
  pr_clean "$OI_V" "$3"; O_V="$PR_CLEAN"
  [ "$full" = "$O_V" ] || oi_warn "$1: усечено до $3 знаков"
  O_FULL="$full"
}

# oi_validate: the checks of the DESIGN order, on the loaded document -> O_* variables (rc: exit 1 with the field named)
oi_validate() {
  local v
  oi_need_scalar action;  [ "$OI_V" = work.order ] || refuse "action: ожидается work.order"
  oi_need_scalar format;  [ "$OI_V" = 1 ] || refuse "format: ожидается 1"
  # identifiers: a closed alphabet, the field is named (REQ-PKG-10)
  oi_need_scalar commitment.id; O_C="$OI_V"
  pr_valid_id "$O_C" || { _pr_id_err commitment.id "$O_C"; refuse "$PR_ERR"; }           # PKG-O-ID
  oi_need_scalar executor; O_EXEC="$OI_V"
  pr_valid_id "$O_EXEC" || { _pr_id_err executor "$O_EXEC"; refuse "$PR_ERR"; }
  # free text: one line, no control characters, cut; a secret is refused
  oi_clean_field title commitment.title 200; O_TITLE="$O_V"; v="$O_FULL"
  [ -n "$O_TITLE" ] || refuse "commitment.title: не задан"
  pr_has_secret "$v" && refuse "commitment.title: похоже на секрет"
  oi_clean_field requirements commitment.requirements 4000 list-ok; O_REQS="$O_V"
  pr_has_secret "$O_FULL" && refuse "commitment.requirements: похоже на секрет"
  # due
  oi_need_scalar commitment.due; v="$OI_V"; O_DUE=""
  if [ -n "$v" ]; then
    case "${v:0:10}" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) O_DUE="${v:0:10}" ;;
      *) pr_clean "$v" 24; refuse "commitment.due: ожидается дата ГГГГ-ММ-ДД, получено '$PR_CLEAN'" ;;
    esac
  fi
  oi_clean_field kind commitment.kind 64; O_KIND="$O_V"
  oi_clean_field creditor commitment.creditor 120; O_CRED="$O_V"
  # repository
  oi_clean_field repo.id repo.id 64; O_RID="$O_V"
  oi_need_scalar repo.base; O_BASE="$OI_V"
  if [ -n "$O_BASE" ]; then
    case "$O_BASE" in -*|*[[:space:]]*|*[[:cntrl:]]*|*'@{'*|*\\*) pr_clean "$O_BASE" 40; refuse "repo.base: недопустимое имя ветки '$PR_CLEAN'" ;; esac
    git check-ref-format "refs/heads/$O_BASE" 2>/dev/null || { pr_clean "$O_BASE" 40; refuse "repo.base: недопустимое имя ветки '$PR_CLEAN'"; }
  fi
  oi_need_scalar repo.url; O_URL="$OI_V"
  if [ -n "$O_URL" ]; then
    pr_url_ok "$O_URL" || refuse "repo.url: недопустимая схема или символы (разрешены ssh, https, http, file, scp-вид, абсолютный путь)"
    pr_url_show "$O_URL"
    if [ "$PR_URLS" != "$O_URL" ]; then oi_warn "repo.url: учётные данные удалены из адреса"; O_URL="$PR_URLS"; fi
  fi
  oi_need_scalar repo.hosting; O_HOST=""
  case "$OI_V" in
    github|bare) O_HOST="$OI_V" ;;
    "") ;;
    *) pr_clean "$OI_V" 24; oi_warn "repo.hosting: значение '$PR_CLEAN' не распознано, игнорируется" ;;
  esac
  # delivery
  oi_need_scalar deliver.branch; pr_clean "$OI_V" 120; O_BRANCH="$PR_CLEAN"
  oi_need_scalar deliver.delivery; O_DELIV="$OI_V"
  case "$O_DELIV" in
    ""|[a-z]*) case "$O_DELIV" in *[!a-z._-]*) pr_clean "$O_DELIV" 24; refuse "deliver.delivery: недопустимое значение '$PR_CLEAN'" ;; esac ;;
    *) pr_clean "$O_DELIV" 24; refuse "deliver.delivery: недопустимое значение '$PR_CLEAN'" ;;
  esac
  oi_need_scalar mandate_digest; pr_clean "$OI_V" 64; O_DIGEST="$PR_CLEAN"
  O_INFIX="${O_C:0:40}"
}

# oi_flat <source> <source-ref>: the flat JSON of the DESIGN on stdout
oi_flat() {
  jq -n --arg source "$1" --arg source_ref "$2" --arg commitment "$O_C" --arg title "$O_TITLE" --arg executor "$O_EXEC" \
    --arg repo_base "$O_BASE" --arg repo_url "$O_URL" --arg branch "$O_BRANCH" --arg delivery "$O_DELIV" --arg due "$O_DUE" \
    --arg sid_infix "$O_INFIX" --arg warn "$OI_WARN" \
    '{source:$source, source_ref:$source_ref, commitment:$commitment, title:$title, executor:$executor, repo_base:$repo_base, repo_url:$repo_url,
      branch:$branch, delivery:$delivery, due:$due, sid_infix:$sid_infix, warnings:($warn | split("\n") | map(select(length > 0)))}'
}

# oi_accept <file> <source> <source-ref>
oi_accept() {
  oi_read_doc "$1"
  oi_validate
  oi_flat "$2" "$3"
}

# ------------------------------------------------------------------------------------------------------------
# Mailbox: `inbox --json` of the vendored mesh_endpoint.py prints ONE canonical JSON line per accepted envelope
# (mesh_endpoint.py:155-162). A work order is {kind: "directive", body: {action: "work.order", ...}}; the envelope
# chain was verified by mesh_endpoint.py, the body is still DATA. Without --inbox-json the script runs
# mesh_endpoint.py itself (it needs python3 + PyYAML, as the tool does).
# ------------------------------------------------------------------------------------------------------------
oi_msg_ok() {   # ^[A-Za-z0-9._:-]{1,80}$
  case "$1" in ""|*[!A-Za-z0-9._:-]*) return 1 ;; esac
  [ "${#1}" -le 80 ]
}

# oi_inbox: OI_INBOX_FILE = a file with the envelope lines
oi_inbox() {
  local py="${ORDER_IMPORT_PYTHON:-python3}" mesh="$here/../mo/mesh_endpoint.py"
  if [ -n "$INBOX" ]; then
    [ -f "$INBOX" ] && [ -r "$INBOX" ] || refuse "--inbox-json не читается"
    OI_INBOX_FILE="$INBOX"; return 0
  fi
  command -v "$py" >/dev/null 2>&1 || refuse "python3 не найден — ящик не прочитать: передайте --inbox-json <файл> (вывод 'mesh_endpoint.py inbox --json') либо используйте from-file"
  [ -f "$mesh" ] || refuse "sdx/mo/mesh_endpoint.py не найден рядом со скриптом"
  oi_tmpdir
  PYTHONDONTWRITEBYTECODE=1 MESH_ENDPOINT_DIR="$PROJ" "$py" -I -B "$mesh" pull > /dev/null 2> "$OI_TMP/pull.err" \
    || echo "order-import: pull не удался (читается уже полученное): $(head -n1 "$OI_TMP/pull.err" | tr -d '\000-\037')" >&2
  PYTHONDONTWRITEBYTECODE=1 MESH_ENDPOINT_DIR="$PROJ" "$py" -I -B "$mesh" inbox --json > "$OI_TMP/inbox.jsonl" 2> "$OI_TMP/inbox.err" \
    || refuse "ящик не прочитан (нужны python3 и PyYAML): передайте --inbox-json <файл> либо используйте from-file"
  OI_INBOX_FILE="$OI_TMP/inbox.jsonl"
}

# oi_orders_jq: select expression shared by from-msg and list (garbage lines are skipped)
OI_ENV_SEL='fromjson? | select(type == "object" and .kind == "directive" and (.body | type) == "object" and .body.action == "work.order")'

oi_from_msg() {   # <msg_id>
  local n
  oi_msg_ok "$1" || refuse "msg_id: недопустимое значение (разрешены A-Za-z0-9._:- до 80 знаков)"
  oi_inbox
  oi_tmpdir
  jq -cR --arg id "$1" "$OI_ENV_SEL | select(.msg_id == \$id) | .body" "$OI_INBOX_FILE" > "$OI_TMP/sel.jsonl" 2>/dev/null
  n="$(grep -c . "$OI_TMP/sel.jsonl")"
  [ "$n" -ge 1 ] || refuse "msg_id: директива work.order с msg_id $1 в ящике не найдена"
  [ "$n" -eq 1 ] || refuse "msg_id: в ящике несколько конвертов с msg_id $1 — выбор неоднозначен"
  head -n1 "$OI_TMP/sel.jsonl" > "$OI_TMP/doc.json"
  oi_size_ok "$OI_TMP/doc.json"
  OI_DOC="$OI_TMP/doc.json"; OI_MODE=json
  oi_validate
  oi_flat msg "$1"
}

oi_list() {
  local m c t
  oi_inbox
  jq -rR "$OI_ENV_SEL | [(.msg_id | tostring), (.body.commitment.id? // \"\" | tostring), (.body.commitment.title? // \"\" | tostring)] | @tsv" "$OI_INBOX_FILE" 2>/dev/null \
  | while IFS=$'\t' read -r m c t; do
      oi_msg_ok "$m" || { echo "order-import: конверт с недопустимым msg_id пропущен" >&2; continue; }
      pr_clean "$c" 64; c="$PR_CLEAN"; pr_clean "$t" 100; t="$PR_CLEAN"
      printf '%s\t%s\t%s\n' "$m" "$c" "$t"
    done
}

# ------------------------------------------------------------------------------------------------------------
# Issue (REQ-PKG-24). ASSUMPTION OF SDX (Q-10): the sim-kit reference does not define how an order is wrapped in an
# issue; SDX takes the FIRST fenced block ```yaml (or ```yml) that contains the line `action: work.order` at zero
# indent. The text of an issue is unauthenticated: the command prose asks the user to confirm it in any gate_mode (К-9).
# ------------------------------------------------------------------------------------------------------------
OI_FENCE_AWK='
BEGIN { inb = 0; hit = 0; blk = "" }
{ sub(/\r$/, "") }
inb == 0 && /^```[ \t]*(yaml|yml)[ \t]*$/ { inb = 1; hit = 0; blk = ""; next }
inb == 1 && /^```[ \t]*$/ { if (hit) { printf "%s", blk; exit } inb = 0; next }   # PKG-O-FENCE
inb == 1 { blk = blk $0 "\n"; if ($0 ~ /^action:[ \t]*["\047]?work\.order["\047]?[ \t]*(#.*)?$/) hit = 1 }
'

oi_from_issue() {   # <N>
  local gh="${ORDER_IMPORT_GH:-gh}"
  case "$1" in ""|*[!0-9]*) refuse "issue: номер должен быть десятичным целым" ;; esac
  [ "${#1}" -le 9 ] || refuse "issue: номер слишком длинный"
  if [ -n "$REPO" ]; then
    case "$REPO" in
      -*|/*|*/|*/*/*|*[!A-Za-z0-9._/-]*) refuse "repo: ожидается owner/repo (A-Za-z0-9._-)" ;;
      */*) ;;
      *) refuse "repo: ожидается owner/repo" ;;
    esac
  fi
  command -v "$gh" >/dev/null 2>&1 || refuse "gh не найден: скопируйте YAML-блок заказа из issue в файл и используйте --from-order <файл> (from-file)"
  oi_tmpdir
  if [ -n "$REPO" ]; then
    "$gh" issue view "$1" --repo "$REPO" --json body > "$OI_TMP/issue.json" 2> "$OI_TMP/gh.err"
  else
    "$gh" issue view "$1" --json body > "$OI_TMP/issue.json" 2> "$OI_TMP/gh.err"
  fi || { pr_clean "$(head -n1 "$OI_TMP/gh.err")" 160; refuse "issue: gh issue view не удался ($PR_CLEAN); используйте --from-order <файл>"; }
  jq -r '.body // ""' "$OI_TMP/issue.json" 2>/dev/null | LC_ALL=C awk "$OI_FENCE_AWK" > "$OI_TMP/block.yaml"
  [ -s "$OI_TMP/block.yaml" ] || refuse "issue: в тексте нет блока \`\`\`yaml с action: work.order на нулевом отступе; используйте --from-order <файл>"
  oi_size_ok "$OI_TMP/block.yaml"
  oi_load_yaml "$OI_TMP/block.yaml"
  oi_validate
  oi_flat issue "#$1"
}

usage() {
  echo "использование: order-import.sh from-file <path> | from-msg <msg_id> | from-issue <N> | list | stamp-state --sid <sid> --commitment <C> | unfold <path>  [--proj DIR] [--out FILE] [--inbox-json FILE] [--repo owner/repo]" >&2
  exit 2
}

sub="${1:-}"; [ $# -gt 0 ] && shift
POS=""; PROJ="${CLAUDE_PROJECT_DIR:-.}"; OUTF=""; INBOX=""; REPO=""; SID=""; CARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --proj|--out|--inbox-json|--repo|--sid|--commitment)
      [ $# -ge 2 ] || { echo "order-import: у $1 нет значения." >&2; exit 2; }
      case "$1" in --proj) PROJ="$2" ;; --out) OUTF="$2" ;; --inbox-json) INBOX="$2" ;; --repo) REPO="$2" ;; --sid) SID="$2" ;; *) CARG="$2" ;; esac
      shift 2 ;;
    --*) echo "order-import: неизвестный аргумент: $(pr_clean "$1" 40; printf '%s' "$PR_CLEAN")" >&2; usage ;;
    *) [ -z "$POS" ] || usage; POS="$1"; shift ;;
  esac
done

case "$sub" in
  from-file)
    [ -n "$POS" ] || usage
    pr_clean "${POS##*/}" 80
    oi_accept "$POS" file "$PR_CLEAN" ;;
  from-msg)
    [ -n "$POS" ] || usage
    oi_from_msg "$POS" ;;
  from-issue)
    [ -n "$POS" ] || usage
    oi_from_issue "$POS" ;;
  list) oi_list ;;
  unfold)
    [ -n "$POS" ] || usage
    [ -f "$POS" ] || refuse "файл не читается"
    oi_tmpdir
    LC_ALL=C tr -d '\r' < "$POS" | oi_unfold > "$OI_TMP/unfold.out" || exit 2
    if grep -q '^#UNFOLD-ERR' "$OI_TMP/unfold.out"; then refuse "order: ошибка склейки строк"; fi
    cat "$OI_TMP/unfold.out" ;;
  *) usage ;;
esac
