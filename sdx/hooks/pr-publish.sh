#!/usr/bin/env bash
# sdx/hooks/pr-publish.sh — publishes a built change package (FEAT-017, /sdx:pr, REQ-PKG-10, 13..16, 18, 35).
#
#   bash pr-publish.sh --sid <sid> [--proj DIR] [--commitment C] [--title T] [--base-name B]
#                      [--remote <name|URL>] [--hosting auto|github|bare] [--dry-run]
#   stdout: one JSON object {branch, remote, remote_sha, pushed, already, ready, hosting, pr:{url,created}|null,
#           degraded: gh-missing|gh-unauthenticated|gh-failed|null, instruction: string|null}
#   stderr: progress.  rc: 0 published (a degraded PR step included) | 1 refusal | 2 usage / environment
#
# The user's confirmation of the push is the job of the /sdx:pr command BEFORE this call (in any gate_mode); the script
# does not replace it, but protects itself: only refs/heads/change/*, ONLY an explicit refspec "B:B" (no "+", no
# --force / --force-with-lease / --all / --mirror / --tags / --follow-tags; the user's git configuration is neutralised),
# a whitelist of URL schemes (GIT_ALLOW_PROTOCOL as well), prod-guard on the synthesised `git push`, fast-forward only
# (overwriting a remote change/* is not implemented in 2.5.0). Every output goes through pr_url_show: no credentials.
# Before any network access the package is re-checked by pr-check.sh --phase post --no-tests (FAIL -> rc 1, no push).
# --dry-run validates everything and prints the result WITHOUT any network access (no ls-remote, no push, no gh).
# bash 3.2, no arrays; no interpreters other than bash/awk/sed/jq/git (+ the optional gh CLI). Anchors "# PKG-P-*" are
# mutation-run labels.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -f "$here/lib/pr-lib.sh" ]; then echo "pr-publish: lib/pr-lib.sh плагина не найдена." >&2; exit 2; fi
. "$here/lib/pr-lib.sh"

die() { echo "pr-publish: $2" >&2; exit "$1"; }
usage() { echo "pr-publish: использование: pr-publish.sh --sid <sid> [--proj DIR] [--commitment C] [--title T] [--base-name B] [--remote <имя|URL>] [--hosting auto|github|bare] [--dry-run]" >&2; exit 2; }
# scrub: credentials of URLs ("://user:pass@" -> "://") in anything that is about to be shown
scrub() { sed 's#\(://\)[^/@[:space:]]*@#\1#g'; }

sid=""; proj="${CLAUDE_PROJECT_DIR:-.}"; a_c=""; a_t=""; a_b=""; remote_arg=""; hosting_arg=auto; dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --sid|--proj|--commitment|--title|--base-name|--remote|--hosting)
      [ $# -ge 2 ] || usage
      case "$1" in --sid) sid="$2" ;; --proj) proj="$2" ;; --commitment) a_c="$2" ;; --title) a_t="$2" ;; --base-name) a_b="$2" ;; --remote) remote_arg="$2" ;; *) hosting_arg="$2" ;; esac
      shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) usage ;;
  esac
done
[ -n "$sid" ] || usage
case "$hosting_arg" in auto|github|bare) ;; *) usage ;; esac
command -v git >/dev/null 2>&1 || die 2 "git не найден"
command -v jq >/dev/null 2>&1 || die 2 "jq не найден"
git -C "$proj" rev-parse --git-dir >/dev/null 2>&1 || die 2 "$proj не git-репозиторий"
proj="$(cd "$proj" && pwd)"

set --
[ -z "$a_c" ] || set -- "$@" --commitment "$a_c"
[ -z "$a_t" ] || set -- "$@" --title "$a_t"
[ -z "$a_b" ] || set -- "$@" --base-name "$a_b"
pr_resolve "$proj" "$sid" "$@" || die 1 "$PR_ERR"

tip="$(git -C "$proj" rev-parse --verify -q "refs/heads/$PR_BRANCH^{commit}" 2>/dev/null)" || die 1 "пакет не собран: нет ветки $PR_BRANCH (сначала pr-build)"
case "$PR_BRANCH" in change/*) ;; *) die 1 "публикуется только change/*, а не '$PR_BRANCH'" ;; esac
spec="refs/heads/$PR_BRANCH:refs/heads/$PR_BRANCH"   # PKG-P-REFSPEC: explicit, no "+", no glob, one ref

# ---- where to: a configured remote (by name) or a URL that passed the whitelist ----
remote="${remote_arg:-${PR_URL:-origin}}"
if git -C "$proj" remote | grep -qxF -- "$remote"; then
  rurl="$(git -C "$proj" remote get-url --push "$remote" 2>/dev/null)"
else
  pr_url_ok "$remote" || { pr_url_show "$remote"; pr_clean "$PR_URLS" 80; die 1 "недопустимый remote/URL: '$PR_CLEAN' (допустимы имя настроенного remote, ssh/https/http/file URL, scp-вид, абсолютный путь)"; }   # PKG-P-URLWL
  rurl="$remote"
fi
pr_url_show "$rurl"; rurl_show="$PR_URLS"
case "$remote" in *://*|*@*:*|/*) remote_show="$rurl_show" ;; *) remote_show="$remote" ;; esac

# ---- prod-guard on the synthesised command (the PreToolUse hook does not see what a script runs itself) ----
pg="$(jq -n --arg c "git push $remote $spec" '{tool_name: "Bash", tool_input: {command: $c}}' | CLAUDE_PROJECT_DIR="$proj" bash "$here/prod-guard.sh" 2>/dev/null)"
case "$pg" in *'"permissionDecision":"deny"'*) die 1 "prod-guard: push заблокирован паттерном проекта (.claude/sdx/prod-guard.conf)" ;; esac   # PKG-P-PRODGUARD

# ---- hosting ----
if [ "$hosting_arg" = auto ]; then pr_hosting "$rurl" "$PR_HOSTING_HINT"; hosting="$PR_HOSTING"; else hosting="$hosting_arg"; fi

# ---- the PR body (from the manifest of the tip) is built BEFORE any network access: a secret refuses the push ----
errf=""; bodyf=""
trap 'rm -f "$errf" "$bodyf"' EXIT
if [ "$PR_DELIVERY" = pr ]; then
  man="$(mktemp "${TMPDIR:-/tmp}/sdx-pr-man.XXXXXX")" || die 2 "не удалось создать временный файл"
  if git -C "$proj" show "$tip:CHANGE.yaml" > "$man" 2>/dev/null && my_load "$man"; then
    _my_scalar change.commitment; pr_clean "$MY_S" 80; b_c="$PR_CLEAN"
    _my_scalar change.executor; pr_clean "$MY_S" 80; b_e="$PR_CLEAN"
    _my_list change.scope_touched; b_n="$(printf '%s\n' "$MY_L" | grep -c .)"
    _my_scalar change.verify.tests; pr_clean "$MY_S" 40; b_v="$PR_CLEAN"
    _my_list change.adr; pr_clean "$(printf '%s' "$MY_L" | tr '\n' ',' | sed 's/,/, /g')" 300; b_a="${PR_CLEAN%, }"
    _my_scalar change.touches_shared; b_s="$MY_S"
    _my_scalar change.history_ref; pr_clean "$MY_S" 120; b_h="$PR_CLEAN"
    _my_scalar change.notes; pr_clean "$MY_S" 300; b_o="$PR_CLEAN"
    if [ "$b_s" = true ]; then b_sl="touches_shared: true — слияние такого пакета — решение человека"; else b_sl="touches_shared: false"; fi
    body="Обязательство: $b_c
Исполнитель: $b_e
Изменено файлов: $b_n
Проверка исполнителя (verify.tests): ${b_v:-—}
ADR: ${b_a:-—}
$b_sl
История: ${b_h:-—}
Примечания исполнителя: ${b_o:-—}

Пакет собран SDX (/sdx:pr): один squash-коммит кода и отдельный последний коммит CHANGE.yaml."
  else
    body="Обязательство: $PR_C
Исполнитель: $PR_EXEC

(манифест CHANGE.yaml в вершине ветки не прочитан)"
  fi
  rm -f "$man"
  if pr_has_secret "$body"; then die 1 "тело PR похоже на секрет (поле манифеста) — отправка отменена"; fi
  bodyf="$(mktemp "${TMPDIR:-/tmp}/sdx-pr-body.XXXXXX")" || die 2 "не удалось создать временный файл"
  printf '%s\n' "$body" > "$bodyf"
fi

# ---- the package is re-checked BEFORE any push (verify-1 W3): "pr-check blocks the push" is enforced here, not only by the order of the steps
# of /sdx:pr. Phase post, without the project tests (they ran in phase pre). FAIL (rc 1) or an environment error (rc 2) refuse the push;
# WARN (rc 3) was confirmed by the user at P7 of the command, so it does not block. There is no way to skip this check.
pcx="$(bash "$here/pr-check.sh" --sid "$sid" --proj "$proj" --phase post --no-tests "$@" 2>&1)"; pcrc=$?   # PKG-P-POSTCHECK
case "$pcrc" in
  0|3) ;;
  *) pcf="$(printf '%s\n' "$pcx" | grep -E '^(FAIL|PR-CHECK)' | head -n 6 | scrub | tr '\n' ' ')"
     die 1 "pr-check --phase post отверг пакет (rc $pcrc), push не выполнен: $pcf" ;;
esac

rsha=""; pushed=false; already=false
if [ "$dry" = 0 ]; then
  export GIT_ALLOW_PROTOCOL=file:ssh:https:http GIT_TERMINAL_PROMPT=0
  : "${GIT_SSH_COMMAND:=ssh -o BatchMode=yes}"; export GIT_SSH_COMMAND
  errf="$(mktemp "${TMPDIR:-/tmp}/sdx-pr-pub.XXXXXX")" || die 2 "не удалось создать временный файл"
  lsout="$(git -C "$proj" ls-remote --heads -- "$remote" "refs/heads/$PR_BRANCH" 2>"$errf")" \
    || die 1 "не удалось прочитать remote $remote_show: $(head -n 3 "$errf" | scrub | tr '\n' ' ')"
  rsha="$(printf '%s\n' "$lsout" | awk 'NR == 1 { print $1 }')"
  if [ -n "$rsha" ] && [ "$rsha" != "$tip" ]; then
    git -C "$proj" merge-base --is-ancestor "$rsha" "$tip" 2>/dev/null \
      || die 1 "на удалённой стороне $PR_BRANCH не предок вершины пакета (non-fast-forward); перезапись в 2.5.0 не поддерживается"   # PKG-P-FF
  fi
  if [ "$rsha" = "$tip" ]; then
    already=true; pushed=true
    echo "pr-publish: $PR_BRANCH уже на $remote_show (${tip:0:12}) — push не нужен" >&2
  else
    pout="$(git -C "$proj" -c push.followTags=false -c push.default=nothing push --porcelain --no-follow-tags -- "$remote" "$spec" 2>&1)"; prc=$?   # PKG-P-NOFOLLOW
    if [ "$prc" -ne 0 ]; then die 1 "push в $remote_show не удался: $(printf '%s\n' "$pout" | scrub | head -n 4 | tr '\n' ' ')"; fi
    lsout="$(git -C "$proj" ls-remote --heads -- "$remote" "refs/heads/$PR_BRANCH" 2>/dev/null)"
    rsha="$(printf '%s\n' "$lsout" | awk 'NR == 1 { print $1 }')"
    [ "$rsha" = "$tip" ] || die 1 "после push ветка $PR_BRANCH на удалённой стороне (${rsha:-нет}) не равна вершине пакета ($tip)"
    pushed=true
    echo "pr-publish: отправлено $PR_BRANCH → $remote_show (${tip:0:12})" >&2
  fi
fi

# ---- the pull request (delivery: pr): gh when it is there; any trouble with it is a degradation, never a refusal ----
pr_url=""; pr_created=false; degraded=""; instruction=""
instr="Откройте PR вручную: $PR_BRANCH → $PR_BASE_NAME в $rurl_show."
degrade() { degraded="$1"; instruction="$instr"; }   # PKG-P-GH
gh_step() {
  local t owner repo slug="" lst purl out line
  case "$rurl_show" in
    *github.com[:/]*)
      t="${rurl_show#*github.com}"; t="${t#[:/]}"; t="${t%/}"; t="${t%.git}"
      case "$t" in */*)
        owner="${t%%/*}"; repo="${t#*/}"
        case "$owner" in ""|*[!A-Za-z0-9._-]*) ;; *) case "$repo" in ""|*[!A-Za-z0-9._-]*) ;; *) slug="$owner/$repo" ;; esac ;; esac ;;
      esac ;;
  esac
  command -v gh >/dev/null 2>&1 || { degrade gh-missing; return 0; }
  GH_PROMPT_DISABLED=1 gh auth status >/dev/null 2>&1 || { degrade gh-unauthenticated; return 0; }
  [ -n "$slug" ] || { degrade gh-failed; return 0; }
  lst="$(GH_PROMPT_DISABLED=1 gh pr list --head "$PR_BRANCH" --repo "$slug" --json url 2>/dev/null)" || { degrade gh-failed; return 0; }
  purl="$(printf '%s' "$lst" | jq -r '.[0].url // empty' 2>/dev/null)"
  if [ -n "$purl" ]; then pr_url="$purl"; pr_created=false; return 0; fi
  out="$(GH_PROMPT_DISABLED=1 gh pr create --repo "$slug" --base "$PR_BASE_NAME" --head "$PR_BRANCH" --title "$PR_C: $PR_TITLE" --body-file "$bodyf" 2>/dev/null)" || { degrade gh-failed; return 0; }
  line="$(printf '%s\n' "$out" | grep -E '^https?://' | tail -n 1)"
  if [ -n "$line" ]; then pr_url="$line"; pr_created=true; else degrade gh-failed; fi
  return 0
}
if [ "$PR_DELIVERY" = pr ] && [ "$dry" = 0 ]; then
  # github only: a bare host has no pull requests, the package is ready as the branch + CHANGE.yaml (REQ-PKG-15); "open the PR manually"
  # is shown solely for a degraded github step. With delivery: branch no PR is created at all.
  if [ "$hosting" = github ]; then gh_step; fi   # PKG-P-BAREINSTR
fi
# ready: the branch with CHANGE.yaml is on the remote and, for a github host with delivery: pr, the pull request exists
ready=false
if [ "$pushed" = true ]; then
  if [ "$PR_DELIVERY" = pr ] && [ "$hosting" = github ] && [ -z "$pr_url" ]; then ready=false; else ready=true; fi
fi
if [ -n "$pr_url" ]; then pr_clean "$pr_url" 300; pr_url="$PR_CLEAN"; fi

# ---- result ----
jq -n -c --arg branch "$PR_BRANCH" --arg remote "$remote_show" --arg rsha "$rsha" --argjson pushed "$pushed" --argjson already "$already" --argjson ready "$ready" \
  --arg hosting "$hosting" --arg purl "$pr_url" --argjson created "$pr_created" --arg degraded "$degraded" --arg instruction "$instruction" '
  {branch: $branch, remote: $remote, remote_sha: (if $rsha == "" then null else $rsha end), pushed: $pushed, already: $already, ready: $ready,
   hosting: $hosting, pr: (if $purl == "" then null else {url: $purl, created: $created} end),
   degraded: (if $degraded == "" then null else $degraded end), instruction: (if $instruction == "" then null else $instruction end)}'
exit 0
