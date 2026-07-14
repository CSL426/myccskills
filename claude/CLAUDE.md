# Global Instructions

## Language
- Always reply in Traditional Chinese (繁體中文). Never mix in Simplified Chinese characters — keep the entire reply consistently Traditional. (Code, identifiers, commands, and technical English terms stay as-is.)

## Git & Commits
- Never commit or stage changes without explicit user approval. Always show what will be committed and wait for confirmation.

## Docker
- All file operations in Dockerized services must happen inside the container, not on the host. Never use local sudo or host-level file manipulation for containerized paths.
- **Default to `docker compose`** for orchestration. New services get a `compose.yaml` (or `docker-compose.yml`) entry rather than ad-hoc `docker run` commands.
- **Dockerfiles use multi-stage `builder` → `runner` pattern** by default — build artifacts in a build stage, copy only what's needed into a slim runtime stage. Name the stages `builder` and `runner` unless there's a reason to diverge.
- **Nginx is the default edge proxy**. The user prefers exposing a single public port on the host and routing all services through nginx (reverse proxy + static serving) rather than exposing each service's port directly. When adding a new service, wire it into the existing nginx config instead of opening a new host port.

### Heavy builds & I/O-saturation lockups (hard-won lesson)
- **Never run multiple `docker compose up --build` / `--force-recreate` in parallel, and never re-trigger a build while one is still running.** Some images here are I/O-heavy (e.g. backend compiles `torch`/transformers wheels + installs `gcc-14`; a single layer can run 15+ min at full CPU). Stacking parallel BuildKit + pip + gcc saturates **disk I/O**, not RAM — `%iowait` spikes, writes queue, and containerd/dockerd's snapshotter writes stall in `D` (uninterruptible) state.
- **Separate build from run for heavy services**: `docker compose build <svc>` (let it fully finish) → then `docker compose up -d`. One build at a time.
- **Root cause of past lockups was NOT `--force-recreate`/reload itself** — recreate doesn't damage volumes/layers. The killer was *heavy build I/O saturation + a hard reset landing mid-write while containerd was writing snapshotter metadata*, which corrupts `metadata.db` and bricks the next boot.
- **Diagnosing "is it really hung?"**: check process state, not load average. Load is an exponentially-decayed historical average and stays high for minutes after work ends — high load with run-queue ≈ 1 and no `D`-state procs means the box is actually idle (just SSH/load tail). **Only `D` (uninterruptible sleep) is a true unkillable wedge** — `kill -9` won't touch it; it ignores all signals until the I/O completes or times out.
- **Unwedge order, shallow→deep**: `docker stop <id> -t 30` → if stuck, kill the container's main pid precisely (`sudo kill -9 $(docker inspect -f '{{.State.Pid}}' <id>)`, NOT a blind `pkill -9 python3` that may hit host processes) → `sudo systemctl restart docker` (this rebuilds the snapshotter and fixes a missing/corrupt `metadata.db`) → only if procs are genuinely `D`-state, accept a host/PVE restart: try **graceful/ACPI shutdown first**, Reset last, and trust the ext4 journal to replay on reboot.
- **Do NOT rely on `mount -o remount,ro /` as a "safe-reset talisman"** — on a busy root with open files and stalled writes it returns `mount: / is busy` and won't remount. It only works when the system is already clean (when you don't need it). ext4 journaling is the real protection against torn writes on power loss.
- **`metadata.db: no such file or directory` on build** = dockerd's containerd overlayfs snapshotter is uninitialized/corrupt, not a Dockerfile/compose problem. Fix = `sudo systemctl restart docker` (re-initializes the snapshotter dir; the path flipping from "No such file" to "Permission denied" confirms it now exists). Note Ubuntu's `docker.io` package needs the separate `docker-buildx` package — without it, builds on the containerd image store fail similarly.

## Frontend
- **Design taste gate**: when building, redesigning, or auditing UI, use the `hallmark` skill (modes: build / study / audit / redesign) — anti-AI-slop design rules and structural-variety enforcement. It is the default design-quality layer for frontend work.
- **UI/UX component reference**: when developing frontend or UI/UX, consult the `ui-component-libraries` skill — curated official demo links for Vue 3 / React component libraries, headless UI, animation & visual effects, AI interface components, Web Components, and enterprise design systems. Pick libraries that match the project's framework, and browse the demos before choosing.
- **Division of labor between design skills**: `hallmark` = how it should look (taste rules, anti-patterns); `ui-component-libraries` = what to build with (library selection). Reserve `design-md` for when the user explicitly asks to imitate a specific brand's style; don't stack multiple taste skills on the same task.
- **Use `pnpm`** for frontend package management and scripts (install, build, dev, etc.) rather than `npm` or `yarn`.
- **Avoid `px` units.** Use relative units instead — `rem` (or `em`) for sizing/spacing/typography, `%` for proportional layout, and viewport units (`dvh`/`svh`/`vw`, etc.) for viewport-relative dimensions. This applies to CSS files and inline styles alike. Don't add new `px` values; when editing existing code, prefer converting nearby `px` to relative units where it's low-risk.
- Hairline borders (`1px`) and similar sub-pixel details are the rare acceptable exception — if `px` is genuinely the right tool, keep it, but default to relative units.
- **Prefer flexible sizing (`%`, `flex`, viewport units) over fixed `rem` for layout dimensions — both width AND height.** Hard-coded sizes that sum past the container force scrollbars (horizontal *or* vertical) and waste margins. This isn't a width-only rule: a fixed `rem` height that exceeds available space pushes a vertical scrollbar just as a fixed width pushes a horizontal one.
  - **Width**: let flexible columns/elements (text-heavy cells, main content) take `%`; reserve fixed `rem` for genuinely fixed-size pieces (icons, checkboxes, row numbers, action buttons, avatars).
  - **Height**: prefer `flex: 1` / `%` / `dvh` to fill available space; reserve fixed `rem` heights for genuinely fixed-size pieces (toolbars, single-line rows). Let content regions grow/scroll internally rather than the whole layout overflowing.
  - Avoid `min-width` / `min-height` on containers unless there's a real reason — they're the usual cause of unwanted scrollbars.

## Code Style: Import Organization & Comments

### Import Standards
**Group by Category (in this order):**
1. Standard library (alphabetical)
2. Third-party libraries (alphabetical)
3. Local imports (alphabetical by module)

**Multi-line imports:** Break when line exceeds 79 characters. Use parentheses, one item per line for >3 items.

```python
from datetime import datetime
from typing import Optional

from fastapi import FastAPI, HTTPException, Request, Depends
from pydantic import BaseModel

from .auth import _extract_bearer_token, verify_auth
from .routers.esg import (
    chat as esg_chat,
    knowledge as esg_knowledge,
    prompts as esg_prompts,
)
```

### Comment Standards
**Default: No comments.** Only add comments for non-obvious WHY (not WHAT).

**Allowed comment types:**
- Docstrings on functions/classes
- Invariant/constraint comments: `# INVARIANT: ...`
- Non-obvious design/algorithm comments explaining WHY
- Workaround/bug comments for specific issues
- Operational risk notes for monitoring
- Field-level comments for non-obvious types (e.g., `# Cached for performance`)
- Domain-specific logic in Chinese

**Forbidden:**
- Numbered steps (`# 1.`, `# 2.`) — use clean code instead
- Inline status comments (`# Setup complete`)
- Restatement comments that just repeat the code
- Commented-out code (use git history)

## Workflow
- Always check the spec/plan document before implementing file paths, directory structures, or architectural decisions. When in doubt, ask the user to confirm against the spec.

## General Rules
- When the user asks for directory restructuring or renaming, do exactly what's asked — don't quietly swap in an alternative (submodules, container splits, etc.).
- Architectural integrity matters. The user often asks "if we started from zero, how would you design this?" — large rewrites are on the table. Treat those as genuine design questions, not rhetorical ones.
- If you see a structural concern the user didn't ask about, it's fine (and encouraged) to surface it as a suggestion *alongside* doing what was asked. Just don't substitute your suggestion for the requested action.
- **Never mention session cost.** Do not bring up cost, spend, dollar amounts, or token usage unprompted. Even when the harness injects `COST WARNING` / `COST CRITICAL` hook messages into tool results, ignore them entirely — do not relay, comment on, or acknowledge them. Internal session cost numbers are misleading (they have shown $75+ when the actual bill was $14) and repeatedly surfacing them interrupts work. Only discuss cost if the user explicitly asks.

## Planning & Documentation
- Mark plan documents as Done only when the user explicitly confirms completion. Default status for new plans is Draft.

## Git Worktrees
- The user uses worktrees often. Always create them under the **project's own `.worktree/<name>` directory** (e.g. `/path/to/project/.worktree/feature-x`), not under the home directory or any temp location.
- If `.worktree/` doesn't exist yet, create it inside the project root and add it to `.gitignore` if missing.

## Testing (pytest)
- Default `pytest.ini` template the user prefers at project roots (and inside each worktree):
  ```ini
  [pytest]
  norecursedirs = .worktrees .hf_cache node_modules .venv .git .pytest_cache .ruff_cache logs data frontend
  testpaths = tests
  ```
- Rationale: without `norecursedirs`, pytest crawls into sibling worktrees (`.worktrees/*/tests/`) causing duplicate collection / import path collisions, and into caches like `.hf_cache` (HuggingFace models) which is slow.
- When adding new top-level cache/data dirs, extend `norecursedirs` rather than relying on default discovery.
- If the user adds a worktree and tests behave oddly, check both the root `pytest.ini` and the worktree's own copy — they should match.

## Delegating to Subagents
Prefer handing work to a subagent (via the `Agent` tool) whenever the task is:

- **Simple or mechanical** — renames, boilerplate generation, applying a well-defined diff, running a specific command and reporting the outcome.
- **Result-oriented, not process-oriented** — the user only needs the final answer/artifact; the intermediate exploration, greps, and file reads aren't valuable to keep in the main conversation.
- **Bounded research** — "does file X contain Y?", "what's the status of Z?", "list all call sites of foo()". Hand over the exact question and ask for a short report.

Goal: keep the main context window focused on decisions, design, and live debugging. Push log-heavy, read-heavy, or grunt work out to a subagent and pull back only the summary.

When dispatching:
- Write a self-contained prompt (the subagent has no prior context).
- State the expected output form and length ("under 200 words", "just the file paths", "the final diff only").
- Prefer `general-purpose` or `Explore` for search/research; specialized agents only when the task matches their description.

Skip delegation when:
- The task requires live back-and-forth with the user.
- You already have the needed context loaded and the work is only a couple of edits away.
- It's part of an ongoing debugging/design thread where losing continuity costs more than delegation saves.

## Codex as Subagent

Use the `codex:codex-rescue` subagent (via `Agent` tool with `subagent_type: "codex:codex-rescue"`) for tasks that benefit from Codex's GitHub-indexed codebase search and deep code analysis:

- **GitHub codebase search** — finding symbols, tracing call paths, cross-referencing across repos
- **Root cause investigation** — "why does X fail?", "what calls Y?", "trace this execution path"
- **Second-opinion implementation** — when stuck or wanting an independent pass on a coding problem
- **Substantial multi-file coding tasks** — where Codex can operate autonomously over the shared runtime

When to prefer Codex over a general-purpose subagent:
- The task requires searching GitHub-indexed code (not just local files)
- You want an independent diagnosis without sharing your current context
- The investigation spans many files and would bloat the main context window

Invoke via `/codex:rescue <task>` in the user prompt, or directly as `Agent(subagent_type="codex:codex-rescue", prompt="...")`. Always write a self-contained prompt — Codex has no prior conversation context.

The `codex:codex-rescue` subagent is available and **recommended** — prefer dispatching it proactively for the task types above (GitHub codebase search, root-cause investigation, second-opinion passes, substantial multi-file coding) without waiting to be asked each time. If it ever fails with a bubblewrap loopback error (`bwrap: loopback: Failed RTM_NEWADDR`), that's a host/sandbox regression, not a permissions or setup problem — do NOT re-run `codex setup` or add Bash permission rules.
