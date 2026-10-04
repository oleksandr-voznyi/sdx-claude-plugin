# Записка SDX → sim-kit: три находки при вендоринге 0.7.3 в плагин (FEAT-015)

Для: `agentico/reviews/` · От: репозиторий SDX · Основание: сессия `feat-015-mo-interop-20261004`, вендоринг
sim-kit 0.7.3 (`core/mesh_endpoint.py`, `core/devagent_hook.py`, `core/MO-INTEROP.md`) по политике PROC-028.
Статус: `proposed`. Отправляется на Closeout сессии после явного подтверждения.

## 1. Вызовы без `PYTHONDONTWRITEBYTECODE=1` в вендорённых текстах
`MO-INTEROP.md` §5 (`python3 $MO_TOOLS/mesh_endpoint.py …`) и docstring `devagent_hook.py:17–18` («добавить в
`.claude/settings.json`: `python3 "$CLAUDE_PROJECT_DIR/tools/devagent_hook.py"`») вызывают инструменты без
`PYTHONDONTWRITEBYTECODE=1`. В плагинной модели `devagent_hook.py` импортирует `mesh_endpoint` из того же
каталога, и python пишет `sdx/mo/__pycache__/` в **корень плагина** — нарушение инварианта ADR-013 SDX («контент
плагина не пишет в свой корень в рантайме»); сторож `test-mo-inventory.sh` считает подкаталог находкой.
Прогнано: с переменной каталога нет, без неё — есть (`context_report.md` §3 сессии).
Плагин защищён обёрткой (`sdx/hooks/mo-hook.sh`, `mo-session.sh`); незащищённым остаётся вызов «по docstring» в
обход обёртки. Просьба: добавить `PYTHONDONTWRITEBYTECODE=1` в примеры §5 и docstring (одна строка в каждом).

## 2. Регистр `on_write`: `raw_mode` приводит к нижнему, основной путь сравнивает с учётом регистра
`devagent_hook.py:38` (`raw_mode`, используется в `cannot_check`) берёт `.lower()`; `devagent_hook.py:181`
сравнивает `c.get("on_write") == "deny"` без приведения. Следствие: `on_write: DENY` блокирует при
`cannot_check` (нет PyYAML и т.п.), но **не блокирует** штатную проверку цели — запись в `exec_paths` без аренды
даёт `notice` и rc 0. Воспроизведение (фикстура `.mesh/endpoint.yaml` с `on_write: DENY`, `exec_paths` на
каталог `dep`, inbox пуст):
```bash
printf '{"tool_name":"Write","tool_input":{"file_path":"%s/dep/x"},"cwd":"%s"}' "$fx" "$fx" \
  | PYTHONDONTWRITEBYTECODE=1 MESH_ENDPOINT_DIR="$fx" CLAUDE_PROJECT_DIR="$fx" python3 sdx/mo/devagent_hook.py; echo "rc=$?"
# ожидание по docstring: rc=2 (deny); факт: rc=0, конверт notice в .mesh/outbox/
```
Обёртка SDX читает режим как `raw_mode` (нижний регистр), т.е. трактует `DENY` как `deny` — расхождение с хуком
на этой фикстуре зафиксировано в сьюте как INFO. Просьба: один `.lower()` на строке 181 (или сравнение с
`raw_mode`).

## 3. Норма `Deployment` под МО — формального согласования нет
Плагин фиксирует (`sdx/protocol.md`, ADR-021): этап `Deployment` под МО завершается отправкой `artifact.offer`
(+ `request`), `msg_id` — в артефактах сессии; `rollout.result` — вход следующей сессии. Разбор
`SDX-MO-interop-review-2026-10-04.md` §2 п.1 с этим согласился и записал в `MO-INTEROP.md` §1, но §3 того же
разбора числит «подтвердить SDX» открытым. Этой запиской SDX подтверждает формулировку; просьба закрыть пункт.
