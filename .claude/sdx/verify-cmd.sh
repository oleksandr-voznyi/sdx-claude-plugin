#!/usr/bin/env bash
# Per-project verify command for stop-gate (REQ-GATE-2) — SDX meta-project.
#
# Runs the full hook unit-test suite (sdx/hooks/test-*.sh) so that stop-gate
# enforces a deterministic test floor on SDX sessions of the framework itself
# (dogfood, DEBT-004). No --fast mode: the full suite (25 suites, 2026-10-31, FEAT-017) is
# measured below against the stop-gate timeout (180 s).
#
# Runner (FEAT-017, verify-1, DESIGN K-10): SDX_VERIFY_JOBS=<n> suites run concurrently; the default is 2 when the
# machine has >= 4 CPUs, else 1; SDX_VERIFY_JOBS=1 is the original sequential runner. The output of every suite is
# buffered and printed IN THE SUITE ORDER, the "==> name: PASS|FAIL" lines, the Summary line and the exit code are the same
# in both modes. Suites are independent (each works in its own mktemp directory and reads the checkout only).
# Measurements (2026-10-31, 8 cores, load average 5-8 from other processes of the host, 25 suites): sequential
# (SDX_VERIFY_JOBS=1) 192 s, over the 180 s stop-gate timeout; default (SDX_VERIFY_JOBS=2) 126.6 s. On a quiet machine the
# sequential run takes ~118 s (117.7 s at load average ~0.7).
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

# Number of concurrent suites: SDX_VERIFY_JOBS, else 2 on >= 4 CPUs, else 1.
ncpu="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)"
case "$ncpu" in ''|*[!0-9]*) ncpu=1 ;; esac
if [ "$ncpu" -ge 4 ]; then jobs_default=2; else jobs_default=1; fi
jobs="${SDX_VERIFY_JOBS:-$jobs_default}"
case "$jobs" in ''|*[!0-9]*|0) echo "verify-cmd: SDX_VERIFY_JOBS must be a positive integer (got '$jobs'); using $jobs_default" >&2; jobs="$jobs_default" ;; esac
[ "$jobs" -le "${#suites[@]}" ] || jobs=${#suites[@]}

failed=0
total=${#suites[@]}
passed_count=0

if [ "$jobs" -le 1 ]; then
  # sequential: the output streams as the suites run
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
else
  # concurrent: <jobs> suites at a time (xargs -P), output buffered per suite, printed in the suite order as each one finishes
  VERIFY_TMPD="$(mktemp -d)" || { echo "verify-cmd: cannot create a temp directory" >&2; exit 1; }
  export VERIFY_TMPD
  xpid=""
  cleanup() {
    if [ -n "$xpid" ]; then pkill -P "$xpid" 2>/dev/null; kill "$xpid" 2>/dev/null; fi
    rm -rf "$VERIFY_TMPD"
  }
  trap cleanup EXIT
  trap 'exit 130' INT TERM
  printf '%s\0' "${suites[@]}" | xargs -0 -n1 -P "$jobs" bash -c '
    n="$(basename "$1")"
    bash "$1" > "$VERIFY_TMPD/$n.out" 2>&1
    echo "$?" > "$VERIFY_TMPD/$n.rc.t"
    mv "$VERIFY_TMPD/$n.rc.t" "$VERIFY_TMPD/$n.rc"
  ' _ &
  xpid=$!
  for suite in "${suites[@]}"; do
    name="$(basename "$suite")"
    while [ ! -f "$VERIFY_TMPD/$name.rc" ]; do
      kill -0 "$xpid" 2>/dev/null || { [ -f "$VERIFY_TMPD/$name.rc" ] || break; }
      sleep 0.3
    done
    echo "==> Running $name"
    cat "$VERIFY_TMPD/$name.out" 2>/dev/null
    if [ "$(cat "$VERIFY_TMPD/$name.rc" 2>/dev/null)" = "0" ]; then
      echo "==> $name: PASS"
      passed_count=$((passed_count + 1))
    else
      echo "==> $name: FAIL"
      failed=1
    fi
    echo
  done
  wait "$xpid" 2>/dev/null
  xpid=""
fi

echo "Summary: $passed_count/$total suites passed"

if [ "$failed" -ne 0 ]; then
  exit 1
fi

exit 0
