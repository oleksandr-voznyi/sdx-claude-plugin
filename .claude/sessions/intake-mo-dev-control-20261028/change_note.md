# Change note: intake-mo-dev-control-20261028

Сессия типа `intake`; стартовала с `no_code = true`, флаг снят на `Verification` решением пользователя (`decisions_log.md`,
`[объём]`): помимо дельты `docs/backlog/` — точечная правка двух тест-сьютов.

## Что сделано
- Новые записи: `FEAT-016` (2.4.0 — мандат и декларации, перевендоринг sim-kit 0.9.0), `FEAT-017` (2.5.0 — сдача пакетом,
  `/sdx:pr`), `FEAT-018` (3.0 — headless). Приоритеты стартовые: high / high / normal; `wave: null`.
- Дополнения «Уточнения разбора» без смены атрибутов: `FEAT-006` (2), `DEBT-043`.
- Индекс `docs/backlog/README.md`: три строки в «Открытые», абзац происхождения.

## Зачем
Записка владельца МО 26.10 переводит границу SDX↔МО с места (стенды) на стадии (мандат). Ответная записка SDX
`<aibok>/agentico/reviews/SDX-MO-dev-control-reply-2026-10-28.md` принимает принцип и раскладывает требования по трём
выпускам; этот intake переносит раскладку в трекаемый бэклог, чтобы следующая feature-сессия стартовала от `FEAT-016`.

## Попутная правка кода (эскалация объёма)
Stop-gate оказался красным: процесс `claude` экспортирует `PYTHONDONTWRITEBYTECODE=1`, переменная наследуется мутантами
`BYTECODE-ENV`/`BYTECODE-FS` (`test-mo-hook.sh`) и `no-bytecode-env` (`test-mo-session.sh`), и проверки «обёртка сама
ставит переменную» проходят вхолостую. Правка: `unset PYTHONDONTWRITEBYTECODE` сразу после `set -uo pipefail` в обоих
сьютах (герметичность к окружению вызывающего). Логика обёрток не менялась; 108 + 26 проверок зелёные с переменной в
окружении и без неё.

## Затронутые файлы
`sdx/hooks/test-mo-hook.sh`, `sdx/hooks/test-mo-session.sh` (по четыре строки);
`docs/backlog/FEAT-016-mo-mandate-and-declarations.md`, `FEAT-017-mo-change-package-delivery.md`,
`FEAT-018-mo-headless-stages.md`, `FEAT-006-authority-model-risk-classes.md`, `DEBT-043-selftest-perimeter-excludes-mo-hooks.md`,
`README.md`; сессионный `intake.md`.

## Границы
Ответная записка написана вне репозитория и не коммитится здесь. Находки по sim-kit (ответ §4) в бэклог плагина не
попадают. `--work-dir`, 0.8.3, GitLab/Gitea, замена гейтов актора — сознательно не взяты (см. `intake.md`).
