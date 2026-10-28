#!/usr/bin/env bash
# sdx/hooks/lib/test-cmd.sh — test-command resolver (FEAT-016, REQ-MAND-18, 20). Sourced, not executed.
# MIRROR of the resolution block of stop-gate.sh (the per-project runner, then composer / npm / phpunit
# autodetect). stop-gate.sh is NOT edited (self-test copies it with lib/resolve-session.sh); drift is caught
# by the twin scenario (7) in test-suites-gen.sh, which runs the real stop-gate.sh on fixtures.
#
#   test_cmd_resolve <proj>   sets TC_KIND (verify-cmd|composer|npm|phpunit|none) and TC_CMD, the command
#                             as written into tests/suites.yaml (a shell string run from the repo root).
# Presence of .claude/sdx/verify-cmd.sh activates it, not the execute bit (DEBT-026); hence "bash ...".

test_cmd_resolve() {
  local proj="$1"
  TC_KIND="none"; TC_CMD=""
  if [ -f "$proj/.claude/sdx/verify-cmd.sh" ]; then   # SG-ORDER
    TC_KIND="verify-cmd"; TC_CMD="bash .claude/sdx/verify-cmd.sh"   # SG-BASH
  elif [ -f "$proj/composer.json" ] && grep -q '"test"' "$proj/composer.json"; then
    TC_KIND="composer"; TC_CMD="composer test"
  elif [ -f "$proj/package.json" ] && grep -q '"test"' "$proj/package.json"; then
    TC_KIND="npm"; TC_CMD="npm test --silent"
  elif [ -f "$proj/phpunit.xml" ] || [ -f "$proj/phpunit.xml.dist" ]; then
    TC_KIND="phpunit"; TC_CMD="./vendor/bin/phpunit"
  fi
  return 0
}
