# Operator To-Do

Operator-authored items live in "## Operator items" below and are never
touched by automation. Auto-added pointer items (mirroring a decision or
question just appended to NEEDS-YOU.md) live between the AUTO markers and
are mechanically appended by
`adapters/claude-code/scripts/needs-you.sh` (the `add` splice,
ask-rooted-workstreams-p1 Task 4) — never hand-edit inside the markers;
re-appending only ever ADDS a line, never rewrites one. A pointer's
resolved/checked state is DERIVED (a later auditor pass, plan Task 12)
from the underlying NEEDS-YOU ledger, not tracked here — entries in this
file are an append-only log, not removed when the ledger item resolves.

## Operator items

_(add your own free-form to-do items in this section — never overwritten)_

<!-- AUTO:START -->
- [x] AUTO: question waiting on operator — "Register the NL-CoordSync scheduled task (4th installer, joins the 3 already on your to-do). WHAT: the cross-machine peer view just deployed to :7733 stays honestly empty until each machine publishes on the 600s cadence. DO (once, ~10s, from the main checkout on master): powershell -NoProfile -File adapters\claude-code\scripts\install-coord-sync-task.ps1 -RepoPath "C:\Users\misha\dev\Pocket Technician\neural-lace" — then the same on Jaime's machine. WHY YOURS: Task Scheduler mutation is permission-blocked for agent sessions." (needs-you `NY-1784327382-f3e8`, tier 3, session `unknown`) — see NEEDS-YOU.md
<!-- AUTO:END -->
