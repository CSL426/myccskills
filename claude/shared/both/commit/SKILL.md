---
name: commit
description: Smart commit with auto-split detection — analyzes git changes, scans for secrets, and proposes conventional commit messages.
metadata:
  mirror-of: ~/.claude/commands/commit.md
  mirror-hash: f074576e3cf32eeb17867bd6b400cc9bfee1a06bb2d9fe181049ab86d6612e08
---

Analyze git changes and propose commits.

Run these git commands first:
1. `git status`
2. `git diff HEAD`
3. `git log --oneline -10`
4. `git diff HEAD | grep -inE '(password|secret|api_key|api_secret|auth_token|access_token|private_key|DATABASE_URL|AWS_|GITHUB_TOKEN|STRIPE_)' || echo 'No secrets detected'`

Then analyze and propose commit messages.

**Commit Style:**
- Format: `type: short description in english` — colon is MANDATORY
- Types: feat, fix, refactor, docs, test, chore, perf, style
- One line only, no body, no Co-Authored-By
- Lowercase (except proper nouns)

**Type selection:**
- refactor: ONLY pure structural changes, zero behavior change. Any new param/endpoint/config/capability = NOT refactor.
- feat: new behavior or capability, even if small
- chore: infra/tooling, no app behavior change
- fix: corrects a bug
- When in doubt → prefer feat or chore over refactor

**Splitting — only split when concerns are clearly unrelated:**
- Group backend + frontend together if they serve the same feature
- package-lock.json → group with whoever caused the dep change
- Default: keep together, don't over-split

**Important:**
- DO NOT run git add or git commit — propose only.
- If secrets scan has matches → STOP and list them.
- If no changes → say so and stop.
