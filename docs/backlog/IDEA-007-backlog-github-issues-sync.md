---
id: IDEA-007
type: idea
status: open
priority: low
wave: null
source: полевой репорт (сессия fw-stagegate-winpath-20260720, попутное пожелание)
session: null
links: [PROC-006, PROC-007]
---

# IDEA-007. Автоматический пуш записей бэклога в GitHub Issues

## Суть
Бэклог SDX (`docs/backlog/`, ADR-015) — файловый и локальный. Для публичности и трекшена
(PROC-006) и для находок из реальных сессий (PROC-007) полезна возможность автоматически
публиковать записи бэклога как GitHub Issues проекта — как минимум для мета-репозитория SDX.

## Рекомендация
Рассмотреть: синхронизация запись-бэклога ↔ issue через `gh` CLI (frontmatter уже
машиночитаем: `id`, `type`, `status`, `priority`, `links`); опция в `/sdx:backlog add`
(«запушить как issue?») и/или пункт Closeout. Открытые вопросы: направление синхронизации
(one-way push достаточно?), дедупликация по `id`, приватные проекты без remote.
