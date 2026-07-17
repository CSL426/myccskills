---
description: Sync AI CLI config across tools/machines via ~/ai-config/data (status auto-runs; init/apply/commit ask first)
---

Invoke the `ai-config-sync` skill via the Skill tool to sync AI CLI configuration through the nested `~/ai-config/data` repo.

Arguments (optional): $ARGUMENTS — a tool (`claude`|`codex`|`agy`|`all`, default `all`) and/or an intent (e.g. "apply", "save my changes", "share this skill to all CLIs").

Always run `ai-config status` first and report the diff. Do NOT run `init`, `apply`, `git commit`, or `git push` without explicit user approval — confirm each state-changing step before executing.
