---
name: ci-check
description: >-
  Two jobs, both only in a project that actually has CI configured
  (.github/workflows, .gitlab-ci.yml, .circleci/config.yml,
  azure-pipelines.yml, .travis.yml, Jenkinsfile, bitbucket-pipelines.yml):
  (1) BEFORE running `git push`, `git push --tags`, or creating a release
  tag, run the same checks CI would run (tests, lint, build) locally first,
  so a failure is caught before spending a round trip through CI — this is
  the primary trigger, not an afterthought. (2) After pushing, or as a
  wrap-up step after /simplify or /code-review, check the latest CI run
  status for the current branch so a red build isn't missed while stacking
  more commits on top. Skip silently in repos with no CI config, no network,
  or no CLI available for the provider — this is a lightweight side-check,
  not a CI debugging tool.
metadata:
  short-description: 'Run CI-equivalent checks before pushing/tagging, and check CI status after, if the project has CI configured'
---

Lightweight, not an investigation. Run this quietly as a side step — don't
announce "checking CI" unless there's something to report.

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

## 2. Before push or tag — run CI's checks locally first

This is the main point of this skill: catch a failure before it costs a
round trip through CI, not after. Do this before any `git push`, and
especially before `git push --tags` / creating a release tag, since a tag
push often triggers a build+release job that a plain commit push does not.

- Read the CI config file(s) found in step 1 and pull out the actual test/
  lint/build commands from the job steps (e.g. a `run:` line in a GitHub
  Actions workflow, a `script:` entry in `.gitlab-ci.yml`). Don't guess a
  generic command — use what the project's own CI actually runs.
- Run those same commands locally now, across the OSes/versions you
  reasonably can (e.g. if the matrix includes Windows and you're on Linux,
  at least run the Linux-equivalent checks — note the gap rather than
  silently skipping it).
- If something fails locally, stop and report it — don't push a change you
  know will fail CI. Fix it first, or tell the user what's failing and let
  them decide.
- If everything passes locally, that's still not a guarantee for
  platforms/configurations you couldn't reproduce locally (e.g. a different
  OS in the matrix) — say so plainly rather than implying full coverage.

## 3. After pushing — check status

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

## 4. Report

One line, not a wall of output:

- All recent runs green → nothing to say, or a brief "CI green" if directly
  relevant to what the user asked.
- Latest run failed or in progress → say so plainly, with the run's title/URL
  (`gh run view <id> --web` link or the printed URL), before proposing new
  work on top of it.
- No runs yet for this branch/commit (e.g. not pushed) → note that CI hasn't
  run against this yet; nothing more to do.

## 5. Never block, never auto-fix

This skill only surfaces status — it does not investigate failures, rerun
jobs, or change code. If the user wants the failure diagnosed, that's a
separate, explicit task: look at the failing job's logs
(`gh run view <run-id> --log-failed`), find the root cause, and only then
propose or make a fix.

## When this pairs with push or a release tag

This is the trigger that matters most. Before running `git push` — and
especially before `git push --tags` / `git push origin <tag>`, since that
often kicks off a build+release pipeline that costs real time and can
publish a broken release — run step 2 first. Don't wait for CI to be the
one to tell you it's broken.

## When this pairs with commit

Before finalizing a commit message or proposing what to stage, glance at
whether the current branch's last CI run is red. If it is, mention it — the
user may want to fix that first rather than stack more commits on a known
failure. Don't refuse to commit; just don't stay silent about a red build.

## When this pairs with /simplify or /code-review

After the pass finishes and any changes are in place, if the branch was
already pushed and CI ran on it, check whether that run is green. This is a
wrap-up sanity check, not a gate — report what you see and stop.
