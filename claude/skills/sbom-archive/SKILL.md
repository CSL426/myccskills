---
name: sbom-archive
description: Use when the user asks to archive, file, or move a generated SBOM report (.spdx.json / .pdf pair, typically produced by the sbom-report skill) into the ~/sbom-archive repo. Triggered by phrases like "歸檔這份 SBOM"/"把這份報告放到 sbom-archive"/"存到 archive", naming which project/subsystem it belongs to. This is a deliberate, user-triggered filing step — never run automatically right after sbom-report finishes; the user reviews the report first and decides where (or whether) to file it.
---

# SBOM Archive Filing

## Overview

Moves an already-generated SBOM report pair (`*.spdx.json` + `*.pdf`) into the dated archive structure at `~/sbom-archive`. This is a separate, manual step from generating the report — the user inspects the report first, then tells you which project/subsystem to file it under.

## Archive layout

```
~/sbom-archive/<project>/<subsystem>/<YYYY-MM-DD>/<subsystem-name>.spdx.json
~/sbom-archive/<project>/<subsystem>/<YYYY-MM-DD>/<subsystem-name>.pdf
```

- One dated folder per run — never overwrite a prior snapshot. If a report for the same subsystem+date already exists, ask the user whether to replace it or use today's actual date again (multiple runs same day are fine, just confirm intent).
- File basenames drop the `-current-<timestamp>` suffix and the `_report_<timestamp>` suffix that `sbom-report` produces — rename to just `<subsystem-name>.spdx.json` / `<subsystem-name>.pdf`.
- Date folder uses the date the report was generated (from the source filename's timestamp, or today if unclear), formatted `YYYY-MM-DD`.

Known projects/subsystems so far (extend as new ones come up — always confirm with the user if the mapping is unclear or the project is new):

| Project | Subsystem dir | Example source filename prefix |
|---|---|---|
| `hciot` | `後台` | `jtai-rag-current-*` |
| `hciot` | `手機前端` | `jtai-phone-fe-current-*` |
| `hciot` | `後端` | `jtai-hciot-backend-current-*` |
| `hciot` | `kiosk前端` | `jtai-frontend-current-*` |

## Steps

1. Identify the source `.spdx.json` and its paired `.pdf` (same basename prefix, different extension/suffix). If the user only names one, find its pair in the same directory.
2. Confirm target project + subsystem — from what the user said, or by asking if ambiguous. Do not guess silently for a subsystem not in the table above.
3. Create the dated target dir: `mkdir -p ~/sbom-archive/<project>/<subsystem>/<date>`
4. Move (not copy) the files there, renamed to drop timestamps:
   ```bash
   mv "<src>.spdx.json" ~/sbom-archive/<project>/<subsystem>/<date>/<subsystem-name>.spdx.json
   mv "<src>....pdf"    ~/sbom-archive/<project>/<subsystem>/<date>/<subsystem-name>.pdf
   ```
5. Commit the filed files in `~/sbom-archive`:
   ```bash
   cd ~/sbom-archive
   git add <project>/<subsystem>/<date>/
   git commit -m "chore: archive <project> <subsystem> SBOM report (<date>)"
   ```
   Do **not** `git push` — pushing is a separate approval the user must give explicitly, even though committing locally is now part of this flow.
6. Report the final paths and the commit result. If `~/sbom-archive/README.md`'s subsystem table doesn't yet list this project/subsystem, mention that to the user and offer to update it — don't edit it silently.

## Common mistakes

- Auto-filing right after `sbom-report` finishes without the user reviewing the report first — always wait to be asked.
- Copying instead of moving, leaving stale duplicates in the original output location (`.worktrees/` etc).
- Keeping the `-current-<timestamp>` / `_report_<timestamp>` suffixes in the archived filename.
- Guessing an unlisted subsystem mapping instead of asking.
