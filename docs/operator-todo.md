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
- [x] AUTO: question waiting on operator — "Live ~/.claude/settings.json still wires the retired hook workstreams-state-gate.sh (2 references). Upstream commit d805a9a deleted that file, so those chain entries now point at nothing and harness-doctor reports RED wiring-resolves + RED template-live-drift. The committed template (adapters/claude-code/settings.json.template) is already correct — 0 references. Fix is a machine-local config edit to ~/.claude/settings.json, which needs /grant-local-edit authorization from you before I can touch it." (needs-you `NY-1785210417-d58a`, tier untiered, session `unknown`) — see NEEDS-YOU.md
- [x] AUTO: question waiting on operator — "Three harness scripts are committed with git mode 100644 (non-executable): adapters/claude-code/hooks/session-start-digest.sh, adapters/claude-code/scripts/session-resumer.sh, adapters/claude-code/scripts/needs-you.sh. On this Mac ~/.claude/{hooks,scripts} are SYMLINKS into the repo, so the repo's mode IS the live mode and harness-doctor reports 3 REDs. Windows checkouts do not surface this. Fix is git update-index --chmod=+x on the three paths plus a commit — say the word and I will do it." (needs-you `NY-1785210418-90c8`, tier untiered, session `unknown`) — see NEEDS-YOU.md
- [x] AUTO: question waiting on operator — "test question for bash3.2 repro with enough context to pass lint https://example.com/x" (needs-you `NY-1785344266-7a69`, tier untiered, session `sess-repro`) — see NEEDS-YOU.md
- [x] AUTO: decision waiting on operator — "## [2026-07-05] Activate auto-resume daemon (E.7) — low urgency, one 2-min action" (needs-you `NY-1785345974-1388`, tier migrated_from_legacy_file, session `legacy-migration`) — see NEEDS-YOU.md
- [x] AUTO: decision waiting on operator — "Decision needed: which review-independence model unblocks master for branch wip/harness-hardening-2026-07-29." (needs-you `NY-1785357818-7d3f`, tier untiered, session `a3fcb6ea`) — see NEEDS-YOU.md
- [x] AUTO: decision waiting on operator — "Pick a database" (needs-you `NY-1785366310-867a`, tier untiered, session `unknown`) — see NEEDS-YOU.md
- [x] AUTO: decision waiting on operator — "### Decision needed: which storage backend does the fx-active migration (docs/plans/fx-active.md) write to first." (needs-you `NY-1785366327-adde`, tier untiered, session `unknown`) — see NEEDS-YOU.md
- [x] AUTO: decision waiting on operator — "Decision needed: how to process the 123-file review backlog once the review-independence pipeline lands (building now, plan review-independence RI1-RI4)." (needs-you `NY-1785369704-ecbf`, tier untiered, session `a3fcb6ea`) — see NEEDS-YOU.md
- [x] AUTO: decision waiting on operator — "Decision needed: how to process the 123-file review backlog once the review-independence pipeline lands (building now, plan review-independence RI1-RI4)." (needs-you `NY-1785390332-316c`, tier untiered, session `unknown`) — see NEEDS-YOU.md
- [x] AUTO: decision waiting on operator — "### Decision needed: false-positive probe — does a bogus task reference fabricate a correlation (docs/plans/fx-active.md)." (needs-you `NY-1785390341-e54e`, tier untiered, session `unknown`) — see NEEDS-YOU.md
- [x] AUTO: decision waiting on operator — "Action needed: register the coordination publisher on the Windows desktop (one command, one time)." (needs-you `NY-1785394095-d8ec`, tier untiered, session `a3fcb6ea`) — see NEEDS-YOU.md
- [x] AUTO: decision waiting on operator — "Action needed: register the coordination publisher on the Windows desktop (supersedes retracted NY-1785394095-d8ec; corrected after a wrong diagnosis)." (needs-you `NY-1785425479-0d4d`, tier untiered, session `a3fcb6ea`) — see NEEDS-YOU.md
<!-- AUTO:END -->
