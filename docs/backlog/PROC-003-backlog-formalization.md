---
id: PROC-003
type: proc
status: in-progress
priority: high
wave: null
source: audit-2026-07-01 (E2)
session: fw-backlog-20260719
links: [ADR-015]
---

# PROC-003. Формализация бэклога: структура, префиксы, команды, волны

## Суть
Бэклог живёт неструктурированно (этот файл + roadmap в gitignored-бандле);
нет ID-префиксов по типам, трассировки в документации, команд просмотра, планирования волн.
Техдолг фиксируется нерегулярно.

## Рекомендация
Трекаемый `docs/backlog/` (файл на задачу, YAML frontmatter: id, type,
status, priority, wave, source-session, links) + индекс; префиксы по типам (FEAT-/BUG-/DEBT-/
IDEA-/PROC-); команды `/sdx:backlog` (список/фильтры/деталь/add); шаг Closeout «отложенное и
WARN-находки → DEBT-записи»; поле `wave` для планирования волн. Машиночитаемый frontmatter —
как интеграционная точка будущего плагина портфельного управления. Миграция находок A*–E*
этого файла в новый формат. ADR.
