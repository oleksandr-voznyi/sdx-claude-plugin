# DESIGN (архив сессии): feat-017-mo-change-package-20261031

> Полный DESIGN сессии с датированными пометками кругов верификации; сжатый перенос — `docs/designs/mo-interop.md` («Дельты FEAT-017»).

# Technical Design: FEAT-017 — сдача пакетом изменения (плагин 2.5.0 «`/sdx:pr`»)

status: draft (Technical Design, сессия `feat-017-mo-change-package-20261031`; вход — утверждённый `SPEC.md` REQ-PKG-1…35 с дефолтами раздела «Открытые вопросы», `context_report.md`, `decisions_log.md`)

Условные обозначения. `SK` = `/home/archi/Code/aibok/agentico/meta-orchestrator/sim-kit/` (внешний эталон, читался как данные), `DEV` = `SK/core/dev.py`, `MI` = `sdx/mo/MO-INTEROP.md` (0.9.1). `ДЛ` = `decisions_log.md`. `К-N` — пункты раздела «Коллизии и вопросы». Якоря `# PKG-*` в коде — метки для мутационных прогонов (как `# MAND-*`). Образец формата и дисциплины — `docs/history/designs/feat-016-mo-mandate-20261028.md`.

Что проверено прогоном до написания (скретч вне репозитория, не часть поставки):
(а) сборка пакета чистым plumbing на фикстуре — `commit-tree` от дерева `sdx/<sid>` с родителем `base`; манифест через временный индекс (`GIT_INDEX_FILE` + `read-tree` + `update-index --add --cacheinfo` + `write-tree` + `commit-tree`); `update-ref` с «старым значением» из нулей отказывает на существующей ветке; рабочее дерево, индекс и текущая ветка не менялись (`git status` пуст, `HEAD` = `sdx/s1`); `git archive` от `head` даёт одну и ту же сумму в рабочем клоне и в независимом клоне; `git merge-tree --write-tree` есть в git 2.53 (машина автора);
(б) `yaml.safe_dump` (формат `work.order`, `DEV:552`) **переносит** длинные значения (`title`, `requirements`, элементы списков) на следующие строки и ставит одинарные кавычки при `: ` — `miniyaml.sh` такой вход отвергает («кавычка не закрыта»). Прототип awk-«распрямителя» (раздел `order-import.sh`) + `miniyaml` совпал с `yaml.safe_load` на 367 сгенерированных дампах (167 с переносами), расхождений 0; двойные кавычки с переносом — отказ по построению;
(в) `sha256(CHANGE.template.yaml)` рабочей копии `SK/` = `346d2e6e…fd5cd` = содержимое тега `sim-kit-0.9.1` (`git show sim-kit-0.9.1:./CHANGE.template.yaml`, из каталога `sim-kit/` — репозиторий лежит выше) — вопрос Q-14 Discovery закрыт фактом;
(г) `marketplace.json` поля `version` не содержит — версию правит только `plugin.json`.

## Архитектурный обзор

Поставка — детерминированный слой «сборка → проверка → публикация» вокруг одной новой команды `/sdx:pr`, плюс приём заказа и экспорт протокола. Всё включается **только в режиме мандата** (`.mesh/endpoint.yaml` + `.mesh/mandate.yaml`) и только при `delivery: pr|branch`; вне мандата все прежние команды и сьюты не меняются (REQ-PKG-34).

Принятые архитектурные решения (альтернативы — в разделе «Альтернативы»):

- **D-1. Пакет собирается чистым git-plumbing, без `checkout`.** Рабочее дерево, индекс и текущая ветка `sdx/<sid>` не трогаются ни на одном шаге (R-1, R-2, критерий «дерево чистое после `/sdx:pr`»). Дерево squash-коммита: если `base` — предок `sdx/<sid>` (норма), то это **дерево вершины `sdx/<sid>`** (оно уже без каталога сессии после шага 5), родитель — `base`; иначе (ветка вырезана не от `base`) — результат `git merge-tree --write-tree base sdx/<sid>` и только после подтверждения пользователя (`--allow-diverged`).
- **D-2. Манифест — отдельный последний коммит через временный индекс.** `CHANGE.yaml` создаётся `git hash-object -w --stdin`, кладётся в *временный* индекс поверх дерева `head`, коммит `commit-tree -p head`. Файла `CHANGE.yaml` в рабочем дереве никогда нет — хук области (`on_write: deny`, R-2) срабатывать не на что. Ветка создаётся `git update-ref refs/heads/change/<C>-<exec> <tip> <старое значение>` (создание — «старое» = нули: существующую ветку молча перезаписать невозможно).
- **D-3. Манифест порождается обходом вендорённого шаблона.** Список и порядок ключей берутся из `sdx/mo/CHANGE.template.yaml`; значения — из вычисленного JSON; ключ шаблона, неизвестный `pr-build.sh`, — отказ «обновите плагин» (дрейф шаблона при перевендоринге ловится сразу, а не молчаливой утерей поля). Строки рендерит `jq` (`tojson` ⊂ YAML double-quoted) — экранирование чужих значений не пишется руками (REQ-PKG-10). Все строки в кавычках (в т.ч. 12-hex `mandate_digest`, который голый YAML прочёл бы числом).
- **D-4. Одна библиотека `lib/pr-lib.sh`, два независимых оракула в тестах.** `pr-build`, `pr-check`, `pr-publish` разделяют вычисление имени ветки, `base`, области, реестра ADR. Единственность реализации — риск «обе стороны ошибаются одинаково»; его закрывают тесты: (i) независимый python-оракул `audit()` (транслитерация `DEV:340–424`, INFO-skip без PyYAML), (ii) независимый пересчёт `archive_sha256` в отдельном клоне, (iii) статические таблицы `glob_any` уже закреплены `test-mandate-lib`.
- **D-5. Данные заказа переживают шаг 5 в истории git, а не во внешнем состоянии.** `pr_session_rev` находит коммит, где ещё был каталог сессии (`HEAD`, либо родитель коммита, удалившего `session_state.json`), и читает `order.yaml`/`verification_report.md`/`change_note.md` через `git show` (REQ-PKG-4). Никакого нового хранилища «после сессии».
- **D-6. Результат сдачи — пустой служебный коммит с трейлерами на `sdx/<sid>`.** Каталога сессии нет, значит писать в `change_note.md`/`session.log` некуда; возвращать файл в `.claude/sessions/` нельзя (`closeout-check`, инвариант 6, и повторный squash получил бы файл в net-diff), класть в `docs/history/` нельзя (уходит в репозиторий заказчика). Пустой коммит не меняет дерево, не попадает в пакет, переживает `clone`, читается `git log --grep` (`mandate-info.sh pr-status`). `git notes` отвергнуты (не клонируются и не показываются по умолчанию) — К-2, К-16.
- **D-7. `pr-check` — две фазы, три исхода.** `pre` (до сборки: дерево, ветка, срок, область по предсказанному диффу, реестр ADR, тесты, URL) и `post` (после сборки: структура пакета, манифест против пересчёта). Исходы: `PASS` (rc 0), `WARN n` (rc 3: нет `FAIL`, нужны явные подтверждения), `FAIL n` (rc 1: push блокируется без права обхода). Красный тест не создаёт ветку (нет «хвостов» к откату).
- **D-8. Публикация — узкая и недоверчивая.** Явный refspec `refs/heads/change/<C>-<exec>:refs/heads/change/<C>-<exec>` (без `+`), whitelist схем URL, `GIT_ALLOW_PROTOCOL`, `-c push.followTags=false -c push.default=nothing`, fast-forward-проверка по `ls-remote`, силового режима в 2.5.0 нет (К-3), внутренний прогон `prod-guard.sh` на синтезированной команде `git push …` (внутри скрипта хук `PreToolUse` команду не видит), `gh` — необязательное улучшение с деградацией до `bare`.
- **D-9. Заказ — три канала, один нормализованный снимок.** JSON (конверт `inbox --json`, тело `body`) разбирает `jq`; YAML-файл и YAML-блок issue — `order-unfold` (awk, распрямление переносов `safe_dump`) + `miniyaml` (названная граница: двойные кавычки с переносом, блочные скаляры `|`/`>`, пустая строка внутри значения, якоря, список словарей, flow-словарь — отказ с причиной). Выход — `order.yaml` сессии в *нашем* формате (все скаляры в одну строку в кавычках — его потом читает `miniyaml` без распрямления) и flat-JSON для команды. PyYAML в рантайме не требуется.
- **D-10. `protocol.yaml` — экспорт двух форматов журнала.** Нормативный блок `### Развилка:` и фактически применяемая строка `- [YYYY-MM-DD ][тег] текст` (тег в квадратных скобках; нотация единая во всех носителях, круг 3) (этой сессии) читаются одним `awk`; рендер — `jq`. Пустые/отсутствующие источники → пустые списки.
- **D-11. `commitment` пишется отдельным `jq` после `init`** (`order-import.sh stamp-state`), сигнатура `sdx-stage.sh init` (7 позиционных) и единственный писатель `stage` не меняются; `write_stage` правит только `.stage`, поле переживает переходы (проверяется тестом).
- **D-12. Единый вход Closeout под мандатом.** `commands/archive.md` в режиме `bridge` (`pr|branch`) после общей прелюдии (гейт входа, цикл `next` до `Closeout`) передаёт управление процедуре `commands/pr.md`; `/sdx:pr` вызванная напрямую выполняет ту же прелюдию по ссылке на `archive.md` *(2026-10-31, круг 3 верификации: на любом `stage`, включая `Closeout`; гейт входа — дисклоуз `auto_decisions.md` при `auto`, отказ при `no_gates` — проходится всегда; цикл `next` при `Closeout` — штатный no-op; см. «Поправки круга 3 верификации»)*. Текст шагов 1–5 живёт в одном месте (`archive.md`), `pr.md` его не дублирует. Токен `closeout-mode = bridge` сохраняется (К-7).

### Новые и изменяемые файлы (сводка)

| Файл | Тип | Назначение |
|---|---|---|
| `commands/pr.md` | ADDED | конвейер `/sdx:pr` (REQ-PKG-1…7, 13, 17, 18) |
| `sdx/hooks/lib/pr-lib.sh` | ADDED | общая библиотека: идентификаторы, `base`, история сессии, область, реестр ADR, URL, секреты |
| `sdx/hooks/pr-build.sh` | ADDED | squash + манифест + ветка (REQ-PKG-5, 6, 8, 9, 10) |
| `sdx/hooks/pr-check.sh` | ADDED | фазы `pre`/`post`, зеркало формальных проверок `audit()` (REQ-PKG-11, 12, 26, 27) |
| `sdx/hooks/pr-publish.sh` | ADDED | push по явному refspec, `gh pr create`, деградация (REQ-PKG-13…16, 18, 35) |
| `sdx/hooks/protocol-export.sh` | ADDED | `protocol.yaml` из журналов (REQ-PKG-19…22) |
| `sdx/hooks/order-import.sh` | ADDED | приём заказа (файл / конверт / issue), `stamp-state` (REQ-PKG-23…25) |
| `sdx/hooks/mandate-info.sh` | MODIFIED | `pr-mode`, `pr-status` (добавлением; `closeout-mode`/`closeout-check` не меняются) |
| `sdx/hooks/lib/mandate.sh` | MODIFIED | `mandate_fnmatch` (чистый `fnmatch` узла для `scope.branches`) |
| `sdx/mo/CHANGE.template.yaml`, `sdx/mo/SIMKIT_SHA256` | ADDED/MODIFIED | четвёртый вендорённый файл выпуска 0.9.1 (REQ-PKG-28), К-1 |
| `sdx/templates/CONTRIBUTING-MO.md` | ADDED | «как сдать изменение» для чужих харнесов (REQ-PKG-29) |
| `commands/{archive,start,status}.md` | MODIFIED | делегирование, `--from-order|--from-issue`, `commitment`/сдача в статусе |
| `agents/devops.md`, `sdx/templates/claude-md-snippet.md`, `sdx/protocol.md` | MODIFIED | проза (REQ-PKG-30, 32, 33) |
| `docs/DECISIONS.md` (ADR-022), `docs/specs\|designs/mo-interop.md`, `README.md`, `README.en.md`, `CLAUDE.md`, `docs/designs/decision-journal-and-resume.md` (поправка: поле `commitment`), `docs/backlog/FEAT-017-…md`, `docs/history/releases/v2.5.0-notes.md` | MODIFIED/ADDED | документы |
| `.claude-plugin/plugin.json` | MODIFIED | `2.4.0` → `2.5.0` |
| `sdx/hooks/lib/pkg-fixture.sh` | ADDED | общий тестовый помощник (фикстурный репозиторий пакета) |
| `sdx/hooks/test-{pr-build,pr-check,pr-publish,protocol-export,order-import}.sh` | ADDED | новые сьюты |
| `sdx/hooks/test-{mo-prose,mandate-scope,mandate-lib,sdx-stage,mo-inventory}.sh` | MODIFIED | только добавлением (кроме закреплённого текста моста — Q-17 SPEC) |

`hooks/hooks.json` **не меняется** (новых хуков нет). `stop-gate.sh`, `archive-verify.sh`, `sdx-stage.sh` *(2026-10-31, круг 1 верификации: одна строка текста отказа `next --to` исправлена попутно по DEBT-046 — см. «Поправки круга 1»)*, `mo-hook.sh`, `mo-session.sh`, `miniyaml.sh`, `lib/test-cmd.sh` не меняются. Инфраструктуры для DevOps (Docker/CI/деплой) нет; единственный пункт «для devops» — текстовая правка `agents/devops.md`.

## Компоненты и Интеграции

### [ADDED] `sdx/hooks/lib/pr-lib.sh` — общая библиотека (REQ-PKG-4, 5, 10, 12, 26)

`source`-библиотека; подключает `miniyaml.sh`, `mandate.sh`, `test-cmd.sh` по `${BASH_SOURCE[0]%/*}`. bash 3.2: без `declare -A`, `mapfile`, `${v,,}`, `timeout`, `%N`, **без массивов** (пустой массив под `set -u` падает в bash < 4.4; списки — строки, разделённые `\n`, как в `mandate.sh`). Функции:

```
pr_valid_id <str>           # rc 0 ⇔ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$, без "..", не оканчивается "." и ".lock"      # PKG-ID
pr_clean <str> [max=200]    # PR_CLEAN: перевод строки/табуляция -> пробел, остальные C0/DEL/U+2028/2029/0085 вырезаны, trim, усечение (контракт переопределён поправкой круга 1: C1 U+0080…U+009F и U+2028/2029 → пробел, прочие C0/DEL вырезаны)
pr_has_secret <str>         # rc 0 ⇔ совпал ERE зеркала REDACT[0] из sdx/mo/mesh_endpoint.py:35:                       # PKG-SECRET
                            #   (password|passwd|pwd|secret|token|api[_-]?key|client[_-]?secret)"?[[:space:]]*[:=]   (grep -Eiq)
pr_sha256                   # stdin -> hex; sha256sum | shasum -a 256 (как test-mo-inventory.sh); нет утилит -> rc 2
pr_session_rev <proj> <sid> # PR_SESS_REV = sha коммита, где ещё лежит .claude/sessions/<sid>/ (HEAD, либо родитель коммита,     # PKG-SESSREV
                            #   удалившего session_state.json на ветке sdx/<sid>); rc 1, если не найден
pr_sess_cat <proj> <sid> <name>   # содержимое файла сессии на PR_SESS_REV (git show), rc 1 если файла нет
pr_order_load <proj> <sid>  # my_load снимка order.yaml на PR_SESS_REV -> PR_O_COMMIT PR_O_TITLE PR_O_BASE PR_O_URL PR_O_HOSTING PR_O_BRANCH PR_O_EXEC PR_O_DIGEST (пусто, если снимка нет)
pr_resolve <proj> <sid> [--commitment C] [--title T] [--base-name B]
                            # PR_C PR_EXEC PR_BRANCH PR_TITLE PR_BASE_NAME PR_BASE_REF PR_BASE_SHA PR_URL PR_HOSTING_HINT PR_DELIVERY PR_DOCS_MODE PR_DIGEST;
                            # rc 0 | 1 (PR_ERR = «<поле>: <причина>»). Порядок источников — снимок заказа, аргумент (расхождение с
                            # непустым снимком — отказ, молчаливой подмены нет); <exec> — только mandate.executor
pr_base_ref <proj> <name>   # refs/heads/<name>, иначе refs/remotes/<remote>/<name>; PR_BASE_REF/PR_BASE_SHA; rc 1, если нет ни одного
pr_files <proj> <a> <b>     # git -c core.quotepath=off diff --name-only -z a b -> строки; путь с управляющим символом -> rc 1 (PR_ERR)
pr_scope_eval               # вход: $PR_FILES; выход: PR_OUT (вне mandate_in_union, только если paths непуст), PR_SHARED, PR_DOCSF,
                            #   PR_SESSF (пути под .claude/sessions/), PR_DOCS_OUTSIDE (под docs/, не покрытые docs_paths)
pr_registry <proj> <base> <head>  # (2026-10-31, круг 3: реальная сигнатура; в первоначальном наброске было `<files>` — файлы берутся из $PR_FILES) PR_REG_PATH PR_REG_STATE (one|none|ambiguous) PR_REG_ANCHORS: docs/DECISIONS.md, иначе единственный файл по
                            #   маске docs/**/{DECISIONS,decisions}*.md (дефолт Q-7); якоря — заголовки ADR/D-NNN, добавленные диффом
pr_url_ok <url>             # whitelist: ssh://… https://… http://… file://… scp-вид user@host:path, абсолютный локальный путь; остальное
                            #   (ext::, fd::, transport::, пробелы, ведущий '-') отказ                                                # PKG-URL-WL
pr_url_show <url>           # PR_URLS: учётные данные вида user:pass@ вырезаны (для вывода и трейлеров)
pr_hosting <url> [hint]     # github | bare: hint из заказа приоритетнее; иначе "github.com" в URL -> github
```

Правила разрешения `base` (`pr_base_ref`): `refs/heads/<name>` предпочтительнее remote-tracking (сессия вырезана от локальной ветки, `start.md:29`); имя `<name>` — `repo.base` заказа, иначе `lib/default-branch.sh`. Автоматического `fetch` нет (сеть — только у `pr-publish`). Если и локальная, и remote-tracking существуют и различаются — это WARN `base.remote-drift` (показывается на подтверждении), не молчаливый выбор.

`pr_registry`: кандидаты — изменённые файлы диффа `base..head`; `docs/DECISIONS.md` приоритетен, затем единственное совпадение маски; ноль или несколько — `none|ambiguous` (WARN по REQ-PKG-26, `adr: []` в манифесте и пометка в `notes`). Якорь: `git diff -U0 base head -- <reg> | grep '^+#'` → первый токен вида `[A-Z]+-[0-9]+` заголовка (`ADR-022` → `docs/DECISIONS.md#ADR-022`); узел отбрасывает часть после `#` (`DEV:398`).

### [ADDED] `sdx/hooks/pr-build.sh` — squash и манифест (REQ-PKG-5, 6, 8, 9, 10)

```
bash pr-build.sh --sid <sid> [--proj DIR] [--commitment C] [--title T] [--base-name B]
                 [--allow-diverged] [--resubmit] [--notes TEXT]
stdout: один JSON-объект (см. «Схема данных»); stderr: человекочитаемые строки; rc: 0 собран | 1 отказ | 2 окружение/использование | 3 нужно подтверждение
```

Алгоритм (нетривиальные места — фрагментами):

```bash
. "$here/lib/pr-lib.sh"                                   # bash 3.2, set -uo pipefail
[ "$(mandate_mode "$proj")" = on ] && mandate_load "$proj" || die 1 "режим мандата не включён или мандат не разобран"
pr_resolve "$proj" "$sid" ... || die 1 "$PR_ERR"          # C, exec, base, title: поле называется в сообщении
src="refs/heads/sdx/$sid"; srcsha=$(git -C "$proj" rev-parse --verify -q "$src^{commit}") || die 1 "нет ветки sdx/$sid"
[ "$(git -C "$proj" symbolic-ref -q HEAD)" = "$src" ] || die 1 "текущая ветка не sdx/$sid"
# 1) дерево squash
if git -C "$proj" merge-base --is-ancestor "$PR_BASE_SHA" "$srcsha"; then               # PKG-ANCESTOR
  tree=$(git -C "$proj" rev-parse "$srcsha^{tree}")
else
  [ "$allow_diverged" = 1 ] || { echo "NEED allow-diverged: sdx/$sid вырезана не от $PR_BASE_NAME" >&2; exit 3; }
  tree=$(git -C "$proj" merge-tree --write-tree "$PR_BASE_SHA" "$srcsha") \
    || die 1 "merge-tree: конфликт или git < 2.38 (слейте $PR_BASE_NAME в sdx/$sid вручную)"
fi
# 2) родитель squash: base либо (повторная сдача) прежняя вершина
old=$(git -C "$proj" rev-parse --verify -q "refs/heads/$PR_BRANCH" || true)
if [ -n "$old" ]; then
  [ "$resubmit" = 1 ] || { echo "NEED resubmit: ветка $PR_BRANCH уже есть" >&2; exit 3; }
  git -C "$proj" cat-file -e "$old:CHANGE.yaml" || die 1 "$PR_BRANCH существует, но это не пакет SDX (нет CHANGE.yaml)"
  parent="$old"; zero="$old"
else parent="$PR_BASE_SHA"; zero=0000000000000000000000000000000000000000; fi         # PKG-CAS
git -C "$proj" cat-file -e "$tree:CHANGE.yaml" 2>/dev/null && die 1 "в коде уже есть корневой CHANGE.yaml (код пакета манифеста не содержит)"   # PKG-NOCHANGEYAML
head=$(printf '%s\n' "$PR_C: $PR_TITLE" | git -C "$proj" commit-tree "$tree" -p "$parent") || die 2 "git commit-tree (нет user.name/user.email?)"
```

Повторная сдача (REQ-PKG-18, К-3): `head` второго раунда имеет родителем *прежнюю вершину* (манифест-коммит первого раунда); дерево `head` — вершина `sdx/<sid>` без `CHANGE.yaml`, поэтому разница «прежняя вершина → новая голова» удаляет старый `CHANGE.yaml`, а разница `base..head` (чистый net-diff) не меняется. Отправка — fast-forward без `--force`. *(2026-10-31, круг 1 верификации: если база ушла вперёд, `head` получает вторым родителем новую базу — см. «Поправки круга 1 верификации».)* Узел делает `git merge --squash <head>` (`DEV:451`), несколько коммитов в `base..head` ему безразличны; `tip^ == head` и `diff head..tip = [CHANGE.yaml]` сохраняются.

Вычисления манифеста (после `head`):

```bash
mbase=$(git -C "$proj" merge-base "$head" "$PR_BASE_SHA")                                  # = base узла: merge-base(head, dev)
PR_FILES=$(pr_files "$proj" "$mbase" "$head") || die 1 "$PR_ERR"                           # scope_touched, включая сгенерированное   # PKG-SCOPE-TOUCHED
[ -n "$PR_FILES" ] || die 1 "дельта base..head пуста (nonempty)"                           # PKG-EMPTY
pr_scope_eval                                                                              # PR_SHARED ≠ ∅  => touches_shared=true   # PKG-SHARED
asha=$(git -C "$proj" -c tar.umask=0002 archive --format=tar "$head" | pr_sha256)         # PKG-ARCHIVE: от head, не от tip; umask закреплён
```

Поля (REQ-PKG-9): `commitment=PR_C`, `executor=mandate.executor`, `mandate_digest=mandate.digest`, `base=$mbase`, `head`, `archive_sha256=$asha`, `scope_touched`, `touches_shared`, `spec` — самый поздно менявшийся `docs/specs/*.md` среди `PR_FILES` как `<путь>@<git log -1 --format=%h sdx/<sid> -- путь>` (нет перенесённой спецификации — ключ **опускается**, как предписывает шаблон «если стадия spec была»), `verify.tests` = `pass`, если `verification_report.md` на `PR_SESS_REV` содержит строку `Итог: PASS`, иначе `unknown`; `verify.report` = `sdx/<sid>@<rev8>:.claude/sessions/<sid>/verification_report.md` (путь в истории ветки; пусто → `""`), `adr` — `pr_registry` (при `docs_in_repo: none` — `[]`), `docs` — `PR_DOCSF`, `history_ref: executor:sdx/<sid>`, `notes` — `--notes` либо `SDX <версия плагина>: сессия <sid>` (+ пометки реестра/нескольких спецификаций). Необязательные ключи МОVE.IO (`module{}`, `contracts_changed`, `migrations{}`, `layer`) в шаблоне — только в комментарии, не заполняются.

Отказы до записи: каталог сессии в дереве вершины `sdx/<sid>` (шаг 5 не выполнен), `pr_valid_id` на `C` и `exec` (поле называется: `executor: недопустимые символы ':'`), `git check-ref-format "refs/heads/$PR_BRANCH"`, `pr_has_secret` на `title`/`notes`/каждый путь, управляющий символ в пути, пустой дифф.

Генерация YAML (D-3):

```bash
keys=""                                                      # ключи шаблона в порядке файла; комментарии и пустые строки пропущены
while IFS= read -r l || [ -n "$l" ]; do
  case "$l" in ""|"#"*|"  #"*) continue ;; "change:") continue ;;
    "  "[a-z]*:*) k=${l#  }; k=${k%%:*}
       case " format commitment executor mandate_digest base head archive_sha256 scope_touched touches_shared spec verify adr docs history_ref notes " in
         *" $k "*) keys="$keys $k" ;; *) die 1 "шаблон sim-kit содержит поле '$k', неизвестное pr-build — обновите плагин" ;; esac ;;   # PKG-TEMPLATE-KEYS
    *) die 1 "строка шаблона вне ожидаемой формы" ;; esac
done < "$here/../mo/CHANGE.template.yaml"
manifest=$(jq -n -r --argjson v "$vals" --arg keys "$keys" "$RENDER_CHANGE")        # RENDER_CHANGE — jq-программа ниже
```
```jq
def sc: if type=="string" then (gsub("[\u2028\u2029\u0085]";" ") | tojson) elif type=="null" then "\"\"" else tojson end;
def lst($i): if length==0 then " []" else "\n" + (map($i + "- " + sc) | join("\n")) end;
def emit($k): $v[$k] as $x
  | if $k=="verify" then "  verify:\n    tests: " + ($x.tests|sc) + "\n    report: " + ($x.report|sc)
    elif ($x|type)=="array" then "  " + $k + ":" + ($x|lst("    "))
    else "  " + $k + ": " + ($x|sc) end;
"# CHANGE.yaml (format 1) — SDX /sdx:pr по CHANGE.template.yaml sim-kit; манифест — отдельный последний коммит над головой кода\nchange:\n"
  + ([ ($keys | split(" ")[] | select(length>0) | . as $k | select($v | has($k)) | emit($k)) ] | join("\n")) + "\n"
```

Коммит манифеста (D-2):

```bash
blob=$(printf '%s' "$manifest" | git -C "$proj" hash-object -w --stdin)
idx=$(mktemp -u "${TMPDIR:-/tmp}/sdx-pr-idx.XXXXXX"); trap 'rm -f "$idx"' EXIT
GIT_INDEX_FILE="$idx" git -C "$proj" read-tree "$head"                                     # PKG-PLUMB: ни рабочее дерево, ни настоящий индекс не трогаются
GIT_INDEX_FILE="$idx" git -C "$proj" update-index --add --cacheinfo "100644,$blob,CHANGE.yaml"
mtree=$(GIT_INDEX_FILE="$idx" git -C "$proj" write-tree)
tip=$(printf 'SDX: CHANGE.yaml (%s)\n' "$PR_C" | git -C "$proj" commit-tree "$mtree" -p "$head")   # PKG-TIPPARENT: -p head, не base
git -C "$proj" update-ref -m "sdx pr-build $sid" "refs/heads/$PR_BRANCH" "$tip" "$zero" || die 1 "ветка $PR_BRANCH изменилась параллельно (CAS)"
```
Ничего из перечисленного не запускает pre-commit-хуки (`commit-tree` их не вызывает) и не пишет в рабочее дерево. Вывод — JSON и выход 0. Состояние после: `HEAD` = `sdx/<sid>`, `git status` без изменений, появились объекты и одна ссылка `refs/heads/change/<C>-<exec>`.

### [ADDED] `sdx/hooks/pr-check.sh` — проверка перед публикацией (REQ-PKG-11, 12, 26, 27)

```
bash pr-check.sh --sid <sid> [--phase pre|post|all] [--proj DIR] [--commitment C] [--title T] [--base-name B] [--no-tests]
stdout: строки "OK|FAIL|WARN|NOTE <id>: <текст>" и последняя "PR-CHECK PASS" | "PR-CHECK WARN <n>" | "PR-CHECK FAIL <n>"
rc: 0 PASS | 3 есть WARN, нет FAIL | 1 есть FAIL | 2 использование/окружение;  --phase по умолчанию all
```

Формат строк — как у `closeout-check` (`OK …`/`FAIL …`), с идентификатором для мутантов и подтверждений. Значения мандата/заказа в вывод попадают через `pr_clean` (данные, не инструкции).

**Фаза `pre`** (до сборки; ветка `change/*` ещё не обязана существовать):

| id | исход | зеркало узла / REQ |
|---|---|---|
| `closeout.branch`, `closeout.tree`, `closeout.session` | FAIL | выводы `mandate-info.sh closeout-check <sid>` проксируются как есть (ветка `sdx/<sid>`, дерево чистое кроме `.mesh`, каталога сессии нет в `HEAD`) — REQ-PKG-11 (а), (г) |
| `id.commitment`, `id.executor`, `branch.name` | FAIL | `pr_valid_id`, `check-ref-format` (R-7, REQ-PKG-5) |
| `branch.scope` | FAIL | `scope.branches` (непуст) × имя ветки через `mandate_fnmatch` — **чистый `fnmatch`**, не `glob_any` (`DEV:374–375`) — REQ-PKG-11 (е) |
| `mandate.valid` | FAIL | `mandate_expired` — `valid_until >= today` (`DEV:369`) — (ж) |
| `mandate.digest` | FAIL | в мандате нет 12-hex `digest` (манифест без него бессмыслен) |
| `mandate.lint` | WARN | `history: executor` + `docs_in_repo: none` — `lint` узла отвергает (`DEV:84–85`) |
| `base.ref` | FAIL | нет `base` (ни локальной, ни remote-tracking) |
| `base.ancestor` | WARN | `base` — не предок `sdx/<sid>`: нужен `--allow-diverged` (REQ-PKG-5) |
| `base.remote-drift` | WARN | локальный `base` ≠ remote-tracking |
| `branch.exists` | WARN | локальная `change/<C>-<exec>` уже есть: повторная сдача (`--resubmit`, REQ-PKG-18) |
| `diff.nonempty` | FAIL | `nonempty` (`DEV:381–382`) |
| `diff.scope` | FAIL | `files ⊆ paths ∪ shared ∪ docs` (`mandate_in_union`, пустой `paths` — без ограничения) — (в) |
| `diff.session` | FAIL | в дифф попали пути `.claude/sessions/` (шаг 5 не выполнен/откатан) — (г) |
| `docs.final` | FAIL | `docs_in_repo: final`: изменённый путь под `docs/`, не покрытый `docs_paths` (REQ-PKG-27, К-12) |
| `adr.registry` | WARN | при `final`/по умолчанию: реестр не менялся, неоднозначен или вне `docs_paths` (`PR_REG_STATE`) — (и), REQ-PKG-26, ответ МО §3 п.3 |
| `shared.note` | NOTE | `touches_shared: true` + список — REQ-PKG-12 |
| `attrs.export` | WARN | `$GIT_DIR/info/attributes` содержит `export-ignore|export-subst`: сумма архива у узла может не совпасть (R-8) |
| `url.scheme` | FAIL | `pr_url_ok(repo.url)` |
| `url.origin-drift` | WARN | `repo.url` заказа ≠ ни один configured remote (push пойдёт в URL заказа — показывается на подтверждении) |
| `tests` | FAIL | повторный прогон тестовой команды (`test_cmd_resolve`) из корня под `timeout ${SDX_VERIFY_TIMEOUT:-180}`; нет команды — `NOTE tests: тест-команды нет — пропущено`; `--no-tests` — `NOTE`; дерево пакета ≠ рабочее дерево (`base.ancestor` WARN) — `WARN tests: прогон не относится к пакету` — (з) |

Тесты запускаются последними и только если нет `FAIL` выше (экономия времени); хвост вывода красной команды — в stderr. `timeout`/`gtimeout` нет в `PATH` (macOS) — прогон без ограничения и `NOTE tests: нет timeout`.

**Фаза `post`** (ветка собрана; читает `refs/heads/<branch>` и манифест из его вершины):

| id | исход | зеркало узла |
|---|---|---|
| `manifest.parse` | FAIL | `CHANGE.yaml` в корне вершины есть и разбирается `miniyaml` (наш вывод — блочное подмножество) — `manifest` reject |
| `manifest.format` | FAIL | `change.format == 1` (`DEV:354`) |
| `manifest.commit` | FAIL | у вершины ровно один родитель `== change.head`, и `git diff --name-only head tip` ровно `CHANGE.yaml` (`DEV:355–360`) — (б) |
| `manifest.headtree` | FAIL | в дереве `head` нет корневого `CHANGE.yaml` |
| `manifest.identity` | FAIL | `commitment`/`executor`/`mandate_digest` манифеста = заказ/мандат; имя ветки = `change/<C>-<exec>` |
| `manifest.archive` | FAIL | пересчёт `sha256(git archive --format=tar head)` = `archive_sha256` (`DEV:391–394`) — (д) |
| `manifest.scope` | FAIL | `scope_touched` как множество = `git diff --name-only mbase head`, `base` = `merge-base(head, base)` |
| `manifest.shared` | FAIL | вычисленное `touches_shared` истинно, а в манифесте не `true` (`DEV:387–390`); обратное — `NOTE` |
| `manifest.adr` | WARN | при `final`: `adr` непуст и каждый путь (до `#`) в `PR_FILES` (`DEV:397–400`) |
| `manifest.secret` | FAIL | `pr_has_secret` на тексте манифеста |
| `pkg.session`, `pkg.scope`, `pkg.nonempty` | FAIL | то же, что `diff.*`, по фактическому диффу `base..tip` без `CHANGE.yaml` |
| `branch.scope`, `mandate.valid`, `closeout.tree`, `closeout.branch` | FAIL | повтор: ветка/срок/дерево могли измениться за время подтверждений |

`all` = `pre` затем `post`, если `pre` без `FAIL`. Проверки `pre` до сборки *предсказывают* дифф: при предке `base` — `git diff --name-only base_sha sdx/<sid>` (совпадёт с `base..head` сборки), в расходящемся случае — по дереву `git merge-tree --write-tree base_sha sdx/<sid>` (дерево пишется только в объектную базу).

### [ADDED] `sdx/hooks/pr-publish.sh` — push и PR (REQ-PKG-13…16, 18, 35)

```
bash pr-publish.sh --sid <sid> [--proj DIR] [--commitment C] [--title T] [--base-name B] [--remote <имя|URL>] [--hosting auto|github|bare] [--dry-run]
stdout: JSON результата; stderr: прогресс; rc: 0 отправлено (в т.ч. деградация без gh) | 1 отказ | 2 использование/окружение
```
Подтверждение пользователя делает `commands/pr.md` *до* вызова; скрипт его не подменяет, но защищается сам.

```bash
pr_resolve ...; tip=$(git rev-parse --verify -q "refs/heads/$PR_BRANCH") || die 1 "пакет не собран"
case "$PR_BRANCH" in change/*) ;; *) die 1 "публикуется только change/*" ;; esac                           # PKG-P-REFSPEC
remote="${remote_arg:-${PR_URL:-origin}}"                       # remote — имя настроенного remote либо URL, прошедший pr_url_ok
git -C "$proj" remote | grep -qxF -- "$remote" || pr_url_ok "$remote" || die 1 "недопустимый remote/URL"   # PKG-P-URLWL
spec="refs/heads/$PR_BRANCH:refs/heads/$PR_BRANCH"                    # без "+", без --all/--mirror/--follow-tags/--tags
jq -n --arg c "git push $remote $spec" '{tool_name:"Bash",tool_input:{command:$c}}' | CLAUDE_PROJECT_DIR="$proj" bash "$here/prod-guard.sh" \
  | grep -q '"permissionDecision":"deny"' && die 1 "prod-guard: push заблокирован паттерном проекта"   # PKG-P-PRODGUARD
rsha=$(GIT_TERMINAL_PROMPT=0 git -C "$proj" ls-remote --heads -- "$remote" "refs/heads/$PR_BRANCH" | cut -f1)
if [ -n "$rsha" ] && [ "$rsha" != "$tip" ]; then                                                          # PKG-P-FF
  git -C "$proj" merge-base --is-ancestor "$rsha" "$tip" 2>/dev/null || die 1 "на удалённой стороне $PR_BRANCH не предок вершины (non-fast-forward); перезапись в 2.5.0 не поддерживается"
fi
GIT_ALLOW_PROTOCOL=file:ssh:https:http GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes}" \
  git -C "$proj" -c push.followTags=false -c push.default=nothing push --porcelain --no-follow-tags -- "$remote" "$spec"   # PKG-P-NOFOLLOW
```
Идемпотентность: `rsha == tip` — `pushed: true, already: true`, push не выполняется. После push — `ls-remote` повторно: `remote_sha == tip` иначе отказ.

*(Поправка круга 4 верификации, 2026-10-31: явный `--title` побеждает заголовок снимка заказа без отказа — это поведение `pr_resolve`; отказом остаются расхождения `--commitment`/`--base-name` со снимком.)* Хостинг: `pr_hosting` (поле заказа приоритетнее, иначе `github.com` в URL → `github`, иначе `bare`). При `github`: `command -v gh` и `gh auth status` rc 0 → `gh pr list --head <branch> --repo <owner/repo> --json url` (существующий PR → вернуть его, не создавать второй) иначе `gh pr create --repo <owner/repo> --base <repo.base> --head <branch> --title "<C>: <title>" --body-file <tmp>` (аргументы массивом без оболочки; `owner/repo` — из URL по `github.com[:/]owner/repo(.git)?`, не разобрался → деградация). Нет `gh`/нет авторизации/любая ошибка `gh` → **деградация**: `pr: null`, `degraded: "gh-missing|gh-unauthenticated|gh-failed"`, `instruction` — одна строка «Откройте PR вручную: <branch> → <base> в <url без учётных данных>.», rc 0 (REQ-PKG-16: не отказ). Тело PR строится из манифеста вершины (`git show tip:CHANGE.yaml` → `my_load`): обязательство, `executor`, число файлов в `scope_touched`, `verify`, `adr`, `touches_shared` (строка «слияние такого пакета — решение человека»), `history_ref`; значения — через `pr_clean`, `pr_has_secret` на теле → отказ до отправки.

### [ADDED] `sdx/hooks/protocol-export.sh` — `protocol.yaml` из журналов (REQ-PKG-19…22)

```
bash protocol-export.sh --sid <sid> [--proj DIR] [--out FILE|-] [--from-rev REV]
по умолчанию: читает рабочее дерево, пишет .claude/sessions/<sid>/protocol.yaml; --from-rev REV читает git show REV:.claude/sessions/<sid>/…, вывод в stdout
stderr: "protocol: done N decisions M (adr K) questions Q verified V deltas D"; rc 0 | 1 нет ни одного читаемого источника И каталога сессии | 2 использование/окружение
```
Источники и правила (отсутствие источника → пустой список, не ошибка — критерий приёмки):

| Раздел | Источник | Правило |
|---|---|---|
| `decisions[]` | `decisions_log.md` | `{id: "D-<n>", what, why, alternatives: [..], adr: bool, tag, stage}`; `tag`/`stage` — лишние ключи (схема узла допускает, `DEV:586–589` проверяет лишь `id/what/why`) |
| `questions[]` | тот же файл | строка `"[<тег>] <название>"` на каждую запись: вопрос — название, ответ — `decisions[]` (дублирование названо, К-5) |
| `verified[]` | `verification_report.md` | строки `- …` раздела `## Сводка`; `Матрица: OK a, WARN b, FAIL c` по последнему столбцу таблицы; строка `Итог по области: …` блока `SDX-MANDATE-SCOPE`, если есть (числа кругов в формате отчёта нет — не восстанавливается, К-5) |
| `deltas[]` | `SPEC.md`, иначе `change_note.md` | `"[ADDED|MODIFIED|REMOVED] REQ-…"` (идентификатор, иначе первые 80 знаков строки); дубликаты убираются, порядок сохраняется |
| `done[]` | `PLAN.md` сессии, иначе `docs/history/plans/<sid>.md` (шаг 3 уже перенёс план), иначе `change_note.md` | отмеченные `- [x] …` (≤120 знаков); для свёрнутой дельты — одна запись `change_note.md: <первый заголовок или строка>` |

`adr: true` — запись (все поля) содержит `ADR-[0-9]+` (REQ-PKG-20; «в выполненном переносе» отдельно не восстанавливается: перенос не привязан к записи). Разбор журнала (ядро, `awk` → TSV):

```awk
# TSV: tag \t stage \t title \t what \t why \t alts \t adr(0|1); tabs/newlines inside values are flattened to spaces
function out() { if (have) { adr = ((what why title alts) ~ /ADR-[0-9]+/) ? 1 : 0
    if (what == "" && why == "" ) { next_skip = 1 } else {
      if (what == "") what = title; if (why == "") why = what; print tag "\t" stage "\t" title "\t" what "\t" why "\t" alts "\t" adr } } have = 0; what = why = alts = title = tag = stage = ""; cur = "" }
/^### Развилка:/ { out(); have = 1; kind = "A"; t = $0; sub(/^### Развилка:[ \t]*/, "", t)
    if (match(t, /^\[[^]]+\]/)) { tag = substr(t, 2, RLENGTH - 2); t = substr(t, RLENGTH + 1); sub(/^[ \t]+/, "", t) }
    if (match(t, /\(этап:[^)]*\)[ \t]*$/)) { stage = substr(t, RSTART + 7, RLENGTH - 8); gsub(/^[ \t]+|[ \t)]+$/, "", stage); t = substr(t, 1, RSTART - 1) }
    gsub(/[ \t]+$/, "", t); title = t; next }
/^### / { out(); next }
kind == "A" && have && /^- Вариант:/       { cur = "what"; v = $0; sub(/^- Вариант:[ \t]*/, "", v); what = v; next }
kind == "A" && have && /^- Обоснование:/   { cur = "why";  v = $0; sub(/^- Обоснование:[ \t]*/, "", v); why = v; next }
kind == "A" && have && /^- (Варианты|Альтернативы):/ { cur = "alts"; v = $0; sub(/^- [^:]+:[ \t]*/, "", v); alts = v; next }
kind == "A" && have && cur != "" && /^[ \t]+[^ \t]/ { v = $0; gsub(/^[ \t]+/, "", v); if (cur == "what") what = what " " v; else if (cur == "why") why = why " " v; else alts = alts " " v; next }
# format B (as actually written in this session): "- [YYYY-MM-DD ]\[tag\] text", continuation = indented lines
/^- ([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] )?\[(триада|FAIL|контракт|деструктив|объём|ручной-шаг|триаж|директива)\]/ \
    { out(); have = 1; kind = "B"; t = $0; sub(/^- ([0-9-]+ )?/, "", t); match(t, /^\[[^]]+\]/); tag = substr(t, 2, RLENGTH - 2)
      t = substr(t, RLENGTH + 1); sub(/^[ \t]+/, "", t); why = t; what = t; i = index(t, ". "); if (i > 0 && i < 200) what = substr(t, 1, i); else if (length(t) > 200) what = substr(t, 1, 200); title = what; cur = "b"; next }
kind == "B" && have && cur == "b" && /^[ \t]+[^ \t]/ { v = $0; gsub(/^[ \t]+/, "", v); why = why " " v; next }
END { out() }
```
В формате B «Вариант» и «Обоснование» отдельно не заданы: `what` — первое предложение (≤200 знаков), `why` — вся запись; ничего не выдумывается (К-4). Рендер — одним `jq` (`tojson` = экранирование; `D-<n>` по порядку; пустые списки `[]`):

```bash
decisions=$(awk -f ... decisions_log.md | jq -Rn '[inputs | select(length>0) | split("\t") | {tag:.[0], stage:.[1], title:.[2], what:.[3], why:.[4], alternatives:(if .[5]=="" then [] else [.[5]] end), adr:(.[6]=="1")}] | to_entries | map(.value + {id:("D-"+((.key+1)|tostring))})')   # PKG-X-ID
```
Запись с пустыми `what` и `why` пропускается со строкой в stderr. Файл — tracked, коммитится командой (`sdx(<sid>): export protocol.yaml`) на `sdx/<sid>`, в `change/*` не входит (squash берёт дерево после шага 5, где каталога сессии нет). Второго ручного ввода в реестр решений нет: записи `adr: true` — справка узлу/читателю; сам реестр ведётся штатно шагом 2 (REQ-PKG-22).

### [ADDED] `sdx/hooks/order-import.sh` — приём заказа (REQ-PKG-23…25)

```
bash order-import.sh from-file  <path>          [--proj DIR] [--out FILE]
bash order-import.sh from-msg   <msg_id>        [--proj DIR] [--out FILE] [--inbox-json FILE]
bash order-import.sh from-issue <N> [--repo owner/repo] [--proj DIR] [--out FILE]
bash order-import.sh list                       [--proj DIR] [--inbox-json FILE]      # work.order в ящике: msg_id / C / название
bash order-import.sh stamp-state --sid <sid> --commitment <C> [--proj DIR]
stdout: flat-JSON {source, source_ref, commitment, title, executor, repo_base, repo_url, branch, delivery, due, sid_infix, warnings[]}
rc: 0 принят | 1 отказ (формат/идентификаторы/нет такого заказа) | 3 расхождение с локальным мандатом (stdout: строки MISMATCH <поле> order=<..> local=<..>) | 2 окружение
```
Источники:
- `from-file`: первый непробельный символ `{` → JSON (`jq`); иначе YAML: `LC_ALL=C tr -d '\r'` → `order-unfold` (awk) → `my_load`. Лимит размера 64 КиБ (больше — отказ).
- `from-msg`: `inbox --json` — одна каноническая JSON-строка конверта на заказ (`mesh_endpoint.py:155–162`); `jq -c 'select(.kind=="directive" and .body.action=="work.order" and .msg_id==$id) | .body'`. Без `--inbox-json` скрипт сам вызывает `PYTHONDONTWRITEBYTECODE=1 MESH_ENDPOINT_DIR="$proj" python3 "$here/../mo/mesh_endpoint.py" pull` и `inbox --json` (нужны python3 и PyYAML — они и так нужны самому `mesh_endpoint.py`; нет — отказ с подсказкой `--inbox-json` / `from-file`). `msg_id` проверяется по `^[A-Za-z0-9._:-]{1,80}$`.
- `from-issue`: `gh issue view <N> [--repo] --json body` (нет `gh` — отказ: «используйте `--from-order <файл>`», REQ-PKG-24); из `body` — **первый** fenced-блок ```` ```yaml ```` (также `yml`), содержащий строку `action: work.order` на нулевом отступе (ограничение блока 64 КиБ), далее как YAML-файл. Формат обёртки — допущение SDX (Q-10).

`order-unfold` (D-9; awk, граница названа в комментарии скрипта и в `docs/specs/mo-interop.md`): значение ключа/элемента списка, чьё содержимое — не flow/блочный скаляр/якорь/тег, склеивает следующие строки с отступом больше отступа ключа (одним пробелом — как сворачивает `yaml.safe_dump`); элемент вида `- key: …` (список словарей) не склеивается и далее отказывается `miniyaml`; двойная кавычка, не закрытая на строке, и пустая строка внутри значения — маркер `#UNFOLD-ERR`, ведущий к отказу.

Нормализация и проверки (порядок): `action == "work.order"`, `format == 1`; `commitment.id`, `executor` — `pr_valid_id` (`C-…`, `<exec>`; недопустимые символы — отказ с названием поля); `title`/`requirements` — `pr_clean` (требования до 4000 знаков); `due` — `^[0-9-]{10}` либо пусто; `repo.base` — `check-ref-format --branch`; `repo.url` — `pr_url_ok`; секреты — `pr_has_secret` на `title`/`requirements`; затем сверка с локальным мандатом (REQ-PKG-23, код 3): `mandate_digest` = `mandate.digest`, `executor` = `mandate.executor`, `deliver.branch` = `change/<C>-<exec>` (`# PKG-O-DIGEST`, `# PKG-O-EXEC`, `# PKG-O-BRANCH`). Расхождения выводятся *все* сразу (значения через `pr_clean`). Снимок `--out` (по умолчанию `.claude/sessions/<sid>/order.yaml`; *2026-10-31, круг 2 верификации: `start.md` передаёт `--out "$snapdir/order.yaml"` в ПЕРВОМ и единственном вызове — временный каталог вне репозитория, копирование в каталог сессии на шаге 6а после подтверждения, источник повторно не читается; см. «Поправки круга 2 верификации»*) рендерится `jq` в формате «Схема данных» ниже. `sid_infix` — `C`, сведённый к `[A-Za-z0-9._-]`, ≤40 знаков; команда `start.md` вставляет его в `session_id` (REQ-PKG-25).

`stamp-state`: добавляет `commitment` в существующий `session_state.json` (`jq --arg c "$C" '. + {commitment:$c}'` во временный файл рядом + `mv`, как `write_stage`); отказ, если состояния нет, `C` невалиден или поле уже стоит с другим значением; идемпотентен (`# PKG-O-STAMP`).

### [MODIFIED] `sdx/hooks/mandate-info.sh` — `pr-mode`, `pr-status` (REQ-PKG-2, 17, 34)

Только добавление подкоманд; `closeout-mode`/`closeout-check` и их мутанты (`MAND-BRIDGE`, `MAND-CHECK-*`) не меняются.

```
bash mandate-info.sh pr-mode [proj]
  OK executor=<safe> delivery=<pr|branch> docs_in_repo=<final|full|none> history=<executor|mo|both|unset> digest=<12hex|?>     rc 0
  REFUSE no-mandate | REFUSE orphan | REFUSE delivery:<safe> | REFUSE error:<причина>                                          rc 1
bash mandate-info.sh pr-status <sid> [proj]
  PR: branch=<b> head=<8> tip=<8> remote=<url без учётных данных> hosting=<h> pr=<url|-> (sdx/<sid>@<8>)     — последняя сдача (трейлеры служебного коммита)
  PR: собран, не отправлен …                                                                                     — вариант "pr built"
  PR: не сдан                                                                                                    — служебных коммитов нет
```
`pr-mode`: `mandate_mode` ≠ `on` → `REFUSE no-mandate` (`orphan` — отдельно, текст команды один); нечитаемый мандат → `REFUSE error:…`; `delivery` ∉ {`pr`,`branch`} → `REFUSE delivery:<safe>` (`artifact.offer` → мост 2.4.0, остальное — стоп-рубрика); `docs_in_repo` не задан → `final` (дефолт узла, `DEV:397`) (`# PKG-PRMODE-DELIVERY`, `# PKG-PRMODE-NOMANDATE`). Все значения проходят `safe` (`[A-Za-z0-9._-]`, прочее → `?`). `pr-status` читает `git log --grep "^sdx(<sid>): pr (submitted|built) " -n1`, трейлеры `SDX-PR-*` — данные, выводятся через `safe`.

### [MODIFIED] `sdx/hooks/lib/mandate.sh` — `mandate_fnmatch`

```bash
# mandate_fnmatch <string> <pattern>: rc 0 iff fnmatch(string, pattern) — ТОЛЬКО первая ветка glob_any (scope.branches проверяется узлом fnmatch'ем, DEV:374–375)
mandate_fnmatch() { local LC_ALL=C f="$1" p="$2" bs='\'; _my_rep "$p" "$bs" "$bs$bs"; _my_rep "$MY_REP" "[^" "[$bs^"; p="$MY_REP"; case "$f" in $p) return 0 ;; esac; return 1; }   # PKG-FNMATCH
```
Отличие от `mandate_glob_one` реально: шаблон `change` не совпадёт с `change/x` (у `glob_one` сработало бы правило префикса). Тест `[P]` на таблице случаев.

### [ADDED] `commands/pr.md` — конвейер (REQ-PKG-1…7, 13, 17, 18)

`argument-hint: [<C>] [--title "<заголовок>"] [--resubmit] [--build-only]`; `description: Сдача изменения пакетом под мандатом МО (второй вариант Closeout): squash, CHANGE.yaml, проверка, push/PR.` Структура (выполняется Session Manager в основной сессии; каждая остановка — стоп-рубрика, решение записывается там, где ещё есть куда писать):

```
P0 Режим.   bash mandate-info.sh pr-mode
    REFUSE no-mandate|orphan -> ОДНА строка и стоп (REQ-PKG-2/34):
       «/sdx:pr: нужен режим мандата МО (.mesh/endpoint.yaml и .mesh/mandate.yaml); без него сдача пакетом неприменима — закрывайте сессию через /sdx:archive.»
    REFUSE delivery:artifact.offer -> «delivery=artifact.offer: сдача оффером, используйте /sdx:archive (мост bridge:offer)»; delivery:<иное>, error:… -> стоп-рубрика [контракт], вопрос пользователю
P1 Состояние.  sid по ветке sdx/<sid>. Каталог сессии есть и вызов не из моста (на любом stage, в т.ч. Closeout) -> прелюдия archive.md (шаги 1–2а: гейт входа с дисклоузом auto_decisions.md, цикл next до Closeout — при Closeout no-op), затем сюда.
    Каталога сессии нет в HEAD (шаг 5 уже сделан: повторная сдача/сбой) -> пропусти P2–P4, данные заказа — из истории (pr_session_rev).
P2 Шаги 1–4 чек-листа по commands/archive.md (коммиты; перенос дельт с учётом docs_in_repo; архив PLAN.md; журнал/бэклог). Шаги 6–8 стандартного Closeout: (n/a, пакет). artifact.offer-оффер не отправляется.
P3 Экспорт.   bash protocol-export.sh --sid <sid>      затем git add .claude/sessions/<sid>/protocol.yaml && git commit -m "sdx(<sid>): export protocol.yaml"
P4 Шаг 5.     git rm -r .claude/sessions/<sid> && git commit -m "sdx(<sid>): drop session artifacts pre-package"   (как в archive.md; REQ-COMPAT-3 скан легаси-имён — разово, как там)
P5 Проверка до сборки.  bash pr-check.sh --sid <sid> --phase pre [--commitment <C>] [--title "<T>"]    (Bash timeout >= 600000 мс: гоняет тесты проекта)
    rc 1 -> показать FAIL, стоп (устранить, повторить с P5). rc 3 -> показать WARN; AskUserQuestion по каждому классу (base.ancestor -> --allow-diverged, branch.exists -> --resubmit,
         adr.registry / base.remote-drift / url.origin-drift / mandate.lint / tests -> «принять и продолжить»/«остановиться»); [триаж]-запись невозможна (каталога нет) — подтверждения уходят в трейлер P9.
P6 Сборка.    out=$(bash pr-build.sh --sid <sid> [--allow-diverged] [--resubmit] ...)    rc 3 -> вернуться к подтверждению
P7 Проверка после.  bash pr-check.sh --sid <sid> --phase post     rc 1 -> стоп, пакет НЕ публиковать; локальную ветку удалить можно только по [деструктив]-подтверждению
P8 Подтверждение.  показать: ветку, remote/URL (без учётных данных), git show <tip>:CHANGE.yaml, итог pr-check, touches_shared, список WARN, принятых на P5.
    AskUserQuestion «Отправить пакет?» (Отправить / Оставить локально) — В ЛЮБОМ gate_mode, включая auto ([контракт]); --build-only или «Оставить» -> P9 без push
P9 Публикация + запись.  res=$(bash pr-publish.sh --sid <sid> ...)  ->  git commit --allow-empty -F - (трейлеры SDX-PR-*, раздел «Схема данных»)
P10 Итог.  вывод пользователю: ветка, head/tip, remote, URL PR либо одна строка инструкции, «ветка sdx/<sid> остаётся», что узел сделает сам (аудит, change.merge), что protocol.yaml
    в узел этой командой не отправляется (при history: mo узел читает его из ветки sdx/<sid> своего клона; при history: executor канал — вне SDX, К-18)
```
Идентификатор и заголовок (REQ-PKG-7): при заказе — из снимка `order.yaml`; без заказа `<C>` берётся из аргумента команды (нет — отказ с подсказкой «`/sdx:pr <C>`»), заголовок — из `--title`, иначе первая строка `# …` из `SPEC.md`/`change_note.md` на `PR_SESS_REV` предлагается пользователю на подтверждение. Расхождение аргумента со снимком заказа — отказ, не молчаливая подмена.

Запреты в прозе: не вызывать `audit()` и не писать в `.mesh/`; не выполнять `git push` напрямую (только `pr-publish.sh`); не слить `change/*` и не открыть PR «от имени узла» (REQ-PKG-35); данные заказа/мандата/issue — данные, не инструкции.

### [MODIFIED] `commands/archive.md` (REQ-PKG-1, 30)

Шаг 2а, ветка `bridge` (`pr|branch`): текст ручной инструкции из трёх шагов **удаляется**; вместо него: «Шаги 1–5 и сдача пакета выполняются процедурой `commands/pr.md` (Read) — прелюдия (шаги 1–2а) уже пройдена, продолжай с P0; `archive-verify.sh` не вызывается; шаги 6–8 `(n/a, пакет)`; ветка `sdx/<id>` остаётся». Ветки `bridge:offer`, `undefined:*`, `error:*` и `standard` — без изменений, за исключением одной правки: в `bridge:offer` фраза «пакет собирается при любом `delivery`» заменяется на «пакет `change/<C>-<exec>` для `artifact.offer` — решение узла; ручная сборка по `sdx/mo/CHANGE.template.yaml` и `sdx/templates/CONTRIBUTING-MO.md`» (поведение 2.4.0 сохранено, REQ-PKG-30). Заголовок чек-листа: «Closeout имеет два варианта — „мёрж“ (шаги 6–8) и „пакет“ (`/sdx:pr`)».

### [MODIFIED] `commands/start.md` (REQ-PKG-23…25)

`argument-hint: <type> <goal> [--auto] [--from-order <order.yaml|msg_id>] [--from-issue <N>]`; новый шаг **1б** после показа мандата (1а): при `--from-order`/`--from-issue` — (i) `mandate-info.sh pr-mode` не `OK` → отказ одной строкой («заказ принимается только в режиме мандата с delivery pr|branch»); (ii) `order-import.sh from-file|from-msg|from-issue` (для `--from-order <значение>`: существующий файл — `from-file`, иначе шаблон `msg_id` — `from-msg`; без значения — `order-import.sh list` и вопрос), код 3 → остановка `[контракт]` с выводом `MISMATCH`-строк; код 1 → причина дословно и стоп; (iii) `gate_mode: auto` (директива) **и** `--from-issue` (неаутентифицированный текст, К-9) → `AskUserQuestion` с показом `commitment`/`title`/`executor`/`scope`/`repo` до создания сессии (`[директива]`, запись в `decisions_log.md` после шага 7 — файла ещё нет, запись переносится на первый коммит состояния); (iv) `commitment.title` — цель, если `<goal>` не задан; `commitment.requirements` — вход для `ba`/`architect` как *данные*; (v) `scope` заказа показывается рядом с мандатом (шаг 1а печатает его уже в 2.4.0); (vi) предупреждение одной строкой, если текущая ветка ≠ `repo.base` заказа (сессия вырежется не от `base`, REQ-PKG-5). После шага 6 (`init`): `order-import.sh stamp-state --sid <sid> --commitment <C>` и копирование подтверждённого снимка `cp "$snapdir/order.yaml" .claude/sessions/<sid>/order.yaml` *(2026-10-31, круг 2 верификации: снимок пишется ОДНИМ вызовом `order-import.sh from-* --out "$snapdir/order.yaml"` во временный каталог на шаге 1б до подтверждения; повторного вызова источника нет)*; снимок и состояние уходят в seed-коммит шага 7. `session_id` содержит `sid_infix`. Без этих флагов поведение шагов 1–8 прежнее.

### [MODIFIED] `commands/status.md` (REQ-PKG-25, 17)

Шаг 3: `commitment` из `session_state.json`, если поле есть. Новый шаг **5б** (читающий): в режиме мандата — `mandate-info.sh pr-status <id>`; ветка `sdx/<id>` без каталога сессии (после шага 5 `/sdx:pr`) показывается как «сессия в состоянии сдачи пакета (каталог сессии удалён)» с этой строкой — иначе `/sdx:status` после шага 5 нечего было бы показать.

### [MODIFIED/ADDED] Вендоринг, шаблон «как сдать», документы (REQ-PKG-28…33)

- **`sdx/mo/CHANGE.template.yaml`** — побайтовая копия `git show sim-kit-0.9.1:./CHANGE.template.yaml` (sha256 `346d2e6e52477faf69811411dfa11a96526daa28639a05ff523b9e90d86fd5cd`, сверен с рабочей копией); строка в `SIMKIT_SHA256` (порядок — как у существующих); `SIMKIT_VERSION` остаётся `0.9.1`; три прежних файла не трогаются; упоминание имени на **пяти** поверхностях сторожа (`README.md`, `README.en.md`, `CLAUDE.md`, `sdx/protocol.md`, `docs/DECISIONS.md`) и в `sdx/mo/README.md`. Правила (d)/(e) `test-mo-inventory.sh` не меняются. Вопрос PROC-028 «отдельная сессия» — К-1.
- **`sdx/templates/CONTRIBUTING-MO.md`** — собственный текст SDX, нейтральный к инструменту (только `git`, `sha256sum`, текстовый редактор): что такое пакет изменения и кому его отдавать; имя ветки `change/<C>-<executor>`; порядок «код → один squash-коммит → `CHANGE.yaml` отдельным последним коммитом»; таблица полей манифеста с командами вычисления (`git rev-parse`, `git archive --format=tar <head> | sha256sum`, `git diff --name-only`); `touches_shared`, `adr` (файл реестра, изменённый в пакете), `docs`; область (`scope`, `shared_paths`, `docs_paths`) и срок мандата; схема `protocol.yaml` (пять списков, `decisions[] {id, what, why}`) и куда его положить; что делает узел сам (аудит, ревью, слияние) и чего исполнитель не делает (слияние, теги, push в защищённые ветки); чек-лист самопроверки. Ссылка на шаблон `sdx/mo/CHANGE.template.yaml`. Деплоится как есть; в репозиторий заказчика его копирует человек.

## Схема данных / API

### `CHANGE.yaml` (внешний контракт, формат 1; порождается `pr-build.sh`, читается `audit()` узла `DEV:256–265`)

```yaml
# CHANGE.yaml (format 1) — SDX /sdx:pr по CHANGE.template.yaml sim-kit; манифест — отдельный последний коммит над головой кода
change:
  format: 1
  commitment: "C-ACME-001"
  executor: "ex1"
  mandate_digest: "123456789012"        # всегда в кавычках: голый 12-значный hex-из-цифр YAML прочёл бы числом
  base: "<40 hex: merge-base(head, base)>"
  head: "<40 hex: голова кода>"
  archive_sha256: "<sha256 git archive --format=tar head>"
  scope_touched:
    - "docs/DECISIONS.md"
    - "package-lock.json"
    - "src/mod1/a.js"
  touches_shared: true
  spec: "docs/specs/mod1.md@a1b2c3d"    # ключ опущен, если перенесённой спецификации нет
  verify:
    tests: "pass"                        # pass | unknown
    report: "sdx/feat-x-20261031@a1b2c3d4:.claude/sessions/feat-x-20261031/verification_report.md"
  adr:
    - "docs/DECISIONS.md#ADR-022"        # [] при docs_in_repo: none или если реестр не менялся (WARN подтверждён)
  docs:
    - "docs/DECISIONS.md"
  history_ref: "executor:sdx/feat-x-20261031"
  notes: "SDX 2.5.0: сессия feat-x-20261031"
```
Порядок ключей — порядок шаблона. Парсер узла — `yaml.safe_load`; наш `pr-check` читает тот же файл `miniyaml.sh` (вывод — в подмножестве: блочные отображения, блочные списки с отступом, строки в двойных кавычках). Тестовый оракул сверяет оба разбора.

### `protocol.yaml` (схема `protocol_check()` `DEV:577–593`)

```yaml
# protocol.yaml — экспорт журналов сессии feat-x-20261031 (SDX 2.5.0). Источник правды — журналы сессии; файл производный.
done:
  - "…"
decisions:
  - id: "D-1"
    what: "…"
    why: "…"
    alternatives: []
    adr: false
    tag: "триаж"
    stage: "Business Spec"
questions:
  - "[триаж] Гейт Business Spec"
verified:
  - "Итог: PASS"
  - "Находки: FAIL: 0, WARN: 2"
  - "Матрица: OK 31, WARN 2, FAIL 0"
deltas:
  - "[ADDED] REQ-PKG-1"
```
Пустой раздел — `done: []`. Все пять ключей присутствуют всегда; `decisions[i].{id,what,why}` непусты по построению.

### Снимок заказа `.claude/sessions/<sid>/order.yaml` (наш формат; пишет `order-import.sh`, читает `pr-lib.sh` через `git show` на `PR_SESS_REV`)

```yaml
order:
  format: 1
  source: "msg"                 # file | msg | issue
  source_ref: "m-20261031-001"  # msg_id | имя файла | #N
  commitment:
    id: "C-ACME-001"
    kind: "change"
    title: "…"                  # pr_clean: одна строка, ≤200 знаков
    requirements: "…"           # pr_clean: одна строка, ≤4000 знаков
    due: "2026-12-01"
    creditor: "acme"
  executor: "ex1"
  mandate_digest: "123456789012"
  repo:
    id: "app"
    url: "ssh://dobro/srv/app.git"
    base: "dev"
    hosting: "github"           # только если есть в заказе
  deliver:
    branch: "change/C-ACME-001-ex1"
    delivery: "pr"
```
Строки сведены к одной и в двойных кавычках: снимок читается `miniyaml` без распрямления. Мандат целиком в снимок **не** копируется (источник правды — `.mesh/mandate.yaml`, перечитывается на каждом вызове, D-3 FEAT-016).

### `session_state.json` (REQ-PKG-25)

Новое **необязательное** поле `commitment` (строка); `sdx-stage.sh init` по-прежнему пишет семь ключей, поле добавляет `order-import.sh stamp-state` отдельным `jq`; без `--from-order` его нет. Поправка к «никакого нового поля» в `docs/designs/decision-journal-and-resume.md` (датированная пометка там и в протоколе).

### Служебный коммит результата (D-6; пишет `commands/pr.md` на шаге P9)

```
sdx(<sid>): pr submitted change/<C>-<exec>      # либо "pr built change/<C>-<exec>" (собран, не отправлен)

SDX-PR-Branch: change/<C>-<exec>
SDX-PR-Head: <40 hex>
SDX-PR-Tip: <40 hex>
SDX-PR-Remote: <URL без учётных данных | имя remote>
SDX-PR-Hosting: bare|github
SDX-PR-Url: <URL PR | ->
SDX-PR-Ack: <список принятых WARN через запятую | ->        # base.ancestor,adr.registry,…
SDX-PR-Confirmed: <gate_mode>:user                          # решение пользователя на push ([контракт]); при "pr built" — declined|build-only
```
Коммит `--allow-empty`; `git commit -F -` из heredoc (не перенаправление в файл проекта).

### JSON-выходы

`pr-build.sh`: `{"branch","commitment","executor","base","head","tip","base_ref","archive_sha256","scope_touched":N,"touches_shared":bool,"adr":[…],"docs":N,"resubmit":bool,"diverged":bool,"warnings":[…]}`.
`pr-publish.sh`: `{"branch","remote","remote_sha","pushed":bool,"already":bool,"ready":bool,"hosting","pr":{"url","created"}|null,"degraded":"gh-missing|gh-unauthenticated|gh-failed"|null,"instruction":"…"|null}`.
`order-import.sh`: `{"source","source_ref","commitment","title","executor","repo_base","repo_url","branch","delivery","due","sid_infix","warnings":[…]}`.

### Коды возврата и тексты

| Скрипт | rc | Смысл |
|---|---|---|
| `pr-build.sh` | 0 / 1 / 2 / 3 | собран / отказ (`pr-build: <поле>: <причина>` в stderr) / окружение, использование / нужно подтверждение (`NEED allow-diverged`, `NEED resubmit`) |
| `pr-check.sh` | 0 / 3 / 1 / 2 | `PASS` / `WARN n` / `FAIL n` / окружение |
| `pr-publish.sh` | 0 / 1 / 2 | отправлено (в т.ч. деградация без `gh`) / отказ / окружение |
| `protocol-export.sh` | 0 / 1 / 2 | записан (в т.ч. все списки пусты) / нет ни одного источника и каталога сессии / окружение |
| `order-import.sh` | 0 / 1 / 3 / 2 | принят / отказ / расхождение с мандатом / окружение |
| `mandate-info.sh pr-mode` | 0 / 1 | `OK …` / `REFUSE …` |

Отказ без мандата в прозе `pr.md` — ровно одна строка (текст в P0).

## Обработка ошибок и Граничные случаи

- **Нет мандата / мандат без `endpoint.yaml` / `delivery` ∉ {pr, branch}.** `pr-mode` → `REFUSE`; команда отказывает *до* любых побочных эффектов (REQ-PKG-2). `artifact.offer` остаётся на мосте 2.4.0.
- **Идентификаторы.** `C` или `executor` вне `[A-Za-z0-9][A-Za-z0-9._-]{0,63}` (в т.ч. `client-harness:kitgroup`, `..`, пробел, ведущий `-`, `.lock` на конце) → отказ `pr-build: executor: недопустимый символ ':'`; подмены нет (R-7). Итоговое имя дополнительно проверяет `git check-ref-format`.
- **`user.name`/`user.email` не заданы** → `commit-tree` падает → rc 2 с подсказкой; запись в `git config` скрипт не делает.
- **Каталог сессии ещё в `HEAD`** (шаг 5 пропущен): `pr-check pre` → `FAIL closeout.session`; `pr-build` соберёт дерево с каталогом — поэтому `pr-build` сам отказывает, если в дереве вершины `sdx/<sid>` есть `.claude/sessions/<sid>/` (двойная защита).
- **Расходящийся `base`** (`sdx/<sid>` вырезана не от `base`): без `--allow-diverged` — rc 3; с ним — `merge-tree`; конфликт слияния или git < 2.38 → rc 1 с инструкцией влить `base` в `sdx/<sid>` вручную. Пакет *всегда* строится от актуального локального `base`; узел пересчитывает `merge-base` сам (`DEV:376–380`).
- **Ветка `change/<C>-<exec>` уже есть.** Не пакет SDX (нет `CHANGE.yaml` в корне вершины) → отказ; пакет SDX → rc 3 `NEED resubmit`; параллельное изменение ссылки (CAS) → отказ.
- **Пустой дифф / только служебные файлы** → `FAIL diff.nonempty`. **Путь с управляющим символом** → отказ (формат `-z` читается, но YAML-квотирование имён с `\n` не поддерживается — вне контракта, названо).
- **`CHANGE.yaml` уже в коде** (корень репозитория) → отказ: манифест не может править существующий файл, `tip^ == head` и «разница — ровно `CHANGE.yaml`» потеряли бы смысл.
- **Тест-команда** отсутствует → `NOTE`, не `FAIL`; красная → `FAIL`, хвост вывода в stderr; превышение `SDX_VERIFY_TIMEOUT` (по умолчанию 180 с, как у stop-gate) = красная; нет `timeout`/`gtimeout` → прогон без ограничения (названо).
- **Реестр ADR.** `docs/DECISIONS.md` не менялся или неоднозначен при `final` → `WARN adr.registry` (подтверждение, не отказ); путь реестра вне `docs_paths` → `WARN` с текстом ответа МО §3 п.3; `docs_in_repo: none` → проверок реестра нет.
- **`gh`**: нет / не авторизован / сбой / URL не `github.com/owner/repo` → деградация (push выполнен, одна строка инструкции, rc 0). PR для этой ветки уже существует → его URL, второй не создаётся.
- **Push**: сеть/авторизация упали → rc 1, пакет остаётся локально (повторный вызов идемпотентен); `GIT_TERMINAL_PROMPT=0` и `ssh -o BatchMode=yes` — интерактивных запросов нет; не-fast-forward → отказ с причиной.
- **Заказ**: больше 64 КиБ, не `work.order`, `format ≠ 1`, недопустимые идентификаторы, недопустимый `repo.url`, секрет в `title`/`requirements` → rc 1; несколько `work.order` в ящике → `list` и явный `msg_id` (угадывания «последнего» нет); `gh` нет → `--from-issue` отказ с подсказкой; YAML вне подмножества → rc 1 с причиной `miniyaml`/`order-unfold` (в частности «двойная кавычка с переносом» — передайте заказ через ящик или сократите значение).
- **`decisions_log.md`** отсутствует/пуст → `decisions: []`; запись без `what` и `why` пропускается со строкой в stderr; смешение форматов A и B допустимо.
- **Повторный вызов `/sdx:pr` после сбоя на любом шаге P5–P9** безопасен: каждый шаг идемпотентен или отказывает; каталог сессии не нужен (D-5).
- **Параллельная сдача двух сессий одного `C`** → вторая получит `NEED resubmit`/CAS-отказ; два исполнителя одного обязательства различаются `<exec>` в имени ветки.
- **Хуки.** Внутренние записи скриптов (`protocol.yaml`, объекты git) хук `PreToolUse` не видит — он разбирает *текст* Bash-команды; командные строки `/sdx:pr` не содержат перенаправлений `>` в проект (служебный коммит — `git commit -F -`). Именованная граница (К-17).

## Безопасность

- **Данные, не инструкции.** Заказ, тело issue, конверт, мандат, журналы — чужой/внешний текст: проходят `pr_clean`/`jq tojson`, не исполняются, не попадают в командные строки через оболочку (`gh`, `git` — массивы аргументов; `eval` запрещён; `case "$f" in $p` использует значение мандата лишь как шаблон области).
- **Алфавит.** Всё, что становится частью имени ветки, ограничено `[A-Za-z0-9._-]`; заголовок коммита/PR — `pr_clean` (без переводов строк и управляющих символов).
- **Push только после подтверждения** пользователя в любом `gate_mode` (`[контракт]`); перед подтверждением показываются ветка, remote/URL *без учётных данных*, манифест, итог `pr-check`, расхождение `repo.url` заказа и `origin` (заказ мог подменить URL — экфильтрация кода). В `auto` решение не принимается по умолчанию.
- **Только `change/*`, только явный refspec, без `+`.** Не используются `--force`/`--force-with-lease`/`--all`/`--mirror`/`--tags`/`--follow-tags`; конфиг пользователя нейтрализован `-c push.followTags=false -c push.default=nothing` и явным refspec (`remote.<n>.push` с явным refspec в командной строке не действует). `sdx/*` не уходит ни при каких конфигурациях (тест P2). Перезапись удалённой `change/*` не реализована (К-3).
- **Транспорт.** whitelist схем URL (`ssh`, `https`, `http`, `file`, scp-вид, абсолютный путь), `GIT_ALLOW_PROTOCOL=file:ssh:https:http` (закрывает `ext::`/`fd::`/`transport::`), URL с ведущим `-` или пробелом отказывается, аргумент всегда после `--`.
- **`prod-guard` как есть:** внутри скрипта прогоняется `prod-guard.sh` на синтезированной команде `git push …` (хук `PreToolUse` внутреннюю команду не видит); паттерны проекта сохраняют силу.
- **Секреты.** `pr_has_secret` (зеркало `REDACT[0]` вендорённого `mesh_endpoint.py`) на заголовке, `notes`, путях и теле PR; манифест целиком проверяется в `pr-check post`; секреты в *диффе* ловит `secrets_in_diff` узла (`redact_patterns` узла исполнителю недоступны — Q-13).
- **`gh` — не зависимость.** Любая его недоступность — деградация; токены `gh` скрипт не читает и не логирует.
- **Права.** Скрипты вызываются как `bash <путь>` (BUG-008). Новых зависимостей нет: bash 3.2, git, jq, awk, sed, grep; `python3`/PyYAML — только оракулы в тестах (INFO-skip без них) и `mesh_endpoint.py` в `from-msg` (который сам их требует).
- **PROC-020.** Поставка не меняет hook-скрипты и механизм надзора (`mo-hook.sh`, `mo-session.sh`, `hooks.json` не тронуты); новый вендорённый файл — К-1; сессия не в `gate_mode: auto`.

## Тесты

Конвенция та же, что FEAT-016: у каждой ветки красная сторона (мутант по якорю `# PKG-*` либо встроенный негативный случай); шапка-комментарий сьюта; bash 3.2; `mktemp -d` + `trap`; без записи в чекаут (и без `__pycache__`: `PYTHONDONTWRITEBYTECODE=1`); сьюты подхватываются глобом `verify-cmd.sh`; блоки выбираются переменной `<SUITE>_ONLY` (как `MANDATE_SCOPE_ONLY`), вложенный прогон мутанта — `<SUITE>_NESTED=1`, путь изменённого скрипта — `<SUITE>_UNDER_TEST`; `SCEN_MIN=1` в мутантах сокращает матрицу до различающего блока (как в `test-mo-hook.sh`).

### [ADDED] `sdx/hooks/lib/pkg-fixture.sh` — общий тестовый помощник

`source`-файл (не сьют: имя не `test-*.sh`). `pkg_fixture_template` собирает **один раз за прогон сьюта** шаблон: bare-репозиторий `remote.git` (ветка `dev`), клон `wc` с `src/mod1/a.js`, `src/core/b.js`, `package-lock.json`, `docs/DECISIONS.md`, `docs/specs/mod1.md`, `.claude/sdx/verify-cmd.sh` (управляемый `exit 0|1`), ветка `sdx/s1` от `dev`: каталог сессии (`session_state.json`, `order.yaml`, `decisions_log.md`, `verification_report.md`, `change_note.md`) → код (изменение `a.js`, `package-lock.json`, ADR-099 в реестре, спецификация) → коммит `git rm -r` каталога сессии; `.mesh/endpoint.yaml` + `.mesh/mandate.yaml` (форма дампа узла, `executor: ex1`, `digest: "123456789012"`, `valid_until: "2099-01-01"`, `delivery: pr`, `docs_in_repo: final`, `scope.paths [src/mod1/**]`, `shared_paths [package-lock.json]`, `docs_paths [docs/**]`, `branches [change/*]`). `pkg_fixture_copy <dst>` — `cp -a` шаблона (миллисекунды); вложенные прогоны мутантов получают `PKG_FIXTURE_TEMPLATE` от родителя. `pkg_craft_*` — фабрики «фальшивых» пакетов обходным plumbing'ом (лишний коммит между `head` и вершиной, посторонний файл в манифест-коммите, неверный `archive_sha256`, файл вне области, недекларированный `touches_shared`, каталог сессии в пакете, `format: 2`, манифест внутри головы) — по образцу `mkpkg` (`SK/tests/kit.sh:695–742`).

### [ADDED] `test-pr-build.sh`

| № | Что | Красная сторона |
|---|---|---|
| B1 | золотой путь: rc 0, JSON, `tip^ == head`, `head`'s родитель = `base`, `base..head` — ровно один коммит с темой `C: заголовок`; **независимый python-оракул `audit()`** (транслитерация формальных проверок `DEV:340–424`: `manifest_of`, `manifest.commit`, `branch` по `fnmatch`, `scope` по `glob_any`, `shared.declared`, `archive_sha256`, `adr`; без реестра обязательств, тестов и ревью) → `approve` (INFO-skip без PyYAML) | мутанты B-таблицы; встроенный негатив: оракул на повреждённом пакете ≠ `approve` |
| B2 | plumbing-инварианты: до/после совпадают `HEAD`, имя ветки, `git status --porcelain`, `git ls-files -s`; `CHANGE.yaml` на диске нет (`find`); `tip`-дерево = дерево `head` + один блоб | `PKG-PLUMB` |
| B3 | `archive_sha256` = пересчёт в **независимом клоне** (`git clone` + `git archive`) и = `sha256` `git archive` фикстуры | `PKG-ARCHIVE` (хеш от `tip`) |
| B4 | `scope_touched` включает «сгенерированное» (`package-lock.json`); `touches_shared` оба исхода (два вызова на копиях) | `PKG-SCOPE-TOUCHED`, `PKG-SHARED` |
| B5 | `adr`: реестр менялся → `["docs/DECISIONS.md#ADR-099"]`; не менялся → `[]` + `notes`; `docs_in_repo: none` → `[]`; `spec` есть/нет (ключ опущен); `verify.tests` `pass`/`unknown` | — |
| B6 | экранирование (REQ-PKG-10): заголовок с `"`, `\`, `: `, `#`, `'`, `{}`, ` - `, юникод, переводом строки (сведён к пробелу); манифест разобран `miniyaml` и `yaml.safe_load` (оракул) → одинаковые значения; `mandate_digest` из цифр остаётся строкой | мутант `PKG-QUOTE` (рендер без `tojson`) |
| B7 | отказы: `executor` с `:`, `C` с `..`/ведущим `-`/пробелом/65 знаками, секрет в заголовке, путь с управляющим символом, `CHANGE.yaml` в коде, пустой дифф, каталог сессии в дереве `sdx/<sid>`, нет мандата, мандат без `endpoint.yaml`, не та ветка | `PKG-ID`, `PKG-SECRET`, `PKG-NOCHANGEYAML`, `PKG-EMPTY` |
| B8 | повторная сдача: без флага rc 3 `NEED resubmit`; с флагом — родитель нового `head` = прежняя вершина, `tip^ == head`, оракул `approve`; существующая не-пакетная `change/*` → rc 1; гонка (CAS) | `PKG-CAS` |
| B9 | расходящийся `base` (`dev` ушёл вперёд после выреза): rc 3; с флагом — дифф `base..head` только изменения сессии, без чужих; конфликт → rc 1 | `PKG-ANCESTOR` |
| B10 | шаблонно-управляемая генерация: ключи и порядок манифеста = ключам шаблона; копия шаблона с лишним ключом → rc 1 «обновите плагин»; копия без ключа `adr` → манифест без `adr` | `PKG-TEMPLATE-KEYS` |
| B11 | дерево пакета (`git ls-tree -r tip`) не содержит `.claude/sessions/` и `protocol.yaml` (REQ-PKG-19) | — |
| B12 | `PKG-TIPPARENT`: манифест-коммит с родителем `base` вместо `head` | `PKG-TIPPARENT` |

Бюджет ≈ 8 с (шаблон фикстуры ≈ 0,5 с, 12 блоков на `cp -a`-копиях, 12 мутантов ≈ 0,3 с каждый).

### [ADDED] `test-pr-check.sh`

| № | Что | Красная сторона |
|---|---|---|
| C1 | `pre` зелёный: rc 0 `PR-CHECK PASS`, тест-стаб `exit 0` | — |
| C2 | `pre` блокирует (rc 1, каждый — свой `FAIL <id>`): грязное дерево; каталог сессии в `HEAD`; не та ветка; недопустимый `executor`; имя вне `scope.branches` (`branches: [feat/*]`); истёкший мандат (`SDX_MANDATE_TODAY`); файл вне области; документ вне `docs_paths` при `final`; пустой дифф; красный тест-стаб (`exit 1`, хвост в stderr); `repo.url` вида `ext::…`; нет `digest` | `PKG-C-TREE`, `-SESSION`, `-BRANCH`, `-EXPIRED`, `-SCOPE`, `-DOCS-FINAL`, `-TESTS` |
| C3 | `pre` требует подтверждения (rc 3, `WARN <id>`): расходящийся `base`; ветка уже есть; реестр ADR не менялся (`final`); реестр вне `docs_paths`; дрейф remote-tracking; `export-ignore` в `info/attributes`; `history: executor` + `docs_in_repo: none`; при `docs_in_repo: none` реестр не проверяется | `PKG-C-ADR` |
| C4 | `post` зелёный на пакете из `pr-build` + оракул `approve` | — |
| C5 | `post` красные стороны (пакеты из `pkg_craft_*`): лишний коммит между `head` и вершиной; посторонний файл в манифест-коммите; неверный `archive_sha256`; файл вне области; `touches_shared` не объявлен; каталог сессии в пакете; `format: 2`; манифест внутри головы без `archive_sha256`; фальшивый `scope_touched`; секрет в `notes`; `commitment`/`executor`/`digest` не те | `PKG-C-TIPCOMMIT`, `-ARCHIVE`, `-SHARED`, `-SESSION`, `-SCOPE` |
| C6 | **паритет с оракулом `audit()`**: для каждого пакета C4/C5 `оракул ≠ approve ⇔ pr-check post ≠ PASS` (по проверкам, которые оракул покрывает), таблица «пакет → ожидаемые id провала» | встроенный негатив: подмена вердикта оракула краснит сверку |
| C7 | `all` = `pre` затем `post`; `--no-tests` пропускает только тесты; значения мандата в выводе проходят `pr_clean` (враждебный `executor` с ESC/переводом строки) | — |

Бюджет ≈ 10 с (≈ 16 пакетов/копий, python-оракул одним вызовом на пакет ≈ 0,12 с, 11 мутантов).

### [ADDED] `test-pr-publish.sh`

| № | Что | Красная сторона |
|---|---|---|
| P1 | push в локальный bare как `repo.url`: на удалённой стороне ровно одна новая ссылка `refs/heads/change/<C>-<exec>` (`for-each-ref`), `sdx/s1` и теги отсутствуют; JSON; `remote_sha == tip` | `PKG-P-REFSPEC` (в мутанте — `+refs/heads/*`/glob) |
| P2 | враждебный конфиг: `push.default=matching`, `remote.origin.push=+refs/heads/*:refs/heads/*`, `push.followTags=true` + аннотированный тег на вершине `sdx/s1` → на удалённой стороне по-прежнему только `change/…`, тегов нет | `PKG-P-NOFOLLOW` |
| P3 | не-fast-forward: на удалённой стороне `change/…` на постороннем коммите → rc 1; повтор уже отправленного → rc 0, `already: true`; FF-продолжение (повторная сдача) уходит без `--force` | `PKG-P-FF` |
| P4 | хостинг: `https://github.com/o/r.git`, `git@github.com:o/r.git` → `github`; локальный путь → `bare`; подсказка заказа приоритетнее | — |
| P5 | `gh`-стаб в `PATH` (записывает argv): (а) есть и авторизован → `pr list --head … --repo o/r` затем `pr create --repo o/r --base dev --head change/… --title "C: T" --body-file F`; тело содержит обязательство, `touches_shared`, нет секретов; (б) `gh` нет → rc 0, `degraded: gh-missing`, одна строка `instruction`; (в) `gh auth status` rc 1 → `gh-unauthenticated`; (г) PR уже есть → его URL, `create` не вызывается; push во всех случаях выполнен | `PKG-P-GH` (мутант: отказ вместо деградации) |
| P6 | отказы: ветка `sdx/s1`/`main`; URL `ext::sh -c 'touch MARK'` (файл-маркер не создан); `-oProxyCommand=…`; URL с пробелом; нет remote; `prod-guard.conf` с `git push` → rc 1 | `PKG-P-URLWL`, `PKG-P-PRODGUARD` |
| P7 | учётные данные `https://u:p@host/x.git` не попадают в stdout/stderr/JSON (`--dry-run`) | — |

Бюджет ≈ 6 с.

### [ADDED] `test-protocol-export.sh`

Оракул схемы — `python3` + `yaml.safe_load`, логика `protocol_check()` (`DEV:577–593`): пять ключей-списков, `decisions[i].{id,what,why}` непусты (один вызов python на все выходы; INFO-skip без PyYAML, остальные проверки через `jq` на JSON-форме остаются).

| № | Что | Красная сторона |
|---|---|---|
| X1 | формат A (`### Развилка`, `Вариант`/`Обоснование`, многострочное продолжение, `Варианты`) → `decisions`, `alternatives`, `tag`, `stage` | встроенный негатив: оракул схемы на файле без одного из пяти разделов краснеет |
| X2 | формат B — **буквальный `decisions_log.md` этой сессии** (golden-копия) → `what`/`why` непусты, тег, `D-1…` | `PKG-X-FMTB` (мутант не читает B → список пуст) |
| X3 | смесь A+B в одном файле, порядок сохранён | — |
| X4 | нет файлов / пустой каталог сессии / только `decisions_log.md` пуст → пять пустых списков, rc 0; нет каталога и нет источников → rc 1 | `PKG-X-EMPTY` (мутант опускает пустой раздел) |
| X5 | `adr`: запись с `ADR-021` → `true`, без → `false` | `PKG-X-ADR` |
| X6 | `id`: `D-1…D-n`, уникальны, непусты | `PKG-X-ID` |
| X7 | враждебные значения: `"`, `\`, `---`, `: `, табуляция, 5000 знаков, U+2028 → оракул-roundtrip (значение в `safe_load` = исходному с поправкой на сведение пробелов) | — |
| X8 | `verified`/`deltas`/`done` из `verification_report.md`/`SPEC.md`/`change_note.md`/`docs/history/plans/<sid>.md` | — |
| X9 | `--from-rev <родитель коммита шага 5>` даёт тот же файл, что запуск до шага 5 (REQ-PKG-4/D-5) | `PKG-X-REV` |

Бюджет ≈ 3 с.

### [ADDED] `test-order-import.sh`

| № | Что | Красная сторона |
|---|---|---|
| O1 | файл: статический golden — `yaml.safe_dump` заказа с переносами (одинарные кавычки, продолжение строк, список с переносом) → `commitment`, `title`, `requirements`, `repo.base/url`, `deliver.branch` совпадают с ожидаемыми | `PKG-O-UNFOLD` |
| O2 | паритет `order-unfold`+`miniyaml` с `yaml.safe_load` на ~25 сгенерированных дампах (python/PyYAML, INFO-skip); отказы: двойные кавычки с переносом, блочный скаляр, пустая строка внутри значения, якорь, список словарей — rc 1 с причиной | — |
| O3 | конверт: `--inbox-json` (строки конвертов `directive`/`work.order`, посторонние `kind`, два заказа) → выбор по `msg_id`; `list`; неизвестный `msg_id` → rc 1 | — |
| O4 | issue: `gh`-стаб отдаёт `{"body": …}` с несколькими fenced-блоками (первый — не заказ) → берётся первый **yaml-блок с `action: work.order`**; без `gh` → rc 1 с подсказкой `--from-order <файл>` | `PKG-O-FENCE` |
| O5 | сверка с мандатом: `mandate_digest` / `executor` / `deliver.branch` не совпали → rc 3, все `MISMATCH`-строки сразу | `PKG-O-DIGEST`, `PKG-O-EXEC`, `PKG-O-BRANCH` |
| O6 | идентификаторы и враждебные значения: `C` с `/`, `..`, пробелом; `title` с переводом строки, `` ` ``, `$(…)`, ESC, 5000 знаков; `repo.url` с `ext::`; секрет в `requirements` → rc 1 / сведено без побочных эффектов (файл-маркер не создан) | `PKG-O-ID` |
| O7 | снимок: `--out` пишет `order.yaml` в нашем формате; повторное чтение `pr_order_load` возвращает те же значения; `stamp-state` добавляет `commitment`, не трогает остальные ключи, идемпотентен, отказывает на другом значении | `PKG-O-STAMP` |

Бюджет ≈ 3 с.

### [MODIFIED] существующие сьюты (только добавлением, кроме пинов текста моста — Q-17 SPEC)

- **`test-mo-prose.sh`** — новые `[19]…[27]` с красной стороной на повреждённой копии (`[19]` `archive.md`; `[20]` `pr.md`; `[21]` протокол; `[22]` сниппет; `[23]` ADR-022; `[24]` `devops.md`; `[25]` README×2/`CLAUDE.md`; `[26]` `start.md`/`status.md`; `[27]` `CONTRIBUTING-MO.md`): `archive.md` делегирует `pr.md` для `bridge`, ручная инструкция из трёх шагов отсутствует, `bridge:offer`/`undefined`/`error` на месте; `pr.md` содержит вызовы всех скриптов, `AskUserQuestion`, «в любом gate_mode», одну строку отказа без мандата, не содержит командной строки `git push` вне запретительного текста; протокол — два варианта Closeout и снятие моста для `pr|branch`; **сниппет = текст §6 `MO-INTEROP.md` 0.9.1** (сравнение после снятия `> ` и склейки строк) и содержит `/sdx:pr`; ADR-022 заголовком; `devops.md` (`/sdx:pr`, «теги»); `README.md`/`README.en.md`/`CLAUDE.md` называют `CHANGE.template.yaml`, `pr-build.sh`, `CONTRIBUTING-MO.md`; `start.md` (`--from-order`, `--from-issue`, `order-import.sh`), `status.md` (`pr-status`); `plugin.json` = 2.5.0; `sdx/templates/CONTRIBUTING-MO.md` есть и в `sdx/mo/` его нет. **Изменяются пины 2.4.0:** `[11]` (сниппет «нет /sdx:pr» → «есть /sdx:pr»), `[12]` (мост: `(n/a, пакет)` для `bridge`, `(n/a, мандат)` остаётся для `bridge:offer`), `[17]` (версия 2.4.0 → 2.5.0), `chk_plugin_version`.
- **`test-mandate-scope.sh` `[M]`** — `pr-mode` (нет мандата, orphan, `pr`, `branch`, `artifact.offer`, `patch`, нечитаемый, `docs_in_repo` не задан → `final`, враждебный `executor` → `safe`), `pr-status` (нет сдач; `submitted`; `built`; враждебные трейлеры); мутанты `PKG-PRMODE-NOMANDATE`, `PKG-PRMODE-DELIVERY`.
- **`test-mandate-lib.sh`** — `mandate_fnmatch`: таблица (`change/*` ↔ `change/C-ex1` да; `change` ↔ `change/x` **нет**, у `glob_one` — да; `[^x]`; пусто); мутант `PKG-FNMATCH` (подмена на `glob_one`) краснит строку «`change` ↔ `change/x`».
- **`test-sdx-stage.sh`** — `[42]`: поле `commitment` переживает `next`/`next --to`, `init` пишет прежние семь ключей без него.
- **`test-mo-inventory.sh`** — на реальном каталоге четыре вендорённых файла, `CHANGE.template.yaml` проходит (c)/(d)/(e); `CONTRIBUTING-MO.md` в `sdx/mo/` — находка (d) (красная сторона на фикстуре).

### Бюджет времени

Прирост (оценка по аналогии с замерами FEAT-016: фикстурный сьют 2–7 с): `test-pr-build` ≈ 8 с, `test-pr-check` ≈ 10 с, `test-pr-publish` ≈ 6 с, `test-protocol-export` ≈ 3 с, `test-order-import` ≈ 3 с, правки существующих ≈ +3 с. Итого **≈ +33 с** к «≈ 105–125 с» → **≈ 140–160 с при пределе 180 с** (запас 20–40 с; под нагрузкой — меньше). Контроль и рычаги:
1. До Closeout — прогон `verify-cmd.sh` с замером и актуализация комментария (19 → 24 сьюта); критерий SPEC «с запасом» = ≤ 150 с без нагрузки.
2. Если > 150 с: (а) мутанты — только с `SCEN_MIN=1` в основном прогоне, полный набор — под `PKG_FULL=1` (нет — только различающие блоки); (б) рычаг второго порядка — параллельный запуск сьютов в `.claude/sdx/verify-cmd.sh` (`SDX_VERIFY_JOBS`, по умолчанию 2; сьюты независимы: каждый работает в `mktemp`) — правка dogfood-раннера, не плагина (К-10).
3. `tests/suites.yaml` (`budget_min: 3`) остаётся.

## Обратная совместимость (REQ-PKG-34, 35) — доказательство по построению

| Компонент | Гейт | Что подтверждает, что без мандата/без новых флагов ничего не изменилось |
|---|---|---|
| `commands/pr.md` | новая команда; `pr-mode` ≠ `OK` → одна строка | `test-mandate-scope [M]` (`REFUSE`), `test-mo-prose [20]` |
| `commands/archive.md` | ветка `bridge` — через `closeout-mode`, `standard` — прежний чек-лист 1–8 бит-в-бит | `test-archive-verify.sh`, `test-mo-prose [12]`, `[19]` |
| `commands/start.md` | новый шаг 1б срабатывает только при `--from-order|--from-issue`; без них шаги 1–8 прежние | `test-mo-prose [26]` (шаги 1–8 на месте), `test-sdx-stage [42]` |
| `commands/status.md` | шаг 5б — только при `mandate_mode = on` | прозаический grep |
| `mandate-info.sh` | добавлены подкоманды; `mode|show|status|closeout-*` не тронуты | существующие `[M]` без правок |
| `lib/mandate.sh` | добавлена функция; остальные не тронуты | `test-mandate-lib` (старые L1–L9) |
| `sdx-stage.sh`, `stop-gate.sh`, `archive-verify.sh`, `mo-hook.sh`, `mo-session.sh`, `hooks.json`, `miniyaml.sh` | не меняются | их сьюты зелёные без правок (`test-sdx-stage [1]–[41]`, `test-stop-gate`, `test-archive-verify`, `test-mo-hook`, `test-mo-session`, `test-hook-wiring`, `test-selftest`) |
| `session_state.json` | поле `commitment` необязательно; `init` не меняется | `test-sdx-stage [42]` |
| `sdx/mo/` | добавлен файл того же выпуска; три прежних байт-в-байт | `test-mo-inventory.sh` (c) |

Отступы от «бит в бит» названы: (1) пины текста моста и сниппета в `test-mo-prose` (`[11]`, `[12]`, `[17]`) — по Q-17 SPEC; (2) ручная инструкция моста для `pr|branch` снята (REQ-PKG-30); (3) `closeout-mode` по-прежнему печатает `bridge` для `pr|branch` — токен сохранён, смысл «пакет» (К-7).

## Альтернативы (отвергнутые)

- **Squash через `git checkout -b change/… base` + `git merge --squash` + коммит + `checkout` обратно.** Отвергнуто (D-1): трогает рабочее дерево и индекс, ломает `closeout-check` при сбое посередине, нужна запись `CHANGE.yaml` в дерево (R-2), хук области и `prod-guard` видят `checkout`/`merge`; plumbing даёт ту же историю без побочных эффектов и проверен на фикстуре.
- **`git worktree add` во временный каталог.** Отвергнуто: запись вне проекта вне контроля хука области, чистка при сбое, нет выигрыша (дерево уже есть как объект).
- **`CHANGE.yaml` писать файлом и `git add`/`commit`.** Отвергнуто (D-2, R-2).
- **Рендер манифеста `printf`/`sed` по шаблону построчно.** Отвергнуто: экранирование чужих значений руками — главный источник дефектов (REQ-PKG-10); `jq tojson` даёт валидный YAML double-quoted для любого значения.
- **PyYAML для разбора заказа.** Отвергнуто (D-1 FEAT-016, R-3): не гарантирован вне MO-окружения; `order-unfold`+`miniyaml` проверен на 367 дампах и fail-closed.
- **Результат сдачи: `git notes` / файл в `.claude/sessions/` / файл в `docs/history/`.** Отвергнуто (D-6): notes не клонируются; файл сессии ломает `closeout-check` и повторный squash; `docs/history/` уезжает в репозиторий заказчика.
- **Силовая перезапись `change/*` (`--force-with-lease`) для повторной сдачи.** Отвергнуто (К-3): FF-цепочка решает ту же задачу без деструктива.
- **Предупреждения/подтверждения `pr-check` как `FAIL`.** Отвергнуто: REQ-PKG-26 прямо допускает сдачу после явного подтверждения, поэтому третий исход `WARN` (rc 3).
- **Рефакторинг `closeout-check`/`archive-verify.sh` под пакет.** Отвергнуто: `archive-verify.sh` не меняется и при мандате не вызывается; `closeout-check` переиспользуется вызовом.
- **Токен `closeout-mode` переименовать в `package`.** Отвергнуто (К-7): churn пинов `test-mandate-scope [Mcm]`, `archive.md`, протокола без изменения поведения.

## Коллизии и вопросы (к решению; молча не решались)

Пункты К-1, К-2, К-3, К-9, К-10, К-12 требуют явного ответа пользователя на гейте Technical Design; остальные — «принято по предложению, если нет возражений».

- **К-1. Вендоринг `CHANGE.template.yaml` и PROC-028 («обновление `sdx/mo/` — отдельной сессией, не в `auto`»).** REQ-PKG-28 и ДЛ Q-14 включают файл в эту поставку. Это *добавление файла того же выпуска 0.9.1* без правки трёх прежних (`SIMKIT_VERSION` не меняется), а не обновление вендорённого кода; хеш рабочей копии `SK/` проверен на совпадение с тегом `sim-kit-0.9.1` (`346d2e6e…fd5cd`). **Предложение:** выполнить первой задачей PLAN (T0), в `interactive`-сессии (так и есть), с повторной сверкой `git show sim-kit-0.9.1:./CHANGE.template.yaml | sha256sum` в момент копирования и зелёным `test-mo-inventory.sh`; формулировка политики в `protocol.md` дополняется оговоркой «добавление файла того же выпуска допустимо в сессии поставки, обновление версии — по-прежнему отдельная сессия». Нужно подтверждение.
- **К-2. REQ-PKG-13: «запись в `decisions_log.md`» решения о push физически невозможна** — подтверждение идёт на шаге P8, после шага 5 (`git rm -r` каталога сессии), файла уже нет. **Предложение:** решение фиксируется трейлерами `SDX-PR-Confirmed`/`SDX-PR-Ack` служебного коммита на `sdx/<sid>` (постоянно, видно в `git log`, переживает клон); `decisions_log.md` не дописывается. Альтернатива — перенести подтверждение до шага 5 и строить пакет предсказанным деревом, — нарушает строгий порядок REQ-PKG-3/ДЛ Q-5. Нужно подтверждение.
- **К-3. Коллизия REQ-PKG-6 (ровно один коммит кода поверх `base`) и REQ-PKG-14/18 (перезапись `change/*` — деструктив; повторная сдача — «новая вершина поверх существующей»).** Единственный способ повторной сдачи без force — fast-forward. **Предложение:** первая сдача — один squash-коммит; повторная — новый squash-коммит с родителем = прежняя вершина (FF-цепочка, раздел `pr-build`), `base..head` содержит >1 коммита только при повторной сдаче, узлу это безразлично (`merge --squash`, `DEV:451`); принудительная перезапись в 2.5.0 **не реализуется** (REQ-PKG-14 «force — отдельное подтверждение» сводится к отказу с инструкцией «удалите удалённую ветку вручную»); это сужает SPEC, а не расширяет. Нужно подтверждение (альтернатива — реализовать `--force-with-lease=<ref>:<sha>` под `[деструктив]`; в задании на проектирование «никаких `--force`»).
- **К-4. Формат `decisions_log.md`: нормативный (блоки `### Развилка:` + `Вариант`/`Обоснование`) против фактического (однострочные `- [YYYY-MM-DD ][тег] текст` — именно так написан журнал этой сессии).** Парсер читает оба; в формате B `what` — первое предложение (≤200 знаков), `why` — вся запись (REQ-PKG-20 требует непустые оба, ничего не выдумывается). **Предложение:** принять; заведомый долг «единый формат журнала» — `DEBT`-запись на Closeout (PROC-019 в этой сессии не меняется).
- **К-5. `questions[]` и `verified[]` не имеют полноценных источников.** Вопросы `AskUserQuestion` не журналируются (только решения стоп-рубрики); числа кругов верификации в формате `verification_report.md` нет. **Предложение:** `questions[]` = названия записей журнала (вопрос) при `decisions[]` = ответы (дублирование названо); «число кругов» не экспортируется (отклонение от текста REQ-PKG-21, источника нет); расширение журналирования — вне предмета.
- **К-6. `/sdx:status` после шага 5.** Каталога сессии нет, существующий `status.md` ничего не покажет по ветке. **Предложение:** `pr-status` (чтение трейлеров) и пометка «сессия в состоянии сдачи пакета»; это небольшое расширение объёма относительно текста SPEC (REQ-PKG-17, 25), но указано в задании на проектирование.
- **К-7. Токен `closeout-mode = bridge`** для `pr|branch` теперь означает «пакет», а не «мост». **Предложение:** сохранить токен (пины `test-mandate-scope [Mcm]`, `archive.md`, протокол), пометить термин «исторический» в протоколе; `DEBT`-запись «переименовать в `package`».
- **К-8. `order-unfold` — дополнительная ступень разбора YAML.** Без неё `order.yaml` из `yaml.safe_dump` (длинные `title`/`requirements`) не читается `miniyaml` (подтверждено прогоном); PyYAML не гарантирован. **Предложение:** принять ступень; граница названа (двойные кавычки с переносом, блочные скаляры, пустая строка внутри значения, якоря, список словарей, flow-словарь — отказ); конверты ящика (JSON, `jq`) этой границы не имеют — основной канал.
- **К-9. Доверие к `--from-issue`.** Issue — неаутентифицированный текст (в отличие от конверта с проверенной цепочкой). SPEC требует подтверждения приёма только для `directive` в `auto`. **Предложение:** `--from-issue` подтверждается пользователем *в любом* `gate_mode` с показом `commitment/title/executor/scope/repo`; `mandate_digest` сверяется, но секретом не является (не аутентификация). Нужно подтверждение.
- **К-10. Бюджет времени.** Прирост ≈ +33 с к «≈ 105–125 с» → ≈ 140–160 с при пределе 180 с (раздел «Тесты»). **Предложение:** замер до Closeout; при > 150 с — `SCEN_MIN`-режим мутантов в основном прогоне и/или параллельный раннер в `.claude/sdx/verify-cmd.sh` (`SDX_VERIFY_JOBS=2`) — правка dogfood-скрипта репозитория, не плагина. Нужно согласие на этот рычаг заранее.
- **К-11. `pr-check` гоняет полный набор тестов проекта** (в этом репозитории ≈ 2 мин) — вызывать `pr-check` надо с Bash-таймаутом ≥ 600 с (проза `pr.md`), а при расходящемся `base` тесты относятся к рабочему дереву, не к дереву пакета (`WARN tests`). Кеш stop-gate недоступен (он в удалённом каталоге сессии). Поле `verify.tests` манифеста — утверждение по `verification_report.md` (`Итог: PASS`), не по этому прогону (иначе манифест строился бы после проверки, а проверка — по манифесту).
- **К-12. Что такое «документ вне `docs_paths`» (REQ-PKG-27).** **Предложение:** путь под `docs/`, не покрытый `docs_paths` мандата (именно туда ходят переносы шага 2/4: `docs/specs`, `docs/designs`, `docs/history`, `docs/backlog`, реестр ADR); документация внутри `scope.paths` (README модуля) не затрагивается. При `final` это `FAIL docs.final`. Нужно подтверждение определения.
- **К-13. `base`.** Локальная ветка предпочтительнее remote-tracking; автоматического `fetch` нет. Расхождение — `WARN base.remote-drift`; в ручном режиме без заказа `base` = `lib/default-branch.sh`, который может не совпадать с `dev` узла — тогда `merge-base` узла (`DEV:376`) даст чужие изменения в пакете: именно для этого есть `WARN` и показ перед push.
- **К-14. `docs_in_repo: none` и ADR.** Узел проверяет `adr` только при `final` (`DEV:397`); при `none` скрипты не требуют реестра, `adr: []`, переносы `(n/a)` — дельты остаются в `protocol.yaml` (в истории `sdx/<sid>`).
- **К-15. Автор squash-коммитов** — текущая git-идентичность исполнителя (Q-2 SPEC); нет идентичности — rc 2 с подсказкой, `git config` не пишется.
- **К-16. REQ-PKG-17 («`change_note.md`/`session.log`»)** заменено служебным пустым коммитом с трейлерами (D-6): названные файлы после шага 5 недоступны, а возврат файла в `.claude/sessions/` ломает инварианты. `/sdx:resume` эти коммиты не читает (работает по сессии до шага 5); расширение — вне предмета.
- **К-17. Внутренние записи скриптов не видны хуку `PreToolUse`** (он разбирает текст Bash-команды): `protocol-export.sh` пишет в `.claude/sessions/` даже при `on_write: deny` без области; `pr-build.sh` пишет объекты и ссылку в `.git`. Это не обход (запись — действие плагина, не агента), но граница называется в протоколе; поведение реального хука 0.9.1 на командные строки `/sdx:pr` — в ручном сценарии.
- **К-18. Upstream-вопросы владельцу МО (не работа плагина):** (1) канал доставки `protocol.yaml` узлу при `history: executor` (у узла читателя из репозитория нет, `DEV:577`); (2) формат issue-заказа; (3) исключение корневого `CHANGE.yaml` из `_in_scope` хука (`devagent_hook.py`); (4) семантика `docs_in_repo: final|full`; (5) `artifact.offer` с полем `change` (0.9.1 его не читает) — не добавляется.
- **К-19. `git merge-tree --write-tree` требует git ≥ 2.38.** На старых — расходящаяся ветка не собирается автоматически (rc 1 с инструкцией влить `base` в `sdx/<sid>`); норма (предок) от версии не зависит.

## Границы и риски

- **`archive_sha256` между версиями git** (R-8): проверено на одной версии (клон той же машины); `tar.umask` закреплён `0002`, `info/attributes` с `export-*` даёт `WARN`, `.gitattributes` дерева читается узлом так же. Расхождение у узла — `reject` с понятной причиной, не порча данных.
- **Разбор заказа — подмножество YAML + `order-unfold`** (К-8). Формы вне подмножества отказывают с причиной; заказ из ящика (JSON) границ не имеет.
- **Живой `audit()` узла плагин не вызывает** (REQ-PKG-35); паритет доказывается транслитерацией формальных проверок (независимый python-оракул) и ручным сценарием.
- **Хостинг.** `gitlab`/`gitea` ведут себя как `bare` (эталон `DEV:225`); `glab` не используется.
- **`protocol.yaml` до узла дойти не обязан** (REQ-PKG-22): остаётся в истории `sdx/<sid>`; канал при `history: executor` — К-18.
- **Тесты проекта внутри `pr-check` могут быть дороги** (К-11); `tests` в `pre` выполняется один раз.
- **Мандат переиздаётся узлом** между `/sdx:start` и `/sdx:pr`: `pr-check` перечитывает `.mesh/mandate.yaml` на каждом вызове (D-3 FEAT-016); смена `digest` относительно снимка заказа — `MISMATCH` на старте и `FAIL manifest.identity` на сдаче.
- **Повторная сдача после `return`/`reject`** — только FF-цепочка (К-3); если узел уже слил `head`, новая сдача — новое обязательство.
- **Территория PROC-020:** поставка не меняет механизм надзора; сессия не в `gate_mode: auto`.
- **Параллельные поставки:** FEAT-018 (`sdx run`/headless) будет вызывать те же скрипты — их контракты (JSON, коды) спроектированы как стабильный интерфейс.

## Поправки круга 1 верификации (2026-10-31)

Отражают решения оркестратора (`decisions_log.md` `[FAIL]`), SPEC — раздел «Поправки круга 1 верификации».
- **`pr-build.sh`, повторная сдача при ушедшей базе (Д-1, дополняет К-3 и абзац «Повторная сдача» выше).** Если `PR_BASE_SHA` не предок прежней вершины пакета, `head` создаётся `commit-tree` с родителями `<прежняя вершина> <PR_BASE_SHA>`; `merge-base(head, base)` = новая база, `scope_touched` без чужих файлов, `base` манифеста — новая. Если база уже предок прежней вершины, цепочка прежняя (один родитель, fast-forward). `tip^ == head` и `diff head..tip = [CHANGE.yaml]` сохраняются, `pr-check post` проходит. Тест `B13`, мутант `PKG-RESUBMIT-BASE`.
- **`pr-check.sh`, фаза `post` и `pr.md` P7** принимают `--commitment`/`--title` (ручной режим без заказа). Тест: `C4` (фикстура без `order.yaml`), `test-mo-prose [20]` (каждый вызов `pr-check` в `pr.md` несёт оба флага).
- **`pr-publish.sh`.** (а) Перед сетью — `pr-check.sh --phase post --no-tests` с теми же `--proj/--sid/--commitment/--title`; rc 1/2 — отказ без push, обхода нет; rc 3 не блокирует (`# PKG-P-POSTCHECK`, тест `P8`). (б) PR-шаг только для `github`; на `bare` при любом `delivery` `instruction: null`; в JSON добавлено `ready` (ветка с `CHANGE.yaml` на remote и, для `github` + `delivery: pr`, существующий PR); при `delivery: branch` PR не создаётся (`# PKG-P-BAREINSTR`, тест `P1`). Раздел «JSON-выходы»: `pr-publish.sh` дополнен полем `ready`.
- **`lib/pr-lib.sh` (замороженная библиотека, правка по решению оркестратора).** `pr_clean`: C1 (U+0080…U+009F) и U+2028/2029 → пробел (`# PKG-CLEAN-C1`); `pr_files`: путь с C1/U+2028/2029 — отказ; `pr-build` (`sc`) заменяет C1 пробелом.
- **`protocol-export.sh`** — резерв `verified[]` из строки итога (`# PKG-X-VERDICT`, тест `X11`).
- **`commands/start.md`, `commands/pr.md`** — `--from-order` в `auto` подтверждается (`[директива]`); `adr.registry` в `auto` — вопрос, прочие WARN P5 принимаются дефолтом без записи в `auto_decisions.md` (после P4 каталога сессии нет) — только в трейлер `SDX-PR-Ack` с раскрытием списка на P8 (дисклоуз).
- **`sdx-stage.sh`** (раздел «Новые и изменяемые файлы» — «не меняется»): исправлена одна строка текста отказа `next --to` под `no_code` (DEBT-046: обратные кавычки внутри двойных создавали файл `false` в cwd); тест `[43]` исполняется во временном каталоге проекта.
- **`.claude/sdx/verify-cmd.sh`** — рычаг К-10 реализован: `SDX_VERIFY_JOBS` (по умолчанию 2 при `nproc ≥ 4`, иначе 1; `1` — последовательно), вывод сьютов буферизуется и печатается в порядке сьютов, `Summary` и код возврата прежние. Замер под нагрузкой: 192 с → 126,6 с.
- **Граница (Р-1).** Зеркало `audit()` соответствует вендорённой версии (`SIMKIT_VERSION`); проверки более новых версий узла в нём отсутствуют до перевендоринга.

## Ручной сценарий для Verification

Автотестами **не** проверяются (и проверяются честно только вручную/на бинарнике):

1. **Живой `audit()` узла на пакете.** В дереве `sim-kit` 0.9.1 (реестр `mo`, PyYAML 6.0.3, образец — `tests/kit.sh:695–742`) завести bare-репозиторий `app.git` как `repo.url`, исполнителя с мандатом `delivery: pr`, обязательство; выдать мандат в проект-фикстуру, провести реальную сессию до `/sdx:pr` (`bare`, подтверждение push); на узле `./mo change poll app` → `./mo change audit app change/C-…`. Ожидание: **нет `reject`/`return` по формальным проверкам** (`manifest`, `format`, `manifest.commit`, `branch`, `scope`, `shared.declared`, `archive_sha256`, `adr`); `test:unit`/`review` — по настройке узла. Точные команды выдачи мандата — как в ручном сценарии FEAT-016 п.2 (не проверены проектированием).
2. **`gh pr create` на реальном репозитории GitHub** (тестовый): PR открыт против `repo.base`, заголовок `C: title`, тело из манифеста; затем `gh auth logout` → повтор: деградация до `bare` (ветка запушена, одна строка инструкции). Автотест проверяет только argv стаба.
3. **Доставка `protocol.yaml`.** Достать файл `git show sdx/<sid>@<rev>:.claude/sessions/<sid>/protocol.yaml`, положить в `work/<C>/` узла, `./mo work protocol <C>` → счётчики без ошибок. Это проверка схемы живым `protocol_check()`, не канала доставки (канала нет — К-18).
4. **Хук области на командные строки `/sdx:pr`** при `mandate.on_write: deny` и реальном `devagent_hook.py` 0.9.1: `bash pr-build.sh`, `bash protocol-export.sh`, `git commit --allow-empty -F -` не блокируются; ожидаемо, но не проверено исполнением (R-2).
5. **Проза `pr.md`/`archive.md`** (поведение модели): одноразовая сессия под мандатом с `bare`; шаги P0–P10, подтверждение push в `interactive` **и** в `auto`, отказ одной строкой без мандата, делегирование из `/sdx:archive`.
6. **`/sdx:start --from-order <msg_id>`** с реальным `mesh_endpoint.py pull` и директивой `work.order`, отправленной узлом (`./mo change order C ex1` со связью); `--from-issue` на реальном issue с YAML-блоком.
7. **`archive_sha256` на другой версии git** (исполнитель — git 2.53, узел — версия узла): сверить `audit()`.
8. **Замер полного прогона** `verify-cmd.sh` (бюджет ≤ 150 с без нагрузки).

## Трассировка REQ → компонент → тест

| REQ-PKG | Компонент | Тест |
|---|---|---|
| 1 | `pr.md`, `archive.md` (делегирование) | `test-mo-prose [19][20]`; ручной п.5 |
| 2 | `mandate-info.sh pr-mode`, прелюдия `pr.md` P0–P1 | `test-mandate-scope [M]` (`pr-mode`) + `PKG-PRMODE-*`; `test-mo-prose [20]` |
| 3 | `pr.md` P1–P10 (порядок), `protocol-export`, `pr-check`, `pr-build`, `pr-publish` | `test-mo-prose [20]` (порядок вызовов); блоки сьютов; ручной п.5 |
| 4 | `pr_session_rev`, `pr_order_load` (D-5) | `test-protocol-export X9` (`PKG-X-REV`); `test-pr-build B1` (после шага 5) |
| 5 | `pr_valid_id`, `pr_resolve`, `pr_base_ref`, `base.ancestor` | `test-pr-build B7, B9` + `PKG-ID`, `PKG-ANCESTOR`; `test-pr-check C2, C3` |
| 6 | `pr-build` (squash, тема) | `B1`, `B8`, `B11` |
| 7 | `pr_resolve --commitment` | `B1` (без заказа), `B7` (расхождение с заказом) |
| 8 | `pr-build` (plumbing, `tip^ == head`) | `B1`, `B2`, `B12` + `PKG-PLUMB`, `PKG-TIPPARENT` |
| 9 | `pr-build` (поля, шаблон) | `B1`, `B3`–`B5`, `B10` + `PKG-ARCHIVE`, `PKG-SHARED`, `PKG-SCOPE-TOUCHED`, `PKG-TEMPLATE-KEYS` |
| 10 | `jq tojson`, `pr_clean`, `pr_has_secret` | `B6`, `B7`; `test-pr-publish P5`; `test-order-import O6` + `PKG-QUOTE`, `PKG-SECRET` |
| 11 | `pr-check` (`pre`/`post`) | `test-pr-check C1`–`C7` + `PKG-C-*` |
| 12 | `diff.nonempty`, `shared.note`, `manifest.shared` | `C2`, `C5`, `B4` |
| 13 | `pr.md` P8 | `test-mo-prose [20]` («в любом gate_mode»); ручной п.5; К-2 |
| 14 | `pr-publish` (refspec, FF, whitelist) | `test-pr-publish P1`–`P3`, `P6` + `PKG-P-REFSPEC`, `-FF`, `-NOFOLLOW`, `-URLWL` |
| 15 | `pr-publish` (`bare`, `repo.url`/`origin`) | `P1`, `P4` |
| 16 | `pr-publish` (`gh`, деградация, тело PR) | `P5` + `PKG-P-GH`; ручной п.2 |
| 17 | `pr.md` P9, `mandate-info.sh pr-status` | `test-mandate-scope [M]` (`pr-status`); `test-mo-prose [20]` |
| 18 | `pr-build --resubmit`, FF-цепочка | `B8`, `P3` |
| 19 | `protocol-export`, squash без каталога | `X1`–`X9`, `B11` |
| 20 | разбор `decisions_log.md` | `X1`, `X2`, `X5`, `X6` + `PKG-X-ADR`, `PKG-X-ID`, `PKG-X-FMTB` |
| 21 | `questions/verified/deltas/done` | `X4`, `X8` + `PKG-X-EMPTY` |
| 22 | `adr: true`; доставка вне SDX | `X5`; текст протокола (`test-mo-prose [21]`) |
| 23 | `order-import from-file|from-msg`, `start.md` 1б | `test-order-import O1`–`O5` + `PKG-O-*`; `test-mo-prose [26]` |
| 24 | `order-import from-issue` | `O4` + `PKG-O-FENCE` |
| 25 | `stamp-state`, снимок, `sid_infix` | `O7` + `PKG-O-STAMP`; `test-sdx-stage [42]` |
| 26 | `pr-check` (`adr.registry`), `archive.md` п.2 | `C3` + `PKG-C-ADR`; `B5` |
| 27 | `pr-check` (`docs.final`) | `C2` + `PKG-C-DOCS-FINAL` |
| 28 | `sdx/mo/CHANGE.template.yaml`, `SIMKIT_SHA256` | `test-mo-inventory.sh` (c)/(d)/(e) |
| 29 | `sdx/templates/CONTRIBUTING-MO.md` | `test-mo-prose [27]`; `test-mo-inventory.sh` (d) |
| 30 | `archive.md`, протокол | `test-mo-prose [12][19][21]` |
| 31 | ADR-022 | `test-mo-prose [23]` |
| 32 | сниппет | `test-mo-prose [22]` (вхождение текста §6 + предложение), `test-snippet-check.sh` |
| 33 | `devops.md`, README×2, `CLAUDE.md`, дельты, версия | `test-mo-prose [17][24][25]` |
| 34 | `pr-mode`, все гейты «режим мандата» | все прежние сьюты без правок; `test-mandate-scope [M]` |
| 35 | `pr.md` (запреты), `pr-publish` (без force/`--all`) | `test-pr-publish P1`–`P3`, `P6`; `test-mo-prose [20]` |

## Перечень правок документов (REQ-PKG-30…33)

- **`sdx/protocol.md`:** (1) «Контракт закрытия сессии» — два варианта Closeout («мёрж» 1–8 и «пакет» `/sdx:pr`), пункты «Мост Closeout при мандате» переписаны: `bridge` (`pr|branch`) → пакет, ручная инструкция снята, `bridge:offer`/`undefined`/`error` сохранены; (2) подраздел «Мандат»: список скриптов (`pr-*`, `protocol-export`, `order-import`), служебный коммит с трейлерами, `commitment` в `session_state.json`, граница (5) про `docs_in_repo` дополнена (`final` = `full`, проверка реестра по `docs_paths`), граница «внутренние записи скриптов не видны хуку»; (3) «Вендорённые компоненты» — четвёртый файл `CHANGE.template.yaml`, оговорка К-1, `CONTRIBUTING-MO.md` — не вендорённый (`sdx/templates/`); (4) «Журнал решений» — оба формата записи названы.
- **`docs/DECISIONS.md`:** **ADR-022 «Пакет изменения — второй вариант Closeout»** (контекст, решение D-1…D-12 кратко, альтернативы, последствия; снимает мост FEAT-016 как временный для `pr|branch`; поправка к ADR-021: мост → пакет, `docs_in_repo: final = full`); датированная поправка к ADR-020 не нужна (набор этапов не меняется).
- **`docs/specs/mo-interop.md`:** REQ-MAND-23/23a/23b — отметка «заменено REQ-PKG-30 для `pr|branch`»; раздел «Дельты FEAT-017» (REQ-PKG-1…35).
- **`docs/designs/mo-interop.md`:** «Дельта FEAT-017» — сжатый перенос этого дизайна; полный дизайн после Closeout — `docs/history/designs/feat-017-mo-change-package-20261031.md`.
- **`docs/designs/decision-journal-and-resume.md`:** датированная поправка — необязательное поле `commitment` в `session_state.json`; формат B записи журнала.
- **`commands/{archive,start,status}.md`, `commands/pr.md`:** см. «Компоненты».
- **`agents/devops.md`:** «Режим МО»: действие сдачи — `/sdx:pr` (основная сессия, не `devops`); слияний вне `scope.branches` и тегов по-прежнему нет; пункт «При `delivery: artifact.offer`…» сохранён; упоминание `CHANGE.template.yaml`.
- **`sdx/templates/claude-md-snippet.md`:** пункт «МО над стендами» заменяется текстом §6 `MO-INTEROP.md` 0.9.1 плюс одно предложение с сохранёнными нормами 2.4.0 (REQ-PKG-32); `snippet-check.sh` сообщает `STALE` для проектов со старым блоком, `reconcile` предлагает обновление (без правок кода скрипта).
- **`README.md` / `README.en.md`** (согласованная пара): таблица `sdx/mo/` — четыре файла; новые скрипты `sdx/hooks/`, `commands/pr.md`, `sdx/templates/CONTRIBUTING-MO.md`; абзац «Версия 2.5.0 — сдача пакетом изменения».
- **`CLAUDE.md`:** §3 «Этапы → Closeout» — два варианта; §6 — перечень `sdx/hooks/` (+`pr-*`, `protocol-export`, `order-import`, `lib/pr-lib`), `sdx/mo/` (четыре файла, `CHANGE.template.yaml`), `sdx/templates/CONTRIBUTING-MO.md`.
- **`docs/backlog/FEAT-017-…md`:** уточнения (`CONTRIBUTING-MO.md` в `sdx/templates/`, поле `change` в `artifact.offer` не добавляется, `docs_in_repo`); на Closeout `status: closed`, `session`. Новые записи на Closeout: `DEBT` «токен `closeout-mode` → `package`», `DEBT` «единый формат `decisions_log.md`», `IDEA` «upstream-запись владельцу МО (К-18)», `IDEA` «параллельный раннер `verify-cmd.sh`» (если не понадобится по К-10).
- **`.claude-plugin/plugin.json`** → `2.5.0` (`marketplace.json` версии не содержит); `docs/history/releases/v2.5.0-notes.md` — двуязычные накопительные заметки (русский блок, `---`, английский; раздел «Границы» с непроверенным: живой `audit()`, `gh` на реальном GitHub, `archive_sha256` между версиями git, хук области на `/sdx:pr`, канал `protocol.yaml`); тег `v2.5.0` на merge-коммите; push/релиз — только по явной просьбе.
- **`.claude/sdx/verify-cmd.sh`:** комментарий о длительности и числе сьютов (19 → 24) по факту замера.

## Декомпозиция для PLAN (порядок и критерий готовности)

0. **T0 — вендоринг (К-1).** `sdx/mo/CHANGE.template.yaml` + строка `SIMKIT_SHA256` + упоминания на поверхностях; `sdx/templates/CONTRIBUTING-MO.md`. Готово: `test-mo-inventory.sh` зелёный, хеш сверен с тегом.
1. **T1 — `lib/pr-lib.sh` + `mandate_fnmatch`** + дополнения `test-mandate-lib.sh` (+`PKG-FNMATCH`, `PKG-ID`, `PKG-SECRET`, `PKG-URL-WL`, `PKG-SESSREV` статически через сьюты потребителей). Готово: таблицы `pr_valid_id`/`pr_url_ok`/`fnmatch` и портируемость (`FORBID`) зелёные.
2. **T2 — `lib/pkg-fixture.sh`** (шаблон фикстуры, `pkg_craft_*`, python-оракул `audit()` как функция). Готово: оракул даёт `approve` на пакете, собранном фабрикой «по образцу `mkpkg`», и `reject/return` на красных фабриках.
3. **T3 — `order-import.sh`** + `test-order-import.sh` + `stamp-state` + `test-sdx-stage [42]`. Независим от T5–T7 после T1.
4. **T4 — `protocol-export.sh`** + `test-protocol-export.sh`. Независим после T1.
5. **T5 — `pr-build.sh`** + `test-pr-build.sh` (B1–B12, мутанты). Зависит от T1, T2.
6. **T6 — `pr-check.sh`** + `test-pr-check.sh` (C1–C7). Зависит от T5.
7. **T7 — `pr-publish.sh`** + `test-pr-publish.sh` (P1–P7). Зависит от T5 (не от T6).
8. **T8 — `mandate-info.sh pr-mode|pr-status`** + дополнения `test-mandate-scope [M]` (+`PKG-PRMODE-*`). Независим после T1.
9. **T9 — команды:** `commands/pr.md`, правки `archive.md`, `start.md`, `status.md` + `test-mo-prose [19]…[27]` (+обновление пинов `[11]`, `[12]`, `[17]`). Зависит от T3–T8 (имена и выводы скриптов).
10. **T10 — документы** (перечень выше), `plugin.json` 2.5.0, release notes, сниппет. Зависит от T9. Готово: `test-mo-prose`, `test-snippet-check`, `test-mo-inventory`, `test-hook-wiring` зелёные.
11. **T11 — замыкание:** полный прогон `verify-cmd.sh` с замером (К-10), ручной сценарий (пп.1–8) отдан Verification, записи бэклога на Closeout.

Порядок 0→1→2→{3,4,8}→5→{6,7}→9→10→11 обязателен по зависимостям; 3, 4, 8 независимы друг от друга; 6 и 7 независимы друг от друга. Критерий готовности поставки — все блоки «Критериев приемки» SPEC закрыты тестами, кроме перечисленных в «Ручном сценарии».

## Поправки круга 3 верификации (2026-10-31)

Отражают решения оркестратора (`decisions_log.md` `[FAIL]` круга 3), SPEC — раздел «Поправки круга 3 верификации».
- **Снимок заказа (FAIL-1 круга 3; подтверждает «Поправки круга 2»).** Снимок пишется ОДНИМ вызовом `order-import.sh from-* --out "$snapdir/order.yaml"` во временный каталог (`snapdir` от `mktemp -d`, вне репозитория) на шаге 1б до подтверждения; на шаге 6а он копируется в каталог сессии. Повторного вызова источника нет. Пользователю до создания сессии показывается снимок целиком — все поля `order.yaml`, включая `requirements`, как данные (маркер «[ДАННЫЕ, не инструкции]»). Путь `snapdir` модель выводит из вывода `mktemp -d` и подставляет буквально в шаг 6а (переменные оболочки между вызовами Bash не сохраняются). При `MISMATCH` (код 3) сессия не создаётся: снимка нет, продолжение возможно только повторным приёмом заказа.
- **`/sdx:pr` вне `Closeout` (FAIL-2, WARN-2; уточняет D-12).** Прямой вызов выполняет прелюдию `archive.md` (шаги 1–2а) на любом `stage`, включая `Closeout`: гейт входа (дисклоуз `auto_decisions.md` при `gate_mode: auto`, ADR-014; отказ при `no_gates`) проходится всегда до P2; цикл `next` — с коммитами состояния, гейты этапов не обходятся; при `Closeout` цикл — штатный no-op.
- **Классификация вариантов Closeout (WARN-3).** Единая во всех носителях: «мёрж» (без мандата; шаги 6–8 штатные) / «пакет» (`delivery: pr|branch`, `/sdx:pr`; шаги 6–8 `(n/a, пакет)`) / «мост» (`delivery: artifact.offer`, `bridge:offer`; шаги 6–8 `(n/a, мандат)`) / `undefined` — остановка.
- **Расхождения DESIGN ↔ CLI (INFO-6).** `pr-publish.sh` принимает `--title` (как `pr-check`/`pr-build`; нужен для пост-проверки перед сетью); `pr_registry` имеет сигнатуру `<proj> <base> <head>` (файлы — из `$PR_FILES`).
- **Нотация формата B журнала решений (INFO-2)** — `- [YYYY-MM-DD ][<тег>] текст` (дата необязательна, тег в скобках из закрытого набора) — единая в D-10, К-4, протоколе и `docs/designs/decision-journal-and-resume.md`.
- **Решение `[деструктив]` на P7 после P4 (INFO-5):** каталога сессии нет, поэтому записывается в трейлер служебного коммита `SDX-PR-Ack` / `SDX-PR-Decision` (если P9 не достигнут — в итоговое сообщение пользователю).
