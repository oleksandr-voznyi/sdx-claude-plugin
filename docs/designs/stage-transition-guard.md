# Технический дизайн: детерминированный владелец поля `stage` (DEBT-001 + DEBT-011)

## Архитектурный обзор

Решение вводит единственного детерминированного писателя поля `stage` — CLI-скрипт `sdx/hooks/sdx-stage.sh` с четырьмя подкомандами — и техническую границу в виде deny-хука `stage-write-guard.sh`, блокирующего прямую правку поля в обход механизма.

Ключевое свойство: **`sdx-stage.sh` мутирует файл через Bash (printf/jq/mv), а не через `Write`/`Edit`/`MultiEdit`.** Хук `stage-write-guard.sh` матчится только на эти три инструмента — легитимный путь физически вне его зоны видимости.

Две шесть прозаических точек записи сводятся к четырём вызовам:

| Команда | Подкоманда `sdx-stage.sh` |
|---|---|
| `/sdx:start`, `/sdx:import` | `init` |
| `/sdx:next`, `/sdx:archive` (вход в Closeout) | `next` |
| `/sdx:backtrack --to <stage>` | `backtrack` |
| `/sdx:retrack <track>` | `retrack` |

## Компоненты

- **`sdx/hooks/sdx-stage.sh`** — единственный писатель `stage`, 4 подкоманды (`init|next|backtrack|retrack`).
- **`sdx/hooks/stage-write-guard.sh`** — PreToolUse-хук, deny прямой правки `stage`.
- **`sdx/hooks/lib/resolve-session.sh`** — общая библиотека резолюции сессии (branch → sid).
- **`hooks/hooks.json`** — новая запись `stage-write-guard.sh` в существующем matcher-е `Write|Edit|MultiEdit`.
- **Команды** `/sdx:start`, `/sdx:import`, `/sdx:next`, `/sdx:backtrack`, `/sdx:retrack`, `/sdx:archive` — прозаические писатели `stage` заменяются на вызов `sdx-stage.sh`.
- **`sdx/protocol.md`** — новый раздел о механизме перехода, ссылка на матрицу как источник истины.
- **`docs/DECISIONS.md`** — новый ADR-016.

## Интерфейс `sdx-stage.sh`

Вызывается через Bash, уважает `${CLAUDE_PROJECT_DIR:-.}`:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/sdx/hooks/sdx-stage.sh" <subcommand> <args...>
```

### Подкоманды

**`init` — первичная установка (`/sdx:start`/`/sdx:import`)**
```
sdx-stage.sh init <sid> <type> <track> <stage> <gate_mode> <git_branch>
```
- Требует отсутствия `session_state.json`; повторный вызов → `exit 2`.
- Валидирует, что `<stage>` — первый активный этап `<track>`.
- Создаёт файл целиком и атомарно пишет в `session.log` строку `[START]`.

**`next` — forward-переход (`/sdx:next`, `/sdx:archive` вход в Closeout)**
```
sdx-stage.sh next <sid>
```
- Без явной цели; скрипт сам вычисляет следующий активный этап.
- Проверяет гейт-условие **уходящего** этапа.
- `Closeout` в матрице — обычная последняя строка; отдельного кода не требуется.

**`backtrack` — backward-переход (`/sdx:backtrack --to <stage>`)**
```
sdx-stage.sh backtrack <sid> <target-stage>
```
- Явная цель обязательна.
- Без проверки гейт-артефактов уходящего этапа.
- Помечает outdated артефакты этапов после целевого.

**`retrack` — пересчёт под новый трек (`/sdx:retrack <track>`)**
```
sdx-stage.sh retrack <sid> <target-stage>
```
- Вызывается **после** того, как `/sdx:retrack.md` уже обновил поле `track`.
- Проверяет: (1) цель активна в новом треке; (2) гейт-артефакты всех предшествующих ей этапов существуют.

### Коды возврата

| Код | Значение |
|---|---|
| `0` | Успех, включая безопасный no-op |
| `1` | Переход отклонён (гейт, невалидная цель) |
| `2` | Ошибка окружения/вызова (нет `jq`, нет `session_state.json`, плохие аргументы) |

## Матрица «трек → этапы → гейт-артефакты»

Источник истины находится внутри `sdx-stage.sh` как heredoc с `|`-разделителем:

```bash
SDX_STAGE_MATRIX='
full|Discovery|context_report.md|no
full|Business Spec|SPEC.md|no
full|Technical Design|DESIGN.md|no
full|Task Planning|PLAN.md|no
full|Execution|-|no
full|Documentation|-|no
full|Verification|verification_report.md|yes
full|Deployment|-|no
full|Closeout|-|no
standard|Discovery|-|no
standard|Change|change_note.md|no
standard|Execution|-|no
standard|Verification|verification_report.md|yes
standard|Closeout|-|no
patch|Execution|change_note.md|no
patch|Verification|verification_report.md|yes
patch|Closeout|-|no
'
```

Формат строки: `track|stage|artifact|fail_marker`
- `artifact` — относительный путь в каталоге сессии; "-" = гейт не проверяем объективно.
- `fail_marker` — "yes" = требуется отсутствие `^### \[FAIL\]` в артефакте; "no" = только существование+непустота.
- Порядок строк внутри трека = порядок активных этапов.

`sdx/protocol.md` хранит человекочитаемую проекцию этой же таблицы; sanity-тест в `test-sdx-stage.sh` сверяет упорядоченные цепочки этапов.

## Механика записи `stage` (атомарность)

```bash
write_stage() {   # $1 = новое значение stage
  local new="$1" tmp
  tmp="$(mktemp "${state}.XXXXXX")" || {
    echo "SDX sdx-stage: не удалось создать временный файл..." >&2; exit 2; }
  if ! jq --arg s "$new" '.stage = $s' "$state" > "$tmp"; then
    rm -f "$tmp"
    echo "SDX sdx-stage: jq не смог обновить $state..." >&2
    exit 2
  fi
  mv "$tmp" "$state"    # mktemp в той же директории -> атомарный mv на одном fs
}
```

`mktemp` создаёт временный файл **в том же каталоге**, что целевой, иначе `mv` между разными файловыми системами не гарантирует атомарность. Частичная запись невозможна.

**Без `jq` — отказ (fail-closed).** Проверка выполняется в начале скрипта, до разбора подкоманды. Обоснование: скрипт — единственный писатель состояния; отказать при невозможности безопасного парсинга — единственный способ гарантировать целостность.

## Deny-хук `stage-write-guard.sh`

### Проводка и резолюция

Третья запись в существующем matcher-е `PreToolUse` / `Write|Edit|MultiEdit`. Использует общую `lib/resolve-session.sh`:

```bash
. "$here/lib/resolve-session.sh"
sid="$(resolve_sid "$proj")"
[ -z "$sid" ] && exit 0   # не SDX-ветка -> no-op
state="$proj/.claude/sessions/${sid}/session_state.json"
```

### Защита от создания и деградация

```bash
[ -f "$state" ] || exit 0   # файла ещё нет -> это создание, не правка
# Проверка jq после убеждения, что операция касается $state
if ! command -v jq >/dev/null 2>&1; then
  echo "SDX stage-write-guard: jq недоступен..." >&2
  exit 0   # fail-open (REQ-DENY-4)
fi
```

### Единый принцип обнаружения: apply-and-compare

Все три инструмента используют один и тот же принцип: получить полное содержимое файла ДО и ПОСЛЕ операции, распарсить `.stage` из обоих через `jq` и сравнить **значения**:

| Инструмент | Источник содержимого «после» |
|---|---|
| `Write` | `.tool_input.content` дано целиком |
| `Edit` | Симулируется заменой `old_string → new_string` в реальном содержимом с диска |
| `MultiEdit` | Симулируется применением массива `edits[]` последовательно |

Ложноположительный случай (реформатирование пробелов без изменения значения) не возникает: сравниваются распарсенные значения, не текстовые паттерны.

### Нормализация путей

```bash
normalize_path() {
  # Схлопывает "/./" и повторные "/", но НЕ резолвит ".."
}
target="$(normalize_path "$target")"
state="$(normalize_path "$state")"
```

Сегмент `..` не нормализуется — граница, принятая осознанно (для полной нормализации нужно угадывать cwd хука).

### Реальные границы

- **Bash-обход (DEBT-003).** `session_state.json` редактируемый через `sed -i`/`jq` in-place — хук матчится только на `Write`/`Edit`/`MultiEdit`. Это единственно практически достижимый путь внести несогласованное состояние.
- **Сегмент `..` в пути.** Контракт `Write`/`Edit`/`MultiEdit` требует абсолютных путей, но технически возможно.

## Backward-переход: маркировка outdated

```bash
mark_outdated() {   # $1 = path, $2 = target stage
  local f="$1" tgt="$2"
  [ -f "$f" ] || return 0
  head -c 200 "$f" | grep -q '<!-- SDX-OUTDATED' && return 0   # уже помечен
  local tmp
  tmp="$(mktemp "${f}.XXXXXX")" || return 1
  { printf '<!-- SDX-OUTDATED: устарело откатом /sdx:backtrack --to "%s" (%s). Актуализируйте перед продолжением; история версии — `git log -p -- %s`. -->\n\n' \
      "$tgt" "$(date '+%Y-%m-%d %H:%M:%S')" "$f"
    cat "$f"; } > "$tmp" && mv "$tmp" "$f"
  echo "OUTDATED: $f"
}
```

HTML-комментарий-баннер вставляется **первой строкой** файла. Файл не переименовывается и не перемещается. Маркировка идемпотентна (повторный `backtrack` не дублирует баннер).

**Скоуп маркировки:** артефакты **строго после** целевого этапа в порядке трека, **без верхней границы** — до конца активных этапов трека. Артефакт самого целевого этапа не метится. Помеченный артефакт продолжает засчитываться как доказательство для `next` и `retrack` (баннер — сигнал, а не механическое ограничение).

## Forward-skip guard в `retrack`

`retrack` достижима на этап, только если гейт-артефакты **всех** предшествующих ему этапов нового трека фактически существуют на диске — по тем же критериям, что `next`:

```bash
for each stage s in new_track with row_order < target_row_order:
  if NOT stage_artifact_ok(s):
    deny with message naming missing stage and artifact
```

Проверка не опирается на текущий `stage` и не сравнивает его ни с чем — только на то, что реально есть на диске. Это предотвращает храповик: самодекларируемая позиция `stage` не может быть единственным доказательством прогресса.

Собственный первый активный этап нового трека всегда достижим (пустая цепочка предшественников).

**Эквивалентность `Change`.** Этап `Change` (patch/standard) засчитывается подтверждённым, если существует **либо** непустой `change_note.md`, **либо** одновременно непустые `SPEC.md` **и** `DESIGN.md`. Это не ослабление, а прямое следствие: при эскалации `retrack.md` безусловно промоутит `change_note.md` в оба эти файла перед вызовом скрипта; сессия `full`, дошедшая до `Technical Design`, сделала строго больше, чем требовал бы `Change`.

## Общая библиотека `lib/resolve-session.sh`

```bash
#!/usr/bin/env bash
# Sourceable, no side effects except function definition
resolve_sid() {
  local proj="$1" branch
  branch="$(git -C "$proj" branch --show-current 2>/dev/null || true)"
  case "$branch" in
    sdx/*) printf '%s' "${branch#sdx/}" ;;
    *)     printf '' ;;
  esac
}
```

Используется `stage-write-guard.sh` и может быть использована `stage-gate.sh`/`stop-gate.sh` (рекомендованный рефакторинг той же сессии, не блокирующий).
