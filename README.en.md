# SDX — Spec-Driven X for Claude Code

[![Release](https://img.shields.io/github/v/release/oleksandr-voznyi/sdx-claude-plugin?label=version)](https://github.com/oleksandr-voznyi/sdx-claude-plugin/releases)

🇷🇺 [Русская версия (каноническая)](README.md)

SDX is a Spec-Driven Development (SDD) framework for Claude Code, packaged as a **plugin**: a session lifecycle (`/sdx:start` → … → `/sdx:archive`), role-based subagents, a unified stage scale with scalable ceremony, and a deterministic hook-based enforcement layer. One installed plugin serves every project on the machine — no need to replicate framework files across projects.

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
- `.claude/sdx/` — enforcement-layer configs: `prod-guard.conf` (block patterns for prod commands), `verify-cmd.sh` (test command for the stop-gate), `sdx-version` (marker of the plugin version the project was last reconciled against — written exclusively by `/sdx:reconcile`, checked by `/sdx:start`), `.cache/` (untracked cache of self-test results, gitignored);
- targeted `.gitignore` patterns and (optionally) an SDX block in the project's CLAUDE.md.

## What's inside the plugin

| Path | Contents |
|------|----------|
| `commands/` | 15 `/sdx:*` commands (start, next, status, switch, checkpoint, verify, manual, proto, archive, init, export, import, backlog, reconcile, audit) |
| `agents/` | 9 subagents: `ba`, `architect`, `lead-dev`, `developer`, `qa`, `reviewer`, `tech-writer`, `devops`, `auditor` |
| `hooks/hooks.json` | Enforcement-layer wiring (SessionStart / PreToolUse / Stop) |
| `sdx/protocol.md` | Session protocol: state, unified stage scale and flags, gates, Closeout, import/export |
| `sdx/hooks/` | Hook scripts (stop-gate, prod-guard, preflight) and their tests (`test-*.sh`); `sdx-stage.sh`/`archive-verify.sh` are CLI scripts invoked by commands, not `hooks.json` wiring |
| `sdx/templates/` | Templates for per-project configs and the CLAUDE.md SDX block |

Hooks are safe by default: outside an `sdx/<id>` branch and without per-project configs they are transparent (no-op), so a user-scope installation does not interfere with projects that don't use SDX.

## Unified stage scale and mode flags

The SDX lifecycle scales with task size through one canonical order of **nine stages**, not a choice among separate profiles: `Discovery → Business Spec → Technical Design → Task Planning → Execution → Documentation → Verification → Deployment → Closeout`. A stage's activity for a given session is determined by two orthogonal mechanisms — delta size (which artifact to produce: a full one or one folded into `change_note.md`) and two independent boolean state flags, `no_code` and `no_gates`, which can only narrow the active set.

| Flag | Purpose | Session types | Active set |
|------|---------|---------------|-----------|
| — (both `false`) | Regular work: bugfix, feature, refactor — from a point fix to a large task touching contracts/architecture | `bug`, `feature`, `refactor`, `init`, `import` | Full canonical order; for a small delta, planning stages fold into `change_note.md` (minimum — `Execution → Verification → Closeout`) |
| `no_code = true` | Process work without code: backlog grooming, retrospective, incident review, intake of new requirements, audit-report triage | `grooming`, `retro`, `postmortem`, `intake`, `audit` (rigidly bound, no dialog) | `Discovery → Business Spec/Technical Design (change_note.md) → Verification → Closeout` — `Task Planning`/`Execution`/`Documentation`/`Deployment` are unconditionally excluded |
| `no_gates = true` | Extreme prototyping: a fast, code-first hypothesis check without TDD/`PLAN.md`/commits until an explicit decision | `proto` (rigidly bound, no dialog) | `Execution` only (no `Closeout`) |

> The "Session types" column reads the same way for all three rows: the `type → flags` binding is rigid and unconditional for the five `no_code`-family types and for `proto` (no choice dialog); for `bug`/`feature`/`refactor`/`init`/`import` both flags start `false`, and delta size is a prosaic judgement, reassessed on every `/sdx:next`.

### `no_code` and its session types

The `no_code` flag handles work on the backlog and SDX process itself. All five session types follow the same active set of planning stages; the difference lies in the nature of input and output:

- **`grooming`** — review of existing backlog entries: update status, priority, wave. This is a **redistribution** of attributes across existing entries.
- **`retro`** — review of completed sessions over a period: identify patterns and conclusions, expressed as new backlog entries.
- **`postmortem`** — review of an incident (production, process failure, critical defect): timeline, root cause, action plan.
- **`intake`** — processing a significant new block of external requirements (epic, batch of bug reports, product material): breakdown into backlog entries. This is **creation** of new entries from external material.
- **`audit`** — triage of an already-produced `/sdx:audit` report. The `/sdx:audit` command itself is a read-only "as-is" project audit run outside sessions: a parallel fan-out across nine vectors (architecture, triad integrity, requirement traceability, code quality, tests, documentation, deployment, security, process) builds a cumulative report in `docs/history/audit/`; each vector gets one of three outcomes — findings, clean, or **not applicable** (the vector structurally has no subject) — and the report itself gates nothing. The `audit` session type takes that already-existing report as input and **verifies** its findings against the backlog: it enriches open entries, spawns new entries for previously unrecorded findings, and files a separate regression entry when a finding matches an already-closed entry. It produces no permanent analysis document — the second `no_code`-family type without one, alongside `grooming` (the subject of the review is already a permanent document — the report itself).

**The distinction between `intake`, `grooming`, and `audit`:** `intake` **generates** new entries from external material (create), `grooming` then **redistributes** priority and wave across what has accumulated without creating new entries (update), `audit` **verifies** the accumulated backlog against a fresh as-is project report — enriching existing entries, spawning new ones for previously unrecorded findings, and separately flagging a regression when a finding matches an already-closed entry (verify). All three work with the same `docs/backlog/`, but in different operational directions.

Each `no_code` session must produce at least one observable backlog change and pass a lightweight verification. For `retro`, `postmortem`, and `intake`, a permanent analysis document is additionally created in `docs/history/`; `grooming` and `audit` produce no such document.

### `no_gates` and mandatory legalization

`no_gates` is an extreme-prototyping mode (ADR-018): its only session type is `proto`, and the `proto → no_gates = true` binding is rigid and unconditional (no choice dialog) — much like all five `no_code`-family types are rigidly bound to their flag.

While `no_gates == true`, code is written in one continuous pass: no `PLAN.md`, no `change_note.md`, and — the single named exception to the incremental-commit norm (ADR-005) — no intermediate code commits. Once done, the `/sdx:proto` gate unconditionally asks the user to decide: **reject** the prototype (a targeted rollback to the baseline snapshot) or **accept** it and legalize the session (reverse-engineer `SPEC.md`/`DESIGN.md` from the already-written code, clear the flag). A session with `no_gates == true` has no `Closeout` of its own: it cannot be closed or merged into the main branch without legalization (REQ-VIBE-8) — `/sdx:archive` stops on such a session and points to `/sdx:proto`.

## Rules and documentation

- Process, the unified stage scale, gates, and the session closeout contract: `sdx/protocol.md`.
- Framework architecture decisions (ADR): `docs/DECISIONS.md`.
- Development history: `docs/history/`.

Requirement: `jq` on PATH (used by the hooks; checked by the preflight hook on session start).
