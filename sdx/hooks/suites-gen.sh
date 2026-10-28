#!/usr/bin/env bash
# SDX suites-gen (FEAT-016, REQ-MAND-18..20): generate / check tests/suites.yaml, the repository's test
# declaration read by the meta-orchestrator node (dev.py run_suites). The command comes from the SAME
# resolution stop-gate.sh uses (lib/test-cmd.sh), so what the node runs is what the floor runs.
#
#   bash suites-gen.sh [--check] [proj]      proj defaults to ${CLAUDE_PROJECT_DIR:-.}
# First word of stdout is the outcome:
#   CREATED  file absent, command known -> written (deterministic bytes, atomic)
#   OK       file present, suites.unit matches the resolution
#   DIFFERS  file present, suites.unit differs/absent -> nothing written, both sides printed
#   ABSENT   --check, file absent, command known -> nothing written
#   NOCMD    no command known (stop-gate would be a no-op) -> nothing written
# rc 0; rc 2 on an unreadable existing file, `tests` not a directory, or a usage error.
# An existing file is NEVER overwritten. budget_min = ceil(SDX_VERIFY_TIMEOUT / 60), minutes.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for l in miniyaml.sh test-cmd.sh; do
  if [ ! -f "$here/lib/$l" ]; then echo "SDX suites-gen: lib/$l плагина не найдена." >&2; exit 2; fi
done
. "$here/lib/miniyaml.sh"
. "$here/lib/test-cmd.sh"

check=0; proj=""
for a in "$@"; do
  case "$a" in
    --check) check=1 ;;
    -*) echo "SDX suites-gen: неизвестный ключ: $a" >&2; exit 2 ;;
    *) proj="$a" ;;
  esac
done
[ -n "$proj" ] || proj="${CLAUDE_PROJECT_DIR:-.}"
file="$proj/tests/suites.yaml"

test_cmd_resolve "$proj"
if [ "$TC_KIND" = none ]; then   # SG-NOCMD
  echo "NOCMD stop-gate no-op: нет .claude/sdx/verify-cmd.sh и автодетект пуст — набор unit не определён"
  exit 0
fi

# budget_min = ceil(S / 60); S must be a positive integer of at most 9 digits, else 180 (note on stderr)
S="${SDX_VERIFY_TIMEOUT:-180}"
case "$S" in
  ''|*[!0-9]*|0*[!0-9]*) S="" ;;
esac
if [ -n "$S" ] && [ "$(( 10#$S ))" -gt 0 ] && [ "${#S}" -le 9 ]; then S=$(( 10#$S )); else
  echo "SDX suites-gen: SDX_VERIFY_TIMEOUT='${SDX_VERIFY_TIMEOUT:-}' не положительное целое — принято 180 с" >&2
  S=180
fi
budget=$(( (S + 59) / 60 ))   # SG-CEIL

# yq <value>: plain scalar, or single-quoted when it has ': ', ' #' or a leading indicator character
yq() {
  case "$1" in
    ''|*': '*|*' #'*|[\!\&\*\[\]\{\}\|\>\'\"%@\`#,?:-]*|*' ') printf "'%s'" "$(printf '%s' "$1" | sed "s/'/''/g")" ;;
    *) printf '%s' "$1" ;;
  esac
}

if [ -e "$proj/tests" ] && [ ! -d "$proj/tests" ]; then
  echo "SDX suites-gen: $proj/tests не каталог" >&2; exit 2
fi

if [ -e "$file" ]; then   # SG-OVERWRITE
  my_load "$file"; lrc=$?
  if [ "$lrc" -ne 0 ]; then echo "SDX suites-gen: tests/suites.yaml не разобран: ${MY_ERR:-?}" >&2; exit 2; fi
  _my_kind suites.unit
  cur_cmd=""; cur_b=""; have_b=0
  case "$MY_K" in
    scalar) _my_scalar suites.unit; cur_cmd="$MY_S" ;;
    map)
      if _my_scalar suites.unit.cmd; then cur_cmd="$MY_S"; fi
      if _my_scalar suites.unit.budget_min; then cur_b="$MY_S"; have_b=1; fi ;;
  esac
  if [ "$MY_K" = scalar ] || [ "$MY_K" = map ]; then
    b_same=0; case "$cur_b" in ''|*[!0-9]*) [ "$cur_b" = "$budget" ] && b_same=1 ;; *) [ $((10#$cur_b)) -eq "$budget" ] && b_same=1 ;; esac   # numbers compare as numbers
    if [ "$cur_cmd" = "$TC_CMD" ] && { [ "$MY_K" = scalar ] || [ "$b_same" = 1 ]; }; then echo "OK tests/suites.yaml: unit.cmd совпадает с резолвом"; exit 0; fi
  fi
  _my_q "$cur_cmd"; a="$MY_QV"; _my_q "$TC_CMD"; c="$MY_QV"
  case "$cur_b" in ''|*[!0-9]*) _my_q "$cur_b"; b="$MY_QV" ;; *) b="$cur_b" ;; esac   # numeric budget printed bare, like the expected one   # SG-NUM
  echo "DIFFERS tests/suites.yaml не изменён: unit.cmd=$a vs $c; budget_min=$b vs $budget (файл не перезаписывается — правьте вручную)"
  exit 0
fi

if [ "$check" = 1 ]; then
  echo "ABSENT tests/suites.yaml нет; создаст suites-gen.sh без --check (unit.cmd=$TC_CMD, budget_min=$budget)"
  exit 0
fi

mkdir -p "$proj/tests" || exit 2
tmp="$(mktemp "$proj/tests/.suites.XXXXXX")" || exit 2
{
  echo '# tests/suites.yaml — декларация тестов репозитория для узла МО (sim-kit 0.9, dev.py run_suites).'
  echo '# Создан /sdx:init или /sdx:reconcile (sdx/hooks/suites-gen.sh) из той же команды, что исполняет stop-gate.'
  echo '# Имена наборов — контракт policy/tests.yaml узла: unit | module | regression.'
  echo '# cmd — строка оболочки в корне рабочей копии узла; budget_min — минуты; selector зарезервирован (пусто — набор целиком).'
  echo '# Файл НЕ перезаписывается генератором; правьте вручную.'
  echo 'suites:'
  echo '  unit:'
  echo "    cmd: $(yq "$TC_CMD")"
  echo "    budget_min: $budget"
  echo '    selector: ""'
  echo '  # module:'
  echo '  #   cmd: <команда модульных/интеграционных тестов>'
  echo '  #   budget_min: 10'
  echo '  #   selector: ""'
  echo '  # regression:'
  echo '  #   cmd: <команда полной регрессии приложения>'
  echo '  #   budget_min: 60'
  echo '  #   selector: ""'
} > "$tmp" && chmod 644 "$tmp" && mv "$tmp" "$file" || { rm -f "$tmp"; exit 2; }
echo "CREATED tests/suites.yaml (unit.cmd=$TC_CMD, budget_min=$budget); файл версионируется (tracked), .gitignore не правится"
exit 0
