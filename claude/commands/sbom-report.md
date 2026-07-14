---
description: Generate an SPDX SBOM and PDF dependency vulnerability report for a project
---

Invoke the `sbom-report` skill via the Skill tool to generate a software bill of materials (SPDX) and render a PDF dependency vulnerability report.

Arguments (optional): $ARGUMENTS — the project root or name to scan (e.g. a worktree path). If omitted, infer the target project from the current context and confirm only if ambiguous.

Follow the skill's steps: prepare a clean temp source copy, generate SPDX with SBOMTool, render the PDF with the ex-sbom server, then stop the server and report the artifact paths plus the lockfile-version caveat.
