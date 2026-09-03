#!/usr/bin/env bash
# Data-layer contract test suite for /sdx:resume (PROC-019, PLAN.md session
# proc-run-as-durable-unit-20260902, Groups 4/5/6).
#
# The slash command /sdx:resume itself (and the touched commands/next.md, verify.md,
# proto.md, status.md) cannot be invoked as slash commands from THIS repository's own
# session — commands/*.md resolve from the INSTALLED plugin copy, not the working tree
# (PROC-020 constraint, see DESIGN.md "Ограничение PROC-020"). This suite closes that
# constraint two ways, not one:
#
#   Group 4 (T14-T18): the bash/jq/git DATA-LAYER CONTRACT /sdx:resume's algorithm stands
#   on is exercised directly, on a throwaway git-repo fixture built by setup_fixture() —
#   this does not depend on which commands/*.md copy is installed anywhere.
#
#   Group 5/6 (T19-T24): the PROSE of commands/*.md (which cannot be executed) is checked
#   STRUCTURALLY — grep for load-bearing formulations, with a demonstrated red side via a
#   mutant copy of the real file — same technique already used in this repo for
#   commands/status.md ([T24]/[T28] in test-selftest.sh).
#
# The one thing genuinely left open — invoking /sdx:resume ITSELF as a real slash command
# (the Task/AskUserQuestion wrapper) — is explicitly named, not silently assumed closed:
# it is PLAN.md T25's job (a live run during THIS session's own Verification, reading the
# working-tree copies of commands/*.md by hand as a checklist), not this suite's.
#
# Fixture isolation (REQ-SESS-2-adjacent hygiene, mirrors test-selftest.sh's
# build_session_fixture / T13 note): every scenario in this file operates on its own
# mktemp -d fixture(s), NEVER on this repo's own live .claude/sessions/*/ or .claude/sdx/ —
# there is a known prior defect class in this repo (a dev test once clobbered a running
# session's .stopgate.out) that this isolation exists to avoid reproducing here.
#
# Self-contained: no network, no timing dependencies. Picked up automatically by
# verify-cmd.sh's test-*.sh glob (no separate registration needed).
# Usage: bash sdx/hooks/test-resume-contract.sh
set -uo pipefail

# Locale: several lint checks below use case-insensitive matching (`grep -Fi`) on Cyrillic
# prose. Case folding for non-ASCII is locale-dependent, so a caller running under LC_ALL=C
# would silently get ASCII-only folding and a weaker check than the one written here. Pin a
# UTF-8 locale when one is available; fall back to the ambient environment otherwise (the
# exact-case half of every such check still holds, only the folding half degrades).
for _loc in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
  if locale -a 2>/dev/null | grep -qix "$_loc"; then export LC_ALL="$_loc"; break; fi
done
unset _loc

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

echo "=== test-resume-contract.sh ==="
echo ""

# normalize <file> — joins a hard-wrapped markdown file into a single whitespace-normalized
# line. This repo hard-wraps prose at ~90-100 cols for diff-friendliness (see sdx/protocol.md,
# commands/resume.md), which means a multi-word load-bearing phrase frequently spans a line
# break in the SOURCE FILE even though it reads as one continuous sentence. A plain
# single-line `grep -F` would then miss a phrase that is genuinely present in the prose —
# this helper is what makes the lint checks below test the PROSE, not its line-wrapping.
normalize() { tr '\n' ' ' < "$1" | tr -s ' '; }

# =============================================================================================
# Group 4 (T14-T18): shared fixture — a throwaway git repo shaped like a real SDX session,
# built ONCE and reused by every scenario below (per PLAN.md: "построить один раз в
# setup_fixture(), переиспользовать во всех сценариях этой группы"). Scenarios that need to
# leave the tree dirty or rewrite history restore it afterwards (git checkout -- <path>) so
# later scenarios still see the fixture in its original committed shape where that matters
# (T14/T15); T16 is pure-function and never touches the fixture; T17 intentionally adds
# further commits (batching proof) — this happens AFTER T14/T15/T16 have already read what
# they need, and T18 does not depend on the fixture's committed shape at all (it is a plain
# jq-transform test against session_state.json's current content).
# =============================================================================================

FIX=""
cleanup() { [ -n "$FIX" ] && rm -rf "$FIX"; FIX=""; }
trap cleanup EXIT

setup_fixture() {
  FIX="$(mktemp -d)"
  ( cd "$FIX" && git init -q && git config user.email "test@example.com" \
      && git config user.name "SDX Test" ) >/dev/null 2>&1

  local sdir="$FIX/.claude/sessions/fix-01"
  mkdir -p "$sdir"

  cat > "$sdir/session_state.json" <<'EOF'
{
  "session_id": "fix-01",
  "type": "feature",
  "stage": "Execution",
  "status": "executing",
  "gate_mode": "interactive",
  "git_branch": "sdx/fix-01",
  "no_code": false,
  "no_gates": false
}
EOF

  cat > "$sdir/PLAN.md" <<'EOF'
# Plan

- [x] T01 First task, done
- [x] T02 Second task, done
- [ ] T03 Third task, open
- [ ] T04 Fourth task, open
EOF

  # Log lines use the format the REAL writer produces (sdx-stage.sh log_line: "[STAGE_CHANGE]
  # Переход на этап <X>"), not a "<X> -> <Y>" shape no writer emits. The trailing [ERROR] line
  # is not decoration: after a CLI death the last line of session.log is routinely an [ERROR]
  # or [CHECKPOINT] entry, which is exactly what made the original `tail -1 "$(grep -l …)"`
  # composition wrong. A fixture whose last line is a [STAGE_CHANGE] cannot tell the correct
  # implementation from the broken one -- see scenario T14b below.
  cat > "$sdir/session.log" <<'EOF'
[2026-09-01 09:00:00] [START] Инициализация сессии fix-01
[2026-09-01 09:05:00] [STAGE_CHANGE] Переход на этап Business Spec
[2026-09-01 10:00:00] [STAGE_CHANGE] Переход на этап Technical Design
[2026-09-01 11:00:00] [STAGE_CHANGE] Переход на этап Task Planning
[2026-09-01 12:00:00] [STAGE_CHANGE] Переход на этап Execution
[2026-09-01 12:30:00] [ERROR] Verification: 2 FAIL
EOF

  cat > "$sdir/decisions_log.md" <<'EOF'
### Развилка: [контракт] Пример зафиксированного решения (этап: Execution)
- Вариант: тестовый принятый вариант
- Обоснование: тестовое обоснование для фикстуры
EOF

  ( cd "$FIX" && git add -A && git commit -q -m "fixture: initial fix-01 state" ) >/dev/null 2>&1
}

setup_fixture
SDIR="$FIX/.claude/sessions/fix-01"

# ---------------------------------------------------------------------------------------------
# T14 — scenario 1: composition without a dirty tree restores stage/progress/transition/
# decisions (REQ-RESUME-1). This is also the executable form of the REQ-KILL-1 acceptance
# criterion, not just a claim about it (PLAN.md T14).
# ---------------------------------------------------------------------------------------------
echo "[T14] scenario 1: composition without dirty tree restores stage/progress/transition/decisions (REQ-RESUME-1, REQ-KILL-1)"
{
  mapfile -t jqvals < <(jq -r '.stage, .no_code, .no_gates, .gate_mode' "$SDIR/session_state.json")
  stage="${jqvals[0]}"; no_code="${jqvals[1]}"; no_gates="${jqvals[2]}"; gate_mode="${jqvals[3]}"
  checked="$(grep -c '^- \[x\]' "$SDIR/PLAN.md" 2>/dev/null || echo 0)"
  total="$(grep -c '^- \[[ x]\]' "$SDIR/PLAN.md" 2>/dev/null || echo 0)"
  first_open="$(grep -m1 '^- \[ \]' "$SDIR/PLAN.md" 2>/dev/null || echo "(нет открытых задач)")"
  last_tr="$(grep '\[STAGE_CHANGE\]' "$SDIR/session.log" 2>/dev/null | tail -1)"
  last_stage_line="${last_tr:-(переходов не зафиксировано)}"
  decisions_found="$([ -f "$SDIR/decisions_log.md" ] && grep -c '^### Развилка' "$SDIR/decisions_log.md" || echo 0)"

  if [ "$stage" = "Execution" ] && [ "$no_code" = "false" ] && [ "$no_gates" = "false" ] \
     && [ "$gate_mode" = "interactive" ] && [ "$checked" -eq 2 ] && [ "$total" -eq 4 ] \
     && printf '%s' "$first_open" | grep -q 'T03' \
     && printf '%s' "$last_stage_line" | grep -q 'Переход на этап Execution' \
     && [ "$decisions_found" -eq 1 ]; then
    pass "green: stage=Execution 2/4 first-open=T03 last-transition='Переход на этап Execution' decisions=1"
  else
    fail "T14 green" "stage=$stage no_code=$no_code no_gates=$no_gates gate_mode=$gate_mode checked=$checked total=$total first_open='$first_open' last='$last_stage_line' decisions=$decisions_found"
  fi

  # Red: corrupt exactly one input (strip the last STAGE_CHANGE line from session.log, done on
  # a disposable COPY of the fixture, never on the shared $FIX) — the corresponding composition
  # value must change and the assertion above must no longer hold for it.
  mut="$(mktemp -d)"; cp -r "$FIX/." "$mut/"
  sdirm="$mut/.claude/sessions/fix-01"
  grep -v 'Переход на этап Execution' "$sdirm/session.log" > "$sdirm/session.log.tmp" \
    && mv "$sdirm/session.log.tmp" "$sdirm/session.log"
  lm="$(grep '\[STAGE_CHANGE\]' "$sdirm/session.log" 2>/dev/null | tail -1)"
  last_mut="${lm:-(переходов не зафиксировано)}"
  if printf '%s' "$last_mut" | grep -q 'Переход на этап Execution'; then
    fail "T14 red (session.log)" "mutation did not change the recovered transition: '$last_mut'"
  else
    pass "red: stripping the last transition line changes the recovered transition (now '$last_mut') — scenario discriminates"
  fi
  rm -rf "$mut"
}

# ---------------------------------------------------------------------------------------------
# T14b — the composition must read the last [STAGE_CHANGE] LINE, not the last line of the file.
# This scenario exists because the delivered composition originally read
#   tail -1 "$(grep -l '[STAGE_CHANGE]' session.log)"
# where grep -l prints the FILE NAME, so tail -1 returned the file's last line whatever its
# category. Found as a FAIL by fresh-eyes review of this very delivery. The fixture's trailing
# [ERROR] line is what makes the two forms observably different: with a [STAGE_CHANGE] last,
# both forms agree and no test could tell them apart.
echo "[T14b] composition reads the last [STAGE_CHANGE], not the last log line (regression guard)"
{
  correct="$(grep '\[STAGE_CHANGE\]' "$SDIR/session.log" 2>/dev/null | tail -1 || echo '(переходов не зафиксировано)')"
  # The defective form, reproduced verbatim as the mutant:
  defective="$(tail -1 "$(grep -l '\[STAGE_CHANGE\]' "$SDIR/session.log" 2>/dev/null)" 2>/dev/null)"

  if printf '%s' "$correct" | grep -q '\[STAGE_CHANGE\] Переход на этап Execution'; then
    pass "green: correct form recovers the last transition even with a trailing [ERROR] line"
  else
    fail "T14b green" "correct='$correct'"
  fi

  if printf '%s' "$defective" | grep -q '\[ERROR\]'; then
    pass "red: the defective 'tail -1 \$(grep -l …)' form returns the [ERROR] line instead — the two forms are observably different"
  else
    fail "T14b red" "defective form did not reproduce the defect: '$defective'"
  fi

  # Boundary: a log with no transitions at all must not yield an empty string silently.
  #
  # This assertion MUST be evaluated in a shell that does NOT inherit this suite's options.
  # The first version of it was green for the wrong reason: the delivered line ended in
  # `| tail -1 || echo "(…)"`, whose fallback fires only under `set -o pipefail` (a pipeline's
  # status is `tail`'s, and `tail -1` exits 0 on empty input). This suite sets `-uo pipefail`;
  # the agent shell that actually runs the command does not. The test proved a property of its
  # own environment and called it a property of the delivery -- caught by fresh-eyes review as
  # a FAIL. Hence: run the delivered form in BOTH environments and require the same answer.
  nolog="$(mktemp -d)"
  printf '[t] [START] x\n' > "$nolog/session.log"
  # The delivered composition, quoted verbatim from commands/resume.md.
  delivered='last_tr="$(grep '"'"'\[STAGE_CHANGE\]'"'"' "$sdir/session.log" 2>/dev/null | tail -1)"; printf '"'"'%s\n'"'"' "${last_tr:-(переходов не зафиксировано)}"'
  plain="$(env -i bash --noprofile --norc -c "sdir='$nolog'; $delivered")"
  strict="$(env -i bash --noprofile --norc -c "set -uo pipefail; sdir='$nolog'; $delivered")"
  if [ "$plain" = "(переходов не зафиксировано)" ] && [ "$strict" = "$plain" ]; then
    pass "boundary: no-transition log yields the explicit marker identically with and without pipefail (env-independent)"
  else
    fail "T14b boundary" "plain='$plain' strict='$strict' (expected both to be the explicit marker)"
  fi

  # Red side for the boundary: the pipefail-dependent form must be shown to DIFFER between the
  # two environments -- otherwise the check above would pass for any implementation.
  fragile='grep '"'"'\[STAGE_CHANGE\]'"'"' "$sdir/session.log" 2>/dev/null | tail -1 || echo "(переходов не зафиксировано)"'
  f_plain="$(env -i bash --noprofile --norc -c "sdir='$nolog'; $fragile")"
  f_strict="$(env -i bash --noprofile --norc -c "set -uo pipefail; sdir='$nolog'; $fragile")"
  if [ -z "$f_plain" ] && [ "$f_strict" = "(переходов не зафиксировано)" ]; then
    pass "red: the '|| echo' form is empty without pipefail and non-empty with it — the check discriminates env-dependence"
  else
    fail "T14b boundary red" "f_plain='$f_plain' f_strict='$f_strict'"
  fi
  rm -rf "$nolog"

  # Same defect class, second instance: the PLAN.md progress counters. `grep -c` PRINTS "0"
  # and RETURNS 1 when nothing matches, so a `… || echo 0` tail emits TWO lines ("0\n0") on a
  # session whose plan has no completed task yet -- the common shape of a session killed early,
  # i.e. exactly the case /sdx:resume exists for. The delivered form assigns and defaults with
  # ${var:-0} instead, which yields one line both when the file is missing and when it matches
  # nothing. Asserted on line COUNT, not just value: a value check alone passes for "0\n0".
  planfx="$(mktemp -d)"
  printf '# plan\n- [ ] T01 open\n- [ ] T02 open\n' > "$planfx/PLAN.md"
  delivered_cnt='done_n="$(grep -c "^- \[x\]" "$p/PLAN.md" 2>/dev/null)"; printf "%s\n" "${done_n:-0}"'
  fragile_cnt='grep -c "^- \[x\]" "$p/PLAN.md" 2>/dev/null || echo 0'
  d_lines="$(env -i bash --noprofile --norc -c "p='$planfx'; $delivered_cnt" | wc -l)"
  d_val="$(env -i bash --noprofile --norc -c "p='$planfx'; $delivered_cnt")"
  f_lines="$(env -i bash --noprofile --norc -c "p='$planfx'; $fragile_cnt" | wc -l)"
  if [ "$d_lines" -eq 1 ] && [ "$d_val" = "0" ]; then
    pass "boundary: plan with no completed task yields exactly one line '0'"
  else
    fail "T14b plan counter" "lines=$d_lines value='$d_val'"
  fi
  if [ "$f_lines" -eq 2 ]; then
    pass "red: the '|| echo 0' form emits two lines on the same input — the check discriminates"
  else
    fail "T14b plan counter red" "expected 2 lines from the fragile form, got $f_lines"
  fi

  # And the missing-file case must still yield one line, not an empty one.
  m_lines="$(env -i bash --noprofile --norc -c "p='$planfx/nowhere'; $delivered_cnt" | wc -l)"
  m_val="$(env -i bash --noprofile --norc -c "p='$planfx/nowhere'; $delivered_cnt")"
  if [ "$m_lines" -eq 1 ] && [ "$m_val" = "0" ]; then
    pass "boundary: missing PLAN.md yields one line '0', not an empty line"
  else
    fail "T14b plan counter (missing file)" "lines=$m_lines value='$m_val'"
  fi
  rm -rf "$planfx"
}

# ---------------------------------------------------------------------------------------------
# T15 — scenario 2: dirty-tree guard. (a) clean tree: HEAD-read and naive disk-read agree.
# (b) dirty tree: they diverge (proves the guard is necessary). Then a separate check that
# actually EXERCISES the guard sequence itself ("check git status --porcelain, and if not
# empty, refuse to read at all"), not just the path-divergence fact (PLAN.md T15 explicit
# requirement, DESIGN.md "Рекомендация developer'у Execution").
# ---------------------------------------------------------------------------------------------
echo "[T15] scenario 2: dirty-tree guard — divergence proof + actual guard sequence (REQ-KILL-1/2)"
{
  clean_head="$( (cd "$FIX" && git show HEAD:.claude/sessions/fix-01/PLAN.md) | grep -c '\[x\]')"
  clean_disk="$(grep -c '\[x\]' "$SDIR/PLAN.md")"
  if [ "$clean_head" -eq 2 ] && [ "$clean_disk" -eq 2 ] && [ "$clean_head" -eq "$clean_disk" ]; then
    pass "T15a: on a clean tree, git-show(HEAD) and naive disk read agree (2 == 2)"
  else
    fail "T15a" "clean_head=$clean_head clean_disk=$clean_disk"
  fi

  # Dirty the tree: flip one open checkbox to done, uncommitted.
  sed -i 's/^- \[ \] T03/- [x] T03/' "$SDIR/PLAN.md"
  dirty_head="$( (cd "$FIX" && git show HEAD:.claude/sessions/fix-01/PLAN.md) | grep -c '\[x\]')"
  dirty_disk="$(grep -c '\[x\]' "$SDIR/PLAN.md")"
  if [ "$dirty_head" -eq 2 ] && [ "$dirty_disk" -eq 3 ] && [ "$dirty_head" -ne "$dirty_disk" ]; then
    pass "T15b: on a dirty tree, git-show(HEAD)=2 diverges from naive disk-read=3 — proves the guard is necessary"
  else
    fail "T15b" "dirty_head=$dirty_head dirty_disk=$dirty_disk"
  fi

  # guard_sequence <dir> — mirrors commands/resume.md step 2 literally: check `git status
  # --porcelain` FIRST; if it is non-empty, refuse to read anything else at all (not just
  # "note the divergence" — actually stop before touching the file).
  guard_sequence() {
    local dir="$1" dirty
    dirty="$(cd "$dir" && git status --porcelain)"
    if [ -n "$dirty" ]; then
      echo "GUARD: dirty tree, refusing to read" >&2
      return 1
    fi
    grep -c '\[x\]' "$dir/.claude/sessions/fix-01/PLAN.md"
  }

  if guard_sequence "$FIX" >/tmp/sdx-resume-t15-out 2>/tmp/sdx-resume-t15-err; then
    fail "T15 guard" "guard_sequence succeeded on a DIRTY tree (should have refused): $(cat /tmp/sdx-resume-t15-out)"
  else
    pass "T15 guard: guard_sequence refuses to read on a dirty tree (non-zero return, no leaked disk value)"
  fi
  rm -f /tmp/sdx-resume-t15-out /tmp/sdx-resume-t15-err

  # Red: a mutant guard with the `git status --porcelain` check removed leaks the uncommitted
  # value on the SAME dirty tree — demonstrating the check is load-bearing, not decorative.
  guard_sequence_mutant() {
    local dir="$1"
    grep -c '\[x\]' "$dir/.claude/sessions/fix-01/PLAN.md"
  }
  leaked="$(guard_sequence_mutant "$FIX")"
  if [ "$leaked" -eq 3 ]; then
    pass "red: removing the git status --porcelain check from guard_sequence leaks the uncommitted value (3) — the guard's absence is exactly what this scenario catches"
  else
    fail "T15 red" "expected mutant to leak 3, got $leaked"
  fi

  # Restore clean tree for subsequent scenarios that depend on the committed fixture shape.
  (cd "$FIX" && git checkout -q -- .claude/sessions/fix-01/PLAN.md)
}

# ---------------------------------------------------------------------------------------------
# T16 — scenario 3+4: a fork matching an existing decisions_log.md record is applied silently
# (no re-asking); a fork WITHOUT a match falls through to the ordinary path (REQ-RESUME-3).
# ---------------------------------------------------------------------------------------------
echo "[T16] scenario 3+4: decisions_log.md honored (REQ-RESUME-3)"
{
  # resolve_fork <log> <terms> — mirrors commands/resume.md step 6 / commands/next.md step 2б:
  # simple keyword grep against decisions_log.md; found -> apply silently, not found -> ask.
  resolve_fork() {
    local log="$1" terms="$2"
    if [ -f "$log" ] && grep -qi -- "$terms" "$log"; then
      echo "applied-silently"
    else
      echo "ask-user"
    fi
  }

  outcome_a="$(resolve_fork "$SDIR/decisions_log.md" "Пример зафиксированного решения")"
  if [ "$outcome_a" = "applied-silently" ]; then
    pass "T16a: fork matching an existing decisions_log.md record is applied silently, no AskUserQuestion"
  else
    fail "T16a" "expected applied-silently, got $outcome_a"
  fi

  outcome_b="$(resolve_fork "$SDIR/decisions_log.md" "совершенно другая никогда не записанная развилка")"
  if [ "$outcome_b" = "ask-user" ]; then
    pass "T16b: fork with no match falls through to the ordinary path (ask), no dedicated branch"
  else
    fail "T16b" "expected ask-user, got $outcome_b"
  fi

  # Red side (branch (a) only): removing the grep check turns a real match into "not found".
  resolve_fork_mutant() {
    echo "ask-user"   # grep check removed entirely
  }
  outcome_a_mut="$(resolve_fork_mutant "$SDIR/decisions_log.md" "Пример зафиксированного решения")"
  if [ "$outcome_a_mut" = "ask-user" ]; then
    pass "red: removing the grep-match check turns a real 'found' into 'not found' — scenario (a) discriminates"
  else
    fail "T16 red" "expected mutant to report ask-user, got $outcome_a_mut"
  fi

  # Honest limit on branch (b) — no automated red side, and this is not an oversight.
  # DESIGN.md "Развилка 7" is explicit: "отсутствие записи И ЕСТЬ индикатор, обрабатываемый
  # уже существующим путём (нет совпадения -> обычное поведение гейта)" — there is no
  # DEDICATED code path for "no match" that could be broken independently of branch (a)'s
  # grep check above; (b) IS the fallthrough of the same one check, not a second mechanism.
  # No mutation exists that flips (b) without ALSO being exactly the (a) mutation already
  # demonstrated — same class of honest limit as test-sdx-stage.sh scenario [32] (T03/T18
  # below) and test-selftest.sh [T08]/[T27].
}

# ---------------------------------------------------------------------------------------------
# T17 — scenario 5: batching — a decision record commits together with the state/log change
# that triggered it, in the SAME commit, not a separate one (REQ-DEC-4, REQ-BOUND-3).
# ---------------------------------------------------------------------------------------------
echo "[T17] scenario 5: batching — decision record commits with the transition, no separate commit (REQ-DEC-4, REQ-BOUND-3)"
{
  before1="$(cd "$FIX" && git rev-list --count HEAD)"
  jq '.stage = "Verification"' "$SDIR/session_state.json" > "$SDIR/session_state.json.tmp" \
    && mv "$SDIR/session_state.json.tmp" "$SDIR/session_state.json"
  printf '[2026-09-01 13:00:00] [STAGE_CHANGE] Execution -> Verification\n' >> "$SDIR/session.log"
  printf '\n### Развилка: [объём] Batching test decision (этап: Verification)\n- Вариант: batch-committed\n- Обоснование: proves batching\n' >> "$SDIR/decisions_log.md"

  ( cd "$FIX" && git add .claude/sessions/fix-01/session_state.json \
      .claude/sessions/fix-01/session.log .claude/sessions/fix-01/decisions_log.md \
      && git commit -q -m "sdx(fix-01): stage Execution -> Verification" )

  after1="$(cd "$FIX" && git rev-list --count HEAD)"
  files_in_commit="$(cd "$FIX" && git diff-tree --no-commit-id --name-only -r HEAD)"
  n_new_commits=$((after1 - before1))
  has_state=0; printf '%s\n' "$files_in_commit" | grep -qF 'session_state.json' && has_state=1
  has_log=0; printf '%s\n' "$files_in_commit" | grep -qF 'session.log' && has_log=1
  has_dec=0; printf '%s\n' "$files_in_commit" | grep -qF 'decisions_log.md' && has_dec=1

  if [ "$n_new_commits" -eq 1 ] && [ "$has_state" -eq 1 ] && [ "$has_log" -eq 1 ] && [ "$has_dec" -eq 1 ]; then
    pass "green: exactly 1 new commit carries session_state.json + session.log + decisions_log.md together"
  else
    fail "T17 green" "n_new_commits=$n_new_commits has_state=$has_state has_log=$has_log has_dec=$has_dec files='$files_in_commit'"
  fi

  # Red: split into two separate commits (state+log, then decisions_log.md separately) — the
  # anti-pattern REQ-BOUND-3 forbids. The count of commits carrying this second transition
  # becomes 2, not 1.
  jq '.stage = "Deployment"' "$SDIR/session_state.json" > "$SDIR/session_state.json.tmp" \
    && mv "$SDIR/session_state.json.tmp" "$SDIR/session_state.json"
  printf '[2026-09-01 14:00:00] [STAGE_CHANGE] Verification -> Deployment\n' >> "$SDIR/session.log"
  printf '\n### Развилка: [FAIL] Second batching test decision (этап: Deployment)\n- Вариант: split-committed\n- Обоснование: proves the red side\n' >> "$SDIR/decisions_log.md"

  before2="$(cd "$FIX" && git rev-list --count HEAD)"
  ( cd "$FIX" && git add .claude/sessions/fix-01/session_state.json .claude/sessions/fix-01/session.log \
      && git commit -q -m "sdx(fix-01): stage Verification -> Deployment" )
  ( cd "$FIX" && git add .claude/sessions/fix-01/decisions_log.md \
      && git commit -q -m "sdx(fix-01): decision record (separate commit — anti-pattern)" )
  after2="$(cd "$FIX" && git rev-list --count HEAD)"
  n_red=$((after2 - before2))

  if [ "$n_red" -eq 2 ]; then
    pass "red: splitting state+log and decisions_log.md into two commits makes the transition span 2 commits, not 1 — discriminates"
  else
    fail "T17 red" "expected 2 commits for the split anti-pattern, got $n_red"
  fi
}

# ---------------------------------------------------------------------------------------------
# T18 — scenario 6: legacy artifacts/history fields survive `.stage = $s` on a resume-shaped
# fixture (REQ-STATE-2), a second-angle regression of test-sdx-stage.sh's [31]/[32] (T02/T03).
# ---------------------------------------------------------------------------------------------
echo "[T18] scenario 6: legacy artifacts/history fields survive .stage = \$s on a resume-fixture (REQ-STATE-2)"
{
  # Honest limit, dословно the same reasoning as test-sdx-stage.sh scenario [32] (T03): no
  # line in sdx-stage.sh reads .artifacts/.history today, so the only mutation that could turn
  # this scenario red is ADDING code that reads them — i.e. reproducing DEBT-038 itself. Not
  # duplicated here in full; see test-sdx-stage.sh [32] for the complete argument.
  legacy="$(mktemp)"
  jq '. + {artifacts: [], history: []}' "$SDIR/session_state.json" > "$legacy"
  result="$(jq --arg s "Closeout" '.stage = $s' "$legacy")"
  has_artifacts="$(echo "$result" | jq 'has("artifacts")')"
  has_history="$(echo "$result" | jq 'has("history")')"
  new_stage="$(echo "$result" | jq -r '.stage')"
  artifacts_val="$(echo "$result" | jq -c '.artifacts')"
  history_val="$(echo "$result" | jq -c '.history')"

  if [ "$has_artifacts" = "true" ] && [ "$has_history" = "true" ] && [ "$new_stage" = "Closeout" ] \
     && [ "$artifacts_val" = "[]" ] && [ "$history_val" = "[]" ]; then
    pass "legacy artifacts/history fields survive .stage = \$s untouched, stage updates correctly"
  else
    fail "T18" "has_artifacts=$has_artifacts has_history=$has_history stage=$new_stage artifacts=$artifacts_val history=$history_val"
  fi
  rm -f "$legacy"
}

# =============================================================================================
# Group 5 (T19-T23): structural checks on commands/*.md prose — grep for load-bearing
# formulations, red side via a mutant copy of the real file (style: [T24]/[T28] in
# test-selftest.sh).
# =============================================================================================

# ---------------------------------------------------------------------------------------------
echo "[T19] structural check: commands/status.md step 6 present (decisions_log.md marker, grep pattern, empty-state wording)"
{
  STATUS_MD="$ROOT/commands/status.md"
  status6_checks() {
    local f="$1" n=0
    grep -qF 'decisions_log.md' "$f" && n=$((n + 1))
    grep -qF "grep '^### Развилка'" "$f" && n=$((n + 1))
    grep -qF 'журнал решений пуст/отсутствует' "$f" && n=$((n + 1))
    echo "$n"
  }
  n_checks="$(status6_checks "$STATUS_MD")"
  if [ "$n_checks" -eq 3 ]; then
    pass "green: 3/3 structural markers for status.md step 6 present"
  else
    fail "T19 green" "n_checks=$n_checks"
  fi

  # Note: all three markers live in ONE paragraph line in status.md (step 6 is a single
  # sentence) — `grep -v` of the whole line would wipe all three at once and prove nothing
  # about which check discriminates. `sed` removes only the targeted SUBSTRING, leaving the
  # other two markers on the same line intact.
  mutated="$(mktemp)"
  sed 's/журнал решений пуст\/отсутствует//' "$STATUS_MD" > "$mutated"
  n_red="$(status6_checks "$mutated")"
  if [ "$n_red" -eq 2 ]; then
    pass "red: stripping the empty-state wording drops the count to 2/3 — gate discriminates"
  else
    fail "T19 red" "expected 2, got $n_red"
  fi
  rm -f "$mutated"
}

# ---------------------------------------------------------------------------------------------
echo "[T20] structural check: commands/resume.md — guard, all-records sweep, REQ-RESUME-3, asymmetry, kill-test phrase"
{
  RESUME_MD="$ROOT/commands/resume.md"
  resume_checks() {
    local f="$1" n=0
    grep -qF '**Гард чистого рабочего дерева.**' "$f" && n=$((n + 1))                # (а)
    grep -qF 'это **ВСЕ**' "$f" && n=$((n + 1))                                       # (б)
    grep -qF 'Соблюдение записанных решений (REQ-RESUME-3)' "$f" && n=$((n + 1))      # (в)
    grep -qF 'не распространяется' "$f" && n=$((n + 1))                               # (г)
    normalize "$f" | grep -qF 'на момент последнего зафиксированного (закоммиченного) состояния' && n=$((n + 1))  # (д)
    # (е) The composition block must read the last [STAGE_CHANGE] LINE. Positive marker plus a
    # NEGATIVE one: the defective `tail -1 "$(grep -l …)"` form must not come back. Guarding the
    # absence matters as much as the presence here -- the two forms differ only on logs whose
    # last line is not a transition, i.e. exactly the CLI-death case this command exists for.
    grep -qF "grep '\\[STAGE_CHANGE\\]' \"\$sdir/session.log\" 2>/dev/null | tail -1" "$f" \
      && ! grep -qF 'tail -1 "$(grep -l' "$f" \
      && ! grep -qF '| tail -1 || echo' "$f" \
      && n=$((n + 1))
    echo "$n"
  }
  n_checks="$(resume_checks "$RESUME_MD")"
  if [ "$n_checks" -eq 6 ]; then
    pass "green: 6/6 structural markers present (guard, all-records, REQ-RESUME-3, asymmetry, kill-test phrase, correct STAGE_CHANGE read)"
  else
    fail "T20 green" "n_checks=$n_checks"
  fi

  # Independent red branch for marker (е): reintroduce the defective form and watch it drop.
  regressed="$(mktemp)"
  # Mutant = the file with the defective form present (as a careless future edit would leave
  # it). The negative half of marker (е) must fire on its mere presence, wherever it sits.
  cp "$RESUME_MD" "$regressed"
  printf '   tail -1 "$(grep -l %s[STAGE_CHANGE]%s "$sdir/session.log")"\n' "'" "'" >> "$regressed"
  n_reg="$(resume_checks "$regressed")"
  if [ "$n_reg" -eq 5 ]; then
    pass "red: reintroducing the defective 'tail -1 \$(grep -l …)' form drops the count to 5/6 — the regression is caught"
  else
    fail "T20 red (STAGE_CHANGE read)" "expected 5, got $n_reg"
  fi
  rm -f "$regressed"

  mutated="$(mktemp)"
  grep -v 'Гард чистого рабочего дерева' "$RESUME_MD" > "$mutated"
  n_red="$(resume_checks "$mutated")"
  if [ "$n_red" -eq 5 ]; then
    pass "red: stripping the clean-tree guard heading drops the count to 5/6 — gate discriminates"
  else
    fail "T20 red" "expected 5, got $n_red"
  fi
  rm -f "$mutated"
}

# ---------------------------------------------------------------------------------------------
echo "[T21] structural check: commands/next.md — four markers (auto symmetry, batched commit, REQ-RESUME-3 check, unconditional write rule)"
{
  NEXT_MD="$ROOT/commands/next.md"
  next_checks() {
    local f="$1" n=0
    grep -qF 'Стоп-рубрика останавливает `auto`-сессию так же, как `interactive`' "$f" && n=$((n + 1))   # (а)
    grep -qF 'decisions_log.md, если он был изменён в этом ходе' "$f" && n=$((n + 1))                     # (б)
    grep -qF '2б. **Соблюдение записанных решений (REQ-RESUME-3' "$f" && n=$((n + 1))                     # (в)
    # (г) REQ-DEC-1/3: the instruction to WRITE the record must be unconditional, i.e. it must
    # live in its own step, NOT inside the `- Если "auto":` bullet of step 2а. The first version
    # of this delivery had it only there, which made the mere EXISTENCE of the instruction depend
    # on gate_mode -- in `interactive`, the default and REQ-DEC-1's first addressee, the command
    # said nothing about recording at all. Found as a FAIL by fresh-eyes review. Marker (а) alone
    # cannot catch that: it greps the auto-branch phrasing and would happily cement the defect.
    grep -qF '2в. **Запись решения, принятого на стоп-рубрике' "$f" \
      && grep -qF 'БЕЗУСЛОВНО, в любом `gate_mode`' "$f" \
      && n=$((n + 1))
    echo "$n"
  }
  n_checks="$(next_checks "$NEXT_MD")"
  if [ "$n_checks" -eq 4 ]; then
    pass "green: 4/4 markers present (auto symmetry, batched commit, REQ-RESUME-3 check, unconditional write rule)"
  else
    fail "T21 green" "n_checks=$n_checks"
  fi

  # Red for (г): strip the unconditional write step and watch the count drop. Without this
  # branch the marker would be asserted green-only, i.e. the exact regression it guards against
  # (folding the rule back under the auto branch) could return unnoticed.
  regressed="$(mktemp)"
  grep -v '2в. \*\*Запись решения, принятого на стоп-рубрике' "$NEXT_MD" > "$regressed"
  n_reg="$(next_checks "$regressed")"
  if [ "$n_reg" -eq 3 ]; then
    pass "red: stripping the unconditional write step drops the count to 3/4 — gate_mode-independence is guarded"
  else
    fail "T21 red (unconditional write)" "expected 3, got $n_reg"
  fi
  rm -f "$regressed"

  # Red: strip edit (в) — the REQ-RESUME-3 pre-AskUserQuestion check.
  mutated="$(mktemp)"
  grep -v '2б. \*\*Соблюдение записанных решений (REQ-RESUME-3' "$NEXT_MD" > "$mutated"
  n_red="$(next_checks "$mutated")"
  if [ "$n_red" -eq 3 ]; then
    pass "red: stripping edit (в) (pre-AskUserQuestion check) drops the count to 3/4 — gate discriminates"
  else
    fail "T21 red" "expected 3, got $n_red"
  fi
  rm -f "$mutated"
}

# ---------------------------------------------------------------------------------------------
echo "[T22] structural check: commands/verify.md — decision record batched with verification_report.md commit"
{
  VERIFY_MD="$ROOT/commands/verify.md"
  verify_checks() {
    local f="$1" n=0
    grep -qF 'Запись в журнал решений (`PROC-019`)' "$f" && n=$((n + 1))
    grep -qF 'decisions_log.md, если он был изменён на шаге 7' "$f" && n=$((n + 1))
    # Third marker: the explicit NEGATIVE note in step 5 (reviewer's input composition).
    # DESIGN.md ("Безопасность" -> "Изоляция reviewer") asks for it by name, and asks for it
    # HERE rather than only in sdx/protocol.md, precisely to stop a future edit from adding
    # decisions_log.md to the reviewer's input "for completeness". A note whose whole purpose
    # is to prevent a future regression is worthless if its own absence is not caught.
    grep -qF 'в состав входа НЕ входит' "$f" && n=$((n + 1))
    echo "$n"
  }
  n_checks="$(verify_checks "$VERIFY_MD")"
  if [ "$n_checks" -eq 3 ]; then
    pass "green: 3/3 markers present (decisions_log.md write + batched commit + reviewer-isolation note)"
  else
    fail "T22 green" "n_checks=$n_checks"
  fi

  mutated="$(mktemp)"
  grep -vF 'Запись в журнал решений (`PROC-019`)' "$VERIFY_MD" > "$mutated"
  n_red="$(verify_checks "$mutated")"
  if [ "$n_red" -eq 2 ]; then
    pass "red: stripping the decisions_log.md write step drops the count to 2/3 — gate discriminates"
  else
    fail "T22 red" "expected 2, got $n_red"
  fi

  # Second, independent red branch: strip ONLY the reviewer-isolation note. Without its own
  # mutation the third marker would be asserted green-only, i.e. it could be silently deleted
  # by the same drift it exists to prevent.
  grep -vF 'в состав входа НЕ входит' "$VERIFY_MD" > "$mutated"
  n_red2="$(verify_checks "$mutated")"
  if [ "$n_red2" -eq 2 ]; then
    pass "red: stripping the reviewer-isolation note alone drops the count to 2/3 — the note itself is guarded"
  else
    fail "T22 red (isolation note)" "expected 2, got $n_red2"
  fi
  rm -f "$mutated"
}

# ---------------------------------------------------------------------------------------------
echo "[T23] structural check: commands/proto.md — decision recorded in both branches (reject/legalize)"
{
  PROTO_MD="$ROOT/commands/proto.md"
  proto_decl_count() { grep -c 'акт категории `\[деструктив\]`' "$1" 2>/dev/null || echo 0; }

  n_checks="$(proto_decl_count "$PROTO_MD")"
  if [ "$n_checks" -eq 2 ]; then
    pass "green: 2/2 branches (reject + legalize) record a decisions_log.md entry"
  else
    fail "T23 green" "n_checks=$n_checks"
  fi

  # Only the legalize-branch insertion contains "Легализация прототипа — акт категории"
  # (the reject-branch insertion reads "Отклонение прототипа — акт категории") — this text
  # is unique to one of the two lines, so a plain fixed-string removal drops exactly one.
  mutated="$(mktemp)"
  grep -vF 'Легализация прототипа — акт категории' "$PROTO_MD" > "$mutated"
  n_red="$(proto_decl_count "$mutated")"
  if [ "$n_red" -eq 1 ]; then
    pass "red: removing one of the two insertions (legalize branch) drops the count from 2 to 1 — discriminates"
  else
    fail "T23 red" "expected 1, got $n_red"
  fi
  rm -f "$mutated"
}

# =============================================================================================
# Group 6 (T24): documentation lint — three checks from DESIGN.md "Тестовая стратегия" →
# "Документационный lint", each with all three red-side branches demonstrated (task
# instruction: "не пропускать ни одно под предлогом «уже покрыто выше»").
# =============================================================================================

echo "[T24] documentation lint: kill-test phrase / no-overclaim / asymmetry named explicitly (REQ-KILL-1/2, REQ-BOUND-2)"
{
  PROTOCOL_MD="$ROOT/sdx/protocol.md"
  RESUME_MD="$ROOT/commands/resume.md"
  KILL_PHRASE='на момент последнего зафиксированного (закоммиченного) состояния'
  OVERCLAIM_RE='восстанавливает.*(полностью|без каких-либо потерь)'
  ASYM_PHRASE='не распространяется'

  # --- (1) kill-test boundary phrase present, both files, >=1 each ---
  in_protocol=0; normalize "$PROTOCOL_MD" | grep -qF -- "$KILL_PHRASE" && in_protocol=1
  in_resume=0; normalize "$RESUME_MD" | grep -qF -- "$KILL_PHRASE" && in_resume=1
  if [ "$in_protocol" -eq 1 ] && [ "$in_resume" -eq 1 ]; then
    pass "(1) green: kill-test boundary phrase found in both sdx/protocol.md and commands/resume.md"
  else
    fail "T24(1) green" "in_protocol=$in_protocol in_resume=$in_resume"
  fi

  mut1a="$(mktemp)"; grep -v 'зафиксированного' "$PROTOCOL_MD" > "$mut1a"
  r1a=0; normalize "$mut1a" | grep -qF -- "$KILL_PHRASE" && r1a=1
  if [ "$r1a" -eq 0 ]; then
    pass "(1) red a: stripping the phrase's line(s) from sdx/protocol.md drops the match to 0 — discriminates"
  else
    fail "T24(1) red a" "expected 0, still found"
  fi
  rm -f "$mut1a"

  mut1b="$(mktemp)"; grep -v 'зафиксированного' "$RESUME_MD" > "$mut1b"
  r1b=0; normalize "$mut1b" | grep -qF -- "$KILL_PHRASE" && r1b=1
  if [ "$r1b" -eq 0 ]; then
    pass "(1) red b: stripping the phrase's line(s) from commands/resume.md drops the match to 0 — discriminates"
  else
    fail "T24(1) red b" "expected 0, still found"
  fi
  rm -f "$mut1b"

  # --- (2) overclaim absent, both files, ==0 ---
  oc_protocol=0; normalize "$PROTOCOL_MD" | grep -qE -- "$OVERCLAIM_RE" && oc_protocol=1
  oc_resume=0; normalize "$RESUME_MD" | grep -qE -- "$OVERCLAIM_RE" && oc_resume=1
  if [ "$oc_protocol" -eq 0 ] && [ "$oc_resume" -eq 0 ]; then
    pass "(2) green: no overclaim wording ('восстанавливает...полностью/без каких-либо потерь') in either file"
  else
    fail "T24(2) green" "oc_protocol=$oc_protocol oc_resume=$oc_resume"
  fi

  mut2="$(mktemp)"
  { cat "$RESUME_MD"; printf '\n\nMUTANT: команда восстанавливает состояние полностью, без исключений.\n'; } > "$mut2"
  oc_mut=0; normalize "$mut2" | grep -qE -- "$OVERCLAIM_RE" && oc_mut=1
  if [ "$oc_mut" -eq 1 ]; then
    pass "(2) red: injecting a deliberate overclaim sentence flips the match to 1 — gate discriminates"
  else
    fail "T24(2) red" "expected the injected overclaim mutant to be caught, was not"
  fi
  rm -f "$mut2"

  # --- (3) asymmetry named explicitly, sdx/protocol.md, "Журнал решений" section, >=1 ---
  # Case-insensitive: sdx/protocol.md capitalizes "НЕ распространяется" mid-sentence for
  # emphasis; DESIGN.md's own lint table allows "эквивалентная формулировка", and SPEC.md's own
  # acceptance-criteria text uses the lowercase form — the CONCEPT, not the exact casing, is
  # what this check enforces (commands/resume.md, by contrast, happens to use the lowercase
  # form on its own single un-wrapped line — see T20(г) above, which checks it case-sensitively).
  asym_protocol=0; normalize "$PROTOCOL_MD" | grep -qFi -- "$ASYM_PHRASE" && asym_protocol=1
  if [ "$asym_protocol" -eq 1 ]; then
    pass "(3) green: asymmetry ('не распространяется') named explicitly in sdx/protocol.md"
  else
    fail "T24(3) green" "asym_protocol=$asym_protocol"
  fi

  mut3="$(mktemp)"; grep -vi 'распространяется' "$PROTOCOL_MD" > "$mut3"
  r3=0; normalize "$mut3" | grep -qFi -- "$ASYM_PHRASE" && r3=1
  if [ "$r3" -eq 0 ]; then
    pass "(3) red: stripping the asymmetry line from sdx/protocol.md drops the match to 0 — discriminates"
  else
    fail "T24(3) red" "expected 0, still found"
  fi
  rm -f "$mut3"
}

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "ALL PASSED"
  exit 0
else
  exit 1
fi
