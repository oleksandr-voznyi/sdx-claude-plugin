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
