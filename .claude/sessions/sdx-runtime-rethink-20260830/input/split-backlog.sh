#!/usr/bin/env bash
# Разбирает backlog-entries.md на отдельные файлы записей.
#
#   bash split-backlog.sh backlog-entries.md docs/backlog
#
# Идемпотентен: существующие файлы НЕ перезаписываются (сообщает и пропускает) —
# запись бэклога могла быть уже заведена и отредактирована вручную.
set -euo pipefail

src="${1:?укажите путь к backlog-entries.md}"
dst="${2:?укажите каталог назначения, например docs/backlog}"

[ -f "$src" ] || { echo "нет файла: $src" >&2; exit 2; }
mkdir -p "$dst"

created=0 skipped=0
current=""

while IFS= read -r line; do
  case "$line" in
    '### FILE: '*)
      current="${line#'### FILE: '}"
      current="${current// /}"
      out="$dst/$current"
      if [ -e "$out" ]; then
        echo "пропуск (уже есть): $current"
        current=""
        skipped=$((skipped + 1))
      else
        : > "$out"
        echo "создан: $current"
        created=$((created + 1))
      fi
      infence=0
      continue
      ;;
  esac

  [ -n "$current" ] || continue

  # содержимое записи лежит внутри ```markdown ... ``` — сами ограждения не пишем
  if [ "$line" = '```markdown' ]; then infence=1; continue; fi
  if [ "$line" = '```' ] && [ "${infence:-0}" = 1 ]; then
    infence=0
    current=""
    continue
  fi
  [ "${infence:-0}" = 1 ] && printf '%s\n' "$line" >> "$dst/$current"
done < "$src"

echo "---"
echo "создано: $created, пропущено: $skipped"
echo "Индекс docs/backlog/README.md обновите вручную или командой /sdx:backlog."
