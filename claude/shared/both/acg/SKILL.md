---
name: acg
description: Use when the user wants to run, sync, share, or version-control AI CLI configuration across machines or across tools (Claude Code, Codex, Antigravity/agy) — adding a rule/agent/skill/MCP server and propagating it, sharing a skill between CLIs, or invoking /acg to execute the sync. Covers the ~/ai-config tool repo, nested ~/ai-config/data settings repo, the ai-config/acg CLI commands (status/init/apply/pull/push/project/package), the claude/shared/{both,codex,agy} cross-tool skill mechanism, auto-backup, and credential exclusion.
---

# ai-config Sync

## Overview

`~/ai-config` is the public tool repo. Its ignored `~/ai-config/data` directory is a separate private Git repo that centralizes AI CLI configuration and syncs it between each tool's home dir and other machines.

Core model: **the data repo is the source of truth.** `init` pulls live config INTO `~/ai-config/data`; `apply` pushes data repo config OUT to the live home dirs.

Round trip: edit → `init` → commit in `data/` (or `ai-config push`, which does init+review+commit+push together) → on the other machine `pull` → `apply`.

## Executing a sync (when invoked to run, e.g. /acg)

State-changing steps require confirmation. **Only `status` and `list` run automatically.**

1. **Always start with `status`** (read-only) and report the diff:
   ```bash
   ai-config status [tool]
   ```
2. Interpret the diff for the user, then decide the next action and **ask before running it**:
   - Live config changed on this machine, user wants to save it → `ai-config init [tool]`
   - Repo config should be pushed to live home dirs → `ai-config apply [tool]` (auto-backs up first)
   - Remote has newer config → `ai-config pull [tool]` (fast-forward only, then shows status)
3. **Never `git add`/`commit`/`push` without explicit approval** (global rule). This includes `ai-config push`, which commits and pushes as part of its flow — treat invoking it as requiring the same approval as a manual commit. After an approved `init`/`apply`, show the user `git status` and the proposed commit, and wait.
4. If `~/ai-config/data` has pre-existing staged changes you did not make, do not bundle them — stage and commit only the files this task touched.

Pass `tool` (`claude`|`codex`|`agy`|`all`) through from the user's request; default `all`.

## Tools managed

| repo subdir | tool | home dir | syncs |
|---|---|---|---|
| `claude/` | Claude Code | `~/.claude/` | CLAUDE.md, settings.json, mcp.json, statusline.sh, agents/, commands/, rules/, skills/ |
| `codex/` | Codex CLI | `~/.codex/` | AGENTS.md, config.toml, rules/, skills/ |
| `agy/` | Antigravity CLI | `~/.gemini/antigravity-cli/` | settings.json, mcp_config.json, skills/ |

## Commands

```bash
ai-config <command> [tool]     # `acg` is the short alias
```
`tool` = `claude` | `codex` | `agy` | `all` (default) — accepted by `init`, `apply`, `project`, `status`, `pull`, `push`, `sync`.

| command | does |
|---|---|
| `status [tool]` | diff repo vs live config (read-only, safe anytime) |
| `init [tool]` | collect live config from home dirs INTO repo |
| `apply [tool]` | deploy repo config OUT to home dirs (auto-backs up first) |
| `project [tool]` | project live `~/.claude/` directly to Codex/agy (auto-backs up first) |
| `pull [tool]` | fast-forward the data repo, then show status |
| `sync [tool]` | alias for `pull` |
| `push [tool]` | gather → review → commit → push, in one guarded flow (see below) |
| `list` | list managed tools + file counts + backup snapshot count |
| `package [skill]` | zip a shared skill for Claude Desktop upload |
| `setup` | configure the data repo remote and verify push access |
| `update [version]` | install the latest release, or a pinned one (also downgrades) |
| `skill` | print the built-in acg usage guide (works before `setup`) |
| `completion` | print the Bash/PowerShell completion script |
| `version` | show the installed version |
| `reset` | wipe configs to empty skeleton (confirms first) |

### `push` — the guarded commit path

`push` is not a plain `git push`; it runs `init`, derives a conventional-commit
message from the staged paths (e.g. `chore: update claude settings`), shows the
diff, and asks for confirmation before committing and pushing.

Its guards, worth knowing because they cause "failures" that are actually
refusals to proceed:

- **Pre-staged changes abort it.** Anything already `git add`ed makes push bail so
  it can't commit a diff you didn't review. Unstage first.
- **Snapshot check.** If the staged tree changes between review and commit, the
  commit is rolled back via `update-ref` and nothing is pushed.
- **Detached HEAD or an in-progress merge/rebase** cancels the push.
- On cancel, changes are left **unstaged**, not lost.

Because `push` reviews and commits by itself, don't hand-stage files first when
using it. For a hand-written commit message, commit manually in `data/` instead.

## Decision rules

- **Where does a new skill go?** Claude Code's own slash commands live in `~/.claude/commands/` (Claude-only, not cross-tool). For Claude Code skills, `~/.claude/skills/` **is** synced — it's a managed dir alongside `rules/` and `commands/`, so `init` gathers it and `apply` deploys it. A skill you want on **Codex/agy too** additionally needs a copy in `~/ai-config/data/claude/shared/`:
  - `claude/shared/both/<skill>/SKILL.md` → projected to Codex **and** agy
  - `claude/shared/codex/<skill>/` → Codex only
  - `claude/shared/agy/<skill>/` → agy only
  - The repo `shared/` copy is authoritative; deleting it there auto-removes the mirror (managed-skill reconciliation). If you also want Claude Code to use it, keep a second copy in `~/.claude/skills/<skill>/`.
- **init vs apply:** changed config on THIS machine and want to save it → `init` (then commit). Want to pull someone else's committed config onto this machine → `apply`. When unsure, run `status` first — it's read-only.
- **mtime is a hint, not authority:** for differing content, `status` shows repo/live modification times and labels the newer side. Use it to spot likely local edits, but remember Git checkout and external copy operations can change mtime; still confirm whether `init` or `apply` matches the user's intent.
- **Always `status` before `apply`** to see what will change. `apply` auto-backs up to `~/.ai-config-backup/<timestamp>/` but previewing is cheaper than restoring.
- **Read `-` lines carefully:** they mark files that exist only live, which `apply` would delete. If that content matters, `init` it into the repo first. (Requires 1.0.16+; earlier versions did not report untracked content in a managed directory the repo lacked entirely.)

## Safety (built into the script)

- **Auto-backup** before every `apply` and `project` → `~/.ai-config-backup/<timestamp>/`.
- **Credentials never copied:** `.credentials.json`, `auth.json`, `oauth_creds.json`, `google_accounts.json`, `trustedFolders.json` are always excluded — never hardcode or stage secrets.
- **Codex `[projects.*]` preserved:** `apply` keeps the target machine's project blocks, updating only general settings.
- **`permissions` is machine-local and never synced** (also `trustedWorkspaces` for agy). Each machine keeps its own allowlist, so a permission granted here won't appear on the other machine — that difference in `status` is expected, not drift.
- **Plugin `cache/` and `.git` are skipped** when projecting `plugins/` to agy — they're regenerable install cache, and `.git` pack files are read-only, which breaks re-mirroring.
- **"mirror stale" on a machine you just pulled to usually means run `apply`**, not edit `mirror-hash` — the local mirror source is the outdated side. `mirror-hash` is LF-normalized as of 1.0.17, so CRLF line endings on Windows no longer read as drift.
- Shared skills sync only `SKILL.md` + `examples/` + `references/` + `scripts/` + `agents/` per skill.

## Typical workflow: add a cross-CLI skill

1. Author/verify the skill (in `~/.claude/skills/<name>/` if Claude should use it too).
2. Copy `SKILL.md` (+ supporting dirs) into `~/ai-config/data/claude/shared/both/<name>/`.
3. `ai-config status` → confirm `+ skills/<name>/SKILL.md (only in ai-config)`.
4. `ai-config apply` → mirrors it into Codex + agy skills dirs (auto-backup runs).
5. Show `git status` and the exact proposed commit scope; only after explicit user approval, stage/commit/push (or run `ai-config push`, which reviews and confirms before committing). Other machines then use `ai-config pull` + `apply`.
6. To hand the skill to Claude Desktop instead, `ai-config package <skill>` zips it for upload.

## Common mistakes

- Putting a cross-tool skill only in `~/.claude/skills/` and expecting Codex/agy to get it. That dir syncs to other **machines**, but only `claude/shared/` projects to other **tools** — a cross-tool skill needs both copies.
- Editing live `~/.codex/...` then forgetting `init` — the change isn't captured until you collect it into the repo.
- Running `apply` without `status` first.
- Trying to sync a Claude slash command to Codex/agy — they have no slash-command concept; only `skills/` cross-syncs.
