# DESIGN (архив сессии): feat-016-mo-mandate-20261028

> Полный DESIGN сессии с датированными пометками кругов верификации; сжатый перенос — `docs/designs/mo-interop.md` (раздел «Дельты FEAT-016»).

# Technical Design: FEAT-016 п.2–9 — мандат МО и декларации (плагин 2.4.0 «мандат и декларации»)

status: draft (Technical Design, сессия `feat-016-mo-mandate-20261028`; вход — утверждённый `SPEC.md` REQ-MAND-1…33, 11a, `context_report.md`, `decisions_log.md`)

Условные обозначения. `MI` = `sdx/mo/MO-INTEROP.md` (sim-kit 0.9.1), `DH` = `sdx/mo/devagent_hook.py`, `DEV` = `sim-kit/core/dev.py` (внешний эталон, читался как данные). `ДЛ-N` — `decisions_log.md`. `К-N` — пункты раздела «Коллизии и вопросы». Якоря `# MAND-*` в коде — метки для мутационных прогонов (как `# MO-*`).

Что проверено прогоном до написания (скретч, не в репозитории): (а) awk-разборщик подмножества YAML (компонент `miniyaml.sh`) совпал с `yaml.safe_load` на 27 из 30 фикстур по результату «стадии / отказ», расхождения — только в сторону отказа (дубликат ключа, flow-словарь, якорь — К-8); (б) bash-реализация `glob_any` совпала с эталонной формулой `DEV:67–68` (`fnmatch` ∨ `fnmatch(p.rstrip("/")+"/*")` ∨ `startswith(p.rstrip("*").rstrip("/")+"/")`) на 27 случаях, включая `[^x]`, обратную косую, пустой шаблон, `Src/` против `src/**`.

## Архитектурный обзор

Поставка — детерминированный слой вокруг одного нового входа, `.mesh/mandate.yaml`, который в 2.3.x не читался. Все ветки включаются **только в режиме мандата** (оба файла `endpoint.yaml` и `mandate.yaml`), кроме двух названных SPEC исключений (`tests/suites.yaml`, новое содержание `/sdx:status` и сниппета).

Принятые архитектурные решения (с обоснованием; альтернативы — в разделе «Альтернативы»):

- **D-1. Один парсер — на bash, без PyYAML.** Новая библиотека `sdx/hooks/lib/miniyaml.sh` (разборщик подмножества YAML на awk, нормализованный поток записей) и `sdx/hooks/lib/mandate.sh` (семантика мандата: режим, стадии, область, срок, показ). Её вызывают `sdx-stage.sh` (где python запрещён, REQ-MAND-33), `mo-session.sh` (ниже проверки зависимостей PyYAML гарантирован, но второй парсер удвоил бы расхождения), `mandate-info.sh`, `mandate-scope.sh`, `suites-gen.sh` (чтение существующего файла). PyYAML — только **оракул в тестах** (`yaml.safe_load` на тех же фикстурах; INFO-skip без PyYAML). Разбираемое подмножество — то, что порождает `yaml.safe_dump(sort_keys=False)` узла (`DEV:531`) и ручной flow-вид; всё прочее — отказ «вне подмножества» (fail-closed, К-8).
- **D-2. `mo-hook.sh` библиотек не подключает.** Обёртка остаётся автономной (bash 3.2 builtins + cat/jq/python3, тест портируемости `[12]` запрещает `git `/`resolve-session`; мутанты `test-mo-hook.sh` [13] копируют **один файл** в temp — подключение lib их сломало бы). Более строгий режим берётся тем же `mode_re` на втором файле; охрана — расширением `is_mailbox_file`.
- **D-3. Мандат перечитывается на каждом вызове, снимка нет** (дефолты В12/В13). Сигнатура `sdx-stage.sh init` (7 позиционных) и схема `session_state.json` не меняются. Следствие: переиздание мандата в середине сессии меняет гейт со следующего `/sdx:next` (названо в «Границах»).
- **D-4. Две новые read-only подкоманды `sdx-stage.sh`**: `start-stage` (стартовый этап с учётом трёх источников — единственный детерминированный ответ на «первый активный этап», REQ-MAND-11) и `active-set` (источники сужения для `/sdx:status`). `init` и `next` сохраняют формат вызова и вывода.
- **D-5. Область на `/sdx:verify` — скрипт `sdx/hooks/mandate-scope.sh`**, который сам дописывает блок в `verification_report.md` между маркерами (идемпотентно). Находка не зависит от ревьюера (у него нет `Bash`); гейт `gate_ok` (`^### \[FAIL\]`) её видит без правок `sdx-stage.sh`.
- **D-6. Переносы Closeout проверяются «по плану»** (`--planned`), потому что на момент Verification их коммитов в диффе ещё нет (К-3).
- **D-7. `tests/suites.yaml` — скрипт `sdx/hooks/suites-gen.sh` + `lib/test-cmd.sh`**; `stop-gate.sh` **не трогается** (его копируют `selftest`/`test-selftest` вместе с `lib/resolve-session.sh`; правка импорта ломает изоляцию self-test). Единственность правды обеспечивает **тест-близнец**: на фикстурах каждого класса команды сравнивается то, что запустил настоящий `stop-gate.sh`, с тем, что вернул резолвер.
- **D-8. Мост Closeout — `mandate-info.sh closeout-mode|closeout-check`** (детерминированная часть) + проза `archive.md`/протокола. `archive-verify.sh` не меняется и при мандате не вызывается. *(Круг 2 верификации, 2026-10-29: мост действует для любого определённого `delivery`, включая `artifact.offer` -> `bridge:offer`.)*
- **D-9. Показ мандата — одна функция `mandate_report`** (`lib/mandate.sh`); её тексты видят и SessionStart (`mo-session.sh`), и `/sdx:start` (`mandate-info.sh show`) — расхождений формулировок быть не может.

### Новые и изменяемые файлы (сводка)

| Файл | Тип | Назначение |
|---|---|---|
| `sdx/hooks/lib/miniyaml.sh` | ADDED | разборщик подмножества YAML + аксессоры + JSON-квотирование для показа |
| `sdx/hooks/lib/mandate.sh` | ADDED | режим, загрузка/валидация, стадии, `glob_any`, срок, `mandate_report` |
| `sdx/hooks/lib/test-cmd.sh` | ADDED | резолвер тест-команды (зеркало блока `stop-gate.sh:49–64`) |
| `sdx/hooks/mandate-info.sh` | ADDED | CLI: `mode`, `show`, `status`, `closeout-mode`, `closeout-check` |
| `sdx/hooks/mandate-scope.sh` | ADDED | проверка `diff ⊆ область`, блок в `verification_report.md` |
| `sdx/hooks/suites-gen.sh` | ADDED | генерация/проверка `tests/suites.yaml` |
| `sdx/hooks/snippet-check.sh` | ADDED | сверка SDX-блока `CLAUDE.md` с шаблоном (для `reconcile`) |
| `sdx/hooks/sdx-stage.sh` | MODIFIED | третий источник сужения, `start-stage`, `active-set` |
| `sdx/hooks/mo-hook.sh` | MODIFIED | более строгий `on_write`, охрана `mandate.yaml` |
| `sdx/hooks/mo-session.sh` | MODIFIED | строка-предупреждение «мандат без endpoint», показ мандата |
| `commands/{start,next,verify,archive,status,init,reconcile,import}.md` | MODIFIED | проза и вызовы скриптов |
| `agents/devops.md`, `sdx/templates/claude-md-snippet.md`, `sdx/protocol.md` | MODIFIED | проза |
| `docs/DECISIONS.md`, `docs/specs|designs/mo-interop.md`, `docs/backlog/FEAT-016-…md`, `README.md`, `README.en.md`, `CLAUDE.md` | MODIFIED | документы |
| `tests/suites.yaml` | ADDED | dogfood-декларация репозитория |
| `.claude-plugin/plugin.json` | MODIFIED | `version` 2.3.1 → 2.4.0 |
| `.claude/sdx/verify-cmd.sh` | MODIFIED | актуализация комментария о длительности (REQ-MAND-32) |
| `sdx/hooks/test-{mandate-lib,mandate-scope,suites-gen,snippet-check}.sh` | ADDED | новые сьюты |
| `sdx/hooks/test-{mo-hook,mo-session,sdx-stage,mo-prose}.sh` | MODIFIED | только добавлением |

`hooks/hooks.json` **не меняется** (новых хуков нет; `test-hook-wiring.sh` проверяет ровно существующие записи). `sdx/mo/*` не меняется (PROC-028, `test-mo-inventory.sh`). Инфраструктуры для DevOps-агента (Docker/CI/деплой) нет.

## Компоненты и Интеграции

### [ADDED] `sdx/hooks/lib/miniyaml.sh` — разбор подмножества YAML (REQ-MAND-10, 33)

Источник (`source`), не исполняемый. bash 3.2, awk POSIX (`LC_ALL=C`). Без `declare -A`, `mapfile`, `timeout`, `%N` (BUG-010; тест портируемости нового сьюта греп-проверяет lib-файлы тем же `FORBID`).

API:

```
my_parse <file>        # stdout: нормализованные записи (формат ниже); rc 0; последняя запись "X<US>причина" при ошибке
my_load  <file>        # MY_NORM=$(my_parse); MY_ERR=<причина или пусто>; rc 0 ok | 1 ошибка разбора | 2 файл нечитаем
my_scalar <path>       # последнее значение S-записи path (пусто, если нет)
my_list   <path>       # значения L-записей path, по одному в строке
my_exists <path>       # rc 0, если есть запись path или потомок path.*
my_kind   <path>       # stdout: scalar | list | map | null | absent
my_q <str> [max=160]   # JSON-подобное квотирование для ПОКАЗА: вырезает C0-управляющие (кроме пробела) и DEL, экранирует \ и ", усечение до max символов с "…"
```

Формат записей — одна строка, поля через `US=$'\037'` (значения не содержат переводов строк по построению):

| Запись | Смысл |
|---|---|
| `O<US>path` | ключ с пустым значением, дальше потомки (отображение/список) либо null, если потомков нет |
| `S<US>path<US>value` | скаляр (после снятия кавычек; null-слова `~`, `null`, пусто **без** кавычек — не S, а `Z`) |
| `Z<US>path` | явный null |
| `E<US>path` | пустой список/словарь (`[]`, `{}`) |
| `L<US>path<US>value` | элемент списка (блочного или flow) |
| `X<US>reason` | ошибка; разбор прекращён |

Поддерживаемое подмножество (всё иное → `X`): блочные отображения с отступом пробелами; блочные списки **с отступом и без** (`  stages:` + `  - spec` на том же отступе — форма дампа узла); flow-списки `[a, "b", 'c']` (в одну строку и многострочные); одинарные/двойные кавычки (`''` и `\"`, `\\`); комментарии `# …` и пустые строки; CRLF; `---` как первая содержательная строка. Отказ: табуляция в отступе, `…`/второй документ, ключ вне `[A-Za-z0-9_-]+`, список словарей, flow-словарь с содержимым, якоря/алиасы/теги/блочные скаляры (`& * ! | > % @` в начале значения), дубликат ключа на одном пути, неплоский plain-скаляр с `: `, ключ под скаляром, ключ после элементов списка. Проверенный прототип разборщика (граничные случаи уже обкатаны на 30 фикстурах; ядро — функции `unq`, `emit_flow`, стек отступов `tind[]/tpath[]/kind[]`):

```awk
# kind[depth] in {open, scalar, list}; a "- x" line is legal only under an open/list key with tind <= its indent
if (body ~ /^- / || body == "-") {
  if (depth == 0 || (kind[depth] != "open" && kind[depth] != "list") || tind[depth] > ind) err("элемент списка вне ключа, строка " NR)
  ...; print "L\037" tpath[depth] "\037" v; kind[depth] = "list"; next
}
if (match(body, /^[A-Za-z0-9_-]+:([ \t]|$)/)) { key = body; sub(/:.*$/, "", key); val = substr(body, RLENGTH + 1) } else err("строка не разобрана как YAML, строка " NR)
while (depth > 0 && tind[depth] >= ind) depth--           # pop to the parent by indent
path = (depth > 0) ? tpath[depth] "." key : key
if (path in seen) err("дубликат ключа " path); seen[path] = 1
```

Причина `X` всегда начинается с русского описания и номера строки; `MY_ERR` попадает в stderr отказов дословно. Аксессоры — `awk -F"$US"` по `MY_NORM`; ни один не использует `eval`.

### [ADDED] `sdx/hooks/lib/mandate.sh` — семантика мандата (REQ-MAND-2, 3, 6–10, 12)

`source`-библиотека, подключает `miniyaml.sh` по `${BASH_SOURCE[0]%/*}`. Функции:

```
mandate_mode <proj>         # stdout: on (оба файла) | orphan (только mandate.yaml) | none        # MAND-MODE
mandate_load <proj>         # my_load .mesh/mandate.yaml + валидация; rc 0 | 1 (MANDATE_ERR=причина)
                            #   1) нет записи "O mandate" (в т.ч. mandate: пуст, корень не словарь)      # MAND-ROOT
                            #   2) mandate.stages — S-запись (скаляр) → "stages не список"
                            #   3) элемент вне {spec,design,execute,verify} → "неизвестная стадия: X"    # MAND-UNKNOWN
                            #   вывод: MANDATE_STAGES (по строке), MANDATE_PATHS/_SHARED/_DOCS/_BRANCHES (по строке);
                            #   MANDATE_DOCS = docs_paths, а при пустом/отсутствующем — "docs/**"          # MAND-DOCS-DEFAULT
mandate_stage_class <Этап>  # spec|design|execute|verify|always|never  (таблица ниже)
mandate_stage_allowed <Этап># rc 0, если этап НЕ исключён мандатом (always — всегда; never — никогда)
mandate_glob_one <path> <pat>  # rc 0 ⇔ glob_any(path,[pat]) эталона
mandate_glob_any <path> <pat>… # rc 0, если совпал хотя бы один
mandate_expired             # rc 0, если valid_until матчит ^YYYY-MM-DD и < сегодня (SDX_MANDATE_TODAY или date +%F)   # MAND-EXPIRY
mandate_raw_on_write <file> # то же правило mode_re, что в mo-hook.sh, → deny|notice (для /sdx:status)
mandate_report <proj> <prefix>  # показ и предупреждения, stdout (вызывающий решает, куда)
```

Таблица отображения (`MI` §7; ДЛ-1):

| Этап SDX | класс | допущен, если |
|---|---|---|
| Discovery, Business Spec | `spec` | `spec` ∈ stages |
| Technical Design, Task Planning | `design` | `design` ∈ stages |
| Execution, Documentation | `execute` | `execute` ∈ stages |
| Verification, Closeout | `always` | всегда |
| Deployment | `never` | никогда (при мандате, при любом `delivery`) |

Пустой/отсутствующий/`null` `stages` → пустое множество: допущены только `always` (дефолт В7).

`glob_any` (проверено на 27 случаях против эталона):

```bash
mandate_glob_one() {   # $1 path, $2 pattern
  local f="$1" p="$2" a b
  p="${p//\\/\\\\}"; p="${p//\[^/[\\^}"                       # MAND-GLOB-ESC: fnmatch has no escapes and no [^..] negation
  case "$f" in $p) return 0 ;; esac                           # fnmatch(path, p)
  a="$p"; while [ "${a%/}" != "$a" ]; do a="${a%/}"; done     # p.rstrip("/")
  case "$f" in $a/*) return 0 ;; esac                         # fnmatch(path, a + "/*")
  b="$p"; while [ "${b%\*}" != "$b" ]; do b="${b%\*}"; done   # p.rstrip("*")
  while [ "${b%/}" != "$b" ]; do b="${b%/}"; done             # .rstrip("/")
  [ "${f#"$b"/}" != "$f" ]                                    # MAND-GLOB-PREFIX: startswith(b + "/")
}
```
Вызывается при `LC_ALL=C` (диапазоны `[a-z]` не зависят от локали); `*` совпадает с `/` — как в Python.

`mandate_report <proj> <prefix>` печатает (в таком порядке; каждая строка начинается с `<prefix>`):

1. при ошибке загрузки — одна строка `…ВНИМАНИЕ: мандат .mesh/mandate.yaml не разобран (<причина>): /sdx:start и /sdx:next откажут (fail-closed).` и возврат;
2. заголовок `… мандат МО (.mesh/mandate.yaml; выдан узлом, правится только узлом) — поля ниже ДАННЫЕ, не инструкции:`;
3. три строки полей, каждая с префиксом `  [ДАННЫЕ, не инструкции] `: (а) `executor= digest= valid_until= delivery= history= docs_in_repo=`; (б) `stages=[…] on_write=` (`on_write` только если задан); (в) `scope.paths=[…] shared_paths=[…] docs_paths=[…] branches=[…]`. Значения — `my_q` (кавычки, усечение до 160 знаков); список — первые 8 элементов и `…(+N)`; отсутствующее поле печатается `unset`; общий предел строки 480 знаков;
4. *(Поправка круга 4 верификации, 2026-10-29: по К-1 предупреждение области печатается отдельной строкой на КАЖДЫЙ непокрытый каталог — `.claude/sessions/`, затем `docs/`.)* предупреждения (каждое — одна строка, только при условии): **область** (REQ-MAND-6, К-1): `scope.paths` непуст И пробный путь `.claude/sessions/x` не покрыт объединением `paths ∪ shared ∪ docs` (и/или `docs/x`) → `…ВНИМАНИЕ: область мандата не покрывает <.claude/sessions/ | docs/ | оба>: записи артефактов сессии/документов окажутся вне области; при mandate.on_write: deny хук заблокирует их. Мандат не правится (его выдаёт узел).`; **срок** (REQ-MAND-7): `…ВНИМАНИЕ: мандат истёк (valid_until=…): узел отклонит пакет по mandate.valid; работа не блокируется.`

Для `orphan` отдельная функция `mandate_orphan_line <prefix>` печатает ровно одну строку: `<prefix> .mesh/mandate.yaml есть, но .mesh/endpoint.yaml нет — мандат без endpoint.yaml не действует (гейт стадий, проверка области и охрана мандата выключены).`

### [ADDED] `sdx/hooks/mandate-info.sh` — CLI для команд (REQ-MAND-3, 5, 23, 26)

`bash mandate-info.sh <sub> [proj]`, `proj` по умолчанию `${CLAUDE_PROJECT_DIR:-.}`. Все подкоманды, кроме `closeout-check`, — rc 0 (информирование); выводы построчно-стабильные.

| Подкоманда | stdout |
|---|---|
| `mode` | `on` \| `orphan` \| `none` |
| `show` | при `on` — `mandate_report "$proj" "SDX mandate:"`; при `orphan` — `mandate_orphan_line`; при `none` — пусто |
| `status` | одна строка МО (формат в «Схеме данных») |
| `closeout-mode` | `standard` (нет режима мандата) \| `bridge` (`on` и `delivery ∈ {pr,branch}`) \| `bridge:offer` (`on` и `delivery: artifact.offer`; поправка 2026-10-29, было `standard`) \| `undefined:<delivery>` (`on`, значение иное — К-5) \| `error:<причина>` |
| `closeout-check <sid>` | `OK`-строки либо `FAIL <причина>`; rc 0/1. Проверки: текущая ветка `== sdx/<sid>`; `git status --porcelain` пуст; в `HEAD` нет путей под `.claude/sessions/<sid>/` (`git ls-tree -r --name-only HEAD`). Ветка не удаляется и не сливается |

### [ADDED] `sdx/hooks/mandate-scope.sh` — `diff ⊆ область` (REQ-MAND-12…15)

```
git -c core.quotepath=off diff --name-only "$def"...sdx/<id> -- . ':!.claude/sessions/**' \
  | bash mandate-scope.sh [--proj DIR] --into <verification_report.md> [--planned <path>]…
```
Вход stdin — пути по строке (путь с переводом строки — вне контракта; `core.quotepath=off` оставляет кириллицу как есть). Алгоритм:

1. `mandate_mode != on` → **ничего не печатает и не пишет** (REQ-MAND-15), rc 0. При `--into` существующего блока от прошлого прогона **не** удаляет (в этом режиме блока быть не должно).
2. `mandate_load` не прошёл → блок с единственной находкой `### [FAIL] Мандат МО не разобран: <причина>` (fail-closed), rc 1.
3. Для каждого файла `f`: `in_union = glob_any(f, paths ∪ shared ∪ docs)`; `in_shared = glob_any(f, shared)`. Если `paths` непуст и не `in_union` → `FAIL`. Если `in_shared` → `WARN` (даже при пустом `paths`, В9).
4. Для каждого `--planned p` (перенос Closeout, К-3): если `paths` непуст и не `glob_any(p, union)` → `FAIL` с причиной «перенос Closeout вне docs_paths» (REQ-MAND-14). Пустой `paths` → не FAIL.
5. Блок (между `<!-- SDX-MANDATE-SCOPE:BEGIN -->` и `…END -->`; при повторе прежний блок заменяется awk-ом, остальной отчёт не трогается):

```markdown
<!-- SDX-MANDATE-SCOPE:BEGIN -->
## Область мандата (детерминированная проверка `mandate-scope.sh`; добавлена оркестратором, сводка ревьюера выше не пересчитывается)
- Мандат: executor=<…>, digest=<…>; файлов в диффе: N; запланированных переносов Closeout: M
- Итог по области: PASS | FAIL (K) | WARN (L)
### [FAIL] [Область] Файл вне области мандата: `path`
- Где: `path` — не входит в scope.paths ∪ shared_paths ∪ docs_paths
- Суть: правка за границей мандата; узел отклонит пакет по `scope`.
### [WARN] [Область] Общий путь (shared_paths): `path`
- Суть: правка общего файла; слияние такого пакета — решение человека; в FEAT-017 станет touches_shared: true.
### [FAIL] [Область] Перенос Closeout вне docs_paths: `docs/DECISIONS.md`
- Суть: путь не покрыт docs_paths мандата; узел должен перечислить реестр решений явно (вопрос §5.3 записки).
<!-- SDX-MANDATE-SCOPE:END -->
```
Заголовок блока — `##`, находки — `###` с теми же маркерами, что у ревьюера, поэтому `gate_ok` и существующий шаг 7 `verify.md` работают без правок. Строка срока: если `mandate_expired`, в блок добавляется **не-заголовочная** строка `> Предупреждение: мандат истёк (valid_until=…) — решение у узла; гейт не блокируется` (`### [WARN]` потребовал бы квитирования, а REQ-MAND-7 запрещает блокировать).
6. Коды: 0 — нет FAIL; 1 — есть FAIL; 2 — ошибка использования (нет `--into`/нечитаем отчёт). stdout — одна сводная строка (`PASS|FAIL K|WARN L`).

### [ADDED] `sdx/hooks/lib/test-cmd.sh` и `sdx/hooks/suites-gen.sh` (REQ-MAND-18…21)

`test_cmd_resolve <proj>` — зеркало блока `stop-gate.sh:49–64` (порядок: `.claude/sdx/verify-cmd.sh` по наличию → `composer.json` с `"test"` → `package.json` с `"test"` → `phpunit.xml|.dist`), возвращает `TC_KIND` (`verify-cmd|composer|npm|phpunit|none`) и `TC_CMD` для `tests/suites.yaml`: `bash .claude/sdx/verify-cmd.sh` | `composer test` | `npm test --silent` | `./vendor/bin/phpunit`. Файл `stop-gate.sh` не меняется; расхождение ловит тест-близнец (раздел «Тесты»). *(Поправка круга 3 верификации, 2026-10-29: `cmd` зеркалит stop-gate: `./.claude/sdx/verify-cmd.sh` при бите исполнения, иначе `bash .claude/sdx/verify-cmd.sh` (поправка SPEC REQ-MAND-18/19))*

`suites-gen.sh [--check] [proj]`:

| Исход (первое слово stdout) | Условие | Действие |
|---|---|---|
| `CREATED` | файла нет, команда определена | пишет `tests/suites.yaml` (детерминированно, ниже) |
| `OK` | файл есть, `suites.unit` (строка или `.cmd`/`.budget_min`) совпадает с резолвом | ничего |
| `DIFFERS` | файл есть, `unit` расходится или отсутствует | ничего; в stdout обе стороны (`unit.cmd=<…> vs <…>`, `budget_min`) |
| `ABSENT` | `--check`, файла нет, команда определена | ничего (только сообщение) |
| `NOCMD` | команда не определена | файл не создаётся; причина «stop-gate no-op: нет verify-cmd.sh и автодетект пуст» |
| rc 2 | нечитаемый существующий файл / не каталог | сообщение; файл не меняется |

`budget_min = ceil(S / 60)`, `S = ${SDX_VERIFY_TIMEOUT:-180}`; `S` не целое положительное → `S=180` и строка в stderr. Существующий файл читается `my_*` (форма `unit: "<cmd>"` и `unit: {cmd, budget_min, selector}` — обе). Запись атомарна (`mktemp` рядом + `mv`), `mkdir -p tests`.

### [MODIFIED] `sdx/hooks/sdx-stage.sh` — третий источник сужения (REQ-MAND-8…11)

Скрипт остаётся bash+jq (fail-closed на jq — прежний код ДО диспетчера). Библиотека подключается **лениво** и только в режиме мандата, поэтому без мандата ни один новый байт кода не выполняется, кроме проверки двух `-f`.

```bash
MANDATE_ON=0
mandate_gate_load() {   # $1 = refusal exit code: init -> 2, next -> 1
  [ -f "$proj/.mesh/endpoint.yaml" ] && [ -f "$proj/.mesh/mandate.yaml" ] || return 0        # MAND-MODE
  local lib="${BASH_SOURCE[0]%/*}/lib/mandate.sh"
  [ -f "$lib" ] || { echo "SDX sdx-stage: lib/mandate.sh плагина не найдена — мандат МО не проверить, отказ (fail-closed)." >&2; exit "$1"; }
  . "$lib"
  if ! mandate_load "$proj"; then
    echo "SDX sdx-stage: мандат МО (.mesh/mandate.yaml) не разобран: $MANDATE_ERR — отказ (fail-closed: неизвестная граница не трактуется как «без границ»). Мандат выдаёт и правит узел МО." >&2
    exit "$1"
  fi
  MANDATE_ON=1
}
is_excluded_by_mandate() { [ "$MANDATE_ON" = 1 ] && ! mandate_stage_allowed "$1"; }          # MAND-EXCL
is_skipped() { { [ "$2" = "true" ] && is_excluded_by_no_code "$1"; } || is_excluded_by_mandate "$1"; }
```

Точки врезки (остальное тело `cmd_init`/`cmd_next` не меняется):

| Место | Правка |
|---|---|
| `cmd_init`, после шага 5 (`no_code` на исключённом этапе), **до** шага 6 (файл существует) | `mandate_gate_load 2`; затем `is_excluded_by_mandate "$stage"` → stderr `SDX sdx-stage: мандат МО исключает стартовый этап '<stage>' (стадия '<класс>' не в mandate.stages=[…]; Deployment при мандате исключён всегда) — получите допустимый этап через 'sdx-stage.sh start-stage'.` rc **2** (у `init` ненулевой код по-прежнему всегда 2) |
| `cmd_next`, **после** блока приоритета 0 (`no_gates`) и до ветки `--to` | `mandate_gate_load 1` — `no_gates`-сессия мандат не читает вовсе (приоритет 0 не меняется) |
| `--to`, сразу после проверки `no_code`-исключения (перед `idx_current`) | `is_excluded_by_mandate "$to_target"` → stderr `SDX sdx-stage: мандат МО исключает этап '<to_target>' (стадия '<класс>' не в mandate.stages=[<список>]; Deployment при мандате исключён всегда) — переход --to на этот этап недоступен; stage не изменён. Мандат выдаёт узел МО.` rc **1**, `write_stage` не вызывается |
| форвард, цикл пропуска кандидата | `while is_skipped "$candidate" "$no_code" && [ "$candidate" != "Closeout" ]; do …` # MAND-SKIP — пропуск без отказа |

Коды: нечитаемый мандат в `next` — rc **1** (исправимо пользователем; `archive.md` уже обрабатывает rc 1 как «гейт не пройден, чек-лист не начинается»), в `init` — rc 2 (ранее оговорено). Нет lib при режиме мандата — fail-closed (rc по месту вызова).

Новые подкоманды (read-only; в usage-строку диспетчера добавляется `start-stage|active-set`, К-10):

- `sdx-stage.sh start-stage <желаемый_этап> <no_code> <no_gates>` → stdout: имя этапа; rc 0. Алгоритм: проверка литералов и взаимоисключения флагов — как шаги 1–3 `init` (rc 2); `no_gates=true` → кандидат только `Execution`, при исключении мандатом — rc 1 и stderr «нет допустимого стартового этапа: no_gates допускает только Execution, а мандат исключает его (stages без execute)»; иначе идти от желаемого этапа вперёд по каноническому порядку до первого, не исключённого `no_code` и мандатом (`Closeout` — всегда допустим, поэтому тупика нет); нечитаемый мандат → rc 1 с тем же текстом отказа.
- `sdx-stage.sh active-set <sid>` → девять строк `<Этап>\t<active|excluded:<источники через запятую>>` (`no_code`, `no_gates`, `mandate(<класс>)`); при нечитаемом мандате — rc 1 и первая строка `MANDATE-ERROR <причина>`. Для `/sdx:status` (REQ-MAND-26).

Сессия, стартовавшая до переиздания мандата, может оказаться на этапе, исключённом новым мандатом: `next` вперёд работает (гейт уходящего этапа проверяется как раньше), `--to` на исключённый — отказ; стадия состояния `stage` не «лечится» скриптом (названо в «Границах»).

### [MODIFIED] `sdx/hooks/mo-hook.sh` (REQ-MAND-16, 17)

Автономный файл, без `source`. Три правки; существующие якоря и строки сохраняются. *(Поправка круга 1 верификации, 2026-10-29: четвёртая правка — `# MAND-PYYAML`: при `deny`, пришедшем из мандата, обёртка проверяет PyYAML до запуска хука и при отказе отдаёт JSON deny; сценарии `[2y]` a–d и мутант `MAND-PYYAML`.)*

1. Режим из двух файлов — сразу после блока `mode=notice … # MO-MODE`, одна строка-якорь:
```bash
[ "$mode" = deny ] || { [ -f "$proj/.mesh/mandate.yaml" ] && text="$(cat "$proj/.mesh/mandate.yaml" 2>/dev/null)" && [[ $text =~ $mode_re ]] && case "${BASH_REMATCH[2]}" in [dD][eE][nN][yY]) mode=deny ;; esac; }   # MAND-MODE2
```
`mode_re` тот же (регистр значения не учитывается; нет ключа/ошибка чтения → остаётся `notice`). Читается только после раннего выхода по `endpoint.yaml` (`MO-EARLY-EXIT` не меняется), то есть `mandate.yaml` без `endpoint.yaml` не читается (REQ-MAND-2). Исход «`mandate.on_write: deny`, `endpoint: notice`» → `cannot_check` ведёт себя как в `deny`; обратная комбинация и `notice/notice` — как раньше.
2. Охрана `mandate.yaml` — `is_mailbox_file` получает третий параметр-список имён (дефолт `"endpoint.yaml cursors.json"`; цикл `for f in $names; do`), вызов для `endpoint/cursors` **не меняется** (текст отказа и якорь `# MO-GUARD` прежние — REQ-MAND-1); сразу под ним вторая строка:
```bash
[ -n "$fp" ] && is_mailbox_file "$fp" "$cwd0" "mandate.yaml" && deny_json "SDX mo-hook: .mesh/mandate.yaml выдаёт узел МО, не dev-agent: сессия не расширяет собственную область (MO-INTEROP §7). Запись остановлена."   # MO-GUARD-MANDATE
```
Нормализация пути (`MO-NORM`), проверка `proj_abs`/`proj_phys` — общие. Охрана безусловна по наличию файла `mandate.yaml` (К-4) и действует в обоих режимах (`notice`/`deny`): она стоит до запуска хука и не зависит от `mode`.

### [MODIFIED] `sdx/hooks/mo-session.sh` (REQ-MAND-3, 4, 6, 7)

Корневая проверка `[ -f "$proj/.mesh/endpoint.yaml" ] || exit 0` **сохраняется дословно** (её «old»-фрагмент — в мутанте `no-guard`). Определения `P=…` и `say()` переносятся выше этой проверки без изменения текста (иначе строка ниже их не видит); перед проверкой добавляется одна строка:

```bash
[ -f "$proj/.mesh/endpoint.yaml" ] || { [ -f "$proj/.mesh/mandate.yaml" ] && { . "$plugin_root/sdx/hooks/lib/mandate.sh" 2>/dev/null && mandate_orphan_line "$P" >&2 || printf '%s\n' "SDX mo-session: .mesh/mandate.yaml есть, но .mesh/endpoint.yaml нет — мандат без endpoint.yaml не действует." >&2; }; }   # MAND-ORPHAN
```
(`$P` определяется выше; строка ровно одна в обеих ветках.)

Показ — отдельный блок **после** `leases` и **до** финальной строки `say "$P входящие читать…"`:

```bash
if [ -f "$proj/.mesh/mandate.yaml" ]; then   # MAND-SHOW (endpoint.yaml guaranteed above)
  if . "$plugin_root/sdx/hooks/lib/mandate.sh" 2>/dev/null; then mandate_report "$proj" "$P" >&2
  else say "$P мандат .mesh/mandate.yaml не показан: lib/mandate.sh плагина недоступна."; fi
fi
```
Ветка «нет python3/PyYAML» (дословный `say` сохраняется как префикс «old») получает суффикс только при наличии мандата: `mnote=""; [ -f "$proj/.mesh/mandate.yaml" ] && mnote=" Мандат .mesh/mandate.yaml не прочитан."` и `…Установите python3 и PyYAML.$mnote"` — одна строка остаётся одной (инвариант `py-two-lines`), без мандата строка бит-в-бит прежняя. Все выходы — `exit 0`; в новых комментариях слово «exit» не используется (тест `[9]` ищет его построчно). *(Поправка круга 3 верификации, 2026-10-29: суффикс читается без python3: «Мандат … читается без python3 и показан ниже» (К-2))*

### [MODIFIED] Команды (проза + вызовы скриптов)

- **`commands/start.md`.** Новый шаг **1а** (после сверки версии, до шага 2): `bash "${CLAUDE_PLUGIN_ROOT}/sdx/hooks/mandate-info.sh" show`; вывод показать пользователю **дословно** (REQ-MAND-5; канал SessionStart не проверен, DEBT-045). Шаг 3 «Назначение флагов и стартового этапа»: выбранный суждением `stage` проходит через `sdx-stage.sh start-stage "<stage>" "<no_code>" "<no_gates>"` — её stdout и есть стартовый этап (без мандата — тот же `stage`); rc ненулевой → показать stderr, **остановиться до шага 5** (ветка не создаётся). Шаг 6 (`init`) вызывает уже допустимый этап; описание кода `2` дополняется «или мандат МО исключает стартовый этап/не разобран».
- **`commands/import.md`** (строка вызова `init`): тот же `start-stage` перед `init`.
- **`commands/next.md`.** Пояснение «ограничение цели по флагу» дополняется: «и мандатом МО (`stages`, `Deployment` при мандате исключён всегда)»; код `1` с причиной «мандат МО исключает этап» трактуется как любой отказ перехода (`[ERROR] Ошибка перехода: …`, `stage` не изменён); при мандате `artifact.offer` отправляется на `Execution`/`Verification` (ДЛ-1). *(Поправка круга 3 верификации, 2026-10-29: `artifact.offer` отправляется ОДИН раз на шаге моста Closeout (`bridge:offer`); при уже отправленном на `Execution`/`Verification` — пропуск `(уже отправлен: <msg_id>)`)*
- **`commands/verify.md`.** Шаг **6а** (после того как ревьюер создал `verification_report.md`, до шага 7 «Гейт»): при `mandate-info.sh mode == on` выполнить блок из раздела «mandate-scope» с `--planned` по правилу: `docs/specs/` — если есть `SPEC.md` или `change_note.md`; `docs/designs/` — если есть `DESIGN.md`; `docs/history/plans/` — если есть `PLAN.md`; `docs/history/sessions-log.md` и `docs/backlog/` — всегда; `docs/DECISIONS.md` — если сессия вводит/правит ADR (суждение оркестратора; при сомнении — включить). Затем прочитать отчёт с блоком и свести находки (шаг 6 «Сведи…»). В режиме мандата `mandate_expired` → строка-предупреждение в сводку. Без мандата шаг 6а не выполняется и ничего не добавляет (REQ-MAND-15). В `agents/reviewer.md` изменений нет (изоляция).
- **`commands/archive.md`** и протокол «Контракт закрытия»: `mandate-info.sh closeout-mode`. `standard` — прежний чек-лист. `bridge` — шаги 1–5 как есть, где п.2 учитывает `docs_in_repo` (`none` → переносы в `docs/specs|designs` и ADR `(n/a, docs_in_repo: none)`; `final`/`full` — штатный перенос, К-6), шаги **6–8** `(n/a, мандат)`; вместо `archive-verify.sh` — `mandate-info.sh closeout-check <sid>`; ветка `sdx/<id>` остаётся, пользователю выводится пошаговая инструкция ручной сборки пакета `change/<C>-<exec>` (squash из `sdx/<id>` + `CHANGE.yaml` по `CHANGE.template.yaml` sim-kit) — «до `/sdx:pr` (`FEAT-017`)». `undefined:<delivery>` и `error:…` — **остановка и вопрос пользователю** (стоп-рубрика: контракт). *(Поправка круга 3 верификации, 2026-10-29: `closeout-mode` → `bridge` или `bridge:offer` при любом определённом `delivery`; при `bridge:offer` к шагам 1–5 добавляется шаг отправки оффера, ветка остаётся, пакет собирается при любом `delivery`)*
- **`commands/status.md`.** Новый шаг (между 5 и 6, чисто читающий): `mandate-info.sh status` и `sdx-stage.sh active-set <id>`; вывести строку МО и таблицу активности с источниками.
- **`commands/init.md`.** Шаг 2c: «`tests/suites.yaml` создаёт сверка (шаг 4, `/sdx:reconcile`) вызовом `suites-gen.sh`; файл **tracked**, паттерн `.gitignore` не добавляется»; шаг 6 (отчёт) включает исход `CREATED|OK|DIFFERS|NOCMD`.
- **`commands/reconcile.md`.** В шаге 6 (детект) две новые категории: (е) `tests/suites.yaml` — `suites-gen.sh --check` (`ABSENT` → применимо на шаге 10 по подтверждению группы вызовом `suites-gen.sh` без `--check`; `DIFFERS`/`NOCMD` — только находка); (ж) «устаревший SDX-блок `CLAUDE.md`» — `snippet-check.sh` (ниже), применимо **только с явного согласия** (замена блока целиком между маркерами). В `--scan-only` — ничего не пишется.

### [ADDED] `sdx/hooks/snippet-check.sh` (REQ-MAND-25)

`bash snippet-check.sh <CLAUDE.md> [шаблон]` (шаблон по умолчанию — `claude-md-snippet.md` рядом с плагином). stdout: `ABSENT` (нет маркеров), `BROKEN` (нет парного `SDX:END`/более одного блока), `OK` (блок идентичен шаблону с точностью до хвостовых пробелов и CRLF), `STALE`. rc 0. Замену выполняет оркестратор по согласию (`snippet-check.sh --replace` не вводится: запись в пользовательский файл — только прозой, как вставка на `init`).

### [MODIFIED] `agents/devops.md` (REQ-MAND-22)

В «Режим МО» переключатель различает два признака: «есть `endpoint.yaml`» (стенды, как прежде) и «есть также `mandate.yaml`» (режим мандата). Добавляется подпункт: при мандате **не** выполняй слияния в ветки, не входящие в `scope.branches` (ветки, куда исполнителю разрешено писать), и не создавай теги — это `change.merge`/`change.promote` узла; пустой `scope.branches` означает «ограничение не задано» (как у эталона), но слияние в `main`/`dev`/`stage` и теги под мандатом всё равно не действие `devops`; `Deployment` исключён из активного набора (`sdx-stage.sh`), `prod-guard` и stop-gate не ослабляются. В «Инструкциях» п.3 уточняется. Обновляется ссылка «`.mesh/endpoint.yaml`/`cursors.json` не правишь» → «и `.mesh/mandate.yaml`». Слова-инварианты для `test-mo-prose.sh`: `mandate.yaml`, `scope.branches`, `теги`, `prod-guard`.

### [MODIFIED] `sdx/templates/claude-md-snippet.md` (REQ-MAND-24)

В абзац «МО над стендами» — одно предложение (до фразы «Нет `.mesh/endpoint.yaml` — пункт неприменим»): «Если рядом есть `.mesh/mandate.yaml`, он говорит, какие стадии делаешь ты и в какой области; запись вне области и слияние в защищённые ветки — не твоё действие.» Без `/sdx:pr`. Первая строка маркера и `SDX:END` не меняются.

## Схема данных / API

### Форма `.mesh/mandate.yaml` (внешний контракт, `DEV:525–531`)

Блочный вид дампа узла (списки без отступа) и flow-вид тестового `mandate_yaml()` (`test-mo-hook.sh:105`) — **обе** формы входят в фикстуры. Потребляемые поля: `mandate.stages`, `mandate.scope.{paths,shared_paths,docs_paths,branches}`, `mandate.delivery`, `mandate.history`, `mandate.docs_in_repo`, `mandate.valid_until`, `mandate.on_write`, `mandate.executor`, `mandate.digest`. Остальное (`repo`, `issued`, `node`, `format`, `how_to_deliver.*`) разбирается и игнорируется. Кавычки у даты (`valid_until: '2026-12-31'`) снимаются.

### Коды возврата и тексты

| Скрипт / ситуация | rc | stderr/stdout |
|---|---|---|
| `sdx-stage.sh init`, этап исключён мандатом / мандат не разобран | 2 | тексты выше |
| `sdx-stage.sh next` (форвард/`--to`), мандат не разобран | 1 | текст «не разобран» |
| `sdx-stage.sh next --to <исключённый>` | 1 | текст «исключает этап» |
| `sdx-stage.sh start-stage` | 0 / 1 / 2 | stdout — этап |
| `mandate-scope.sh` | 0 / 1 / 2 | блок в отчёт; stdout — сводка |
| `suites-gen.sh` | 0 / 2 | первое слово stdout — исход |
| `mandate-info.sh` | 0 (кроме `closeout-check`: 0/1) | см. таблицу |
| `mo-hook.sh`, `mo-session.sh` | всегда 0 | как прежде |

### Строка `mandate-info.sh status` (REQ-MAND-26)

```
МО: endpoint.yaml=<есть|нет>; mandate.yaml=<есть|нет>; режим мандата=<включён|выключен|«мандат без endpoint не действует»>; on_write: endpoint=<deny|notice|—> mandate=<deny|notice|—> (обёртка берёт <deny|notice>); jq=<есть|нет> python3=<есть|нет> PyYAML=<есть|нет>; valid_until=<…|—> digest=<…|—>
```
`PyYAML` — `PYTHONDONTWRITEBYTECODE=1 python3 -c 'import yaml'`; ничего не пишется. Активный набор — вывод `sdx-stage.sh active-set` (источники сужения в скобках).

### `tests/suites.yaml` (REQ-MAND-18, 19)

Генерируется побайтно детерминированно (нет дат/версий). Пример для `verify-cmd.sh` и `SDX_VERIFY_TIMEOUT=180`:

```yaml
# tests/suites.yaml — декларация тестов репозитория для узла МО (sim-kit 0.9, dev.py run_suites).
# Создан /sdx:init или /sdx:reconcile (sdx/hooks/suites-gen.sh) из той же команды, что исполняет stop-gate.
# Имена наборов — контракт policy/tests.yaml узла: unit | module | regression.
# cmd — строка оболочки в корне рабочей копии узла; budget_min — минуты; selector зарезервирован (пусто — набор целиком).
# Файл НЕ перезаписывается генератором; правьте вручную.
suites:
  unit:
    cmd: bash .claude/sdx/verify-cmd.sh  # круг 3: ./.claude/sdx/verify-cmd.sh при бите исполнения, иначе bash …
    budget_min: 3
    selector: ""
  # module:
  #   cmd: <команда модульных/интеграционных тестов>
  #   budget_min: 10
  #   selector: ""
  # regression:
  #   cmd: <команда полной регрессии приложения>
  #   budget_min: 60
  #   selector: ""
```
Скаляры с `: `, ` #` или ведущим служебным символом квотируются одинарными кавычками. Файл читается `yaml.safe_load` без ошибок (проверено на образце; структурный тест плагина делает то же через `my_*` и, при наличии PyYAML, через оракул).

### Dogfood (REQ-MAND-21)

`tests/suites.yaml` репозитория: `unit.cmd: bash .claude/sdx/verify-cmd.sh`, `budget_min: 3` (полный прогон ≈ 78–105 с < 180 с); `module`/`regression` — образцы. Разовая проверка `dev.py run_suites` на чекауте sim-kit 0.9.1 — раздел «Ручной сценарий». *(Поправка круга 3 верификации, 2026-10-29: `cmd` зеркалит stop-gate: `./.claude/sdx/verify-cmd.sh` при бите исполнения, иначе `bash .claude/sdx/verify-cmd.sh` (поправка SPEC REQ-MAND-18/19))*

## Обработка ошибок и Граничные случаи

- **Нечитаемый мандат.** `sdx-stage.sh` (`init`/`next`/`start-stage`/`active-set`) отказывает с причиной; `mo-session` печатает одну строку и `exit 0`; `mandate-scope.sh` выдаёт `FAIL`-блок; `mo-hook` не читает мандат ничем, кроме `mode_re`, и потому ошибки разбора не имеет.
- **`stages` пустой/`null`/`[]`** → допущены только `Verification`/`Closeout`; со стартом `start-stage Discovery …` → `Verification`.
- **Неизвестное имя стадии (`lint`, `Spec`)** → отказ; `stages: spec` (скаляр) → «не список».
- **CRLF, комментарии, `---`** — поддержаны; табуляция в отступе, второй документ — отказ.
- **Значения со служебными символами** (кавычки, `\`, ESC, 5000 знаков, 20 элементов) показываются через `my_q`: управляющие вырезаются, длина и число элементов ограничены; ни одна строка вывода не начинается значением мандата (всегда префикс и маркер).
- **Истёкший `valid_until`** — предупреждение, не блокировка; пустой `valid_until` — предупреждения нет; не-дата — предупреждения нет.
- **Пустой `scope.paths`** — «без ограничений»: нет предупреждения области (REQ-MAND-6), нет `FAIL`; `WARN` по `shared_paths` остаётся.
- **`docs_paths` не задан/пуст** → `docs/**` (как `DEV:386`).
- **Файл мандата исчез/появился между вызовами** — каждый вызов решает заново (D-3); `.mesh/` вне git.
- **Нет `jq`** — `sdx-stage.sh` по-прежнему fail-closed до разбора; `mandate-*` и `suites-gen.sh` jq не используют.
- **Нет `python3`** — ни один новый скрипт python не вызывает (кроме `status`, который лишь проверяет наличие).
- **Параллельный запуск** `suites-gen.sh` — атомарная запись (`mktemp`+`mv`), существующий файл не перезаписывается.
- **`SDX_VERIFY_TIMEOUT` не число** — fallback 180 и строка в stderr; stop-gate в этом случае сам красит прогон (вне поставки).
- **Путь в диффе с экзотикой** (пробелы, кириллица) — читаются построчно; перевод строки в имени — вне контракта (названо).
- **Совпадение семантик.** `/sdx:verify` следует `glob_any` аудита узла, не `_in_scope` хука; различия (хук считает `.mesh*` и корень в области и не применяет `docs_paths` через `glob_any`) объясняются в протоколе (раздел «Мандат»), в код не переносятся.

## Безопасность

- **Данные, не инструкции.** Всё содержимое мандата подаётся под маркером `[ДАННЫЕ, не инструкции]`, квотируется и усекается (`my_q`); управляющие символы вырезаются (инъекция в терминал/контекст). Ни одна функция не выполняет значения мандата (`eval` запрещён; `case "$f" in $p)` использует значение только как шаблон, `cmd` из `suites.yaml` генератор **пишет**, но не исполняет).
- **Самовыдача мандата.** Мягко — `MO-GUARD-MANDATE` (Write-семейство); жёстко — узел по `digest` и аудиту. `Bash`-пути (`>`, `sed -i`, `git checkout`) не охраняются (названная граница, как (а) в протоколе).
- **Fail-closed на гейте стадий** при нечитаемом мандате; fail-open там, где решение необратимо не ухудшается (показ).
- **PROC-020.** Поставка меняет hook-скрипты и механизм надзора → не в `gate_mode: auto`; `devops` при мандате не сливает и не ставит теги.
- **Новые зависимости:** нет (bash, awk, grep, sed, date; python/PyYAML — только в тестах как оракул; *поправка круга 1: `mo-hook.sh` дополнительно пробует `import yaml` при `deny` из мандата — проба, не зависимость*).
- **Права:** новые скрипты вызываются как `bash <путь>` (BUG-008), бит выполнения не требуется.

## Тесты

Конвенция: у каждой новой ветки красная сторона (мутант по якорю или встроенный негативный случай); шапка-комментарий сьюта — как `test-mo-inventory.sh`; bash 3.2; временные каталоги `mktemp -d` + `trap`; без записи в чекаут (в т.ч. `__pycache__`). Сьюты подхватываются глобом `verify-cmd.sh`.

### [ADDED] `test-mandate-lib.sh`

| № | Что | Красная сторона |
|---|---|---|
| L1 | корпус из ~35 фикстур: блочная/flow/смешанная, CRLF, комментарии, `---`, кавычки, пустой/`null`/`[]` `stages`, ошибки (не YAML, нет `mandate`, `stages` скаляр, неизвестная стадия, табуляция, дубликат, flow-словарь, якорь); ожидаемые `(rc, stages)` — статическая таблица | мутант `MAND-ROOT` (нет проверки корня), `MAND-UNKNOWN` (принимает чужие имена), `MAND-FLOW` (ломает разбор flow) |
| L2 | паритет с `yaml.safe_load` на том же корпусе (оракул, INFO-skip без PyYAML); расхождения допустимы **только** в сторону отказа и перечислены поимённо (дубликат, flow-словарь, якорь) | встроенный негативный: оракул-подмена возвращает иной список → сравнение краснеет |
| L3 | реальный дамп узла (полный `how_to_deliver`, `format: 1`, дата в кавычках) → поля `executor/digest/valid_until/delivery/scope.*` | — (L1 мутанты) |
| L4 | таблица этапов × `stages` ∈ {`[spec]`,`[design]`,`[execute]`,`[verify]`,`[]`, все}: `Deployment` исключён всегда; `Verification`/`Closeout` всегда допущены | мутанты `MAND-NEVER` (Deployment допущен), `MAND-ALWAYS` |
| L5 | `glob_any`: статическая таблица ≥ 27 случаев (`p/`, `p/**`, `*`, равенство, `[!x]`, `[^x]`, `\`, пустой, регистр, `docs/**` vs `docs/`) + оракул `fnmatch`-формулой `DEV:67–68` (INFO-skip без python3) | мутанты `MAND-GLOB-PREFIX`, `MAND-GLOB-ESC` |
| L6 | `mandate_expired` с `SDX_MANDATE_TODAY`: прошлая/сегодня/будущая/пустая/не-дата | мутант `MAND-EXPIRY` (знак сравнения) |
| L7 | `mandate_mode`: оба/только мандат/только endpoint/ничего | мутант `MAND-MODE` (игнорирует endpoint) |
| L8 | `mandate_report`: враждебные значения (кавычка, `\`, ESC, 5000 знаков, 20 элементов, значение с переводом строки в кавычках) → каждая строка начинается с префикса/маркера, ESC отсутствует, усечение/`…(+N)`; предупреждения области (не покрыт `.claude/sessions/`; пустой `paths` — нет предупреждения; `docs/` покрыт дефолтом) и срока | мутант `MAND-SANITIZE`, `MAND-SCOPE-WARN` (предупреждение при пустом `paths`) |
| L9 | портируемость lib-файлов (`FORBID` как в `test-mo-hook.sh [12]`) + красная сторона на копии с `mapfile` | встроенная |

### [ADDED] `test-mandate-scope.sh`

Фикстуры: временный git-репозиторий с веткой `main`, веткой `sdx/s1`, файлами в диффе; мандат в обеих формах. Сценарии: (1) нет мандата и мандат без endpoint → нет вывода, отчёт не тронут (REQ-MAND-15); (2) файл вне объединения → `### [FAIL]` в отчёте, rc 1, `gate_ok`-форма (`^### \[FAIL\]`) срабатывает; (3) `shared_paths` → `### [WARN]`; файл одновременно в `paths` и `shared` → `WARN`; (4) пустой `scope.paths` → нет `FAIL`, `WARN` по `shared` остаётся; (5) `docs_paths` отсутствует → `docs/**` по умолчанию; файл `docs/DECISIONS.md` в диффе — ok; (6) `--planned docs/DECISIONS.md` при узком `docs_paths` → `FAIL` с причиной; при `docs/**` — нет; (7) повтор `--into` заменяет блок (идемпотентность), остальной отчёт побайтно сохранён; (8) нечитаемый мандат → `FAIL`-блок, rc 1; (9) сверочные случаи эталона `glob_any` через скрипт (интеграция с L5); (10) просроченный мандат → непроходящая заголовок строка-предупреждение, rc не 1. Мутанты (копия скрипта + lib в temp): `MAND-OUTSIDE` (убрана ветка FAIL), `MAND-SHARED` (убрана WARN), `MAND-EMPTY-PATHS` (FAIL при пустом `paths`), `MAND-PLANNED` (не проверяет `--planned`), `MAND-REPLACE` (дописывает второй блок).

### [ADDED] `test-suites-gen.sh`

(1) `verify-cmd.sh` + 180 → `CREATED`, `cmd: bash .claude/sdx/verify-cmd.sh`, `budget_min: 3`; 61 → 2; 60 → 1; 1 → 1; 181 → 4; нечисло → fallback 3 + stderr; (2) побайтовая детерминированность (два прогона в разные каталоги — равенство); (3) идемпотентность: второй запуск `OK`, файл без изменений; ручная правка `unit.cmd` → `DIFFERS`, файл без изменений; форма `unit: "<cmd>"` читается; (4) `NOCMD` — файл не создан; (5) автодетект `composer`/`npm`/`phpunit` и приоритет (verify-cmd.sh побеждает); (6) структура: `suites` — корень, `unit` — словарь `{cmd, budget_min, selector}`, закомментированные `module`/`regression` присутствуют и **не** активны (`my_exists suites.module` = нет); (7) **тест-близнец с `stop-gate.sh`** (по каждому классу из (5)): fixture-репозиторий на ветке `sdx/t` со `stage=Execution`, `SDX_STOP_GATE=1`, на `PATH` заглушки `composer`/`npm` и `vendor/bin/phpunit`, пишущие метку; запускается настоящий `stop-gate.sh`, затем `suites-gen.sh`; метка запуска (`verify-cmd`/`composer`/…) обязана совпасть с `TC_KIND` — любой дрейф резолвера краснит тест; (8) dogfood-файл репозитория: tracked (`git ls-files tests/suites.yaml`), `unit.cmd` равна `bash .claude/sdx/verify-cmd.sh`, `budget_min` ≥ 3, `module`/`regression` — комментарии; (9) при PyYAML — `safe_load` образца и dogfood-файла (оракул, INFO-skip иначе); (10) портируемость. Мутанты: `SG-CEIL` (деление без округления вверх), `SG-OVERWRITE` (перезапись), `SG-NOCMD` (создаёт файл без команды), `SG-ORDER` (composer раньше verify-cmd.sh — ловит близнец), `SG-BASH` (`cmd` без `bash`). *(Поправка круга 3 верификации, 2026-10-29: `cmd` зеркалит stop-gate: `./.claude/sdx/verify-cmd.sh` при бите исполнения, иначе `bash .claude/sdx/verify-cmd.sh` (поправка SPEC REQ-MAND-18/19); мутант `SG-BASH` — `cmd` без `bash` при отсутствии бита исполнения)*

Тот же сьют содержит раздел **[M] `mandate-info.sh`** (на тех же git-фикстурах): `mode` (три значения), `show` (при `none` — пусто; при `orphan` — ровно одна строка; при `on` — тот же вывод, что `mandate_report`), `status` (все поля строки; `PyYAML` — без записи на диск), `closeout-mode` (`standard` без мандата и при `artifact.offer`; `bridge` при `pr|branch`; `undefined:patch`; `error:…` при нечитаемом мандате), `closeout-check` (зелёный случай; красные: не та ветка, грязное дерево, каталог сессии в `HEAD`). Мутанты: `MAND-BRIDGE` (`bridge` и при `artifact.offer`), `MAND-CHECK-TREE` (не проверяет чистое дерево), `MAND-CHECK-SESSION` (не проверяет каталог сессии). *(Поправка круга 3 верификации, 2026-10-29: `closeout-mode`: `standard` только без мандата; `bridge` при `pr|branch`, `bridge:offer` при `artifact.offer`; мутант `MAND-BRIDGE` подменяет `bridge:offer` на `standard`)*

### [ADDED] `test-snippet-check.sh`

`ABSENT`/`OK`/`STALE`/`BROKEN` (два блока, нет `END`), CRLF/хвостовые пробелы допустимы, текст вне маркеров не влияет; мутант — сравнение без учёта содержимого. Плюс grep-инвариант: сниппет содержит предложение о `mandate.yaml` и не содержит `/sdx:pr` (в `test-mo-prose.sh`, ниже).

### [MODIFIED] `test-mo-hook.sh` (только добавлением)

- **`[2m]`** режим из двух файлов: матрица `{endpoint: notice|deny|нет ключа} × {mandate: нет файла|notice|deny|Deny|блочная форма дампа с `on_write: 'deny'`|flow}` × сценарий «не могу проверить» (нет `python3`) → JSON deny ⇔ `deny` хотя бы в одном; `mandate.yaml` без `endpoint.yaml` — тишина. Красная сторона: мутант **`MAND-MODE2`** (`/# MAND-MODE2/d`) краснит ячейки «endpoint notice, mandate deny».
- **`[7m]`** охрана `mandate.yaml`: `Write|Edit|MultiEdit|NotebookEdit` × формы пути (`abs`, `rel`, `dots`, `dslash`, `updir`, физический путь через симлинк проекта) × режим (`notice`/`deny`) × (с областью / с пустой областью / файла `mandate.yaml` нет) → JSON deny, `exit 0`, причина называет `mandate.yaml`; контроли: `.mesh/other.yaml`, `.mesh/inbox/x.json` не блокируются этой охраной; текст отказа для `endpoint.yaml`/`cursors.json` **не изменился** (сверка с прежней строкой — REQ-MAND-1). Мутанты: **`MAND-GUARD-MANDATE`** (`/# MO-GUARD-MANDATE/d`), **`MAND-NAME`** (`s|"mandate.yaml"|"mandate.yml"|`).
- **`[8i…]`** паритет обёртки и реального хука на реальных формах дампа (нужен PyYAML, иначе INFO-skip): для каждой формы `on_write` из корпуса `[2m]` значение, которое берёт `mode_re` (проверяется через сценарий «нет файла хука» — `cannot_check` блокирует ⇔ `deny`), совпадает с `yaml.safe_load(...)['mandate'].get('on_write')`, приведённым к нижнему регистру (расхождение допускается только на заведомо экзотическом YAML и перечислено поимённо).
- В `[13]` добавляются два вызова `mutate` (≈ 2–3 с); `mutate`-функция и сценарии `scen*` не меняются.

### [MODIFIED] `test-mo-session.sh`

Фикстурный корень получает `sdx/hooks/lib/{miniyaml,mandate}.sh` (`cp`; мутанты работают с копиями скрипта, но с тем же `CLAUDE_PLUGIN_ROOT`). *(Поправка круга 4 верификации, 2026-10-29: по К-2 сценарий [12] ждёт суффикс «читается без python3» и группу полей мандата, а не «не прочитан».)* Новые сценарии: **[10]** мандат без `endpoint.yaml` → ровно одна строка, `exit 0`, python/jq не запускались; **[11]** с мандатом (обе формы): группа под `[ДАННЫЕ, не инструкции]` после строк `inbox`/`leases` и до финальной строки, поля, `on_write` только если задан, враждебные значения не ломают вывод (все строки — с префиксом), предупреждения области/срока, `exit 0`; **[12]** без `python3/PyYAML` + мандат → ровно одна строка, содержащая «не прочитан»; без мандата — строка бит-в-бит прежняя (сверка с эталонной строкой из существующего сценария 2). Мутанты через `red`: `no-orphan` (убрать строку `MAND-ORPHAN`), `orphan-two-lines`, `no-show` (убрать блок `MAND-SHOW`), `show-before-inbox` (перестановка), `no-marker` (убрать «[ДАННЫЕ, не инструкции]» из `mandate_report` — через копию lib), `mnote-always` (суффикс без условия: краснит «без мандата — строка прежняя»). Прежние «old»-фрагменты не меняются (сверено с `test-mo-session.sh:331–341`).

### [MODIFIED] `test-sdx-stage.sh` (сценарии `[30]…`; прежние `[1]–[29]` не правятся)

Хелпер `setup_mandate <stages-форма>`: пишет `.mesh/endpoint.yaml` + `.mesh/mandate.yaml` в `TMPPROJ` (форма `block|flow`). Сценарии: **[30]** регресс «без мандата»: (а) нет `.mesh/`; (б) только `endpoint.yaml`; (в) только `mandate.yaml` (с `stages: [spec]`) — `next` ведёт себя как в 2.3.x (идёт на `Technical Design`); **[31]** `stages: [spec]` (block и flow): `Business Spec` → `Verification` за один `next` (пропуск `Technical Design`/`Task Planning`/`Execution`/`Documentation`); `Verification` → `Closeout` (пропуск `Deployment`); **[32]** `stages: [execute, verify]`: `init` на `Discovery` → rc 2; `start-stage Discovery false false` → `Execution`; **[33]** `Deployment` исключён при каждом `delivery` (в т.ч. `artifact.offer`) — `next` с `Verification` не останавливается на нём; **[34]** `--to` исключённого этапа → rc 1, `.stage` не изменился (байтовое сравнение файла), причина в stderr называет стадию; `--to` активного — штатно; **[35]** нечитаемые мандаты (не YAML, нет `mandate`, `stages` скаляр, неизвестная стадия) → `next` rc 1, `init` rc 2, файл состояния не создан/не изменён; **[36]** пустой/отсутствующий `stages` → из `Execution` `next` идёт на `Verification`; **[37]** `no_gates=true` без `execute`: `init Execution` → rc 2, `start-stage … true` → rc 1; с `execute` — штатно; `next` у существующей `no_gates`-сессии — `OK no-op Execution` независимо от мандата (приоритет 0); **[38]** `no_code`-тип + `stages: [execute, verify]`: `start-stage Discovery true false` → `Verification`; **[39]** `active-set` (источники `no_code`, `no_gates`, `mandate(spec)` и т.д.) и **[40]** read-only: `start-stage`/`active-set` не меняют ни одного файла (снимок `find|cksum`). **Мутационная секция [41]** (в этом сьюте мутантов раньше не было — вводится с хелпером копирования `sdx-stage.sh` + `lib/` в temp): `MAND-MODE` (режим без `endpoint`), `MAND-EXCL` (мандат не исключает), `MAND-SKIP` (цикл не пропускает), `MAND-DEPLOY` (Deployment допущен), `MAND-TO` (нет отказа для `--to`) — каждый краснит свой сценарий. Время: сценарии оперируют крошечными каталогами (≈ +2 с).

### [MODIFIED] `test-mo-prose.sh` (grep-инварианты с красной стороной на повреждённой копии)

`[9]` «два признака»: `protocol.md`, `docs/designs/mo-interop.md`, `README.md`, `README.en.md`, `docs/DECISIONS.md` (ADR-021 п.3) содержат `mandate.yaml` в формулировке признака и **не** содержат «единственный признак»/«единственным признаком»; `[10]` `agents/devops.md`: `mandate.yaml`, `scope.branches`, `теги`, сохранён переключатель `endpoint.yaml` и `PYTHONDONTWRITEBYTECODE=1`; `[11]` сниппет: одно предложение о `.mesh/mandate.yaml`, нет `/sdx:pr`, маркеры `SDX:BEGIN`/`SDX:END` на месте; `[12]` `commands/archive.md` и протокол: `bridge`, `(n/a, мандат)`, `closeout-check`, `archive-verify.sh` не вызывается при мандате, `change/<C>-<exec>`; `[13]` `commands/verify.md`: `mandate-scope.sh`, `--into`, `--planned`; `[14]` `commands/start.md`: `mandate-info.sh show`, `start-stage`; `[15]` протокол «Активность этапа» упоминает мандат как третий сужающий источник и `Deployment` исключён при мандате, а абзац «`Deployment` под МО» сохраняет слова `Deployment`/`artifact.offer` (инвариант прежнего `[5b]`); `[16]` `docs/DECISIONS.md`: поправки к ADR-020 и ADR-021 датированы; `[17]` `plugin.json` `version` = 2.4.0. Красная сторона каждого — как в файле: проверка той же функцией на повреждённой копии.

### Бюджет времени (REQ-MAND-32)

Прирост (оценка по аналогии с текущими замерами): `test-mandate-lib` ≈ 5–8 с (корпус + оракул-процессы Python — один вызов на корпус), `test-mandate-scope` ≈ 4 с, `test-suites-gen` ≈ 5 с (близнец с `stop-gate.sh` — 5 запусков), `test-snippet-check` ≈ 1 с, `test-mo-hook` +4 с, `test-mo-session` +3 с, `test-sdx-stage` +3 с, `test-mo-prose` +1 с. Итого ≈ +25–30 с к ≈ 78 с → ≈ 105 с при пределе 180 с (запас ≈ 75 с). Контроль — прогон `verify-cmd.sh` с замером; комментарий в `.claude/sdx/verify-cmd.sh` (строки 5–6: «~60 секунд, 15 сьютов») актуализируется по факту прогона.

## Обратная совместимость (REQ-MAND-1, 31) — доказательство по построению

Каждая новая ветка стоит за предикатом «оба файла `.mesh/endpoint.yaml` и `.mesh/mandate.yaml` существуют»:

| Компонент | Гейт | Что подтверждает, что без мандата ничего не изменилось |
|---|---|---|
| `sdx-stage.sh` | `mandate_gate_load` возвращает 0 до подключения lib; `is_excluded_by_mandate` при `MANDATE_ON=0` ложна; `is_skipped` ≡ прежнему условию цикла | существующие `[1]–[29]` (726 строк) без правок + новый `[30]` (три варианта «нет мандата») |
| `mo-hook.sh` | вторая строка режима читает файл только если он есть; охрана `mandate.yaml` — единственное **безусловное** новое поведение (К-4) | `[1]–[13]` без правок: тексты отказов `endpoint/cursors` не менялись; `[2m]` строка «нет файла» |
| `mo-session.sh` | `MAND-ORPHAN` печатает только при наличии `mandate.yaml`; `MAND-SHOW` — только при нём; суффикс `mnote` пуст без мандата | существующие сценарии 1–9 без правок + мутант `mnote-always` |
| команды | `mandate-info.sh show` при `none` ничего не печатает; `start-stage` без мандата возвращает входной этап (если он не исключён `no_code`/`no_gates`, иначе — прежний отказ делает `init`); `verify.md` шаг 6а и `archive.md` ветка `bridge` — по `mode`/`closeout-mode` | `test-sdx-stage [30]`, `test-mandate-scope (1)` |
| `stop-gate.sh`, `archive-verify.sh`, `hooks.json` | не меняются | `test-stop-gate.sh`, `test-archive-verify.sh`, `test-hook-wiring.sh`, `test-selftest.sh` зелёные без правок |

Отступы от «бит в бит» ровно те, что названы SPEC (REQ-MAND-1 (а), (б)) **плюс два, найденные при проектировании** и вынесенные в К-4 и К-10: (1) охрана записи `mandate.yaml` действует независимо от наличия мандата; (2) usage-строка `sdx-stage.sh` при неверной подкоманде перечисляет `start-stage|active-set`.

## Альтернативы (отвергнутые)

- **Читать мандат Python'ом в `mo-session.sh`.** Отвергнуто (D-1): два парсера, два набора расхождений с `safe_load`; `sdx-stage.sh` всё равно bash.
- **Снимок мандата в `session_state.json`** (расширение схемы, сигнатуры `init`, правки `start/import/proto`). Отвергнуто (В12/В13): расширяет единственного писателя `stage`; мандат вне git и всё равно может быть переиздан узлом.
- **Подключать `lib/mandate.sh` из `mo-hook.sh`.** Отвергнуто (D-2): ломает автономность файла, мутанты `[13]` и тест портируемости.
- **Рефакторинг `stop-gate.sh` на общий резолвер.** Отвергнуто (D-7): `selftest.sh`/`test-selftest.sh` копируют `stop-gate.sh` и `lib/resolve-session.sh` в изолированный каталог — новый `source` потребовал бы правок периметра self-test, который в поставку не входит (DEBT-043, вторая часть).
- **Поручить находку области ревьюеру.** Невозможно: нет `Bash` (контракт изоляции), и ревьюер не должен выводить детерминированный факт «на глаз».
- **Проза вместо `suites-gen.sh`.** Отвергнуто (В14): неповторяемо и не тестируется.

## Коллизии и вопросы (к решению; молча не решались)

- **К-1. REQ-MAND-6 «ни `.claude/sessions/`, ни `docs/`» против логики риска.** *(Принято: отдельная строка на каждый непокрытый каталог — реализовано в `mandate_report`.)* Буквально «оба не покрыты» почти никогда не срабатывает: мандат узла всегда подставляет `docs_paths: [docs/**]` (`DEV:529`) → `docs/` покрыт. Реальный риск — непокрытый `.claude/sessions/`. **Предложение (реализовано в дизайне):** предупреждать **по каждому** непокрытому каталогу отдельно (одна строка, названы оба при необходимости); частный случай «оба» входит в него. Критерий приёмки 4 («область без `.claude/sessions/` / `docs/`») этому не противоречит.
- **К-2. REQ-MAND-4 (без `python3/PyYAML` мандат не показывается) против D-1.** Раз парсер на bash, показ мандата в вырожденном режиме технически возможен (и там нужнее всего: при `deny` и недоступном python хук блокирует **каждый** вызов). **Предложение:** следовать утверждённому SPEC (суффикс «не прочитан», строка остаётся одной); улучшение — отдельным решением, не молча. *(Поправка круга 3 верификации, 2026-10-29: К-2 принята иначе: мандат читается bash-парсером, суффикс «читается без python3 и показан ниже»)*
- **К-3. REQ-MAND-14 («переносы Closeout входят в проверяемый диф») против времени.** Verification идёт до Closeout; коммитов переносов в `git diff main...sdx/<id>` ещё нет. **Предложение (реализовано):** ключ `--planned` с правилом вычисления из набора артефактов сессии (`verify.md` шаг 6а) — `FAIL` по запланированному переносу вне `docs_paths`. Остаточный риск: `docs/DECISIONS.md` попадает в список по суждению оркестратора («есть ли ADR») — при сомнении включать.
- **К-4. REQ-MAND-17 (охрана `mandate.yaml` «в обоих режимах») против REQ-MAND-1.** Обёртка активна лишь при `endpoint.yaml`; если мандата ещё нет, запись нового `.mesh/mandate.yaml` сессией раньше проходила, теперь блокируется. **Предложение:** охранять безусловно (создание мандата сессией — ровно та атака, от которой охрана), добавить это третьим названным исключением REQ-MAND-1. Нужно подтверждение.
- **К-5. `delivery: patch|worktree`** (допустимы по `DEV:24`) в SPEC для моста Closeout не определены. **Предложение:** `closeout-mode` → `undefined:<delivery>`, `archive.md` останавливается и спрашивает пользователя (стоп-рубрика «контракт»); `artifact.offer` — штатный Closeout по SPEC. *(Поправка круга 3 верификации, 2026-10-29: `artifact.offer` — НЕ штатный Closeout: мост `bridge:offer` (шаг отправки оффера один раз), см. SPEC REQ-MAND-23 / критерий 16)*
- **К-6. Семантика `docs_in_repo` (`final|full|none`)** в `MI` §7 не раскрыта. **Предложение:** `none` → переносы `docs/specs|designs|DECISIONS` — `(n/a, docs_in_repo: none)`; `final`/`full` — штатный перенос шага 2 (различие `full` SDX не реализует); вопрос владельцу МО, выпуск не блокирует.
- **К-7. Коды отказа.** `next` при нечитаемом мандате — 1, `init` — 2: объяснено (rc `init` всегда 2; `next` 1 = «исправимо пользователем, чек-лист Closeout не начинается»). Согласовать при ревью.
- **К-8. Разбор мандата и `safe_load`** (REQ-MAND-10 «тот же результат»). Три класса входа, где `safe_load` принимает, а подмножество отказывает: дубликат ключа, flow-словарь, якорь/алиас (и любой иной синтаксис вне подмножества). **Предложение:** принять (fail-closed безопасен; узел такого не порождает), зафиксировать в протоколе как границу.
- **К-9. REQ-MAND-33** разрешает PyYAML в `mo-session.sh`; дизайн не использует его нигде в рантайме (только как проверку «доступен ли хук sim-kit» и оракул тестов) — строже, чем требует SPEC.
- **К-10. Usage-строка `sdx-stage.sh`** при неизвестной подкоманде меняется (`<init|next|start-stage|active-set>`); существующих тестов на неё нет. Если требуется бит-в-бит — оставить прежнюю строку и документировать новые подкоманды только в протоколе (дешёвая альтернатива).
- **К-11. Посторонние файлы:** в рабочем дереве есть неотслеживаемый пустой `sdx/hooks/false`, а в корне репозитория — отслеживаемый пустой файл `false` (оба создаются, судя по всему, опечаткой редиректа). К поставке не относится; помечено для решения на Closeout (бэклог), дизайном не затрагивается.
- **К-12. Предупреждение области зависит от `on_write` не в самой строке**: при `notice` хук лишь шлёт `scope.write` в ящик; строка предупреждения одинакова в обоих режимах (упоминание `deny` остаётся условным).

## Границы и риски

- **Разбор мандата — подмножество YAML.** Отличие от `safe_load` только в сторону отказа (К-8); для узла дамп стабилен (`safe_dump(sort_keys=False)`). Риск: будущая версия sim-kit добавит тип значения, который подмножество не знает → гейт откажет (громко, с причиной) до правки lib — приемлемо при fail-closed; защита — сверка корпуса при каждом перевендоринге (добавить фикстуру реального дампа в `test-mandate-lib` L3 при обновлении `sdx/mo/`).
- **Мягкая граница хука и жёсткая проверка `verify` — разные правила** (`_in_scope` против `glob_any`+`docs_paths`); расхождение — не дефект, объясняется в протоколе; сверочные случаи эталона закрепляют `verify`.
- **Обёртка (`mode_re`) и хук (`safe_load`) могут видеть мандат по-разному** на экзотическом YAML; тест `[2m]/[8i]` на реальных формах дампа.
- **Охрана `Bash`-путей к `mandate.yaml` отсутствует** (названная граница; обнаружение — у узла по `digest`).
- **Переиздание мандата в середине сессии** меняет гейт со следующего вызова; смена `digest` SDX не отслеживает (В13).
- **Канал SessionStart не проверен** (DEBT-045): показ дублируется на `/sdx:start`; гейт от этого не зависит.
- **Мост Closeout — временная ручная граница до `FEAT-017`:** пакет `change/<C>-<exec>` собирает пользователь; ветка `sdx/<sid>` копится до аудита узла.
- **Время прогона:** ≈ 105 с ожидаемо при пределе 180 с; нарушение краснит каждый ход stop-gate — контролируется замером до Closeout.
- **Территория PROC-020:** поставка не в `gate_mode: auto`.
- **Параллельные поставки:** `FEAT-017` будет расширять `mandate.sh` (`touches_shared`, `work.order`) — функции спроектированы вызываемыми по отдельности.

## Ручной сценарий для Verification

Автотестами **не** проверяются (и проверяются честно только на бинарнике/вручную):

1. **Канал SessionStart для модели** (DEBT-045): запустить настоящий `claude` в проекте-фикстуре с `.mesh/endpoint.yaml` + `.mesh/mandate.yaml`, в первой же реплике спросить модель, какие стадии у неё в мандате, не вызывая `/sdx:start`. Ожидаемый результат — «не проверено» либо ответ; **вывод `/sdx:start` — гарантированный канал**, и именно он проверяется.
2. **Реальный мандат узла** (критерий 7, паритет формы): выдать мандат `./mo mandate issue` на локальный чекаут sim-kit 0.9.1 в проект-фикстуру и прогнать `sdx-stage.sh start-stage/next` и `mandate-info.sh show` на этом файле. Если выдача неудобна — `python3 -c 'import sys; sys.path.insert(0,"<sim-kit>/core"); …dev.mandate_yaml("<executor>")'` (точная команда **не проверена** проектированием; нужен реестр узла).
3. **`dev.py run_suites` читает `tests/suites.yaml`** (критерий 14): на чекауте sim-kit 0.9.1 вызвать `run_suites("audit", <repo>, [])` (или `run_suites` через `./mo`-обвязку) — реальный прогон набора `unit` займёт полный `verify-cmd.sh` (≈ 1.5–2 мин); допустимо подменить `cmd` на `true` во временной копии и проверить, что именно структура читается без `ok: False`/`нет в tests/suites.yaml`. Команда не проверена мной.
4. **Мост Closeout `delivery: pr`** (критерий 16): прозаическая часть `archive.md` проходится на одноразовой сессии с мандатом: шаги 1–5, `(n/a, мандат)` на 6–8, `closeout-check` зелёный, ветка `sdx/<sid>` осталась. Детерминированная часть (`closeout-mode`/`closeout-check`) покрыта автотестом, **проза — нет**.
5. **Взаимодействие двух PreToolUse на `Bash`** с мандатом (`prod-guard` + `mo-hook`) — из ручного сценария FEAT-015; повторить с `mandate.on_write: deny` и записью вне области.

## Трассировка REQ → компонент → тест

| REQ-MAND | Компонент | Тест |
|---|---|---|
| 1 | все гейты «оба файла»; разд. «Обратная совместимость» | все прежние сьюты без правок; `test-sdx-stage [30]`; `test-mo-session [12]` (строка без мандата); `test-mo-hook [7m]` (текст `endpoint/cursors`); `test-mandate-scope (1)` |
| 2 | `mandate_mode` | `test-mandate-lib L7`; `[8h3]`, `[2m]` (mandate без endpoint) |
| 3 | `MAND-ORPHAN`, `mandate_orphan_line`, `mandate-info show` | `test-mo-session [10]` + мутанты `no-orphan`/`orphan-two-lines`; `test-mandate-lib L7` |
| 4 | `MAND-SHOW`, `mandate_report`, суффикс `mnote` | `test-mo-session [11]`, `[12]` + мутанты `no-show`/`show-before-inbox`/`no-marker`/`mnote-always`; `L8` |
| 5 | `commands/start.md` шаг 1а, `mandate-info.sh show` | `test-mo-prose [14]`; `test-mandate-lib L8` (тот же текст) |
| 6 | `mandate_report` (предупреждение области, К-1) | `L8` + мутант `MAND-SCOPE-WARN` |
| 7 | `mandate_expired`, `mandate_report`, блок `mandate-scope` | `L6` + мутант `MAND-EXPIRY`; `test-mandate-scope (10)` |
| 8 | `mandate_stage_class/allowed`, `is_skipped` | `test-sdx-stage [31][32][36]`, `L4` + мутанты `MAND-SKIP`, `MAND-EXCL` |
| 9 | класс `always`/`never` | `[33]`, `L4` + мутанты `MAND-NEVER`/`MAND-ALWAYS`/`MAND-DEPLOY`; `test-mo-prose [15]` |
| 10 | `miniyaml.sh`, `mandate_load` | `L1`–`L3`, `[35]` + мутанты `MAND-ROOT`/`MAND-UNKNOWN`/`MAND-FLOW`; паритет `L2` |
| 11 | `--to`-проверка, `init`-проверка, `start-stage` | `[34]`, `[37]`, `[38]` + мутант `MAND-TO` |
| 11a, 28 | `docs/DECISIONS.md` поправки; протокол | `test-mo-prose [16]` |
| 12 | `mandate-scope.sh`, `mandate_glob_*` | `test-mandate-scope (2)(5)(9)`, `L5` + мутанты `MAND-GLOB-*`, `MAND-OUTSIDE` |
| 13 | `mandate-scope.sh` (исходы, пустой `paths`, `shared`) | `(2)(3)(4)` + мутанты `MAND-SHARED`, `MAND-EMPTY-PATHS` |
| 14 | `--planned`, `verify.md` шаг 6а | `(6)` + мутант `MAND-PLANNED`; `test-mo-prose [13]` |
| 15 | ранний возврат `mandate-scope.sh` | `(1)` |
| 16 | `MAND-MODE2` в `mo-hook.sh` | `[2m]`, `[8i]` + мутант `MAND-MODE2` |
| 17 | `MO-GUARD-MANDATE`, `is_mailbox_file` | `[7m]` + мутанты `MAND-GUARD-MANDATE`, `MAND-NAME` |
| 18–20 | `suites-gen.sh`, `lib/test-cmd.sh`, `init.md`, `reconcile.md` | `test-suites-gen` (1)–(7) + мутанты `SG-*` |
| 21 | `tests/suites.yaml` | `test-suites-gen (8)(9)` + ручной п.3 |
| 22 | `agents/devops.md` | `test-mo-prose [10]` |
| 23 | `mandate-info.sh closeout-*`, `archive.md`, протокол | `test-mandate-scope [M]` (`closeout-mode`/`closeout-check`, мутанты `MAND-BRIDGE`/`MAND-CHECK-*`) + `test-mo-prose [12]`; ручной п.4 |
| 24 | сниппет | `test-mo-prose [11]` |
| 25 | `snippet-check.sh`, `reconcile.md` | `test-snippet-check` + `test-mo-prose` (категория в `reconcile.md`) |
| 26 | `mandate-info.sh status`, `sdx-stage.sh active-set`, `status.md` | `[39][40]`; `test-mandate-scope [M]` (строка `status`); проза `status.md` — ревью |
| 27, 29 | протокол, README×2, CLAUDE.md, дельты `docs/specs|designs/mo-interop.md`, запись `FEAT-016` | `test-mo-prose [9]`; `test-mo-inventory.sh` зелёный |
| 30 | `plugin.json` 2.4.0, релизные заметки | `test-mo-prose [17]` |
| 31 | — | `verify-cmd.sh` полный |
| 32 | комментарий `verify-cmd.sh` | замер полного прогона |
| 33 | отсутствие python в `sdx-stage.sh`/lib | `L9` + `grep -n python3 sdx-stage.sh lib/*.sh` пусто (инвариант в `test-mandate-lib`); `test-mo-inventory.sh` (`sdx/mo/*` без правок) |

## Перечень правок документов (REQ-MAND-27…30)

- **`sdx/protocol.md`:** (1) «МО-хук» — «два признака»: `endpoint.yaml` — стенды (0.7.x, FEAT-015), `mandate.yaml` — процесс изменений (0.9); новый подраздел «Мандат» (признак, показ, гейт стадий, область `verify`, мост Closeout; различие `_in_scope` и `glob_any`); границы (а)–(д): (д) снимается, (а) дополняется `mandate.yaml`; (2) «Активность этапа» — третий источник сужения (мандат), порядок приоритета: `no_gates` → флаги/мандат → объём дельты; абзац «`Deployment` под МО`: при мандате исключён всегда, `artifact.offer` — на `Execution`/`Verification`, для `endpoint.yaml` без мандата норма прежняя»; (3) «Механизм перехода» — `start-stage`, `active-set`, коды отказа мандата; (4) «Closeout» — ветка `bridge`; (5) ссылки «MI §6 мандат» → §7. *(Поправка круга 3 верификации, 2026-10-29: то же: оффер один раз на шаге моста Closeout, при отправленном — пропуск `(уже отправлен: <msg_id>)`)*
- **`docs/DECISIONS.md`:** датированная поправка к ADR-020 («мандат МО — третий сужающий источник активного набора; `Deployment` при мандате исключён»), датированная поправка к ADR-021 (три слоя границы; снятие (д); п.3 «два признака»; п.7 — для `endpoint.yaml` без мандата).
- **`docs/specs/mo-interop.md`, `docs/designs/mo-interop.md`:** переносятся дельты этой поставки; убирается «промежуточная граница до `FEAT-016`» (пункт (7) поправки в шапке дизайна; границы в SPEC `:120–130`); `:39` и `:280` дизайна — «два признака».
- **`README.md` / `README.en.md`** (согласованная пара): абзац про активацию МО-хуков → «два признака»; перечень файлов `sdx/hooks/` и `tests/suites.yaml`; запись о версии 2.4.0.
- **`CLAUDE.md`:** §6 — перечень `sdx/hooks/` (lib, `mandate-*`, `suites-gen`, `snippet-check`) и `tests/suites.yaml`; формулировка МО-слоя — «два признака» (§3 упоминания МО нет — править нечего, кроме того, что есть).
- **`docs/backlog/FEAT-016-…md`:** ДЛ-1 (Deployment по эталону), ДЛ-2 (имена `unit/module/regression`), 0.9.1 вместо 0.9.0, «389» → без числа; на Closeout `status: closed`, `session`.
- **Новые записи бэклога на Closeout:** записка upstream (`.claude/sessions/**` в дефолтном `docs_paths`; ссылки на `/sdx:pr` в §6 эталона), `К-11` (посторонние `false`), вопросы К-5/К-6 владельцу МО.
- **`.claude-plugin/plugin.json`** → `2.4.0`; релизные заметки — двуязычные накопительные (русский блок, `---`, английский; раздел «Границы» с непроверенным: канал SessionStart, `run_suites` вживую, ручной мост Closeout); тег `v2.4.0` на merge-коммите; push/релиз — только по явной просьбе.

## Декомпозиция для PLAN (порядок и критерий готовности)

1. `miniyaml.sh` + `mandate.sh` + `test-mandate-lib.sh` (L1–L9, мутанты) — готово, когда L-сценарии и мутанты зелёные.
2. `sdx-stage.sh` (гейт, `start-stage`, `active-set`) + `test-sdx-stage [30]–[41]`.
3. `mandate-info.sh`, `mandate-scope.sh` + `test-mandate-scope.sh` (в т.ч. блок `closeout`).
4. `mo-hook.sh` (`MAND-MODE2`, `MO-GUARD-MANDATE`) + расширения `test-mo-hook.sh`.
5. `mo-session.sh` + расширения `test-mo-session.sh`.
6. `lib/test-cmd.sh`, `suites-gen.sh`, `tests/suites.yaml`, `snippet-check.sh` + `test-suites-gen.sh`, `test-snippet-check.sh`.
7. Проза: команды, `devops.md`, сниппет, протокол + `test-mo-prose [9]–[17]`.
8. Документы, версия, бэклог, комментарий `verify-cmd.sh`; полный прогон с замером ≤ 120 с (ориентир) и ≤ 180 с (предел).
Порядок 1→2→3 обязателен (зависимости); 4, 5, 6 независимы после 1.
