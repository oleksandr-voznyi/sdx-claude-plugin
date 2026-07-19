#!/usr/bin/env bash
# SDX default-branch resolver (REQ-BRANCH-1/2/3/4).
# Prints the repository's default/main branch name. Single source of truth,
# reused by hooks and (documented) by prose commands.
# Usage: default-branch.sh [proj_dir]   (proj_dir defaults to CWD)
# Safe with no remote configured.
set -uo pipefail
proj="${1:-${CLAUDE_PROJECT_DIR:-.}}"

# 1) Authoritative signal when a remote exists: origin/HEAD symbolic ref.
ref="$(git -C "$proj" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null || true)"
if [ -n "$ref" ]; then
  echo "${ref#refs/remotes/origin/}"; exit 0
fi

# 2) Configured init.defaultBranch (covers fresh repos with no remote).
cfg="$(git -C "$proj" config --get init.defaultBranch 2>/dev/null || true)"
if [ -n "$cfg" ] && git -C "$proj" show-ref --verify --quiet "refs/heads/$cfg"; then
  echo "$cfg"; exit 0
fi

# 3) Heuristic: prefer an existing local main, then master.
if   git -C "$proj" show-ref --verify --quiet refs/heads/main;   then echo main
elif git -C "$proj" show-ref --verify --quiet refs/heads/master; then echo master
elif [ -n "$cfg" ]; then echo "$cfg"          # configured name even if branch absent yet
else echo main                                # last-resort default
fi
