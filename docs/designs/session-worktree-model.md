# Technical Design: Рефакторинг работы с сессиями (git worktree + tracked artifacts + автоопределение основной ветки)

## Архитектурный обзор

Рефакторинг переводит жизненный цикл сессии на модель **«одна сессия = один git worktree на
ветке `sdx/<id>`»**, внутри которого содержательные артефакты сессии становятся версионируемыми
и коммитятся инкрементально. Это одновременно:

- делает физически исполнимым давно задекларированное решение ADR-005 «артефакты коммитятся в
  ветку инкрементально» (устраняет C7 — сейчас блокируется `.gitignore`);
- устраняет слепой `git add -A && git commit` в `switch.md` (C2) — переключение сессий больше
  не трогает общее рабочее дерево, потому что каждая сессия физически изолирована в своём
  каталоге;
- вводит динамическое автоопределение имени основной ветки (`main`/`master`/иное) через единый
  шелл-хелпер, переиспользуемый хуками и prose-командами (REQ-BRANCH-*).

Три опорных инженерных инварианта дизайна:

1. **Enforcement держится на `$CLAUDE_PROJECT_DIR`.** Все хуки резолвят активную сессию через
   `git -C "$proj" branch --show-current` и строят пути от `$proj`. По эмпирике context_report
   §8 (консервативное допущение) `CLAUDE_PROJECT_DIR` фиксируется на каталоге запуска CLI и НЕ
   следует за `cd` внутри процесса. Отсюда прямое следствие: **сессия ведётся из отдельного
   экземпляра CLI, запущенного в каталоге её worktree.** Дизайн обязан быть корректным именно
   при этом worst-case допущении (если харнесс на деле проксирует `cwd → CLAUDE_PROJECT_DIR`,
   ручные хендоффы схлопываются в оптимизацию, но корректность не меняется).

2. **`main` никогда не видит файлы сессии — даже мимолётно** (вариант A, см. ADR-009). Удаление
   каталога сессии оформляется коммитом `git rm -r` НА ВЕТКЕ `sdx/<id>` ДО мёржа. Мёрж `--no-ff`
   вносит в DAG основной ветки всю историю сессии (достижима через второй родитель merge-коммита
   → не собирается GC), но HEAD-дерево основной ветки чисто. Так REQ-SESS-3 и REQ-SESS-4
   выполняются одновременно.

3. **`archive-verify.sh` worktree-агностичен.** Полагается только на переданный `$proj` и git;
   `rm -rf` каталога сессии превращается из активного деструктива в проверку отсутствия +
   штатное `git worktree remove`. Тесты параметризуются `$CLAUDE_PROJECT_DIR`, добавляется
   worktree-фикстура.

### Схема размещения

```
<repo-root>/                          ← основной worktree, ветка <default> (main/master)
├─ .git/                              ← общий git-каталог (шарится всеми worktree)
├─ .gitignore                         ← targeted-паттерны (см. ниже), tracked на всех ветках
├─ .claude/sdx/hooks/*.sh             ← код хуков, tracked, идентичен во всех worktree
├─ docs/…                             ← постоянные доки, tracked
└─ .sdx/
   ├─ bundles/                        ← (gitignored) транспорт import/export
   └─ worktrees/                      ← (gitignored) КОРЕНЬ worktree сессий
      └─ <id>/                        ← worktree сессии, ветка sdx/<id>
         ├─ .claude/sdx/hooks/*.sh    ← те же скрипты (шаринг по ветке)
         ├─ docs/…                    ← та же ветка → правки идут в sdx/<id>
         └─ .claude/sessions/<id>/    ← АРТЕФАКТЫ СЕССИИ (tracked на sdx/<id>)
            ├─ session_state.json     ← tracked
            ├─ session.log            ← tracked
            ├─ SPEC.md / DESIGN.md …  ← tracked
            ├─ .stopgate.count        ← IGNORED (REQ-SESS-2)
            └─ .stopgate.out          ← IGNORED (REQ-SESS-2)
```

Для хука/команды, запущенных в worktree сессии: `proj = .sdx/worktrees/<id>/`,
`sid = <id>`, путь к состоянию `proj/.claude/sessions/<id>/session_state.json` разрешается
как `.sdx/worktrees/<id>/.claude/sessions/<id>/…`. Двойное вхождение `<id>` (в пути worktree и в
пути артефактов) — осознанная косметическая цена: слой worktree даёт запись в `git worktree
list`, слой `.claude/sessions/<id>/` сохраняет канонический путь, на который уже завязаны ВСЕ
хуки (правок путей в хуках не требуется).

---

## Решения по 8+1 открытым вопросам

| # | Вопрос | Решение | Кратко |
|---|--------|---------|--------|
| 1 | Расположение worktree | **Внутри репо**, gitignored `.sdx/worktrees/<id>/`; escape-hatch `SDX_WORKTREE_ROOT` | предсказуемость путей + унификация с `.sdx/`; самовложенность закрыта gitignore |
| 2 | Порядок удаления файлов | **Вариант A** — `git rm -r` коммитом на ветке до мёржа | `main` HEAD никогда не содержит файлы сессии; история жива через merge-DAG |
| 3 | Allowlist версионируемого | **Корневой `.gitignore`**, targeted-паттерны; НЕ per-directory | одна точка, не требует scaffolding в `start.md` |
| 4 | Судьба `.claude/sessions/` | **Сохранить** имя/относительный путь | минимум правок; хуки не трогаем |
| 5 | Семантика `/sdx:switch` | **Инструкция открыть CLI в каталоге worktree** + вывод `git worktree list` | под консервативным допущением §8; полностью снимает C2 |
| 6 | Миграция vs cutover | **Чистый cutover**, breaking change в ADR-009; текущая сессия закрывается гибридно вручную | активных не-worktree сессий в мета-проекте нет |
| 7 | Тестирование archive-verify | **worktree-агностичный хук** + новые сценарии tracked-files + worktree-фикстура | переписать gitignore-допущение фикстур |
| 8 | Автоопределение ветки | **Хелпер `lib/default-branch.sh`**: `origin/HEAD` → `init.defaultBranch` → эвристика `main`/`master` | единая точка для хуков и prose |
| 9 | ADR | **ADR-009** (worktree+tracked) и **ADR-010** (автоопределение ветки) | см. раздел ADR |

Обоснования и отклонённые альтернативы — в разделе ADR ниже.

---

## Компоненты и Интеграции

### Инфраструктура (хуки, скрипты)

- **[ADDED] `.claude/sdx/hooks/lib/default-branch.sh`** — новый общий хелпер. Печатает имя
  основной ветки для проекта. Вызывается хуками и (документированно) агентом в prose-командах.
  Единственный источник истины резолва (REQ-BRANCH-1/4).

- **[MODIFIED] `.claude/sdx/hooks/archive-verify.sh`** — (а) резолв основной ветки через
  `lib/default-branch.sh` вместо литерала `main` (REQ-BRANCH-2); (б) деструктив `rm -rf`
  заменён на проверку отсутствия каталога сессии в дереве основной ветки (post-A он уже удалён
  коммитом) + `git worktree remove --force` найденного worktree (REQ-WT-5); (в) worktree-путь
  обнаруживается через `git worktree list --porcelain` по ветке `sdx/<id>` — хук не хардкодит
  `.sdx/worktrees/`.

- **[MODIFIED] `.claude/sdx/hooks/test-archive-verify.sh`** — фикстуры перестают гитигнорить
  `.claude/sessions/`; добавляются сценарии tracked-файлов + вариант-A + worktree-remove +
  `master`-репозиторий. См. раздел «Тестирование».

- **[UNCHANGED, зафиксировать] `.claude/sdx/hooks/stage-gate.sh`, `stop-gate.sh`** — уже
  worktree-совместимы (резолв сессии по ветке, пути от `$proj`, per-session temp помечен
  «worktree-safe»). Правок кода не требуют. **Косвенная зависимость:** их `.stopgate.*`
  теперь обязаны быть gitignored (иначе грязнят дерево на каждом Stop и ломают инвариант 1) —
  обеспечивается корневым `.gitignore` (REQ-SESS-2).

- **[UNCHANGED, зафиксировать] `.claude/sdx/hooks/prod-guard.sh`, `preflight.sh`** —
  worktree-нейтральны (не резолвят сессию по ветке/пути). Явно вне объёма правок (SPEC «Вне
  объёма»).

### Конфигурация

- **[MODIFIED] `.gitignore`** — снять широкий `.claude/sessions/`, добавить targeted-паттерны.
  Точная конфигурация — в разделе «Схема данных / конфиги».

### Команды `/sdx:*`

- **[MODIFIED] `.claude/commands/sdx/start.md`** — `git worktree add .sdx/worktrees/<id> -b
  sdx/<id>` вместо `git checkout -b`; seed-файлы состояния пишутся в worktree, коммитятся на
  ветку; хендофф-инструкция «продолжить сессию из CLI в каталоге worktree».

- **[MODIFIED] `.claude/commands/sdx/switch.md`** — **полная переписка**: убрать `git add -A`,
  `git commit`, `git checkout` (REQ-WT-2, [REMOVED] слепой авто-коммит). Новое поведение —
  вывести `git worktree list`, найти путь worktree для `sdx/<id>` и инструктировать пользователя
  открыть/запустить CLI в этом каталоге.

- **[MODIFIED] `.claude/commands/sdx/archive.md`** — новая последовательность Closeout под
  вариант A: перенос дельт (на ветке) → `git rm -r` каталога сессии (на ветке) → мёрж `--no-ff`
  в основную ветку → `archive-verify.sh` (проверка + `git worktree remove`). Чётко разведены
  «коммит дельт» и «коммит удаления». Хендофф на основную ветку/CLI для мёржа.

- **[MODIFIED] `.claude/commands/sdx/verify.md`** — diff через динамическую основную ветку
  (REQ-BRANCH-3) + **исключение `.claude/sessions/**` из diff для reviewer** (иначе
  fresh-eyes-diff теперь замусорен tracked-артефактами сессии — регресс, введённый tracked-
  моделью).

- **[MODIFIED] `.claude/commands/sdx/init.md`** — шаг 2: перестать добавлять `.claude/sessions/`
  в `.gitignore`; вместо этого прописывать targeted-паттерны (worktree-модель). Убрать
  предпосылку об игноре всего каталога сессий.

- **[MODIFIED, факультативно] `.claude/commands/sdx/status.md`** — листинг активных сессий через
  `git worktree list` (закрывает часть C5). Не блокирует приёмку (SPEC «Вне объёма»), но дёшево
  и когерентно новой модели — включаем как явное улучшение.

### Документация фреймворка

- **[MODIFIED] `.claude/sdx/protocol.md`** — новый подраздел «Модель сессии = worktree = ветка»;
  переписать §Enforcement-слой (archive-verify под вариант A) и §Контракт закрытия (порядок:
  удаление ДО мёржа); заменить `main` на «основную ветку (автоопределяется)» в §Fresh-eyes,
  §Контракт закрытия, §Git-флоу.

- **[MODIFIED] `CLAUDE.md` §6** — строка «`.claude/sessions/`: (Игнорируется git…)» —
  прямое противоречие целевому поведению; переписать под worktree/tracked-модель.

- **[MODIFIED] `docs/DECISIONS.md`** — добавить **ADR-009** и **ADR-010** (полные тексты —
  раздел ADR ниже). ADR-005 НЕ переписывается задним числом (прецедент ADR-008).

> **Пометка для DevOps-агента:** инфраструктурных изменений среды (CI, деплой, контейнеры) нет.
> Есть операционное изменение рабочего процесса разработчика: параллельные сессии = несколько
> каталогов worktree + несколько CLI-инстансов. При наличии IDE с рекурсивным file-watcher
> рекомендуется исключить `.sdx/` из индексации; предусмотрен escape-hatch `SDX_WORKTREE_ROOT`
> для выноса worktree за пределы репозитория на проектах, где вложенность создаёт проблемы.

---

## Схема данных / конфиги

### `.gitignore` (точная новая конфигурация)

```gitignore
# SDX: worktree-каталоги сессий (git-checkout'ы веток sdx/<id>) — никогда не трекаются
#      в основной ветке; предотвращает самовложенность worktree в рабочее дерево.
.sdx/worktrees/

# SDX: эфемерные scratch-файлы enforcement-слоя (loop-guard, буфер верификации).
#      НЕ версионируются ни при каких условиях (REQ-SESS-2).
.claude/sessions/*/.stopgate.*

# SDX: переносимые бандлы import/export (транспортные артефакты).
.sdx/bundles/

# Локальные настройки Claude Code.
.claude/settings.local.json
```

**Что изменилось и почему это выполняет требования:**
- Удалён широкий `.claude/sessions/` → содержательные `.md`/`.json`-артефакты сессии становятся
  трекаемыми (REQ-SESS-1). Явный allowlist не нужен: игнорируем точечно только шум.
- `.claude/sessions/*/.stopgate.*` → эфемерные буферы хуков не попадают в индекс (REQ-SESS-2),
  дерево остаётся чистым на каждом Stop (инвариант 1 archive-verify не ломается).
- `.sdx/worktrees/` → каталоги worktree, физически лежащие внутри репозитория, не трекаются
  основной веткой (гарант того, что HEAD-дерево `main` не тянет за собой копии деревьев сессий).
  Паттерн действует и внутри worktree (файл `.gitignore` tracked → шарится по ветке) → вложенные
  worktree тоже не трекаются.

Замечание: на основной ветке каталог `.claude/sessions/` в норме отсутствует (существует только
внутри worktree на ветке `sdx/<id>`), поэтому паттерн `.stopgate.*` безвреден при отсутствии
каталога.

### `session_state.json`

Схема без изменений (см. protocol.md). Поле `git_branch` продолжает хранить `sdx/<id>`. Опция:
можно добавить необязательное поле `worktree_path` для удобства `status`/`archive`, но не
обязательно — путь надёжно резолвится из `git worktree list --porcelain`. **Решение: не
добавлять** (избегаем дублирования источника истины; git — реестр).

---

## Псевдокод изменённых скриптов

### `.claude/sdx/hooks/lib/default-branch.sh` [ADDED]

```bash
#!/usr/bin/env bash
# SDX default-branch resolver (REQ-BRANCH-1/2/3/4).
# Prints the repository's default/main branch name. Single source of truth,
# reused by hooks and (documented) by prose commands.
# Usage: default-branch.sh [proj_dir]   (proj_dir defaults to CWD)
# Safe with no remote configured.
set -uo pipefail
proj="${1:-${CLAUDE_PROJECT_DIR:-.}}"

# 1) Authoritative signal when a remote exists: origin/HEAD symbolic ref.
ref="$(git -C "$proj" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null || true)"
if [ -n "$ref" ]; then
  echo "${ref#refs/remotes/origin/}"; exit 0
fi

# 2) Configured init.defaultBranch (covers fresh repos with no remote).
cfg="$(git -C "$proj" config --get init.defaultBranch 2>/dev/null || true)"
if [ -n "$cfg" ] && git -C "$proj" show-ref --verify --quiet "refs/heads/$cfg"; then
  echo "$cfg"; exit 0
fi

# 3) Heuristic: prefer an existing local main, then master.
if   git -C "$proj" show-ref --verify --quiet refs/heads/main;   then echo main
elif git -C "$proj" show-ref --verify --quiet refs/heads/master; then echo master
elif [ -n "$cfg" ]; then echo "$cfg"          # configured name even if branch absent yet
else echo main                                # last-resort default
fi
```

Порядок фолбэков обоснован: `origin/HEAD` — единственный сигнал, отражающий «что команда считает
основной веткой» на репозиториях с remote (в т.ч. `master`-репо); при отсутствии remote —
конфиг проекта; затем эвристика по фактически существующим локальным веткам. Хелпер никогда не
падает и всегда печатает непустое имя (безопасность при отсутствии remote — REQ-BRANCH-4).

> Известное ограничение: `origin/HEAD` может быть протухшим (`git remote set-head origin -a`
> лечит). Это редкий крайний случай; фиксируем в комментарии хелпера, а не усложняем резолвер.

### `.claude/sdx/hooks/archive-verify.sh` [MODIFIED]

```bash
#!/usr/bin/env bash
# SDX archive-verify (REQ-CLOSEOUT-1): enforce Closeout invariants 1, 5, 6
# under the worktree + tracked-artifacts model (ADR-009) and dynamic default
# branch (ADR-010). Called from /sdx:archive AFTER the session branch has been
# merged into the default branch. Run with CLAUDE_PROJECT_DIR = MAIN worktree root.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
proj="${CLAUDE_PROJECT_DIR:-.}"
sid="${1:?session_id required}"
sdir="$proj/.claude/sessions/$sid"
def="$("$here/lib/default-branch.sh" "$proj")"      # ADR-010: no hardcoded 'main'
fail=0

# Invariant 1: main worktree clean (session files already git-rm'd on branch pre-merge,
#              variant A → nothing dirty here).
if [ -n "$(git -C "$proj" status --porcelain)" ]; then
  echo "[FAIL] рабочее дерево не чистое — есть незакоммиченные изменения." >&2; fail=1
fi

# Invariant 5: branch sdx/<id> provably merged into the DEFAULT branch.
if git -C "$proj" rev-parse --verify "sdx/$sid" >/dev/null 2>&1; then
  if ! git -C "$proj" branch --merged "$def" --format='%(refname:short)' | grep -qx "sdx/$sid"; then
    echo "[FAIL] ветка sdx/$sid не слита в $def." >&2; fail=1
  fi
elif [ "${SDX_ARCHIVE_NO_BRANCH_OK:-0}" != "1" ]; then
  echo "[FAIL] ветка sdx/$sid отсутствует — слияние недоказуемо; деструктив отменён. (SDX_ARCHIVE_NO_BRANCH_OK=1 для оверрайда)" >&2
  fail=1
fi

# Invariant 6 (variant A): session dir MUST be absent from the default-branch tree.
# Its presence means the git-rm-before-merge step (Closeout) was skipped → block.
if [ -e "$sdir" ] && git -C "$proj" ls-files --error-unmatch "$sdir" >/dev/null 2>&1; then
  echo "[FAIL] каталог сессии всё ещё tracked в дереве $def — пропущен коммит 'git rm' до мёржа (вариант A)." >&2
  fail=1
fi

[ "$fail" -ne 0 ] && { echo "[ABORT] Closeout не завершён — устраните FAIL и повторите." >&2; exit 1; }

# Post-checks passed → штатное освобождение worktree (REQ-WT-5) вместо rm -rf.
# Обнаружение пути worktree по ветке (хук не хардкодит .sdx/worktrees/).
wt="$(git -C "$proj" worktree list --porcelain \
        | awk -v b="refs/heads/sdx/$sid" '
            /^worktree /{p=substr($0,10)} /^branch /{if($2==b) print p}')"
if [ -n "$wt" ]; then
  git -C "$proj" worktree remove --force "$wt" 2>/dev/null \
    || { echo "[FAIL] не удалось освободить worktree $wt" >&2; exit 1; }
fi
# Страховка: физического каталога артефактов в основном дереве быть не должно.
if [ -d "$sdir" ]; then
  rm -rf "$sdir"
  [ -d "$sdir" ] && { echo "[FAIL] не удалось удалить остаточный $sdir" >&2; exit 1; }
fi

# Delete the merged branch (safe -d: only if merged; no-op if already gone).
git -C "$proj" branch -d "sdx/$sid" >/dev/null 2>&1 || true

echo "[OK] Closeout-инварианты выполнены: дерево чистое, ветка слита в $def, worktree/сессия $sid освобождены."
```

Ключевые отличия от текущей версии: (1) `def` вместо `main`; (2) новый инвариант «каталог сессии
не tracked в дереве основной ветки» — детектор пропуска варианта A; (3) `git worktree remove`
вместо/до `rm -rf`; `rm -rf` остаётся лишь страховкой на остаточный физический каталог. Порядок
«проверки → потом любое деструктивное действие» сохранён.

---

## Последовательности

### Sequence 1 — `/sdx:start` (создание сессии)

```
Оркестратор в ОСНОВНОМ CLI (proj = repo-root, ветка = <default>):
  1. session_id ← сгенерировать; триаж трека.
  2. git worktree add .sdx/worktrees/<id> -b sdx/<id>        # REQ-WT-1
  3. mkdir -p .sdx/worktrees/<id>/.claude/sessions/<id>
  4. записать session_state.json (git_branch=sdx/<id>, track, stage), session.log seed
  5. git -C .sdx/worktrees/<id> add .claude/sessions/<id>    # tracked (REQ-SESS-1)
     git -C .sdx/worktrees/<id> commit -m "sdx(<id>): init session state"
  6. ХЕНДОФФ: «Продолжите сессию из CLI, запущенного в .sdx/worktrees/<id>/»
     (обоснование — консервативное допущение §8: enforcement резолвится по
      CLAUDE_PROJECT_DIR = каталог запуска CLI = worktree сессии).
Дальнейшие /sdx:next|checkpoint|verify выполняются из CLI сессии (proj = worktree).
```

### Sequence 2 — Closeout под вариант A (`/sdx:archive`)

```
ФАЗА 1 — в CLI СЕССИИ (proj = .sdx/worktrees/<id>, ветка = sdx/<id>):
  1. Убедиться: все артефакты закоммичены, дерево worktree чистое.
  2. Перенос дельт в ПОСТОЯННЫЕ доки (файлы docs/ существуют в checkout ветки sdx/<id>):
       docs/specs/…, docs/designs/…, docs/history/…  → edit → commit на sdx/<id>.
  3. Архив PLAN.md → docs/history/plans/<id>.md → commit на sdx/<id>.
  4. Обновить глобальный лог docs/history/… → commit на sdx/<id>.
  5. git rm -r .claude/sessions/<id> && git commit -m "sdx(<id>): drop session artifacts pre-merge"
       # вариант A: HEAD ветки больше не содержит каталог сессии (REQ-SESS-3);
       # на диске worktree файлы тоже удалены, но worktree-каталог цел.
  6. ХЕНДОФФ на основной CLI (мёрж должен идти в основном worktree — git запрещает
     checkout той же ветки в двух worktree).

ФАЗА 2 — в ОСНОВНОМ CLI (proj = repo-root):
  7. def=$(.claude/sdx/hooks/lib/default-branch.sh)
     git checkout "$def"
     git merge --no-ff sdx/<id> -m "Merge sdx/<id>"
       # docs-дельты вливаются в основную ветку; каталога сессии в HEAD-дереве НЕТ;
       # --no-ff: вся история sdx/<id> достижима из merge-коммита (REQ-SESS-4).
  8. bash .claude/sdx/hooks/archive-verify.sh <id>
       # инв.1 (дерево чисто) + инв.5 (слита в $def) + инв.6 (каталог не tracked)
       # → git worktree remove --force .sdx/worktrees/<id>  (REQ-WT-5)
       # → git branch -d sdx/<id>
  9. Итоговая сводка Closeout.
```

Инвариант «`main` получает только merge-коммиты» сохраняется (в отличие от отклонённого варианта
B). Проверка REQ-SESS-3: `git ls-tree -r <default>` не содержит `.claude/sessions/<id>/*`;
`git log <merge>^2 -- .claude/sessions/<id>` показывает историю (не в HEAD).

### Sequence 3 — `/sdx:switch <id>` (переключение)

```
Оркестратор (любой CLI):
  1. wt = git worktree list --porcelain | (найти путь по ветке sdx/<id>)
  2. Если не найдено → ошибка: «сессия <id> не активна (нет worktree) — /sdx:start или уже
     заархивирована».
  3. НИКАКИХ git add/commit/checkout (REQ-WT-2; [REMOVED] слепой авто-коммит).
  4. Инструкция пользователю: «Откройте/запустите CLI в каталоге <wt> — это и есть
     переключение на сессию <id>. Текущее рабочее дерево не затрагивается.»
```

---

## Обработка ошибок и Граничные случаи

- **Пропущен `git rm` до мёржа (вариант A не выполнен).** `archive-verify.sh` инвариант 6 ловит
  tracked-каталог сессии в дереве основной ветки → `[FAIL]`, деструктив отменён. Не молчаливая
  деградация.
- **Ветка `sdx/<id>` отсутствует при archive.** Сохранено текущее fail-closed поведение +
  оверрайд `SDX_ARCHIVE_NO_BRANCH_OK=1` (context_report §3).
- **`git worktree remove` при незакоммиченных/ignored-файлах.** Используем `--force` (безопасно:
  вызывается только ПОСЛЕ прохождения инвариантов 1/5/6 — доказано, что содержательное состояние
  сохранено в git). Игнорируемые `.stopgate.*` не блокируют удаление.
- **Самоудаление worktree из-под cwd.** В канонической последовательности мёрж+verify идут из
  ОСНОВНОГО CLI, поэтому worktree сессии не удаляется «из-под ног». Если оператор всё же гонит
  archive из CLI сессии, отмечаем: терминал окажется в удалённом каталоге — вернуться в основной.
- **Отсутствие remote (`origin/HEAD` не задан).** `default-branch.sh` тихо падает на шаг 2/3,
  возвращает валидное имя (REQ-BRANCH-4). Хук остаётся безопасным.
- **`master`-репозиторий.** `default-branch.sh` вернёт `master` (через `origin/HEAD` или
  эвристику) → инвариант 5 и diff считаются относительно `master` (REQ-BRANCH-2/3).
- **`.stopgate.*` в diff/статусе.** Игнорируются корневым паттерном → не грязнят дерево
  (инвариант 1) и не попадают в reviewer-diff.
- **Reviewer-diff замусорен tracked-артефактами сессии.** Ранее файлы сессии были gitignored и
  не попадали в `main...sdx/<id>`; теперь попадают. `verify.md` исключает `.claude/sessions/**`
  из diff pathspec'ом, сохраняя фокус fresh-eyes на реальной поставке.
- **Вложенный worktree внутри worktree.** Запрещаем конвенцией; технически предотвращён тем, что
  `.sdx/worktrees/` gitignored и на ветке сессии (не трекается, не индексируется).
- **Параллельные сессии с грязными деревьями.** Физически изолированы разными каталогами
  worktree (REQ-WT-3) — правки одной невидимы другой by construction.

---

## Безопасность

- **Устранение слепого `git add -A` (C2).** Главный security-выигрыш: `switch.md` больше не
  коммитит произвольное содержимое рабочего дерева (потенциальные секреты/мусор) под шумным
  сообщением. Переключение вообще не мутирует git-состояние (REQ-WT-2).
- **Деструктив только после доказанных инвариантов.** Порядок «проверки → потом
  worktree remove/branch -d» сохранён; `--force` применяется исключительно за гейтом инвариантов.
- **`--force` у `git worktree remove`** несёт риск потери НЕзакоммиченных данных worktree —
  снят тем, что инвариант 1 (чистое дерево) и инвариант 5 (слияние) уже подтвердили сохранность
  содержательного состояния в git до вызова.
- **Автоопределение ветки не расширяет поверхность атаки.** Хелпер read-only, не исполняет
  внешний ввод; имя ветки берётся из локального git-состояния.
- **Секреты в tracked-артефактах.** Новое: `session.log`/`session_state.json` теперь версионируются
  и (при push) видны команде. Это соответствует цели C7, но фиксируем норму: в артефакты сессии
  не помещать секреты (лог экономный, durable-события — protocol.md). Отдельного механизма
  редактирования не вводим (вне объёма).

---

## Риски и деградация

1. **[Высокий] Допущение о `CLAUDE_PROJECT_DIR`.** Весь enforcement и модель «сессия = свой
   CLI в worktree» держатся на том, что харнесс фиксирует `CLAUDE_PROJECT_DIR` на каталоге
   запуска CLI. Эмпирика §8 — консервативная, полная верификация в песочнице невозможна.
   Деградация при неверном допущении: если env НЕ следует за каталогом worktree, хуки резолвят
   ветку основного дерева → enforcement тихо становится no-op для worktree-сессий (класс риска
   C5). Митигация: дизайн корректен под worst-case; хендофф-инструкции явно сажают пользователя
   в каталог worktree; приёмочный критерий REQ-WT-1 (проверка `git worktree list` + запуск хука
   из worktree) верифицирует связку на реальном харнессе в Execution.
2. **[Средний] UX двойного хендоффа** (start → CLI сессии; archive-мёрж → основной CLI). Цена
   консервативного допущения. Митигация: если харнесс на деле проксирует cwd→env, хендоффы
   схлопываются — документируем как возможную будущую оптимизацию, не меняя контракт.
3. **[Средний] IDE/watcher-шум и двойная индексация** при worktree внутри репо. Митигация:
   рекомендация исключить `.sdx/` из индексации; escape-hatch `SDX_WORKTREE_ROOT` для выноса
   наружу без изменения кода (только резолв базового пути в `start.md`/`archive.md`).
4. **[Средний] Регресс тест-сьюта `test-archive-verify.sh`.** Все 6 сценариев завязаны на
   gitignore-допущение. Полная переработка фикстур (см. ниже) — обязательна, иначе ложные
   PASS/FAIL.
5. **[Низкий] Протухший `origin/HEAD`.** `default-branch.sh` может вернуть устаревшее имя.
   Митигация: фолбэк-эвристика + документированный `git remote set-head origin -a`.
6. **[Низкий] Рост истории основной ветки.** `--no-ff` тянет всю историю артефактов сессии в
   DAG. Это осознанная цена REQ-SESS-4 (история достижима). HEAD-дерево остаётся чистым.

---

## Тестирование (перезапись `test-archive-verify.sh`)

Хук делаем worktree-агностичным (полагается только на `$proj` + git) → базовые сценарии остаются
валидными на обычном репо, но фикстуры перестают гитигнорить каталог сессии.

- **[MODIFIED] `setup_clean_repo()`** — убрать `printf '.claude/sessions/\n' > .gitignore`.
  Вместо этого: коммитить `.gitignore` с targeted-паттернами (`.stopgate.*`, `.sdx/worktrees/`),
  а содержательные файлы сессии — трекать. Дерево «чистое», потому что всё закоммичено, а не
  потому что игнорируется.
- **[ADDED] `setup_worktree_repo()`** — фикстура с реальным `git worktree add`: создаёт worktree
  на `sdx/<id>`, трекает файлы сессии в нём, эмулирует вариант A (`git rm` + commit на ветке),
  мёржит `--no-ff` в основную ветку, затем прогоняет хук из основного репо.
- **[ADDED] Сценарий 7 — tracked-файлы + вариант A (happy path).** После мёржа: инвариант 6
  проходит (каталог не tracked в дереве основной ветки), `git worktree remove` освобождает
  worktree (проверить `git worktree list` без записи), ветка удалена, `[OK]`.
- **[ADDED] Сценарий 8 — пропущен `git rm` до мёржа.** Каталог сессии вмёржен tracked → инвариант
  6 `[FAIL]`, worktree НЕ удалён.
- **[ADDED] Сценарий 9 — `master`-репозиторий.** `git init -b master`, полный вариант-A цикл →
  инвариант 5 проходит относительно `master` БЕЗ `SDX_ARCHIVE_NO_BRANCH_OK` (REQ-BRANCH-2).
- **[ADDED] Юнит-тест `default-branch.sh`** (новый файл `test-default-branch.sh` или блок):
  кейсы — `origin/HEAD`=master; нет remote + `init.defaultBranch=trunk`; нет remote + только
  `main`; нет remote + только `master`; пустой репозиторий.
- Существующие сценарии 1–6 переписать под tracked-фикстуру (сохранив их смысл: dirty tree,
  unmerged, success, branch-absent, override, anchored-suffix).

---

## ADR (кандидаты — к внесению в `docs/DECISIONS.md` на Closeout)

### ADR-009. git worktree + версионируемые артефакты сессии

- **Контекст.** ADR-005 декларировал «артефакты коммитятся в ветку сессии инкрементально», но
  `.claude/sessions/` целиком в `.gitignore` — коммит физически невозможен (аудит 2026-07-01,
  C7). Параллельно `switch.md` делал слепой `git add -A && git commit` в общем дереве (C2).
  Обе находки решаются одной связкой.
- **Решение.** Одна сессия = один **git worktree** на ветке `sdx/<id>`, расположенный в
  gitignored `.sdx/worktrees/<id>/` внутри репозитория. Содержательные `.md`/`.json`-артефакты
  сессии (`.claude/sessions/<id>/…`) версионируются на этой ветке; эфемерные `.stopgate.*`
  игнорируются точечным паттерном корневого `.gitignore`. Удаление каталога сессии оформляется
  коммитом `git rm -r` НА ВЕТКЕ до мёржа (**вариант A**); мёрж `--no-ff` вносит историю в DAG
  основной ветки, но не в её HEAD-дерево. `archive-verify.sh` переходит с активного `rm -rf` на
  проверку отсутствия + `git worktree remove`. `switch.md` больше не трогает общее дерево:
  переключение = запуск CLI в каталоге нужного worktree (следствие консервативного допущения о
  `CLAUDE_PROJECT_DIR`, §8). Чистый **cutover** без миграции существующих не-worktree сессий.
- **Обоснование.** Делает ADR-005 буквально истинным (устраняет C7); полностью снимает C2 (нет
  общего дерева для порчи); физическая изоляция каталогами закрывает REQ-WT-3 без stash/локов.
  Вариант A предпочтён варианту B (пост-мёрж `rm`+commit прямо в основную ветку), т.к. сохраняет
  инвариант «основная ветка получает только merge-коммиты» и роль хука как gate, а не источника
  прямых коммитов в основную ветку. Расположение внутри репо (vs снаружи) выбрано за
  предсказуемость путей, унификацию с `.sdx/bundles/` и простоту хендофф-инструкций;
  самовложенность закрыта gitignore, watcher-шум — рекомендацией/escape-hatch `SDX_WORKTREE_ROOT`.
- **Инварианты.**
  - Содержательные артефакты сессии tracked на `sdx/<id>`; `.stopgate.*` — никогда (REQ-SESS-1/2).
  - После Closeout HEAD-дерево основной ветки не содержит `.claude/sessions/<id>/`; история
    достижима через merge-DAG до `git branch -d` и после него — через merge-коммит (REQ-SESS-3/4).
  - `switch.md` НЕ выполняет `git add -A`/`commit`/`checkout` в общем дереве (REQ-WT-2).
  - Деструктив (`worktree remove`, `branch -d`) — только после доказанных инвариантов 1/5/6.
  - Пересмотр расположения worktree или варианта удаления — новый ADR.
- **Связь.** Уточняет/операционализирует ADR-005 (не переписывает его); прецедент нового ADR при
  развороте — ADR-008.

### ADR-010. Автоопределение основной ветки вместо хардкода `main`

- **Контекст.** Хуки и команды хардкодят `main` (`archive-verify.sh` инвариант 5, `verify.md`
  diff, prose протокола). На репозиториях с `master`/иным именем инвариант «ветка слита» ложно
  падает/пропускается, diff считается относительно несуществующей ветки (запрос 2026-07-03).
- **Решение.** Единый шелл-хелпер `.claude/sdx/hooks/lib/default-branch.sh` резолвит имя
  основной ветки: `git symbolic-ref refs/remotes/origin/HEAD` → `git config init.defaultBranch`
  (если ветка существует) → эвристика существующих локальных `main`/`master` → last-resort `main`.
  Хелпер переиспользуется хуками (`archive-verify.sh`) и документированно — агентом в prose-
  командах (`verify.md`, `archive.md`, protocol.md). Хелпер безопасен при отсутствии remote и
  всегда печатает непустое имя.
- **Обоснование.** Один источник истины устраняет дрейф между точками хардкода; `origin/HEAD` —
  наиболее авторитетный сигнал «что команда считает основной веткой», с деградацией к локальным
  сигналам при отсутствии remote. Не требует per-project настройки (REQ-BRANCH-4).
- **Инварианты.**
  - Ни хук, ни команда не содержат литерала `main` как имени основной ветки (REQ-BRANCH-1);
    иллюстративные упоминания в доках допускаются с явной пометкой.
  - Резолв — только через `lib/default-branch.sh` (или его документированный one-liner); новые
    места, нуждающиеся в имени основной ветки, обязаны использовать хелпер.
  - Изменение порядка фолбэков — новый ADR.

---

## Трассируемость к REQ-ID

| REQ | Компоненты/решения |
|-----|--------------------|
| REQ-SESS-1 | `.gitignore` (снят широкий ignore); `start.md`/`next`/`checkpoint` коммитят артефакты на ветку; ADR-009 |
| REQ-SESS-2 | `.gitignore` паттерн `.claude/sessions/*/.stopgate.*`; ADR-009 |
| REQ-SESS-3 | Вариант A (`git rm -r` до мёржа) + `--no-ff`; `archive-verify.sh` инвариант 6; Sequence 2 |
| REQ-SESS-4 | `--no-ff` merge (история в DAG); `branch -d` после мёржа; ADR-009 |
| REQ-WT-1 | `start.md` `git worktree add`; тест-сценарий 7; критерий `git worktree list` |
| REQ-WT-2 | `switch.md` переписан ([REMOVED] `add -A`/commit/checkout); ADR-009 |
| REQ-WT-3 | Физическая изоляция worktree-каталогами (by construction) |
| REQ-WT-4 | Стандартный шаринг tracked-дерева git worktree (хуки/settings/agents на всех ветках) |
| REQ-WT-5 | `archive-verify.sh` `git worktree remove`; тест-сценарий 7 |
| REQ-BRANCH-1 | `lib/default-branch.sh`; правки `archive-verify.sh`, `verify.md`, protocol.md; ADR-010 |
| REQ-BRANCH-2 | `archive-verify.sh` инвариант 5 через `$def`; тест-сценарий 9 (`master`) |
| REQ-BRANCH-3 | `verify.md` diff через `$def`; ADR-010 |
| REQ-BRANCH-4 | `lib/default-branch.sh` безопасен без remote, без per-project настройки; `init.md` |

---

## Самозакрытие текущей сессии (гибридно, вне worktree)

Сессия `fw-session-worktree-20260703` создана в СТАРОЙ модели (её каталог сейчас gitignored, она
не в worktree). После реализации рефакторинга флип `.gitignore` делает её артефакты трекаемыми
«задним числом». Закрытие — гибридное, вручную:
- перенос дельт (`SPEC.md`/`DESIGN.md`) в `docs/specs/`, `docs/designs/` — как обычно (пункт 2
  Closeout);
- шаг `git worktree remove` неприменим (worktree нет) → отметить `(n/a)`;
- удаление `.claude/sessions/<id>/` выполнить обычным `git rm`/`rm` вручную (не через новую
  worktree-ветку логику);
- ADR-009 фиксирует cutover: это последняя сессия старой модели, последующие — только worktree.
