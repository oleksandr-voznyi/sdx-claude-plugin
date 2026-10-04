#!/usr/bin/env bash
# Static guard for the vendored directory sdx/mo/ (PROC-028, amendment to ADR-013).
#
# sdx/mo/ is the one part of the plugin whose source of truth is NOT this repository: it is a
# vendored copy of the meta-orchestrator leaf-session tools from sim-kit. Two fixation files
# pin what was vendored — SIMKIT_VERSION (one line, the sim-kit release) and SIMKIT_SHA256
# (`sha256sum` output over every vendored file). Local edits to vendored code are forbidden; a
# defect goes upstream as a note, the plugin waits for a release. This suite is what makes the
# rule more than text: any local edit changes a hash and turns the suite red until SIMKIT_SHA256
# is rewritten on purpose. (Rewriting it silently is a diff-review concern, not a test one —
# a named limit, see protocol "Вендорённые компоненты".)
#
# What it checks, for a directory D:
#   (a) SIMKIT_VERSION exists and is exactly one non-empty line of the form X.Y[.Z];
#   (b) SIMKIT_SHA256 exists; every line is "<64 hex>  <name>";
#   (c) every listed file exists in D and its sha256 matches;
#   (d) every file in D other than SIMKIT_VERSION, SIMKIT_SHA256 and README.md is listed.
# Composition and hashes only — never semantics (envelope version compatibility is a judgement
# made at update time, not a test).
#
# Deliberately static, like test-init-patterns.sh and test-hook-wiring.sh: it hashes files, runs
# no hooks. The checker is exercised on a scratch fixture with one green and four red sides
# before it is pointed at the real sdx/mo/ — a guard never shown to go red proves nothing.
# While FEAT-015 is not delivered the real directory does not exist; scenario [6] says so out
# loud and counts it neither as a pass nor as a fail.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MO_DIR="$ROOT/sdx/mo"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

echo "=== test-mo-inventory.sh ==="
echo ""

# Portable sha256 (BUG-010 lesson: do not assume GNU coreutils). Output: bare hex digest.
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else echo "no-sha256-tool"; fi
}

# check_inventory <dir> — prints one finding per line; empty output = inventory consistent.
# Single function for fixture and real directory: one comparison, many inputs.
check_inventory() {
  local d="$1" ver line hash name listed f rel
  if [ ! -f "$d/SIMKIT_VERSION" ]; then
    echo "SIMKIT_VERSION missing"
  else
    ver="$(grep -c . "$d/SIMKIT_VERSION" 2>/dev/null)"
    if [ "$ver" != "1" ]; then
      echo "SIMKIT_VERSION must be exactly one non-empty line (got $ver)"
    elif ! grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)?$' "$d/SIMKIT_VERSION"; then
      echo "SIMKIT_VERSION malformed: '$(head -1 "$d/SIMKIT_VERSION")' (expected X.Y[.Z])"
    fi
  fi
  if [ ! -f "$d/SIMKIT_SHA256" ]; then
    echo "SIMKIT_SHA256 missing"
    return 0
  fi
  listed=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if ! printf '%s\n' "$line" | grep -qE '^[0-9a-f]{64}  [^/ ][^ ]*$'; then
      echo "SIMKIT_SHA256 malformed line: '$line'"; continue
    fi
    hash="${line%%  *}"; name="${line#*  }"
    listed="$listed $name"
    if [ ! -f "$d/$name" ]; then
      echo "listed but missing: $name"
    elif [ "$(sha256_of "$d/$name")" != "$hash" ]; then
      echo "hash mismatch: $name"
    fi
  done < "$d/SIMKIT_SHA256"
  # (d) unlisted files — flat directory by contract; a subdirectory is itself a finding.
  for f in "$d"/* "$d"/.[!.]*; do
    [ -e "$f" ] || continue
    rel="${f#"$d"/}"
    case "$rel" in SIMKIT_VERSION|SIMKIT_SHA256|README.md|__pycache__) continue ;; esac
    if [ -d "$f" ]; then echo "unexpected subdirectory: $rel"; continue; fi
    case " $listed " in *" $rel "*) ;; *) echo "unlisted file: $rel" ;; esac
  done
}

if [ "$(sha256_of "$0")" = "no-sha256-tool" ]; then
  fail "sha256 tool" "neither sha256sum nor shasum found — the guard cannot run on this host"
  echo ""; echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"; exit 1
fi

# --- Fixture: a consistent vendored directory ------------------------------------------------
fx="$(mktemp -d)"
trap 'rm -rf "$fx"' EXIT
printf 'print("endpoint")\n' > "$fx/mesh_endpoint.py"
printf 'print("hook")\n'     > "$fx/devagent_hook.py"
printf '# rules\n'           > "$fx/MO-INTEROP.md"
printf '# local notes, not vendored\n' > "$fx/README.md"
printf '0.7.3\n' > "$fx/SIMKIT_VERSION"
{
  for n in mesh_endpoint.py devagent_hook.py MO-INTEROP.md; do
    printf '%s  %s\n' "$(sha256_of "$fx/$n")" "$n"
  done
} > "$fx/SIMKIT_SHA256"

echo "[1] Consistent fixture: no findings (green side)"
out="$(check_inventory "$fx")"
if [ -z "$out" ]; then pass "consistent fixture reports nothing"
else fail "consistent fixture reported findings" "$(printf '%s' "$out" | tr '\n' ';')"; fi

echo "[2] Red side: a file added locally but not listed"
printf 'x\n' > "$fx/extra.py"
out="$(check_inventory "$fx")"
case "$out" in *"unlisted file: extra.py"*) pass "unlisted file is reported" ;;
  *) fail "unlisted file not reported" "got: '$out'" ;; esac
rm -f "$fx/extra.py"

echo "[3] Red side: a vendored file edited locally (the rule this suite exists for)"
printf '# local patch\n' >> "$fx/devagent_hook.py"
out="$(check_inventory "$fx")"
case "$out" in *"hash mismatch: devagent_hook.py"*) pass "local edit is reported as hash mismatch" ;;
  *) fail "local edit not reported" "got: '$out'" ;; esac
printf 'print("hook")\n' > "$fx/devagent_hook.py"
[ -z "$(check_inventory "$fx")" ] || fail "fixture restore" "fixture not back to green after [3]"

echo "[4] Red side: a listed file missing from the directory"
mv "$fx/MO-INTEROP.md" "$fx/MO-INTEROP.md.bak"
out="$(check_inventory "$fx")"
case "$out" in *"listed but missing: MO-INTEROP.md"*) pass "missing listed file is reported" ;;
  *) fail "missing listed file not reported" "got: '$out'" ;; esac
mv "$fx/MO-INTEROP.md.bak" "$fx/MO-INTEROP.md"

echo "[5] Red side: SIMKIT_VERSION malformed (two lines; then a 'v' prefix)"
printf '0.7.3\n0.7.2\n' > "$fx/SIMKIT_VERSION"
out="$(check_inventory "$fx")"
case "$out" in *"exactly one non-empty line"*) pass "two-line SIMKIT_VERSION is reported" ;;
  *) fail "two-line SIMKIT_VERSION not reported" "got: '$out'" ;; esac
printf 'v0.7.3\n' > "$fx/SIMKIT_VERSION"
out="$(check_inventory "$fx")"
case "$out" in *"malformed"*) pass "'v'-prefixed SIMKIT_VERSION is reported" ;;
  *) fail "'v'-prefixed SIMKIT_VERSION not reported" "got: '$out'" ;; esac
printf '0.7.3\n' > "$fx/SIMKIT_VERSION"

# --- The real directory ---------------------------------------------------------------------
echo "[6] Real sdx/mo/ (exists only once FEAT-015 is delivered)"
if [ -d "$MO_DIR" ]; then
  out="$(check_inventory "$MO_DIR")"
  if [ -z "$out" ]; then pass "sdx/mo/ matches SIMKIT_SHA256 and SIMKIT_VERSION ($(cat "$MO_DIR/SIMKIT_VERSION"))"
  else fail "sdx/mo/ inventory inconsistent" "$(printf '%s' "$out" | tr '\n' ';')"; fi
else
  # Not a pass: nothing was verified. Not a fail: absence is the documented pre-FEAT-015 state.
  echo "  INFO: sdx/mo/ absent — nothing vendored yet (FEAT-015 not delivered); real-directory check skipped"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "ALL PASSED"
  exit 0
else
  exit 1
fi
