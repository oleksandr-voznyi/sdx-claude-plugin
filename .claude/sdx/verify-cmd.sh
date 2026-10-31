#!/usr/bin/env bash
# Per-project verify command for stop-gate (REQ-GATE-2) — SDX meta-project.
#
# Runs the full hook unit-test suite (sdx/hooks/test-*.sh) so that stop-gate
# enforces a deterministic test floor on SDX sessions of the framework itself
# (dogfood, DEBT-004). No --fast mode: the full suite (25 suites, 2026-10-31, FEAT-017) runs in
# ~80-125 seconds depending on machine load (measured 117.7 s at load average ~0.7 on 8 cores,
# 2026-10-31; 124 s at load average ~10 for 19 suites, 2026-10-29; test-mo-hook.sh alone ~20s),
# under the stop-gate timeout (180s). Suites run sequentially; no parallel runner was needed.
set -uo pipefail

# Resolve the repo root relative to this script's location:
#   this file lives in .claude/sdx/, repo root is two levels up.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
hooks_dir="$root/sdx/hooks"

# Glob (not a hardcoded list) so new test-*.sh suites are picked up
# automatically without editing this script.
suites=("$hooks_dir"/test-*.sh)

# Guard against a silent no-op: if the glob matched nothing (e.g. the hooks
# directory moved or was emptied), fail loudly instead of exiting 0.
if [ ! -e "${suites[0]}" ]; then
  echo "verify-cmd: no test-*.sh suites found in $hooks_dir" >&2
  exit 1
fi

failed=0
total=${#suites[@]}
passed_count=0

for suite in "${suites[@]}"; do
  name="$(basename "$suite")"
  echo "==> Running $name"
  if bash "$suite"; then
    echo "==> $name: PASS"
    passed_count=$((passed_count + 1))
  else
    echo "==> $name: FAIL"
    failed=1
  fi
  echo
done

echo "Summary: $passed_count/$total suites passed"

if [ "$failed" -ne 0 ]; then
  exit 1
fi

exit 0
