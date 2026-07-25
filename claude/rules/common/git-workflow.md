# Git Workflow

## Commit Message Format

```
<type>: <description>

<optional body>
```

Types: feat, fix, refactor, docs, test, chore, perf, ci

Attribution is disabled globally via `~/.claude/settings.json` — don't add
Co-Authored-By trailers.

## Pull Requests

Base the summary on the full commit range (`git diff <base>...HEAD`), not just
the latest commit. Push new branches with `-u`.
