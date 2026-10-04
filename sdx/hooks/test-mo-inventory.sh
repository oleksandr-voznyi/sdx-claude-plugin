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
#   (b) SIMKIT_SHA256 exists; every line is "<64 hex>  <name>" with a flat name (no '/', no spaces);
#   (c) every listed file exists in D and its sha256 matches;
#   (d) every entry in D other than SIMKIT_VERSION, SIMKIT_SHA256 and README.md is a listed file —
#       hidden files included; a subdirectory is a finding (the directory is flat by contract, and
#       python bytecode must not be written here: the FEAT-015 wrapper runs python with
#       PYTHONDONTWRITEBYTECODE=1, so a __pycache__/ is a finding, not an exception);
#   (e) every listed name is mentioned by each prose surface that recounts the composition of
#       sdx/mo/ — README.md, README.en.md, CLAUDE.md, sdx/protocol.md, docs/DECISIONS.md (PROC-027 class:
#       a bare-name inventory drifts silently; this is composition only, never meaning).
# Composition, hashes and mentions — never semantics (envelope version compatibility is a
# judgement made at update time, not a test).
#
# Deliberately static, like test-init-patterns.sh and test-hook-wiring.sh: it hashes files, runs
# no hooks. Both checkers are exercised on a scratch fixture with green and red sides before
# they are pointed at the real sdx/mo/ — a guard never shown to go red proves nothing. The real
# directory is delivered by FEAT-015, so its absence is a regression: scenario [6] FAILs on it
# (red side: a copy of this suite with MO_DIR pointed at a missing directory must exit 1).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# MO_DIR_UNDER_TEST overrides the directory under test (red side of scenario [6]).
MO_DIR="${MO_DIR_UNDER_TEST:-$ROOT/sdx/mo}"
SURFACES="README.md README.en.md CLAUDE.md sdx/protocol.md docs/DECISIONS.md"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

echo "=== test-mo-inventory.sh ==="
echo ""

# Portable sha256 (BUG-010 lesson: do not assume GNU coreutils). Output: bare hex digest.
# MO_INV_SHA_TOOL forces one implementation so scenario [12] can exercise the fallback path on a
# host that has both tools; unset = auto-detect, which is what the real check uses.
sha256_of() {
  local tool="${MO_INV_SHA_TOOL:-}"
  if [ -z "$tool" ]; then
    if command -v sha256sum >/dev/null 2>&1; then tool=sha256sum
    elif command -v shasum >/dev/null 2>&1; then tool=shasum
    else echo "no-sha256-tool"; return 0; fi
  fi
  case "$tool" in
    sha256sum) sha256sum "$1" | cut -d' ' -f1 ;;
    shasum)    shasum -a 256 "$1" | cut -d' ' -f1 ;;
    *)         echo "no-sha256-tool" ;;
  esac
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
    # Flat name: no '/', no spaces — anything else cannot be a file of THIS directory.
    if ! printf '%s\n' "$line" | grep -qE '^[0-9a-f]{64}  [^/ ]+$'; then
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
  for f in "$d"/* "$d"/.[!.]*; do
    [ -e "$f" ] || continue
    rel="${f#"$d"/}"
    case "$rel" in SIMKIT_VERSION|SIMKIT_SHA256|README.md) continue ;; esac
    if [ -d "$f" ]; then echo "unexpected subdirectory: $rel"; continue; fi
    case " $listed " in *" $rel "*) ;; *) echo "unlisted file: $rel" ;; esac
  done
}

# listed_names <sha256-file> — the names column, one per line.
listed_names() { grep -oE '  [^/ ]+$' "$1" 2>/dev/null | sed 's/^  //'; }

# check_surfaces <sha256-file> <surface>... — prints one finding per (name, surface) the surface
# does not mention. Literal match on the bare file name: a prose inventory that drops a file is
# caught; a prose inventory that describes it wrongly is not (PROC-027 names this limit).
check_surfaces() {
  local sha="$1" s n; shift
  for s in "$@"; do
    [ -f "$s" ] || { echo "surface missing: $s"; continue; }
    while IFS= read -r n; do
      [ -z "$n" ] && continue
      grep -qF -- "$n" "$s" || echo "surface $s does not mention: $n"
    done <<< "$(listed_names "$sha")"
  done
}

if [ "$(sha256_of "$0")" = "no-sha256-tool" ]; then
  fail "sha256 tool" "neither sha256sum nor shasum found — the guard cannot run on this host"
  echo ""; echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"; exit 1
fi

# --- Fixture: a consistent vendored directory ------------------------------------------------
fx="$(mktemp -d "${TMPDIR:-/tmp}/mo-inv.XXXXXX")"
trap 'rm -rf "$fx"' EXIT
VENDORED="mesh_endpoint.py devagent_hook.py MO-INTEROP.md"
printf 'print("endpoint")\n' > "$fx/mesh_endpoint.py"
printf 'print("hook")\n'     > "$fx/devagent_hook.py"
printf '# rules\n'           > "$fx/MO-INTEROP.md"
printf '# local notes, not vendored\n' > "$fx/README.md"
printf '0.7.3\n' > "$fx/SIMKIT_VERSION"
write_sha256() {  # regenerate SIMKIT_SHA256 for the fixture from VENDORED
  local n; { for n in $VENDORED; do printf '%s  %s\n' "$(sha256_of "$fx/$n")" "$n"; done; } > "$fx/SIMKIT_SHA256"
}
write_sha256
expect_green() {  # expect_green <label> — fixture must be back to consistent after a red scenario
  [ -z "$(check_inventory "$fx")" ] || fail "fixture restore" "fixture not back to green after $1"
}

echo "[1] Consistent fixture: no findings (green side)"
out="$(check_inventory "$fx")"
if [ -z "$out" ]; then pass "consistent fixture reports nothing"
else fail "consistent fixture reported findings" "$(printf '%s' "$out" | tr '\n' ';')"; fi

echo "[1b] The fixture's SIMKIT_SHA256 is a real sha256sum file: 'sha256sum -c' accepts it too"
if command -v sha256sum >/dev/null 2>&1; then
  if (cd "$fx" && sha256sum -c --quiet SIMKIT_SHA256 >/dev/null 2>&1); then pass "format is sha256sum-compatible (the one-command manual check the protocol promises)"
  else fail "sha256sum -c rejects the fixture file" "format drifted from sha256sum's"; fi
else echo "  INFO: sha256sum absent on this host — compatibility check skipped"; fi

echo "[2] Red side: a file added locally but not listed (visible and hidden)"
printf 'x\n' > "$fx/extra.py"; printf 'x\n' > "$fx/.hidden.py"
out="$(check_inventory "$fx")"
case "$out" in *"unlisted file: extra.py"*) pass "unlisted file is reported" ;; *) fail "unlisted file not reported" "got: '$out'" ;; esac
case "$out" in *"unlisted file: .hidden.py"*) pass "unlisted hidden file is reported" ;; *) fail "hidden file not reported" "got: '$out'" ;; esac
rm -f "$fx/extra.py" "$fx/.hidden.py"; expect_green "[2]"

echo "[3] Red side: a vendored file edited locally (the rule this suite exists for)"
printf '# local patch\n' >> "$fx/devagent_hook.py"
out="$(check_inventory "$fx")"
case "$out" in *"hash mismatch: devagent_hook.py"*) pass "local edit is reported as hash mismatch" ;; *) fail "local edit not reported" "got: '$out'" ;; esac
printf 'print("hook")\n' > "$fx/devagent_hook.py"; expect_green "[3]"

echo "[4] Red side: a listed file missing from the directory"
mv "$fx/MO-INTEROP.md" "$fx/MO-INTEROP.md.bak"
out="$(check_inventory "$fx")"
case "$out" in *"listed but missing: MO-INTEROP.md"*) pass "missing listed file is reported" ;; *) fail "missing listed file not reported" "got: '$out'" ;; esac
mv "$fx/MO-INTEROP.md.bak" "$fx/MO-INTEROP.md"; expect_green "[4]"

echo "[5] Red side: SIMKIT_VERSION malformed (two lines; a 'v' prefix; absent)"
printf '0.7.3\n0.7.2\n' > "$fx/SIMKIT_VERSION"
out="$(check_inventory "$fx")"
case "$out" in *"SIMKIT_VERSION must be exactly one non-empty line"*) pass "two-line SIMKIT_VERSION is reported" ;; *) fail "two-line SIMKIT_VERSION not reported" "got: '$out'" ;; esac
printf 'v0.7.3\n' > "$fx/SIMKIT_VERSION"
out="$(check_inventory "$fx")"
case "$out" in *"SIMKIT_VERSION malformed: 'v0.7.3'"*) pass "'v'-prefixed SIMKIT_VERSION is reported" ;; *) fail "'v'-prefixed SIMKIT_VERSION not reported" "got: '$out'" ;; esac
rm -f "$fx/SIMKIT_VERSION"
out="$(check_inventory "$fx")"
case "$out" in *"SIMKIT_VERSION missing"*) pass "absent SIMKIT_VERSION is reported" ;; *) fail "absent SIMKIT_VERSION not reported" "got: '$out'" ;; esac
printf '0.7.3\n' > "$fx/SIMKIT_VERSION"; expect_green "[5]"

echo "[7] Red side: SIMKIT_SHA256 malformed lines (short hash; a path with '/'); absent file"
cp "$fx/SIMKIT_SHA256" "$fx/SIMKIT_SHA256.bak"
printf 'deadbeef  foo\n' >> "$fx/SIMKIT_SHA256"
printf '%s  ../escape\n' "$(sha256_of "$fx/MO-INTEROP.md")" >> "$fx/SIMKIT_SHA256"
out="$(check_inventory "$fx")"
case "$out" in *"malformed line: 'deadbeef  foo'"*) pass "short hash line is reported as malformed" ;; *) fail "short hash line not reported" "got: '$out'" ;; esac
case "$out" in *"malformed line: "*"  ../escape'"*) pass "path with '/' is reported as malformed, not resolved" ;; *) fail "path with '/' not reported" "got: '$out'" ;; esac
rm -f "$fx/SIMKIT_SHA256"
out="$(check_inventory "$fx")"
case "$out" in *"SIMKIT_SHA256 missing"*) pass "absent SIMKIT_SHA256 is reported" ;; *) fail "absent SIMKIT_SHA256 not reported" "got: '$out'" ;; esac
mv "$fx/SIMKIT_SHA256.bak" "$fx/SIMKIT_SHA256"; expect_green "[7]"

echo "[8] Red side: a subdirectory (including python's __pycache__) is a finding, not an exception"
mkdir "$fx/__pycache__"
out="$(check_inventory "$fx")"
case "$out" in *"unexpected subdirectory: __pycache__"*) pass "__pycache__/ is reported" ;; *) fail "__pycache__/ not reported" "got: '$out'" ;; esac
rmdir "$fx/__pycache__"; expect_green "[8]"

echo "[9] Prose surfaces (check (e)): a surface that drops one vendored name is reported"
srf="$fx/surface.md"
printf 'vendored: mesh_endpoint.py, devagent_hook.py, MO-INTEROP.md\n' > "$srf"
out="$(check_surfaces "$fx/SIMKIT_SHA256" "$srf")"
if [ -z "$out" ]; then pass "surface naming every file reports nothing (green side)"
else fail "complete surface reported findings" "$(printf '%s' "$out" | tr '\n' ';')"; fi
printf 'vendored: mesh_endpoint.py, MO-INTEROP.md\n' > "$srf"
out="$(check_surfaces "$fx/SIMKIT_SHA256" "$srf")"
case "$out" in *"does not mention: devagent_hook.py"*) pass "dropped name is reported for that surface" ;; *) fail "dropped name not reported" "got: '$out'" ;; esac
out="$(check_surfaces "$fx/SIMKIT_SHA256" "$fx/no-such-surface.md")"
case "$out" in *"surface missing: "*) pass "a missing surface file is itself a finding" ;; *) fail "missing surface not reported" "got: '$out'" ;; esac

echo "[12] Portability: the shasum fallback hashes identically to sha256sum (when both exist)"
if command -v sha256sum >/dev/null 2>&1 && command -v shasum >/dev/null 2>&1; then
  a="$(MO_INV_SHA_TOOL=sha256sum sha256_of "$fx/MO-INTEROP.md")"; b="$(MO_INV_SHA_TOOL=shasum sha256_of "$fx/MO-INTEROP.md")"
  if [ "$a" = "$b" ] && [ "${#a}" = 64 ]; then pass "shasum -a 256 fallback agrees with sha256sum"
  else fail "fallback disagrees" "sha256sum='$a' shasum='$b'"; fi
else echo "  INFO: only one sha256 tool on this host — fallback equivalence not exercised"; fi

# --- The real directory ---------------------------------------------------------------------
echo "[6] Real sdx/mo/ (delivered by FEAT-015; absence is a regression)"
if [ -d "$MO_DIR" ]; then
  out="$(check_inventory "$MO_DIR")"
  if [ -z "$out" ]; then pass "sdx/mo/ matches SIMKIT_SHA256 and SIMKIT_VERSION ($(cat "$MO_DIR/SIMKIT_VERSION"))"
  else fail "sdx/mo/ inventory inconsistent" "$(printf '%s' "$out" | tr '\n' ';')"; fi
  # shellcheck disable=SC2086
  out="$(cd "$ROOT" && check_surfaces "$MO_DIR/SIMKIT_SHA256" $SURFACES)"
  if [ -z "$out" ]; then pass "every vendored name is mentioned by each composition surface ($SURFACES)"
  else fail "composition surfaces drifted from sdx/mo/" "$(printf '%s' "$out" | tr '\n' ';')"; fi
else
  # Delivered by FEAT-015: a missing directory is a regression, not a pre-delivery state.
  fail "sdx/mo/ missing" "$MO_DIR does not exist (vendored by FEAT-015)"
fi

# Red side of [6]: the same suite with MO_DIR pointing at a missing directory must FAIL exactly once.
if [ -z "${MO_DIR_UNDER_TEST:-}" ]; then
  echo "[6r] Missing sdx/mo/ turns the suite red"
  rout="$(MO_DIR_UNDER_TEST="$(mktemp -d)/absent" bash "${BASH_SOURCE[0]}" 2>&1)"; rrc=$?
  if [ "$rrc" -eq 1 ] && [ "$(printf '%s\n' "$rout" | grep -c 'FAIL: sdx/mo/ missing')" = 1 ] \
     && printf '%s' "$rout" | grep -q 'Results: .* 1 failed'; then
    pass "MO_DIR_UNDER_TEST=<absent> -> rc 1 with exactly 1 FAIL (sdx/mo/ missing)"
  else fail "absent sdx/mo/ stayed green" "rc=$rrc"; fi
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "ALL PASSED"
  exit 0
else
  exit 1
fi
