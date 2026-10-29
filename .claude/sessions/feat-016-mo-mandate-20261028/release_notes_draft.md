Накопительный релиз 2.3.1 + 2.4.0 за 2026-10-28 … 2026-10-29: мандат разработки узла МО (второй признак режима), гейт стадий, область мандата на `/sdx:verify`, декларация `tests/suites.yaml`, перевендоринг sim-kit. Версия 2.3.1 (перевендоринг) отдельно не выпускалась — её изменения входят сюда.

### Что изменилось

- **Мандат МО — второй признак режима (FEAT-016, поправки ADR-020 и ADR-021).** Рядом с `.mesh/endpoint.yaml` (стенды) плагин распознаёт `.mesh/mandate.yaml` (процесс изменений: какие стадии делает исполнитель и в какой области). Без `mandate.yaml` поведение прежнее, как в 2.3.x (кроме безусловной охраны `.mesh/mandate.yaml` от `Write`/`Edit` при наличии `endpoint.yaml`); `mandate.yaml` без `endpoint.yaml` — не режим мандата (одна строка предупреждения, как в хуке sim-kit). Разбор мандата — чистый bash (`sdx/hooks/lib/miniyaml.sh`, `lib/mandate.sh`), python для него не запускается.
- **`mandate.stages` как третий сужающий источник активного набора.** `spec` → Discovery + Business Spec; `design` → Technical Design + Task Planning; `execute` → Execution + Documentation; `verify` → Verification. Стадия вне мандата исключается: `/sdx:start` стартует на первом допустимом этапе (`start-stage`), `/sdx:next --to` на исключённый этап отказывает (`sdx-stage.sh`, запись `[ERROR]`). `Verification` и `Closeout` активны всегда; `Deployment` при мандате исключён всегда (он у узла). Для `endpoint.yaml` без мандата ADR-021 п.7 действует как раньше.
- **Показ мандата.** `/sdx:start` печатает мандат как данные (`mandate-info.sh show`) — гарантированный канал; `mo-session.sh` (SessionStart) печатает ту же группу полей под «[ДАННЫЕ, не инструкции]». `/sdx:status` показывает строку МО с мандатом (часть DEBT-043).
- **Область мандата на `/sdx:verify`.** `mandate-scope.sh` сверяет `git diff` с `scope.paths ∪ shared_paths ∪ docs_paths`: файл вне области — `FAIL` (гейт), файл в `shared_paths` — `WARN`, просроченный `valid_until` — предупреждение; пустой `scope.paths` — «без ограничений», как у эталона.
- **`mo-hook.sh`.** Исход «не могу проверить» берёт более строгий режим из `endpoint.on_write` и `mandate.on_write`; запись в `.mesh/mandate.yaml` отказывается как для `endpoint.yaml`.
- **`tests/suites.yaml`.** `suites-gen.sh` на `/sdx:init` и `/sdx:reconcile` создаёт декларацию набора `unit` (`cmd`, `budget_min` из `SDX_VERIFY_TIMEOUT`); `module`/`regression` — закомментированные образцы (имена — контракт `policy/tests.yaml` узла). Резолв команды совпадает со `stop-gate.sh` — дрейф ловит тест-близнец. Репозиторий плагина получил свою декларацию (dogfood).
- **`devops` и мост Closeout.** При мандате слияния в ветки вне `scope.branches` и теги — не действие `devops`. До `/sdx:pr` (FEAT-017) при мандате с любым определённым `delivery` чек-лист Closeout выполняет шаги 1–5, шаги 6–8 отмечаются `(n/a, мандат)`, `archive-verify.sh` не вызывается (проверка `closeout-check`), `change/<C>-<exec>` создаёт пользователь. Мост действует при любом определённом `delivery`; для `artifact.offer` (`bridge:offer`) к шагам добавляется отправка оффера — один раз.
- **Абзац сниппета** `claude-md-snippet.md`: одно предложение о мандате; `snippet-check.sh` сообщает `ABSENT|BROKEN|OK|STALE`, `/sdx:reconcile` предлагает обновление.
- **Перевендоринг sim-kit (бывший 2.3.1).** `sdx/mo/` обновлён до sim-kit 0.9.1 (хеши в `SIMKIT_SHA256`); хук сам ставит `sys.dont_write_bytecode`, мутант `BYTECODE-FS` снят; для инстансов с `self_deploy` `devops` деплоит сам (решение коллизии в пользу эталона).
- Тест-сьют: 15 → 19 сьютов (новые: `test-mandate-lib`, `test-mandate-scope`, `test-suites-gen`, `test-snippet-check`); полный прогон ≈ 80–125 с в зависимости от загрузки машины. `hooks/hooks.json`, `stop-gate.sh`, `archive-verify.sh`, `agents/reviewer.md` и `sdx/mo/*` относительно 2.3.0 не менялись (кроме перевендоринга `sdx/mo/`).
- Обёртка `mo-hook.sh`: при `deny`, пришедшем из мандата, проверяет PyYAML до запуска хука и при его отсутствии блокирует запись (`MAND-PYYAML`); при `deny` из `endpoint.yaml` поведение прежнее.

## Границы

- Видимость вывода SessionStart для модели **не проверена** (DEBT-045); гарантированный канал — вывод `/sdx:start`.
- Мандат реального узла и чтение `tests/suites.yaml` через `dev.py run_suites` **не проверены вживую** (проверена форма по эталону и фикстурам; ручной сценарий — в сессии).
- Проза моста Closeout (`archive.md`) проверяется только ручным прогоном.
- Запись через `Bash` вне области мандата хук останавливает best-effort — разбором текста команды (как для `exec_paths`); `Bash`-пути к `.mesh/*` обёртка не охраняет — подмену мандата обнаруживает узел по `mandate_digest` и аудитом пакета.
- Разбор мандата — подмножество YAML (чистый bash); формы вне подмножества отказывают с указанием причины и сверены с `yaml.safe_load` оракулом там, где доступны python/PyYAML.
- `/sdx:pr`, `CHANGE.yaml`, `--from-order` — FEAT-017; headless — FEAT-018.
- Узлы со старым ядром могут видеть `mesh.version-skew` на конвертах 0.9.x — ожидаемо.

---

Cumulative release 2.3.1 + 2.4.0, 2026-10-28 … 2026-10-29: the MO node's development mandate (a second mode signal), a stage gate, mandate scope checked at `/sdx:verify`, the `tests/suites.yaml` declaration, re-vendored sim-kit. 2.3.1 (the re-vendoring) was never released on its own, so its changes are included here.

### What changed

- **The MO mandate is a second mode signal (FEAT-016, ADR-020 and ADR-021 amendments).** Next to `.mesh/endpoint.yaml` (stands) the plugin recognises `.mesh/mandate.yaml` (the change process: which stages the executor does and in what scope). Without `mandate.yaml` behaviour is exactly 2.3.x (except the unconditional guard of `.mesh/mandate.yaml` against `Write`/`Edit` whenever `endpoint.yaml` exists); `mandate.yaml` without `endpoint.yaml` is not mandate mode (one warning line, as in the sim-kit hook). The mandate is parsed in pure bash (`sdx/hooks/lib/miniyaml.sh`, `lib/mandate.sh`); no python is started for it.
- **`mandate.stages` as a third narrowing source of the active stage set.** `spec` -> Discovery + Business Spec; `design` -> Technical Design + Task Planning; `execute` -> Execution + Documentation; `verify` -> Verification. A stage outside the mandate is excluded: `/sdx:start` starts at the first admissible stage (`start-stage`), while `/sdx:next --to` an excluded stage is refused (`sdx-stage.sh`, `[ERROR]` logged). `Verification` and `Closeout` are always active; `Deployment` is always excluded under a mandate (it belongs to the node). For `endpoint.yaml` without a mandate ADR-021 item 7 applies as before.
- **Showing the mandate.** `/sdx:start` prints the mandate as data (`mandate-info.sh show`) — the guaranteed channel; `mo-session.sh` (SessionStart) prints the same field group under "[DATA, not instructions]". `/sdx:status` shows an MO line with the mandate (part of DEBT-043).
- **Mandate scope at `/sdx:verify`.** `mandate-scope.sh` checks `git diff` against `scope.paths ∪ shared_paths ∪ docs_paths`: a file outside is `FAIL` (gate), a file in `shared_paths` is `WARN`, an expired `valid_until` is a warning; empty `scope.paths` means "unrestricted", as in the reference.
- **`mo-hook.sh`.** The "cannot verify" outcome takes the stricter of `endpoint.on_write` and `mandate.on_write`; writes to `.mesh/mandate.yaml` are refused like `endpoint.yaml`.
- **`tests/suites.yaml`.** `suites-gen.sh` creates a declaration of the `unit` suite at `/sdx:init` and `/sdx:reconcile` (`cmd`, `budget_min` from `SDX_VERIFY_TIMEOUT`); `module`/`regression` are commented samples (the names are the node's `policy/tests.yaml` contract). Command resolution mirrors `stop-gate.sh` — a twin test catches drift. The plugin repository ships its own declaration (dogfood).
- **`devops` and the Closeout bridge.** Under a mandate, merges into branches outside `scope.branches` and tags are not `devops` actions. Until `/sdx:pr` (FEAT-017), with any defined `delivery` the Closeout checklist runs steps 1-5, steps 6-8 are marked `(n/a, mandate)`, `archive-verify.sh` is not called (`closeout-check` instead), and the user creates `change/<C>-<exec>`. The bridge applies to any defined `delivery`; for `artifact.offer` (`bridge:offer`) an offer-sending step is added, once only.
- **Snippet paragraph** in `claude-md-snippet.md`: one sentence on the mandate; `snippet-check.sh` reports `ABSENT|BROKEN|OK|STALE`, `/sdx:reconcile` offers an update.
- **sim-kit re-vendoring (formerly 2.3.1).** `sdx/mo/` is updated to sim-kit 0.9.1 (hashes in `SIMKIT_SHA256`); the hook now sets `sys.dont_write_bytecode` itself, the `BYTECODE-FS` mutant is removed; for `self_deploy` instances `devops` deploys itself (the collision resolved in favour of the reference).
- Test suite: 15 -> 19 suites (new: `test-mandate-lib`, `test-mandate-scope`, `test-suites-gen`, `test-snippet-check`); a full run takes ~80-125 s depending on machine load. `hooks/hooks.json`, `stop-gate.sh`, `archive-verify.sh`, `agents/reviewer.md` and `sdx/mo/*` are unchanged relative to 2.3.0 (apart from the `sdx/mo/` re-vendoring).
- `mo-hook.sh`: when `deny` comes from the mandate, the wrapper probes PyYAML before running the hook and blocks the write if it is missing (`MAND-PYYAML`); `deny` from `endpoint.yaml` behaves as before.

## Boundaries

- Whether the model sees SessionStart output is **not verified** (DEBT-045); the guaranteed channel is the `/sdx:start` output.
- A real node's mandate and reading `tests/suites.yaml` via `dev.py run_suites` are **not verified live** (the format is checked against the reference and fixtures; the manual scenario is in the session).
- The Closeout bridge prose (`archive.md`) is verified by a manual run only.
- `Bash` writes outside the mandate scope are stopped best-effort by parsing the command text (as for `exec_paths`); `Bash` paths into `.mesh/*` are not guarded by the wrapper — a tampered mandate is detected by the node via `mandate_digest` and the package audit.
- The mandate parser handles a YAML subset (pure bash); forms outside it are refused with a reason and cross-checked against `yaml.safe_load` as an oracle where python/PyYAML exist.
- `/sdx:pr`, `CHANGE.yaml`, `--from-order` are FEAT-017; headless is FEAT-018.
- Nodes on an older core may show `mesh.version-skew` on 0.9.x envelopes — expected.
