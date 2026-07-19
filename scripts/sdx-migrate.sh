#!/usr/bin/env bash
# SDX plugin bootstrap & migration script.
#
# Machine setup (always):
#   1. Ensure jq (hook-layer dependency) is installed.
#   2. Register the sdx marketplace from GitHub (if not registered).
#   3. Install the sdx plugin at user scope (if not installed) -> /sdx:* in every project.
#   4. Enable session-start auto-update: extraKnownMarketplaces (+ autoUpdate) and
#      enabledPlugins {"sdx@sdx": true} in ~/.claude/settings.json.
#
# Project migration (with --project, or auto-detected legacy files in CWD):
#   5. Remove vendored legacy framework files (.claude/commands/sdx, SDX agents,
#      .claude/sdx/{protocol.md,hooks,verify-cmd.sh.template}) — per-project data
#      (.claude/sessions/, .claude/sdx/*.conf|*.allow|verify-cmd.sh, docs/) is kept.
#   6. Strip legacy hook wiring (.claude/sdx/hooks/*) from project .claude/settings.json.
#   7. Declare the plugin dependency in project .claude/settings.json
#      (extraKnownMarketplaces + enabledPlugins) so other machines get an install prompt.
#
# Usage:
#   sdx-migrate.sh              # machine setup; project part only if legacy detected in CWD
#   sdx-migrate.sh --project    # machine setup + force project part for CWD
#   SDX_REPO_URL=https://github.com/me/fork.git sdx-migrate.sh   # override source repo
#
# Idempotent: safe to re-run. Nothing is committed to git automatically.
set -uo pipefail

REPO_SLUG="${SDX_REPO_SLUG:-oleksandr-voznyi/sdx-claude-plugin}"
REPO_URL="${SDX_REPO_URL:-https://github.com/${REPO_SLUG}.git}"
MP_NAME="sdx"
PLUGIN_ID="sdx@sdx"
USER_SETTINGS="$HOME/.claude/settings.json"
FORCE_PROJECT=0
[ "${1:-}" = "--project" ] && FORCE_PROJECT=1

ok()   { printf '  [OK] %s\n' "$1"; }
warn() { printf '  [WARN] %s\n' "$1" >&2; }
die()  { printf '  [FAIL] %s\n' "$1" >&2; exit 1; }

command -v claude >/dev/null 2>&1 || die "Claude Code CLI ('claude') не найден в PATH."

# --- 1. jq (needed by SDX hooks AND by this script for settings merges) -------------
echo "== Зависимости =="
if command -v jq >/dev/null 2>&1; then
  ok "jq уже установлен"
else
  SUDO=""; [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && SUDO="sudo"
  if   command -v apt-get >/dev/null 2>&1; then $SUDO apt-get install -y -qq jq
  elif command -v dnf     >/dev/null 2>&1; then $SUDO dnf install -y -q jq
  elif command -v yum     >/dev/null 2>&1; then $SUDO yum install -y -q jq
  elif command -v apk     >/dev/null 2>&1; then $SUDO apk add --quiet jq
  elif command -v brew    >/dev/null 2>&1; then brew install -q jq
  fi
  command -v jq >/dev/null 2>&1 && ok "jq установлен" \
    || die "не удалось установить jq автоматически — установите вручную и повторите."
fi

# --- 2. Marketplace registration ----------------------------------------------------
echo "== Marketplace =="
if claude plugin marketplace list 2>/dev/null | grep -Eq "(^|[[:space:]])❯?[[:space:]]*${MP_NAME}([[:space:]]|$|@)" \
   || jq -e --arg m "$MP_NAME" 'has($m)' "$HOME/.claude/plugins/known_marketplaces.json" >/dev/null 2>&1; then
  ok "marketplace '${MP_NAME}' уже зарегистрирован"
else
  claude plugin marketplace add "$REPO_URL" \
    || die "не удалось добавить marketplace из $REPO_URL (проверьте сетевой доступ к GitHub)."
  ok "marketplace '${MP_NAME}' добавлен из $REPO_URL"
fi

# --- 3. Plugin install (user scope -> all projects on this machine) -----------------
echo "== Плагин =="
if jq -e --arg p "$PLUGIN_ID" '.plugins | has($p)' "$HOME/.claude/plugins/installed_plugins.json" >/dev/null 2>&1; then
  ok "плагин ${PLUGIN_ID} уже установлен"
else
  claude plugin install "$PLUGIN_ID" --scope user || die "установка ${PLUGIN_ID} не удалась."
  ok "плагин ${PLUGIN_ID} установлен (scope user)"
fi

# --- 4. User settings: declarative enable + auto-update on session start ------------
echo "== Пользовательские настройки (${USER_SETTINGS}) =="
# Reuse the exact source object Claude Code stored on 'marketplace add' (schema-safe).
MP_SOURCE="$(jq -c --arg m "$MP_NAME" '.[$m].source // empty' "$HOME/.claude/plugins/known_marketplaces.json" 2>/dev/null)"
[ -z "$MP_SOURCE" ] && MP_SOURCE="$(jq -cn --arg u "$REPO_URL" '{source:"url", url:$u}')"
mkdir -p "$(dirname "$USER_SETTINGS")"
[ -f "$USER_SETTINGS" ] || echo '{}' > "$USER_SETTINGS"
cp "$USER_SETTINGS" "${USER_SETTINGS}.bak.$(date +%Y%m%d%H%M%S)"
tmp="$(mktemp)"
jq --arg m "$MP_NAME" --arg p "$PLUGIN_ID" --argjson src "$MP_SOURCE" '
  .extraKnownMarketplaces[$m] = {source: $src, autoUpdate: true}
  | .enabledPlugins[$p] = true
' "$USER_SETTINGS" > "$tmp" && mv "$tmp" "$USER_SETTINGS" \
  || die "не удалось обновить ${USER_SETTINGS}"
ok "extraKnownMarketplaces.${MP_NAME} (autoUpdate: true) + enabledPlugins.${PLUGIN_ID}"

# Pull the freshest plugin right now (session-start auto-update covers the future).
claude plugin marketplace update "$MP_NAME" >/dev/null 2>&1 \
  && ok "marketplace обновлён до актуального состояния" \
  || warn "marketplace update не прошёл — проверьте сетевой доступ к GitHub."

# --- 5-7. Project migration ---------------------------------------------------------
LEGACY=0
{ [ -d .claude/commands/sdx ] || [ -f .claude/sdx/protocol.md ] || [ -d .claude/sdx/hooks ]; } && LEGACY=1
if [ "$FORCE_PROJECT" -eq 1 ] || [ "$LEGACY" -eq 1 ]; then
  echo "== Миграция проекта: $(pwd) =="
  IN_GIT=0; git rev-parse --is-inside-work-tree >/dev/null 2>&1 && IN_GIT=1
  # remove: tracked files via git rm (staged for review), untracked via rm.
  remove() {
    [ -e "$1" ] || return 0
    if [ "$IN_GIT" -eq 1 ] && git ls-files --error-unmatch "$1" >/dev/null 2>&1; then
      git rm -rq "$1"
    else
      rm -rf "$1"
    fi
    ok "удалено: $1"
  }
  remove .claude/commands/sdx
  for a in ba architect lead-dev developer qa reviewer tech-writer devops; do
    remove ".claude/agents/${a}.md"
  done
  remove .claude/sdx/protocol.md
  remove .claude/sdx/hooks
  remove .claude/sdx/verify-cmd.sh.template
  rmdir .claude/commands .claude/agents 2>/dev/null || true

  PROJ_SETTINGS=".claude/settings.json"
  mkdir -p .claude
  [ -f "$PROJ_SETTINGS" ] || echo '{}' > "$PROJ_SETTINGS"
  cp "$PROJ_SETTINGS" "${PROJ_SETTINGS}.bak.$(date +%Y%m%d%H%M%S)"
  tmp="$(mktemp)"
  # 6. drop legacy hook wiring pointing into .claude/sdx/hooks; 7. declare plugin dep.
  jq --arg m "$MP_NAME" --arg p "$PLUGIN_ID" --argjson src "$MP_SOURCE" '
    if .hooks then
      .hooks |= with_entries(
        .value |= map(.hooks |= map(select((.command // "") | contains(".claude/sdx/hooks/") | not))
                      | select(.hooks | length > 0))
      ) | .hooks |= with_entries(select(.value | length > 0))
        | (if .hooks == {} then del(.hooks) else . end)
    else . end
    | .extraKnownMarketplaces[$m] = {source: $src}
    | .enabledPlugins[$p] = true
  ' "$PROJ_SETTINGS" > "$tmp" && mv "$tmp" "$PROJ_SETTINGS" \
    || die "не удалось обновить ${PROJ_SETTINGS}"
  ok "settings.json: legacy hook-проводка снята; marketplace + enabledPlugins объявлены"

  if [ "$IN_GIT" -eq 1 ]; then
    echo
    echo "  Изменения НЕ закоммичены (осознанно). Проверьте и закоммитьте:"
    echo "    git add .claude/settings.json && git commit -m 'chore(sdx): migrate to sdx plugin'"
  fi
  echo "  Затем в проекте выполните /sdx:init — он сверит структуру и .gitignore."
else
  echo "== Миграция проекта: legacy-файлы в $(pwd) не обнаружены — пропущено (форс: --project) =="
fi

echo
echo "Готово. Перезапустите Claude Code CLI, чтобы плагин (команды /sdx:* и хуки) подхватился."
