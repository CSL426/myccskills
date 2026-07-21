---
name: ci-check
description: >-
  Check CI status for the current project's branch when about to propose a
  commit, right after pushing, or as a wrap-up step after /simplify or
  /code-review — but only in a project that actually has CI configured
  (.github/workflows, .gitlab-ci.yml, .circleci/config.yml,
  azure-pipelines.yml, .travis.yml, Jenkinsfile, bitbucket-pipelines.yml).
  Surfaces the latest run status for the current branch so a red build isn't
  missed while stacking more commits on top. Skip silently in repos with no
  CI config, no network, or no CLI available for the provider — this is a
  lightweight side-check, not a CI debugging tool.
metadata:
  short-description: 'Check CI status during commit or /simplify workflows, if the project has CI configured'
---

Lightweight status check, not an investigation. Run this quietly as a side
step — don't announce "checking CI" unless there's something to report.

## 1. Detect CI

Look for, in order:

- `.github/workflows/*.yml` / `*.yaml` → GitHub Actions
- `.gitlab-ci.yml` → GitLab CI
- `.circleci/config.yml` → CircleCI
- `azure-pipelines.yml` → Azure Pipelines
- `.travis.yml` → Travis CI
- `Jenkinsfile` → Jenkins
- `bitbucket-pipelines.yml` → Bitbucket Pipelines

No match → stop here, say nothing. Don't mention CI at all in a project that
doesn't have it.

## 2. Check status

**GitHub Actions** (if `gh` CLI is available and authenticated):

```bash
gh run list --branch "$(git branch --show-current)" --limit 3
```

If the current `HEAD` commit has already been pushed, prefer matching by
commit for precision:

```bash
gh run list --commit "$(git rev-parse HEAD)"
```

**GitLab CI** (if `glab` CLI is available):

```bash
glab ci status
```

**Other providers**, or no matching CLI installed: don't try to scrape a web
UI. Just note once that CI is configured but status can't be checked
automatically here — point at the remote repo's CI page if the remote URL is
known.

## 3. Report

One line, not a wall of output:

- All recent runs green → nothing to say, or a brief "CI green" if directly
  relevant to what the user asked.
- Latest run failed or in progress → say so plainly, with the run's title/URL
  (`gh run view <id> --web` link or the printed URL), before proposing new
  work on top of it.
- No runs yet for this branch/commit (e.g. not pushed) → note that CI hasn't
  run against this yet; nothing more to do.

## 4. Never block, never auto-fix

This skill only surfaces status — it does not investigate failures, rerun
jobs, or change code. If the user wants the failure diagnosed, that's a
separate, explicit task: look at the failing job's logs
(`gh run view <run-id> --log-failed`), find the root cause, and only then
propose or make a fix.

## When this pairs with commit

Before finalizing a commit message or proposing what to stage, glance at
whether the current branch's last CI run is red. If it is, mention it — the
user may want to fix that first rather than stack more commits on a known
failure. Don't refuse to commit; just don't stay silent about a red build.

## When this pairs with /simplify or /code-review

After the pass finishes and any changes are in place, if the branch was
already pushed and CI ran on it, check whether that run is green. This is a
wrap-up sanity check, not a gate — report what you see and stop.
