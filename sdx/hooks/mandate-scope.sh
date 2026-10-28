#!/usr/bin/env bash
# SDX mandate-scope (FEAT-016, REQ-MAND-12..15, 7): the deterministic `diff ⊆ mandate area` check of
# /sdx:verify. The reviewer agent has no Bash, so the orchestrator runs this script and the finding lands in
# verification_report.md as a block between SDX-MANDATE-SCOPE markers; the existing gate regex ^### \[FAIL\]
# then sees it without any change to sdx-stage.sh. Outside mandate mode (both .mesh/endpoint.yaml and
# .mesh/mandate.yaml) it prints and writes NOTHING (REQ-MAND-15).
#
#   git -c core.quotepath=off diff --name-only "$def"...sdx/<id> -- . ':!.claude/sessions/**' \
#     | bash mandate-scope.sh [--proj DIR] --into <verification_report.md> [--planned <path>]...
#
# stdin: changed paths, one per line. --planned: Closeout transfers not yet in the diff (К-3).
# stdout: one word, PASS | FAIL <K> | WARN <L>. rc: 0 no FAIL | 1 at least one FAIL | 2 usage/IO error.
# The semantics follow the node audit (glob_any + docs_paths), NOT the hook's _in_scope (see protocol "Мандат").
set -uo pipefail

case "${BASH_SOURCE[0]}" in */*) here="${BASH_SOURCE[0]%/*}" ;; *) here="." ;; esac
if [ ! -f "$here/lib/mandate.sh" ]; then
  echo "SDX mandate-scope: lib/mandate.sh плагина не найдена." >&2
  exit 2
fi
. "$here/lib/mandate.sh"

usage() {
  echo "SDX mandate-scope: использование: mandate-scope.sh [--proj DIR] --into <report.md> [--planned <path>]... (пути — со стандартного ввода)" >&2
  exit 2
}

proj="${CLAUDE_PROJECT_DIR:-.}"; into=""; planned=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --proj) [ "$#" -ge 2 ] || usage; proj="$2"; shift 2 ;;
    --into) [ "$#" -ge 2 ] || usage; into="$2"; shift 2 ;;
    --planned) [ "$#" -ge 2 ] || usage; planned="$planned${planned:+$'\n'}$2"; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$into" ] || usage

[ "$(mandate_mode "$proj")" = on ] || exit 0

if [ -e "$into" ]; then
  [ -r "$into" ] && [ -w "$into" ] || { echo "SDX mandate-scope: отчёт '$into' нечитаем или недоступен для записи." >&2; exit 2; }
else
  case "$into" in */*) rdir="${into%/*}" ;; *) rdir="." ;; esac
  [ -d "$rdir" ] || { echo "SDX mandate-scope: каталог отчёта '$rdir' не существует." >&2; exit 2; }
fi

# _safe <str> <max> -> SAFE: reduce an untrusted value to [A-Za-z0-9._-] (anything else -> '?'), at most <max> chars
_safe() {
  local s="${1:0:$2}" i c out=""
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in [A-Za-z0-9._-]) out="$out$c" ;; *) out="$out?" ;; esac
  done
  SAFE="$out"
}
# _pshow <path> -> PSHOW: a changed path made safe for a Markdown code span (control chars out, backtick -> apostrophe)
_pshow() { local s="${1//[[:cntrl:]]/}"; _my_rep "$s" '`' "'"; PSHOW="${MY_REP:0:200}"; }

files=""; nfiles=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  files="$files$f"$'\n'; nfiles=$((nfiles + 1))
done
nplanned=0
if [ -n "$planned" ]; then
  while IFS= read -r f; do [ -n "$f" ] && nplanned=$((nplanned + 1)); done <<< "$planned"
fi

BEGIN='<!-- SDX-MANDATE-SCOPE:BEGIN -->'
END='<!-- SDX-MANDATE-SCOPE:END -->'
block=""
nfail=0; nwarn=0
ex=""; dg=""

if ! mandate_load "$proj"; then
  _my_q "$MANDATE_ERR"
  block="$BEGIN"$'\n'"## Область мандата (детерминированная проверка \`mandate-scope.sh\`; добавлена оркестратором, сводка ревьюера выше не пересчитывается)"$'\n'
  block="$block### [FAIL] Мандат МО не разобран: $MY_QV"$'\n'"- Суть: граница мандата неизвестна — проверка области не может быть пройдена (fail-closed); исправляет мандат узел МО."$'\n'"$END"
  nfail=1
else
  _my_scalar mandate.executor; _safe "$MY_S" 40; ex="$SAFE"
  _my_scalar mandate.digest; _safe "$MY_S" 40; dg="$SAFE"
  restricted=0
  [ -n "$MANDATE_PATHS" ] && restricted=1   # MAND-EMPTY-PATHS: empty scope.paths means "no restriction"
  findings=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    _pshow "$f"; p="$PSHOW"
    if [ "$restricted" = 1 ] && ! mandate_in_union "$f"; then   # MAND-OUTSIDE
      findings="$findings### [FAIL] [Область] Файл вне области мандата: \`$p\`"$'\n'"- Где: \`$p\` — не входит в scope.paths ∪ shared_paths ∪ docs_paths"$'\n'"- Суть: правка за границей мандата; узел отклонит пакет по \`scope\`."$'\n'
      nfail=$((nfail + 1))
    fi
    if mandate_match_list "$f" "$MANDATE_SHARED"; then   # MAND-SHARED
      findings="$findings### [WARN] [Область] Общий путь (shared_paths): \`$p\`"$'\n'"- Суть: правка общего файла; слияние такого пакета — решение человека; в FEAT-017 станет touches_shared: true."$'\n'
      nwarn=$((nwarn + 1))
    fi
  done <<< "$files"
  while IFS= read -r f; do   # MAND-PLANNED
    [ -n "$f" ] || continue
    if [ "$restricted" = 1 ] && ! mandate_in_union "$f"; then
      _pshow "$f"; p="$PSHOW"
      findings="$findings### [FAIL] [Область] Перенос Closeout вне docs_paths: \`$p\`"$'\n'"- Суть: путь не покрыт docs_paths мандата; узел должен перечислить реестр решений явно (вопрос §5.3 записки)."$'\n'
      nfail=$((nfail + 1))
    fi
  done <<< "$planned"
  if [ "$nfail" -gt 0 ]; then verdict="FAIL ($nfail)"; elif [ "$nwarn" -gt 0 ]; then verdict="WARN ($nwarn)"; else verdict="PASS"; fi
  block="$BEGIN"$'\n'"## Область мандата (детерминированная проверка \`mandate-scope.sh\`; добавлена оркестратором, сводка ревьюера выше не пересчитывается)"$'\n'
  block="$block- Мандат: executor=$ex, digest=$dg; файлов в диффе: $nfiles; запланированных переносов Closeout: $nplanned"$'\n'
  block="$block- Итог по области: $verdict"$'\n'"$findings"
  if mandate_expired; then
    _my_scalar mandate.valid_until
    _safe "$MY_S" 20
    block="$block> Предупреждение: мандат истёк (valid_until=$SAFE) — решение у узла; гейт не блокируется"$'\n'
  fi
  block="$block$END"
fi

# ---- write the block: replace the previous one in place, else append (the rest of the report is untouched)
have_block=0; nonl=0
if [ -s "$into" ]; then
  nb=0; ne=0; l=""
  while IFS= read -r l; do
    case "$l" in *"$BEGIN"*) nb=$((nb + 1)) ;; *"$END"*) ne=$((ne + 1)) ;; esac
  done < "$into"
  if [ -n "$l" ]; then   # the last line had no newline (it stays in $l when read fails)
    nonl=1
    case "$l" in *"$BEGIN"*) nb=$((nb + 1)) ;; *"$END"*) ne=$((ne + 1)) ;; esac
  fi
  if [ "$nb" = 1 ] && [ "$ne" = 1 ]; then have_block=1
  elif [ "$nb" != 0 ] || [ "$ne" != 0 ]; then
    echo "SDX mandate-scope: в отчёте '$into' непарные или повторные маркеры SDX-MANDATE-SCOPE — файл не изменён." >&2
    exit 2
  fi
fi
if [ "$have_block" = 1 ]; then   # MAND-REPLACE
  tmp="$(mktemp "$into.XXXXXX")" || { echo "SDX mandate-scope: не удалось создать временный файл рядом с '$into'." >&2; exit 2; }
  BLK="$block" awk -v b="$BEGIN" -v e="$END" '
    index($0, b) && !done { print ENVIRON["BLK"]; skip = 1; done = 1; next }
    skip { if (index($0, e)) skip = 0; next }
    { print }' "$into" > "$tmp"
  cat "$tmp" > "$into" || { rm -f "$tmp"; echo "SDX mandate-scope: не удалось записать '$into'." >&2; exit 2; }
  rm -f "$tmp"
else
  {
    if [ -s "$into" ]; then
      if [ "$nonl" = 1 ]; then printf '\n'; fi
      printf '\n'
    fi
    printf '%s\n' "$block"
  } >> "$into" || { echo "SDX mandate-scope: не удалось записать '$into'." >&2; exit 2; }
fi

if [ "$nfail" -gt 0 ]; then echo "FAIL $nfail"; exit 1; fi
if [ "$nwarn" -gt 0 ]; then echo "WARN $nwarn"; else echo "PASS"; fi
exit 0
