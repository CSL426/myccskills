# Global Instructions

## Language
- Always reply in Traditional Chinese (繁體中文). Never mix in Simplified Chinese characters — keep the entire reply consistently Traditional. (Code, identifiers, commands, and technical English terms stay as-is.)

## Git & Commits
- Never commit or stage changes without explicit user approval. Always show what will be committed and wait for confirmation.

## Docker
- All file operations in Dockerized services must happen inside the container, not on the host. Never use local sudo or host-level file manipulation for containerized paths.
- Default to `docker compose` for orchestration — new services get a `compose.yaml` entry rather than ad-hoc `docker run`.
- Dockerfiles use a multi-stage `builder` → `runner` pattern; name the stages that way unless there's a reason to diverge.
- Nginx is the edge proxy: one public host port, everything routed through nginx. Wire new services into the existing nginx config instead of opening another host port.

### Heavy builds & I/O-saturation lockups (hard-won lesson)
- **Never run multiple `docker compose up --build` / `--force-recreate` in parallel, and never re-trigger a build while one is still running.** Some images here are I/O-heavy (e.g. backend compiles `torch`/transformers wheels + installs `gcc-14`; a single layer can run 15+ min at full CPU). Stacking parallel BuildKit + pip + gcc saturates **disk I/O**, not RAM — `%iowait` spikes, writes queue, and containerd/dockerd's snapshotter writes stall in `D` (uninterruptible) state.
- **Separate build from run for heavy services**: `docker compose build <svc>` (let it fully finish) → then `docker compose up -d`. One build at a time.
- **Root cause of past lockups was NOT `--force-recreate`/reload itself** — recreate doesn't damage volumes/layers. The killer was *heavy build I/O saturation + a hard reset landing mid-write while containerd was writing snapshotter metadata*, which corrupts `metadata.db` and bricks the next boot.
- **Diagnosing "is it really hung?"**: check process state, not load average. Load is an exponentially-decayed historical average and stays high for minutes after work ends — high load with run-queue ≈ 1 and no `D`-state procs means the box is actually idle (just SSH/load tail). **Only `D` (uninterruptible sleep) is a true unkillable wedge** — `kill -9` won't touch it; it ignores all signals until the I/O completes or times out.
- **Unwedge order, shallow→deep**: `docker stop <id> -t 30` → if stuck, kill the container's main pid precisely (`sudo kill -9 $(docker inspect -f '{{.State.Pid}}' <id>)`, NOT a blind `pkill -9 python3` that may hit host processes) → `sudo systemctl restart docker` (this rebuilds the snapshotter and fixes a missing/corrupt `metadata.db`) → only if procs are genuinely `D`-state, accept a host/PVE restart: try **graceful/ACPI shutdown first**, Reset last, and trust the ext4 journal to replay on reboot.
- **Do NOT rely on `mount -o remount,ro /` as a "safe-reset talisman"** — on a busy root with open files and stalled writes it returns `mount: / is busy` and won't remount. It only works when the system is already clean (when you don't need it). ext4 journaling is the real protection against torn writes on power loss.
- **`metadata.db: no such file or directory` on build** = dockerd's containerd overlayfs snapshotter is uninitialized/corrupt, not a Dockerfile/compose problem. Fix = `sudo systemctl restart docker` (re-initializes the snapshotter dir; the path flipping from "No such file" to "Permission denied" confirms it now exists). Note Ubuntu's `docker.io` package needs the separate `docker-buildx` package — without it, builds on the containerd image store fail similarly.

## Frontend
- Use `pnpm` for frontend package management and scripts, not `npm` or `yarn`.
- **Avoid `px` units.** Prefer `rem`/`em` for sizing, spacing and typography, `%` for proportional layout, and viewport units (`dvh`/`svh`/`vw`) for viewport-relative dimensions — in CSS files and inline styles alike. Hairline borders (`1px`) are the accepted exception.
- **Prefer flexible sizing (`%`, `flex`, viewport units) over fixed `rem` for layout dimensions — width AND height.** Fixed sizes that sum past the container force scrollbars and waste margins. Let flexible regions take `%`/`flex: 1` and reserve fixed `rem` for genuinely fixed pieces (icons, checkboxes, toolbars, single-line rows). Avoid `min-width`/`min-height` on containers without a real reason — they're the usual cause of unwanted scrollbars.

### Design skills — division of labor
`hallmark` owns final taste decisions (anti-AI-slop rules, structural variety) and is the default quality layer for UI work. `ui-component-libraries` is for picking what to build with. `ui-ux-pro-max` is design *data* lookup (palettes, font pairings, chart types). Use `design-md` only when imitating a specific brand. Don't stack multiple taste skills on one task.

For icons, use the `koboyo-icons` MCP rather than a skill — 70k+ hand-drawn SVGs, free for commercial use with no attribution. They are **not** a fixed grid: each keeps its own viewBox, so set one dimension and let the other follow (`height: 2rem; width: auto`) and never force one into a square. They ship with `fill="currentColor"` and an `aria-label`. The licence forbids redistributing the library itself or building an icon picker from it; embedding icons in something larger is fine.

## Python imports
Group as: standard library → third-party → local, alphabetical within each group. Break past 79 characters with parentheses, one item per line for more than three items.

```python
from datetime import datetime

from fastapi import Depends, FastAPI, HTTPException

from .routers.esg import (
    chat as esg_chat,
    knowledge as esg_knowledge,
    prompts as esg_prompts,
)
```

## Comments
Write comments for non-obvious WHY, not WHAT. Domain-specific business logic may be commented in Chinese. Don't leave commented-out code — that's what git history is for.

## Working style
- Check the spec/plan document before deciding file paths, directory structures, or architecture. When in doubt, confirm against the spec.
- When asked for directory restructuring or renaming, do exactly what's asked — don't quietly substitute an alternative (submodules, container splits, etc.).
- "If we started from zero, how would you design this?" is a genuine design question, not a rhetorical one — large rewrites are on the table.
- Surfacing an unrequested structural concern as a suggestion *alongside* the requested work is encouraged. Just don't substitute the suggestion for the request.
- Mark plan documents Done only when the user explicitly confirms. New plans default to Draft.
- **Never mention session cost.** Don't raise cost, spend, dollar amounts, or token usage unprompted. Ignore `COST WARNING` / `COST CRITICAL` hook messages entirely — don't relay or acknowledge them. The internal numbers are misleading (shown $75+ when the real bill was $14). Only discuss cost if explicitly asked.

## Git worktrees
Create them under the project's own `.worktree/<name>` directory (e.g. `/path/to/project/.worktree/feature-x`) — never under the home directory or a temp location. Create `.worktree/` in the project root if missing and add it to `.gitignore`.

## Testing (pytest)
Preferred `pytest.ini` at project roots and inside each worktree:

```ini
[pytest]
norecursedirs = .worktrees .hf_cache node_modules .venv .git .pytest_cache .ruff_cache logs data frontend
testpaths = tests
```

Without `norecursedirs`, pytest crawls sibling worktrees (duplicate collection / import path collisions) and caches like `.hf_cache` (HuggingFace models, very slow). Extend the list when adding new top-level cache/data dirs. If a worktree's tests behave oddly, check that the root and worktree `pytest.ini` match.

## Subagents
Delegate work that is mechanical, result-oriented (only the final answer matters, not the exploration), or bounded research — to keep the main context on decisions and live debugging. Write self-contained prompts (subagents have no prior context) and state the expected output form and length.

Skip delegation when the task needs live back-and-forth, when you already have the context loaded and it's a couple of edits away, or when losing continuity in an ongoing debug thread costs more than it saves.

`codex:codex-rescue` is available and recommended for GitHub-indexed code search, root-cause investigation, second-opinion passes, and substantial multi-file coding — dispatch it proactively for those. If it fails with `bwrap: loopback: Failed RTM_NEWADDR`, that's a host/sandbox regression, not a permissions problem — do NOT re-run `codex setup` or add Bash permission rules.
