# Evidence + rung-3 articulation — cockpit-roadmap-redesign Task 4

Task: 4. Inbox view + context contract enforcement (Verification: full, rung 3)
Builder: plan-phase-builder (sonnet), commit 589d9d4 (build/roadmap-t4, 16 files) → master
62bb460; fragments (server.js mount + index.html tag) orchestrator-spliced next commit with
exact anchors. DEPLOYED LIVE: /api/inbox 200; #inbox renders "Awaiting your answer (3)"
with real ledger items (first surfaced item = NY-1783427528-ea50, the exact invisible-open-
decision defect from the 2026-07-19 doctor diagnosis). Composed at landing: inbox-routes
23/0, cockpit 242/0, server 173/0, needs-you 45/0. Gates: pending (opus pair in flight).

## Builder-reported evidence (gates re-derive)
- Suites: needs-you 45/0 · inbox-routes 23/0 · auditor 44/0 (9 new quarantine S9a-i + S10
  title-fold parity) · server 168/0 · cockpit 214/0 in-worktree · honesty-gate 40/0 ·
  resumer 69/0 · stop-dispatcher 73/0.
- Livesmoke: real ledger fixture via --serve + curl: NY-clean answerable with full §3
  anatomy (title/options/my_pick/reply_channel); quarantined/legacy excluded with honest
  lint_reasons/defect_filed; resolved absent from both buckets. Real CLI: interactive add
  with anchorless text exits 1 BLOCKED teaching message, writes nothing; identical text
  --mechanical exits 0, lands quarantined with lint_warnings.

## Rung-3 articulation (builder-authored, condensed)
**Spec meaning:** context contract (inbox-routes.js:290-310) splits ledger into answerable
(open decision/question, lint_warnings empty) vs quarantined (open decision, lint_warnings
non-empty); inflight/decided excluded (:302). Lint promotion (needs-you.sh:576,603,608)
blocks interactive path on lint failure; --mechanical callers store-and-quarantine.
Auto-defect in the auditor's own cycle (auditor.js:976, hooked :1229), reusing filed-once/
recurrence state.
**Edge cases covered:** legacy no-producer quarantined item (keys/files against ledger id,
S9d); question items never quarantine (S2/S2c); absent ledger.json → TRUE-empty (S9);
corrupt ledger.json → ok:false never crash (S8); win state scoped to answerable; recurrence
escalation at 3 distinct ids (S9g-i); interactive block writes nothing (T24c).
**Edge cases NOT covered:** "blocks: <item>" always null — no roadmap-side signal
correlates a stalled item to a needs-you id (buildInboxItem, blocks_roadmap_id:null; filed
ROADMAP-WAITING-ON-YOU-SIGNAL-01); "open source session" always falls back to the copyable
resume command (Harness Health drill-in R3 not wired); reply-with parsing heuristic
best-effort, not rigid grammar.
**Assumptions:** "My items" build + standalone-pane retirement is task 8's bullet — not
built here per dispatch (filed INBOX-MY-ITEMS-RELOCATION-01; retirement micro-task
dispatched by orchestrator covering both). The requests.js comment-splice defect the
builder re-discovered independently was already fixed on master (dca80ed) before landing.

## Gate results
### task-verifier: pending (opus, in flight)
### comprehension-reviewer: pending (opus, in flight)
