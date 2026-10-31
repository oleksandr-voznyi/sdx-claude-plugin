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
  okn=0; badn=0; badlist=""; foldedn=0
  for y in "$TMP"/gen/*.yaml; do
    b="${y%.yaml}"
    bash "$SCRIPT" unfold "$y" > "$b.unf" 2>/dev/null
    [ "$(wc -l < "$b.unf")" -lt "$(wc -l < "$y")" ] && foldedn=$((foldedn + 1))
    if my_load "$b.unf"; then
      printf '%s\n' "$MY_NORM" | tr '\037' '\t' | grep -E '^[SZLE]'$'\t' | LC_ALL=C sort > "$b.got"
      LC_ALL=C sort "$b.exp" | grep . > "$b.expsorted"
      if cmp -s "$b.got" "$b.expsorted"; then okn=$((okn + 1)); else badn=$((badn + 1)); badlist="$badlist ${b##*/}"; fi
    else badn=$((badn + 1)); badlist="$badlist ${b##*/}(parse: $MY_ERR)"; fi
  done
  if [ "$okn" -ge 25 ] && [ "$badn" -eq 0 ] && [ "$foldedn" -ge 15 ]; then pass "[O2] parity with yaml.safe_load on $okn generated dumps ($foldedn of them folded; 0 divergences)"
  else fail "[O2] parity with yaml.safe_load" "$okn equal, $badn diverge, $foldedn folded:$badlist"; fi
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

# a valid order body as JSON; the cases below override single fields
BASE_JSON='{"action":"work.order","format":1,"commitment":{"id":"C-ACME-001","kind":"change","title":"Feature mod1","requirements":"Implement mod1","due":"2026-12-01","creditor":"acme"},"executor":"ex1","mandate_digest":"123456789012","repo":{"id":"app","url":"ssh://git@git.example.com/srv/app.git","base":"dev"},"deliver":{"branch":"change/C-ACME-001-ex1","delivery":"pr"}}'
# mkj <out-file> <jq-path> <value>: the base order with one string field replaced
mkj() { printf '%s' "$BASE_JSON" | jq --arg v "$3" "$2 = \$v" > "$1"; }

# ---------------------------------------------------------------------------------------------------- [O3]
if want O3; then
echo "[O3] mailbox envelope: selection by msg_id, list, foreign kinds, malformed msg_id"
ORD2="$(printf '%s' "$BASE_JSON" | jq -c '.commitment.id = "C-ACME-002" | .commitment.title = "Second order"')"
{
  printf '%s\n' "{\"msg_id\":\"m-1\",\"kind\":\"directive\",\"seq\":1,\"body\":$BASE_JSON}" | jq -c .
  printf '%s\n' '{"msg_id":"m-2","kind":"notice","seq":2,"body":{"event":"scope.write"}}'
  printf '%s\n' '{"msg_id":"m-3","kind":"directive","seq":3,"body":{"action":"other.thing"}}'
  printf '%s\n' "{\"msg_id\":\"m-4\",\"kind\":\"directive\",\"seq\":4,\"body\":$ORD2}" | jq -c .
  printf '%s\n' 'this line is not json'
  printf '%s\n' "{\"msg_id\":\"m-5\",\"kind\":\"fact\",\"seq\":5,\"body\":$BASE_JSON}" | jq -c .
} > "$TMP/inbox.jsonl"
run_oi from-msg m-1 --inbox-json "$TMP/inbox.jsonl" --proj "$NOMAND"
eq "[O3] m-1: rc 0, the first order" "$RC:$(jv .commitment):$(jv .source):$(jv .source_ref)" "0:C-ACME-001:msg:m-1"
run_oi from-msg m-4 --inbox-json "$TMP/inbox.jsonl" --proj "$NOMAND"
eq "[O3] m-4: the second order is selected by msg_id" "$RC:$(jv .commitment):$(jv .title)" "0:C-ACME-002:Second order"
for bad in m-2 m-3 m-5 m-404; do
  run_oi from-msg "$bad" --inbox-json "$TMP/inbox.jsonl" --proj "$NOMAND"
  if [ "$RC" -eq 1 ] && [ -z "$OUT" ] && [ -n "$ERR" ]; then pass "[O3] $bad (not a directive work.order / unknown): rc 1 with a reason"; else fail "[O3] $bad" "rc=$RC out=[$OUT] err=[$ERR]"; fi
done
long81="$(head -c 81 /dev/zero | tr '\0' 'a')"
for bad in "m 1" "../x" "m-1;id" "$long81"; do
  run_oi from-msg "$bad" --inbox-json "$TMP/inbox.jsonl" --proj "$NOMAND"
  if [ "$RC" -eq 1 ] && [ -z "$OUT" ] && printf '%s' "$ERR" | grep -q 'msg_id'; then pass "[O3] malformed msg_id [${bad:0:12}] refused: rc 1, the reason names msg_id"; else fail "[O3] malformed msg_id [${bad:0:12}]" "rc=$RC out=[$OUT] err=[$ERR]"; fi
done
run_oi from-msg --inbox-json "$TMP/inbox.jsonl" --proj "$NOMAND"
eq "[O3] no msg_id: usage, rc 2" "$RC" "2"
run_oi list --inbox-json "$TMP/inbox.jsonl" --proj "$NOMAND"
eq "[O3] list: rc 0, exactly the two orders, msg_id / C / title tab-separated" "$RC:$OUT" "0:m-1"$'\t'"C-ACME-001"$'\t'"Feature mod1"$'\n'"m-4"$'\t'"C-ACME-002"$'\t'"Second order"
printf '%s\n' '{"msg_id":"m-9","kind":"notice","seq":1,"body":{}}' > "$TMP/inbox-empty.jsonl"
run_oi list --inbox-json "$TMP/inbox-empty.jsonl" --proj "$NOMAND"
eq "[O3] list without orders: rc 0, nothing on stdout" "$RC:$OUT" "0:"
run_oi from-msg m-1 --inbox-json "$TMP/no-such-inbox.jsonl" --proj "$NOMAND"
if [ "$RC" -ne 0 ] && [ -z "$OUT" ]; then pass "[O3] unreadable --inbox-json: refused (rc $RC)"; else fail "[O3] unreadable inbox" "rc=$RC out=[$OUT]"; fi
ORDER_IMPORT_PYTHON=no-such-python-here run_oi from-msg m-1 --proj "$NOMAND"
if [ "$RC" -eq 1 ] && [ -z "$OUT" ] && printf '%s' "$ERR" | grep -q -- '--inbox-json'; then pass "[O3] no python3 and no --inbox-json: rc 1 with the hint --inbox-json / from-file"; else fail "[O3] no python3" "rc=$RC out=[$OUT] err=[$ERR]"; fi
fi

# ---------------------------------------------------------------------------------------------------- [O4]
if want O4; then
echo "[O4] issue: the first yaml block with 'action: work.order' (gh stub)"
mkdir -p "$TMP/ghbin"
cat > "$TMP/ghbin/gh" <<'STUB'
#!/usr/bin/env bash
# gh stub: `gh issue view <N> [--repo R] --json body` prints {"body": <contents of $GH_STUB_BODY>}; rc from $GH_STUB_RC
printf '%s\n' "$*" > "$GH_STUB_LOG"
[ "${GH_STUB_RC:-0}" -eq 0 ] || { echo "gh: HTTP 404" >&2; exit "$GH_STUB_RC"; }
[ "$1 $2" = "issue view" ] || exit 1
jq -Rs '{body: .}' < "$GH_STUB_BODY"
STUB
chmod +x "$TMP/ghbin/gh"
export GH_STUB_LOG="$TMP/gh.log" GH_STUB_BODY="$TMP/issue.txt"
{
  printf 'Please take this.\n\n```bash\necho not-an-order\n```\n\n```yaml\n# a sample config, not an order\nname: example\n```\n\n'
  printf '```yaml\naction: work.order\nformat: 1\ncommitment:\n  id: C-ISSUE-007\n  title: Order from an issue\n  requirements: Do the thing\nexecutor: ex1\nrepo:\n  base: dev\n'
  printf 'deliver:\n  branch: change/C-ISSUE-007-ex1\n  delivery: pr\n```\n\nThanks.\n'
} > "$TMP/issue.txt"
OLDPATH="$PATH"; PATH="$TMP/ghbin:$PATH"
run_oi from-issue 7 --proj "$NOMAND"
eq "[O4] issue 7: the order block is taken (not the bash block, not the config block)" "$RC:$(jv .commitment):$(jv .source):$(jv .source_ref)" "0:C-ISSUE-007:issue:#7"
eq "[O4] gh was called as: issue view 7 --json body" "$(cat "$GH_STUB_LOG")" "issue view 7 --json body"
run_oi from-issue 12 --repo acme/app --proj "$NOMAND"
eq "[O4] --repo is passed to gh" "$(cat "$GH_STUB_LOG")" "issue view 12 --repo acme/app --json body"
printf 'No order here.\n\n```yaml\nname: example\n```\n' > "$TMP/issue.txt"
run_oi from-issue 8 --proj "$NOMAND"
if [ "$RC" -eq 1 ] && [ -z "$OUT" ] && printf '%s' "$ERR" | grep -q 'work.order'; then pass "[O4] no order block: rc 1, the reason names work.order"; else fail "[O4] no order block" "rc=$RC out=[$OUT] err=[$ERR]"; fi
GH_STUB_RC=1 run_oi from-issue 9 --proj "$NOMAND"
if [ "$RC" -eq 1 ] && [ -z "$OUT" ]; then pass "[O4] gh fails: rc 1"; else fail "[O4] gh fails" "rc=$RC out=[$OUT]"; fi
for bad in "7;id" "abc" "1 2" "0x7" "12345678901"; do
  run_oi from-issue "$bad" --proj "$NOMAND"
  if [ "$RC" -eq 1 ] && [ -z "$OUT" ] && printf '%s' "$ERR" | grep -q 'issue'; then pass "[O4] malformed issue number [$bad] refused: rc 1"; else fail "[O4] malformed issue number [$bad]" "rc=$RC out=[$OUT] err=[$ERR]"; fi
done
for bad in 'a b/c' 'noslash' '-x/y' 'a/b/c'; do
  run_oi from-issue 7 --repo "$bad" --proj "$NOMAND"
  if [ "$RC" -eq 1 ] && [ -z "$OUT" ] && printf '%s' "$ERR" | grep -q 'repo'; then pass "[O4] malformed --repo [$bad] refused: rc 1"; else fail "[O4] malformed --repo [$bad]" "rc=$RC out=[$OUT] err=[$ERR]"; fi
done
eq "[O4] gh was not called for a malformed argument" "$(cat "$GH_STUB_LOG")" "issue view 9 --json body"
PATH="$OLDPATH"
ORDER_IMPORT_GH=gh-is-not-installed run_oi from-issue 7 --proj "$NOMAND"
if [ "$RC" -eq 1 ] && [ -z "$OUT" ] && printf '%s' "$ERR" | grep -q -- '--from-order'; then pass "[O4] no gh: rc 1 with the hint --from-order <file>"; else fail "[O4] no gh" "rc=$RC out=[$OUT] err=[$ERR]"; fi
fi

# ---------------------------------------------------------------------------------------------------- [O6]
if want O6; then
echo "[O6] hostile identifiers and values: refused or neutralised, no side effects"
MARK="$TMP/marker"; rm -f "$MARK"
idcase() {  # <label> <jq-path> <value> <field fragment>
  mkj "$TMP/h.json" "$2" "$3"
  run_oi from-file "$TMP/h.json" --proj "$NOMAND"
  if [ "$RC" -eq 1 ] && [ -z "$OUT" ] && printf '%s' "$ERR" | grep -q -- "$4"; then pass "[O6] $1: rc 1, the field is named ($4)"; else fail "[O6] $1" "rc=$RC out=[$OUT] err=[$ERR]"; fi
}
idcase "C with a slash" .commitment.id "a/b" commitment.id
idcase "C = .." .commitment.id ".." commitment.id
idcase "C with a space" .commitment.id "C 1" commitment.id
idcase "C with a colon" .commitment.id "x:y" commitment.id
idcase "C with a leading dash" .commitment.id "-C1" commitment.id
idcase "C ending with .lock" .commitment.id "C1.lock" commitment.id
idcase "C with a newline" .commitment.id $'C1\nx' commitment.id
idcase "executor client-harness:kitgroup" .executor "client-harness:kitgroup" executor
idcase "executor with a unicode letter" .executor "exé" executor
idcase "url ext::" .repo.url "ext::sh -c touch $MARK" repo.url
idcase "url fd::" .repo.url "fd::1" repo.url
idcase "url option injection" .repo.url "-oProxyCommand=x" repo.url
idcase "url with a space" .repo.url "https://h/a b.git" repo.url
idcase "base with a leading dash" .repo.base "-x" repo.base
idcase "base a..b" .repo.base "a..b" repo.base
idcase "base with a space" .repo.base "a b" repo.base
idcase "due not a date" .commitment.due "tomorrow" commitment.due
idcase "action not work.order" .action "legacy.import" action
idcase "format 2" .format "2" format
idcase "secret in requirements" .commitment.requirements "use password: hunter2 for the db" commitment.requirements
idcase "secret in title" .commitment.title "api_key=abc123" commitment.title
idcase "empty title" .commitment.title "" commitment.title
[ ! -e "$MARK" ] && pass "[O6] no marker file was created by any refused value" || fail "[O6] marker" "a refused value had a side effect"
# values that are accepted but neutralised
mkj "$TMP/h.json" .commitment.title $'line1\nline2 `touch '"$MARK"'` $(touch '"$MARK"$') \033[31m red\ttab'
run_oi from-file "$TMP/h.json" --proj "$NOMAND"
t="$(jv .title)"
if [ "$RC" -eq 0 ] && [ ! -e "$MARK" ] && [ "$(printf '%s' "$t" | wc -l | tr -d ' ')" = 0 ] && ! printf '%s' "$t" | LC_ALL=C grep -q '[[:cntrl:]]' && printf '%s' "$t" | grep -qF '$(touch'; then
  pass "[O6] markup in the title: one line, no control characters, shown literally, nothing executed"
else fail "[O6] markup in the title" "rc=$RC title=[$t] marker=$([ -e "$MARK" ] && echo yes || echo no)"; fi
big="$(head -c 5000 /dev/zero | tr '\0' 'x')"
mkj "$TMP/h.json" .commitment.title "$big"
run_oi from-file "$TMP/h.json" --proj "$NOMAND"
if [ "$RC" -eq 0 ] && [ "$(jv '.title|length')" -le 200 ] && [ "$(jv '.warnings|length')" -ge 1 ]; then pass "[O6] a 5000-character title is cut to 200 with a warning"; else fail "[O6] long title" "rc=$RC len=$(jv '.title|length') warnings=$(jv '.warnings')"; fi
mkj "$TMP/h.json" .repo.url "https://user:tok3n@git.example.com/srv/app.git"
run_oi from-file "$TMP/h.json" --proj "$NOMAND"
if [ "$RC" -eq 0 ] && [ "$(jv .repo_url)" = "https://git.example.com/srv/app.git" ] && [ "$(jv '.warnings|length')" -ge 1 ] && ! printf '%s' "$OUT" | grep -q tok3n; then pass "[O6] credentials in repo.url are removed from the result, with a warning"; else fail "[O6] url credentials" "rc=$RC out=[$OUT]"; fi
fi

ensure_fixture() { [ -n "${PKG_FIXTURE_TEMPLATE:-}" ] || pkg_fixture_template "$TMP" || { echo "fixture template failed" >&2; return 1; }; }

# ---------------------------------------------------------------------------------------------------- [O5]
if want O5; then
echo "[O5] the local mandate check: mandate_digest / executor / deliver.branch -> rc 3, all mismatches at once"
if ensure_fixture && pkg_fixture_copy "$TMP/fx5"; then
  P5="$PKG_WC"
  mkj "$TMP/m.json" .commitment.id C-ACME-001
  run_oi from-file "$TMP/m.json" --proj "$P5"
  eq "[O5] a matching order: rc 0, no mandate warning" "$RC:$(jv '[.warnings[]|select(test("мандат"))]|length')" "0:0"
  mism() {  # <label> <jq-edit> <expected stdout>
    printf '%s' "$BASE_JSON" | jq -c "$2" > "$TMP/m.json"
    run_oi from-file "$TMP/m.json" --proj "$P5" --out "$TMP/m-out.yaml"
    if [ "$RC" -eq 3 ] && [ "$OUT" = "$3" ] && [ ! -e "$TMP/m-out.yaml" ]; then pass "[O5] $1: rc 3, the exact MISMATCH lines, no snapshot written"
    else fail "[O5] $1" "rc=$RC out=[$OUT] snapshot=$([ -e "$TMP/m-out.yaml" ] && echo written || echo none)"; fi
  }
  mism "digest differs" '.mandate_digest = "999999999999"' "MISMATCH mandate_digest order=999999999999 local=123456789012"
  mism "executor differs" '.executor = "ex2"' "MISMATCH executor order=ex2 local=ex1"
  mism "branch differs" '.deliver.branch = "change/C-ACME-001-ex9"' "MISMATCH deliver.branch order=change/C-ACME-001-ex9 local=change/C-ACME-001-ex1"
  mism "all three differ (all lines at once, fixed order)" '.mandate_digest = "000000000000" | .executor = "ex2" | .deliver.branch = "change/x"' \
"MISMATCH mandate_digest order=000000000000 local=123456789012
MISMATCH executor order=ex2 local=ex1
MISMATCH deliver.branch order=change/x local=change/C-ACME-001-ex1"
  mism "order without a digest" 'del(.mandate_digest)' "MISMATCH mandate_digest order=- local=123456789012"
  mism "order without a branch" 'del(.deliver.branch)' "MISMATCH deliver.branch order=- local=change/C-ACME-001-ex1"
  printf '%s' "$BASE_JSON" | jq -c '.mandate_digest = "12\u001b[31mEVIL"' > "$TMP/m.json"
  run_oi from-file "$TMP/m.json" --proj "$P5"
  if [ "$RC" -eq 3 ] && ! printf '%s' "$OUT" | LC_ALL=C grep -q '[[:cntrl:]]' && printf '%s' "$OUT" | grep -q 'order=12\[31mEVIL'; then pass "[O5] a hostile digest is shown cleaned (no control characters)"
  else fail "[O5] hostile digest" "rc=$RC out=[$OUT]"; fi
  # an unreadable local mandate cannot be compared: stop, never "no boundary"
  pkg_fixture_copy "$TMP/fx5b" && printf 'mandate:\n  stages: [bogus\n' > "$PKG_WC/.mesh/mandate.yaml"
  printf '%s' "$BASE_JSON" > "$TMP/m.json"
  run_oi from-file "$TMP/m.json" --proj "$PKG_WC"
  if [ "$RC" -eq 3 ] && printf '%s' "$OUT" | grep -q '^MISMATCH ' && [ -n "$OUT" ]; then pass "[O5] an unreadable local mandate: rc 3 (fail-closed)"; else fail "[O5] unreadable mandate" "rc=$RC out=[$OUT]"; fi
  run_oi from-file "$TMP/m.json" --proj "$NOMAND"
  eq "[O5] no local mandate: accepted with a warning, rc 0" "$RC:$(jv '[.warnings[]|select(test("мандат"))]|length')" "0:1"
else
  fail "[O5] fixture" "the fixture could not be built"
fi
fi

# ---------------------------------------------------------------------------------------------------- [O7]
if want O7; then
echo "[O7] the snapshot (--out) and stamp-state"
if ensure_fixture; then
  RT="$TMP/rt"; rm -rf "$RT"; mkdir -p "$RT"
  git -C "$RT" init -q && git -C "$RT" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init && git -C "$RT" checkout -q -b sdx/rt
  mkdir -p "$RT/.claude/sessions/rt"; printf '{"stage":"Closeout"}\n' > "$RT/.claude/sessions/rt/session_state.json"
  snap() {  # <json file> -> commit the snapshot of that order on sdx/rt
    run_oi from-file "$1" --proj "$RT" --out "$RT/.claude/sessions/rt/order.yaml"
    git -C "$RT" add -A && git -C "$RT" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m snap
  }
  printf '%s' "$BASE_JSON" | jq '.repo.hosting = "github"' > "$TMP/s.json"
  snap "$TMP/s.json"; src=$RC
  pr_order_load "$RT" rt; lrc=$?
  eq "[O7] --out: rc 0, pr_order_load reads the snapshot" "$src:$lrc" "0:0"
  eq "[O7] roundtrip: commitment / title / requirements / due" "$PR_O_COMMIT|$PR_O_TITLE|$PR_O_REQS|$PR_O_DUE" "C-ACME-001|Feature mod1|Implement mod1|2026-12-01"
  eq "[O7] roundtrip: base / url / hosting / repo id" "$PR_O_BASE|$PR_O_URL|$PR_O_HOSTING|$PR_O_REPO" "dev|ssh://git@git.example.com/srv/app.git|github|app"
  eq "[O7] roundtrip: branch / delivery / executor / digest" "$PR_O_BRANCH|$PR_O_DELIVERY|$PR_O_EXEC|$PR_O_DIGEST" "change/C-ACME-001-ex1|pr|ex1|123456789012"
  eq "[O7] roundtrip: source / source_ref" "$PR_O_SOURCE|$PR_O_SOURCE_REF" "file|s.json"
  if ! grep -q '^mandate:' "$RT/.claude/sessions/rt/order.yaml" && ! grep -E '^[ ]*[a-z_]+: ' "$RT/.claude/sessions/rt/order.yaml" | grep -v '^  format: 1$' | grep -qv '^[ ]*[a-z_]*: "'; then pass "[O7] the snapshot has no copy of the mandate and every scalar (but format) is double-quoted"
  else fail "[O7] snapshot format" "$(cat "$RT/.claude/sessions/rt/order.yaml")"; fi
  snap "$TMP/m.json"; pr_order_load "$RT" rt
  eq "[O7] no hosting in the order -> no hosting in the snapshot" "[$PR_O_HOSTING]" "[]"
  mkj "$TMP/s.json" .commitment.title 'He said "hi" \ back: a # b'
  snap "$TMP/s.json"; pr_order_load "$RT" rt
  eq "[O7] quotes, backslash, colon and hash survive the snapshot" "$PR_O_TITLE" 'He said "hi" \ back: a # b'
  run_oi from-file "$TMP/m.json" --proj "$RT" --out "$TMP/no-dir/order.yaml"
  if [ "$RC" -eq 2 ] && [ ! -e "$TMP/no-dir" ]; then pass "[O7] --out into a missing directory: rc 2, nothing created"; else fail "[O7] --out missing dir" "rc=$RC"; fi
  # stamp-state
  SP="$TMP/sp"; mkdir -p "$SP/.claude/sessions/s7"
  CLAUDE_PROJECT_DIR="$SP" bash "$SCRIPT_DIR/sdx-stage.sh" init s7 feature Discovery interactive sdx/s7 false false >/dev/null 2>&1
  SF="$SP/.claude/sessions/s7/session_state.json"
  before="$(jq -S 'del(.commitment)' "$SF")"
  run_oi stamp-state --sid s7 --commitment C-ACME-001 --proj "$SP"
  if [ "$RC" -eq 0 ] && [ "$(jq -r .commitment "$SF")" = "C-ACME-001" ] && [ "$(jq -S 'del(.commitment)' "$SF")" = "$before" ]; then pass "[O7] stamp-state adds commitment and leaves the other keys alone"
  else fail "[O7] stamp-state" "rc=$RC err=[$ERR] state=$(jq -c . "$SF")"; fi
  cp "$SF" "$TMP/sf.before"
  run_oi stamp-state --sid s7 --commitment C-ACME-001 --proj "$SP"
  if [ "$RC" -eq 0 ] && cmp -s "$SF" "$TMP/sf.before"; then pass "[O7] stamp-state is idempotent (same value: rc 0, file unchanged)"; else fail "[O7] idempotent" "rc=$RC"; fi
  run_oi stamp-state --sid s7 --commitment C-OTHER-002 --proj "$SP"
  if [ "$RC" -eq 1 ] && cmp -s "$SF" "$TMP/sf.before" && printf '%s' "$ERR" | grep -q 'commitment'; then pass "[O7] stamp-state refuses another value (rc 1, file unchanged)"; else fail "[O7] other value" "rc=$RC err=[$ERR]"; fi
  run_oi stamp-state --sid s7 --commitment 'a/b' --proj "$SP"
  if [ "$RC" -eq 1 ] && cmp -s "$SF" "$TMP/sf.before"; then pass "[O7] stamp-state refuses an invalid C (rc 1, file unchanged)"; else fail "[O7] invalid C" "rc=$RC"; fi
  run_oi stamp-state --sid nosuch --commitment C-ACME-001 --proj "$SP"
  if [ "$RC" -eq 1 ] && [ ! -e "$SP/.claude/sessions/nosuch" ]; then pass "[O7] stamp-state without a state file: rc 1, nothing created"; else fail "[O7] no state" "rc=$RC"; fi
  run_oi stamp-state --sid '../x' --commitment C-ACME-001 --proj "$SP"
  eq "[O7] stamp-state with a hostile sid: rc 1" "$RC" "1"
  run_oi stamp-state --commitment C-ACME-001 --proj "$SP"
  eq "[O7] stamp-state without --sid: usage, rc 2" "$RC" "2"
  eq "[O7] no temporary files left beside session_state.json" "$(ls "$SP/.claude/sessions/s7" | sort | tr '\n' ' ')" "session.log session_state.json "
  # a state of the stamped session is still valid for sdx-stage.sh
  mkdir -p "$SP/.claude/sessions/s7"; printf 'x\n' > "$SP/.claude/sessions/s7/context_report.md"
  out="$(CLAUDE_PROJECT_DIR="$SP" bash "$SCRIPT_DIR/sdx-stage.sh" next s7 2>&1)"
  if [ "$out" = "OK Discovery -> Business Spec" ] && [ "$(jq -r .commitment "$SF")" = "C-ACME-001" ]; then pass "[O7] sdx-stage.sh next works on the stamped state and keeps the field"; else fail "[O7] next after stamp" "out=[$out]"; fi
else
  fail "[O7] fixture" "the fixture could not be built"
fi
fi

#@@SECTIONS-END@@

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
