# Evidence — ws-ui-residuals-2026-06-10

Structured per-task artifacts live in `ws-ui-residuals-2026-06-10-evidence/*.evidence.json`
(mechanical level, captured via `write-evidence.sh capture`). This file carries the runtime
outputs the structured artifacts reference, for audit.

## Task 2 — selftest

`node neural-lace/workstreams-ui/state/selftest.js` → **20 passed, 0 failed** (19 pre-existing
properties + new P19 text-repair property). Sibling suites also green after the change:
reconciler.selftest 33/33, work-in-motion-sweep.selftest 37/37, responsive.selftest 27/27.

## Task 3 — correction emission (canonical state, coordination repo)

Pre-emission safety dry-run: audit-log re-derivation hash vs cached snapshot hash —
**byte-identical** (sha256 match, 2698 audit events, 1322 nodes), attestation verified. The
post-compaction re-fold in appendEvent is therefore lossless.

10 `item-text-set` events emitted through `state.js appendEvent` (actor=dispatch, deterministic
event_ids `fix-fffd-<item_id>-2026-06-10`, idempotent on re-run). Every correction replaced
U+FFFD with an em-dash; the cls-s8 item additionally had two ` ? `-mangled arrows restored to
` → ` (original phrasing confirmed in the launch-sprint source doc, line 330: "SHIPPED in
PR #378 →"). Items corrected: cls-s1, cls-s2, cls-s3, cls-s4, cls-s5, cls-coord-cody,
cls-coord-jaime, cls-coord-misha, cls-tier2-contact-delete, cls-s8-support-chatbot.
**Nothing left uncorrected** — all 10 reconstructions were context-confident.

Post-emission verification: whole-file U+FFFD count **0** (was 10); `verifySnapshotAttested`
→ **verified: true**; audit log now 2708 events with all 10 corrections durably present.

## Task 4 — filter partition (live counts)

Old behavior: awaiting-me 209 = in-flight 209 (non-discriminating).
New behavior on live data: **awaiting-me 34 / in-flight 175**, overlap 0, 34+175 = 209 open
items (exact partition; blocked/deferred/responded sets are empty today).

## Task 5 — advocate-style browser check

Real headless Chrome (puppeteer-core + system Chrome) against the worktree server (port 7799)
reading the live canonical state. 6/6 PASS:

- S2 chips differ — awaiting-me=34, in-flight=175, blocked=0, all=210
- S2 awaiting-me = 34 (strict Misha-ask subset)
- S2 in-flight = 175 (work-in-motion complement)
- S1 corrected em-dash text renders (all three COORD rows, 210 rows total)
- S1 zero U+FFFD in rendered page
- S3 zero console errors on load + filter interaction

DOM evidence (COORD rows, rendered text): "COORD — Cody: provide real contact export file…",
"COORD — Jaime: ship 22-contradiction guardrails…", "COORD — Misha: review CallRail scope…"
(em-dashes render; names quoted here are tracker data rendered at runtime, not harness code).
Acceptance PASS artifact: `.claude/state/acceptance/ws-ui-residuals-2026-06-10/` keyed to the
plan commit SHA.
