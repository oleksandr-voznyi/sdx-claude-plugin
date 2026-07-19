# Change Note — fw-migrate-20260719 (patch)

## Что и зачем
Дистрибуция переведена с локального пути на GitHub (`git@github.com:oleksandr-voznyi/sdx-claude-plugin.git`, private): папка разработки переименована в `sdx-claude-plugin`, репо создано и запушено. Добавлен идемпотентный bootstrap/миграционный скрипт `scripts/sdx-migrate.sh` для раскатки на серверы:
1) jq; 2) marketplace из GitHub (если нет); 3) установка `sdx@sdx` user-scope (если нет); 4) `extraKnownMarketplaces.sdx` (autoUpdate: true — автообновление при старте сессии) + `enabledPlugins."sdx@sdx"` в `~/.claude/settings.json` (merge через jq, с бэкапом); 5–7) миграция проекта в CWD (`--project` или автодетект legacy): удаление vendored-файлов фреймворка (git rm для tracked), снятие legacy hook-проводки из project settings.json, объявление зависимости в project settings.json; per-project слой не трогается; авто-коммита нет (норма REQ-WT-2).

## Затронутые файлы
- `scripts/sdx-migrate.sh` (новый, +x)
- `README.md`: раздел «Установка» переписан под GitHub + скрипт; новый раздел «Миграция проекта»; правило бампа `version`.

## Проверка
- `bash -n` OK; фикстурный legacy-проект: удаление/сохранение файлов и трансформация settings.json проверены прогоном (см. verification в сессии).
