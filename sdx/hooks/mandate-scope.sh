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

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
elif [ ! -d "$(dirname "$into")" ]; then
  echo "SDX mandate-scope: каталог отчёта '$(dirname "$into")' не существует." >&2
  exit 2
fi

# safe <str> <max>: reduce an untrusted value to [A-Za-z0-9._-] (anything else -> '?') for the report header
safe() { printf '%s' "$1" | LC_ALL=C sed 's/[^A-Za-z0-9._-]/?/g' | cut -c1-"$2"; }
# pshow <path>: a changed path made safe for a Markdown code span (control chars out, backtick -> apostrophe)
pshow() { local s="${1//[[:cntrl:]]/}"; _my_rep "$s" '`' "'"; printf '%s' "${MY_REP:0:200}"; }

files=""; nfiles=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  files="$files$f"$'\n'; nfiles=$((nfiles + 1))
done
nplanned=0
if [ -n "$planned" ]; then nplanned="$(printf '%s\n' "$planned" | grep -c .)"; fi

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
  _my_scalar mandate.executor; ex="$(safe "$MY_S" 40)"
  _my_scalar mandate.digest; dg="$(safe "$MY_S" 40)"
  restricted=0
  [ -n "$MANDATE_PATHS" ] && restricted=1   # MAND-EMPTY-PATHS: empty scope.paths means "no restriction"
  findings=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    p="$(pshow "$f")"
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
      p="$(pshow "$f")"
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
    block="$block> Предупреждение: мандат истёк (valid_until=$(safe "$MY_S" 20)) — решение у узла; гейт не блокируется"$'\n'
  fi
  block="$block$END"
fi

# ---- write the block: replace the previous one in place, else append (the rest of the report is untouched)
tmp="$(mktemp "$into.XXXXXX" 2>/dev/null)" || { echo "SDX mandate-scope: не удалось создать временный файл рядом с '$into'." >&2; exit 2; }
trap 'rm -f "$tmp" "$tmp.blk"' EXIT
printf '%s\n' "$block" > "$tmp.blk"
have_block=0
if [ -f "$into" ]; then
  nb="$(grep -cF "$BEGIN" "$into")"; ne="$(grep -cF "$END" "$into")"
  if [ "$nb" = 1 ] && [ "$ne" = 1 ]; then have_block=1
  elif [ "$nb" != 0 ] || [ "$ne" != 0 ]; then
    echo "SDX mandate-scope: в отчёте '$into' непарные или повторные маркеры SDX-MANDATE-SCOPE — файл не изменён." >&2
    exit 2
  fi
fi
if [ "$have_block" = 1 ]; then   # MAND-REPLACE
  awk -v bf="$tmp.blk" -v b="$BEGIN" -v e="$END" '
    BEGIN { while ((getline l < bf) > 0) blk = blk l "\n" }
    index($0, b) && !done { printf "%s", blk; skip = 1; done = 1; next }
    skip { if (index($0, e)) skip = 0; next }
    { print }' "$into" > "$tmp"
else
  if [ -f "$into" ]; then
    cat "$into" > "$tmp"
    if [ -n "$(tail -c 1 "$into")" ]; then printf '\n' >> "$tmp"; fi   # the report did not end with a newline
    printf '\n' >> "$tmp"
  fi
  cat "$tmp.blk" >> "$tmp"
fi
cat "$tmp" > "$into" || { echo "SDX mandate-scope: не удалось записать '$into'." >&2; exit 2; }

if [ "$nfail" -gt 0 ]; then echo "FAIL $nfail"; exit 1; fi
if [ "$nwarn" -gt 0 ]; then echo "WARN $nwarn"; else echo "PASS"; fi
exit 0
