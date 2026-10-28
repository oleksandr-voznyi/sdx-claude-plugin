#!/usr/bin/env bash
# sdx/hooks/lib/miniyaml.sh — parser of the YAML SUBSET that `.mesh/mandate.yaml` uses (FEAT-016,
# REQ-MAND-10, 33). Sourced, not executed. bash 3.2 + POSIX awk (LC_ALL=C); no GNU-only flags, no
# associative arrays; mandate values are DATA and never reach the shell as code.
#
# Supported: block mappings (spaces), block lists with AND without indent (yaml.safe_dump shape),
# flow lists `[a, "b", 'c']` (one-line and multi-line), single/double quotes, comments, blank lines,
# CRLF, a leading `---`. Everything else is refused ("вне подмножества", fail-closed): tab indent,
# second document, duplicate key, flow mapping, anchors/aliases/tags/block scalars, nested flow,
# list of mappings, a key under a scalar, a key after list items. The subset is STRICTER than
# yaml.safe_load only in the direction of refusal (DESIGN К-8).
#
# API (all read the result of the last my_load in $MY_NORM):
#   my_parse <file>   stdout: normalised records; the last one is "X<US>reason" on error
#   my_load  <file>   MY_NORM / MY_ERR; rc 0 ok | 1 parse error | 2 file unreadable
#   my_scalar <path>  last scalar value of <path> (empty if none)
#   my_list   <path>  list items of <path>, one per line
#   my_exists <path>  rc 0 if <path> or any descendant has a record
#   my_kind   <path>  scalar | list | map | null | absent
#   my_q <str> [max]  display quoting: C0/DEL stripped, \ and " escaped, truncated to max (160) chars
# Record format, fields separated by US (0x1f): O path | S path value | Z path | E path | L path value | X reason.

US=$'\037'

my_parse() {
  LC_ALL=C awk -v US="$US" '
  function err(msg) { printf "X%s%s, строка %d\n", US, msg, curln; failed = 1; exit }
  function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
  # scalar(v): parse a quoted or plain scalar into SV (value) and SK ("S" or "Z"). v has no leading blanks.
  function scalar(v,    c, i, n, ch, nx, out, rest) {
    SV = ""; SK = "S"
    c = substr(v, 1, 1)
    if (c == "\"") {
      n = length(v); out = ""; i = 2
      while (i <= n) {
        ch = substr(v, i, 1)
        if (ch == "\\") {
          nx = substr(v, i + 1, 1)
          if (nx == "\\" || nx == "\"" || nx == "/") out = out nx
          else if (nx == "t") out = out "\t"
          else if (nx == "n" || nx == "r") out = out " "
          else err("неподдерживаемая escape-последовательность в двойных кавычках")
          i += 2; continue
        }
        if (ch == "\"") break
        out = out ch; i++
      }
      if (i > n) err("кавычка не закрыта")
      rest = substr(v, i + 1)
      if (rest !~ /^[ \t]*$/ && rest !~ /^[ \t]+#/) err("лишние символы после закрывающей кавычки")
      gsub(US, "", out); SV = out; return
    }
    if (c == SQ) {
      n = length(v); out = ""; i = 2
      while (i <= n) {
        ch = substr(v, i, 1)
        if (ch == SQ) {
          if (substr(v, i + 1, 1) == SQ) { out = out SQ; i += 2; continue }
          break
        }
        out = out ch; i++
      }
      if (i > n) err("кавычка не закрыта")
      rest = substr(v, i + 1)
      if (rest !~ /^[ \t]*$/ && rest !~ /^[ \t]+#/) err("лишние символы после закрывающей кавычки")
      gsub(US, "", out); SV = out; return
    }
    if (index("&*!|>%@`", c) > 0) err("якорь, алиас, тег или блочный скаляр вне подмножества")
    sub(/[ \t]+#.*$/, "", v); sub(/[ \t]+$/, "", v)
    if (v ~ /: / || v ~ /:\t/ || v ~ /:$/) err("строка не разобрана как YAML (двоеточие в простом скаляре, список словарей или вложенное отображение)")
    gsub(US, "", v)
    if (v == "~" || v == "null" || v == "Null" || v == "NULL") SK = "Z"
    SV = v
  }
  # flow_feed(s): accumulate one line of a flow list; when the closing bracket arrives, emit L/E records.
  function flow_feed(s) { err("flow-список вне подмножества (разбор не реализован)") }
  BEGIN { SQ = "\047"; depth = 0; content = 0; failed = 0; fl_active = 0; rootind = -1 }
  {
    curln = NR
    line = $0; sub(/\r$/, "", line)
    if (fl_active) { flow_feed(line); next }
    if (line ~ /^ *\t/) err("табуляция в отступе")
    if (line ~ /^[ \t]*$/ || line ~ /^[ \t]*#/) next
    match(line, /[^ ]/); ind = RSTART - 1
    body = substr(line, ind + 1); sub(/[ \t]+$/, "", body)
    if (body ~ /^---([ \t]+#.*)?$/) { if (content) err("второй документ (---)"); content = 1; next }
    if (body ~ /^\.\.\.([ \t]+#.*)?$/) err("второй документ или маркер конца документа (...)")
    content = 1
    if (body ~ /^-([ \t]|$)/) {
      v = substr(body, 2); sub(/^[ \t]+/, "", v)
      while (depth > 0 && tind[depth] > ind) depth--
      if (depth == 0 || (kind[depth] != "open" && kind[depth] != "list")) err("элемент списка вне ключа")
      if (kind[depth] == "list" && ind != lind[depth]) err("непоследовательный отступ элементов списка")
      if (v == "" || v ~ /^#/) err("пустой элемент списка вне подмножества")
      if (v ~ /^-([ \t]|$)/ || v ~ /^[\[{]/) err("вложенный список или flow вне подмножества")
      scalar(v)
      printf "L%s%s%s%s\n", US, tpath[depth], US, SV
      kind[depth] = "list"; lind[depth] = ind
      next
    }
    if (body ~ /^[A-Za-z0-9_-]+:([ \t]|$)/) {
      key = body; sub(/:.*$/, "", key)
      val = substr(body, length(key) + 2); sub(/^[ \t]+/, "", val)
      if (val ~ /^#/) val = ""
    } else err("строка не разобрана как YAML")
    while (depth > 0 && tind[depth] >= ind) depth--
    if (depth > 0) {
      if (kind[depth] == "scalar") err("ключ под скаляром")
      if (kind[depth] == "list") err("ключ после элементов списка")
      if (kind[depth] == "map" && ind != cind[depth]) err("непоследовательный отступ")
      if (kind[depth] == "open") { kind[depth] = "map"; cind[depth] = ind }
      path = tpath[depth] "." key
    } else {
      if (rootind >= 0 && ind != rootind) err("непоследовательный отступ")
      rootind = ind; path = key
    }
    if (path in seen) err("дубликат ключа " path)
    seen[path] = 1
    depth++; tind[depth] = ind; tpath[depth] = path
    if (val == "") { kind[depth] = "open"; printf "O%s%s\n", US, path; next }
    kind[depth] = "scalar"
    c = substr(val, 1, 1)
    if (c == "[") { fl_path = path; fl_line = NR; fl_buf = ""; flow_feed(val); next }
    if (c == "{") {
      v2 = val; sub(/[ \t]+#.*$/, "", v2); gsub(/[ \t]/, "", v2)
      if (v2 == "{}") { printf "E%s%s\n", US, path; next }
      err("flow-словарь вне подмножества")
    }
    scalar(val)
    if (SK == "Z") printf "Z%s%s\n", US, path
    else printf "S%s%s%s%s\n", US, path, US, SV
  }
  END { if (!failed && fl_active) { curln = fl_line; err("flow-список не закрыт") } }
  ' "$1"
}

my_load() {
  local last
  MY_NORM=""; MY_ERR=""
  if [ ! -f "$1" ] || [ ! -r "$1" ]; then MY_ERR="файл не читается: $1"; return 2; fi
  MY_NORM="$(my_parse "$1")"
  last="${MY_NORM##*$'\n'}"
  if [ "${last:0:2}" = "X$US" ]; then MY_ERR="${last#X"$US"}"; return 1; fi
  return 0
}

my_scalar() { printf '%s\n' "$MY_NORM" | LC_ALL=C awk -F"$US" -v p="$1" '$1 == "S" && $2 == p { v = $3; f = 1 } END { if (f) print v }'; }
my_list()   { printf '%s\n' "$MY_NORM" | LC_ALL=C awk -F"$US" -v p="$1" '$1 == "L" && $2 == p { print $3 }'; }
my_exists() { printf '%s\n' "$MY_NORM" | LC_ALL=C awk -F"$US" -v p="$1" '$1 != "X" && $1 != "" && ($2 == p || index($2, p ".") == 1) { f = 1 } END { exit !f }'; }
my_kind() {
  printf '%s\n' "$MY_NORM" | LC_ALL=C awk -F"$US" -v p="$1" '
    $1 == "X" || $1 == "" { next }
    $2 == p { if ($1 == "L" || $1 == "E") k = "list"; else if ($1 == "S") k = "scalar"; else if ($1 == "Z") k = "null"; else if ($1 == "O" && k == "") k = "null" }
    index($2, p ".") == 1 { d = 1 }
    END { if (k == "" && !d) print "absent"; else if (d && (k == "" || k == "null")) print "map"; else print k }'
}

# my_q <str> [max=160]: JSON-like quoting for DISPLAY of untrusted values (REQ-MAND-3).
my_q() {
  local s="$1" max="${2:-160}" cut="" c2 l2 l3 l4
  s="$(printf '%s' "$s" | LC_ALL=C tr -d '\000-\037\177')"
  if [ "${#s}" -gt "$max" ]; then
    s="${s:0:max}"; cut="…"
    # a byte-locale cut may leave an incomplete UTF-8 sequence at the tail: drop it
    c2="$(printf '[\200-\277]')"; l2="$(printf '[\300-\337]')"; l3="$(printf '[\340-\357]')"; l4="$(printf '[\360-\367]')"
    s="$(printf '%s' "$s" | LC_ALL=C sed -e "s/${l2}\$//" -e "s/${l3}${c2}\{0,1\}\$//" -e "s/${l4}${c2}\{0,2\}\$//")"
  fi
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  printf '"%s%s"\n' "$s" "$cut"
}
