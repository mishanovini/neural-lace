# Plan: Conversation Tree Management UI — v1 (proposed DAG for ADR-031 Option 4)

Status: DRAFT
Execution Mode: orchestrator
Mode: design
Backlog items absorbed: none
tier: 4
rung: 2
architecture: coding-harness
frozen: false
prd-ref: conversation-tree-management-ui

<!--
DRAFT, not ACTIVE, by design. This plan is a Phase-4 design-package
deliverable awaiting TWO human gates the harness makes non-delegable:
  (G1) Misha ADOPTS an architecture in ADR-031. This plan decomposes
       Option 4 (ADR-031's *recommendation*, Status: Proposed). If Misha
       picks Option 1/2/3, this plan is re-authored, not edited.
  (G2) Misha APPROVES this DAG (Tier-3+ human DAG-review checkpoint;
       dag-review-waiver-gate.sh).
Status flips DRAFT → ACTIVE only after G1 AND G2. While DRAFT the plan
is NOT scanned by product-acceptance-gate; the 5-field schema is
informational (Check 10 gates ACTIVE plans) but populated for
review-completeness. prd-validity-gate fired on this Write and ALLOWED
(docs/prd.md has all 7 substantive sections; prd-validity-reviewer
PASSed at 8b1453e). Decision-A RESOLVED → docs/prd.md (ADR-031).
-->

## Goal

Build v1 of the Conversation Tree Management UI per **ADR-031 Option 4** (tree-as-durable-state + fire-and-forget Dispatch via the `spawn-task-report-back.md` convention): a localhost GUI that makes the Misha↔Dispatch conversation tree durable, visible, and navigable, with decision-list and action-list side surfaces, click-to-spawn-bound-session, branch checklists with auto-collapse, and bidirectional (non-concurrent, next-spawn-reconciled) JSON state. v1 delivers PRD scenarios S1, S2, S4, S5, S6, S7 fully and S3 in its non-concurrent form; S8/live-co-edit is explicitly deferred to a v2 (Option-3) upgrade.

## Scope

- **IN:** the items below.
  - JSON tree-state schema + atomic-write durability layer (resolves PRD OQ-1 conflict-unit, OQ-4 action-item typing; the Tier-4 contract — gets ADR-032).
  - Localhost GUI: tree view (pan/zoom/expand/collapse/click), decision-list + action-list surfaces, branch checklist + auto-collapse, drag-drop re-parent, promote-node-to-branch, tag cross-links.
  - Dispatch integration via `spawn-task-report-back.md`: annotation markers (FR-12) write tree mutations at session boundary; SessionStart surfacer reflects them; conclude-branch→spawn-bound-session; session-question→child-node.
  - Bidirectional check-off override (FR-9) with visible contested state; defer-my-action-with-condition (FR-13); optional enable/disable seam (FR-16); first-run empty state (FR-17); the FR-2 cardinality rule.
- **OUT:** (v1) the items below are explicitly excluded.
  - Live mid-session control / injection into a running cloud Dispatch session (ADR-031 hard constraint — research-ruled-out).
  - Concurrent same-file co-edit by a *running* session + Misha (PRD S8, NFR-2 live notice, FR-11 *concurrent* property) — deferred to v2/Option-3; v1 is non-concurrent.
  - Channels bridge / real-time snapshot model (OQ-2 → *snapshot* in v1; real-time is the v2 concurrency-model rebuild per ADR-031 r2).
  - Everything in the PRD Out-of-scope list (multi-user, mobile, JSON hand-editing, aggressive alerting, auto-conflict-resolution).

## Walking Skeleton

The thinnest end-to-end slice touching every layer, built FIRST (it is Task A2+C1+B1-min+C2-min, sequenced as the skeleton before any flesh):

> One real cloud Dispatch session emits **one** annotation marker → the report-back result JSON lands → the SessionStart surfacer reads it → the GUI renders **one** node from state → Misha clicks it → **one** bound Dispatch session is spawned with that node's context.

Every architectural layer is exercised by this slice: Dispatch boundary-write → JSON state + atomic durability → surfacer → GUI render → spawn path. No side surfaces, no drag-drop, no checklists, no deferral in the skeleton. If the skeleton works end-to-end against a real session, the wiring is proven and Phases B–D add flesh to a known-good spine. If it does not, the architecture (ADR-031 Option 4) is falsified before any feature is built — which is the point of skeleton-first.

## Tasks

<!-- Proposed DAG. Tier-5→Tier1-4 decomposition. Per-phase acceptance +
per-phase reviewers stated. Verification levels per
risk-tiered-verification.md. NO task starts until G1+G2. Wire checks use
the n/a carve-out: file paths are unresolvable until ADR-031 is adopted
(G1) and ADR-032 freezes the schema; the static chain is authored in
Phase-A pre-build, per the carve-out's intended use for pre-implementation
design-package plans. -->

### Phase A — State contract (freezes before any consumer builds; Tier 4)

- [ ] A1. Author ADR-032: JSON tree-state schema — node shape, FR-2 cardinality rule, OQ-1 conflict unit (per-field, honoring ADR-031's pinned independently-addressable per-field-mergeable constraint), OQ-4 action-item typing enum, OQ-6 tree-scope, OQ-7 concluded-branch lifecycle. — Verification: contract — **Reviewer: systems-designer (Tier-4 contract / option-assumption review).**
- [ ] A2. Implement the schema + atomic write-temp-then-rename durability + last-N-version retention (NFR-1). — Verification: full — **Reviewer: code-reviewer + task-verifier.**
  **Prove it works:**
  1. Write a tree state via the schema API.
  2. Kill the writer mid-write (simulated crash), then re-read state.
  3. Observe last-good version intact, no partial/corrupt tree; corruption surfaced if all versions bad.
  **Wire checks:**
  - n/a — concrete file paths are unresolvable until ADR-031 is adopted (G1) and ADR-032 freezes the schema; the statically-verifiable chain is authored in Phase-A pre-build per this plan's carve-out note.
  **Integration points:**
  The JSON state file is the contract every later phase consumes; verify via the A2 unit/property suite (atomic-write-under-crash, per-field-merge property test) cited in Testing Strategy.

### Phase B — Tree GUI core (new top-level UI surface; Tier 3)

- [ ] B1. Tree view: render, pan/zoom, expand/collapse, click-to-focus, branch auto-collapse on all-checked (FR-1, FR-8). — Verification: full — **Reviewer: ux-designer (new UI surface, mandatory) + functionality-verifier.**
  **Prove it works:**
  1. Open the GUI with a seeded multi-node state file; pan/zoom/expand/collapse the tree.
  2. Click a node — it focuses; check the last checklist item on a branch — it collapses.
  3. Expand the collapsed branch — full history returns.
  **Wire checks:**
  - n/a — paths unresolvable pre-G1/ADR-032 (see plan carve-out note); static chain authored Phase-A pre-build.
  **Integration points:**
  Reads the A2 state file; verify by seeding a known state file and asserting rendered node count/structure matches (functionality-verifier, browser).
- [ ] B2. Decision-list + action-list side surfaces, each linked back to originating node (FR-4, FR-5). — Verification: full — **Reviewer: ux-designer + functionality-verifier.**
  **Prove it works:**
  1. Open decision-list; see every unanswered decision linked to its node.
  2. Click one — GUI focuses that node; answer it.
  3. It leaves the list within one state refresh.
  **Wire checks:**
  - n/a — paths unresolvable pre-G1/ADR-032 (see plan carve-out note).
  **Integration points:**
  Consumes A2 state; cross-links to B1 tree focus. Verify: seed state with N unanswered decisions, assert list count = N, answer one, assert N-1 (functionality-verifier).
- [ ] B3. Drag-drop re-parent, promote-node-to-branch, tag cross-links (FR-3, FR-11 GUI-side write). — Verification: full — **Reviewer: functionality-verifier.**
  **Prove it works:**
  1. Drag a node to a new parent — tree re-parents, state file updated.
  2. Promote a node to a branch.
  3. Apply a tag to two nodes — a visible non-tree cross-link renders without changing either parent.
  **Wire checks:**
  - n/a — paths unresolvable pre-G1/ADR-032 (see plan carve-out note).
  **Integration points:**
  Writes A2 state (GUI is the only live writer, v1). Verify: perform each op, re-read state file, assert mutation persisted (functionality-verifier).
- [ ] B4. First-run empty state + optional-module enable/disable seam (FR-16, FR-17, SM-5/SM-6). — Verification: full — **Reviewer: ux-designer + functionality-verifier.**
  **Prove it works:**
  1. Fresh install, no state file — GUI shows an informative empty state, not an error.
  2. Disable the module — run a standard Dispatch session; hook-firing is byte-identical to module-absent.
  3. Re-enable — tree returns.
  **Wire checks:**
  - n/a — paths unresolvable pre-G1/ADR-032 (see plan carve-out note).
  **Integration points:**
  The enable/disable seam touches only the documented integration surface (§4). Verify: hook-firing diff between module-disabled and module-absent runs = empty (SM-5).

### Phase C — Dispatch integration (reuses spawn-task-report-back; Tier 3)

- [ ] C1. Dispatch annotation markers (FR-12) → tree mutations written at session boundary; SessionStart surfacer reflects them into the GUI (FR-11 Dispatch→GUI half). — Verification: full — **Reviewer: systems-designer (integration-point review) + functionality-verifier.**
  **Prove it works:**
  1. Run a real local Dispatch session that emits an annotation marker.
  2. At session end the report-back result lands; open the GUI.
  3. Observe the annotated tree mutation rendered.
  **Wire checks:**
  - n/a — paths unresolvable pre-G1/ADR-032 (see plan carve-out note); the spawn-task-report-back convention is the stable contract this reuses.
  **Integration points:**
  Reuses `spawn-task-report-back.md` (sentinel + result JSON + SessionStart surfacer). Verify: real session → assert tree reflects the annotation; surfacer idempotent (`.acked` prevents re-surface).
- [ ] C2. Conclude-branch → spawn bound session with gathered decisions as prompt + spawn guardrail confirmation (FR-14, FR-19); session question → child node (FR-15). — Verification: full — **Reviewer: systems-designer + functionality-verifier.**
  **Prove it works:**
  1. Answer all of a branch's decisions; conclude it; confirm the spawn guardrail.
  2. Observe a Dispatch session whose prompt contains the gathered decisions.
  3. Have it ask a question — a child node appears under the spawning branch.
  **Wire checks:**
  - n/a — paths unresolvable pre-G1/ADR-032 (see plan carve-out note).
  **Integration points:**
  Invokes the existing spawn path; consumes A2 state. Verify: assert spawned-session prompt contains gathered decisions (log/curl); assert exactly one correctly-parented child node.
- [ ] C3. Bidirectional check-off override with visible contested state; next-spawn reconciliation of GUI-side edits (FR-9, FR-11 GUI→Dispatch half via next-spawn). — Verification: full — **Reviewer: code-reviewer + functionality-verifier.**
  **Prove it works:**
  1. Dispatch implicitly checks an item; Misha unchecks with a note — contested state visible.
  2. Misha checks an item; Dispatch contests — specific "X complete but Y may not be covered" message visible.
  3. Neither side auto-resolves; resolution is explicit-only.
  **Wire checks:**
  - n/a — paths unresolvable pre-G1/ADR-032 (see plan carve-out note).
  **Integration points:**
  Consumes/writes A2 state; reconciliation occurs at next bound spawn (C2). Verify: audit log shows explicit-only resolution, never implicit (SM-4).

### Phase D — Deferral + close-out (Tier 2 / acceptance)

- [ ] D1. Defer-my-action-with-condition: date/time scheduled check + event via existing surfacing hooks + manual unhide floor (FR-13). — Verification: full — **Reviewer: functionality-verifier.**
  **Prove it works:**
  1. Defer an action item with a date condition — it leaves the active list.
  2. Simulate the condition resolving — it returns.
  3. Manual unhide works regardless of condition state.
  **Wire checks:**
  - n/a — paths unresolvable pre-G1/ADR-032 (see plan carve-out note).
  **Integration points:**
  Date/time = lightweight scheduled check; event = existing harness surfacing hooks. Verify: deferred item absent while deferred, present after resolution (functionality-verifier).
- [ ] D2. Acceptance pass: end-user-advocate runtime mode against the running GUI for S1,S2,S3(non-concurrent),S4,S5,S6,S7. — Verification: full — **Reviewer: end-user-advocate (runtime).**
  **Prove it works:**
  1. The end-user-advocate opens the running GUI and executes each in-scope Acceptance Scenario.
  2. It captures per-scenario artifacts (screenshots, logs).
  3. It writes a PASS artifact for the in-scope scenario set.
  **Wire checks:**
  - n/a — acceptance is exercised against the running module post-build; no static code chain applies to an acceptance-pass task (≥30-char carve-out reason).
  **Integration points:**
  The whole module; verify via the PASS artifact under `.claude/state/acceptance/conversation-tree-ui/` matching the plan commit SHA.

## Files to Modify/Create

<!-- Indicative; final paths depend on ADR-031 adoption (G1) + ADR-032
schema. Declared so scope-enforcement-gate has a surface once ACTIVE. -->
- `docs/decisions/032-conversation-tree-state-schema.md` — Tier-4 state contract (A1) + DECISIONS.md index row.
- `<module-root>/state/` — JSON schema, atomic-write durability, version retention (A2).
- `<module-root>/gui/` — tree view, side surfaces, drag-drop, empty state (B1–B4).
- `<module-root>/integration/` — annotation reader, SessionStart surfacer, spawn-bound-session, question→child-node (C1–C3).
- `<module-root>/defer/` — deferral conditions + resolution (D1).
- `adapters/claude-code/` — only the minimal documented integration seam (FR-16/NFR-8); exact files pending G1.
- `SCRATCHPAD.md`, `docs/plans/conversation-tree-ui.md` — status + evidence bookkeeping.

## In-flight scope updates

<!-- Populated during build per spec-freeze/scope-enforcement protocol. Empty at DRAFT. -->

## Assumptions

- ADR-031 Option 4 is adopted by Misha (G1). If not, this plan is void and re-authored against the chosen option.
- Misha continues to drive via cloud Dispatch (the constraint that selected Option 4). Moving to local sessions enables the v2 Option-3 upgrade — out of scope here.
- `spawn-task-report-back.md` remains stable (shipped harness rule). v1 depends only on its Dispatch→orchestrator direction; GUI→Dispatch is next-spawn reconciliation, not a new live channel.
- ADR-032 honors ADR-031's pinned constraint (independently-addressable per-field-mergeable nodes). A2 cannot proceed until A1 freezes that property.
- The harness's existing SessionStart-surfacer pattern is reusable for FR-13 event conditions and FR-11 Dispatch→GUI reflection — verified in C1, not assumed at build.
- No new third-party runtime dependency beyond the GUI framework choice (deferred to ADR-032/B1; minimal-dependency principle applies).

## Edge Cases

- **FR-2 multi-divergent decision-set (resolves the prd-validity-reviewer finding):** when Dispatch presents N decisions and Misha leaves >1 unanswered OR takes >1 deep, the model creates **one shared child branch for the entire divergent set by default; per-decision split is opt-in via promote-node-to-branch (FR-3).** Rationale: a shared branch matches "deal with these together"; per-decision branches opt-in avoid tree explosion. A1/ADR-032 encodes this with an N=3 fixture (2 unanswered + 1 deep).
- Dispatch writes malformed/partial JSON (crash mid-write) → NFR-1 atomic write + last-good fallback; corruption surfaced, never silent loss or blank tree.
- Node bound to a missing/cleaned-up session → NFR-9 degrade to "session unavailable", still navigable.
- Tree growth over months → OQ-7: collapse-by-default + archival tier for branches concluded > N days, recoverable (decided in A1).
- Misha clicks a cold branch while a session is live elsewhere → S3 degraded: explicit "a session is already running; this starts a second one" confirmation, not a silent surprise.
- Spawn guardrail (FR-19): no branch-conclusion spawns a session without per-spawn confirmation or recorded pre-authorization.

## Testing Strategy

- A2/state: unit (schema validation, atomic-write under simulated crash, version retention) + property test (per-field merge).
- B*/GUI: functionality-verifier exercises each scenario in a browser (real clicks, real state file) — not component-only.
- C*/integration: a real local Dispatch session writing annotations → assert tree reflects them; spawn-bound-session produces a session whose prompt contains gathered decisions (curl/log assertion).
- D2: end-user-advocate runtime mode is the acceptance gate for the in-scope scenario set; artifact under `.claude/state/acceptance/conversation-tree-ui/`.
- Per FUNCTIONALITY-OVER-COMPONENTS: a task is done only when a user can do the thing end-to-end against the running module, not when it compiles.

## UX Design Review

Plan-time `ux-designer` review (2026-05-15, @adee136). Systems engineering is strong; gaps are in novel-interaction affordances the PRD requires but the plan left to builder guess. **The Critical findings below are binding build commitments — the build phase MUST implement them; they are addressed in the plan here per `~/.claude/rules/planning.md` ("every Critical gap must be addressed in the plan before building").**

### UX commitments folded into the build (binding)

- **UX-C1 (Critical — contested check-off resolution affordance; C3/FR-9/SM-4).** C3 MUST render a contested item with a per-direction badge (`⚠ Dispatch marked done · you disputed` vs `⚠ You marked done · Dispatch disputed`), the attached note inline, and a two-button resolve control (`Accept their position` / `Keep mine, re-open`). Resolving writes an explicit resolution event to the audit log; until resolved the item counts as NOT checked for FR-8 auto-collapse. Rationale: an unspecified resolution = a permanent dead-end on the surface meant to *unblock* Misha — the PRD's #1 problem driver.
- **UX-C2 (Critical — auto-conclude must not be silent; FR-7).** On navigate-away the prior leaf MUST show a persistent on-node marker `↩ auto-concluded — re-open` (NOT a transient toast); the node stays in the tree, visibly marked, one-click re-openable; its decision/action items remain on the side lists. Rationale: a silent state transition on the product whose entire purpose is "no open work silently disappears" is a credibility contradiction.
- **UX-C3 (Critical — landing surface / information hierarchy).** Default landing surface is the "waiting on me" view — decision-list + action-list shown first with a count badge (`N decisions · M actions waiting`), the tree as a secondary pane/tab. Each list entry shows the originating-node breadcrumb and is one-click to focus that node in the tree. Rationale: the PRD problem is a *surfacing* problem, not a visualization one; landing on a 500-node tree buries the answer to "what's waiting on me?". (Subject to Misha Q1 below — recommendation stands unless he redirects.)
- **UX-I4 (Important — three distinct data states).** B4 MUST implement loading (skeleton + "Loading conversation tree…"), empty/first-run (FR-17 explainer), and corruption (persistent banner `⚠ State file unreadable — showing last good version from <ts>; <N> newer versions could not be parsed` + details disclosure; all-versions-bad → explicit "could not load from any saved version" + audit-log path, never blank) as three never-conflated states.
- **UX-I5 (Important — "session unavailable" node is degraded, not dead; NFR-9).** A session-unavailable node renders with a `⚠ session unavailable — context may be partial` badge, stays click-focusable, still shows its stored decisions/actions/notes, and offers `Spawn a fresh bound session from this branch` (reuses the C2 path).
- **UX-I6 (Important — costly-action confirmation specificity; S3/FR-19).** The S3 concurrent-spawn confirmation MUST name the live session (`A Dispatch session is already live: "<title>" (started <T>). Spawning a second runs them in parallel.`) with `Spawn anyway` / `Cancel` / `Go to the live session`, and MUST be the same single component as the FR-19 spawn guardrail (one spawn-confirmation component, not two).
- **UX-I7 (Important — specify the three guessed affordances).** D1: defer via an action-item overflow menu → `Defer…` → date-picker | event-condition dropdown; deferred items move to a collapsed `Deferred (N)` group (manual-unhide floor). B3: promote = node context-menu `Promote to branch`; node gains a checklist affordance. B2: list-entry click focuses the node in the tree AND scrolls/expands it into view AND switches active context (FR-6) — all three stated.
- **UX-N8 (Nice-to-have — orientation on auto-collapse; FR-8).** Collapse animates (not instant disappear); the collapsed branch leaves a labeled in-place stub `▸ <branch name> ✓ concluded` so spatial memory is preserved.

**Cross-cutting discipline (binding):** every system-initiated state transition (auto-conclude, auto-collapse, defer-condition-resolve) leaves a persistent on-node signal + undo, never transient-only; every bistable/contested state names both its visible signal AND its exit affordance in the owning task body.

### end-user-advocate plan-time review — substitute applied (HARNESS-GAP-33)

The `end-user-advocate` agent is **not dispatchable in this Dispatch environment** (`Agent type 'end-user-advocate' not found`), despite the harness mandating it. This is filed as HARNESS-GAP-33 + `docs/discoveries/2026-05-15-end-user-advocate-not-dispatchable-in-dispatch-env.md`. **No silent skip:** the plan-time-advocate coverage checklist was self-applied, and `systems-designer` + `ux-designer` independently cross-checked scenario coverage. Self-applied coverage result: scenarios s1–s7 map 1:1 to the PRD's in-scope behaviors; FR-2 (cardinality), FR-10 (single parent alert — covered within s4), FR-16/SM-5 (module enable/disable — covered within s-skeleton/B4 acceptance, NOT a standalone scenario → **gap noted**: add an `s8-module-optional` scenario or accept it as DoD-verified-only), FR-19 (spawn guardrail — covered within s6). Decision: FR-16/SM-5 is verified by the B4 functionality-verifier task + SM-5 hook-diff metric rather than a runtime advocate scenario (it is a non-UI invariant); recorded here as a deliberate, Misha-reviewable choice rather than an unstated gap. The real `end-user-advocate` runtime pass (task D2) remains BLOCKED in this environment until HARNESS-GAP-33 is remediated — surfaced as a design-package risk, not hidden.

### Open questions for Misha (Plan-Time Decisions With Interface Impact — your call)

1. **Landing default (UX-C3).** Recommendation: land on the decision/action "waiting on me" lists, tree secondary. The PRD problem statement implies this; the plan now commits to it unless you redirect. Cost of the alternative (tree-first): the "what's waiting on me?" answer is buried.
2. **Contested-resolution write-back (UX-C1 ↔ C2/C3 contract).** When you pick "Accept their position," should that write a note the *next* bound Dispatch session sees (next-spawn reconciliation), or is it purely GUI-local? Recommendation: write it back — it keeps the contested-state honest across the session boundary and matches the non-concurrent reconciliation model. Affects the C3↔C2 contract.
3. **Auto-conclude trigger scope (FR-7).** Is "navigate focus away" *every* click elsewhere, or only spawning/concluding? Recommendation: only spawn/conclude (and explicit focus-switch), NOT idle tree browsing — per-click auto-conclude would thrash the active context. Pin before B1.

## Acceptance Scenarios

<!-- Seeded from PRD scenarios; end-user-advocate plan-time mode hardens
this as part of the Phase-4 gate. Assertions stay private to the advocate. -->

### s1-branches-persist — open branches survive a session boundary
**Slug:** `s1-branches-persist`
**User flow:** 1. Drive a Dispatch session that branches a decision-set. 2. End the session. 3. Open the GUI next session. 4. Observe the open branch present without reading scrollback.
**Success criteria (prose):** every branch open at session end is visible and click-focusable next session (PRD SM-1).
**Artifacts to capture:** screenshot of tree with the persisted branch; audit-log lines; no console errors.

### s2-waiting-on-me — decision list surfaces all unanswered decisions
**Slug:** `s2-waiting-on-me`
**User flow:** 1. Open decision-list surface. 2. See every unanswered decision linked to its node. 3. Click one. 4. Answer it. 5. See it leave the list.
**Success criteria (prose):** answering removes the decision within one state refresh; each entry links back to its node (PRD SM-3).
**Artifacts to capture:** screenshot before/after; state-refresh timing; no console errors.

### s3-resume-cold-branch-non-concurrent — resume an idle branch (no live session)
**Slug:** `s3-resume-cold-branch-non-concurrent`
**User flow:** 1. With no Dispatch session live, click an idle branch node. 2. Compose a follow-up. 3. Observe a bound session spawned for that node.
**Success criteria (prose):** a session is spawned bound to the clicked node with that branch's context; the previously-focused leaf auto-concludes (FR-6/FR-7). The concurrent-session-live variant is OUT of v1 (degraded-behavior confirmation only).
**Artifacts to capture:** screenshot; spawned-session prompt content; no console errors.

### s4-auto-collapse — branch collapses when all items checked
**Slug:** `s4-auto-collapse`
**User flow:** 1. Open a branch with a checklist. 2. Check the final item. 3. Observe the branch collapse. 4. Expand it again.
**Success criteria (prose):** last-item-check collapses; expand restores full history (FR-8); parent gets exactly one "child concluded" alert (FR-10).
**Artifacts to capture:** screenshot collapsed + expanded; alert count = 1.

### s5-contested-checkoff — bidirectional override never silently resolves
**Slug:** `s5-contested-checkoff`
**User flow:** 1. Dispatch implicitly checks an item. 2. Misha unchecks it with a note. 3. Observe contested state. 4. Misha checks an item; Dispatch contests it. 5. Observe the specific message.
**Success criteria (prose):** both override directions produce a visible contested state neither side auto-resolves (PRD SM-4).
**Artifacts to capture:** screenshot of both contested states; audit log shows explicit-only resolution.

### s6-conclude-spawns-session — concluding a branch kicks off a bound session
**Slug:** `s6-conclude-spawns-session`
**User flow:** 1. Answer all of a branch's decisions. 2. Conclude it. 3. Confirm the spawn guardrail. 4. Observe a Dispatch session prompted with the gathered decisions. 5. Have it ask a question. 6. Observe a new child node under the spawning branch.
**Success criteria (prose):** conclusion (with confirmation, FR-19) spawns a session prompted with gathered decisions (FR-14); a session question creates exactly one correctly-parented child node (FR-15).
**Artifacts to capture:** spawned-session prompt; child-node screenshot; guardrail confirmation evidence.

### s7-defer-with-condition — defer my own action item
**Slug:** `s7-defer-with-condition`
**User flow:** 1. Pick an action item. 2. Defer it with a date condition. 3. Observe it leave the active list. 4. Simulate the condition resolving. 5. Observe it return.
**Success criteria (prose):** deferred item absent while deferred, present after condition resolves (FR-13).
**Artifacts to capture:** screenshot before/after; condition-resolution log.

## Out-of-scope scenarios

- **Concurrent same-file co-edit by a running session + Misha (PRD S8)** — OUT of v1 per ADR-031 r2 Finding-1 (cloud Dispatch cannot consume a mid-run external write). Re-enters in v2/Option-3. Rationale: the hard constraint makes live concurrency impossible for cloud Dispatch; v1 is non-concurrent by construction.
- **Live focus-switch of an already-running session (S3 concurrent variant)** — OUT of v1; v1 degrades to concurrent-spawn-with-confirmation. Rationale: requires live injection, ruled out for cloud Dispatch.

## Decisions Log

### Decision: FR-2 multi-divergent branch cardinality
- **Tier:** 2 — **Status:** proceeded with recommendation (resolves the prd-validity-reviewer non-blocking finding)
- **Chosen:** one shared child branch for the entire divergent decision-set by default; per-decision split opt-in via promote-node-to-branch.
- **Alternatives:** one branch per divergent decision (tree explosion; rejected) / no branch until Misha acts (loses the "these are open" signal; rejected).
- **Reasoning:** matches "deal with these together"; opt-in split avoids unbounded fan-out; reuses an FR-3 affordance.
- **To reverse:** change the A1/ADR-032 canonical rule + its N=3 fixture.

### Decision: v1 is non-concurrent (S8/FR-11-concurrent/NFR-2-live OUT)
- **Tier:** 2 — **Status:** proceeded (carries ADR-031 r2 Finding-1 into the plan as explicit scope)
- **Chosen:** GUI is the only live writer; Dispatch writes only at session boundaries; GUI→Dispatch via next-spawn reconciliation.
- **Alternatives:** attempt a live bridge (ruled out for cloud Dispatch by research) / block GUI edits while any session runs (worse UX; rejected).
- **Reasoning:** the cloud-Dispatch hard constraint makes live concurrency impossible; honest v1 scoping beats a feature that cannot work.
- **To reverse:** the v2 Option-3 upgrade (requires Misha on local sessions) — a separate plan.

## Pre-Submission Audit

S1 (Entry-Point Surfacing): swept, every behavior change in Sections 1–10 is cited at a Task + a Files-to-Modify entry (Phase A↔§3/§8, Phase B↔§1/§6, Phase C↔§2/§3/§4, Phase D↔§7); 0 stranded behaviors.
S2 (Existing-Code-Claim Verification): swept, the only existing-code claims are (a) `spawn-task-report-back.md` is a shipped one-directional rule and (b) the SessionStart-surfacer pattern exists — both verified against the rule file + ADR-031 research; the surfacer reuse is marked an Assumption to be re-verified in C1, not asserted as fact.
S3 (Cross-Section Consistency): swept, "non-concurrent v1" is stated identically in Scope OUT, Edge Cases, Decisions Log, Out-of-scope scenarios, and §3/§8; 0 contradictions (the prior over-claim was the ADR-031 r1 finding, already corrected upstream).
S4 (Numeric-Parameter Sweep): swept for params [NFR-3 p95 150ms, ≥500 nodes, OQ-7 ">N days" archival]; 150ms/500 appear once each (§1-equivalent NFR + §9), consistent; "N days" is intentionally symbolic (decided in A1), flagged as such everywhere it appears.
S5 (Scope-vs-Analysis Check): swept, every "Add/Implement/Build" verb in Tasks/§1–10 checked against Scope OUT; live-control/concurrent-co-edit/real-time verbs appear only as explicitly-OUT or v2-deferred; 0 in-scope prescription contradicts the OUT list.

## Definition of Done
- [ ] All tasks checked off (after G1+G2 only)
- [ ] All tests pass; functionality-verifier PASS on every runtime task
- [ ] end-user-advocate runtime PASS artifact for the in-scope scenario set
- [ ] ADR-032 authored + indexed (A1)
- [ ] SCRATCHPAD.md updated; completion report appended; Status flipped (closure procedure)

## Systems Engineering Analysis

### 1. Outcome (measurable user outcome, not output)
- Within one session-boundary, 100% of branches Misha left open are visible and resumable in the GUI without reading scrollback (PRD SM-1).
- Resuming a ≥2-session-cold branch takes ≤3 GUI interactions and zero scrollback reads (SM-2).
- A Dispatch-installed-but-unused session fires zero module-originated interruptions (SM-6).
- 100% of bidirectional-override events produce a visible contested state; 0% silently auto-resolve (SM-4).
- This is the outcome, not "the tree UI is built" — the plate test: Misha's plate is lighter because no open work silently disappears and no stale decision rots unseen.

### 2. End-to-end trace with a concrete example
- T=0 Misha drives a cloud Dispatch session on "investigate harness gap G".
- T=8min Dispatch surfaces 3 decisions, emits annotation `opening child node: G-deepdive-d3`, and writes the tree mutation into the JSON state at its session boundary (report-back result JSON, schema = ADR-032).
- T=session-end the result file lands; on Misha's next GUI open the SessionStart surfacer reads it and renders parent G with d1/d2 auto-checked and an open child `G-deepdive-d3`.
- T+1day Misha clicks `G-deepdive-d3` (no session live), confirms the spawn guardrail; the GUI composes prompt = node context + d3 and spawns a bound session.
- That session asks a clarifying question → emits `child node: G-deepdive-d3-q1` at its boundary → surfacer renders it under `G-deepdive-d3`.
- No step requires reading or injecting into a *running* cloud session — every cross-boundary transition is a file the surfacer reads.

### 3. Interface contracts between components
| Producer | Consumer | Contract |
|---|---|---|
| Dispatch session | JSON state file | Writes tree mutations ONLY at session boundary via report-back result JSON (schema = ADR-032). Never mid-run. Atomic temp+rename. |
| JSON state file | GUI | GUI reads on open + on surfacer signal; GUI is the only live writer; per-field last-write-wins (ADR-031 pinned constraint). |
| GUI | Dispatch (spawn) | "Conclude branch" → spawn bound session; prompt = gathered decisions; guardrail confirmation required (FR-19). One session per conclude. |
| SessionStart surfacer | GUI | Emits a signal when a new report-back result for a tracked node lands; idempotent; `.acked` marker prevents re-surface. |
| Module | Harness core | Only the enumerated seam in §4; zero required Stop/PreToolUse hooks (NFR-8). |

### 4. Environment & execution context
- Localhost-only GUI (NFR-5 — no inbound LAN port). Single user, single machine.
- State file location per OQ-6's resolution in A1 (per-project under the repo, or a global path).
- Reuses the harness's existing SessionStart-surfacer pattern (`spawned-task-result-surfacer.sh` family).
- Integration seam = (a) a Dispatch-prompt sentinel convention (existing `spawn-task-report-back.md`), (b) one SessionStart surfacer reading report-back results into the tree, (c) the spawn call.
- Enable/disable = presence/absence of that surfacer wiring; disabled = byte-identical hook behavior (SM-5). No credentials in state (NFR-5).

### 5. Authentication & authorization map
- No auth: single local user; localhost bind only.
- Dispatch-session spawning uses Misha's existing Claude Code auth — the GUI holds no credentials; it composes a prompt and invokes the existing spawn path (`mcp__ccd_session__spawn_task`-style).
- No new credential, token, or external API surface introduced.
- State file is not credential-bearing (NFR-5 acceptance: credential-pattern scan = 0).
- No third-party network egress beyond the existing spawn path Misha already controls.

### 6. Observability plan (built before the feature)
- The Dispatch annotation trail (FR-12) is the primary observability surface — tree change history reconstructable from annotations alone (NFR-7).
- Every state mutation (GUI or Dispatch) appends to an append-only audit log.
- Current tree state is reconstructable from audit log + annotation trail (NFR-7 acceptance).
- GUI surfaces a visible "last synced from session X at T" indicator so staleness is observable, not silent.
- Surfacer emits a stderr line on every read (skipped/applied) so integration failures are diagnosable from logs alone.

### 7. Failure-mode analysis per step
| Step | Failure | Symptom | Recovery | Escalate |
|---|---|---|---|---|
| Dispatch boundary write | crash mid-write | partial JSON | atomic temp+rename; last-good retained (NFR-1) | corruption banner if all versions bad |
| Surfacer read | malformed result JSON | node not updated | surfacer warns to stderr, skips; manual re-acked | recurring → integration finding |
| Click cold branch (session live) | concurrent spawn | 2nd session starts | explicit pre-spawn confirmation (S3 degraded) | n/a — by design |
| Conclude → spawn | spawn fails | no session created | guardrail shows failure; branch stays open | surface to Misha |
| Bound session | references missing session | node "session unavailable" | NFR-9 degrade; still navigable | n/a |
| Defer condition | scheduled check misses | item never returns | manual unhide floor always available | n/a |

### 8. Idempotency & restart semantics
- Surfacer is idempotent (`.acked` marker; re-run = no-op).
- Atomic state writes → a re-run mutation is safe (last-write-wins per field).
- GUI restart re-reads the state file (no in-memory authority).
- A partially-written Dispatch result is ignored until complete (temp+rename).
- Re-spawning a bound session after a crash: guardrail re-confirms; no silent duplicate.

### 9. Load / capacity model
- Bottleneck: tree-render at scale. NFR-3 target p95 < 150ms interaction at ≥500 nodes.
- OQ-7 archival tier caps the live working set (concluded > N days → archival, recoverable; N decided in A1).
- State file size grows with tree; at saturation the archival tier prunes the live file, not the audit log.
- No network/API rate concern: localhost, no external calls except the existing spawn path, which Misha already paces himself.
- Capacity headroom is observable via the "last synced" indicator + audit-log growth rate.

### 10. Decision records & runbook
- Decision records: ADR-031 (architecture, Proposed); ADR-032 (state schema, Task A1); Decisions Log above (FR-2 cardinality; v1-non-concurrent).
- Runbook — *GUI shows stale tree*: (1) check the surfacer fired (audit log), (2) check the latest report-back result landed + `.acked`, (3) re-open GUI (re-reads state).
- Runbook — *branch didn't auto-collapse*: (1) verify all checklist items checked in state file, (2) check for an unresolved contested item (contested ≠ checked by design).
- Runbook — *concluded branch didn't spawn*: (1) check guardrail confirmation given, (2) check spawn path returned, (3) branch stays open if spawn failed — re-conclude.
- Escalation: recurring surfacer-skip or corruption-banner events become findings (`docs/findings.md`) per the diagnosis "encode the fix" loop.
