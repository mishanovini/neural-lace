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
deliverable awaiting TWO human gates that the harness's process makes
non-delegable:

  (G1) Misha ADOPTS an architecture in ADR-031. This plan decomposes
       Option 4 (ADR-031's *recommendation*, Status: Proposed). If Misha
       chooses Option 1/2/3 instead, this plan is re-authored, not edited.
  (G2) Misha APPROVES this DAG (the Tier-3+ human DAG-review checkpoint,
       Build Doctrine Phase 4 → Phase 5 gate; dag-review-waiver-gate.sh).

Status flips DRAFT → ACTIVE only after G1 AND G2. While DRAFT the plan is
NOT scanned by product-acceptance-gate and the 5-field schema is
informational (Check 10 gates ACTIVE plans). The schema fields are
populated anyway so the plan is review-complete:
  tier:4 — the JSON tree-state is a cross-component contract (Tier-4
           trigger: state-schema change anyone depends on).
  rung:2 — selective-PR autonomy; comprehension gate applies at build.
  architecture:coding-harness — built via the orchestrator pattern.
  frozen:false — spec not frozen until G1+G2 (spec-freeze-gate respected).
  prd-ref — resolves to docs/prd.md (Decision-A RESOLVED, ADR-031).

prd-validity-gate fires on this Write and should ALLOW (docs/prd.md has
all 7 substantive sections; prd-validity-reviewer PASSed at 8b1453e).
-->

## Goal

Build v1 of the Conversation Tree Management UI per **ADR-031 Option 4** (tree-as-durable-state + fire-and-forget Dispatch via the `spawn-task-report-back.md` convention): a localhost GUI that makes the Misha↔Dispatch conversation tree durable, visible, and navigable, with decision-list and action-list side surfaces, click-to-spawn-bound-session, branch checklists with auto-collapse, and bidirectional (non-concurrent, next-spawn-reconciled) JSON state. The deliverable of v1 is a working module that delivers PRD scenarios S1, S2, S4, S5, S6, S7 fully and S3 in its non-concurrent form, with S8/live-co-edit explicitly deferred to a v2 (Option-3) upgrade.

## Scope

- **IN:**
  - JSON tree-state schema + atomic-write durability layer (resolves PRD OQ-1 conflict-unit, OQ-4 action-item typing; this is the Tier-4 contract — gets ADR-032).
  - Localhost GUI: tree view (pan/zoom/expand/collapse/click), decision-list surface, action-list surface, branch checklist + auto-collapse, drag-drop re-parent, promote-node-to-branch, tag cross-links.
  - Dispatch integration via the existing `spawn-task-report-back.md` convention: Dispatch annotation markers (FR-12) write tree mutations at session boundary; a SessionStart surfacer reflects them; "conclude branch → spawn bound session"; "session question → child node".
  - Bidirectional check-off override (FR-9) with visible contested state.
  - Defer-my-action-with-condition (FR-13) — date/time via lightweight scheduled check, event via existing harness surfacing hooks, manual unhide floor.
  - Optional-module enable/disable seam (FR-16) + first-run empty state (FR-17).
  - The FR-2 multi-divergent-branch cardinality rule (resolved below in Decisions).
- **OUT (v1):**
  - Live mid-session control / injection into a running cloud Dispatch session (ADR-031 hard constraint — ruled out by research).
  - Concurrent same-file co-edit by a *running* session + Misha (PRD Scenario 8, NFR-2 live notice, FR-11's *concurrent* property) — deferred to v2/Option-3; v1 is non-concurrent (GUI is the only live writer; Dispatch writes only at its own session boundaries).
  - Channels bridge / real-time snapshot model (OQ-2 resolves to *snapshot* for v1; real-time is the v2 upgrade, and per ADR-031 r2 it is a concurrency-model rebuild, not transport-only).
  - Everything in the PRD's Out-of-scope list (multi-user, mobile, JSON hand-editing, aggressive alerting, auto-conflict-resolution).

## Tasks

<!-- Proposed DAG. Tier-5→Tier1-4 decomposition per work-sizing rubric.
Per-phase acceptance + per-phase reviewers are stated. Verification levels
per risk-tiered-verification.md. Tasks do NOT begin until G1+G2. -->

### Phase A — State contract (must freeze before any consumer builds; Tier 4)

- [ ] A1. Author ADR-032: JSON tree-state schema — node shape, the FR-2 cardinality rule, OQ-1 conflict unit (per-field, honoring ADR-031's pinned "independently-addressable per-field-mergeable nodes" constraint), OQ-4 action-item typing enum, OQ-6 tree-scope (per-project vs global), OQ-7 concluded-branch lifecycle. — Verification: contract — **Reviewer: systems-designer (ADR option/assumption review, Tier-4 contract).**
- [ ] A2. Implement the schema + atomic write-temp-then-rename durability layer + last-N-version retention (NFR-1). — Verification: full — **Reviewer: code-reviewer + task-verifier.**

### Phase B — Tree GUI core (new top-level UI surface; Tier 3)

- [ ] B1. Tree view: render, pan/zoom, expand/collapse, click-to-focus, branch auto-collapse on all-checked (FR-1, FR-8). — Verification: full — **Reviewer: ux-designer (new UI surface, mandatory) + functionality-verifier.**
- [ ] B2. Decision-list + action-list side surfaces, each linked back to originating node (FR-4, FR-5). — Verification: full — **Reviewer: ux-designer + functionality-verifier.**
- [ ] B3. Drag-drop re-parent, promote-node-to-branch, tag cross-links (FR-3, FR-11 GUI-side write). — Verification: full — **Reviewer: functionality-verifier.**
- [ ] B4. First-run empty state + optional-module enable/disable seam (FR-16, FR-17, SM-5/SM-6). — Verification: full — **Reviewer: ux-designer + functionality-verifier.**

### Phase C — Dispatch integration (reuses spawn-task-report-back; Tier 3)

- [ ] C1. Dispatch annotation markers (FR-12) → tree mutations written at session boundary; SessionStart surfacer reflects them into the GUI (FR-11 Dispatch→GUI half). — Verification: full — **Reviewer: systems-designer (integration-point review) + functionality-verifier.**
- [ ] C2. Conclude-branch → spawn bound Dispatch session with gathered decisions as prompt + spawn guardrail confirmation (FR-14, FR-19); session question → child node (FR-15). — Verification: full — **Reviewer: systems-designer + functionality-verifier.**
- [ ] C3. Bidirectional check-off override with visible contested state; next-spawn reconciliation of GUI-side edits (FR-9, FR-11 GUI→Dispatch half via next-spawn). — Verification: full — **Reviewer: code-reviewer + functionality-verifier.**

### Phase D — Deferral + close-out (Tier 2)

- [ ] D1. Defer-my-action-with-condition: date/time scheduled check + event via existing surfacing hooks + manual unhide (FR-13). — Verification: full — **Reviewer: functionality-verifier.**
- [ ] D2. Acceptance pass: end-user-advocate runtime mode against the running GUI for S1,S2,S3(non-concurrent),S4,S5,S6,S7. — Verification: full — **Reviewer: end-user-advocate (runtime).**

## Files to Modify/Create

<!-- Indicative; final paths depend on ADR-031 adoption + ADR-032 schema.
Listed so scope-enforcement-gate has a declared surface once ACTIVE. -->
- `docs/decisions/032-conversation-tree-state-schema.md` — the Tier-4 state contract (Task A1) + DECISIONS.md index row.
- `<module-root>/state/` — JSON tree-state schema, atomic-write durability, version retention (A2).
- `<module-root>/gui/` — tree view, side surfaces, drag-drop, empty state (B1–B4).
- `<module-root>/integration/` — Dispatch annotation reader, SessionStart surfacer, spawn-bound-session, question→child-node (C1–C3).
- `<module-root>/defer/` — deferral conditions + resolution (D1).
- `adapters/claude-code/` — only the minimal documented integration seam (FR-16/NFR-8); enumerated in §3 below. Exact files pending ADR-031 adoption.
- `SCRATCHPAD.md`, `docs/plans/conversation-tree-ui.md` — status + evidence bookkeeping.

## In-flight scope updates

<!-- Populated during build per spec-freeze/scope-enforcement protocol. Empty at DRAFT. -->

## Assumptions

- ADR-031 Option 4 is adopted by Misha (G1). If not, this plan is void and re-authored against the chosen option.
- Misha continues to drive via cloud Dispatch (the constraint that selected Option 4). If he moves to local/Remote-Control sessions, the v2 Option-3 upgrade path applies — out of scope for this plan.
- The `spawn-task-report-back.md` convention remains stable (it is a shipped harness rule). v1 depends only on its Dispatch→orchestrator direction; GUI→Dispatch is next-spawn reconciliation, not a new live channel.
- ADR-032 will honor ADR-031's pinned constraint (independently-addressable per-field-mergeable nodes). A2 cannot proceed until A1 freezes that property.
- The harness's existing surfacing hooks (SessionStart pattern, e.g., discovery-surfacer/spawned-task-result-surfacer) are reusable for FR-13 event conditions and FR-11 Dispatch→GUI reflection — to be verified in C1, not assumed at build time.
- No new third-party runtime dependency beyond the GUI framework choice (deferred to ADR-032/B1; minimal-dependency principle applies).

## Edge Cases

- **FR-2 multi-divergent decision-set (resolves the PRD-review finding):** when Dispatch presents N decisions and Misha leaves >1 unanswered OR takes >1 deep, the model creates **one child branch per divergent decision-subset that Misha groups, defaulting to one shared child branch for the entire divergent set unless Misha explicitly splits it** (promote-node-to-branch, FR-3). Rationale: a shared branch matches the "I'll deal with these together" mental model; per-decision branches are opt-in via the existing promote affordance, avoiding tree explosion. A1/ADR-032 encodes this as the canonical rule with a test fixture for N=3 (2 unanswered + 1 deep).
- Dispatch writes malformed/partial JSON (crash mid-write) → NFR-1 atomic write + last-good fallback; corruption surfaced, never silent data loss or blank tree.
- Node bound to a missing/cleaned-up session → NFR-9 degrade to "session unavailable", still navigable.
- Tree growth over months → OQ-7: collapse-by-default + archival tier for branches concluded > N days, recoverable (decided in A1).
- Misha clicks a cold branch *while a Dispatch session is live elsewhere* → S3 degraded behavior (concurrent bound spawn, not focus-switch) — surfaced in the GUI as an explicit "a session is already running; this will start a second one" confirmation, not a silent surprise.
- Spawn guardrail (FR-19): no branch-conclusion spawns a session without per-spawn confirmation or recorded pre-authorization.

## Testing Strategy

- A2/state: unit (schema validation, atomic-write under simulated crash, version retention) + property test (per-field merge).
- B*/GUI: functionality-verifier exercises each scenario in a browser (real clicks, real state file), not component-only.
- C*/integration: a real (local) Dispatch session writing annotations → assert tree reflects them; spawn-bound-session produces a session whose prompt contains gathered decisions (curl/log assertion).
- D2: end-user-advocate runtime mode is the acceptance gate for the in-scope scenario set; artifact under `.claude/state/acceptance/conversation-tree-ui/`.
- Per FUNCTIONALITY-OVER-COMPONENTS: a task is done only when a user can do the thing, demonstrated end-to-end against the running module — not when it compiles.

## Acceptance Scenarios

<!-- Seeded from PRD scenarios; end-user-advocate plan-time mode hardens
this section as part of the Phase-4 gate. Assertions stay private to the
advocate (scenarios-shared, assertions-private). -->

### s1-branches-persist — open branches survive a session boundary
**Slug:** `s1-branches-persist`
**User flow:** 1. Drive a Dispatch session that branches a decision-set. 2. End the session. 3. Open the GUI next session. 4. Observe the open branch present without reading scrollback.
**Success criteria (prose):** every branch open at session end is visible and click-focusable next session (PRD SM-1).
**Artifacts to capture:** screenshot of tree with the persisted branch; the audit-log lines; no console errors.

### s2-waiting-on-me — decision list surfaces all unanswered decisions
**Slug:** `s2-waiting-on-me`
**User flow:** 1. Open decision-list surface. 2. See every unanswered decision linked to its node. 3. Click one. 4. Answer it. 5. See it leave the list.
**Success criteria (prose):** answering removes the decision within one state refresh; each entry links back to its node (PRD SM-3).
**Artifacts to capture:** screenshot before/after; state-refresh timing; no console errors.

### s3-resume-cold-branch-non-concurrent — resume an idle branch (no live session)
**Slug:** `s3-resume-cold-branch-non-concurrent`
**User flow:** 1. With no Dispatch session live, click an idle branch node. 2. Compose a follow-up. 3. Observe a bound session spawned for that node.
**Success criteria (prose):** a session is spawned bound to the clicked node with that branch's context; the previously-focused leaf auto-concludes (FR-6/FR-7). The concurrent-session-live variant is OUT of v1 scope (degraded-behavior confirmation only).
**Artifacts to capture:** screenshot; spawned-session prompt content; no console errors.

### s4-auto-collapse — branch collapses when all items checked
**Slug:** `s4-auto-collapse`
**User flow:** 1. Open a branch with a checklist. 2. Check the final item. 3. Observe the branch collapse. 4. Expand it again.
**Success criteria (prose):** last-item-check collapses; expand restores full history (FR-8); parent gets exactly one "child concluded" alert (FR-10).
**Artifacts to capture:** screenshot collapsed + expanded; alert count = 1.

### s5-contested-checkoff — bidirectional override never silently resolves
**Slug:** `s5-contested-checkoff`
**User flow:** 1. Have Dispatch implicitly check an item. 2. Uncheck it with a note. 3. Observe contested state. 4. Have Misha check an item; Dispatch contests it. 5. Observe the specific "X complete but Y may not be covered" message.
**Success criteria (prose):** both override directions produce a visible contested state neither side auto-resolves (PRD SM-4).
**Artifacts to capture:** screenshot of both contested states; audit log shows explicit-only resolution.

### s6-conclude-spawns-session — concluding a branch kicks off a bound session
**Slug:** `s6-conclude-spawns-session`
**User flow:** 1. Answer all of a branch's decisions. 2. Conclude it. 3. Confirm the spawn guardrail. 4. Observe a Dispatch session whose prompt is the gathered decisions. 5. Have that session ask a question. 6. Observe a new child node under the spawning branch.
**Success criteria (prose):** conclusion (with confirmation, FR-19) spawns a session prompted with the gathered decisions (FR-14); a session question creates exactly one correctly-parented child node (FR-15).
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
- **Chosen:** one shared child branch for the entire divergent decision-set by default; per-decision split is opt-in via the existing promote-node-to-branch affordance.
- **Alternatives:** one branch per divergent decision (tree explosion; rejected) / no branch until Misha acts (loses the "these are open" signal; rejected).
- **Reasoning:** matches the "deal with these together" mental model; opt-in split avoids unbounded fan-out; reuses an FR-3 affordance rather than new mechanism.
- **To reverse:** change the A1/ADR-032 canonical rule + its N=3 fixture.

### Decision: v1 is non-concurrent (S8/FR-11-concurrent/NFR-2-live OUT)
- **Tier:** 2 — **Status:** proceeded (carries ADR-031 r2 Finding-1 forward into the plan as explicit scope)
- **Chosen:** GUI is the only live writer; Dispatch writes only at session boundaries; GUI→Dispatch via next-spawn reconciliation. Concurrent co-edit deferred to v2/Option-3.
- **Alternatives:** attempt a live bridge (ruled out for cloud Dispatch by research) / block GUI edits while any session runs (worse UX; rejected).
- **Reasoning:** the cloud-Dispatch hard constraint makes live concurrency impossible; honest v1 scoping beats a feature that cannot work.
- **To reverse:** the v2 Option-3 upgrade (requires Misha on local sessions) — a separate plan.

## Definition of Done
- [ ] All tasks checked off (after G1+G2 only)
- [ ] All tests pass; functionality-verifier PASS on every runtime task
- [ ] end-user-advocate runtime PASS artifact for the in-scope scenario set
- [ ] ADR-032 authored + indexed (A1)
- [ ] SCRATCHPAD.md updated; completion report appended; Status flipped (closure procedure)

## Systems Engineering Analysis

### 1. Outcome (measurable user outcome, not output)
Within one session-boundary, 100% of branches Misha left open are visible and resumable in the GUI without reading scrollback (PRD SM-1); resuming a ≥2-session-cold branch takes ≤3 GUI interactions and zero scrollback reads (SM-2); a Dispatch-installed-but-unused session fires zero module-originated interruptions (SM-6). Not "the tree UI is built."

### 2. End-to-end trace with a concrete example
T=0 Misha drives a Dispatch session (cloud) on "investigate harness gap G". T=8min Dispatch surfaces 3 decisions, emits annotation `opening child node: G-deepdive-d3` and writes the tree mutation into the JSON state at its session boundary (report-back result JSON, per spawn-task-report-back convention). T=session-end the result file lands; the SessionStart surfacer on Misha's next GUI open reads it; the GUI renders parent G with d1/d2 auto-checked and an open child `G-deepdive-d3`. T+1day Misha opens GUI, clicks `G-deepdive-d3` (no session live), confirms the spawn guardrail; the GUI composes a prompt = node's gathered context + d3, spawns a bound Dispatch session. That session asks a clarifying question → emits `child node: G-deepdive-d3-q1` at its boundary → surfacer renders it under `G-deepdive-d3`. No step requires reading or injecting into a *running* cloud session — every cross-boundary transition is a file the surfacer reads.

### 3. Interface contracts between components
| Producer | Consumer | Contract |
|---|---|---|
| Dispatch session | JSON state file | Writes tree mutations ONLY at session boundary via report-back result JSON (schema = ADR-032). Never mid-run. Atomic write-temp-then-rename. |
| JSON state file | GUI | GUI reads on open + on surfacer signal; GUI is the only live writer; per-field last-write-wins (ADR-031 pinned constraint). |
| GUI | Dispatch (spawn) | "Conclude branch" → spawn bound session; prompt = gathered decisions; guardrail confirmation required (FR-19). One session per conclude. |
| SessionStart surfacer | GUI | Emits a signal when a new report-back result for a tracked node lands; idempotent; `.acked` marker prevents re-surface. |
| Module | Harness core | Only the enumerated seam in §4; zero required Stop/PreToolUse hooks (NFR-8). |

### 4. Environment & execution context
Localhost-only GUI (NFR-5 — no inbound LAN port). Single user, single machine. State file lives per OQ-6's resolution (A1) — per-project under the repo or a global path. Reuses the harness's existing SessionStart-surfacer pattern (`spawned-task-result-surfacer.sh` family) — the integration seam is: (a) a Dispatch-prompt sentinel convention (existing), (b) one SessionStart surfacer reading report-back results into the tree, (c) the spawn call. Enable/disable = presence/absence of that surfacer wiring; disabled = byte-identical hook behavior (SM-5). No credentials in state (NFR-5).

### 5. Authentication & authorization map
No auth (single local user; localhost bind only). Dispatch-session spawning uses Misha's existing Claude Code auth (the GUI does not hold credentials; it composes a prompt and invokes the existing spawn path — `mcp__ccd_session__spawn_task`-style). No new credential, token, or external API surface. State file is not credential-bearing (NFR-5 acceptance: credential-pattern scan = 0).

### 6. Observability plan (built before the feature)
The Dispatch annotation trail (FR-12) is the primary observability surface — tree change history reconstructable from annotations alone (NFR-7). Every state mutation (GUI or Dispatch) appends to an append-only audit log; current tree reconstructable from audit log + annotations. GUI surfaces a visible "last synced from session X at T" indicator so staleness is observable, not silent.

### 7. Failure-mode analysis per step
| Step | Failure | Symptom | Recovery | Escalate |
|---|---|---|---|---|
| Dispatch boundary write | crash mid-write | partial JSON | atomic temp+rename; last-good retained (NFR-1) | corruption banner if all versions bad |
| Surfacer read | malformed result JSON | node not updated | surfacer warns to stderr, skips; manual re-acked | if recurring, integration bug → finding |
| Click cold branch (session live) | concurrent spawn | 2nd session starts | explicit pre-spawn confirmation (S3 degraded) | n/a — by design |
| Conclude → spawn | spawn fails | no session created | guardrail shows failure; branch stays open | surface to Misha |
| Bound session | references missing session | node "session unavailable" | NFR-9 degrade; still navigable | n/a |
| Defer condition | scheduled check misses | item never returns | manual unhide floor always available | n/a |

### 8. Idempotency & restart semantics
Surfacer is idempotent (`.acked` marker; re-run = no-op). Atomic state writes → a re-run mutation is safe (last-write-wins per field). GUI restart re-reads state file (no in-memory authority). A partially-written Dispatch result is ignored until complete (temp+rename). Re-spawning a bound session after a crash: guardrail re-confirms; no silent duplicate.

### 9. Load / capacity model
Bottleneck: tree-render at scale. NFR-3 target p95 < 150ms interaction at ≥500 nodes; OQ-7 archival tier caps the live working set (concluded > N days → archival, recoverable). State file size grows with tree; at saturation the archival tier prunes the live file, not the audit log. No network/API rate concern (localhost, no external calls except the existing spawn path which Misha already rate-bounds by hand).

### 10. Decision records & runbook
ADR-031 (architecture, Proposed). ADR-032 (state schema, Task A1). Decisions Log above (FR-2 cardinality; v1-non-concurrent). Runbook — *symptom: GUI shows stale tree*: (1) check the surfacer fired (audit log), (2) check the latest report-back result landed + `.acked`, (3) re-open GUI (re-reads state). *Symptom: branch didn't auto-collapse*: (1) verify all checklist items checked in state file, (2) check for an unresolved contested item (contested ≠ checked by design). *Symptom: concluded branch didn't spawn*: (1) check guardrail confirmation was given, (2) check spawn path returned, (3) branch stays open if spawn failed — re-conclude.
