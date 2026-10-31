#!/usr/bin/env bash
# Tests for sdx/hooks/lib/miniyaml.sh and sdx/hooks/lib/mandate.sh (FEAT-016, REQ-MAND-2..12, 10, 31, 33).
# The two libraries are the single bash parser/semantics of `.mesh/mandate.yaml` used by sdx-stage.sh,
# mo-session.sh, mandate-info.sh, mandate-scope.sh and suites-gen.sh. PyYAML/python3 appear here ONLY
# as a test oracle (INFO-skip, never PASS, when absent); no production file calls python.
#
# Scenarios (DESIGN "Тесты"):
#  [L1]  miniyaml corpus: block / flow / mixed forms, CRLF, comments, '---', quoting, null/empty stages,
#        and the refusals (not YAML, tab indent, second document, duplicate key, flow dict, anchor/alias/tag,
#        key under scalar, key after list items, ...) — a static table of (rc, stages) expectations
#  [L1q] my_q: display quoting (control chars stripped, backslash/quote escaped, truncation)
#  [L2]  parity with yaml.safe_load on the same corpus (oracle; divergences only towards refusal, listed by name)
#  [L3]  a real node dump (full how_to_deliver, format: 1, quoted date) -> fields
#  [L4]  stage x stages table (Deployment never; Verification/Closeout always)
#  [L5]  glob_any: static table + oracle formula DEV:67-68
#  [L6]  mandate_expired with SDX_MANDATE_TODAY
#  [L7]  mandate_mode
#  [L8]  mandate_report: hostile values, area/expiry warnings, orphan line
#  [L9]  portability of the lib files (BUG-010) + red side; no python in lib/*.sh and sdx-stage.sh (REQ-MAND-33)
#  [Mut] mutation runs (copies of lib/ in a temp dir, anchored by "# MAND-*" tags)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="${MANDATE_LIB_UNDER_TEST:-$SCRIPT_DIR/lib}"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
info() { echo "  INFO: $1"; }
# MANDATE_ONLY="L5 L8" restricts a run to the named sections (mutation runs re-enter this script).
want() { [ -z "${MANDATE_ONLY:-}" ] && return 0; case " $MANDATE_ONLY " in *" $1 "*) return 0 ;; esac; return 1; }

echo "=== test-mandate-lib.sh ==="
echo ""

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/fx"

# Source the library under test; a missing file is not fatal here — every check then fails by itself.
MY_OK=0
if [ -f "$LIB/miniyaml.sh" ]; then
  # shellcheck disable=SC1091
  . "$LIB/miniyaml.sh" && MY_OK=1
fi

have_my() { [ "$MY_OK" = 1 ] && declare -F my_load >/dev/null 2>&1; }

# fx <name> <content>: write a fixture file (content verbatim, no trailing newline added).
fx() { printf '%s' "$2" > "$TMP/fx/$1.yaml"; }

csv() { local l out="" n=0; while IFS= read -r l; do out="$out${out:+,}$l"; done; printf '%s' "$out"; }

# chk <name> <expect> <content> [path=value ...]
#   expect: "ok:<stages csv>" -> my_load rc 0 and mandate.stages list equals the csv (empty csv = none);
#           "err:<fragment>"  -> my_load rc 1, MY_ERR contains <fragment> and "строка <N>".
#   extra "path=value" args: my_scalar <path> must equal value; "path@csv": my_list <path> joined by ',' must equal csv.
chk() {
  local name="$1" exp="$2" content="$3" rc got a p v
  shift 3
  if ! have_my; then fail "[L1] $name" "lib/miniyaml.sh missing or my_load undefined"; return; fi
  fx "$name" "$content"
  my_load "$TMP/fx/$name.yaml"; rc=$?
  case "$exp" in
    ok:*)
      if [ "$rc" -ne 0 ]; then fail "[L1] $name" "expected ok, rc=$rc err=[$MY_ERR]"; return; fi
      got="$(my_list mandate.stages | csv)"
      if [ "$got" != "${exp#ok:}" ]; then fail "[L1] $name" "stages=[$got] expected [${exp#ok:}]"; return; fi
      for a in "$@"; do
        case "$a" in
          *@*) p="${a%%@*}"; v="${a#*@}"; got="$(my_list "$p" | csv)"
               [ "$got" = "$v" ] || { fail "[L1] $name" "list $p=[$got] expected [$v]"; return; } ;;
          *=*) p="${a%%=*}"; v="${a#*=}"; got="$(my_scalar "$p")"
               [ "$got" = "$v" ] || { fail "[L1] $name" "scalar $p=[$got] expected [$v]"; return; } ;;
        esac
      done
      pass "[L1] $name -> ok [${exp#ok:}]" ;;
    err:*)
      if [ "$rc" -ne 1 ]; then fail "[L1] $name" "expected rc 1, got rc=$rc (stages=[$(my_list mandate.stages | csv)])"; return; fi
      case "$MY_ERR" in *"${exp#err:}"*) ;; *) fail "[L1] $name" "reason [$MY_ERR] lacks [${exp#err:}]"; return ;; esac
      case "$MY_ERR" in *"строка "[0-9]*) ;; *) fail "[L1] $name" "reason [$MY_ERR] lacks a line number"; return ;; esac
      pass "[L1] $name -> refused ($MY_ERR)" ;;
  esac
}

# ============================================================== [L1] corpus
if want L1; then
echo "[L1] miniyaml corpus"
chk block-indented   "ok:spec,design" $'mandate:\n  stages:\n    - spec\n    - design\n'
chk block-indentless "ok:spec,design" $'mandate:\n  stages:\n  - spec\n  - design\n  scope:\n    paths:\n    - src/**\n' "mandate.scope.paths@src/**"
chk flow-oneline     "ok:spec,design" $'mandate:\n  stages: [spec, design]\n'
chk flow-multiline   "ok:spec,design,execute" $'mandate:\n  stages: [\n    spec,\n    "design",\n    \'execute\'\n  ]\n'
chk flow-ml-comments "ok:spec,verify" $'mandate:\n  stages: [spec, # first\n    # a comment line\n    verify]  # tail\n  executor: x\n' "mandate.executor=x"
chk mixed-forms      "ok:spec,execute" $'mandate:\n  stages:\n  - spec\n  - execute\n  scope:\n    paths: [src/**, "tests/**"]\n    shared_paths:\n    - composer.lock\n' "mandate.scope.paths@src/**,tests/**" "mandate.scope.shared_paths@composer.lock"
chk crlf             "ok:spec,design" $'mandate:\r\n  stages:\r\n  - spec\r\n  - design\r\n  executor: dev1\r\n' "mandate.executor=dev1"
chk comments         "ok:spec" $'# top comment\nmandate: # root\n  # inside\n  stages: # key comment\n  - spec # item comment\n  # between\n  executor: e # trailing\n' "mandate.executor=e"
chk doc-start        "ok:spec" $'---\nmandate:\n  stages: [spec]\n'
chk dq-items         "ok:spec,design" $'mandate:\n  stages: ["spec", "design"]\n'
chk sq-items         "ok:spec" $'mandate:\n  stages:\n  - \'spec\'\n'
chk sq-escape        "ok:" $'mandate:\n  scope:\n    paths: [\'it\'\'s\']\n' "mandate.scope.paths@it's"
chk dq-escape        "ok:" $'mandate:\n  executor: "a\\"b\\\\c"\n' 'mandate.executor=a"b\c'
chk date-quoted      "ok:" $'mandate:\n  valid_until: \'2026-12-31\'\n' "mandate.valid_until=2026-12-31"
chk stages-empty     "ok:" $'mandate:\n  stages:\n  executor: x\n' "mandate.executor=x"
chk stages-null      "ok:" $'mandate:\n  stages: null\n'
chk stages-tilde     "ok:" $'mandate:\n  stages: ~\n'
chk stages-brackets  "ok:" $'mandate:\n  stages: []\n'
chk stages-bracket-sp "ok:" $'mandate:\n  stages: [ ]\n'
chk stages-absent    "ok:" $'mandate:\n  executor: x\n'
chk hash-in-quotes   "ok:" $'mandate:\n  executor: "a # b"\n  digest: a#b\n' "mandate.executor=a # b" "mandate.digest=a#b"
chk trailing-spaces  "ok:spec" $'mandate:   \n  executor: dev   \n  stages:   \n  - spec   \n' "mandate.executor=dev"
chk colon-in-plain   "ok:" $'mandate:\n  branch: change/<C>-x\n  url: http://host:80/x\n' "mandate.url=http://host:80/x" "mandate.branch=change/<C>-x"
chk blank-lines      "ok:spec" $'\n\nmandate:\n\n   \n  stages:\n\n  - spec\n\n'
chk indent-4         "ok:spec,design" $'mandate:\n    stages:\n        - spec\n        - design\n    executor: z\n' "mandate.executor=z"
chk flow-trailing-comma "ok:spec,design" $'mandate:\n  stages: [spec, design,]\n'
chk flow-with-comment "ok:spec" $'mandate:\n  stages: [spec] # comment\n'
chk empty-file       "ok:" ''
chk comments-only    "ok:" $'# nothing\n\n# here\n'
chk numeric-scalar   "ok:" $'mandate:\n  format: 1\n' "mandate.format=1"
chk empty-quoted     "ok:" $'mandate:\n  executor: ""\n' "mandate.executor="
chk on-write-quoted  "ok:" $'mandate:\n  on_write: \'deny\'\n' "mandate.on_write=deny"
chk sibling-after-list "ok:spec" $'mandate:\n  stages:\n  - spec\n  delivery: pr\n  history: executor\n' "mandate.delivery=pr" "mandate.history=executor"
chk flow-then-key    "ok:spec,verify" $'mandate:\n  stages: [spec,\n   verify]\n  delivery: branch\n' "mandate.delivery=branch"
chk dash-plain-scalar "ok:" $'mandate:\n  node: -x-y\n' "mandate.node=-x-y"
chk top-level-two-keys "ok:spec" $'repo: r\nmandate:\n  stages: [spec]\nformat: 1\n' "repo=r" "format=1"
# refusals
chk not-yaml         "err:не разобрана как YAML" $'this is not yaml\n'
chk tab-indent       "err:табуляц" $'mandate:\n\tstages: [spec]\n'
chk second-doc       "err:второй документ" $'mandate:\n  stages: [spec]\n---\nmandate:\n  stages: [design]\n'
chk doc-end-marker   "err:второй документ" $'mandate:\n  stages: [spec]\n...\n'
chk dup-key          "err:дубликат ключа" $'mandate:\n  stages: [spec]\n  stages: [design]\n'
chk dup-top          "err:дубликат ключа" $'mandate:\n  stages: [spec]\nmandate:\n  stages: [design]\n'
chk flow-dict        "err:flow-словарь" $'mandate:\n  scope: {paths: [a]}\n'
chk anchor           "err:вне подмножества" $'mandate:\n  stages: &a [spec]\n'
chk alias            "err:вне подмножества" $'mandate:\n  stages: *a\n'
chk tag              "err:вне подмножества" $'mandate:\n  stages: !!seq [spec]\n'
chk block-scalar     "err:вне подмножества" $'mandate:\n  executor: |\n    text\n'
chk key-under-scalar "err:ключ под скаляром" $'mandate:\n  executor: x\n    foo: y\n'
chk key-after-list   "err:ключ после элементов списка" $'mandate:\n  stages:\n  - spec\n    foo: bar\n'
chk list-outside-key "err:элемент списка вне ключа" $'- spec\n'
chk list-under-scalar "err:элемент списка вне ключа" $'mandate:\n  executor: x\n  - y\n'
chk list-of-dicts    "err:не разобрана" $'mandate:\n  stages:\n  - name: x\n'
chk flow-unterminated "err:не закрыт" $'mandate:\n  stages: [spec\n'
chk quote-unterminated "err:не закрыта" $'mandate:\n  executor: "abc\n'
chk inconsistent-indent "err:непоследовательный отступ" $'mandate:\n    a: 1\n  b: 2\n'
chk nested-flow      "err:вне подмножества" $'mandate:\n  stages: [[spec]]\n'
chk plain-colon-space "err:не разобрана" $'mandate:\n  executor: a: b\n'
chk quoted-key       "err:не разобрана" $'"mandate":\n  stages: [spec]\n'
chk flow-trailing-junk "err:после ]" $'mandate:\n  stages: [spec] junk\n'
chk flow-empty-item  "err:пустой элемент" $'mandate:\n  stages: [spec,,design]\n'
chk bad-escape       "err:escape" $'mandate:\n  executor: "a\\qb"\n'

# my_load rc 2 on an unreadable / absent file
if have_my; then
  my_load "$TMP/fx/does-not-exist.yaml"; rc=$?
  if [ "$rc" -eq 2 ]; then pass "[L1] my_load: absent file -> rc 2"; else fail "[L1] my_load absent file" "rc=$rc"; fi
else fail "[L1] my_load: absent file -> rc 2" "lib/miniyaml.sh missing"; fi

# accessors on a fixed document
if have_my; then
  fx acc $'mandate:\n  stages: [spec]\n  e1: []\n  n1:\n  n2: ~\n  s1: v\n  scope:\n    paths:\n    - a\n    - b\n'
  my_load "$TMP/fx/acc.yaml"
  k() { my_kind "$1"; }
  [ "$(k mandate)" = map ] && [ "$(k mandate.stages)" = list ] && [ "$(k mandate.e1)" = list ] && [ "$(k mandate.n1)" = null ] \
    && [ "$(k mandate.n2)" = null ] && [ "$(k mandate.s1)" = scalar ] && [ "$(k mandate.scope)" = map ] && [ "$(k mandate.nope)" = absent ] \
    && pass "[L1] my_kind: map/list/list(empty)/null/null/scalar/map/absent" \
    || fail "[L1] my_kind" "mandate=$(k mandate) stages=$(k mandate.stages) e1=$(k mandate.e1) n1=$(k mandate.n1) n2=$(k mandate.n2) s1=$(k mandate.s1) scope=$(k mandate.scope) nope=$(k mandate.nope)"
  if my_exists mandate.scope && my_exists mandate.scope.paths && my_exists mandate.n1 && ! my_exists mandate.nope && ! my_exists mandate.sco; then
    pass "[L1] my_exists: key, nested key, empty key yes; absent and name-prefix no"
  else fail "[L1] my_exists" "unexpected result"; fi
  [ "$(my_list mandate.scope.paths | csv)" = "a,b" ] && [ -z "$(my_list mandate.s1)" ] && [ -z "$(my_scalar mandate.nope)" ] \
    && pass "[L1] my_list/my_scalar: list values; scalar of a non-scalar / absent is empty" \
    || fail "[L1] my_list/my_scalar" "unexpected"
else
  fail "[L1] my_kind" "lib missing"; fail "[L1] my_exists" "lib missing"; fail "[L1] my_list/my_scalar" "lib missing"
fi

fi
if want L2; then
echo "[L2] parity with yaml.safe_load (oracle) on the L1 corpus"
HAVE_YAML=0
if command -v python3 >/dev/null 2>&1 && PYTHONDONTWRITEBYTECODE=1 python3 -c 'import yaml' >/dev/null 2>&1; then HAVE_YAML=1; fi
# Documented divergences: the subset REFUSES where safe_load accepts (DESIGN К-8) — never the other way round.
ALLOWED_DIV="anchor block-scalar doc-end-marker dup-key dup-top flow-dict list-of-dicts list-outside-key nested-flow not-yaml quoted-key tag"
if [ "$HAVE_YAML" != 1 ]; then
  info "[L2] oracle skipped: python3 or PyYAML absent (INFO-skip, not a PASS)"
elif ! have_my; then
  fail "[L2] parity" "lib/miniyaml.sh missing"
else
  PYORACLE='
import sys, yaml
for f in sys.argv[1:]:
    n = f.rsplit("/", 1)[-1][:-5]
    try:
        d = yaml.safe_load(open(f, encoding="utf-8").read())
        st = []
        if isinstance(d, dict) and isinstance(d.get("mandate"), dict):
            s = d["mandate"].get("stages")
            if isinstance(s, list): st = s
        print(n + "\tok:" + ",".join(str(x) for x in st))
    except Exception:
        print(n + "\terr")'
  : > "$TMP/l2-mine.txt"
  for f in "$TMP"/fx/*.yaml; do
    n="${f##*/}"; n="${n%.yaml}"
    if my_load "$f"; then printf '%s\tok:%s\n' "$n" "$(my_list mandate.stages | csv)" >> "$TMP/l2-mine.txt"
    else printf '%s\terr\n' "$n" >> "$TMP/l2-mine.txt"; fi
  done
  PYTHONDONTWRITEBYTECODE=1 python3 -c "$PYORACLE" "$TMP"/fx/*.yaml > "$TMP/l2-py.txt" 2>/dev/null
  # compare <mine> <oracle>: prints "BAD <name> ..." for a divergence in the wrong direction, "DIV <name>" for a refusal-only one
  cmp_parity() {
    awk -F'\t' 'NR == FNR { m[$1] = $2; next }
      { n = $1; o = $2; v = m[n]
        if (v == o) next
        if (v == "err" && o ~ /^ok:/) print "DIV " n
        else print "BAD " n " mine=" v " oracle=" o }' "$1" "$2"
  }
  total="$(wc -l < "$TMP/l2-mine.txt" | tr -d ' ')"
  res="$(cmp_parity "$TMP/l2-mine.txt" "$TMP/l2-py.txt")"
  bad="$(printf '%s\n' "$res" | grep '^BAD' | head -3)"
  if [ -z "$bad" ] && [ "$total" -ge 50 ]; then pass "[L2] $total fixtures: no divergence from safe_load except towards refusal"
  else fail "[L2] parity" "total=$total ${bad:-no BAD lines}"; fi
  divs="$(printf '%s\n' "$res" | sed -n 's/^DIV //p' | sort | tr '\n' ' ' | sed 's/ $//')"
  if [ "$divs" = "$ALLOWED_DIV" ]; then pass "[L2] refusal-only divergences are exactly the documented set: $divs"
  else fail "[L2] documented divergences" "got [$divs] expected [$ALLOWED_DIV]"; fi
  # built-in negative: a substituted oracle answer must be reported as a wrong-direction divergence
  sed '0,/\tok:spec,design$/s//\tok:forged/' "$TMP/l2-py.txt" > "$TMP/l2-py-forged.txt"
  if ! cmp -s "$TMP/l2-py.txt" "$TMP/l2-py-forged.txt" && cmp_parity "$TMP/l2-mine.txt" "$TMP/l2-py-forged.txt" | grep -q '^BAD'; then
    pass "[L2] red side: a forged oracle answer is reported as a BAD divergence"
  else fail "[L2] red side" "forged oracle not detected"; fi
fi
fi

# ============================================================== [L1q] my_q
if want L1q; then
echo "[L1q] my_q display quoting"
if have_my; then
  got="$(my_q 'plain')"; [ "$got" = '"plain"' ] && pass "[L1q] plain -> \"plain\"" || fail "[L1q] plain" "got [$got]"
  got="$(my_q 'a"b\c')"; [ "$got" = '"a\"b\\c"' ] && pass "[L1q] quote and backslash escaped" || fail "[L1q] escape" "got [$got]"
  got="$(my_q $'a\033[31mb\001c\177d\te')"; [ "$got" = '"a[31mbcde"' ] && pass "[L1q] ESC/C0/DEL/TAB stripped" || fail "[L1q] control chars" "got [$got]"
  long="$(awk 'BEGIN{for(i=0;i<5000;i++)printf "x"}')"
  got="$(my_q "$long")"; n="${#got}"
  if [ "$n" -le 170 ] && [ "$n" -ge 160 ] && [ "${got%…\"}" != "$got" ]; then pass "[L1q] 5000 chars truncated to 160 + ellipsis (len $n)"
  else fail "[L1q] truncation" "len=$n tail=[${got: -4}]"; fi
  got="$(my_q "$long" 10)"; [ "$got" = '"xxxxxxxxxx…"' ] && pass "[L1q] explicit max honoured" || fail "[L1q] max" "got [$got]"
  got="$(my_q '')"; [ "$got" = '""' ] && pass "[L1q] empty -> \"\"" || fail "[L1q] empty" "got [$got]"
  got="$(my_q 'ключ-значение')"; [ "$got" = '"ключ-значение"' ] && pass "[L1q] UTF-8 passes through" || fail "[L1q] utf8" "got [$got]"
  got="$(LC_ALL=C my_q 'абвгдежз' 7)"
  if printf '%s' "$got" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then pass "[L1q] byte-locale truncation never leaves a broken UTF-8 tail"
  else fail "[L1q] utf8 tail" "invalid UTF-8 in [$got]"; fi
else
  for t in plain escape control truncation max empty utf8 utf8-tail; do fail "[L1q] $t" "lib/miniyaml.sh missing"; done
fi

fi
# ============================================================== [L3] real node dump
if want L3; then
echo "[L3] real node dump (yaml.safe_dump(sort_keys=False) shape)"
DUMP=$'mandate:\n  repo: app1\n  stages:\n  - spec\n  - design\n  - execute\n  - verify\n  scope:\n    paths:\n    - src/**\n    - tests/**\n    shared_paths:\n    - composer.lock\n    branches:\n    - dev\n    docs_paths:\n    - docs/**\n  delivery: artifact.offer\n  history: executor\n  docs_in_repo: final\n  valid_until: \'2026-12-31\'\n  on_write: deny\n  executor: sdx-dev1\n  issued: \'2026-10-28T10:00:00+00:00\'\n  node: mo-node-1\n  digest: 0123456789ab\n  format: 1\n  how_to_deliver:\n    branch: change/<C>-sdx-dev1\n    manifest: CHANGE.yaml\n    fields:\n    - format\n    - commitment\n    - executor\n'
chk real-dump "ok:spec,design,execute,verify" "$DUMP" \
  "mandate.executor=sdx-dev1" "mandate.digest=0123456789ab" "mandate.valid_until=2026-12-31" "mandate.delivery=artifact.offer" \
  "mandate.scope.paths@src/**,tests/**" "mandate.scope.shared_paths@composer.lock" "mandate.scope.docs_paths@docs/**" "mandate.scope.branches@dev" \
  "mandate.format=1" "mandate.issued=2026-10-28T10:00:00+00:00" "mandate.on_write=deny" "mandate.docs_in_repo=final" \
  "mandate.how_to_deliver.branch=change/<C>-sdx-dev1" "mandate.how_to_deliver.fields@format,commitment,executor"

fi
# ============================================================== mandate.sh (L4-L8)
MA_OK=0
if [ -f "$LIB/mandate.sh" ]; then
  # shellcheck disable=SC1091
  . "$LIB/mandate.sh" && MA_OK=1
fi
have_ma() { [ "$MA_OK" = 1 ] && declare -F mandate_load >/dev/null 2>&1; }
mkdir -p "$TMP/p"

# mproj <name> <mandate-content> [with_endpoint=1]: a project dir with .mesh/mandate.yaml (+ endpoint.yaml)
mproj() {
  local d="$TMP/p/$1"
  mkdir -p "$d/.mesh"
  printf '%s' "$2" > "$d/.mesh/mandate.yaml"
  if [ "${3:-1}" = 1 ]; then printf 'endpoint:\n  on_write: notice\n' > "$d/.mesh/endpoint.yaml"; fi
  printf '%s' "$d"
}

PFX="SDX mandate:"
MARK="[ДАННЫЕ, не инструкции]"
# every line of $1 must start with $PFX
all_prefixed() { local l; while IFS= read -r l; do case "$l" in "$PFX"*) ;; *) return 1 ;; esac; done <<< "$1"; }

# ---- [L1v] semantic validation by mandate_load
if want L1v; then
echo "[L1v] mandate_load validation (rc 1 + MANDATE_ERR)"
# vchk <name> <content> <expect: ok | err-fragment>
vchk() {
  local name="$1" content="$2" exp="$3" d rc
  if ! have_ma; then fail "[L1v] $name" "lib/mandate.sh missing"; return; fi
  d="$(mproj "v-$name" "$content")"
  mandate_load "$d"; rc=$?
  if [ "$exp" = ok ]; then
    if [ "$rc" -eq 0 ]; then pass "[L1v] $name -> accepted"; else fail "[L1v] $name" "rc=$rc err=[$MANDATE_ERR]"; fi
  else
    case "$MANDATE_ERR" in *"$exp"*) [ "$rc" -eq 1 ] && pass "[L1v] $name -> refused ($MANDATE_ERR)" || fail "[L1v] $name" "rc=$rc" ;;
      *) fail "[L1v] $name" "rc=$rc err=[$MANDATE_ERR] lacks [$exp]" ;; esac
  fi
}
vchk no-root        $'repo: x\n'                                  "mandate"
vchk mandate-empty  $'mandate:\n'                                 "mandate"
vchk mandate-scalar $'mandate: x\n'                               "mandate"
vchk mandate-null   $'mandate: null\n'                            "mandate"
vchk stages-scalar  $'mandate:\n  stages: spec\n'                 "не список"
vchk stages-map     $'mandate:\n  stages:\n    a: b\n'           "не список"
vchk unknown-lint   $'mandate:\n  stages: [spec, lint]\n'         "неизвестная стадия: lint"
vchk unknown-Spec   $'mandate:\n  stages:\n  - Spec\n'            "неизвестная стадия: Spec"
vchk paths-scalar   $'mandate:\n  stages: [spec]\n  scope:\n    paths: src/**\n' "не список"
vchk parse-error    $'mandate:\n\tstages: [spec]\n'               "табуляц"
vchk ok-flow        $'mandate:\n  stages: [spec, design]\n'       ok
vchk ok-empty-stages $'mandate:\n  stages: []\n'                 ok
vchk ok-no-stages   $'mandate:\n  executor: x\n'                  ok
if have_ma; then
  mandate_load "$TMP/p/does-not-exist"; rc=$?
  [ "$rc" -eq 1 ] && [ -n "$MANDATE_ERR" ] && pass "[L1v] no mandate.yaml -> rc 1 with a reason" || fail "[L1v] no mandate.yaml" "rc=$rc err=[$MANDATE_ERR]"
  d="$(mproj v-vars $'mandate:\n  stages: [spec, verify]\n  scope:\n    paths: [src/**]\n    shared_paths: [composer.lock]\n    branches: [dev]\n')"
  mandate_load "$d"
  if [ "$(printf '%s\n' "$MANDATE_STAGES" | csv)" = "spec,verify" ] && [ "$(printf '%s\n' "$MANDATE_PATHS" | csv)" = "src/**" ] \
     && [ "$(printf '%s\n' "$MANDATE_SHARED" | csv)" = "composer.lock" ] && [ "$(printf '%s\n' "$MANDATE_BRANCHES" | csv)" = "dev" ] \
     && [ "$(printf '%s\n' "$MANDATE_DOCS" | csv)" = "docs/**" ]; then
    pass "[L1v] MANDATE_STAGES/_PATHS/_SHARED/_BRANCHES set; MANDATE_DOCS defaults to docs/**"
  else fail "[L1v] MANDATE_* variables" "stages=[$MANDATE_STAGES] paths=[$MANDATE_PATHS] shared=[$MANDATE_SHARED] br=[$MANDATE_BRANCHES] docs=[$MANDATE_DOCS]"; fi
  d="$(mproj v-docs $'mandate:\n  scope:\n    docs_paths: [docs/specs/**]\n')"
  mandate_load "$d"
  [ "$(printf '%s\n' "$MANDATE_DOCS" | csv)" = "docs/specs/**" ] && pass "[L1v] docs_paths set -> MANDATE_DOCS is the set value" || fail "[L1v] docs_paths" "docs=[$MANDATE_DOCS]"
  d="$(mproj v-docs-empty $'mandate:\n  scope:\n    docs_paths: []\n')"
  mandate_load "$d"
  [ "$(printf '%s\n' "$MANDATE_DOCS" | csv)" = "docs/**" ] && pass "[L1v] empty docs_paths -> docs/** (as DEV:386)" || fail "[L1v] empty docs_paths" "docs=[$MANDATE_DOCS]"
else
  fail "[L1v] no mandate.yaml -> rc 1 with a reason" "lib/mandate.sh missing"; fail "[L1v] MANDATE_* variables" "lib missing"
  fail "[L1v] docs_paths" "lib missing"; fail "[L1v] empty docs_paths" "lib missing"
fi

fi
# ---- [L4] stage x stages table
if want L4; then
echo "[L4] stage classes and activity: 9 stages x stages sets"
STAGES9="Discovery|Business Spec|Technical Design|Task Planning|Execution|Documentation|Verification|Deployment|Closeout"
# set name | stages literal | expected allowed flags for the nine stages (1 allowed, 0 excluded)
while IFS='|' read -r sname sflow sexp; do
  [ -z "$sname" ] && continue
  if ! have_ma; then fail "[L4] stages=$sname" "lib/mandate.sh missing"; continue; fi
  d="$(mproj "l4-$sname" "mandate:
  stages: $sflow
")"
  mandate_load "$d"
  got=""; OLDIFS="$IFS"; IFS='|'
  for st in $STAGES9; do
    IFS="$OLDIFS"
    if mandate_stage_allowed "$st"; then got="$got""1"; else got="$got""0"; fi
    IFS='|'
  done
  IFS="$OLDIFS"
  if [ "$got" = "$sexp" ]; then pass "[L4] stages=$sname -> $got"; else fail "[L4] stages=$sname" "got $got expected $sexp"; fi
done <<'TABLE'
spec|[spec]|110000101
design|[design]|001100101
execute|[execute]|000011101
verify|[verify]|000000101
empty|[]|000000101
null|null|000000101
all|[spec, design, execute, verify]|111111101
TABLE
if have_ma; then
  d="$(mproj l4-class $'mandate:\n  stages: [spec]\n')"; mandate_load "$d"
  got=""; OLDIFS="$IFS"; IFS='|'
  for st in $STAGES9; do IFS="$OLDIFS"; got="$got$(mandate_stage_class "$st") "; IFS='|'; done
  IFS="$OLDIFS"
  [ "$got" = "spec spec design design execute execute always never always " ] && pass "[L4] mandate_stage_class table" || fail "[L4] mandate_stage_class" "got [$got]"
  if ! mandate_stage_allowed "Lint" && ! mandate_stage_allowed ""; then pass "[L4] unknown stage name is never allowed (fail-closed)"; else fail "[L4] unknown stage" "allowed"; fi
else fail "[L4] mandate_stage_class table" "lib/mandate.sh missing"; fail "[L4] unknown stage name" "lib missing"; fi

fi
# ---- [L5] glob_any: static table + oracle formula DEV:67-68
if want L5; then
echo "[L5] glob_any against the reference table and the oracle"
GLOBTAB="$TMP/globtab.txt"
cat > "$GLOBTAB" <<'TABLE'
src/a.php	src/**	1
src/a/b.php	src/**	1
src	src/**	0
src/	src/**	1
docs/DECISIONS.md	docs/**	1
docs/DECISIONS.md	docs/	1
docs/x/y.md	docs/	1
docsx/a	docs/	0
README.md	*	1
a/b/c	*	1
a.txt	a.txt	1
a.txt	a.tx	0
a.txt	*.txt	1
dir/a.txt	*.txt	1
a.txt	[!b]*	1
b.txt	[!b]*	0
a.txt	[^b]*	0
^x	[^b]x	1
b.txt	[^b]*	1
a\b	a\b	1
a\x	a\\x	0
x	<empty>	0
/abs/x	<empty>	1
<empty>	<empty>	1
Src/a	src/**	0
src/a	SRC/**	0
.claude/sessions/x	.claude/**	1
.claude/sessions/x	src/**	0
abc	a?c	1
ab/c	a?/c	1
a/c	a?c	1
src/lib/a.php	src/lib/	1
src/lib	src/lib/	0
src/library/a	src/lib/	0
tests/	tests	1
tests/a	tests	1
tests	tests/*	0
a-b	a[-]b	1
a]b	a[]]b	1
[x]	[[]x]	1
a.b	a.b/	0
[ab]/x	[ab]/**	1
TABLE
tab_n=0
while IFS=$'\t' read -r gp gpat gexp; do
  [ -z "$gexp" ] && continue
  tab_n=$((tab_n + 1))
  [ "$gp" = "<empty>" ] && gp=""; [ "$gpat" = "<empty>" ] && gpat=""
  if ! have_ma; then fail "[L5] glob($gp, $gpat)" "lib/mandate.sh missing"; continue; fi
  if LC_ALL=C mandate_glob_any "$gp" "$gpat"; then r=1; else r=0; fi
  if [ "$r" = "$gexp" ]; then pass "[L5] glob_any('$gp', '$gpat') = $gexp"; else fail "[L5] glob_any('$gp', '$gpat')" "got $r expected $gexp"; fi
done < "$GLOBTAB"
[ "$tab_n" -ge 27 ] && pass "[L5] table has $tab_n >= 27 cases" || fail "[L5] table size" "$tab_n"
if have_ma; then
  if LC_ALL=C mandate_glob_any "docs/x" "src/**" "docs/**" && ! LC_ALL=C mandate_glob_any "docs/x" "src/**" "lib/**" && ! LC_ALL=C mandate_glob_any "docs/x"; then
    pass "[L5] mandate_glob_any: any-of semantics (and no patterns -> no match)"
  else fail "[L5] mandate_glob_any any-of" "unexpected"; fi
else fail "[L5] mandate_glob_any any-of" "lib/mandate.sh missing"; fi
# oracle: the reference formula (dev.py glob_any) over the same table; INFO-skip when python3/PyYAML-free python is absent
if command -v python3 >/dev/null 2>&1; then
  ORACLE='
import sys, os, fnmatch
bad = 0
for l in sys.stdin.read().split("\n"):
    if not l: continue
    f, p, e = l.split("\t")
    f = "" if f == "<empty>" else f
    p = "" if p == "<empty>" else p
    r = fnmatch.fnmatch(f, p) or fnmatch.fnmatch(f, p.rstrip("/") + "/*") or f.startswith(p.rstrip("*").rstrip("/") + "/")
    if os.environ.get("WRONG"): r = fnmatch.fnmatch(f, p)
    if int(r) != int(e): bad += 1; print("DIVERGE", f, p, e, int(r))
print("BAD", bad)'
  o1="$(PYTHONDONTWRITEBYTECODE=1 python3 -c "$ORACLE" < "$GLOBTAB" 2>&1 | tail -1)"
  [ "$o1" = "BAD 0" ] && pass "[L5] oracle: the static table agrees with the reference formula (DEV:67-68)" || fail "[L5] oracle" "$o1"
  o2="$(WRONG=1 PYTHONDONTWRITEBYTECODE=1 python3 -c "$ORACLE" < "$GLOBTAB" 2>&1 | tail -1)"
  [ "$o2" != "BAD 0" ] && pass "[L5] oracle red side: a substituted formula diverges from the table ($o2)" || fail "[L5] oracle red side" "wrong formula not detected"
else
  info "[L5] oracle skipped: python3 absent"
fi

fi
# ---- [L6] mandate_expired
if want L6; then
echo "[L6] mandate_expired"
# echk <name> <valid_until yaml fragment or empty> <today or empty> <expected rc: 0 expired | 1 not>
echk() {
  local name="$1" frag="$2" today="$3" exp="$4" d rc
  if ! have_ma; then fail "[L6] $name" "lib/mandate.sh missing"; return; fi
  d="$(mproj "l6-$name" "mandate:
  stages: [spec]
$frag")"
  mandate_load "$d"
  if [ -n "$today" ]; then SDX_MANDATE_TODAY="$today" mandate_expired; rc=$?; else mandate_expired; rc=$?; fi
  [ "$rc" = "$exp" ] && pass "[L6] $name -> rc $rc" || fail "[L6] $name" "rc=$rc expected $exp"
}
echk past          "  valid_until: '2026-10-01'" 2026-10-28 0
echk past-unquoted "  valid_until: 2026-10-27"   2026-10-28 0
echk today         "  valid_until: '2026-10-28'" 2026-10-28 1
echk future        "  valid_until: '2026-12-31'" 2026-10-28 1
echk empty         "  valid_until:"              2026-10-28 1
echk absent        ""                             2026-10-28 1
echk not-a-date    "  valid_until: soon"         2026-10-28 1
echk short-date    "  valid_until: '2026-1-5'"   2026-10-28 1
echk real-past     "  valid_until: '2000-01-01'" "" 0
echk real-future   "  valid_until: '2999-01-01'" "" 1

fi
# ---- [L7] mandate_mode
if want L7; then
echo "[L7] mandate_mode"
mmchk() { # name with_mandate with_endpoint expected
  local name="$1" d="$TMP/p/l7-$1" got
  mkdir -p "$d/.mesh"
  [ "$2" = 1 ] && printf 'mandate:\n  stages: [spec]\n' > "$d/.mesh/mandate.yaml"
  [ "$3" = 1 ] && printf 'on_write: deny\n' > "$d/.mesh/endpoint.yaml"
  if ! have_ma; then fail "[L7] $name" "lib/mandate.sh missing"; return; fi
  got="$(mandate_mode "$d")"
  [ "$got" = "$4" ] && pass "[L7] $name -> $got" || fail "[L7] $name" "got [$got] expected [$4]"
}
mmchk both 1 1 on
mmchk mandate-only 1 0 orphan
mmchk endpoint-only 0 1 none
mmchk nothing 0 0 none
if have_ma; then
  [ "$(mandate_mode "$TMP/p/no-such-dir")" = none ] && pass "[L7] absent project dir -> none" || fail "[L7] absent dir" "not none"
else fail "[L7] absent project dir" "lib/mandate.sh missing"; fi

fi
# ---- [L7r] mandate_raw_on_write (same rule as mo-hook.sh mode_re)
if want L7r; then
echo "[L7r] mandate_raw_on_write"
rchk() { # name content expected
  local f="$TMP/p/raw-$1.yaml" got
  if [ "$2" != "<nofile>" ]; then printf '%s' "$2" > "$f"; else f="$TMP/p/raw-absent.yaml"; fi
  if ! have_ma; then fail "[L7r] $1" "lib/mandate.sh missing"; return; fi
  got="$(mandate_raw_on_write "$f")"
  [ "$got" = "$3" ] && pass "[L7r] $1 -> $got" || fail "[L7r] $1" "got [$got] expected [$3]"
}
rchk deny       $'on_write: deny\n'                                  deny
rchk Deny-quoted $'mandate:\n  on_write: \'Deny\'\n'                 deny
rchk DENY-dq    $'mandate:\n  stages: [spec]\n  on_write: "DENY"\n' deny
rchk notice     $'on_write: notice\n'                                notice
rchk other      $'on_write: warn\n'                                  notice
rchk no-key     $'mandate:\n  stages: [spec]\n'                      "—"
rchk no-file    "<nofile>"                                           "—"

fi
# ---- [L8] mandate_report
if want L8; then
echo "[L8] mandate_report: untrusted values, warnings, orphan line"
if have_ma; then
  LONG="$(awk 'BEGIN{for(i=0;i<5000;i++)printf "y"}')"
  hostile=$'mandate:\n  executor: "ev\\"il\\\\x"\n  digest: d\033[31mred\n  valid_until: \'2999-12-31\'\n  delivery: '"$LONG"$'\n  history: "a\\nb"\n  stages: [spec, execute]\n  on_write: deny\n  scope:\n    paths: [p01, p02, p03, p04, p05, p06, p07, p08, p09, p10, p11, p12, p13, p14, p15, p16, p17, p18, p19, p20]\n    branches: [dev]\n'
  d="$(mproj l8-hostile "$hostile")"
  out="$(SDX_MANDATE_TODAY=2026-10-28 mandate_report "$d" "$PFX")"; rc=$?
  [ "$rc" -eq 0 ] && pass "[L8] hostile mandate: rc 0" || fail "[L8] hostile rc" "rc=$rc"
  if all_prefixed "$out"; then pass "[L8] every output line starts with the prefix"; else fail "[L8] prefix" "a line without prefix: $(printf '%s\n' "$out" | grep -v -F "$PFX" | head -2)"; fi
  if ! printf '%s' "$out" | grep -q $'\033'; then pass "[L8] no ESC in the output"; else fail "[L8] ESC" "ESC leaked"; fi
  n_mark="$(printf '%s\n' "$out" | grep -c -F "$PFX  $MARK ")"
  [ "$n_mark" -eq 3 ] && pass "[L8] exactly three field lines, each '$PFX  $MARK ...'" || fail "[L8] field lines" "count=$n_mark"
  l1="$(printf '%s\n' "$out" | grep -F "$MARK" | sed -n 1p)"; l2="$(printf '%s\n' "$out" | grep -F "$MARK" | sed -n 2p)"; l3="$(printf '%s\n' "$out" | grep -F "$MARK" | sed -n 3p)"
  case "$l1" in *'executor="ev\"il\\x"'*) pass "[L8] quote and backslash in a value are escaped" ;; *) fail "[L8] escaping" "line1=[$l1]" ;; esac
  case "$l1" in *'history="a b"'*) pass "[L8] a newline escape inside quotes collapses to a space" ;; *) fail "[L8] newline value" "line1=[$l1]" ;; esac
  case "$l1" in *'docs_in_repo=unset'*) pass "[L8] absent field prints unset" ;; *) fail "[L8] unset" "line1=[$l1]" ;; esac
  case "$l2" in *'stages=["spec", "execute"]'*'on_write="deny"'*) pass "[L8] stages and on_write on the second line" ;; *) fail "[L8] line2" "[$l2]" ;; esac
  case "$l3" in *'…(+12)'*) pass "[L8] 20 elements -> first 8 and …(+12)" ;; *) fail "[L8] …(+N)" "line3=[$l3]" ;; esac
  long_ok=1; while IFS= read -r l; do [ "${#l}" -le 480 ] || long_ok=0; done <<< "$out"
  [ "$long_ok" = 1 ] && pass "[L8] no line exceeds 480 chars (5000-char value)" || fail "[L8] 480 limit" "a line is longer"
  # no on_write when not set
  d="$(mproj l8-noonw $'mandate:\n  stages: [spec]\n')"
  out="$(mandate_report "$d" "$PFX")"
  case "$out" in *on_write*) fail "[L8] on_write omitted when unset" "present" ;; *) pass "[L8] on_write omitted when unset" ;; esac
  case "$out" in *'docs_paths=["docs/**"]'*) pass "[L8] default docs_paths shown as docs/**" ;; *) fail "[L8] docs default" "$out" ;; esac
  # long values hit the 480 limit with an ellipsis
  W="$(awk 'BEGIN{for(i=0;i<150;i++)printf "w"}')"
  d="$(mproj l8-480 "mandate:
  scope:
    paths: [$W, $W]
    shared_paths: [$W, $W]
    docs_paths: [$W]
    branches: [$W]
")"
  out="$(mandate_report "$d" "$PFX")"
  l3="$(printf '%s\n' "$out" | grep -F "$MARK" | sed -n 3p)"
  if [ "${#l3}" -le 480 ] && [ "${#l3}" -ge 470 ] && [ "${l3%…}" != "$l3" ]; then pass "[L8] over-long field line is cut at 480 with an ellipsis (len ${#l3})"
  else fail "[L8] 480 cut" "len=${#l3} tail=[${l3: -3}]"; fi
else
  for t in rc prefix ESC field-lines escaping newline unset line2 more 480 on_write docs-default 480-cut; do fail "[L8] $t" "lib/mandate.sh missing"; done
fi

fi
if want L8w; then
echo "[L8w] area and expiry warnings (К-1: per directory)"
nwarn() { printf '%s\n' "$1" | grep -c -F "область мандата не покрывает"; }
if have_ma; then
  d="$(mproj w-narrow $'mandate:\n  scope:\n    paths: [src/**]\n')"
  out="$(mandate_report "$d" "$PFX")"
  if [ "$(nwarn "$out")" = 1 ] && printf '%s\n' "$out" | grep -F "область мандата не покрывает" | grep -q -F ".claude/sessions/" \
     && ! printf '%s\n' "$out" | grep -F "область мандата не покрывает" | grep -q -F "docs/"; then pass "[L8w] paths=[src/**]: warns about .claude/sessions/ only (docs/** default covers docs/)"
  else fail "[L8w] sessions only" "n=$(nwarn "$out")"; fi
  d="$(mproj w-both $'mandate:\n  scope:\n    paths: [src/**]\n    docs_paths: [other/**]\n')"
  out="$(mandate_report "$d" "$PFX")"
  if [ "$(nwarn "$out")" = 2 ] && printf '%s\n' "$out" | grep -F "область мандата не покрывает" | grep -q -F ".claude/sessions/" \
     && printf '%s\n' "$out" | grep -F "область мандата не покрывает" | grep -q "docs/"; then pass "[L8w] both uncovered -> two separate warning lines"
  else fail "[L8w] both" "n=$(nwarn "$out")"; fi
  d="$(mproj w-docs-only $'mandate:\n  scope:\n    paths: [.claude/**]\n    docs_paths: [other/**]\n')"
  out="$(mandate_report "$d" "$PFX")"
  if [ "$(nwarn "$out")" = 1 ] && printf '%s\n' "$out" | grep -F "область мандата не покрывает" | grep -q "docs/"; then pass "[L8w] docs/ uncovered only -> one line about docs/"
  else fail "[L8w] docs only" "n=$(nwarn "$out")"; fi
  d="$(mproj w-covered $'mandate:\n  scope:\n    paths: [src/**, .claude/**]\n')"
  out="$(mandate_report "$d" "$PFX")"
  [ "$(nwarn "$out")" = 0 ] && pass "[L8w] covered -> no area warning" || fail "[L8w] covered" "n=$(nwarn "$out")"
  d="$(mproj w-shared $'mandate:\n  scope:\n    paths: [src/**]\n    shared_paths: [.claude/sessions/**]\n')"
  out="$(mandate_report "$d" "$PFX")"
  [ "$(nwarn "$out")" = 0 ] && pass "[L8w] shared_paths counts towards coverage" || fail "[L8w] shared" "n=$(nwarn "$out")"
  d="$(mproj w-empty-paths $'mandate:\n  scope:\n    paths: []\n')"
  out="$(mandate_report "$d" "$PFX")"
  [ "$(nwarn "$out")" = 0 ] && pass "[L8w] empty scope.paths -> no area warning (no restriction)" || fail "[L8w] empty paths" "n=$(nwarn "$out")"
  d="$(mproj w-no-scope $'mandate:\n  stages: [spec]\n')"
  out="$(mandate_report "$d" "$PFX")"
  [ "$(nwarn "$out")" = 0 ] && pass "[L8w] no scope at all -> no area warning" || fail "[L8w] no scope" "n=$(nwarn "$out")"
  # expiry
  d="$(mproj w-expired $'mandate:\n  valid_until: \'2020-01-01\'\n')"
  out="$(SDX_MANDATE_TODAY=2026-10-28 mandate_report "$d" "$PFX")"
  case "$out" in *"мандат истёк (valid_until="*"2020-01-01"*) pass "[L8w] expired mandate -> expiry warning with the date" ;; *) fail "[L8w] expiry" "$out" ;; esac
  all_prefixed "$out" && pass "[L8w] expiry warning carries the prefix" || fail "[L8w] expiry prefix" "no prefix"
  for v in "valid_until: ''" "valid_until: soon"; do
    d="$(mproj "w-exp-$(printf '%s' "$v" | tr -c 'a-z' '_')" "mandate:
  $v
")"
    out="$(SDX_MANDATE_TODAY=2026-10-28 mandate_report "$d" "$PFX")"
    case "$out" in *"мандат истёк"*) fail "[L8w] '$v' -> no expiry warning" "warned" ;; *) pass "[L8w] '$v' -> no expiry warning" ;; esac
  done
  # load error: exactly one line, fail-closed text
  d="$(mproj w-broken $'mandate:\n\tstages: [spec]\n')"
  out="$(mandate_report "$d" "$PFX")"; rc=$?
  if [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] && all_prefixed "$out" \
     && printf '%s' "$out" | grep -q -F "не разобран" && printf '%s' "$out" | grep -q -F "табуляц"; then pass "[L8w] unreadable mandate -> one line with the reason, rc 0"
  else fail "[L8w] load error line" "rc=$rc out=[$out]"; fi
  # orphan line
  out="$(mandate_orphan_line "$PFX")"
  if [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] && all_prefixed "$out" && printf '%s' "$out" | grep -q "endpoint.yaml" && printf '%s' "$out" | grep -q "не действует"; then
    pass "[L8w] mandate_orphan_line: exactly one prefixed line naming endpoint.yaml"
  else fail "[L8w] orphan line" "[$out]"; fi
else
  for t in sessions-only both docs-only covered shared empty-paths no-scope expiry expiry-prefix expiry-empty expiry-notdate load-error orphan; do fail "[L8w] $t" "lib/mandate.sh missing"; done
fi

fi
# ============================================================== [L9] portability
if want L9; then
echo "[L9] portability (BUG-010) and no-python invariant (REQ-MAND-33)"
FORBID='tim''eout|map''file|declare -''A|[$]\{[a-zA-Z_]+,,\}|%''N|readlink -''f|real''path'
for f in miniyaml.sh mandate.sh; do
  if [ ! -f "$LIB/$f" ]; then fail "[L9] lib/$f portability" "file missing"; continue; fi
  if grep -nE "$FORBID" "$LIB/$f" >/dev/null 2>&1; then fail "[L9] lib/$f portability" "forbidden: $(grep -nE "$FORBID" "$LIB/$f" | head -3)"
  else pass "[L9] lib/$f: no GNU-only/bash4-only constructs"; fi
done
if [ -f "$LIB/miniyaml.sh" ]; then
  cp "$LIB/miniyaml.sh" "$TMP/port-mut.sh"; printf 'ma''pfile -t xs <<<""\n' >> "$TMP/port-mut.sh"
  if ! cmp -s "$LIB/miniyaml.sh" "$TMP/port-mut.sh" && grep -qE "$FORBID" "$TMP/port-mut.sh"; then pass "[L9] red side: the same grep flags a mutant with a bash4 construct"
  else fail "[L9] red side of the portability grep" "mutant not flagged"; fi
else fail "[L9] red side of the portability grep" "lib/miniyaml.sh missing"; fi
if [ -f "$LIB/miniyaml.sh" ]; then
  if grep -nE '\beval\b' "$LIB/miniyaml.sh" >/dev/null 2>&1; then fail "[L9] miniyaml.sh has no eval" "found: $(grep -nE '\beval\b' "$LIB/miniyaml.sh" | head -2)"
  else pass "[L9] miniyaml.sh has no eval (mandate values are never executed)"; fi
else fail "[L9] miniyaml.sh has no eval" "file missing"; fi
PYNAME='py''thon'
hits="$(grep -nE "$PYNAME" "$LIB"/*.sh "$SCRIPT_DIR/sdx-stage.sh" 2>/dev/null)"
if [ -z "$hits" ] && [ -f "$LIB/miniyaml.sh" ] && [ -f "$SCRIPT_DIR/sdx-stage.sh" ]; then pass "[L9] no python in lib/*.sh and sdx-stage.sh (REQ-MAND-33)"
else fail "[L9] no python in lib/*.sh and sdx-stage.sh" "${hits:-lib/miniyaml.sh missing}"; fi

fi

# ============================================================== [P] mandate_fnmatch (FEAT-017, REQ-PKG-11 (e))
if want P; then
echo "[P] mandate_fnmatch: pure fnmatch (scope.branches is checked by the node with fnmatch only, DEV:374-375)"
FNTAB="$TMP/fntab.txt"
cat > "$FNTAB" <<'TABLE'
change/C-ex1	change/*	1
feat/x	change/*	0
change/x	change	0
change/a/b	change/*	1
change/	change/*	1
changeX	change/*	0
change-x	change*	1
Change/x	change/*	0
change/x	CHANGE/*	0
a	[!x]	1
x	[!x]	0
a	[^x]	0
^	[^x]	1
x	[^x]	1
a\b	a\b	1
a\x	a\\x	0
abc	a?c	1
x/y	x?y	1
x	<empty>	0
<empty>	<empty>	1
<empty>	*	1
a.txt	*.txt	1
TABLE
fn_n=0
while IFS=$'\t' read -r fs fpat fexp; do
  [ -z "$fexp" ] && continue
  fn_n=$((fn_n + 1))
  [ "$fs" = "<empty>" ] && fs=""; [ "$fpat" = "<empty>" ] && fpat=""
  if ! have_ma || ! declare -F mandate_fnmatch >/dev/null 2>&1; then fail "[P] fnmatch($fs, $fpat)" "mandate_fnmatch undefined"; continue; fi
  if LC_ALL=C mandate_fnmatch "$fs" "$fpat"; then r=1; else r=0; fi
  if [ "$r" = "$fexp" ]; then pass "[P] fnmatch('$fs', '$fpat') = $fexp"; else fail "[P] fnmatch('$fs', '$fpat')" "got $r expected $fexp"; fi
done < "$FNTAB"
[ "$fn_n" -ge 15 ] && pass "[P] table has $fn_n >= 15 cases" || fail "[P] table size" "$fn_n"
# the discriminator: the prefix rule of glob_any (DEV:67-68) makes 'change' cover 'change/x'; branch masks must not
if have_ma && declare -F mandate_fnmatch >/dev/null 2>&1; then
  if mandate_glob_one "change/x" "change" && ! mandate_fnmatch "change/x" "change"; then pass "[P] discriminator: glob_one('change/x','change') holds, fnmatch does not"
  else fail "[P] discriminator" "glob_one and fnmatch must differ on ('change/x','change')"; fi
  mf_lc="$(LC_ALL=en_US.UTF-8 bash -c '. "$1/mandate.sh"; mandate_fnmatch "[" "[[]" && echo y' _ "$LIB" 2>/dev/null)"
  [ "$mf_lc" = y ] && pass "[P] result does not depend on the caller locale" || info "[P] locale probe: en_US.UTF-8 unavailable or differing ('$mf_lc')"
else fail "[P] discriminator" "mandate_fnmatch undefined"; fi
# oracle: python's fnmatch over the same table (INFO-skip without python3)
if command -v python3 >/dev/null 2>&1; then
  FNORACLE='
import sys, os, fnmatch
bad = 0
for l in sys.stdin.read().split("\n"):
    if not l: continue
    f, p, e = l.split("\t")
    f = "" if f == "<empty>" else f
    p = "" if p == "<empty>" else p
    r = fnmatch.fnmatchcase(f, p) if not os.environ.get("WRONG") else fnmatch.fnmatch(f, p) or f.startswith(p.rstrip("*").rstrip("/") + "/")
    if int(r) != int(e): bad += 1; print("DIVERGE", f, p, e, int(r))
print("BAD", bad)'
  o1="$(PYTHONDONTWRITEBYTECODE=1 python3 -I -c "$FNORACLE" < "$FNTAB" 2>&1 | tail -1)"
  [ "$o1" = "BAD 0" ] && pass "[P] oracle: the table agrees with python fnmatch" || fail "[P] oracle" "$o1"
  o2="$(WRONG=1 PYTHONDONTWRITEBYTECODE=1 python3 -I -c "$FNORACLE" < "$FNTAB" 2>&1 | tail -1)"
  [ "$o2" != "BAD 0" ] && pass "[P] oracle red side: the prefix-rule formula diverges ($o2)" || fail "[P] oracle red side" "wrong formula not detected"
else info "[P] oracle skipped: python3 absent"; fi
fi

# ============================================================== [L10] lib/pr-lib.sh: pure functions (FEAT-017)
if want L10; then
echo "[L10] pr-lib: identifiers, cleaning, secrets, sha256, URL whitelist, hosting; portability"
PR_OK=0
if [ -f "$LIB/pr-lib.sh" ]; then
  # shellcheck disable=SC1091
  . "$LIB/pr-lib.sh" && PR_OK=1
fi
have_pr() { [ "$PR_OK" = 1 ] && declare -F pr_valid_id >/dev/null 2>&1; }
# l10 <label> <expect-rc> <function> <args...>: run a boolean function and compare its rc
l10() {
  local label="$1" exp="$2" fn="$3" rc; shift 3
  if ! have_pr || ! declare -F "$fn" >/dev/null 2>&1; then fail "[L10] $label" "lib/pr-lib.sh or $fn missing"; return; fi
  "$fn" "$@"; rc=$?
  if [ "$rc" = "$exp" ]; then pass "[L10] $label"; else fail "[L10] $label" "$fn rc=$rc expected $exp"; fi
}
# pr_valid_id: valid
l10 "valid_id C-ACME-001" 0 pr_valid_id "C-ACME-001"
l10 "valid_id ex1" 0 pr_valid_id "ex1"
l10 "valid_id 64 chars" 0 pr_valid_id "$(printf 'a%.0s' $(seq 1 64))"
l10 "valid_id a.b_c-d" 0 pr_valid_id "a.b_c-d"
# pr_valid_id: invalid
l10 "valid_id empty" 1 pr_valid_id ""
l10 "valid_id client-harness:kitgroup" 1 pr_valid_id "client-harness:kitgroup"
l10 "valid_id .." 1 pr_valid_id ".."
l10 "valid_id a..b" 1 pr_valid_id "a..b"
l10 "valid_id leading -" 1 pr_valid_id "-x"
l10 "valid_id leading ." 1 pr_valid_id ".x"
l10 "valid_id space" 1 pr_valid_id "a b"
l10 "valid_id slash" 1 pr_valid_id "a/b"
l10 "valid_id 65 chars" 1 pr_valid_id "$(printf 'a%.0s' $(seq 1 65))"
l10 "valid_id trailing ." 1 pr_valid_id "abc."
l10 "valid_id trailing .lock" 1 pr_valid_id "abc.lock"
l10 "valid_id unicode" 1 pr_valid_id "жук"
l10 "valid_id newline" 1 pr_valid_id $'a\nb'
# pr_clean: PR_CLEAN <- cleaned value
l10c() {  # <label> <input> <expected> [max]
  if ! have_pr || ! declare -F pr_clean >/dev/null 2>&1; then fail "[L10] clean $1" "pr_clean missing"; return; fi
  PR_CLEAN="<unset>"; pr_clean "$2" ${4:+"$4"}
  if [ "$PR_CLEAN" = "$3" ]; then pass "[L10] clean $1"; else fail "[L10] clean $1" "got [$PR_CLEAN] expected [$3]"; fi
}
l10c "newline and tab become spaces" $'a\nb\tc' "a b c"
l10c "ESC is cut, the rest stays" $'a\033[31mb' "a[31mb"
l10c "C0 and CR are cut" $'a\001b\rc' "abc"
l10c "DEL is cut" $'a\177b' "ab"
l10c "U+2028 is cut" $'a\342\200\250b' "ab"
l10c "U+2029 is cut" $'a\342\200\251b' "ab"
l10c "U+0085 is cut" $'a\302\205b' "ab"
l10c "trim" "   x y  " "x y"
l10c "trailing newline" $'x\n' "x"
l10c "plain unicode survives" "Фича ж" "Фича ж"
l10c "default cut to 200" "$(printf 'a%.0s' $(seq 1 300))" "$(printf 'a%.0s' $(seq 1 200))"
l10c "explicit max" "abcdefghij" "abcde" 5
l10c "backtick and dollar are data" 'a`b$(c)' 'a`b$(c)'
if have_pr && declare -F pr_clean >/dev/null 2>&1; then
  pr_clean "$(printf 'ж%.0s' $(seq 1 150))" 101
  if printf '%s' "$PR_CLEAN" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 && [ "${#PR_CLEAN}" -le 101 ]; then pass "[L10] clean: a cut multibyte value is still valid UTF-8"
  else fail "[L10] clean multibyte cut" "invalid UTF-8 or too long"; fi
else fail "[L10] clean multibyte cut" "pr_clean missing"; fi
# pr_has_secret
l10 "secret: password: x" 0 pr_has_secret "password: x"
l10 "secret: \"token\"=" 0 pr_has_secret '"token"=abc'
l10 "secret: api_key:" 0 pr_has_secret "api_key: 1"
l10 "secret: client-secret :" 0 pr_has_secret "client-secret : v"
l10 "secret: PASSWD= (case)" 0 pr_has_secret "PASSWD=1"
l10 "secret: second line" 0 pr_has_secret $'fine\nsecret: v'
l10 "no secret: plain text" 1 pr_has_secret "Add the login form"
l10 "no secret: tokenizer without : or =" 1 pr_has_secret "fix the tokenizer module"
l10 "no secret: empty" 1 pr_has_secret ""
# pr_sha256 (stdin -> hex)
if have_pr && declare -F pr_sha256 >/dev/null 2>&1; then
  h="$(printf 'abc' | pr_sha256)"
  [ "$h" = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" ] && pass "[L10] sha256 of 'abc'" || fail "[L10] sha256 of 'abc'" "got [$h]"
else fail "[L10] sha256 of 'abc'" "pr_sha256 missing"; fi
# pr_url_ok
for u in "ssh://git@host/srv/app.git" "https://h/o/r.git" "http://h/o/r.git" "file:///srv/app.git" "git@host:o/r.git" "/srv/git/app.git" "ssh://dobro/srv/app.git" "https://u:p@h/x.git"; do
  l10 "url_ok accepts $u" 0 pr_url_ok "$u"
done
for u in "ext::sh -c x" "ext::sh" "fd::1" "transport::x" "-oProxyCommand=x" "https://h/a b" "" "ftp://h/x" "ssh://-oProxyCommand=x/y" "--upload-pack=x" $'https://h/a\nb' "git@-host:x" "relative/path" "FILE:x"; do
  l10 "url_ok refuses [$u]" 1 pr_url_ok "$u"
done
# pr_url_show: credentials are removed from displayed URLs
l10u() {  # <label> <input> <expected>
  if ! have_pr || ! declare -F pr_url_show >/dev/null 2>&1; then fail "[L10] url_show $1" "pr_url_show missing"; return; fi
  PR_URLS="<unset>"; pr_url_show "$2"
  if [ "$PR_URLS" = "$3" ]; then pass "[L10] url_show $1"; else fail "[L10] url_show $1" "got [$PR_URLS] expected [$3]"; fi
}
l10u "user:pass removed" "https://u:p@h/x.git" "https://h/x.git"
l10u "https token-as-user removed" "https://TOKEN@h/x.git" "https://h/x.git"
l10u "ssh user stays" "ssh://git@h/x.git" "ssh://git@h/x.git"
l10u "ssh user:pass removed" "ssh://git:pw@h/x.git" "ssh://h/x.git"
l10u "scp form untouched" "git@h:o/r" "git@h:o/r"
l10u "local path untouched" "/srv/git/app.git" "/srv/git/app.git"
l10u "no credentials untouched" "https://h/x.git" "https://h/x.git"
# pr_hosting <url> [hint] -> PR_HOSTING
l10h() {  # <label> <expected> <url> [hint]
  if ! have_pr || ! declare -F pr_hosting >/dev/null 2>&1; then fail "[L10] hosting $1" "pr_hosting missing"; return; fi
  PR_HOSTING="<unset>"; pr_hosting "$3" ${4:+"$4"}
  if [ "$PR_HOSTING" = "$2" ]; then pass "[L10] hosting $1"; else fail "[L10] hosting $1" "got [$PR_HOSTING] expected [$2]"; fi
}
l10h "github https" github "https://github.com/o/r.git"
l10h "github scp" github "git@github.com:o/r.git"
l10h "github ssh" github "ssh://git@github.com/o/r.git"
l10h "local path is bare" bare "/srv/git/app.git"
l10h "other host is bare" bare "https://git.example.com/o/r.git"
l10h "look-alike host is bare" bare "https://evilgithub.com/o/r.git"
l10h "hint bare beats github.com" bare "https://github.com/o/r.git" bare
l10h "hint github beats a local path" github "/srv/git/app.git" github
l10h "unknown hint is ignored" github "https://github.com/o/r.git" gitlab
# portability (BUG-010) and no python/eval in pr-lib.sh
FORBID10='tim''eout|map''file|declare -''A|[$]\{[a-zA-Z_]+,,\}|%''N|readlink -''f|real''path'
if [ -f "$LIB/pr-lib.sh" ]; then
  if grep -nE "$FORBID10" "$LIB/pr-lib.sh" >/dev/null 2>&1; then fail "[L10] lib/pr-lib.sh portability" "forbidden: $(grep -nE "$FORBID10" "$LIB/pr-lib.sh" | head -3)"
  else pass "[L10] lib/pr-lib.sh: no GNU-only/bash4-only constructs"; fi
  cp "$LIB/pr-lib.sh" "$TMP/port-mut10.sh"; printf 'ma''pfile -t xs <<<""\n' >> "$TMP/port-mut10.sh"
  if ! cmp -s "$LIB/pr-lib.sh" "$TMP/port-mut10.sh" && grep -qE "$FORBID10" "$TMP/port-mut10.sh"; then pass "[L10] red side: the same grep flags a pr-lib mutant with a bash4 construct"
  else fail "[L10] red side of the pr-lib portability grep" "mutant not flagged"; fi
  if grep -nE 'py''thon|\bev''al\b' "$LIB/pr-lib.sh" >/dev/null 2>&1; then fail "[L10] pr-lib.sh has no python and no eval" "found: $(grep -nE 'py''thon|\bev''al\b' "$LIB/pr-lib.sh" | head -2)"
  else pass "[L10] pr-lib.sh has no python and no eval"; fi
else
  fail "[L10] lib/pr-lib.sh portability" "file missing"; fail "[L10] red side of the pr-lib portability grep" "file missing"; fail "[L10] pr-lib.sh has no python and no eval" "file missing"
fi
fi

# ============================================================== [L11] lib/pr-lib.sh: git-dependent functions on a mini repository
if want L11; then
echo "[L11] pr-lib on a mini repository: session history, order snapshot, base, files, scope, registry, resolve"
L11_OK=0
if [ -f "$LIB/pr-lib.sh" ]; then
  # shellcheck disable=SC1091
  . "$LIB/pr-lib.sh" && L11_OK=1
fi
l11_have() { [ "$L11_OK" = 1 ] && declare -F "$1" >/dev/null 2>&1; }
# hermetic git: no user/system config leaks in (diff.renames, core.quotepath, hooks...), fixed identity
printf '[user]\n\tname = t\n\temail = t@t\n[init]\n\tdefaultBranch = dev\n[core]\n\thooksPath = /dev/null\n[commit]\n\tgpgsign = false\n' > "$TMP/gitcfg11"
export GIT_CONFIG_GLOBAL="$TMP/gitcfg11" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$TMP/g11"
R="$TMP/g11/repo"
MANDATE11=$'mandate:\n  repo: app\n  stages:\n  - spec\n  - design\n  - execute\n  - verify\n  scope:\n    paths:\n    - src/mod1/**\n    shared_paths:\n    - package-lock.json\n    docs_paths:\n    - docs/**\n    branches:\n    - change/*\n  delivery: pr\n  history: executor\n  docs_in_repo: final\n  valid_until: \'2099-01-01\'\n  on_write: deny\n  executor: ex1\n  digest: \'123456789012\'\n  format: 1\n'
ORDER11=$'order:\n  format: 1\n  source: "msg"\n  source_ref: "m-1"\n  commitment:\n    id: "C-ACME-001"\n    kind: "change"\n    title: "Feature mod1"\n    requirements: "Do it"\n    due: "2026-12-01"\n    creditor: "acme"\n  executor: "ex1"\n  mandate_digest: "123456789012"\n  repo:\n    id: "app"\n    url: "ssh://dobro/srv/app.git"\n    base: "dev"\n    hosting: "github"\n  deliver:\n    branch: "change/C-ACME-001-ex1"\n    delivery: "pr"\n'
(
  set -e
  git init -q "$R"; cd "$R"
  mkdir -p docs src/mod1 src/core
  printf 'r\n' > README.md; printf '# Decisions\n\n## ADR-001. Base\n' > docs/DECISIONS.md; printf 'a=1\n' > src/mod1/a.js; printf '{}\n' > package-lock.json
  git add -A; git commit -q -m base
  git checkout -q -b sdx/s2; mkdir -p .claude/sessions/s2; printf '{"stage":"Closeout"}\n' > .claude/sessions/s2/session_state.json
  git add -A; git commit -q -m "s2 session only"
  git checkout -q dev; git checkout -q -b sdx/s1
  mkdir -p .claude/sessions/s1
  printf '{"stage":"Closeout"}\n' > .claude/sessions/s1/session_state.json
  printf '%s' "$ORDER11" > .claude/sessions/s1/order.yaml
  printf 'Итог: PASS\n' > .claude/sessions/s1/verification_report.md
  git add -A; git commit -q -m "s1 session"
  printf 'a=2\n' >> src/mod1/a.js; printf 'x\n' >> package-lock.json; printf '\n## ADR-099. New decision\n' >> docs/DECISIONS.md
  mkdir -p docs/specs; printf 'spec\n' > docs/specs/mod1.md; printf 'спека\n' > "docs/спека.md"; printf 'b=1\n' > src/core/b.js
  git add -A; git commit -q -m "s1 code"
  git rm -r -q .claude/sessions/s1; git commit -q -m "s1 close"
  git init -q --bare "$TMP/g11/remote.git"; git remote add origin "$TMP/g11/remote.git"; git push -q origin dev
  git fetch -q origin
  mkdir -p .mesh; printf '%s' "$MANDATE11" > .mesh/mandate.yaml; printf 'endpoint:\n  on_write: notice\n' > .mesh/endpoint.yaml
) >/dev/null 2>&1
L11_BUILT=0; [ -n "$(git -C "$R" rev-parse --verify -q refs/heads/sdx/s1 2>/dev/null)" ] && L11_BUILT=1
[ "$L11_BUILT" = 1 ] && pass "[L11] mini repository built" || fail "[L11] mini repository" "fixture build failed"
l11eq() {  # <label> <got> <expected>
  if [ "$2" = "$3" ]; then pass "[L11] $1"; else fail "[L11] $1" "got [$2] expected [$3]"; fi
}
l11rc() {  # <label> <got-rc> <expected-rc>
  if [ "$2" = "$3" ]; then pass "[L11] $1"; else fail "[L11] $1" "rc=$2 expected $3"; fi
}
SHA_S1_PRE="$(git -C "$R" rev-parse --verify -q 'refs/heads/sdx/s1~1' 2>/dev/null)"   # last commit that still has the session directory
SHA_S2="$(git -C "$R" rev-parse --verify -q refs/heads/sdx/s2 2>/dev/null)"
SHA_DEV="$(git -C "$R" rev-parse --verify -q refs/heads/dev 2>/dev/null)"

# ---- pr_session_rev / pr_sess_cat
if l11_have pr_session_rev; then
  pr_session_rev "$R" s1; rc=$?; l11rc "session_rev s1 (directory removed at tip) rc" "$rc" 0
  l11eq "session_rev s1 -> parent of the removing commit" "$PR_SESS_REV" "$SHA_S1_PRE"   # PKG-SESSREV
  pr_session_rev "$R" s2; rc=$?; l11rc "session_rev s2 (directory at the tip) rc" "$rc" 0
  l11eq "session_rev s2 -> tip" "$PR_SESS_REV" "$SHA_S2"
  pr_session_rev "$R" nosuch; rc=$?; l11rc "session_rev for an unknown session rc" "$rc" 1
  pr_session_rev "$R" "../x"; rc=$?; l11rc "session_rev refuses a hostile sid" "$rc" 1
else for t in "s1 rc" "s1 value" "s2 rc" "s2 value" "unknown" "hostile"; do fail "[L11] session_rev $t" "pr_session_rev missing"; done; fi
if l11_have pr_sess_cat; then
  out="$(pr_sess_cat "$R" s1 verification_report.md)"; rc=$?
  l11rc "sess_cat existing file rc" "$rc" 0; l11eq "sess_cat existing file content" "$out" "Итог: PASS"
  pr_sess_cat "$R" s1 nope.md >/dev/null 2>&1; rc=$?; l11rc "sess_cat missing file rc" "$rc" 1
  pr_sess_cat "$R" s1 "../x" >/dev/null 2>&1; rc=$?; l11rc "sess_cat refuses a path-like name" "$rc" 1
else for t in "existing rc" "existing content" "missing" "path-like"; do fail "[L11] sess_cat $t" "pr_sess_cat missing"; done; fi

# ---- pr_order_load
if l11_have pr_order_load; then
  pr_order_load "$R" s1; rc=$?
  l11rc "order_load s1 rc" "$rc" 0
  l11eq "order_load COMMIT" "${PR_O_COMMIT:-}" "C-ACME-001"
  l11eq "order_load TITLE" "${PR_O_TITLE:-}" "Feature mod1"
  l11eq "order_load BASE" "${PR_O_BASE:-}" "dev"
  l11eq "order_load URL" "${PR_O_URL:-}" "ssh://dobro/srv/app.git"
  l11eq "order_load HOSTING" "${PR_O_HOSTING:-}" "github"
  l11eq "order_load BRANCH" "${PR_O_BRANCH:-}" "change/C-ACME-001-ex1"
  l11eq "order_load EXEC" "${PR_O_EXEC:-}" "ex1"
  l11eq "order_load DIGEST" "${PR_O_DIGEST:-}" "123456789012"
  l11eq "order_load DELIVERY" "${PR_O_DELIVERY:-}" "pr"
  pr_order_load "$R" s2; rc=$?
  l11rc "order_load without a snapshot rc (1 = none)" "$rc" 1
  l11eq "order_load without a snapshot leaves PR_O_* empty" "${PR_O_COMMIT:-}${PR_O_EXEC:-}${PR_O_URL:-}" ""
  mandate_load "$R"; pr_order_load "$R" s1 >/dev/null 2>&1; _my_scalar mandate.executor
  l11eq "order_load does not clobber the loaded mandate (MY_NORM)" "$MY_S" "ex1"
else for t in rc COMMIT TITLE BASE URL HOSTING BRANCH EXEC DIGEST DELIVERY none-rc none-empty no-clobber; do fail "[L11] order_load $t" "pr_order_load missing"; done; fi

# ---- pr_base_ref
if l11_have pr_base_ref; then
  pr_base_ref "$R" dev; rc=$?
  l11rc "base_ref dev rc" "$rc" 0
  l11eq "base_ref prefers the local branch" "$PR_BASE_REF" "refs/heads/dev"
  l11eq "base_ref sha" "$PR_BASE_SHA" "$SHA_DEV"
  l11eq "base_ref no drift when local == remote-tracking" "$PR_BASE_DRIFT" "0"
  pr_base_ref "$R" nosuch >/dev/null 2>&1; rc=$?; l11rc "base_ref: no such branch rc" "$rc" 1
  l11eq "base_ref: error names the field" "${PR_ERR%%:*}" "base"
  pr_base_ref "$R" "bad..name" >/dev/null 2>&1; rc=$?; l11rc "base_ref: invalid ref name rc" "$rc" 1
  rm -rf "$TMP/g11/r2"; cp -a "$R" "$TMP/g11/r2"
  git -C "$TMP/g11/r2" branch -q -f dev refs/heads/sdx/s1   # local dev ahead of origin/dev
  pr_base_ref "$TMP/g11/r2" dev; rc=$?
  l11rc "base_ref drift rc" "$rc" 0
  l11eq "base_ref reports drift between local and remote-tracking" "$PR_BASE_DRIFT" "1"
  l11eq "base_ref drift still prefers the local branch" "$PR_BASE_REF" "refs/heads/dev"
  git -C "$TMP/g11/r2" checkout -q sdx/s1; git -C "$TMP/g11/r2" branch -q -D dev
  pr_base_ref "$TMP/g11/r2" dev; rc=$?
  l11rc "base_ref remote-tracking only rc" "$rc" 0
  l11eq "base_ref falls back to the remote-tracking branch" "$PR_BASE_REF" "refs/remotes/origin/dev"
  l11eq "base_ref remote-tracking sha" "$PR_BASE_SHA" "$SHA_DEV"
else for t in rc local sha drift-none nosuch err-field invalid drift-rc drift-flag drift-local rt-rc rt-ref rt-sha; do fail "[L11] base_ref $t" "pr_base_ref missing"; done; fi

# ---- pr_files
if l11_have pr_files; then
  pr_files "$R" dev refs/heads/sdx/s1; rc=$?
  l11rc "files rc" "$rc" 0
  l11eq "files: names without quoting, session directory absent, sorted" "$PR_FILES" $'docs/DECISIONS.md\ndocs/specs/mod1.md\ndocs/спека.md\npackage-lock.json\nsrc/core/b.js\nsrc/mod1/a.js'
  pr_files "$R" dev dev; rc=$?; l11rc "files: empty diff rc" "$rc" 0; l11eq "files: empty diff -> empty" "$PR_FILES" ""
  rm -rf "$TMP/g11/r3"; cp -a "$R" "$TMP/g11/r3"
  ( cd "$TMP/g11/r3" && git checkout -q -b nl dev && printf 'x' > "$(printf 'a\nb')" && git add -A && git commit -q -m nl ) >/dev/null 2>&1
  pr_files "$TMP/g11/r3" dev nl >/dev/null 2>&1; rc=$?
  l11rc "files: a newline in a path -> rc 1" "$rc" 1
  case "${PR_ERR:-}" in files:*) pass "[L11] files: PR_ERR names the field" ;; *) fail "[L11] files: PR_ERR names the field" "got [${PR_ERR:-}]" ;; esac
  pr_files "$R" dev nosuchrev >/dev/null 2>&1; rc=$?; l11rc "files: unknown revision -> rc 1" "$rc" 1
else for t in rc names empty-rc empty newline err-field badrev; do fail "[L11] files $t" "pr_files missing"; done; fi

# ---- pr_scope_eval (mandate: paths src/mod1/**, shared package-lock.json, docs docs/**)
if l11_have pr_scope_eval; then
  mandate_load "$R"
  PR_FILES=$'docs/DECISIONS.md\ndocs/specs/mod1.md\ndocs/спека.md\npackage-lock.json\nsrc/core/b.js\nsrc/mod1/a.js\n.claude/sessions/s1/order.yaml\noutside/x'
  pr_scope_eval
  l11eq "scope_eval OUT = outside every area" "$PR_OUT" $'src/core/b.js\n.claude/sessions/s1/order.yaml\noutside/x'
  l11eq "scope_eval SHARED" "$PR_SHARED" "package-lock.json"
  l11eq "scope_eval DOCSF" "$PR_DOCSF" $'docs/DECISIONS.md\ndocs/specs/mod1.md\ndocs/спека.md'
  l11eq "scope_eval SESSF" "$PR_SESSF" ".claude/sessions/s1/order.yaml"
  l11eq "scope_eval DOCS_OUTSIDE empty when docs/** is covered" "$PR_DOCS_OUTSIDE" ""
  P2="$(mproj l11narrow "${MANDATE11/docs\/\*\*/docs/specs/**}")"; mandate_load "$P2"; pr_scope_eval
  l11eq "scope_eval DOCS_OUTSIDE = docs/ paths outside docs_paths" "$PR_DOCS_OUTSIDE" $'docs/DECISIONS.md\ndocs/спека.md'
  P3="$(mproj l11nopaths "$(printf '%s\n' "$MANDATE11" | grep -v -e 'src/mod1' -e '^    paths:$')")"; mandate_load "$P3"; pr_scope_eval
  l11eq "scope_eval: empty paths -> no OUT (no restriction)" "$PR_OUT" ""
  PR_FILES=""; mandate_load "$R"; pr_scope_eval
  l11eq "scope_eval: empty file list -> all empty" "$PR_OUT$PR_SHARED$PR_DOCSF$PR_SESSF$PR_DOCS_OUTSIDE" ""
else for t in OUT SHARED DOCSF SESSF DOCS_OUTSIDE narrow nopaths empty; do fail "[L11] scope_eval $t" "pr_scope_eval missing"; done; fi

# ---- pr_registry
if l11_have pr_registry; then
  PR_FILES=$'docs/DECISIONS.md\nsrc/mod1/a.js'
  pr_registry "$R" dev refs/heads/sdx/s1
  l11eq "registry: docs/DECISIONS.md changed -> one" "$PR_REG_STATE" "one"
  l11eq "registry path" "$PR_REG_PATH" "docs/DECISIONS.md"
  l11eq "registry anchor from the added heading" "$PR_REG_ANCHORS" "docs/DECISIONS.md#ADR-099"
  PR_FILES="src/mod1/a.js"; pr_registry "$R" dev refs/heads/sdx/s1
  l11eq "registry: not changed -> none" "$PR_REG_STATE" "none"
  l11eq "registry: none -> empty path and anchors" "$PR_REG_PATH$PR_REG_ANCHORS" ""
  PR_FILES=$'docs/a/decisions-1.md\ndocs/b/DECISIONS-2.md'; pr_registry "$R" dev refs/heads/sdx/s1
  l11eq "registry: two mask candidates -> ambiguous" "$PR_REG_STATE" "ambiguous"
  PR_FILES=$'docs/a/decisions-1.md\nsrc/x'; pr_registry "$R" dev refs/heads/sdx/s1
  l11eq "registry: one mask candidate -> one" "$PR_REG_STATE" "one"
  l11eq "registry: mask candidate path" "$PR_REG_PATH" "docs/a/decisions-1.md"
  PR_FILES=$'docs/DECISIONS.md\ndocs/a/decisions-1.md'; pr_registry "$R" dev refs/heads/sdx/s1
  l11eq "registry: docs/DECISIONS.md has priority over the mask" "$PR_REG_PATH" "docs/DECISIONS.md"
else for t in one path anchor none none-empty ambiguous mask-one mask-path priority; do fail "[L11] registry $t" "pr_registry missing"; done; fi

# ---- pr_resolve
if l11_have pr_resolve; then
  pr_resolve "$R" s1; rc=$?
  l11rc "resolve from the order snapshot rc" "$rc" 0
  l11eq "resolve PR_C" "${PR_C:-}" "C-ACME-001"
  l11eq "resolve PR_EXEC (from the mandate)" "${PR_EXEC:-}" "ex1"
  l11eq "resolve PR_BRANCH" "${PR_BRANCH:-}" "change/C-ACME-001-ex1"
  l11eq "resolve PR_TITLE" "${PR_TITLE:-}" "Feature mod1"
  l11eq "resolve PR_BASE_NAME" "${PR_BASE_NAME:-}" "dev"
  l11eq "resolve PR_BASE_REF" "${PR_BASE_REF:-}" "refs/heads/dev"
  l11eq "resolve PR_BASE_SHA" "${PR_BASE_SHA:-}" "$SHA_DEV"
  l11eq "resolve PR_URL" "${PR_URL:-}" "ssh://dobro/srv/app.git"
  l11eq "resolve PR_HOSTING_HINT" "${PR_HOSTING_HINT:-}" "github"
  l11eq "resolve PR_DELIVERY" "${PR_DELIVERY:-}" "pr"
  l11eq "resolve PR_DOCS_MODE" "${PR_DOCS_MODE:-}" "final"
  l11eq "resolve PR_DIGEST" "${PR_DIGEST:-}" "123456789012"
  pr_resolve "$R" s1 --commitment C-ACME-001 --title "Own title" >/dev/null 2>&1; rc=$?
  l11rc "resolve: argument equal to the snapshot rc" "$rc" 0
  l11eq "resolve: an explicit --title is not a silent override" "${PR_TITLE:-}" "Own title"
  pr_resolve "$R" s1 --commitment C-OTHER-9 >/dev/null 2>&1; rc=$?
  l11rc "resolve: argument differs from a non-empty snapshot -> rc 1" "$rc" 1
  case "${PR_ERR:-}" in commitment:*) pass "[L11] resolve: PR_ERR names the field (commitment)" ;; *) fail "[L11] resolve: PR_ERR names the field" "got [${PR_ERR:-}]" ;; esac
  pr_resolve "$R" s1 --base-name main >/dev/null 2>&1; rc=$?; l11rc "resolve: --base-name differs from the snapshot -> rc 1" "$rc" 1
  pr_resolve "$R" s2 --commitment C-X-1 --title "T" >/dev/null 2>&1; rc=$?
  l11rc "resolve without a snapshot, arguments given rc" "$rc" 0
  l11eq "resolve without a snapshot: PR_C from the argument" "${PR_C:-}" "C-X-1"
  l11eq "resolve without a snapshot: base from default-branch.sh" "${PR_BASE_NAME:-}" "dev"
  l11eq "resolve without a snapshot: no URL, no hint" "${PR_URL:-}${PR_HOSTING_HINT:-}" ""
  pr_resolve "$R" s2 --title "T" >/dev/null 2>&1; rc=$?; l11rc "resolve: no commitment anywhere -> rc 1" "$rc" 1
  pr_resolve "$R" s2 --commitment "a b" --title T >/dev/null 2>&1; rc=$?; l11rc "resolve: invalid commitment id -> rc 1" "$rc" 1
  pr_resolve "$R" s2 --commitment C-X-1 >/dev/null 2>&1; rc=$?; l11rc "resolve: no title anywhere -> rc 1" "$rc" 1
  pr_resolve "$R" s2 --commitment C-X-1 --title "password: hunter2" >/dev/null 2>&1; rc=$?; l11rc "resolve: a secret in the title -> rc 1" "$rc" 1
  rm -rf "$TMP/g11/r4"; cp -a "$R" "$TMP/g11/r4"; printf '%s' "${MANDATE11/executor: ex1/executor: client-harness:kitgroup}" > "$TMP/g11/r4/.mesh/mandate.yaml"
  pr_resolve "$TMP/g11/r4" s1 >/dev/null 2>&1; rc=$?
  l11rc "resolve: executor comes only from the mandate and must be valid -> rc 1" "$rc" 1
  case "${PR_ERR:-}" in executor:*) pass "[L11] resolve: PR_ERR names the field (executor)" ;; *) fail "[L11] resolve: PR_ERR names the field (executor)" "got [${PR_ERR:-}]" ;; esac
  printf '%s' "${MANDATE11/docs_in_repo: final/docs_in_repo: none}" > "$TMP/g11/r4/.mesh/mandate.yaml"; pr_resolve "$TMP/g11/r4" s1 >/dev/null 2>&1
  l11eq "resolve: docs_in_repo none" "${PR_DOCS_MODE:-}" "none"
  printf '%s' "$MANDATE11" | grep -v 'docs_in_repo' > "$TMP/g11/r4/.mesh/mandate.yaml"; pr_resolve "$TMP/g11/r4" s1 >/dev/null 2>&1
  l11eq "resolve: docs_in_repo unset -> final (node default)" "${PR_DOCS_MODE:-}" "final"
  printf '%s' "${MANDATE11/executor: ex1/executor: other}" > "$TMP/g11/r4/.mesh/mandate.yaml"; pr_resolve "$TMP/g11/r4" s1 >/dev/null 2>&1; rc=$?
  l11rc "resolve: the snapshot's executor differs from the mandate's -> rc 1" "$rc" 1
  rm -f "$TMP/g11/r4/.mesh/endpoint.yaml"; pr_resolve "$TMP/g11/r4" s1 >/dev/null 2>&1; rc=$?
  l11rc "resolve: no mandate mode (no endpoint.yaml) -> rc 1" "$rc" 1
else for t in rc C EXEC BRANCH TITLE BASE_NAME BASE_REF BASE_SHA URL HINT DELIVERY DOCS DIGEST arg-ok title-override arg-differs err-field base-differs noorder-rc noorder-C noorder-base noorder-url nocommit badid notitle secret execbad exec-field docs-none docs-unset snap-exec nomode; do fail "[L11] resolve $t" "pr_resolve missing"; done; fi
fi

if want Mut; then
echo "[Mut] mutation runs: each mutant (a copy of lib/ in a temp dir) must differ from the original and turn its sections red"
MUTDIR="$TMP/mut"; mkdir -p "$MUTDIR"
# mutate <name> <lib file> <sed expr> <sections>: re-enter this script with MANDATE_ONLY=<sections> against the mutated lib
mutate() {
  local name="$1" file="$2" expr="$3" only="$4" d="$MUTDIR/$1" out first
  if [ ! -f "$LIB/$file" ]; then fail "[Mut] $name" "no $file to mutate"; return; fi
  mkdir -p "$d"; cp "$LIB"/*.sh "$d/"
  sed "$expr" "$LIB/$file" > "$d/$file"
  if cmp -s "$LIB/$file" "$d/$file"; then fail "[Mut] $name" "mutant is identical to the original (anchor missing?)"; return; fi
  out="$(MANDATE_LIB_UNDER_TEST="$d" MANDATE_ONLY="$only" bash "${BASH_SOURCE[0]}" 2>&1)"
  if printf '%s\n' "$out" | grep -q 'FAIL:'; then
    first="$(printf '%s\n' "$out" | grep -m1 'FAIL:' | cut -c1-120)"
    pass "[Mut] мутант $name → красный (ожидаемо) в [$only]: ${first#  FAIL: }"
  else
    fail "[Mut] $name" "sections [$only] stayed green on the mutant (the check proves nothing)"
  fi
}
mutate MAND-ROOT         mandate.sh '/# MAND-ROOT/d' "L1v"
mutate MAND-UNKNOWN      mandate.sh '/# MAND-UNKNOWN/d' "L1v"
mutate MAND-FLOW         miniyaml.sh '/# MAND-FLOW/s/"\["/"@@"/' "L1"
mutate MAND-NEVER        mandate.sh '/# MAND-NEVER/s/return 1/return 0/' "L4"
mutate MAND-ALWAYS       mandate.sh '/# MAND-ALWAYS/s/return 0/return 1/' "L4"
mutate MAND-GLOB-PREFIX  mandate.sh 's|^  \[ "\${f#.*# MAND-GLOB-PREFIX|  false   # MAND-GLOB-PREFIX|' "L5"
mutate MAND-GLOB-ESC     mandate.sh '/# MAND-GLOB-ESC/d' "L5"
mutate MAND-EXPIRY       mandate.sh '/# MAND-EXPIRY/s/-lt/-gt/' "L6"
mutate MAND-MODE         mandate.sh '/# MAND-MODE/s|\[ -f "\$p/.mesh/endpoint.yaml" \] &&|true \&\&|' "L7"
mutate MAND-SANITIZE     miniyaml.sh '/# MAND-SANITIZE/d' "L1q L8"
mutate MAND-SCOPE-WARN   mandate.sh '/# MAND-SCOPE-WARN/s/\[ -n "\$MANDATE_PATHS" \]/true/' "L8w"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
