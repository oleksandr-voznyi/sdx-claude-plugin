# Протокол SDX-сессий

Этот документ описывает формат состояния и логирования сессий. Им руководствуется основная сессия Claude Code при выполнении команд `/sdx:*` (роль Session Manager). Оркестрация субагентов (architect, ba, lead-dev, developer, qa, tech-writer, devops) выполняется только из основной сессии через инструмент Task — субагенты не могут вызывать друг друга.

## Состояние сессии (session_state.json)
```json
{
  "session_id": "string",
  "type": "feature | bug | refactor | init",
  "stage": "Discovery | Business Spec | Technical Design | Task Planning | Execution | Documentation | Verification | Deployment | Archiving",
  "status": "draft | review | approved | executing",
  "git_branch": "sdx/...",
  "artifacts": [],
  "history": []
}
```

## Логирование
Ключевые изменения состояния ОБЯЗАТЕЛЬНО фиксируются в файле `.claude/sessions/<session_id>/session.log`.

### Формат строки:
`[YYYY-MM-DD HH:mm:ss] [КАТЕГОРИЯ] [ЭТАП] Сообщение`

### Правила и категории:
- **Формат времени**: `YYYY-MM-DD HH:mm:ss`. Не выдумывай время — получай его командой `date '+%Y-%m-%d %H:%M:%S'`.
- **Категории**:
    - `START`: Инициализация сессии или переключение на неё.
    - `STAGE_CHANGE`: Переход между этапами жизненного цикла.
    - `ARTIFACT`: Создание, обновление или удаление значимых файлов (артефактов).
    - `CHECKPOINT`: Создание точки восстановления или фиксация состояния.
    - `INFO`: Важные информационные сообщения (например, запрос статуса).
    - `ERROR`: Ошибки выполнения команд или проверок.
- **ЭТАП**: Текущее значение `stage` из `session_state.json`.
- **Сообщение**: Краткое описание произошедшего на русском языке.

### Техническая реализация:
Запись производится в режиме **append** (дозапись в конец файла) через инструмент Bash с перенаправлением `>>`:
```bash
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ARTIFACT] [Execution] Обновлен PLAN.md" >> .claude/sessions/<session_id>/session.log
```

## Гейты (Gates)
Перед переходом на следующий этап проверяется наличие необходимых артефактов (`SPEC.md`, `DESIGN.md`, `PLAN.md` и т.д.) — см. `/sdx:next`.

## Checkpoint и сброс контекста
Команда `/sdx:checkpoint` записывает суммаризацию состояния в `.claude/sessions/<id>/checkpoint.md`. После этого пользователь может выполнить `/clear`; восстановление контекста происходит чтением файлов сессии (`/sdx:status`, `checkpoint.md`). Менять системный промпт или очищать контекст программно невозможно.
