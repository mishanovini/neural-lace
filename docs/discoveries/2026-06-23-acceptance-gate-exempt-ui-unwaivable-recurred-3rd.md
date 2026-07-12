---
title: Acceptance-gate exempt-on-UI unwaivable block — 3rd recurrence
date: 2026-06-23
type: process
status: superseded
resolution: gate retired to exit-0 shim (ADR 058 D5, d6c0176); successor work-integrity-gate is session-scoped with a waiver fall-through — the unwaivable-exempt-UI deadlock class is structurally gone. Marked 2026-07-12 per state audit.
auto_applied: false
originating_context: <product> UI-chrome PR session (work-org/<product> PR #600), rooted in the neural-lace main checkout; the product-acceptance-gate Stop hook blocked clean session-end on a plan the session never touched.
decision_needed: Build the structural fix the 2026-06-10 discovery already proposed — make the exempt-on-UI mechanical refusal waivable AND/OR add a harness-internal-GUI exemption class — so cross-repo sessions and harness-internal GUI plans stop being unwaivably blocked at every Stop.
predicted_downstream:
  - adapters/claude-code/hooks/product-acceptance-gate.sh
  - adapters/claude-code/rules/acceptance-scenarios.md
  - docs/discoveries/2026-06-10-product-acceptance-gate-waiver-unreachable-for-exempt-ui-plans.md
  - docs/discoveries/2026-06-17-cross-repo-orchestration-gate-misfire.md
---

## What was discovered

This is the **third observed recurrence** (2026-06-10, 2026-06-17, now 2026-06-23) of the same `product-acceptance-gate.sh` misfire — surfaced this time in a real-customer-adjacent context.

A session whose **only** deliverable was a <product>-repo UI-chrome PR ([work-org/<product>#600](https://github.com/work-org/<product>/pull/600)) — making **zero** edits to neural-lace — could not cleanly end because the neural-lace product-acceptance Stop gate blocked on a plan in a *different* worktree:

- **Blocking plan:** `workstreams-ui-server/docs/plans/workstreams-completed-filter-fix-2026-06-17.md` (`Status: ACTIVE`).
- It is `acceptance-exempt: true` with a substantive, *correct* reason ("Workstreams GUI filter fix; state self-tests + a new filter/status-precedence unit test are the acceptance artifact (no product user; the GUI's user is the operator and the local self-tests are the maintainer-observable check)").
- But it declares two paths matching the UI regex (`neural-lace/workstreams-ui/web/app.js`, `.../state/filter-status.selftest.js`). The 2026-06-09 rule in `acceptance-scenarios.md` therefore **mechanically refuses** the exemption ("MECHANICALLY REFUSED on user-facing surfaces"), and per the 2026-06-10 discovery that refusal is **unwaivable** — a per-session acceptance waiver cannot clear it.

Net effect: every neural-lace-rooted session — including ones doing entirely unrelated cross-repo work — inherits an unclearable Stop block until someone triages that one foreign-worktree plan. The retry-guard's 3-retry downgrade is the only escape, which (a) pollutes `unresolved-stop-hooks.log` and (b) pressures the operator toward the very waiver/attestation bypass anti-pattern flagged in the 2026-06-17 discovery.

## Why it matters

1. **It fires on real-customer-adjacent sessions.** This recurrence happened while shipping a real-customer-facing <product> change — exactly when a clean, low-friction wrap matters most.
2. **The blocked plan is correctly self-describing.** Its exempt-reason is right: `workstreams-ui/` is a *harness-internal maintainer GUI*, not a customer product. The 2026-06-09 rule was authored to stop a *customer-facing* product UI from switching off acceptance (originating incident: a Workstreams **product** consolidation that shipped a broken modal as "verified"). It over-matches by treating any `-ui/` / `/web/` path as customer-facing, conflating "harness-internal operator GUI" with "customer product UI."
3. **It is unwaivable by design**, so a session that has *correctly* diagnosed the misfire still has no in-band, non-anti-pattern way to proceed. That is the structural trap the 2026-06-10 discovery named and that remains unbuilt.
4. **Recurrence count is now 3.** The two prior discoveries each proposed fixes; none shipped. The recurrence rate is the signal to prioritize.

## Options

- **A — Make the exempt-on-UI refusal waivable.** Re-order `product-acceptance-gate.sh` so a fresh substantive per-session waiver is honored *before* the exempt-on-UI mechanical refusal short-<product>s. (This is the 2026-06-10 discovery's core proposal.) Restores an honest, audit-logged in-band escape for the cross-repo / foreign-plan case.
- **B — Distinguish harness-internal GUI from customer-facing product UI (root cause).** The UI regex should fire only for product-repo customer surfaces (`src/app/`, `src/components/`, `page.tsx`, `*-ui/` *in a product repo*), and explicitly EXCLUDE harness-internal GUIs (`neural-lace/workstreams-ui/`, `conversation-tree-ui/`) whose user is the maintainer and whose acceptance artifact is a `--self-test`. A plan like the blocking one is then *legitimately* exempt and never refused.
- **C — Catch it at creation, not at every downstream Stop.** Have `plan-reviewer.sh` reject an `acceptance-exempt: true` plan that declares UI paths *at plan-creation time* (where the author can fix it), instead of letting it silently become an unwaivable Stop block for unrelated future sessions across the repo.
- **D — Status quo (per-session triage).** Accept that every cross-repo session pays a block until a human triages the offending foreign plan. (This is what's happening; it costs real friction and pushes toward the bypass anti-pattern.)

## Recommendation

**B as the root-cause fix, composed with A as the safety valve, and C as the upstream catch.** B removes the false-positive entirely for harness-internal GUIs (the largest source of these blocks, since the Workstreams/conversation-tree GUIs are actively developed). A guarantees an honest escape for any residual case. C moves the failure to plan-creation time where the author has context to fix it, instead of stranding it for unrelated downstream sessions. All three are reversible harness-dev changes; none touch product code.

This is explicitly NOT a "write a waiver" recommendation — the prior sessions' waiver-writing was the anti-pattern the 2026-06-17 discovery flagged, and here it is additionally *mechanically futile*.

## Decision

Pending — surfaced to Misha 2026-06-23, who asked that this Stop-gate misfire be reported through Neural Lace's lessons-learned channel. This discovery is that report; it supersedes nothing but adds the third concrete recurrence datapoint to the 2026-06-10 + 2026-06-17 discoveries.

## Implementation log

(empty — no fix built yet; this is a report, not a change.)
