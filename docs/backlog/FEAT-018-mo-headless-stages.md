---
id: FEAT-018
type: feat
status: open
priority: normal
wave: null
source: intake intake-mo-dev-control-20261028 (записка владельца МО `SDX-MO-dev-control-note-2026-10-26.md` §2.1, §2.5, §5 п.5; ответ SDX `SDX-MO-dev-control-reply-2026-10-28.md` §1 Q1/Q3, §2.1; концепция `MO-dev-control-concept.md` 0.3 §4 профиль П3)
session: null
links: [FEAT-016, FEAT-017, PROC-019, PROC-020, FEAT-007, IDEA-002, ADR-014]
---

# FEAT-018. Headless-стадии (плагин 3.0): `sdx run execute|verify|audit`, `questions.yaml` вместо диалога, профиль ревьюера для аудита узла

## Суть
Профиль П3 концепции МО: узел сам запускает стадии SDX в своём рабочем дереве (`claude -p`) по мандату и заказу —
`sdx run <stage> --mandate <m.yaml> --order <o.yaml>`; код возврата `0` — стадия завершена, `1` — нужен человек (файл
вопросов), `2` — отказ по мандату (факт в `sdx.log`). Аудит пакета (`sdx run audit --change <CHANGE.yaml> --rubric
<review.yaml>`) исполняется узлом: механизм в 0.9.0 уже есть (`dev.py audit()`, `llm_review`), от SDX нужен **профиль
ревьюера** — fresh-eyes субагент без контекста сессии исполнителя, с рубрикой из `review.yaml` и вердиктом
`approve | return | reject` по файлам. Владелец МО ставит П3 последним (§5 п.5), после пилота на новом проекте.

Что уже есть в SDX (ответная записка Q1): команды — markdown-промпты, разворачиваемые харнесом; `gate_mode: auto` со
стоп-рубрикой и `auto_decisions.md`; `decisions_log.md` (`PROC-019`). Чего нет: неинтерактивного исхода «нужен человек»
(сегодня — `AskUserQuestion`, в headless он не отвечается), кода возврата процесса по исходу стадии и проверки
`claude -p "/sdx:next"` на бинарнике (не выполнялась). `prod-guard`/`stop-gate` в headless остаются гейтами актора у
исполнителя; аудит узла их дополняет, не заменяет (ADR-021).

## Рекомендация
После `FEAT-017` и пилота. Состав:
1. Проверка на бинарнике: `claude -p "/sdx:next"` в репозитории с активной сессией разворачивает команду плагина и
   исполняет субагентов; результат — в `docs/history/experiments/`. Без этой проверки остальное не планируется.
2. Обёртка `sdx run <stage>` (bash, в плагине; вызов `claude -p` с профилем стадии): `rc 2` при стадии вне
   `mandate.stages` (переиспользует гейт `FEAT-016` п.3), `rc 1` — когда стоп-рубрика требует человека: вопросы пишутся в
   `questions.yaml` (`id`, `what`, `options`, `default`, `tag` из восьми тегов журнала) вместо `AskUserQuestion`, ответы
   читаются из `answers.yaml` при повторном запуске; `rc 0` — стадия завершена, `[STAGE_CHANGE]` в логе.
3. Профиль ревьюера для `audit`: вход — манифест, `delivery.diff` пакета, рубрика; выход — `audit.yaml` в формате
   `dev.py` (`verdict`, `notes[]` по файлам); контракт изоляции тот же, что у `/sdx:verify` (только `Task`, без `Bash`).
4. `sdx run pr` = `/sdx:pr` headless.

Критерии приёмки: П3-прогон на фикстурном репозитории от `work.order` до `change/<C>-<exec>` без единого интерактивного
вопроса при полном мандате; при заказе с коллизией триады — `rc 1` и непустой `questions.yaml`.
