# SDX — Spec-Driven X for Claude Code

[![Release](https://img.shields.io/github/v/release/oleksandr-voznyi/sdx-claude-plugin?label=version)](https://github.com/oleksandr-voznyi/sdx-claude-plugin/releases)

🇷🇺 [Русская версия (каноническая)](README.md)

SDX is a Spec-Driven Development (SDD) framework for Claude Code, packaged as a **plugin**: a session lifecycle (`/sdx:start` → … → `/sdx:archive`), role-based subagents, adaptive ceremony tracks, and a deterministic hook-based enforcement layer. One installed plugin serves every project on the machine — no need to replicate framework files across projects.

> Note: the plugin's working language is Russian (chat, specs, session artifacts) — see the language policy in `CLAUDE.md` §1. Code, comments, and API docs are in English. Multilingual support is on the roadmap (backlog: FEAT-002).

## Installation

The repository is both a marketplace and a plugin; the canonical source is GitHub: `https://github.com/oleksandr-voznyi/sdx-claude-plugin.git` (public — https access, no keys required).

**Recommended — the bootstrap script** (idempotent; installs `jq`, registers the marketplace, installs the plugin at user scope for all projects on the machine, enables auto-update on session start):

```bash
git clone --depth 1 https://github.com/oleksandr-voznyi/sdx-claude-plugin.git /tmp/sdx-plugin \
  && /tmp/sdx-plugin/scripts/sdx-migrate.sh \
  && rm -rf /tmp/sdx-plugin
```

The same by hand:

```bash
claude plugin marketplace add https://github.com/oleksandr-voznyi/sdx-claude-plugin.git
claude plugin install sdx@sdx --scope user
# auto-update on session start: extraKnownMarketplaces.sdx.autoUpdate=true in ~/.claude/settings.json
```

Updates are pulled automatically on session start (`autoUpdate: true`); force with `/plugin marketplace update sdx`. Consumers pick up a plugin update when `version` in `plugin.json` is bumped — bump it on every meaningful release. Each bump is accompanied by a `vX.Y.Z` tag on the bump commit and a GitHub release (`gh release create vX.Y.Z --title … --notes …`) — version history lives on the [releases page](https://github.com/oleksandr-voznyi/sdx-claude-plugin/releases).

## Migrating a project from the legacy (vendored) SDX

In the root of a project carrying an old framework copy, run `scripts/sdx-migrate.sh` (add `--project` if legacy files are not auto-detected): the script removes legacy framework files (`.claude/commands/sdx/`, SDX agents in `.claude/agents/`, `.claude/sdx/{protocol.md,hooks/}`), strips the old hook wiring from the project's `.claude/settings.json`, and declares the plugin dependency there (`extraKnownMarketplaces` + `enabledPlugins: {"sdx@sdx": true}`), leaving the per-project layer intact (`.claude/sessions/`, `.claude/sdx/` configs, `docs/`). Changes are left uncommitted — review, commit, then run `/sdx:init` to verify the structure.

## Onboarding a project

Run `/sdx:init` in the target project (`/sdx:init --existing` for an existing codebase). The command deploys the **per-project layer** — the only thing that lives in the project itself:

- `docs/specs/`, `docs/designs/`, `docs/history/plans/`, `docs/backlog/` — permanent triad documents and the tracked backlog;
- `.claude/sessions/<id>/` — active session artifacts (versioned on the `sdx/<id>` branch);
- `.claude/sdx/` — enforcement-layer configs: `prod-guard.conf` (block patterns for prod commands), `stage-gate.allow` (extra write allowlist before the Execution gate), `verify-cmd.sh` (test command for the stop-gate);
- targeted `.gitignore` patterns and (optionally) an SDX block in the project's CLAUDE.md.

## What's inside the plugin

| Path | Contents |
|------|----------|
| `commands/` | 14 `/sdx:*` commands (start, next, status, switch, retrack, backtrack, checkpoint, verify, manual, archive, init, export, import, backlog) |
| `agents/` | 8 subagents: `ba`, `architect`, `lead-dev`, `developer`, `qa`, `reviewer`, `tech-writer`, `devops` |
| `hooks/hooks.json` | Enforcement-layer wiring (SessionStart / PreToolUse / Stop) |
| `sdx/protocol.md` | Session protocol: state, tracks, gates, Closeout, import/export |
| `sdx/hooks/` | Hook scripts (stage-gate, stop-gate, prod-guard, preflight, archive-verify) and their tests (`test-*.sh`) |
| `sdx/templates/` | Templates for per-project configs and the CLAUDE.md SDX block |

Hooks are safe by default: outside an `sdx/<id>` branch and without per-project configs they are transparent (no-op), so a user-scope installation does not interfere with projects that don't use SDX.

## Adaptive tracks (flow profiles)

The SDX lifecycle scales with task size: each session follows one of **four adaptive tracks**, defining active stages and gates.

| Track | Purpose | Session types | Stages |
|-------|---------|---------------|--------|
| **patch** | Bugfix or small fix without logic changes | `bug` | Execution → Verification → Closeout |
| **standard** | Small feature or refactor | `feature`, `refactor` | Discovery → Change → Execution → Verification → Closeout |
| **full** | Large feature affecting contracts or architecture | `feature`, `refactor`, `init`, `import` | Discovery → Business Spec → Technical Design → Task Planning → Execution → Documentation → Verification → Deployment → Closeout |
| **doc** | Process work without code: backlog grooming, retrospective, incident review, intake of new requirements | `grooming`, `retro`, `postmortem`, `intake` | Discovery → Update → Verification → Closeout |

### The `doc` track and its session types

The `doc` track handles work on the backlog and SDX process itself. All four session types follow the same stages; the difference lies in the nature of input and output:

- **`grooming`** — review of existing backlog entries: update status, priority, wave. This is a **redistribution** of attributes across existing entries.
- **`retro`** — review of completed sessions over a period: identify patterns and conclusions, expressed as new backlog entries.
- **`postmortem`** — review of an incident (production, process failure, critical defect): timeline, root cause, action plan.
- **`intake`** — processing a significant new block of external requirements (epic, batch of bug reports, product material): breakdown into backlog entries. This is **creation** of new entries from external material.

**Key distinction between `intake` and `grooming`:** `intake` sits higher in the workflow and focuses on **generating** new entries from external material, while `grooming` then **redistributes** priority and wave across what has accumulated. Both types work with the same `docs/backlog/`, but in opposite operational directions.

Each doc session must produce at least one observable backlog change and pass a lightweight verification. For `retro`, `postmortem`, and `intake`, a permanent analysis document is additionally created in `docs/history/`.

## Rules and documentation

- Process, tracks, gates, and the session closeout contract: `sdx/protocol.md`.
- Framework architecture decisions (ADR): `docs/DECISIONS.md`.
- Development history: `docs/history/`.

Requirement: `jq` on PATH (used by the hooks; checked by the preflight hook on session start).
