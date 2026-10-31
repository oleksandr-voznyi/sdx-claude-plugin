#!/usr/bin/env bash
# sdx/hooks/pr-build.sh — builds the change package of a closed session (FEAT-017, /sdx:pr, REQ-PKG-5..10, 12, 18).
#
#   bash pr-build.sh --sid <sid> [--proj DIR] [--commitment C] [--title T] [--base-name B]
#                    [--allow-diverged] [--resubmit] [--notes TEXT]
#   stdout: one JSON object; stderr: human-readable lines
#   rc: 0 built | 1 refusal ("pr-build: <field>: <reason>") | 2 environment / usage | 3 confirmation needed
#       (stderr "NEED allow-diverged" | "NEED resubmit")
#
# The package is TWO commits made by git plumbing, leaving the working tree and the real
# index untouched: "head" = the code of the session squashed into one commit (parent: the base branch, or the previous tip
# on a re-submission), "tip" = head + the root file CHANGE.yaml (a separate last commit). The only ref written is
# refs/heads/change/<C>-<executor>, by update-ref with an explicit old value (compare-and-swap).
# Everything read from the order, the mandate and the session history is DATA (pr-lib: validated or cleaned).
# bash 3.2, no arrays; no interpreters other than bash/awk/sed/jq/git. Anchors "# PKG-*" are mutation-run labels.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -f "$here/lib/pr-lib.sh" ]; then echo "pr-build: lib/pr-lib.sh плагина не найдена." >&2; exit 2; fi
. "$here/lib/pr-lib.sh"

die() { echo "pr-build: $2" >&2; exit "$1"; }
usage() { echo "pr-build: использование: pr-build.sh --sid <sid> [--proj DIR] [--commitment C] [--title T] [--base-name B] [--allow-diverged] [--resubmit] [--notes TEXT]" >&2; exit 2; }

sid=""; proj="${CLAUDE_PROJECT_DIR:-.}"; a_c=""; a_t=""; a_b=""; allow_diverged=0; resubmit=0; notes_arg=""
while [ $# -gt 0 ]; do
  case "$1" in
    --sid|--proj|--commitment|--title|--base-name|--notes)
      [ $# -ge 2 ] || usage
      case "$1" in --sid) sid="$2" ;; --proj) proj="$2" ;; --commitment) a_c="$2" ;; --title) a_t="$2" ;; --base-name) a_b="$2" ;; *) notes_arg="$2" ;; esac
      shift 2 ;;
    --allow-diverged) allow_diverged=1; shift ;;
    --resubmit) resubmit=1; shift ;;
    *) usage ;;
  esac
done
[ -n "$sid" ] || usage
command -v git >/dev/null 2>&1 || die 2 "git не найден"
command -v jq >/dev/null 2>&1 || die 2 "jq не найден"
git -C "$proj" rev-parse --git-dir >/dev/null 2>&1 || die 2 "$proj не git-репозиторий"
proj="$(cd "$proj" && pwd)"
git -C "$proj" var GIT_COMMITTER_IDENT >/dev/null 2>&1 || die 2 "не заданы user.name/user.email (git config user.name / user.email) — коммит пакета невозможен"

# ---- who, what, from where: one place of decision (pr_resolve); the mandate is loaded by it ----
set --
[ -z "$a_c" ] || set -- "$@" --commitment "$a_c"
[ -z "$a_t" ] || set -- "$@" --title "$a_t"
[ -z "$a_b" ] || set -- "$@" --base-name "$a_b"
pr_resolve "$proj" "$sid" "$@" || die 1 "$PR_ERR"

src="refs/heads/sdx/$sid"
srcsha="$(git -C "$proj" rev-parse --verify -q "$src^{commit}")" || die 1 "нет ветки sdx/$sid"
[ "$(git -C "$proj" symbolic-ref -q HEAD)" = "$src" ] || die 1 "текущая ветка не sdx/$sid (пакет собирается из ветки закрытой сессии)"

# ---- 1) the tree of the squash ----
diverged=false
if git -C "$proj" merge-base --is-ancestor "$PR_BASE_SHA" "$srcsha"; then   # PKG-ANCESTOR
  tree="$(git -C "$proj" rev-parse "$srcsha^{tree}")"
else
  [ "$allow_diverged" = 1 ] || { echo "NEED allow-diverged: sdx/$sid вырезана не от $PR_BASE_NAME (локальная $PR_BASE_NAME ушла вперёд)" >&2; exit 3; }
  mt="$(git -C "$proj" merge-tree --write-tree "$PR_BASE_SHA" "$srcsha" 2>/dev/null)" \
    || die 1 "merge-tree: конфликт слияния или git < 2.38 (слейте $PR_BASE_NAME в sdx/$sid вручную)"
  tree="$(printf '%s\n' "$mt" | head -n1)"
  git -C "$proj" cat-file -e "$tree^{tree}" 2>/dev/null || die 1 "merge-tree не вернул дерево (git < 2.38?); слейте $PR_BASE_NAME в sdx/$sid вручную"
  diverged=true
fi
if [ -n "$(git -C "$proj" ls-tree -r --name-only "$tree" -- ".claude/sessions/$sid/" 2>/dev/null)" ]; then
  die 1 "каталог сессии .claude/sessions/$sid/ ещё в дереве sdx/$sid (шаг 5 Closeout не выполнен)"
fi

# ---- 2) the parent: the base, or (re-submission) the previous tip ----
zero=0000000000000000000000000000000000000000
old="$(git -C "$proj" rev-parse --verify -q "refs/heads/$PR_BRANCH^{commit}" 2>/dev/null || true)"
if [ -n "$old" ]; then
  git -C "$proj" cat-file -e "$old:CHANGE.yaml" 2>/dev/null || die 1 "ветка $PR_BRANCH уже есть, но это не пакет SDX (нет CHANGE.yaml в корне)"
  [ "$resubmit" = 1 ] || { echo "NEED resubmit: ветка $PR_BRANCH уже есть (повторная сдача поверх прежней вершины)" >&2; exit 3; }
  parent="$old"; zero="$old"
else
  parent="$PR_BASE_SHA"; zero=0000000000000000000000000000000000000000   # PKG-CAS
fi
git -C "$proj" cat-file -e "$tree:CHANGE.yaml" 2>/dev/null && die 1 "в коде уже есть корневой CHANGE.yaml (код пакета манифеста не содержит)"   # PKG-NOCHANGEYAML
head="$(printf '%s: %s\n' "$PR_C" "$PR_TITLE" | git -C "$proj" commit-tree "$tree" -p "$parent")" || die 2 "git commit-tree не удался (нет user.name/user.email?)"

# ---- refusals that need the diff of the package: control characters, secrets, an empty change ----
mbase="$(git -C "$proj" merge-base "$head" "$PR_BASE_SHA")" || die 1 "нет общего предка пакета и $PR_BASE_NAME"
pr_files "$proj" "$mbase" "$head" || die 1 "$PR_ERR"
[ -n "$PR_FILES" ] || die 1 "дельта base..head пуста (nonempty): нечего сдавать"   # PKG-EMPTY
while IFS= read -r f; do
  if pr_has_secret "$f"; then die 1 "files: путь похож на секрет"; fi
done <<< "$PR_FILES"

# ---- TASK-T40 partial output (replaced in the next steps) ----
jq -n --arg head "$head" '{head:$head}'
exit 0
