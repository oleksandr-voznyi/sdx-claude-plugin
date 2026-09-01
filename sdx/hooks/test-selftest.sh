#!/usr/bin/env bash
# Unit/mutation tests for selftest.sh (FEAT-014 + DEBT-010).
#
# Covers PLAN.md T09-T21 / DESIGN.md "Тестовая стратегия" for sdx/hooks/selftest.sh. Every
# property below is a pair (green / red) — a green-only assertion proves nothing about whether
# the check actually discriminates, so each scenario demonstrably flips to red via a concrete
# mutation (decoy hook, seeded config, env override), not just asserted "should be true".
#
# Runs self-contained: everything happens under mktemp -d fixtures (or, where the DESIGN
# explicitly calls for it — T13 — against THIS repo's own real session, with careful
# backup/restore so no observable state survives the test run). No test in this file depends on
# hooks/hooks.json, ${CLAUDE_PLUGIN_ROOT}, or an installed copy of the plugin — selftest.sh is
# invoked directly (`bash sdx/hooks/selftest.sh`), exactly like every other test-*.sh in this
# directory (see PLAN.md "Ограничение среды исполнения").
#
# Usage: bash sdx/hooks/test-selftest.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SELFTEST="$SCRIPT_DIR/selftest.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# ---- generic helpers -------------------------------------------------------

# build_real_hooks_fixture <dir>
#   Populates <dir> with copies of the three REAL hooks under test (preflight.sh,
#   prod-guard.sh, stop-gate.sh) plus lib/resolve-session.sh (stop-gate.sh sources it
#   relative to its OWN location, which after copying is <dir>, not $SCRIPT_DIR).
build_real_hooks_fixture() {
  local dir="$1"
  mkdir -p "$dir/lib"
  cp "$SCRIPT_DIR/preflight.sh" "$dir/preflight.sh"
  cp "$SCRIPT_DIR/prod-guard.sh" "$dir/prod-guard.sh"
  cp "$SCRIPT_DIR/stop-gate.sh" "$dir/stop-gate.sh"
  cp "$SCRIPT_DIR/lib/resolve-session.sh" "$dir/lib/resolve-session.sh"
}

# run_selftest — invokes selftest.sh with the env vars named below (empty string == unset,
# selftest.sh's `${VAR:-default}` resolution treats both the same way). Captures stderr into
# RS_STDERR (stdout is never used by selftest.sh, per DESIGN.md — discarded), exit code into
# RS_EC. Reads: RS_PROJ RS_PLUGIN_ROOT RS_HOOKS_DIR RS_BUDGET RS_FORCE RS_PATH.
RS_EC=0
RS_STDERR=""
run_selftest() {
  RS_EC=0
  RS_STDERR="$(
    CLAUDE_PROJECT_DIR="${RS_PROJ:-}" \
    CLAUDE_PLUGIN_ROOT="${RS_PLUGIN_ROOT:-}" \
    SDX_SELFTEST_HOOKS_DIR="${RS_HOOKS_DIR:-}" \
    SDX_SELFTEST_BUDGET_MS="${RS_BUDGET:-}" \
    SDX_SELFTEST_FORCE="${RS_FORCE:-}" \
    PATH="${RS_PATH:-$PATH}" \
    bash "$SELFTEST" 2>&1 >/dev/null
  )"
  RS_EC=$?
}

# cache_field <file> <field>  — extract a quoted-string field's value (grep -o, no jq).
cache_field() {
  grep -o "\"$2\":\"[^\"]*\"" "$1" 2>/dev/null | head -1 | sed -E "s/.*\"$2\":\"([^\"]*)\"\$/\1/"
}
# cache_field_raw <file> <field> — extract a non-string (number/bool) field's value.
cache_field_raw() {
  grep -o "\"$2\":[^,}]*" "$1" 2>/dev/null | head -1 | sed -E "s/\"$2\"://"
}

echo "=== test-selftest.sh ==="
echo ""

# =============================================================================
# T09 — probe_preflight reacts to the probed script's behaviour (REQ-ST-2)
# =============================================================================
echo "[T09] probe_preflight: green (real preflight.sh) / red (decoy exit 1)"
{
  proj_g="$(mktemp -d)"; hooks_g="$(mktemp -d)"; build_real_hooks_fixture "$hooks_g"
  RS_PROJ="$proj_g" RS_HOOKS_DIR="$hooks_g" RS_FORCE=1 run_selftest
  cache_g="$proj_g/.claude/sdx/.cache/selftest.json"
  val="$(cache_field "$cache_g" preflight)"
  if [ "$val" = pass ]; then pass "T09 green: real preflight.sh -> preflight=pass"; else fail "T09 green" "preflight=$val"; fi
  rm -rf "$proj_g" "$hooks_g"

  proj_r="$(mktemp -d)"; hooks_r="$(mktemp -d)"; build_real_hooks_fixture "$hooks_r"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$hooks_r/preflight.sh"   # decoy: always fails
  RS_PROJ="$proj_r" RS_HOOKS_DIR="$hooks_r" RS_FORCE=1 run_selftest
  cache_r="$proj_r/.claude/sdx/.cache/selftest.json"
  pf="$(cache_field "$cache_r" preflight)"; pg="$(cache_field "$cache_r" prod_guard)"; sg="$(cache_field "$cache_r" stop_gate)"
  if [ "$pf" = fail ] && [ "$pg" = pass ] && [ "$sg" = pass ]; then
    pass "T09 red: decoy preflight.sh (exit 1) -> preflight=fail, prod_guard/stop_gate unaffected (pass)"
  else
    fail "T09 red" "preflight=$pf prod_guard=$pg stop_gate=$sg"
  fi
  rm -rf "$proj_r" "$hooks_r"
}

# =============================================================================
# T10 — probe_prod_guard discriminates BOTH sides of the deny/no-op body (REQ-ST-2)
# =============================================================================
echo "[T10] probe_prod_guard: green (real) / red-1 (always empty) / red-2 (always deny)"
{
  proj_g="$(mktemp -d)"; hooks_g="$(mktemp -d)"; build_real_hooks_fixture "$hooks_g"
  RS_PROJ="$proj_g" RS_HOOKS_DIR="$hooks_g" RS_FORCE=1 run_selftest
  val="$(cache_field "$proj_g/.claude/sdx/.cache/selftest.json" prod_guard)"
  if [ "$val" = pass ]; then pass "T10 green: real prod-guard.sh -> prod_guard=pass"; else fail "T10 green" "prod_guard=$val"; fi
  rm -rf "$proj_g" "$hooks_g"

  proj_r1="$(mktemp -d)"; hooks_r1="$(mktemp -d)"; build_real_hooks_fixture "$hooks_r1"
  printf '#!/usr/bin/env bash\ncat >/dev/null\nexit 0\n' > "$hooks_r1/prod-guard.sh"   # always empty stdout
  RS_PROJ="$proj_r1" RS_HOOKS_DIR="$hooks_r1" RS_FORCE=1 run_selftest
  val="$(cache_field "$proj_r1/.claude/sdx/.cache/selftest.json" prod_guard)"
  if [ "$val" = fail ]; then pass "T10 red-1: decoy always-empty-stdout -> prod_guard=fail"; else fail "T10 red-1" "prod_guard=$val"; fi
  rm -rf "$proj_r1" "$hooks_r1"

  proj_r2="$(mktemp -d)"; hooks_r2="$(mktemp -d)"; build_real_hooks_fixture "$hooks_r2"
  printf '#!/usr/bin/env bash\ncat >/dev/null\nprintf %%s '"'"'{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"decoy"}}'"'"'\nexit 0\n' \
    > "$hooks_r2/prod-guard.sh"   # always deny, even for the "unmatched" probe call
  RS_PROJ="$proj_r2" RS_HOOKS_DIR="$hooks_r2" RS_FORCE=1 run_selftest
  val="$(cache_field "$proj_r2/.claude/sdx/.cache/selftest.json" prod_guard)"
  if [ "$val" = fail ]; then pass "T10 red-2: decoy always-deny -> prod_guard=fail (symmetry of discrimination)"; else fail "T10 red-2" "prod_guard=$val"; fi
  rm -rf "$proj_r2" "$hooks_r2"
}

# =============================================================================
# T11 — prod_guard probe isolation from the REAL project's prod-guard.conf (REQ-ST-5)
# =============================================================================
echo "[T11] probe_prod_guard isolation: seeded real conf must NOT influence the probe's own fixture"
{
  proj="$(mktemp -d)"; hooks="$(mktemp -d)"; build_real_hooks_fixture "$hooks"
  mkdir -p "$proj/.claude/sdx"
  # Seed the EXTERNAL CLAUDE_PROJECT_DIR's real prod-guard.conf with a pattern matching "ls -la"
  # — an innocuous command that the probe's OWN synthetic fixture expects to pass through as
  # no-op. If the probe read THIS conf instead of its own isolated one, "ls -la" would be denied.
  printf 'ls -la\n' > "$proj/.claude/sdx/prod-guard.conf"

  # Control comparison (required by DoD): prove the seeded conf really is dangerous by invoking
  # prod-guard.sh directly against it, OUTSIDE selftest's isolation — this is what would happen
  # if probe_prod_guard used $proj instead of its own mktemp -d fixture.
  control_out="$(printf '{"tool_input":{"command":"ls -la"}}' | CLAUDE_PROJECT_DIR="$proj" bash "$hooks/prod-guard.sh" 2>/dev/null)"
  if printf '%s' "$control_out" | grep -q '"permissionDecision":"deny"'; then
    pass "T11 control: reading \$proj's real prod-guard.conf directly WOULD deny 'ls -la' (seed confirmed dangerous)"
  else
    fail "T11 control: seeded conf did not deny 'ls -la' directly — test fixture invalid" "out=$control_out"
  fi

  # Actual: selftest.sh run against this same $proj must remain isolated (prod_guard=pass).
  RS_PROJ="$proj" RS_HOOKS_DIR="$hooks" RS_FORCE=1 run_selftest
  val="$(cache_field "$proj/.claude/sdx/.cache/selftest.json" prod_guard)"
  if [ "$val" = pass ]; then
    pass "T11: selftest.sh's prod_guard probe stayed pass despite \$proj's real (dangerous) conf — isolation holds"
  else
    fail "T11: probe was influenced by the real project's prod-guard.conf" "prod_guard=$val"
  fi
  rm -rf "$proj" "$hooks"
}

# =============================================================================
# T12 — probe_stop_gate discriminates exit 0 vs exit 2, DEBT-026 form (REQ-ST-3)
# =============================================================================
echo "[T12] probe_stop_gate: green (real, DEBT-026 0600 verify-cmd.sh) / red (decoy always exit 0)"
{
  proj_g="$(mktemp -d)"; hooks_g="$(mktemp -d)"; build_real_hooks_fixture "$hooks_g"
  RS_PROJ="$proj_g" RS_HOOKS_DIR="$hooks_g" RS_FORCE=1 run_selftest
  val="$(cache_field "$proj_g/.claude/sdx/.cache/selftest.json" stop_gate)"
  if [ "$val" = pass ]; then pass "T12 green: real stop-gate.sh, DEBT-026 fixture -> stop_gate=pass (exit 2 observed)"; else fail "T12 green" "stop_gate=$val"; fi
  rm -rf "$proj_g" "$hooks_g"

  proj_r="$(mktemp -d)"; hooks_r="$(mktemp -d)"; build_real_hooks_fixture "$hooks_r"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$hooks_r/stop-gate.sh"   # decoy: always green
  RS_PROJ="$proj_r" RS_HOOKS_DIR="$hooks_r" RS_FORCE=1 run_selftest
  val="$(cache_field "$proj_r/.claude/sdx/.cache/selftest.json" stop_gate)"
  if [ "$val" = fail ]; then pass "T12 red: decoy always-exit-0 -> stop_gate=fail"; else fail "T12 red" "stop_gate=$val"; fi
  rm -rf "$proj_r" "$hooks_r"
}

# =============================================================================
# T13 — probe_stop_gate isolation from the REAL active session's .stopgate.* (REQ-ST-5)
# =============================================================================
echo "[T13] probe_stop_gate isolation: real session's .stopgate.* must survive byte-for-byte"
{
  real_branch="$(git -C "$ROOT" branch --show-current 2>/dev/null || true)"
  case "$real_branch" in
    sdx/*)
      real_sid="${real_branch#sdx/}"
      sess_dir="$ROOT/.claude/sessions/$real_sid"
      if [ -d "$sess_dir" ]; then
        backup_dir="$(mktemp -d)"
        for f in "$sess_dir"/.stopgate.*; do
          [ -e "$f" ] && cp -p "$f" "$backup_dir/$(basename "$f")"
        done
        cache_real="$ROOT/.claude/sdx/.cache/selftest.json"
        cache_existed=0
        if [ -f "$cache_real" ]; then cache_existed=1; cp -p "$cache_real" "$backup_dir/__cache.bak"; fi

        printf 'SENTINEL-COUNT\n' > "$sess_dir/.stopgate.count"
        printf 'SENTINEL-OUT\n' > "$sess_dir/.stopgate.out"
        printf 'SENTINEL-OK\n' > "$sess_dir/.stopgate.ok"
        b_count="$(md5sum "$sess_dir/.stopgate.count" | cut -d' ' -f1)"
        b_out="$(md5sum "$sess_dir/.stopgate.out" | cut -d' ' -f1)"
        b_ok="$(md5sum "$sess_dir/.stopgate.ok" | cut -d' ' -f1)"

        # Real CLAUDE_PROJECT_DIR, real branch/session — exactly what DESIGN.md prescribes.
        RS_PROJ="$ROOT" RS_HOOKS_DIR="$SCRIPT_DIR" RS_FORCE=1 run_selftest

        a_count="$(md5sum "$sess_dir/.stopgate.count" | cut -d' ' -f1)"
        a_out="$(md5sum "$sess_dir/.stopgate.out" | cut -d' ' -f1)"
        a_ok="$(md5sum "$sess_dir/.stopgate.ok" | cut -d' ' -f1)"

        if [ "$b_count" = "$a_count" ] && [ "$b_out" = "$a_out" ] && [ "$b_ok" = "$a_ok" ]; then
          pass "T13: real .stopgate.count/.out/.ok byte-for-byte unchanged after selftest run"
        else
          fail "T13: real .stopgate.* files were modified by selftest.sh" \
               "count $b_count->$a_count out $b_out->$a_out ok $b_ok->$a_ok"
        fi

        # Restore real session state exactly as found.
        rm -f "$sess_dir/.stopgate.count" "$sess_dir/.stopgate.out" "$sess_dir/.stopgate.ok"
        for f in "$backup_dir"/.stopgate.*; do
          [ -e "$f" ] && cp -p "$f" "$sess_dir/$(basename "$f")"
        done
        if [ "$cache_existed" -eq 1 ]; then
          cp -p "$backup_dir/__cache.bak" "$cache_real"
        else
          rm -f "$cache_real"
        fi
        rm -rf "$backup_dir"
      else
        echo "  SKIP: no session dir for current branch's sid — T13 requires the real session context"
      fi
      ;;
    *)
      echo "  SKIP: not on an sdx/<id> branch — T13 requires the real session context"
      ;;
  esac
}

# =============================================================================
# T14 — probe_stop_gate never runs the REAL project's verify-cmd.sh (REQ-ST-6)
# =============================================================================
echo "[T14] probe_stop_gate never triggers \$proj's real verify-cmd.sh"
{
  proj="$(mktemp -d)"
  mkdir -p "$proj/.claude/sdx"
  printf '#!/usr/bin/env bash\ntouch "%s/ran.marker"\nexit 0\n' "$proj" > "$proj/.claude/sdx/verify-cmd.sh"
  chmod +x "$proj/.claude/sdx/verify-cmd.sh"
  RS_PROJ="$proj" RS_HOOKS_DIR="$SCRIPT_DIR" RS_FORCE=1 run_selftest
  if [ ! -e "$proj/ran.marker" ]; then
    pass "T14: \$proj's real verify-cmd.sh (marker-touching) was NOT invoked by the stop_gate probe"
  else
    fail "T14: real verify-cmd.sh of \$proj was executed by selftest.sh" "ran.marker present"
  fi
  rm -rf "$proj"
}

# =============================================================================
# T15 — time budget is automatically checked, not just "looks fast enough" (REQ-ST-7)
# =============================================================================
echo "[T15] budget: green (normal run under default 2000ms) / red (slow decoy + tight budget)"
{
  proj_g="$(mktemp -d)"; hooks_g="$(mktemp -d)"; build_real_hooks_fixture "$hooks_g"
  RS_PROJ="$proj_g" RS_HOOKS_DIR="$hooks_g" RS_FORCE=1 run_selftest
  cache_g="$proj_g/.claude/sdx/.cache/selftest.json"
  dur="$(cache_field_raw "$cache_g" duration_ms)"
  exceeded="$(cache_field_raw "$cache_g" budget_exceeded)"
  if [ -n "$dur" ] && [ "$dur" -lt 2000 ] && [ "$exceeded" = false ]; then
    pass "T15 green: normal run duration_ms=$dur < 2000ms budget, budget_exceeded=false"
  else
    fail "T15 green" "duration_ms=$dur budget_exceeded=$exceeded"
  fi
  rm -rf "$proj_g" "$hooks_g"

  proj_r="$(mktemp -d)"; hooks_r="$(mktemp -d)"; build_real_hooks_fixture "$hooks_r"
  printf '#!/usr/bin/env bash\nsleep 1\nexit 2\n' > "$hooks_r/stop-gate.sh"   # artificially slow
  RS_PROJ="$proj_r" RS_HOOKS_DIR="$hooks_r" RS_BUDGET=100 RS_FORCE=1 run_selftest
  redec=$RS_EC
  cache_r="$proj_r/.claude/sdx/.cache/selftest.json"
  exceeded="$(cache_field_raw "$cache_r" budget_exceeded)"
  if [ "$exceeded" = true ] && [ "$redec" -eq 0 ]; then
    pass "T15 red: slow decoy (sleep 1s) + budget=100ms -> budget_exceeded=true, AND selftest.sh still exit 0"
  else
    fail "T15 red" "budget_exceeded=$exceeded selftest_ec=$redec"
  fi
  rm -rf "$proj_r" "$hooks_r"
}

# =============================================================================
# T16 — cache invalidated by plugin version change (REQ-ST-9)
# =============================================================================
echo "[T16] cache: 2nd unchanged run is a cache-hit / plugin version bump invalidates it"
{
  fx_plugin="$(mktemp -d)"; mkdir -p "$fx_plugin/.claude-plugin"
  printf '{"version":"9.9.9"}' > "$fx_plugin/.claude-plugin/plugin.json"
  hooks="$(mktemp -d)"; build_real_hooks_fixture "$hooks"
  proj="$(mktemp -d)"
  cache="$proj/.claude/sdx/.cache/selftest.json"

  RS_PROJ="$proj" RS_PLUGIN_ROOT="$fx_plugin" RS_HOOKS_DIR="$hooks" RS_FORCE="" run_selftest
  [ -f "$cache" ] || { fail "T16 setup" "cache not written on first run"; }
  fp1="$(cache_field "$cache" fingerprint)"
  # Backdate the cache file's mtime to an unmistakable past date. A cache-hit path
  # (`return 0` before ever calling write_cache) leaves the file byte-for-byte and
  # mtime-untouched; a recompute always rewrites it via mktemp+mv, giving it a fresh mtime.
  # This sidesteps `ts`'s 1-second string resolution, which could otherwise coincide across
  # runs executed within the same wall-clock second and make the "unchanged" assertion
  # trivially true for the wrong reason, or the "changed" assertion flaky.
  touch -d "1970-01-02" "$cache"
  mtime1="$(stat -c %Y "$cache")"

  RS_PROJ="$proj" RS_PLUGIN_ROOT="$fx_plugin" RS_HOOKS_DIR="$hooks" RS_FORCE="" run_selftest
  mtime2="$(stat -c %Y "$cache")"; fp2="$(cache_field "$cache" fingerprint)"
  if [ "$mtime2" = "$mtime1" ] && [ "$fp2" = "$fp1" ]; then
    pass "T16 green: unchanged env -> cache-hit (file untouched, fingerprint stable)"
  else
    fail "T16 green" "mtime $mtime1->$mtime2 fingerprint $fp1->$fp2"
  fi

  printf '{"version":"9.9.10"}' > "$fx_plugin/.claude-plugin/plugin.json"
  RS_PROJ="$proj" RS_PLUGIN_ROOT="$fx_plugin" RS_HOOKS_DIR="$hooks" RS_FORCE="" run_selftest
  mtime3="$(stat -c %Y "$cache")"; fp3="$(cache_field "$cache" fingerprint)"
  if [ "$mtime3" != "$mtime1" ] && [ "$fp3" != "$fp1" ]; then
    pass "T16 red: plugin.json version bump -> cache invalidated (file rewritten, fingerprint changed)"
  else
    fail "T16 red" "mtime stayed $mtime3(==$mtime1?) fingerprint $fp1->$fp3"
  fi
  rm -rf "$fx_plugin" "$hooks" "$proj"
}

# =============================================================================
# T17 — cache invalidated by per-project config content, independent of plugin version (REQ-ST-9)
# =============================================================================
echo "[T17] cache: prod-guard.conf / verify-cmd.sh byte changes invalidate the cache on their own"
{
  hooks="$(mktemp -d)"; build_real_hooks_fixture "$hooks"
  proj="$(mktemp -d)"; mkdir -p "$proj/.claude/sdx"
  printf 'x\n' > "$proj/.claude/sdx/prod-guard.conf"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$proj/.claude/sdx/verify-cmd.sh"
  cache="$proj/.claude/sdx/.cache/selftest.json"
  # RS_PLUGIN_ROOT left empty on purpose: plugin version must stay OUT of this test's causal
  # chain entirely (independence from T16's source, not just "didn't happen to change").

  RS_PROJ="$proj" RS_HOOKS_DIR="$hooks" RS_FORCE="" run_selftest
  fp1="$(cache_field "$cache" fingerprint)"
  touch -d "1970-01-02" "$cache"; mtime1="$(stat -c %Y "$cache")"

  # Change prod-guard.conf bytes only.
  printf 'y\n' >> "$proj/.claude/sdx/prod-guard.conf"
  RS_PROJ="$proj" RS_HOOKS_DIR="$hooks" RS_FORCE="" run_selftest
  mtime2="$(stat -c %Y "$cache")"; fp2="$(cache_field "$cache" fingerprint)"
  if [ "$mtime2" != "$mtime1" ] && [ "$fp2" != "$fp1" ]; then
    pass "T17a: prod-guard.conf byte change (plugin version untouched) invalidates cache"
  else
    fail "T17a" "mtime $mtime1->$mtime2 fingerprint $fp1->$fp2"
  fi

  # New baseline, then change verify-cmd.sh bytes only (prod-guard.conf untouched this time).
  touch -d "1970-01-02" "$cache"; mtime2b="$(stat -c %Y "$cache")"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$proj/.claude/sdx/verify-cmd.sh"
  RS_PROJ="$proj" RS_HOOKS_DIR="$hooks" RS_FORCE="" run_selftest
  mtime3="$(stat -c %Y "$cache")"; fp3="$(cache_field "$cache" fingerprint)"
  if [ "$mtime3" != "$mtime2b" ] && [ "$fp3" != "$fp2" ]; then
    pass "T17b: verify-cmd.sh byte change ALONE also invalidates cache (independent of prod-guard.conf/version)"
  else
    fail "T17b" "mtime $mtime2b->$mtime3 fingerprint $fp2->$fp3"
  fi
  rm -rf "$hooks" "$proj"
}

# =============================================================================
# T18 — absence of jq does not crash selftest.sh and does not produce a false "all good" (REQ-ST-10)
# =============================================================================
echo "[T18] jq absent from PATH: (a) no crash, (b) fingerprint non-empty, (c) prod_guard reflects real fail-closed"
{
  NOJQ_BIN="$(mktemp -d)"
  for t in bash cat grep sed md5sum cut head tail mkdir mktemp mv rm git timeout chmod date dirname pwd basename printf; do
    src="$(command -v "$t" 2>/dev/null)" && ln -s "$src" "$NOJQ_BIN/$t" 2>/dev/null || true
  done
  proj="$(mktemp -d)"; hooks="$(mktemp -d)"; build_real_hooks_fixture "$hooks"
  RS_PROJ="$proj" RS_HOOKS_DIR="$hooks" RS_PATH="$NOJQ_BIN" RS_FORCE=1 run_selftest
  cache="$proj/.claude/sdx/.cache/selftest.json"

  if [ "$RS_EC" -eq 0 ]; then
    pass "T18a: selftest.sh exits 0 with jq absent (no unhandled exception)"
  else
    fail "T18a" "exit=$RS_EC stderr=$RS_STDERR"
  fi

  fp="$(cache_field "$cache" fingerprint)"
  if printf '%s' "$fp" | grep -Eq '^[0-9a-f]{32}$'; then
    pass "T18b: compute_fingerprint produced a non-empty, well-formed md5 ($fp) without jq"
  else
    fail "T18b" "fingerprint='$fp'"
  fi

  # (c): with protection configured (probe_prod_guard's own synthetic conf) and jq missing,
  # prod-guard.sh's REAL behaviour is fail-closed for EVERY command, including the probe's
  # "unmatched" call — so the probe must honestly report fail (a real divergence from the
  # expected deny/no-op split), never a false-positive "pass"/"all good".
  pg="$(cache_field "$cache" prod_guard)"
  if [ "$pg" = fail ]; then
    pass "T18c: prod_guard=fail — correctly reflects prod-guard.sh's real fail-closed-for-all behaviour without jq, not a false 'pass'"
  else
    fail "T18c" "prod_guard=$pg (expected fail — see DESIGN.md 'побочный эффект стратегии prod-guard')"
  fi
  rm -rf "$NOJQ_BIN" "$proj" "$hooks"
}

# =============================================================================
# T19 — absence of .claude/sdx/sdx-version does not break selftest.sh (REQ-ST-11), symmetry
# =============================================================================
echo "[T19] sdx-version absence doesn't crash/degrade specially; symmetric with other ABSENT sources"
{
  # (1) sdx-version PRESENT, prod-guard.conf ABSENT.
  hooks="$(mktemp -d)"; build_real_hooks_fixture "$hooks"
  proj1="$(mktemp -d)"; mkdir -p "$proj1/.claude/sdx"
  printf '2.1.0\n' > "$proj1/.claude/sdx/sdx-version"
  RS_PROJ="$proj1" RS_HOOKS_DIR="$hooks" RS_FORCE=1 run_selftest
  status1="$(cache_field "$proj1/.claude/sdx/.cache/selftest.json" selftest_status)"
  fp1="$(cache_field "$proj1/.claude/sdx/.cache/selftest.json" fingerprint)"
  ok1=0; [ "$status1" != broken ] && [ -n "$fp1" ] && ok1=1

  # (2) sdx-version ABSENT, prod-guard.conf PRESENT (harmless comment-only content).
  proj2="$(mktemp -d)"; mkdir -p "$proj2/.claude/sdx"
  printf '# no active patterns\n' > "$proj2/.claude/sdx/prod-guard.conf"
  RS_PROJ="$proj2" RS_HOOKS_DIR="$hooks" RS_FORCE=1 run_selftest
  status2="$(cache_field "$proj2/.claude/sdx/.cache/selftest.json" selftest_status)"
  fp2="$(cache_field "$proj2/.claude/sdx/.cache/selftest.json" fingerprint)"
  ok2=0; [ "$status2" != broken ] && [ -n "$fp2" ] && ok2=1

  if [ "$ok1" -eq 1 ] && [ "$ok2" -eq 1 ]; then
    pass "T19: absence of sdx-version (case 2) behaves the same as absence of prod-guard.conf (case 1) — no special-case crash, fingerprint computed, status=$status1/$status2 (not broken)"
  else
    fail "T19" "case1: status=$status1 fp=$fp1 | case2: status=$status2 fp=$fp2"
  fi
  rm -rf "$hooks" "$proj1" "$proj2"
}

# =============================================================================
# T20 — `degraded` is distinguishable from `broken` (REQ-FAIL-1 vs REQ-FAIL-2)
# =============================================================================
# NOTE — deviation from DESIGN.md's literal Тестовая стратегия wording (reported to the
# orchestrator): the DESIGN.md table's "red-2" trigger for `broken` is "SDX_SELFTEST_HOOKS_DIR
# -> несуществующий каталог". Empirically, that trigger does NOT produce `skip`: every probe
# invokes `bash "$hooks_dir/<script>.sh"`, and when the directory doesn't exist this call simply
# exits non-zero (bash: No such file or directory) — mapped by each probe to `fail`, not `skip`.
# `skip` is reachable ONLY through probe_prod_guard's/probe_stop_gate's OWN fixture-setup
# failing (`mktemp -d`, or `git init`/`checkout`) — `probe_preflight` has no skip branch at all.
# Verified directly against the real script before writing this test:
#   SDX_SELFTEST_HOOKS_DIR=/nonexistent ...            -> selftest_status=degraded (all three: fail)
#   TMPDIR=/nonexistent (mktemp -d fails everywhere)    -> selftest_status=broken   (prod_guard/stop_gate: skip)
# This test therefore uses the TMPDIR-based trigger, which genuinely exercises the `skip` path
# per the pseudocode as written, and documents the discrepancy rather than asserting a `broken`
# outcome the code cannot actually produce via the literal DESIGN.md recipe.
echo "[T20] degraded (decoy wrong answer) vs broken (mktemp -d fails -> skip) — distinct messages, both exit 0"
{
  proj_d="$(mktemp -d)"; hooks_d="$(mktemp -d)"; build_real_hooks_fixture "$hooks_d"
  printf '#!/usr/bin/env bash\ncat >/dev/null\nexit 0\n' > "$hooks_d/prod-guard.sh"   # wrong answer -> fail
  RS_PROJ="$proj_d" RS_HOOKS_DIR="$hooks_d" RS_FORCE=1 run_selftest
  ec_d=$RS_EC
  status_d="$(cache_field "$proj_d/.claude/sdx/.cache/selftest.json" selftest_status)"
  if [ "$status_d" = degraded ] && [ "$ec_d" -eq 0 ] && printf '%s' "$RS_STDERR" | grep -q 'расхождение'; then
    pass "T20 degraded: decoy wrong answer -> selftest_status=degraded, exit 0, stderr mentions 'расхождение'"
  else
    fail "T20 degraded" "status=$status_d ec=$ec_d stderr=$RS_STDERR"
  fi
  RS_STDERR_DEGRADED="$RS_STDERR"
  rm -rf "$proj_d" "$hooks_d"

  proj_b="$(mktemp -d)"
  bad_tmp="$(mktemp -u)/definitely-does-not-exist"   # a path guaranteed not to exist, unwritable
  RS_EC=0
  RS_STDERR="$(
    CLAUDE_PROJECT_DIR="$proj_b" \
    SDX_SELFTEST_HOOKS_DIR="$SCRIPT_DIR" \
    SDX_SELFTEST_FORCE=1 \
    TMPDIR="$bad_tmp" \
    bash "$SELFTEST" 2>&1 >/dev/null
  )"
  ec_b=$?
  status_b="$(cache_field "$proj_b/.claude/sdx/.cache/selftest.json" selftest_status)"
  if [ "$status_b" = broken ] && [ "$ec_b" -eq 0 ] && printf '%s' "$RS_STDERR" | grep -q 'не смог выполнить'; then
    pass "T20 broken: mktemp -d failure (bad TMPDIR) -> selftest_status=broken, exit 0, stderr mentions 'не смог выполнить'"
  else
    fail "T20 broken" "status=$status_b ec=$ec_b stderr=$RS_STDERR"
  fi

  if [ "$RS_STDERR_DEGRADED" != "$RS_STDERR" ]; then
    pass "T20: degraded and broken stderr messages use distinct wording (not the same generic text)"
  else
    fail "T20: messages identical" "both='$RS_STDERR'"
  fi
  rm -rf "$proj_b"
}

# =============================================================================
# T21 — BUG-008 boundary is pinned as a regression test, not just prose (REQ-LIMIT-1)
# =============================================================================
echo "[T21] BUG-008 pin: a probed hook at mode 0600 still passes (bash <path> ignores the exec bit)"
{
  # This test PINS a documented, deliberate limitation (DESIGN.md "Честные ограничения" #1):
  # selftest.sh invokes probed hooks via `bash <path>`, which is mode/exec-bit independent, so
  # it structurally CANNOT detect a BUG-008-class regression (lost exec bit). If a future
  # refactor ever changes the invocation to direct execution (`"$hooks_dir/x.sh"` without
  # `bash`), THIS test will start failing/skipping on a 0600 fixture — that is the intended
  # tripwire: it forces a conscious DESIGN.md review instead of a silent behaviour drift.
  proj="$(mktemp -d)"; hooks="$(mktemp -d)"; build_real_hooks_fixture "$hooks"
  chmod 0600 "$hooks/stop-gate.sh"
  RS_PROJ="$proj" RS_HOOKS_DIR="$hooks" RS_FORCE=1 run_selftest
  val="$(cache_field "$proj/.claude/sdx/.cache/selftest.json" stop_gate)"
  if [ "$val" = pass ]; then
    pass "T21: stop-gate.sh at 0600 still probes as pass — bash <path> is exec-bit independent (BUG-008 pin)"
  else
    fail "T21" "stop_gate=$val (bit stripped should NOT have changed the probe outcome)"
  fi
  rm -rf "$proj" "$hooks"
}

# =============================================================================
# T24 — commands/status.md structural checks for the new step 5 (REQ-HEALTH-1/2/3,
# grep-based, lives here rather than a dedicated test-*.sh because status.md is a prose
# instruction, not an executable script — DESIGN.md "Тестовая стратегия" / PLAN.md T24)
# =============================================================================
echo "[T24] commands/status.md: step 5 structural checks present, positioned after step 4"
{
  STATUS_MD="$ROOT/commands/status.md"

  # status_checks <file> — counts how many of the four REQ-HEALTH-1 structural checks (jq
  # present, prod-guard.conf present+non-empty, verify-cmd.sh present+executable, branch <->
  # session match) are present in <file>. Returns 0-4.
  status_checks() {
    local f="$1" n=0
    grep -qF 'command -v jq >/dev/null 2>&1 && echo present || echo MISSING' "$f" && n=$((n + 1))
    grep -qF '[ -s .claude/sdx/prod-guard.conf ] && echo "present, non-empty" || echo "missing or empty"' "$f" && n=$((n + 1))
    grep -qF '[ -x .claude/sdx/verify-cmd.sh ] && echo "present, executable"' "$f" && n=$((n + 1))
    grep -qF 'соответствие ветки: сравни `git branch --show-current` с `sdx/<session_id>` из `session_state.json`' "$f" && n=$((n + 1))
    echo "$n"
  }

  n_checks="$(status_checks "$STATUS_MD")"
  has_no_rerun=0
  grep -qF 'НЕ запускай `selftest.sh` повторно' "$STATUS_MD" && has_no_rerun=1
  has_age=0
  grep -qF 'возраст `ts`' "$STATUS_MD" && has_age=1

  # Positional check (REQ-LIMIT-3): step 5 marker must appear strictly AFTER the step 4 marker —
  # step 4's own text is asserted byte-identical separately (git diff review, PLAN.md T23 DoD),
  # this only pins ORDER, i.e. step 5 was appended after, not inserted before/inside step 4.
  line4="$(grep -nF '4. **(факультативно) Активные сессии' "$STATUS_MD" | head -1 | cut -d: -f1)"
  line5="$(grep -nF '5. **Здоровье enforcement' "$STATUS_MD" | head -1 | cut -d: -f1)"

  if [ "$n_checks" -eq 4 ] && [ "$has_no_rerun" -eq 1 ] && [ "$has_age" -eq 1 ] \
     && [ -n "$line4" ] && [ -n "$line5" ] && [ "$line5" -gt "$line4" ]; then
    pass "T24 green: 4/4 structural checks + no-rerun phrase + ts-age wording present, step 5 (line $line5) after step 4 (line $line4)"
  else
    fail "T24 green" "n_checks=$n_checks no_rerun=$has_no_rerun age=$has_age line4=$line4 line5=$line5"
  fi

  # Red side (demonstrates the grep gate actually discriminates, DESIGN.md "Красный: временно
  # убрать любой из четырёх пунктов ... → тест обязан упасть"): a copy of the real file with the
  # branch-check line stripped out must score 3/4, not 4/4 — the same predicate the green
  # assertion above relies on.
  mutated="$(mktemp)"
  grep -v 'соответствие ветки: сравни' "$STATUS_MD" > "$mutated"
  n_red="$(status_checks "$mutated")"
  if [ "$n_red" -eq 3 ]; then
    pass "T24 red: stripping the branch-check line drops the count to 3/4 — gate discriminates (would fail the green assertion above)"
  else
    fail "T24 red" "expected 3 structural checks after removing the branch-check line, got $n_red"
  fi
  rm -f "$mutated"
}

# =============================================================================
# T25 — regression grep gate for REQ-LIMIT-2 across all three files touched by this delivery
# (closing task of the plan — runs last, after all texts are in final form)
# =============================================================================
echo "[T25] REQ-LIMIT-2 regression grep gate: no false promises across selftest.sh / test-selftest.sh / status.md / protocol.md"
{
  # Forbidden phrases assembled from array elements that never sit adjacent to each other in
  # THIS file's own source text (each half lives in a separate array literal) — so grepping this
  # very file (T25's target list includes test-selftest.sh itself, per DESIGN.md) cannot produce
  # a spurious self-match purely because the pattern definition mentions the banned words.
  part_a=("блокирует" "отключает" "понижает" "снижает" "ограничивает" "блокирует" "блокирует" "меняет")
  part_b=("автоном" "автоном" "уровень доступа" "уровень доступа" "автоном" "SessionStart" "запуск CLI" "доступные классы риска")

  forbidden=""
  for i in "${!part_a[@]}"; do
    phrase="${part_a[$i]} ${part_b[$i]}"
    forbidden="${forbidden:+$forbidden|}$phrase"
  done

  # sdx/protocol.md joined the target list at the Documentation stage: it is the most-read
  # surface describing this mechanism, so a false promise there costs more than in any of the
  # other three. The gate is about the claim, not about the file type.
  targets=("$ROOT/sdx/hooks/selftest.sh" "$ROOT/sdx/hooks/test-selftest.sh" "$ROOT/commands/status.md" "$ROOT/sdx/protocol.md")

  hit=0
  for t in "${targets[@]}"; do
    if grep -riE "$forbidden" "$t" >/dev/null 2>&1; then
      hit=1
      fail "T25 green" "forbidden phrase found in $t"
    fi
  done
  if [ "$hit" -eq 0 ]; then
    pass "T25 green: zero matches for forbidden gate/blocking claims across all three files"
  fi

  # Red: temporarily inject one forbidden phrase into a scratch copy of each target and confirm
  # the same grep discriminates it (DESIGN.md "Красный: временно вставить одну из запрещённых
  # формулировок ... → тест обязан упасть").
  red_ok=1
  for t in "${targets[@]}"; do
    scratch="$(mktemp)"
    cp "$t" "$scratch"
    printf '\n%s\n' "${part_a[0]} ${part_b[0]}" >> "$scratch"
    if ! grep -riE "$forbidden" "$scratch" >/dev/null 2>&1; then
      red_ok=0
      fail "T25 red" "injecting a forbidden phrase into a copy of $t did NOT trip the gate"
    fi
    rm -f "$scratch"
  done
  if [ "$red_ok" -eq 1 ]; then
    pass "T25 red: injecting a forbidden phrase into a scratch copy of each of the 3 files trips the gate"
  fi
}

# ---- T27 (добавлено на Verification по находке qa) — best-effort write_cache().
#      Свойство: selftest.sh на SessionStart не имеет права уронить старт CLI из-за того, что
#      каталог .claude/sdx/ недоступен на запись (read-only чекаут, чужие права, noexec-раздел).
#      DESIGN.md называет эту ветку обработанной, но ни один сценарий её не исполнял.
#
#      Честная граница дискриминации, установленная опытом при добавлении этого сценария:
#        * краснеет  — если отказ записи кэша сделать фатальным (`mkdir ... || exit 1`);
#        * НЕ краснеет — если просто снять гард `|| return 0`. Причина: скрипт работает под
#          `set -uo pipefail` БЕЗ `-e`, поэтому неудачный `mkdir`/`mktemp` сам по себе
#          исполнение не прерывает, и свойство «exit 0» держится и без гарда.
#      То есть гард сегодня — defence in depth, а не несущая конструкция; несущим он станет,
#      если кто-нибудь добавит `set -e` или явный выход. Сценарий охраняет именно СВОЙСТВО
#      (старт CLI не ломается), а не конкретную строку реализации — и это его предел. ----
echo "[T27] Unwritable .claude/sdx/ -> selftest still exits 0 and writes no cache"
tp="$(mktemp -d)"
mkdir -p "$tp/.claude/sdx"
chmod 0500 "$tp/.claude/sdx"
ec=0
CLAUDE_PROJECT_DIR="$tp" bash "$SELFTEST" >/dev/null 2>&1 || ec=$?
chmod 0700 "$tp/.claude/sdx"    # вернуть права, иначе rm -rf не сможет
if [ "$ec" -eq 0 ] && [ ! -f "$tp/.claude/sdx/.cache/selftest.json" ]; then
  pass "exit 0 with no cache written (best-effort branch taken, CLI start not broken)"
else
  fail "Expected exit 0 AND no cache file" "got exit $ec, cache present: $([ -f "$tp/.claude/sdx/.cache/selftest.json" ] && echo yes || echo no)"
fi
rm -rf "$tp"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "ALL PASSED"
  exit 0
else
  exit 1
fi
