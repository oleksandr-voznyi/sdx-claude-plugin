#!/usr/bin/env bash
# SDX session resolver — shared by hooks that gate on `.stage`.
# Source, don't execute: `. "$here/lib/resolve-session.sh"`.
# resolve_sid <proj>  -> echoes sid on stdout if on branch sdx/<id>, else empty.
# No side effects on source: only a function definition, no top-level code.
resolve_sid() {
  local proj="$1" branch
  branch="$(git -C "$proj" branch --show-current 2>/dev/null || true)"
  case "$branch" in
    sdx/*) printf '%s' "${branch#sdx/}" ;;
    *)     printf '' ;;
  esac
}
