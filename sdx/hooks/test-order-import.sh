#!/usr/bin/env bash
# Tests for sdx/hooks/order-import.sh (FEAT-017, REQ-PKG-23..25, 10): acceptance of a work order (file, mailbox
# envelope, issue), the local-mandate check, the order snapshot and the `commitment` stamp of session_state.json.
# python3/PyYAML appear here ONLY as test oracles (INFO-skip, never PASS, when absent); gh is a stub; nothing is
# written outside a temporary directory.
#
#  [O1] a static golden: an order as yaml.safe_dump writes it (folded plain / single-quoted scalars, folded list item)
#  [O2] parity of `order-unfold` + miniyaml with yaml.safe_load on generated dumps (oracle) + refusals with a reason
#  [O3] mailbox envelope (--inbox-json): selection by msg_id, `list`, foreign kinds, unknown / malformed msg_id
#  [O4] issue (gh stub): first yaml block with `action: work.order`; no gh -> a hint for --from-order
#  [O5] the local mandate check (mandate_digest / executor / deliver.branch): rc 3, ALL mismatches at once
#  [O6] hostile identifiers and values (C with / .. space, markup in title, ext:: url, a secret)
#  [O7] the snapshot (--out) read back by pr_order_load; stamp-state of session_state.json
#  [Mut] mutation runs (copies of the script + lib/ in a temp dir, anchored by "# PKG-O-*")
# ORDER_IMPORT_ONLY="O1 O3" restricts a run; ORDER_IMPORT_UNDER_TEST is the script under test (mutation runs).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${ORDER_IMPORT_UNDER_TEST:-$SCRIPT_DIR/order-import.sh}"
LIB="$SCRIPT_DIR/lib"
export PYTHONDONTWRITEBYTECODE=1

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
info() { echo "  INFO: $1"; }
want() { [ -z "${ORDER_IMPORT_ONLY:-}" ] && return 0; case " $ORDER_IMPORT_ONLY " in *" $1 "*) return 0 ;; esac; return 1; }

echo "=== test-order-import.sh ==="
echo ""

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck disable=SC1091
. "$LIB/miniyaml.sh"
# shellcheck disable=SC1091
. "$LIB/pr-lib.sh"
# shellcheck disable=SC1091
. "$LIB/pkg-fixture.sh"

NOMAND="$TMP/nomand"; mkdir -p "$NOMAND"      # a project without a mandate: the parse/normalise paths only

# run_oi <args...>: RC / OUT / ERR of one invocation (the project is always passed explicitly)
run_oi() {
  OUT="$(bash "$SCRIPT" "$@" 2>"$TMP/err")"; RC=$?
  ERR="$(cat "$TMP/err")"
}
# jv <jq-filter> [json]: one value of the flat JSON of the last run (or of the given text)
jv() { printf '%s' "${2:-$OUT}" | jq -r "$1" 2>/dev/null; }
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "got [$2] expected [$3]"; fi; }
have_oracle() { python3 -I -c 'import yaml' >/dev/null 2>&1; }

# ---------------------------------------------------------------------------------------------------- [O1]
if want O1; then
echo "[O1] static golden: an order as yaml.safe_dump writes it"
cat > "$TMP/golden.yaml" <<'YAML'
action: work.order
format: 1
commitment:
  id: C-ACME-001
  kind: change
  title: Add the mod1 export endpoint with pagination and stable ordering for large
    result sets
  requirements: 'Implement GET /mod1/export returning CSV: columns id, name, created;
    support the page and size parameters; keep ordering stable across pages; document
    the contract in docs/specs/mod1.md and cover with tests.'
  due: '2026-12-01'
  state: open
  creditor: acme
executor: ex1
mandate:
  repo: app
  stages:
  - spec
  - design
  - execute
  - verify
  scope:
    paths:
    - src/mod1/**
    shared_paths:
    - package-lock.json
    docs_paths:
    - docs/**
    branches:
    - change/*
  delivery: pr
  history: executor
  docs_in_repo: final
  valid_until: '2099-01-01'
  on_write: deny
  executor: ex1
  digest: '123456789012'
  format: 1
mandate_digest: '123456789012'
repo:
  id: app
  url: ssh://git@git.example.com/srv/app.git
  base: dev
deliver:
  branch: change/C-ACME-001-ex1
  manifest: CHANGE.yaml
  delivery: pr
notes:
- a note long enough to be folded by the dumper onto a second line of the document,
  and a third
- short
by: operator
ts: '2026-10-31T10:00:00+00:00'
YAML
run_oi from-file "$TMP/golden.yaml" --proj "$NOMAND"
eq "[O1] golden: rc 0" "$RC" "0"
eq "[O1] golden: commitment" "$(jv .commitment)" "C-ACME-001"
eq "[O1] golden: title (folded plain scalar joined by one space)" "$(jv .title)" "Add the mod1 export endpoint with pagination and stable ordering for large result sets"
eq "[O1] golden: executor" "$(jv .executor)" "ex1"
eq "[O1] golden: repo_base" "$(jv .repo_base)" "dev"
eq "[O1] golden: repo_url" "$(jv .repo_url)" "ssh://git@git.example.com/srv/app.git"
eq "[O1] golden: branch" "$(jv .branch)" "change/C-ACME-001-ex1"
eq "[O1] golden: delivery" "$(jv .delivery)" "pr"
eq "[O1] golden: due (quoted date)" "$(jv .due)" "2026-12-01"
eq "[O1] golden: source" "$(jv .source)" "file"
bash "$SCRIPT" unfold "$TMP/golden.yaml" > "$TMP/golden.unf" 2>/dev/null
my_load "$TMP/golden.unf"; lrc=$?
_my_scalar commitment.id
eq "[O1] golden: the unfolded text is read by miniyaml (rc, commitment.id)" "$lrc:$MY_S" "0:C-ACME-001"
_my_scalar commitment.requirements
eq "[O1] golden: requirements (single-quoted folded scalar, 3 lines joined)" "$MY_S" "Implement GET /mod1/export returning CSV: columns id, name, created; support the page and size parameters; keep ordering stable across pages; document the contract in docs/specs/mod1.md and cover with tests."
_my_list notes
eq "[O1] golden: folded list item joined, the next item intact" "$MY_L" "a note long enough to be folded by the dumper onto a second line of the document, and a third"$'\n'"short"
fi

# ---------------------------------------------------------------------------------------------------- [O2]
if want O2; then
echo "[O2] parity of order-unfold + miniyaml with yaml.safe_load; refusals with a reason"
if have_oracle; then
  mkdir -p "$TMP/gen"
  python3 -I -B - "$TMP/gen" <<'PY'
import random, sys, yaml
out = sys.argv[1]
rnd = random.Random(1717)
words = ("alpha beta gamma delta export import module service endpoint pagination ordering stable cover tests "
         "a: b #tag it's \"quoted\" - dash [x] {y} 100% &amp *star !bang @at `tick` yes no null true 2026-12-01 123 "
         "ключ значение пакет заказ").split(" ")
def sentence(lo, hi):
    n = rnd.randint(lo, hi)
    s = " ".join(rnd.choice(words) for _ in range(n))
    return s.strip() or "x"
def scalar():
    r = rnd.random()
    if r < 0.12: return rnd.randint(0, 9999)
    if r < 0.18: return None
    if r < 0.22: return ""
    if r < 0.55: return sentence(1, 6)
    return sentence(12, 60)
def node(depth):
    d = {}
    for i in range(rnd.randint(2, 5)):
        k = "k_%d" % i
        r = rnd.random()
        if r < 0.55: d[k] = scalar()
        elif r < 0.8: d[k] = [sentence(1, 30) for _ in range(rnd.randint(1, 4))]
        elif depth < 2: d[k] = node(depth + 1)
        else: d[k] = scalar()
    return d
for n in range(26):
    doc = node(0)
    width = rnd.choice([80, 80, 60, 40])
    text = yaml.safe_dump(doc, allow_unicode=True, sort_keys=False, width=width)
    open("%s/%02d.yaml" % (out, n), "w", encoding="utf-8").write(text)
    got = yaml.safe_load(text)
    lines = []
    def walk(v, path):
        if isinstance(v, dict):
            for k, x in v.items(): walk(x, path + "." + k if path else k)
        elif isinstance(v, list):
            if not v: lines.append("E\t%s" % path)
            for x in v: lines.append("L\t%s\t%s" % (path, x))
        elif v is None: lines.append("Z\t%s" % path)
        else: lines.append("S\t%s\t%s" % (path, v))
    walk(got, "")
    open("%s/%02d.exp" % (out, n), "w", encoding="utf-8").write("\n".join(lines) + "\n")
PY
  okn=0; badn=0; badlist=""
  for y in "$TMP"/gen/*.yaml; do
    b="${y%.yaml}"
    bash "$SCRIPT" unfold "$y" > "$b.unf" 2>/dev/null
    if my_load "$b.unf"; then
      printf '%s\n' "$MY_NORM" | tr '\037' '\t' | grep -E '^[SZLE]'$'\t' | LC_ALL=C sort > "$b.got"
      LC_ALL=C sort "$b.exp" | grep . > "$b.expsorted"
      if cmp -s "$b.got" "$b.expsorted"; then okn=$((okn + 1)); else badn=$((badn + 1)); badlist="$badlist ${b##*/}"; fi
    else badn=$((badn + 1)); badlist="$badlist ${b##*/}(parse: $MY_ERR)"; fi
  done
  if [ "$okn" -ge 25 ] && [ "$badn" -eq 0 ]; then pass "[O2] parity with yaml.safe_load on $okn generated dumps (0 divergences)"
  else fail "[O2] parity with yaml.safe_load" "$okn equal, $badn diverge:$badlist"; fi
else
  info "[O2] python3/PyYAML absent: the parity with yaml.safe_load is skipped (not a PASS)"
fi
# refusals: each case is an otherwise valid order with one construct outside the subset
base_order() {  # <title-block> -> an order text with the given lines in place of "title"
  printf 'action: work.order\nformat: 1\ncommitment:\n  id: C-ACME-001\n%s\nexecutor: ex1\nrepo:\n  base: dev\n  url: ssh://git@git.example.com/srv/app.git\ndeliver:\n  branch: change/C-ACME-001-ex1\n  delivery: pr\n' "$1"
}
refuse_case() {  # <name> <reason fragment> <title-block>
  base_order "$3" > "$TMP/ref-$1.yaml"
  run_oi from-file "$TMP/ref-$1.yaml" --proj "$NOMAND"
  if [ "$RC" -eq 1 ] && [ -z "$OUT" ] && printf '%s' "$ERR" | grep -q -- "$2"; then pass "[O2] refused ($1): rc 1, reason has [$2]"
  else fail "[O2] refusal $1" "rc=$RC out=[$OUT] err=[$ERR]"; fi
}
refuse_case dq-newline "двойн" $'  title: "first line\n    second line"'
refuse_case block-literal "вне подмножества" $'  title: |\n    literal text'
refuse_case block-folded "вне подмножества" $'  title: >\n    folded text'
refuse_case blank-inside "пуст" $'  title: first line\n\n    second line'
refuse_case anchor "вне подмножества" $'  title: &a text'
refuse_case dict-list "список словарей" $'  title: ok\n  items:\n  - a: 1\n    b: 2'
refuse_case flow-dict "flow-словарь" $'  title: ok\n  extra: {a: 1}'
{ base_order '  title: big'; printf '# '; head -c 70000 /dev/zero | tr '\0' 'x'; printf '\n'; } > "$TMP/ref-big.yaml"
run_oi from-file "$TMP/ref-big.yaml" --proj "$NOMAND"
if [ "$RC" -eq 1 ] && [ -z "$OUT" ] && printf '%s' "$ERR" | grep -q '64'; then pass "[O2] refused (file over 64 KiB): rc 1, reason names the limit"
else fail "[O2] refusal big file" "rc=$RC out=[$OUT] err=[$ERR]"; fi
run_oi from-file "$TMP/does-not-exist.yaml" --proj "$NOMAND"
if [ "$RC" -eq 1 ] && [ -z "$OUT" ]; then pass "[O2] refused (no such file): rc 1"; else fail "[O2] refusal no such file" "rc=$RC out=[$OUT]"; fi
fi

#@@SECTIONS-END@@

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
