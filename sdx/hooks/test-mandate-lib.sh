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

csv() { tr '\n' ',' | sed 's/,$//'; }

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
chk sibling-after-list "ok:spec" $'mandate:\n  stages:\n  - spec\n  delivery: pr\n  history: squash\n' "mandate.delivery=pr" "mandate.history=squash"
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

# ============================================================== [L1q] my_q
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

# ============================================================== [L3] real node dump
echo "[L3] real node dump (yaml.safe_dump(sort_keys=False) shape)"
DUMP=$'mandate:\n  repo: app1\n  stages:\n  - spec\n  - design\n  - execute\n  - verify\n  scope:\n    paths:\n    - src/**\n    - tests/**\n    shared_paths:\n    - composer.lock\n    branches:\n    - dev\n    docs_paths:\n    - docs/**\n  delivery: artifact.offer\n  history: squash\n  docs_in_repo: final\n  valid_until: \'2026-12-31\'\n  on_write: deny\n  executor: sdx-dev1\n  issued: \'2026-10-28T10:00:00+00:00\'\n  node: mo-node-1\n  digest: 0123456789ab\n  format: 1\n  how_to_deliver:\n    branch: change/<C>-sdx-dev1\n    manifest: CHANGE.yaml\n    fields:\n    - format\n    - commitment\n    - executor\n'
chk real-dump "ok:spec,design,execute,verify" "$DUMP" \
  "mandate.executor=sdx-dev1" "mandate.digest=0123456789ab" "mandate.valid_until=2026-12-31" "mandate.delivery=artifact.offer" \
  "mandate.scope.paths@src/**,tests/**" "mandate.scope.shared_paths@composer.lock" "mandate.scope.docs_paths@docs/**" "mandate.scope.branches@dev" \
  "mandate.format=1" "mandate.issued=2026-10-28T10:00:00+00:00" "mandate.on_write=deny" "mandate.docs_in_repo=final" \
  "mandate.how_to_deliver.branch=change/<C>-sdx-dev1" "mandate.how_to_deliver.fields@format,commitment,executor"

# ============================================================== [L9] portability
echo "[L9] portability (BUG-010) and no-python invariant (REQ-MAND-33)"
FORBID='tim''eout|map''file|declare -''A|[$]\{[a-zA-Z_]+,,\}|%''N|readlink -''f|real''path'
for f in miniyaml.sh; do   # mandate.sh joins this loop in T03
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

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
