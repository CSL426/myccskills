---
name: sbom-report
description: Use when the user asks to generate, regenerate, or rerun a software bill of materials (SBOM), SPDX manifest, or dependency vulnerability / security report for a project. Covers Microsoft SBOMTool (SPDX generation) and the ex-sbom Gin HTTP server (PDF report rendering), including .NET sandbox extraction quirks and the lockfile-vs-requirements version caveat.
---

# SBOM Report Generation

## Overview

Generate an SPDX SBOM for a project with Microsoft **SBOMTool**, then render a PDF report with the **ex-sbom** HTTP server. The two tools are independent: SBOMTool emits an SPDX JSON file; ex-sbom is a server that ingests that JSON and produces a PDF.

Core principle: generate from a **clean temporary copy** of the source (not the live worktree), and treat reported versions with suspicion — SBOMTool may read lower-bound `requirements.txt` pins rather than resolved lockfile versions.

## Parameters (ask or infer before running)

| Param | Meaning | Example |
|-------|---------|---------|
| `PROJECT_ROOT` | repo / worktree to scan | `/home/human/jtai/.worktrees/jtai-rag` |
| `PROJECT_NAME` | `-pn` value | `jtai-project` |
| `ORG` | publisher org | `JT AI` |
| `OUT_DIR` | where to drop SPDX/PDF artifacts | `/home/human/jtai/.worktrees` |
| `TS` | a timestamp tag | `$(date +%Y%m%d_%H%M%S)` |

If the user names a project but not these, infer `PROJECT_ROOT` from context and derive the rest; only ask when genuinely ambiguous.

## Execution mode — dispatch to a subagent by default

This whole procedure (Steps 1–3 plus cleanup) is mechanical, result-oriented, and produces a lot of log noise (rsync output, SBOMTool's verbose telemetry dump, curl JSON) that has no value once the run succeeds. **Default to running it via the `Agent` tool (general-purpose subagent) rather than inline in the main conversation**, so that noise stays out of the main context and only the final artifact paths + caveat come back.

Only run inline (not via subagent) if the user explicitly asks to see the steps live, or if the invocation is already happening inside a subagent (no nested dispatch).

When dispatching, write a self-contained prompt that includes: PROJECT_ROOT, PROJECT_NAME, ORG, OUT_DIR, the full Step 1–3 commands from this skill (the subagent has no memory of this skill file), the `pkill -f ex-sbom` cleanup requirement (not `kill %1`), and the interpretation caveat to repeat back. Ask for a report under ~150 words: final `.spdx.json` and `.pdf` paths, package count, cleanup confirmation, and the version-accuracy caveat.

## Tool locations

- SBOMTool binary: `/home/human/.local/bin/sbom-tool`
- ex-sbom binary: `/home/human/.local/bin/ex-sbom`

If either is missing, stop and tell the user — do not attempt to install.

## Step 1 — Prepare a clean source copy

Copy tracked files plus relevant untracked dependency descriptors (`pyproject.toml`, `uv.lock`, `requirements/`, `package.json`, lockfiles) into a temp dir. Exclude heavy/irrelevant trees:

```bash
SRC=/tmp/sbom-src-$TS
rsync -a --exclude '.git' --exclude '.venv' --exclude 'node_modules' \
  --exclude 'frontend/node_modules' --exclude 'data' --exclude 'logs' \
  --exclude '_manifest' "$PROJECT_ROOT"/ "$SRC"/
```

Full `rsync` can be slow if large assets/caches slip through — verify the exclude list covers them.

## Step 2 — Generate SPDX with SBOMTool

SBOMTool is a self-contained .NET binary; in sandboxed sessions it needs a writable bundle extraction dir, or it fails to start:

```bash
MANIFEST=/tmp/sbom-out-$TS
DOTNET_BUNDLE_EXTRACT_BASE_DIR=/tmp/sbom-tool-extract-$TS \
/home/human/.local/bin/sbom-tool generate \
  -b "$SRC" -bc "$SRC" -m "$MANIFEST" \
  -pn "$PROJECT_NAME" -pv 0.0.0 \
  -ps "Organization: $ORG" \
  -nsb https://example.local/sbom/full-project \
  -D true -V Information
```

The SPDX file lands at:

```text
$MANIFEST/_manifest/spdx_2.2/manifest.spdx.json
```

Copy it beside prior reports for easy reference:

```bash
cp "$MANIFEST/_manifest/spdx_2.2/manifest.spdx.json" \
   "$OUT_DIR/$PROJECT_NAME-current-$TS.spdx.json"
```

## Step 3 — Render PDF with ex-sbom

`ex-sbom` is **not** a CLI report command — it starts a Gin HTTP server. Start it on an explicit port (commonly 18080):

```bash
GIN_MODE=release PORT=18080 /home/human/.local/bin/ex-sbom &
```

Endpoints:
- `POST /sbom/upload?name=<filename>` — `Content-Type: application/json`, raw SPDX JSON body.
- `GET /sbom/report/<filename>` — renders the PDF, returns JSON with the generated PDF filename.

```bash
name=$PROJECT_NAME-current-$TS.spdx.json
curl -sS -X POST "http://127.0.0.1:18080/sbom/upload?name=$name" \
  -H 'Content-Type: application/json' \
  --data-binary @"$OUT_DIR/$name"
curl -sS "http://127.0.0.1:18080/sbom/report/$name"
```

ex-sbom writes the PDF into its **process working directory**. If started from a repo root, move the PDF into `$OUT_DIR` so the repo gains no untracked artifact. **Stop the ex-sbom server when done** with `pkill -f ex-sbom` — not `kill %1`. Each skill run happens in a fresh Bash session, so `%1` only refers to jobs started in *that* session; a server backgrounded in an earlier run has no job number here and `kill %1` silently does nothing (or kills the wrong job), leaving the old server running. `pkill -f ex-sbom` finds it by process name regardless of which session started it, so leftover servers from prior runs get cleaned up too — verify with `pgrep -af ex-sbom` afterward (expect no output).

## Interpretation caveat (always surface this)

SBOMTool can report Python versions from broad lower-bound `requirements.txt` entries rather than resolved `uv.lock` versions. A 2026-06-30 run showed `cryptography 42.0.0`, `pydantic 2.0.0`, `pymongo 4.0.0`, `python-multipart 0.0.12`, `pytest 8.0.0` in the SPDX/PDF while `uv.lock` had newer resolved versions. For real remediation priority, also produce a lockfile-based OSV summary from `uv.lock` and `frontend/pnpm-lock.yaml` (or the project's equivalent lockfiles).

## Common mistakes

- Scanning the live worktree directly → slow, picks up junk. Use the temp copy.
- Forgetting `DOTNET_BUNDLE_EXTRACT_BASE_DIR` in sandbox → SBOMTool won't start.
- Treating `ex-sbom` as a CLI → it's a server; you must POST then GET.
- Leaving the ex-sbom server running or dropping a PDF inside a repo — use `pkill -f ex-sbom`, not `kill %1` (job numbers don't carry across sessions).
- Trusting reported versions as resolved versions — cross-check the lockfile.
