#!/usr/bin/env bash
# SDX selftest (FEAT-014 + DEBT-010): синтетическая проба живости preflight.sh/prod-guard.sh/
# stop-gate.sh. Регистрируется КАК ОТДЕЛЬНАЯ запись SessionStart (DESIGN.md "Проводка"), не
# расширяет preflight.sh. НИКОГДА не завершается ненулевым кодом (REQ-FAIL-1/REQ-FAIL-2) и
# НЕ является статической проверкой формы вызова (bash <путь>) — класс регрессии BUG-008
# (потеря бита x) этой пробой структурно не обнаруживается, см. DESIGN.md "Честные ограничения".
# sdx-stage.sh НЕ входит в периметр (см. DESIGN.md, развилка 1).
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$here/../.." && pwd)}"
proj="${CLAUDE_PROJECT_DIR:-.}"

# Guard: this hook may only touch a project that has gone through /sdx:init. The canonical
# marker of an SDX project (same one /sdx:start step 1 checks) is the existence of
# `.claude/sdx/`. In a project that never ran /sdx:init this hook MUST be as transparent as
# prod-guard.sh (`[ -f "$conf" ] || exit 0`) and stop-gate.sh (`[ -z "$sid" ] && exit 0`) —
# no directory, no file, no stderr output. This check MUST run before any operation that could
# create a directory or file (mkdir/mktemp/write_cache), so it comes right after $proj is known.
[ -d "$proj/.claude/sdx" ] || exit 0

# Тест-крючок: позволяет test-selftest.sh подставить фикстур-копии хуков (в т.ч. искусственно
# медленные/неправильные) без правки продовых hooks_dir по умолчанию.
hooks_dir="${SDX_SELFTEST_HOOKS_DIR:-$plugin_root/sdx/hooks}"
budget_ms="${SDX_SELFTEST_BUDGET_MS:-2000}"

cache_dir="$proj/.claude/sdx/.cache"
cache_file="$cache_dir/selftest.json"

now_ns() { date +%s%N; }   # НЕ date +%s%3N — см. DESIGN.md, развилка 4 (ширина %N игнорируется
                            # на этой машине). ВНИМАНИЕ: %s%N — расширение GNU/uutils date и НЕ
                            # переносимо: на BSD/macOS оно возвращает литерал "N". Что именно
                            # сломается дальше — НЕ проверено (нет BSD-окружения): арифметика
                            # под `set -u` может как оборвать исполнение до записи кэша, так и
                            # дать пустой duration_ms. Утверждать конкретный исход, не прогнав
                            # его, здесь запрещено ценой двух ошибок этой же сессии. Известное
                            # ограничение; решение — оформить записью бэклога на Closeout, а не
                            # чинить вслепую.

# ---- отпечаток (jq НЕ используется нигде в этой функции — REQ-ST-10) ----
plugin_version() {
  local pj="$plugin_root/.claude-plugin/plugin.json"
  [ -f "$pj" ] || { echo ABSENT; return; }
  grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$pj" 2>/dev/null | head -1 \
    | sed -E 's/.*"([^"]*)"$/\1/' || echo ABSENT
}
file_component() { [ -f "$1" ] && md5sum "$1" 2>/dev/null | cut -d' ' -f1 || echo ABSENT; }
compute_fingerprint() {
  printf '%s|%s|%s|%s' \
    "$(plugin_version)" \
    "$(file_component "$proj/.claude/sdx/prod-guard.conf")" \
    "$(file_component "$proj/.claude/sdx/verify-cmd.sh")" \
    "$(file_component "$proj/.claude/sdx/sdx-version")" \
    | md5sum | cut -d' ' -f1
}
cached_fingerprint() {
  [ -f "$cache_file" ] || return 1
  grep -o '"fingerprint":"[^"]*"' "$cache_file" | head -1 | sed -E 's/.*"([^"]*)"$/\1/'
}

# write_cache <status> <preflight> <prod_guard> <stop_gate> <fingerprint> <duration_ms> <exceeded>
# Атомарная запись (mktemp + mv в той же ФС — паттерн write_stage() из sdx-stage.sh).
write_cache() {
  local status="$1" pf="$2" pg="$3" sg="$4" fp="$5" dur="$6" exceeded="$7" tmp
  mkdir -p "$cache_dir" 2>/dev/null || return 0   # best-effort: см. "Обработка ошибок"
  tmp="$(mktemp "${cache_file}.XXXXXX" 2>/dev/null)" || return 0
  printf '{"schema":1,"ts":"%s","fingerprint":"%s","selftest_status":"%s","preflight":"%s","prod_guard":"%s","stop_gate":"%s","duration_ms":%s,"budget_ms":%s,"budget_exceeded":%s}\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$fp" "$status" "$pf" "$pg" "$sg" "$dur" "$budget_ms" "$exceeded" \
    > "$tmp" 2>/dev/null && mv "$tmp" "$cache_file" || rm -f "$tmp"
}

# ---- пробы: каждая печатает pass|fail|skip в stdout, НИКОГДА не бросает наружу ----

probe_preflight() {   # REQ-ST-2: только факт exit 0 — нет канала для инъекции плохого состояния.
                       # Это доказывает «скрипт исполнился и вернул 0», а НЕ «предупреждение о jq
                       # сработало бы» — preflight.sh не принимает синтетический вход (см. DESIGN.md).
  bash "$hooks_dir/preflight.sh" >/dev/null 2>/dev/null && echo pass || echo fail
}

probe_prod_guard() {   # REQ-ST-2/5: тело JSON при exit 0 неизменном; изолированный CLAUDE_PROJECT_DIR
  local tp out1 rc1 out2 rc2
  tp="$(mktemp -d)" || { echo skip; return; }
  mkdir -p "$tp/.claude/sdx"
  printf '__sdx_selftest_deny_marker__\n' > "$tp/.claude/sdx/prod-guard.conf"
  out1="$(printf '{"tool_input":{"command":"__sdx_selftest_deny_marker__"}}' \
          | CLAUDE_PROJECT_DIR="$tp" bash "$hooks_dir/prod-guard.sh" 2>/dev/null)"; rc1=$?
  out2="$(printf '{"tool_input":{"command":"ls -la"}}' \
          | CLAUDE_PROJECT_DIR="$tp" bash "$hooks_dir/prod-guard.sh" 2>/dev/null)"; rc2=$?
  rm -rf "$tp"
  if [ "$rc1" -eq 0 ] && printf '%s' "$out1" | grep -q '"permissionDecision":"deny"' \
     && [ "$rc2" -eq 0 ] && [ -z "$out2" ]; then
    echo pass
  else
    echo fail
  fi
}

probe_stop_gate() {   # REQ-ST-3/5/6: DEBT-026-форма, изолированный git-фикстур, БЕЗ коммита
  local tp rc
  tp="$(mktemp -d)" || { echo skip; return; }
  ( cd "$tp" && git init -q && git checkout -q -b sdx/selftest ) 2>/dev/null \
    || { rm -rf "$tp"; echo skip; return; }
  mkdir -p "$tp/.claude/sessions/selftest" "$tp/.claude/sdx"
  printf '{"stage":"Execution"}' > "$tp/.claude/sessions/selftest/session_state.json"
  printf '#!/bin/bash\nexit 1\n' > "$tp/.claude/sdx/verify-cmd.sh"
  chmod 0600 "$tp/.claude/sdx/verify-cmd.sh"   # форма DEBT-026: бит снят, файл всё равно enforced
  rc=0
  CLAUDE_PROJECT_DIR="$tp" bash "$hooks_dir/stop-gate.sh" >/dev/null 2>/dev/null || rc=$?
  rm -rf "$tp"
  [ "$rc" -eq 2 ] && echo pass || echo fail
}

# ---- main ----
main() {
  local fp_now fp_cached
  fp_now="$(compute_fingerprint)"
  if [ "${SDX_SELFTEST_FORCE:-0}" != "1" ]; then
    fp_cached="$(cached_fingerprint 2>/dev/null || true)"
    [ -n "$fp_cached" ] && [ "$fp_cached" = "$fp_now" ] && return 0   # кэш-хит: ничего не делаем
  fi

  local t0 t1 dur r_pf r_pg r_sg exceeded=false overall=ok
  t0="$(now_ns)"
  r_pf="$(probe_preflight)"
  r_pg="$(probe_prod_guard)"
  r_sg="$(probe_stop_gate)"
  t1="$(now_ns)"
  dur=$(( (t1 - t0) / 1000000 ))
  [ "$dur" -gt "$budget_ms" ] && exceeded=true

  case "$r_pf $r_pg $r_sg" in
    *skip*) overall=broken ;;    # REQ-FAIL-2
    *fail*) overall=degraded ;;  # REQ-FAIL-1
  esac

  write_cache "$overall" "$r_pf" "$r_pg" "$r_sg" "$fp_now" "$dur" "$exceeded"

  # Громко, но не блокирующе — тот же канал/конвенция, что у preflight.sh (текст в stderr).
  if [ "$overall" = degraded ]; then
    echo "SDX selftest: обнаружено расхождение ответа хука enforcement-слоя с ожиданием — диагностика, SessionStart НЕ заблокирован. Подробности: /sdx:status. Подключение к реальному ограничению — задел на FEAT-010 (не реализовано)." >&2
  elif [ "$overall" = broken ]; then
    echo "SDX selftest: сам self-test не смог выполнить одну или более проб (не «слой не прошёл проверку», а «self-test не смог проверить слой») — SessionStart НЕ заблокирован. Подробности: /sdx:status." >&2
  fi
  if [ "$exceeded" = true ]; then
    echo "SDX selftest: прогон занял ${dur}мс > бюджет ${budget_ms}мс — информационно, ничего не блокирует." >&2
  fi
}

main || write_cache broken skip skip skip "$(compute_fingerprint 2>/dev/null || echo unknown)" 0 false
exit 0
