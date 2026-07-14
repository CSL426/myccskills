---
description: Delegate investigation, second-opinion analysis, or a coding task to Gemini (Antigravity CLI) via the agy-rescue subagent
argument-hint: "[--background|--wait] [--resume|--fresh] [--readonly] [--model <name>] [what Gemini should investigate, solve, or continue]"
allowed-tools: Agent
---

Invoke the `agy-rescue` subagent via the `Agent` tool (`subagent_type: "agy-rescue"`), forwarding the raw user request as the prompt.
`agy-rescue` is a subagent, not a skill — do not call `Skill(agy-rescue)` (that re-enters this command and hangs the session).
The final user-visible response must be Gemini's output verbatim.

Raw user request:
$ARGUMENTS

Execution mode:

- If the request includes `--background`, run the subagent in the background.
- If the request includes `--wait`, run it in the foreground.
- If neither flag is present, default to foreground.
- `--background` / `--wait` are execution flags for Claude Code — strip them from the forwarded prompt.
- `--resume`, `--fresh`, `--readonly`, `--model <name>` are runtime flags for the subagent — keep them in the forwarded prompt (the subagent maps them to agy flags), but do not treat them as part of the natural-language task text.

Operating rules:

- The forwarded prompt MUST be self-contained: restate the goal, relevant file paths, constraints, and desired output format from the current conversation. Gemini has no access to this conversation.
- If the user's request references conversation context ("the bug we just found", "that file"), resolve those references into concrete paths/descriptions before forwarding.
- Do not investigate, read files, or answer the task yourself — your only job is routing.
- Return the subagent's final message verbatim as the user-visible response. If it reports an error (agy missing, auth failure, timeout), show that error as-is.
