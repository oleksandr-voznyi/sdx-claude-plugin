#!/usr/bin/env bash
# sdx/hooks/lib/pkg-fixture.sh — shared TEST helper of the FEAT-017 suites (test-pr-build/-pr-check/-pr-publish).
# Sourced, not executed; not a suite (the name is not test-*.sh). bash 3.2, no arrays. FROZEN after the foundation
# track: the lanes only call these functions. The python interpreter appears here ONLY inside `pkg_oracle`, the test
# oracle (a transliteration of the formal checks of audit() of the node, sim-kit core/dev.py:340-424 — read as data,
# never imported); no production file uses it. Self-checked by test-pkg-fixture.sh.
#
#   pkg_fixture_template <workdir>   builds the template ONCE per run under <workdir>/tpl and exports PKG_FIXTURE_TEMPLATE
#                                    (an inherited valid PKG_FIXTURE_TEMPLATE is reused: nested mutant runs). Also exports a
#                                    hermetic git environment (GIT_CONFIG_NOSYSTEM=1, GIT_CONFIG_GLOBAL=<tpl>/gitconfig).
#   pkg_fixture_copy <dst>           cp -Rp of the template to <dst>/{wc,remote.git}; sets PKG_WC, PKG_REMOTE; origin and an
#                                    insteadOf rule point at the copy's own remote (the order's repo.url is the template's)
#   pkg_craft_good <wc> [branch]     a correct package built by plumbing independent of pr-build.sh -> PKG_BRANCH_MADE
#                                    PKG_HEAD PKG_TIP PKG_BASE (default branch change/C-ACME-001-ex1)
#   pkg_craft_bad_<kind> <wc> [branch]   a package with exactly one defect; kinds: see test-pkg-fixture.sh
#   pkg_oracle <wc> <branch> [target=dev] [out-of-band expectations from PKG_C / mandate file]
#                                    prints "approve" or "<reject|return> <check ids>"; rc 77 = no python3/PyYAML
#
# Fixture world (constants): session s1 on branch sdx/s1 cut from dev; commitment C-ACME-001; executor ex1;
# mandate digest 123456789012; paths src/mod1/**, shared package-lock.json, docs docs/**, branches change/*.
# The test command .claude/sdx/verify-cmd.sh exits with $PKG_VERIFY_EXIT (default 0).

PKG_SID=s1
PKG_C=C-ACME-001
PKG_EXEC=ex1
PKG_DIGEST=123456789012

pkg_fixture_template() {
  local work="$1" tpl
  if [ -n "${PKG_FIXTURE_TEMPLATE:-}" ] && [ -d "$PKG_FIXTURE_TEMPLATE/wc/.git" ]; then
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$PKG_FIXTURE_TEMPLATE/gitconfig"
    return 0
  fi
  tpl="$work/tpl"
  rm -rf "$tpl"; mkdir -p "$tpl" || return 1
  printf '[init]\n\tdefaultBranch = dev\n[commit]\n\tgpgsign = false\n[core]\n\thooksPath = /dev/null\n[advice]\n\tdetachedHead = false\n[protocol "file"]\n\tallow = always\n' > "$tpl/gitconfig"
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$tpl/gitconfig"
  (
    set -e
    git init -q --bare "$tpl/remote.git"
    git init -q "$tpl/wc"; cd "$tpl/wc"
    git config user.name fixture; git config user.email fixture@example.invalid
    mkdir -p src/mod1 src/core docs/specs .claude/sdx
    printf 'fixture\n' > README.md
    printf 'a=1\n' > src/mod1/a.js; printf 'b=1\n' > src/core/b.js; printf '{}\n' > package-lock.json
    printf '# Decisions\n\n## ADR-001. Base\n' > docs/DECISIONS.md; printf '# mod1\n' > docs/specs/mod1.md
    printf '#!/usr/bin/env bash\nexit "${PKG_VERIFY_EXIT:-0}"\n' > .claude/sdx/verify-cmd.sh
    git add -A; git commit -q -m base
    git remote add origin "$tpl/remote.git"; git push -q origin dev; git fetch -q origin
    git checkout -q -b "sdx/$PKG_SID"
    mkdir -p ".claude/sessions/$PKG_SID"
    printf '{"stage":"Closeout","type":"feature"}\n' > ".claude/sessions/$PKG_SID/session_state.json"
    {
      printf 'order:\n  format: 1\n  source: "msg"\n  source_ref: "m-20261031-001"\n  commitment:\n    id: "%s"\n    kind: "change"\n' "$PKG_C"
      printf '    title: "Feature mod1"\n    requirements: "Implement mod1"\n    due: "2026-12-01"\n    creditor: "acme"\n'
      printf '  executor: "%s"\n  mandate_digest: "%s"\n  repo:\n    id: "app"\n    url: "%s/remote.git"\n    base: "dev"\n' "$PKG_EXEC" "$PKG_DIGEST" "$tpl"
      printf '  deliver:\n    branch: "change/%s-%s"\n    delivery: "pr"\n' "$PKG_C" "$PKG_EXEC"
    } > ".claude/sessions/$PKG_SID/order.yaml"
    printf -- '- 2026-10-31 [design] Use approach A. Because it is simple.\n' > ".claude/sessions/$PKG_SID/decisions_log.md"
    printf '# Verification\n\n## Сводка\nИтог: PASS\n' > ".claude/sessions/$PKG_SID/verification_report.md"
    printf '# Change note\n\nmod1 feature\n' > ".claude/sessions/$PKG_SID/change_note.md"
    git add -A; git commit -q -m "s1 session"
    printf 'a=2\n' >> src/mod1/a.js; printf '\n' >> package-lock.json
    printf '\n## ADR-099. New decision\n' >> docs/DECISIONS.md; printf 'more\n' >> docs/specs/mod1.md
    git add -A; git commit -q -m "s1 code"
    git rm -r -q ".claude/sessions/$PKG_SID"; git commit -q -m "s1 close"
    mkdir -p .mesh
    printf 'endpoint:\n  on_write: notice\n' > .mesh/endpoint.yaml
    {
      printf "mandate:\n  repo: app\n  stages:\n  - spec\n  - design\n  - execute\n  - verify\n  scope:\n    paths:\n    - src/mod1/**\n    shared_paths:\n    - package-lock.json\n"
      printf "    docs_paths:\n    - docs/**\n    branches:\n    - change/*\n  delivery: pr\n  history: executor\n  docs_in_repo: final\n"
      printf "  valid_until: '2099-01-01'\n  on_write: deny\n  executor: %s\n  digest: '%s'\n  format: 1\n" "$PKG_EXEC" "$PKG_DIGEST"
    } > .mesh/mandate.yaml
    printf '.mesh/\n' >> .git/info/exclude
  ) >/dev/null 2>&1 || { rm -rf "$tpl"; return 1; }
  export PKG_FIXTURE_TEMPLATE="$tpl"
  return 0
}

pkg_fixture_copy() {
  local dst="$1" tpl="${PKG_FIXTURE_TEMPLATE:-}"
  [ -d "$tpl/wc/.git" ] || return 1
  mkdir -p "$dst" && cp -Rp "$tpl/wc" "$dst/wc" && cp -Rp "$tpl/remote.git" "$dst/remote.git" || return 1
  git -C "$dst/wc" remote set-url origin "$dst/remote.git" || return 1
  git -C "$dst/wc" config "url.$dst/remote.git.insteadOf" "$tpl/remote.git" || return 1
  PKG_WC="$dst/wc"; PKG_REMOTE="$dst/remote.git"
  return 0
}

# pkg_oracle <wc> <branch> [target=dev]: an INDEPENDENT second implementation of the formal checks of audit() of the
# node (sim-kit core/dev.py:340-424, read as data): manifest_of, format, manifest.commit (tip^ == head, the difference
# is exactly CHANGE.yaml), commitment/executor/mandate_digest against the local mandate, branch by fnmatch, nonempty,
# scope by glob_any (DEV:67-68), shared.declared, archive_sha256, secrets (DEFAULT_REDACT), adr. NOT reproduced: the
# commitment registry state, the test suites of the stand and the LLM review. The mandate comes from <wc>/.mesh/mandate.yaml
# (the node's registry entry), the commitment from $PKG_C. Output: "approve" | "<reject|return> <id,id,...>". rc 77: no
# python3/PyYAML (the suites print INFO and skip — never PASS). PKG_PYTHON overrides the interpreter (tests).
pkg_oracle() {
  local wc="$1" br="$2" target="${3:-dev}" py="${PKG_PYTHON:-python3}"
  command -v "$py" >/dev/null 2>&1 || return 77
  "$py" -I -B - "$wc" "$br" "$target" "$PKG_C" <<'PY'
import sys, subprocess, fnmatch, hashlib, re, datetime
try:
    import yaml
except ImportError:
    sys.exit(77)
wc, ref, target, cid_expected = sys.argv[1:5]
MANIFEST, FORMAT = "CHANGE.yaml", 1
REDACT = [
    r'(?i)("?(?:password|passwd|pwd|secret|token|api[_-]?key|client[_-]?secret)"?\s*[:=]\s*)("[^"]*"|[^\s,;}]+)',
    r'(?i)(authorization:\s*(?:basic|bearer)\s+)(\S+)',
    r'(?i)((?:mongodb(?:\+srv)?|postgres(?:ql)?|mysql|redis|amqp)://[^:/@\s]+:)([^@\s]+)(?=@)',
]
def git(args, binary=False):
    r = subprocess.run(["git", "-C", wc] + args, capture_output=True)
    if r.returncode:
        raise RuntimeError("git " + " ".join(args) + ": " + r.stderr.decode("utf-8", "replace")[-200:])
    return r.stdout if binary else r.stdout.decode("utf-8", "replace")
def glob_any(path, pats):   # DEV:67-68
    return any(fnmatch.fnmatch(path, p) or fnmatch.fnmatch(path, p.rstrip("/") + "/*") or path.startswith(p.rstrip("*").rstrip("/") + "/") for p in pats)
def changed(a, b):
    return [x for x in git(["diff", "--name-only", a + ".." + b]).splitlines() if x]
def out(verdict, ids):
    print(verdict + (" " + ",".join(ids) if ids else "")); sys.exit(0)
try:
    tip = git(["rev-parse", "--verify", "-q", "refs/heads/" + ref + "^{commit}"]).strip()
except RuntimeError:
    print("reject ref"); sys.exit(3)
mnd = (yaml.safe_load(open(wc + "/.mesh/mandate.yaml", encoding="utf-8").read()) or {}).get("mandate") or {}
try:
    txt = git(["show", tip + ":" + MANIFEST])
except RuntimeError:
    out("reject", ["manifest"])
try:
    d = yaml.safe_load(txt) or {}
except yaml.YAMLError:
    out("reject", ["manifest"])
man = d.get("change") or d
checks = []
def ck(name, ok, level="reject"):
    checks.append((name, bool(ok), level)); return ok
head = tip
code_head = str(man.get("head") or tip)
ck("format", man.get("format") == FORMAT)
if code_head != tip:
    try:
        only = changed(code_head, tip)
        ok = git(["rev-parse", tip + "^"]).strip() == code_head and only == [MANIFEST]
    except RuntimeError:
        ok = False
    ck("manifest.commit", ok)
    head = code_head
ck("commitment", str(man.get("commitment") or "") == cid_expected)
eid = str(man.get("executor") or "")
ck("mandate", bool(mnd) and eid == str(mnd.get("executor")))
sc = mnd.get("scope") or {}
ck("mandate.valid", str(mnd.get("valid_until", "")) >= datetime.date.today().isoformat())
if mnd.get("digest") or man.get("mandate_digest"):
    md = str(mnd.get("digest"))
    ck("mandate.digest", str(man.get("mandate_digest", md))[:12] == md, level="return")
if sc.get("branches"):
    ck("branch", any(fnmatch.fnmatch(ref, b) for b in sc["branches"]))
try:
    base = git(["merge-base", head, "refs/heads/" + target]).strip()
except RuntimeError:
    base = str(man.get("base") or head)
files = [f for f in changed(base, tip) if f != MANIFEST]
ck("nonempty", bool(files), level="return")
shared_list = sc.get("shared_paths") or []
docs_list = sc.get("docs_paths") or ["docs/**"]
outside = [f for f in files if sc.get("paths") and not glob_any(f, sc["paths"]) and not glob_any(f, shared_list) and not glob_any(f, docs_list)]
ck("scope", not outside)
shared = [f for f in files if shared_list and glob_any(f, shared_list)]
if shared:
    ck("shared.declared", bool(man.get("touches_shared")), level="return")
if man.get("archive_sha256"):
    ck("archive_sha256", man["archive_sha256"] == hashlib.sha256(git(["archive", "--format=tar", head], binary=True)).hexdigest())
else:
    ck("archive_sha256", False, level="return")
hits = []
for line in git(["diff", base + ".." + tip]).splitlines():
    if line.startswith("+") and not line.startswith("+++"):
        for pt in REDACT:
            mt = re.search(pt, line)
            if mt and mt.group(2).strip('"') not in ("***", "", "null", "None", "changeme", "<secret>", "${", "$"):
                hits.append(line[:40]); break
ck("secrets", not hits)
if mnd.get("docs_in_repo", "final") == "final":
    adr = man.get("adr")
    adrs = [str(a).split("#")[0] for a in (adr if isinstance(adr, list) else [adr])] if adr else []
    ck("adr", bool(adrs) and all(a in files for a in adrs), level="return")
bad = [c for c in checks if not c[1]]
if not bad:
    out("approve", [])
out("reject" if any(c[2] == "reject" for c in bad) else "return", [c[0] for c in bad])
PY
}

# ---------------------------------------------------------------------------------------------------------------
# Package factories. Plumbing only (commit-tree, temporary index, update-ref): no checkout, no pr-build.sh — an
# independent construction of the SAME artefact, so a defect shared by pr-build and its test cannot hide.
# _pkg_build reads knobs from the caller's locals (bash dynamic scope), every knob optional:
#   K_HEAD_FILES     "path=content" lines added to the code tree          K_MANIFEST_EXTRA  "path=content" lines added to the manifest commit
#   K_MID_COMMIT=1   an extra commit between head and the manifest commit  K_MANIFEST_IN_HEAD=1  CHANGE.yaml inside head, no head/archive keys
#   K_ARCHIVE        archive_sha256 override        K_FORMAT  K_COMMITMENT  K_EXECUTOR  K_DIGEST  K_NOTES  K_TOUCHES_SHARED  K_SCOPE_TOUCHED(lines)
#   K_NO_ADR=1       adr: []
# Sets PKG_BRANCH_MADE PKG_BASE PKG_HEAD PKG_TIP. The branch is (re)created with update-ref — the factories build fakes.
# ---------------------------------------------------------------------------------------------------------------

# _pkg_yaml_list <indent> <newline-separated items> -> stdout: " []" or "\n<indent>- \"item\"..."
_pkg_yaml_list() {
  local ind="$1" items="$2" it out=""
  if [ -z "$items" ]; then printf ' []'; return 0; fi
  while IFS= read -r it; do [ -n "$it" ] && out="$out"$'\n'"$ind- \"$it\""; done <<< "$items"
  printf '%s' "$out"
}

# _pkg_add_files <index-file> <wc> <"path=content" lines>
_pkg_add_files() {
  local idx="$1" wc="$2" line p c blob
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    p="${line%%=*}"; c="${line#*=}"
    blob="$(printf '%s\n' "$c" | git -C "$wc" hash-object -w --stdin)" || return 1
    GIT_INDEX_FILE="$idx" git -C "$wc" update-index --add --cacheinfo "100644,$blob,$p" || return 1
  done <<< "$3"
}

_pkg_build() {
  local wc="$1" br="${2:-change/$PKG_C-$PKG_EXEC}" base tree0 tree head tip parent mid idx files shared touches docs spec adr asha
  local zero="0000000000000000000000000000000000000000" manifest mblob mtree
  idx="$(mktemp -u "${TMPDIR:-/tmp}/pkg-craft-idx.XXXXXX")"
  base="$(git -C "$wc" rev-parse --verify -q refs/heads/dev)" || return 1
  GIT_INDEX_FILE="$idx" git -C "$wc" read-tree "refs/heads/sdx/$PKG_SID" || { rm -f "$idx"; return 1; }
  _pkg_add_files "$idx" "$wc" "${K_HEAD_FILES:-}" || { rm -f "$idx"; return 1; }
  tree0="$(GIT_INDEX_FILE="$idx" git -C "$wc" write-tree)" || { rm -f "$idx"; return 1; }
  files="$(git -C "$wc" diff --name-only "$base" "$tree0")"
  if [ -n "${K_SCOPE_TOUCHED:-}" ]; then touches="$K_SCOPE_TOUCHED"; else touches="$files"; fi
  case $'\n'"$files"$'\n' in *$'\npackage-lock.json\n'*) shared=true ;; *) shared=false ;; esac
  [ -z "${K_TOUCHES_SHARED:-}" ] || shared="$K_TOUCHES_SHARED"
  docs="$(printf '%s\n' "$files" | grep '^docs/' || true)"
  spec="docs/specs/mod1.md@$(git -C "$wc" log -n1 --format=%h "refs/heads/sdx/$PKG_SID" -- docs/specs/mod1.md 2>/dev/null)"
  if [ -n "${K_NO_ADR:-}" ]; then adr=""; else adr="docs/DECISIONS.md#ADR-099"; fi
  # the manifest text (fixed layout; every string double-quoted; independent of pr-build's template-driven renderer)
  _pkg_manifest_text() {  # <head-or-empty> <archive-or-empty>
    printf 'change:\n  format: %s\n  commitment: "%s"\n  executor: "%s"\n  mandate_digest: "%s"\n  base: "%s"\n' \
      "${K_FORMAT:-1}" "${K_COMMITMENT:-$PKG_C}" "${K_EXECUTOR:-$PKG_EXEC}" "${K_DIGEST:-$PKG_DIGEST}" "$base"
    [ -z "$1" ] || printf '  head: "%s"\n' "$1"
    [ -z "$2" ] || printf '  archive_sha256: "%s"\n' "$2"
    printf '  scope_touched:%s\n  touches_shared: %s\n  spec: "%s"\n  verify:\n    tests: "pass"\n    report: "sdx/%s@fixture:.claude/sessions/%s/verification_report.md"\n' \
      "$(_pkg_yaml_list '    ' "$touches")" "$shared" "$spec" "$PKG_SID" "$PKG_SID"
    printf '  adr:%s\n  docs:%s\n  history_ref: "executor:sdx/%s"\n  notes: "%s"\n' \
      "$(_pkg_yaml_list '    ' "$adr")" "$(_pkg_yaml_list '    ' "$docs")" "$PKG_SID" "${K_NOTES:-fixture}"
  }
  if [ -n "${K_MANIFEST_IN_HEAD:-}" ]; then
    mblob="$(_pkg_manifest_text "" "" | git -C "$wc" hash-object -w --stdin)"
    GIT_INDEX_FILE="$idx" git -C "$wc" update-index --add --cacheinfo "100644,$mblob,CHANGE.yaml"
    tree="$(GIT_INDEX_FILE="$idx" git -C "$wc" write-tree)"
    head="$(printf 'fixture: head with manifest\n' | git -C "$wc" commit-tree "$tree" -p "$base")"
    tip="$head"
  else
    head="$(printf 'fixture: head\n' | git -C "$wc" commit-tree "$tree0" -p "$base")" || { rm -f "$idx"; return 1; }
    asha="${K_ARCHIVE:-$(git -C "$wc" -c tar.umask=0002 archive --format=tar "$head" | _pkg_sha256)}"
    mblob="$(_pkg_manifest_text "$head" "$asha" | git -C "$wc" hash-object -w --stdin)"
    rm -f "$idx"
    GIT_INDEX_FILE="$idx" git -C "$wc" read-tree "$head"
    GIT_INDEX_FILE="$idx" git -C "$wc" update-index --add --cacheinfo "100644,$mblob,CHANGE.yaml"
    _pkg_add_files "$idx" "$wc" "${K_MANIFEST_EXTRA:-}"
    mtree="$(GIT_INDEX_FILE="$idx" git -C "$wc" write-tree)"
    parent="$head"
    if [ -n "${K_MID_COMMIT:-}" ]; then parent="$(printf 'fixture: extra\n' | git -C "$wc" commit-tree "$tree0" -p "$head")"; fi
    tip="$(printf 'fixture: manifest\n' | git -C "$wc" commit-tree "$mtree" -p "$parent")"
  fi
  rm -f "$idx"
  git -C "$wc" update-ref "refs/heads/$br" "$tip" || return 1
  PKG_BRANCH_MADE="$br"; PKG_BASE="$base"; PKG_HEAD="$head"; PKG_TIP="$tip"
  return 0
}

# sha256 of stdin (independent of lib/pr-lib.sh: a shared defect must not hide)
_pkg_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi
}

# pkg_craft_good <wc> [branch]: a correct package
pkg_craft_good() { _pkg_build "$1" "${2:-}"; }
# one defect each
pkg_craft_bad_extra_commit() { local K_MID_COMMIT=1; _pkg_build "$1" "${2:-}"; }
pkg_craft_bad_foreign_file() { local K_MANIFEST_EXTRA="docs/extra.md=x"; _pkg_build "$1" "${2:-}"; }
pkg_craft_bad_bad_archive() { local K_ARCHIVE="0000000000000000000000000000000000000000000000000000000000000000"; _pkg_build "$1" "${2:-}"; }
pkg_craft_bad_out_of_scope() { local K_HEAD_FILES="src/core/b.js=b=2"; _pkg_build "$1" "${2:-}"; }
pkg_craft_bad_shared_undeclared() { local K_TOUCHES_SHARED=false; _pkg_build "$1" "${2:-}"; }
pkg_craft_bad_session_dir() { local K_HEAD_FILES=".claude/sessions/$PKG_SID/order.yaml=leaked"; _pkg_build "$1" "${2:-}"; }
pkg_craft_bad_format2() { local K_FORMAT=2; _pkg_build "$1" "${2:-}"; }
pkg_craft_bad_manifest_in_head() { local K_MANIFEST_IN_HEAD=1; _pkg_build "$1" "${2:-}"; }
# audit() recomputes scope_touched itself: the oracle is blind to this defect BY DESIGN (the manifest-vs-diff check is pr-check's own)
pkg_craft_bad_fake_scope() { local K_SCOPE_TOUCHED="src/mod1/never-touched.js"; _pkg_build "$1" "${2:-}"; }
pkg_craft_bad_secret_notes() { local K_NOTES="password: hunter2"; _pkg_build "$1" "${2:-}"; }
pkg_craft_bad_wrong_commitment() { local K_COMMITMENT="C-OTHER-9"; _pkg_build "$1" "${2:-}"; }
pkg_craft_bad_wrong_executor() { local K_EXECUTOR="ex9"; _pkg_build "$1" "${2:-}"; }
pkg_craft_bad_wrong_digest() { local K_DIGEST="999999999999"; _pkg_build "$1" "${2:-}"; }
# the branch argument is ignored: the point is a branch name outside scope.branches (change/*); see PKG_BRANCH_MADE
pkg_craft_bad_bad_branch() { _pkg_build "$1" "feat/pkg-bad"; }
pkg_craft_bad_no_adr() { local K_NO_ADR=1; _pkg_build "$1" "${2:-}"; }
