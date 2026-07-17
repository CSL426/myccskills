---
name: ai-config-sync
description: Use when the user wants to run, sync, share, or version-control AI CLI configuration across machines or across tools (Claude Code, Codex, Antigravity/agy) — adding a rule/agent/skill/MCP server and propagating it, sharing a skill between CLIs, or invoking /ai-config-sync to execute the sync. Covers the ~/ai-config repo and its ai-config.sh init/apply/status/list/reset commands, the claude/shared/{both,codex,agy} cross-tool skill mechanism, auto-backup, and credential exclusion.
---

# ai-config Sync

## Overview

`~/ai-config` is a git repo that centralizes AI CLI configuration and syncs it between each tool's home dir and the repo (and across machines via git). Driven by `~/ai-config/ai-config.sh`.

Core model: **repo is the source of truth.** `init` pulls live config INTO the repo; `apply` pushes repo config OUT to the live home dirs. `ai-config.sh` and `ai-config.ps1` are thin wrappers over the same Python 3.11+ core. Edit → `init` → commit/push → other machine `git pull` → `apply`.

## Executing a sync (when invoked to run, e.g. /ai-config-sync)

State-changing steps require confirmation. **Only `status` and `list` run automatically.**

1. **Always start with `status`** (read-only) and report the diff:
   ```bash
   cd ~/ai-config && ./ai-config.sh status [tool]
   ```
2. Interpret the diff for the user, then decide the next action and **ask before running it**:
   - Live config changed on this machine, user wants to save it → `./ai-config.sh init [tool]`
   - Repo config should be pushed to live home dirs → `./ai-config.sh apply [tool]` (auto-backs up first)
3. **Never `git add`/`commit`/`push` without explicit approval** (global rule). After an approved `init`/`apply`, show the user `git status` and the proposed commit, and wait.
4. If `~/ai-config` has pre-existing staged changes you did not make, do not bundle them — stage and commit only the files this task touched.

Pass `tool` (`claude`|`codex`|`agy`|`all`) through from the user's request; default `all`.

## Tools managed

| repo subdir | tool | home dir | syncs |
|---|---|---|---|
| `claude/` | Claude Code | `~/.claude/` | CLAUDE.md, settings.json, mcp.json, agents/, commands/, rules/ |
| `codex/` | Codex CLI | `~/.codex/` | AGENTS.md, config.toml, rules/, skills/ |
| `agy/` | Antigravity CLI | `~/.gemini/antigravity-cli/` | settings.json, mcp_config.json, skills/ |

## Commands

```bash
cd ~/ai-config && ./ai-config.sh <command> [tool]
```
`tool` = `claude` | `codex` | `agy` | `all` (default).

| command | does |
|---|---|
| `init [tool]` | collect live config from home dirs INTO repo |
| `apply [tool]` | deploy repo config OUT to home dirs (auto-backs up first) |
| `project [tool]` | project live `~/.claude/` directly to Codex/agy (auto-backs up first) |
| `status [tool]` | diff repo vs live config (read-only, safe to run anytime) |
| `list` | list managed tools + file counts + backup snapshot count |
| `reset` | wipe configs to empty skeleton (confirms first) |

## Decision rules

- **Where does a new skill go?** Claude Code's own slash commands live in `~/.claude/commands/` (Claude-only, not cross-tool). A **skill you want on Codex/agy too** does NOT go in `~/.claude/skills/` — that dir is not synced. Put it in `~/ai-config/claude/shared/`:
  - `claude/shared/both/<skill>/SKILL.md` → projected to Codex **and** agy
  - `claude/shared/codex/<skill>/` → Codex only
  - `claude/shared/agy/<skill>/` → agy only
  - The repo `shared/` copy is authoritative; deleting it there auto-removes the mirror (managed-skill reconciliation). If you also want Claude Code to use it, keep a second copy in `~/.claude/skills/<skill>/`.
- **init vs apply:** changed config on THIS machine and want to save it → `init` (then commit). Want to pull someone else's committed config onto this machine → `apply`. When unsure, run `status` first — it's read-only.
- **mtime is a hint, not authority:** for differing content, `status` shows repo/live modification times and labels the newer side. Use it to spot likely local edits, but remember Git checkout and external copy operations can change mtime; still confirm whether `init` or `apply` matches the user's intent.
- **Always `status` before `apply`** to see what will change. `apply` auto-backs up to `~/.ai-config-backup/<timestamp>/` but previewing is cheaper than restoring.

## Safety (built into the script)

- **Auto-backup** before every `apply` and `project` → `~/.ai-config-backup/<timestamp>/`.
- **Credentials never copied:** `.credentials.json`, `auth.json`, `oauth_creds.json`, `google_accounts.json`, `trustedFolders.json` are always excluded — never hardcode or stage secrets.
- **Codex `[projects.*]` preserved:** `apply` keeps the target machine's project blocks, updating only general settings.
- Shared skills sync only `SKILL.md` + `examples/` + `references/` + `scripts/` + `agents/` per skill.

## Typical workflow: add a cross-CLI skill

1. Author/verify the skill (in `~/.claude/skills/<name>/` if Claude should use it too).
2. Copy `SKILL.md` (+ supporting dirs) into `~/ai-config/claude/shared/both/<name>/`.
3. `./ai-config.sh status` → confirm `+ skills/<name>/SKILL.md (only in ai-config)`.
4. `./ai-config.sh apply` → mirrors it into Codex + agy skills dirs (auto-backup runs).
5. Show `git status` and the exact proposed commit scope; only after explicit user approval, stage/commit/push. Other machines then use `git pull` + `apply`.

## Common mistakes

- Putting a cross-tool skill in `~/.claude/skills/` and expecting Codex/agy to get it — that dir isn't synced; use `claude/shared/`.
- Editing live `~/.codex/...` then forgetting `init` — the change isn't captured until you collect it into the repo.
- Running `apply` without `status` first.
- Trying to sync a Claude slash command to Codex/agy — they have no slash-command concept; only `skills/` cross-syncs.
