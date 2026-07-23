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
- [x] AUTO: question waiting on operator — "OPERATOR WALKTHROUGH — the last blocker before cockpit-roadmap-redesign closes. WHAT: open http://127.0.0.1:7733 (the redesigned cockpit is live) and do the cold-start walk, under 60 seconds: (1) on the Roadmap tab, answer 'what is the status of the cockpit redesign plan?' from its phase node; (2) read the Inbox (N) count for 'how many items wait on me?'; (3) expand any roadmap item's drill-down and follow a 'from your request(s)' link back to the Requests ledger; (4) confirm nothing reads stalled that you know is running. WHY YOURS: T9's task text names 'the operator's own cold-start walkthrough ON THE NEW SURFACE' — a human sign-off the advocate's 1.7s machine proxy cannot substitute (task-verifier verdict INCOMPLETE conf 9, 2026-07-23). WHAT HAPPENS ON YOUR REPLY: reply 'walkthrough done' (plus any friction you hit) in any session -> task-verifier re-invoked -> T9 flips -> /close-plan archives the redesign. Friction you report becomes backlog rows, not rework blockers." (needs-you `NY-1784807155-8b40`, tier untiered, session `unknown`) — see NEEDS-YOU.md
<!-- AUTO:END -->
