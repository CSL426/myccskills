---
name: install-ai-config
description: Use when setting up the ai-config (acg) CLI on a machine that does not have it yet, or when it is installed but not yet connected to the private data repository — new laptop, fresh VM, reinstalled OS, container, or "my AI CLI settings are missing here". Covers the standalone installer for Linux/macOS/Windows, first-run setup against the private config repo, activating tab completion in the current shell, and the first pull/apply that deploys CLAUDE.md, rules, agents, commands, and skills to Claude Code, Codex, and Antigravity.
---

# Installing ai-config on a new machine

`ai-config` (short alias `acg`) syncs AI CLI configuration between machines and
between Claude Code, Codex, and Antigravity. The public tool repo holds the CLI;
the private data repo holds the actual configuration.

The target machine needs **only Git**. The released CLI is a single executable
with its Python runtime bundled — no Python, pip, or pipx required.

## 1. Install the binary

Linux, macOS, Git Bash, MSYS2, Cygwin:

```bash
curl -fsSL https://raw.githubusercontent.com/CSL426/ai-config/main/install.sh | bash
```

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/CSL426/ai-config/main/install.ps1 | iex
```

On Windows the shell installer delegates to the PowerShell one automatically and
also installs `acg.cmd` plus extensionless launchers for Git Bash.

Optional environment overrides: `AI_CONFIG_VERSION` pins a release tag,
`AI_CONFIG_BIN_DIR` changes the binary destination.

## 2. Connect the private data repo

If the installer ran in an interactive terminal it already offered first-run
setup. When input was redirected (piped installs often are), run setup yourself:

```bash
ai-config setup --data-dir <path> --repo-url <git-url>
```

Setup clones or opens the repo, verifies the required layout, then proves push
access by creating a unique temporary remote branch and deleting it. The local
path is saved only after that push **and** its cleanup both succeed.

The path persists in the platform config dir — Linux
`${XDG_CONFIG_HOME:-~/.config}/ai-config/config.json`, macOS
`~/Library/Application Support/ai-config/config.json`, Windows
`%APPDATA%\ai-config\config.json`. `AI_CONFIG_REPO` overrides it at runtime and
wins over the saved value.

Use an **SSH URL**. URLs with embedded HTTP credentials are rejected outright.
If the account differs from the machine's default SSH identity, configure a host
alias in `~/.ssh/config` and use `git@<alias>:<owner>/<repo>.git`.

## 3. Deploy the configuration

```bash
ai-config pull      # fast-forward the data repo, then show status
ai-config status    # read-only preview; safe anytime
ai-config apply     # deploy to the tool home dirs (auto-backs up first)
```

`apply` writes `CLAUDE.md`, `settings.json`, `mcp.json`, `statusline.sh`, and the
`rules/ agents/ commands/ skills/` directories into `~/.claude`, plus the Codex
and Antigravity equivalents. Always `status` before `apply` — previewing is
cheaper than restoring from `~/.ai-config-backup/<timestamp>/`.

## 4. Activate tab completion in the current shell

Installers register completion, but an already-running shell has not sourced it.
Either open a new terminal or, to activate immediately:

```bash
hash -r && source ~/.local/share/bash-completion/completions/ai-config.bash
```

A subprocess cannot refresh its parent shell, so there is no way for the
installer to do this for a session that is already open.

## Verifying

```bash
ai-config version
ai-config list      # managed tools, file counts, backup snapshot count
ai-config status
```

## Common problems

- **`ai-config update` says to run a PowerShell command.** The installed binary
  predates the self-update logic. Follow the printed command to replace it.
- **Setup fails at the push check.** Push access is genuinely missing, not a
  false alarm — setup refuses to save a repo it cannot write to. Verify the SSH
  key and remote URL, then retry.
- **`status` reports differences in `permissions`.** It should not — that key is
  machine-local and excluded from sync (also `trustedWorkspaces` on Antigravity).
  Each machine keeps its own allowlist; the difference is expected.
- **`apply` overwrote a local customization.** The data repo is the source of
  truth. Capture local changes with `ai-config init <tool>` *before* applying,
  or recover from the automatic backup.
- **Tab completion lists nothing after install.** See step 4 — the shell has not
  sourced the new script yet.

Full detail lives in the tool repo's `README.md` and `docs/`; `docs/skills.md`
covers authoring and installing individual skills.
