# Change Note — fw-roadmap-20260720 (DEBT-008: промоут roadmap Фаз 2–4)

## Что и зачем
Единственная полная спецификация отложенных требований Фаз 2–4 (REQ-LANE-1, REQ-LOOP-1,
REQ-CACHE-1, REQ-LEAN-1, REQ-CHECKPOINT-1, escalate-тир) жила в gitignored-бандле
`.sdx/bundles/upgrade_2026-06-27/sdx-efficiency-automation-2026.bundle.md` — один
`rm`/clone уничтожал roadmap (находка C1 аудита → DEBT-008, priority high, wave 2).

Промоут в трекаемые артефакты (перенос, не пересказ):
1. **`docs/specs/phases-2-4-deferred.md`** (новый) — полные формулировки отложенных
   требований + их дизайн-срезы из бандла (§2.6–2.11), анти-требования
   (REQ-NOOP-PLANMODE / REQ-NOOP-TEAMS), критерии приёмки; раздел «Примечания
   актуализации» помечает устаревшие места бандла (model ID → алиасы ADR-008, пути
   хуков → плагин ADR-013, снапшот биллинга/TTL).
2. **Записи бэклога `IDEA-002…IDEA-006`** — трекинг каждого отложенного требования
   (fanout, loop, checkpoint, lean-audit, escalate-тир); `IDEA-001` (REQ-CACHE-1,
   существовала) перелинкована на спеку. Индекс `README.md` обновлён.
3. `docs/specs/phase1-enforcement-routing.md` — раздел «Отложено» теперь ссылается на
   новую спеку (одна строка).

Бандл в `.sdx/bundles/` остаётся локальным артефактом (gitignored) — риск потери снят
промоутом, удалять его не требуется.

## Затронутые файлы
- `docs/specs/phases-2-4-deferred.md` (новый)
- `docs/backlog/IDEA-002…IDEA-006` (новые), `IDEA-001` (перелинковка), `README.md` (индекс)
- `docs/specs/phase1-enforcement-routing.md` (ссылка в «Отложено»)

## Коммиты
- 18d56ed — основная поставка (спека + IDEA-записи + перелинковка)
- (этот) — верификация: статусы IDEA → deferred, verification_report
