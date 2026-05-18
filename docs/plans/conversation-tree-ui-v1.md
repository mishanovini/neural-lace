# Plan: Conversation Tree Management UI — v1 (ADR-031 Option 2: file-mediated passive tracker)

Status: ACTIVE
Execution Mode: orchestrator
Mode: design
Backlog items absorbed: none
tier: 4
rung: 2
architecture: coding-harness
frozen: true
prd-ref: conversation-tree-management-ui

<!--
RE-AUTHORED, not patched. ADR-031 r7 ACCEPTED Option 2 (file-mediated
state contract, passive observer GUI) and explicitly directs the prior
Option-4 plan be "re-authored against the adopted option, not edited —
it is now materially divergent." The prior plan docs/plans/conversation-tree-ui.md
is marked Status: SUPERSEDED in the same change-set that creates this file
(auto-archives via plan-lifecycle.sh; reversible by one git mv).

Gate state: G1 (architecture adopted) = DONE (ADR-031 r7 ACCEPTED,
Tier-5-hardened, 3 plan-safety pins folded @ 8275d31). G2 (Misha confirms
the plan structure) = DONE — Misha greenlit plan-and-build, confirmed the
phase structure, directed three-pane simultaneous layout + full v1
("the tree and actions list and backlog list should all be visible on the
same screen at the same time. build the full thing in v1."). Status flips
DRAFT → ACTIVE only AFTER plan-reviewer PASS + systems-designer PASS +
ux-designer findings folded. While DRAFT this plan is NOT scanned by
product-acceptance-gate; the 5-field header schema is informational
(Check 10 gates ACTIVE) but populated for review-completeness.
prd-validity-gate resolves prd-ref → docs/prd.md (7 substantive sections;
prd-validity-reviewer PASSed @ 8b1453e).

Decisions 1/4/5 (tech stack / hook timing / acceptance bar) carried as
defaults pending explicit Misha override per his relayed instruction;
recorded in ## Decisions Log so the audit trail is intact.
-->

## Goal

Build v1 of the Conversation Tree Management UI per **ADR-031 Option 2**: a localhost, single-user, passive **tracker** that makes the Misha↔Dispatch conversation *tree* — and the not-yet-started backlog feeding it — durable, visible, and navigable, by reading a **file-mediated state contract** the Dispatch orchestrator writes as it works. The GUI is read-mostly: it surfaces the tree, the "what's waiting on Misha" decision/action lists, and the backlog **all on one screen simultaneously** (Misha directive); it lets Misha modify the tracked state through the GUI (drag-drop, check-off, defer, archive, promote, tag, reorder) by appending events to the same shared log Dispatch reads. The GUI **never becomes the chat and never spawns or steers a Claude Code session** — continuation happens in Dispatch (the Claude desktop app) as normal. v1 delivers all 27 active PRD FRs. The local cloud blind spot (web/`--remote`/Routines threads have no local transcript) is an accepted, surfaced limitation, not a defect.

## User-facing Outcome

After v1 ships, Misha can — at any later point, regardless of elapsed time, without reading scrollback — open the localhost GUI and see, on one screen: (a) the full conversation tree of in-flight work with every open branch present and accurate; (b) every decision/question/action waiting on him, each linked back to its node; (c) his backlog of not-yet-started Claude-Code work items with attached context. He can modify any of it through the GUI and Dispatch sees those modifications the next time it reads the state file. No open thread silently disappears; no stale decision rots unseen; elapsed time costs nothing (PRD SM-1/SM-2/SM-3/SM-8/SM-9).

## Scope

- **IN:**
  - **State contract (Phase A):** versioned JSON schema; append-only event log + periodic snapshot; atomic single-event append; compaction trigger; torn-snapshot recovery (reader replays the log); versioned-reader-refuses-unknown-major; last-N-version retention; append-only audit log (NFR-1, NFR-7; ADR-032 fixes field layout, the 3 viability properties are ADR-031-pinned inputs).
  - **Enforcement substrate (Phase B):** `conversation-tree-state-gate.sh` (PreToolUse, enumerated matcher `mcp__ccd_session__spawn_task|mcp__ccd_session_mgmt__start_code_task|Task|Agent`, Pin-2 error partition), `conversation-tree-stop-gate.sh` (Stop), Pattern rule `conversation-tree-state.md`, hook wiring; preceded by an empirical `tool_name`-for-MCP verification (ADR-031 build-phase pin).
  - **Three-pane GUI (Phase C):** tree pane + actions-list pane + backlog-list pane visible **simultaneously on one screen** (Misha directive — not main/secondary); click-to-surface-context (FR-6); 3 data states (loading / first-run empty FR-17 / corruption UX-I4); GUI-side mutations as appended events (FR-11 GUI-write half — drag-drop re-parent, promote-to-branch, tag cross-links FR-3, archival FR-28).
  - **Tracker behaviors (Phase D):** branch checklist + auto-conclude **only on all-items-checked** (FR-7/FR-8 reframed), parent single-notification (FR-10), check-off override safety-net (FR-9, low emphasis), defer-as-visible-tag (FR-13 reframed), per-branch draft persistence + indicator (FR-27), multi-project trees + global tree + cross-tree links (FR-18/FR-25/FR-3), sort + mouse drag-reorder (FR-29).
  - **Acceptance + close-out (Phase E):** `end-user-advocate` runtime against the running GUI from a non-Dispatch session (Decision 5 default; HARNESS-GAP-34 risk surfaced), close-plan procedure.
  - All 27 active PRD FRs (full v1 per Misha directive — FR-20/21/22 backlog and FR-18/25 multi-project are IN, not deferred).
- **OUT:**
  - Live mid-run injection into / steering of a running session — Option 2 is passive by construction; the GUI never commands Dispatch.
  - Genuinely-cloud threads (Claude-Code-on-web, `--remote`, unattended `/schedule` Routines) — accepted local blind spot per ADR-031 r7; the GUI shows nothing false about them, it shows only what it can see.
  - The NFR-2 co-edit conflict-*resolution mechanism* — only the safety property is in scope here; the mechanism + conflict-unit are ADR-032's (PRD OQ-1).
  - Everything in the PRD `## Out-of-scope` list (multi-user, mobile-native, raw-state hand-editing surface, aggressive nag/alert engine, automatic conflict resolution, generic PM tooling, replacing the desktop-app feature set).
  - `Bash(claude …)` / `/schedule` spawn surfaces — accepted enforcement gap per ADR-031 r7 Pin 1 (same class as the cloud blind spot).
  - Keyboard-accessible drag-drop equivalents (NFR-6 v1: mouse-only acceptable; keyboard-DnD is an explicit v2 nice-to-have).

## Walking Skeleton

The thinnest end-to-end slice touching every Option-2 layer, built FIRST (Phase 0, before any feature flesh):

> A real local Dispatch session (the orchestrator, in a build session) appends **one** `branch-opened` event and writes **one** snapshot to the well-known JSON state file using the minimal-but-real schema → the minimal localhost GUI (Node static server + one HTML page + SSE) reads the snapshot → renders **one** node → Misha opens `http://localhost:<port>` and sees that one node.

Layers exercised: Dispatch write → well-known-path file → atomic single-event append + snapshot → GUI read (snapshot, with log-replay fallback stubbed) → GUI render → SSE push-on-change. No enforcement hooks, no side panes, no checklists, no backlog, no multi-project in the skeleton. If it walks end-to-end on Misha's machine, the Option-2 spine is proven and Phases A–E add flesh to a known-good spine. If it does not, Option 2's core premise (a passive local reader of a file Dispatch writes) is falsified before any feature is built — which is the point of skeleton-first.

## Tasks

<!-- Per-phase acceptance + per-phase reviewers stated. Verification levels
per risk-tiered-verification.md. Wire checks use the n/a carve-out where
concrete file paths are unresolvable until ADR-032 freezes the schema +
the GUI tech layout lands — this is the carve-out's intended use for a
pre-implementation design-package plan; the static chain is authored in
each phase's first task once paths exist. NO build task starts until
plan-reviewer PASS + systems-designer PASS + ux-designer findings folded
+ the DAG waiver is written (tier:4 ⇒ dag-review-waiver-gate fires). -->

### Phase 0 — Walking Skeleton (built FIRST; Tier 2)

- [x] 0.1 Minimal state writer + minimal localhost GUI proving the file-mediated read/write spine end-to-end (one `branch-opened` event + one snapshot → Node server + one HTML page reads + renders one node; SSE push-on-change). — Verification: full — **Reviewer: functionality-verifier.**
  **Prove it works:**
  1. Run the minimal writer; confirm a well-known JSON state file appears with one event + one snapshot.
  2. Start the Node localhost server; open `http://localhost:<port>` in a browser.
  3. Observe exactly one node rendered; append a second `branch-opened` event; observe the GUI update via SSE without a manual reload.
  **Wire checks:**
  - n/a — concrete file paths are unresolvable until Phase A fixes the schema + the Phase-0 server/page paths are created in this task itself; the statically-verifiable chain is authored as 0.1's first sub-step (writer path → state file path → server route → page DOM node) and recorded in the evidence block.
  **Integration points:**
  The state file is the only contract; verify by writing a known 2-event state and asserting the rendered node count = 2 (functionality-verifier, real browser).

### Phase A — State contract (freezes before any consumer builds; Tier 4)

- [x] A1. Author ADR-032: JSON tree-state schema field layout — `schema_version`, event-type enum (branch-opened / decision-raised / question-raised / answered / action-added / action-done / concluded / re-opened / archived / deferred / draft-saved / cross-linked / re-parented / promoted / backlog-added / backlog-activated …), node shape, FR-2 conversational-divergence cardinality rule, OQ-4 typed item set {decision, question, action}, well-known path resolution for per-project trees (FR-18) + the global tree (FR-25), NFR-2 conflict-unit. The 3 viability properties (torn-snapshot recovery, single-event-atomic append, compaction trigger) are **inputs from ADR-031 r7 Pin 3**, not re-decided here. — Verification: contract — **Reviewer: systems-designer (Tier-4 contract review).**
- [x] A2. Implement the state library against ADR-032 (per-component sub-items below; each independently verified). — Verification: full — **Reviewer: code-reviewer + task-verifier.**
  - [x] A2a. Atomic single-event append (Pin 3b) — a reader observes N or N+1 whole events, never a half event.
  - [x] A2b. Periodic snapshot write + compaction trigger (Pin 3c) — a fresh snapshot supersedes and truncates only the log prefix it provably covers.
  - [x] A2c. Torn-snapshot recovery (Pin 3a) — validity/coverage-marker detection + deterministic event-log replay fallback.
  - [x] A2d. Versioned reader refuses an unknown major `schema_version` (Pin 2) with a distinct "schema too new" message, never a mis-parse.
  - [x] A2e. Last-N-version retention + append-only audit log (NFR-1/NFR-7).
  **Prove it works:**
  1. Append N events; kill the writer mid-snapshot-write (simulated torn snapshot); re-read.
  2. Observe the reader detects the torn snapshot and reconstructs state by replaying the event log — no data loss, no blank tree.
  3. Trigger compaction; observe the log prefix truncates and the new snapshot is authoritative; feed an unknown major `schema_version`; observe the distinct refuse message, never a mis-parse.
  **Wire checks:**
  - n/a — concrete paths fixed by ADR-032 in A1; the static chain (writer API → state file → snapshot+log → reader API) is authored in A2's evidence block once A1 freezes the layout.
  **Integration points:**
  The state library is the contract every later phase consumes; verify via the A2 property suite (atomic-append-under-crash, torn-snapshot→log-replay, compaction-truncation, unknown-major-refused) cited in Testing Strategy.

### Phase B — Enforcement substrate (Option-2-specific; harness infrastructure; Tier 3)

- [x] B-DEC-D. DEC-D resolution = **option (d) snapshot-integrity attestation** (Misha-confirmed; supersedes the earlier (b); see Decisions Log → DEC-D for the binding 5-point rule). Sequenced FIRST — B1's §8 gate depends on the corrected contract. The prior (b) attempt `91c86f8` is REPLACED, not extended. Per-component sub-items below; each independently verified. — Verification: full — **Reviewer: systems-designer (ADR revision) + code-reviewer (store.js) + task-verifier.**
  - [x] B-DEC-Da. ADR-032 §7c/§8 **r2 revision**: §7c reverts to the ORIGINAL A2 compaction behavior (truncate covered prefix — the (b) `gateRelevantRetention` carve-out is removed; "no per-gate compaction carve-out, ever"). §8 becomes the **attestation primitive**: a snapshot is trustworthy iff its canonical-JSON sha256 equals the `hash` of the most-recent `snapshot-committed` event in `events[]`; verified ⇒ the gate reads `snapshot.nodes` for branch-presence; mismatch ⇒ torn ⇒ gate refuses + existing A2 torn-snapshot-recovery. Stated as a GENERAL primitive (any future gate gets snapshot-trust free). Add a dated r2 revision note recording (d) supersedes (b) + why. Fix the dangling `§180`→`§1 major-bump rule` citation (ADR-032 + findings.md) flagged by the (b) review.
  - [x] B-DEC-Db. `state/store.js`: REMOVE the (b) `gateRelevantRetention` predicate; restore the original A2 compaction (truncate covered prefix). Add the `snapshot-committed` attestation: every snapshot write atomically appends `{type:"snapshot-committed", hash:"sha256:<canonical-JSON digest of snapshot bytes>", at:<ts>}` to `events[]` as part of the same atomic publish (not a separate step). Add `attestSnapshot()` to the `state/state.js` facade, invoked by any commit that updates the snapshot. sha256 over canonical (deterministic key-ordered) serialized snapshot bytes. Preserve Pin-3a/3b/2 + A2 P1–P8 unchanged.
  - [x] B-DEC-Dc. `state/selftest.js`: replace the (b) P9/P10 with (d) proofs — (i) after a snapshot commit, the most-recent `snapshot-committed` hash equals the canonical-JSON sha256 of the on-disk snapshot; (ii) §8-gate simulation: verified snapshot ⇒ branch-presence resolves from `snapshot.nodes` (incl. a re-opened, a promoted, and a backlog-activated node — proving DEC-E/DEC-F are moot under (d)); (iii) a byte-tampered snapshot ⇒ hash mismatch ⇒ gate refuses + torn-recovery fires; (iv) **the NL-FINDING-004 FR-24 trace** (7-event tree, non-branch-opened final event, compaction fires) now post-compaction `readState()` preserves items/checked-states/drafts/conclusions (the (b) regression is gone because compaction is original-behavior + §8 reads the verified snapshot). Flip `docs/findings.md` NL-FINDING-003 → dispositioned-act and NL-FINDING-004 → dispositioned-act (the (b) approach abandoned; (d) has no such regression) citing the resolving SHA.
  **Prove it works:**
  1. Seed a tree (incl. a re-opened + a promoted + a backlog-activated node + checklist items + a draft + a conclusion); commit a snapshot; confirm a `snapshot-committed` event with the correct canonical-JSON sha256 is appended; trigger compaction; confirm the latest `snapshot-committed` survives naturally and the original-behavior compaction is restored (events[] truncated to covered prefix, audit log never truncated).
  2. §8-gate simulation against the verified snapshot resolves branch-presence for the re-opened/promoted/backlog-activated nodes (DEC-E/DEC-F moot); byte-tamper the snapshot → hash mismatch → gate refuses + torn-recovery engages.
  3. The NL-FINDING-004 FR-24 trace post-compaction `readState()` preserves all state (regression gone); A2 P1–P8 + Phase-0 3-step regression still pass.
  **Wire checks:**
  - n/a — touches the frozen ADR-032 contract doc + the existing `state/` lib; the static chain (ADR §7c/§8 r2 text ↔ `store.js` attestSnapshot + original compaction ↔ `state.js` facade ↔ `selftest.js` (d) proofs ↔ §8 verify-then-read-snapshot) is authored in B-DEC-D's evidence block.
  **Integration points:**
  ADR-032 is the contract every later phase consumes; B1's §8 gate consumes the attestation primitive (verify snapshot via most-recent `snapshot-committed` hash, then read `snapshot.nodes`). Verify via the (d) selftest proofs + systems-designer re-review of the §7c/§8 r2 revision + code-reviewer of store.js/state.js.
- [x] B0. Empirically verify Claude Code populates `tool_name` for the MCP spawn tools (`mcp__ccd_session__spawn_task`, `mcp__ccd_session_mgmt__start_code_task`) the same way it does for built-in `Task`/`Agent` — the ADR-031 r7 explicitly-flagged build-phase assumption. Record the observed event JSON shape. — Verification: mechanical — **Reviewer: task-verifier.**
- [x] B1. `conversation-tree-state-gate.sh` PreToolUse gate (per-component sub-items below; each independently verified). — Verification: full — **Reviewer: harness-reviewer.**
  - [x] B1a. Matcher `mcp__ccd_session__spawn_task|mcp__ccd_session_mgmt__start_code_task|Task|Agent` + branch-name-as-required-key check (the spawn `tool_input` supplies the branch independently — raises the bar from "wrote anything" to "wrote an entry naming this branch").
  - [x] B1b. Pin-2 error partition exactly: JSON-parse-fail → closed; missing-file with prior-spawn-this-session → closed; missing-file with no prior spawn → open (bootstrap exemption); stale-mtime → closed; unknown-schema-major → closed with the distinct "schema too new — upgrade" message; hook-internal jq/IO error → open.
  - [x] B1c. PreToolUse justification escape-hatch — a fresh `.claude/state/conv-tree-spawn-waiver-*.txt` (≥1 substantive line, <1h) permits the spawn (mirrors `bug-persistence-gate.sh`).
  - [x] B1d. `--self-test` exercising each partition cell + the bootstrap exemption + the waiver release-valve.
  **Prove it works:**
  1. Run `conversation-tree-state-gate.sh --self-test`; observe every error-partition cell + bootstrap + waiver scenario PASS.
  2. With a stale state file, attempt a matched spawn; observe BLOCK with the remediation message; drop a fresh waiver; observe ALLOW.
  3. With no state file and no prior spawn this session, attempt a spawn; observe ALLOW (bootstrap).
  **Wire checks:**
  - n/a — hook path is created in this task; static chain (settings.json matcher → hook script → state-file path) authored in B1's evidence block + verified by `--self-test`.
  **Integration points:**
  Mirrors `bug-persistence-gate.sh` / `teammate-spawn-validator.sh` precedents; verify via `--self-test` (mechanical) + one real matched spawn against a fresh vs stale state file.
- [x] B2. `conversation-tree-stop-gate.sh` Stop. Scans `$TRANSCRIPT_PATH` (agent-uneditable) for spawn / Task / Agent dispatch this session; if any occurred without a corresponding state-file write, BLOCK session end with a remediation message + a justification escape-hatch marker (mirrors `bug-persistence-gate.sh` exactly). `--self-test`. — Verification: full — **Reviewer: harness-reviewer.**
  **Prove it works:**
  1. `conversation-tree-stop-gate.sh --self-test` — spawn-without-write BLOCKs; spawn-with-write ALLOWs; no-spawn ALLOWs; waiver-present ALLOWs.
  2. Simulate a transcript with a Task dispatch and no state write; observe BLOCK + remediation.
  3. Add the state write; observe ALLOW.
  **Wire checks:**
  - n/a — hook path created here; static chain (Stop wiring → hook → transcript scan → state-file mtime check) authored in B2 evidence + `--self-test`.
  **Integration points:**
  Reads `$TRANSCRIPT_PATH`; verify via `--self-test` + one real session with/without a state write.
- [ ] B3. Pattern rule `~/.claude/rules/conversation-tree-state.md` (orchestrator self-applies "write the *true* tree"; schema-design-for-key-presence guidance — the ceiling of the mechanical layer is honestly documented). Wire both hooks in `adapters/claude-code/settings.json.template` AND the live `~/.claude/settings.json` (two-layer-config discipline). Update `docs/harness-architecture.md` (docs-freshness-gate). — Verification: mechanical — **Reviewer: harness-reviewer.**
  **Prove it works:**
  1. `diff -q` the wired matcher in `settings.json.template` vs live `~/.claude/settings.json` — byte-identical for the two new hook entries.
  2. Grep `docs/harness-architecture.md` for both hook rows present.
  3. Confirm the Pattern rule states the Mechanism+Pattern split + the cloud/`Bash(claude…)` accepted gaps.
  **Wire checks:**
  - n/a — settings.json + rule paths fixed; static chain (rule file exists → both hooks referenced → both wired in template+live) authored in B3 evidence.
  **Integration points:**
  Two-layer config; verify template↔live byte-identical for the new entries + arch-doc rows present (mechanical).

### Phase C — Three-pane GUI core (new top-level UI surface; Tier 3)

- [ ] C1. Three-pane layout shell + three never-conflated data states (per-component sub-items below; each independently verified). — Verification: full — **Reviewer: ux-designer (mandatory, new UI surface) + functionality-verifier.**
  - [ ] C1a. Three-pane simultaneous layout — tree pane + actions-list pane + backlog-list pane rendered together on one normal desktop viewport, no tab/scroll to reach any pane (Misha directive; supersedes the old plan's UX-C3 main/secondary recommendation).
  - [ ] C1b. Loading state — skeleton + "Loading conversation tree…".
  - [ ] C1c. First-run empty state — FR-17 per-pane explainer of what populates each pane, not an error/blank.
  - [ ] C1d. Corruption state — persistent banner `⚠ State file unreadable — showing last good version from <ts>; <N> newer versions could not be parsed`; all-versions-bad → explicit "could not load from any saved version" + audit-log path, never blank (UX-I4).
  - [ ] C1e. Steady-state-empty per pane (BF-2) — healthy-but-currently-empty, success-framed, distinct from loading/first-run/corruption: actions pane "Nothing waiting on you right now — items appear here when Dispatch raises a decision/question or an action needs you"; backlog pane "No backlog items — capture one with [+]" + capture affordance; tree pane all-concluded renders concluded stubs (UX-N8), never blank.
  **Prove it works:**
  1. Open the GUI with a seeded multi-node state file; observe all three panes rendered simultaneously, no scroll/tab to reach any pane on a normal desktop viewport.
  2. Point at a missing state file → first-run empty state per pane, not an error/blank.
  3. Point at a corrupt latest snapshot with a good prior version → corruption banner + last-good rendered (torn-snapshot recovery from A2 surfaced in UI).
  **Wire checks:**
  - n/a — GUI paths created here; static chain (server route → page → 3 pane DOM containers → state-lib reader) authored in C1 evidence.
  **Integration points:**
  Consumes the A2 reader; verify by seeding known states (good / missing / corrupt) and asserting the correct one of the three states renders (functionality-verifier, browser).
- [ ] C2. Tree pane — render, pan/zoom, expand/collapse, click-to-surface-context (FR-6: selecting a node surfaces its parent chain to root + the sub-branches that diverge from it + that node's open decisions/questions/actions; layered — summary by default, expandable to fuller context per OQ-3). The GUI makes **no claim** to be where the conversation continues; no session-lifecycle UI. — Verification: full — **Reviewer: ux-designer + functionality-verifier.**
  **Prove it works:**
  1. Seed a multi-level tree; pan/zoom/expand/collapse.
  2. Click a deep node; observe its parent chain to root + its diverging sub-branches + its open items surfaced (summary, expandable).
  3. Confirm no "resume/continue session" affordance is presented (passive-tracker invariant).
  **Wire checks:**
  - n/a — paths from C1/A2; static chain authored in C2 evidence.
  **Integration points:**
  Reads A2 state; verify selecting a node renders the exact parent-chain + sub-branch + open-item set for a seeded fixture (functionality-verifier).
- [ ] C3. Actions/decision surfacing in the actions-list pane (per-component sub-items below; each independently verified). — Verification: full — **Reviewer: ux-designer + functionality-verifier.**
  - [ ] C3a. Surface each unanswered decision + each open question + each open action from the tree(s), each entry carrying an originating-node breadcrumb (FR-4/FR-5).
  - [ ] C3b. Clicking an entry focuses + reveals that node in the tree pane (FR-6).
  - [ ] C3c. An answered/done item leaves the list within one state refresh (SM-3).
  **Prove it works:**
  1. Seed N unanswered items; observe the actions-list pane lists exactly N, each with a node breadcrumb.
  2. Click one → the tree pane focuses + reveals that node.
  3. Mark it answered in the state file; observe it leaves the list within one state refresh.
  **Wire checks:**
  - n/a — paths from C1/A2; static chain authored in C3 evidence.
  **Integration points:**
  Consumes A2 state; cross-links to C2 tree focus; verify count=N → answer one → N-1 (functionality-verifier).
- [ ] C4. Backlog pane — capture a not-yet-started item with priority {high, medium, low} (FR-20, OQ-11), attach/modify context (notes/files/prior-decisions — FR-21, both Misha and Claude per symmetric principle), activate → becomes a root node of a new tree carrying its context (FR-22); sort by priority/date/effort/tag + mouse drag-reorder in priority view (FR-29). Distinct surface from the actions list (OQ-10). — Verification: full — **Reviewer: ux-designer + functionality-verifier.**
  **Prove it works:**
  1. Capture a backlog item with priority + a context note; confirm it appears only in the backlog pane, not the actions pane.
  2. Re-sort by each key; drag-reorder in priority view; reload — order persists.
  3. Activate the item; observe a new tree root node exists carrying the attached context.
  **Wire checks:**
  - n/a — paths from C1/A2; static chain authored in C4 evidence.
  **Integration points:**
  Writes/reads A2 state as appended events; verify capture→activate round-trip + sort/reorder persistence (functionality-verifier).
- [ ] C5. GUI-side mutations as appended events (FR-11 GUI-write half — symmetric interface): drag-drop re-parent, promote-node-to-branch, tag cross-links incl. cross-tree (FR-3), node/branch archival (FR-28, never closes a Claude Code session). Every GUI mutation is a single appended event Dispatch reads next time it reads the file. — Verification: full — **Reviewer: functionality-verifier.**
  **Prove it works:**
  1. Drag a node to a new parent → a `re-parented` event appends → re-read shows the new parent; no node gains two parents (FR-1).
  2. Promote a node to a branch; tag-link two nodes across two trees → visible non-tree cross-link, neither parent changed.
  3. Archive a branch → absent from active view, present in archive surface, restorable; no session terminated.
  **Wire checks:**
  - n/a — paths from C1/A2; static chain authored in C5 evidence.
  **Integration points:**
  Appends to the A2 log (the same log Dispatch reads — symmetric FR-11); verify each op re-reads as the expected event + state (functionality-verifier).

### Phase D — Tracker behaviors (Tier 2/3)

- [ ] D1. Branch checklist + conclude/collapse/notify behaviors (per-component sub-items below; each independently verified). — Verification: full — **Reviewer: ux-designer + functionality-verifier.**
  - [ ] D1a. Checklist contains exactly the branch's open decisions + open actions + unanswered questions, nothing already-addressed (FR-8).
  - [ ] D1b. Auto-conclude only when the full checklist is checked; navigate-away changes no branch state (FR-7 reframed).
  - [ ] D1c. Persistent on-node `↩ auto-concluded — re-open` marker (not a transient toast, UX-C2) + animated collapse leaving a labeled in-place stub `▸ <branch> ✓ concluded` (UX-N8).
  - [ ] D1d. Exactly one parent notification on child conclude (FR-10).
  **Prove it works:**
  1. Open a branch with 3 unchecked items; navigate away and back — still open, unchanged (FR-7 reframe).
  2. Check the final item — branch auto-concludes, animates to a labeled collapsed stub, parent shows exactly one notification.
  3. Re-open the stub — full history restored, no data loss.
  **Wire checks:**
  - n/a — paths from Phase C; static chain authored in D1 evidence.
  **Integration points:**
  Reads/writes A2 state; verify all-checked⇒concluded, navigate-away⇒no-op, parent-notification-count=1 (functionality-verifier).
- [ ] D2. Check-off override safety-net (FR-9 — low UI emphasis, explicitly NOT a distrust mechanism): a check-off either side disagrees with is un-checkable/flaggable with a note; per-direction badge (`⚠ Dispatch marked done · you disputed` vs `⚠ You marked done · Dispatch disputed`), the note inline, a two-button resolve (`Accept their position` / `Keep mine, re-open`); the note can itself become a conversation thread; a contested item counts as NOT checked for FR-7 auto-conclude; resolution is explicit-only, never silent/auto (UX-C1, SM-4). The "Accept their position" resolution is itself an appended event (symmetric log — resolved-by-architecture per Decisions Log). — Verification: full — **Reviewer: ux-designer + functionality-verifier.**
  **Prove it works:**
  1. State shows a Dispatch-checked item; Misha un-checks with a note → per-direction contested badge + note inline, item counts as unchecked for auto-conclude.
  2. Misha checks an item; state carries a Dispatch dispute → the specific contested message renders.
  3. Resolve via each button → an explicit resolution event appends to the audit log; nothing auto-resolves.
  **Wire checks:**
  - n/a — paths from Phase C; static chain authored in D2 evidence.
  **Integration points:**
  Reads/writes A2 state; verify audit log shows explicit-only resolution, never implicit (SM-4) (functionality-verifier).
- [ ] D3. Defer-as-visible-tag (FR-13 reframed): deferring an action **tags it "deferred" and it stays on the actions-list pane**, optionally with a scheduled time. At the scheduled time the system **highlights it and notifies Misha — and does nothing else** (no auto-clear, no auto-act, no auto-move). The tag clears **only by explicit Misha action**. — Verification: full — **Reviewer: functionality-verifier.**
  **Prove it works:**
  1. Defer an action with a scheduled time → it remains on the actions list, visibly tagged "deferred".
  2. Advance to the scheduled time → exactly one highlight + notification fires; no other state change (tag not cleared, item not moved/acted).
  3. Manually clear the tag → item returns to normal; nothing was ever destroyed/auto-resolved.
  **Wire checks:**
  - n/a — paths from Phase C; static chain authored in D3 evidence.
  **Integration points:**
  Reads/writes A2 state + a lightweight scheduled check; verify stays-visible-throughout + exactly-one-highlight + manual-clear-only (functionality-verifier).
- [ ] D4. Per-branch draft persistence + node draft-pending indicator (FR-27): an unsent draft tied to a branch is preserved on branch-switch and restored on return; the node shows a persistent draft-pending badge until the draft is sent or cleared; best-effort durability (NFR-1 — draft loss on abrupt crash acceptable; tree/backlog never); an archived branch's draft is preserved best-effort and restored on un-archive (OQ-13). — Verification: full — **Reviewer: ux-designer + functionality-verifier.**
  **Prove it works:**
  1. Type a draft on branch A, switch to B, return to A → exact draft restored; node A shows the draft-pending badge throughout.
  2. Clear the draft → badge removed.
  3. Archive then un-archive a branch with a draft → draft restored if it survived (best-effort).
  **Wire checks:**
  - n/a — paths from Phase C; static chain authored in D4 evidence.
  **Integration points:**
  Reads/writes A2 state (drafts best-effort tier); verify switch-away-return preserves+restores + badge lifecycle (functionality-verifier).
- [ ] D5. Multi-project trees (FR-18 — separate tree per project) + global tree (FR-25 — cross-cutting work) + cross-tree FR-3 cross-links; project discovery is **user-directed only, no auto-discovery** (OQ-12); project isolation — no cross-project leakage except via explicit cross-links / the global tree (NFR-5). — Verification: full — **Reviewer: functionality-verifier.**
  **Prove it works:**
  1. Create work under project A and project B → each appears only in its own tree; switching projects switches trees.
  2. Add cross-cutting work to the global tree; cross-link a global node to a project-A node → visible non-tree association, no multi-parenting.
  3. Confirm project A's tree never surfaces project B content except through an explicit cross-link.
  **Wire checks:**
  - n/a — paths from Phase C + A1 path-resolution; static chain authored in D5 evidence.
  **Integration points:**
  Reads/writes A2 state (per-project + global path resolution from A1); verify isolation + cross-link rendering (functionality-verifier).

### Phase E — Acceptance + close-out

- [ ] E1. `end-user-advocate` runtime mode against the running GUI for the in-scope Acceptance Scenario set, **run from a non-Dispatch standalone Claude Code session** (Decision 5 default — the GUI is the entire user-facing surface; a substitute is weakest exactly there). If standalone is impractical, the documented substitute (self-applied advocate checklist + the systems-designer/ux-designer cross-check used in the design phase) is the interim gate, and the gap is surfaced, not hidden (HARNESS-GAP-34). — Verification: full — **Reviewer: end-user-advocate (runtime).**
  **Prove it works:**
  1. From a standalone session, the advocate opens the running GUI and executes each in-scope scenario.
  2. It captures per-scenario artifacts (screenshots, network/console logs).
  3. It writes a PASS artifact for the in-scope scenario set under `.claude/state/acceptance/conversation-tree-ui-v1/` matching the plan commit SHA.
  **Wire checks:**
  - n/a — acceptance is exercised against the running module post-build; no static code chain applies to an acceptance-pass task (≥30-char carve-out reason: the artifact is a runtime PASS JSON, not a code-chain).
  **Integration points:**
  The whole module; verify via the PASS artifact matching the plan commit SHA.
- [ ] E2. Close-plan procedure: completion report appended; SCRATCHPAD updated; backlog reconciliation verified (header declares `none`); Status flipped (triggers `plan-lifecycle.sh` archival). — Verification: mechanical — **Reviewer: task-verifier.**

## Files to Modify/Create

<!-- Indicative; final paths fixed by ADR-032 (A1) + the Phase-0/C tech
layout. Declared so scope-enforcement-gate has a surface once ACTIVE. -->
- `docs/decisions/032-conversation-tree-state-schema.md` — Tier-4 state contract (A1) + a `docs/DECISIONS.md` index row.
- `neural-lace/conversation-tree-ui/state/` — schema, atomic single-event append, snapshot, compaction, torn-snapshot recovery, version retention, audit log (A2).
- `neural-lace/conversation-tree-ui/server/` — minimal Node localhost server (static serve + state read endpoint + SSE push) (Phase 0, Phase C).
- `neural-lace/conversation-tree-ui/web/` — static HTML/CSS/JS three-pane front-end: tree pane, actions-list pane, backlog pane, data states, mutations (Phase 0, C, D).
- `adapters/claude-code/hooks/conversation-tree-state-gate.sh` — PreToolUse enforcement gate (B1).
- `adapters/claude-code/hooks/conversation-tree-stop-gate.sh` — Stop enforcement gate (B2).
- `adapters/claude-code/rules/conversation-tree-state.md` + `~/.claude/rules/conversation-tree-state.md` — Pattern rule, two-layer mirror (B3).
- `adapters/claude-code/settings.json.template` + `~/.claude/settings.json` — wire both hooks, two-layer (B3).
- `docs/harness-architecture.md` — add the two hook rows + the module row (B3, docs-freshness-gate).
- `docs/plans/conversation-tree-ui.md` — flip Status: SUPERSEDED (auto-archives the obsolete Option-4 plan).
- `SCRATCHPAD.md`, `docs/plans/conversation-tree-ui-v1.md` — status + evidence bookkeeping.

## In-flight scope updates

<!-- Populated during build per spec-freeze/scope-enforcement protocol. Empty at DRAFT. -->
- 2026-05-17: docs/DECISIONS.md — A1 ADR-032 requires its index row in the same commit (decisions-index-gate); previously listed only inside the ADR-032 Files-to-Modify bullet, not as a discrete gate-parseable path.
- 2026-05-17: docs/plans/conversation-tree-ui-v1-evidence.md — A1 front-loads the rung-2 comprehension articulation into the plan's evidence companion (dispatch directive); the plan listed conversation-tree-ui-v1.md for evidence bookkeeping but not the -evidence.md sibling explicitly.
- 2026-05-17 (Misha-authorized scope-in — DEC-D resolution; UPDATED to option (d)): task B-DEC-D revises the frozen `docs/decisions/032-conversation-tree-state-schema.md` §7c/§8 (DEC-D **option (d)** snapshot-integrity attestation; supersedes (b)) and updates `neural-lace/conversation-tree-ui/state/store.js` + `state/state.js` (facade `attestSnapshot()`) + `state/selftest.js` ((d) proofs) + flips `docs/findings.md` NL-FINDING-003 + NL-FINDING-004. ADR-032/§ revision authorized by Misha as "part of Phase B"; store.js/state.js/selftest.js are in A2's declared `state/` scope; findings.md is durable bookkeeping.
- 2026-05-17: docs/decisions/032-conversation-tree-state-schema.md — B-DEC-Da revises §7c/§8 + adds the r1 DEC-D revision note (canonical gate-parseable path for the prose entry above; Misha-authorized as part of Phase B).
- 2026-05-17: neural-lace/conversation-tree-ui/state/store.js — B-DEC-Db generalized gate-relevant-still-live compaction retention (canonical gate-parseable path; in A2's declared state/ scope).
- 2026-05-17: neural-lace/conversation-tree-ui/state/selftest.js — B-DEC-Dc P9/P10 DEC-D proof + P3 update (canonical gate-parseable path; in A2's declared state/ scope).
- 2026-05-17: docs/findings.md — B-DEC-Dc flips NL-FINDING-003 open → dispositioned-act → closed with resolution note (canonical gate-parseable path; durable findings-ledger bookkeeping per findings-ledger.md).
- 2026-05-17 (A2/C awareness — systems-designer A1 non-blocking finding, captured not rediscovered): ADR-032 §3 node shape carries `bound_sessions[]` (FR-15 many-to-many branch↔session) but §2's event enum has NO event that populates it. Additively closable within schema major 1 (a `session-bound`/`session-unbound` event pair — no major bump, no contract break). A2 (or Phase C/D integration) MUST add the `session-bound`/`session-unbound` events to ADR-032 §2 + the reducer. Class: requirement-with-no-write-path-but-additively-closable. Sweep: `rg -n 'bound_sessions|FR-15|session-bound' docs/decisions/032-conversation-tree-state-schema.md`.
- 2026-05-17 (A2 build): adapters/claude-code/hooks/harness-hygiene-scan.sh — one-token vocab-allowlist add (`Error`). The A2 state library legitimately uses the standard JS built-in `Error` ≥3× in `state/schema.js`; the Layer-2 cluster heuristic false-positived on it. Gate's own named remediation (harness-hygiene.md "How to add false-positive exemptions" → vocabulary allowlist) applied: `Error` joins the existing JS-built-in allowlist entries (`Promise|Object|Array|String|Boolean|Number|Function`). Two-layer mirror sync to `~/.claude/hooks/` is an orchestrator/install concern (live mirror outside this worktree).

## Assumptions

- ADR-031 r7 Option 2 is the adopted architecture and its 3 plan-safety pins are binding inputs (verified: ADR Status ACCEPTED r7, pins folded @ 8275d31).
- The Dispatch orchestrator is harness-bound for **local** sessions — `~/.claude/` PreToolUse/Stop hooks fire on it (ADR-031 r7 states this was confirmed structurally and by the very session that produced the ADR; B0 empirically re-verifies the `tool_name`-for-MCP sub-assumption before B1 relies on it).
- Node is already a harness runtime dependency (hooks ecosystem, `write-evidence.sh`, etc.) — the GUI introduces **no new runtime dependency** (tech-stack Decision 1 default: vanilla HTML/CSS/JS + Node localhost server + SSE).
- ADR-032 will fix only the schema **field layout** + NFR-2 conflict-unit; the 3 viability properties are already fixed by ADR-031 r7 (A2 cannot proceed until A1 freezes the field layout).
- Misha drives via **local** Dispatch (desktop-app + phone-trigger, all local — ADR-031 r6 verified on his machine). Genuinely-cloud threads are the accepted blind spot, not a v1 target.
- The harness's existing fresh-marker-gate precedents (`bug-persistence-gate.sh`, `teammate-spawn-validator.sh`) are reusable patterns for B1/B2 — re-verified at B1/B2 build, not assumed correct at plan time.
- `end-user-advocate` remains non-dispatchable inside the Dispatch environment (HARNESS-GAP-34) — E1 plans around this with a non-Dispatch standalone run as the default bar.

## Edge Cases

- **FR-2 conversational-divergence cardinality:** several questions/decisions discussed in one thread = **one branch, not many**; a new branch forms only when the conversation demonstrably diverges into a distinct line of work. A1/ADR-032 encodes this with an N=3 fixture (3 items in one thread ⇒ 0 extra branches; one item opening a sub-investigation ⇒ exactly 1 new branch). Per-item split is opt-in only via promote-to-branch (FR-3/C5).
- Dispatch writes malformed/partial JSON (crash mid-write) → atomic single-event append (Pin 3b) + torn-snapshot→log-replay (Pin 3a); corruption surfaced via the C1 banner, never silent loss or blank tree.
- Snapshot torn but event log intact → reader detects via validity/coverage marker, replays the log (mandatory, Pin 3a).
- Log grows across "a minute or a month" (FR-24) → compaction trigger truncates the covered prefix (Pin 3c); audit log retained separately (NFR-7).
- Spawn attempted with a stale/missing/corrupt state file → B1 error partition (closed/closed/closed) with the waiver release-valve; first spawn with no prior spawn this session → open (bootstrap, Pin 2a).
- Node references a Claude Code session that no longer exists → NFR-9 degrade: `⚠ session unavailable — context may be partial`, still click-focusable, still shows stored items (UX-I5). Archival never causes this (FR-28 closes no session).
- A genuinely-cloud thread (web/`--remote`/Routines) → invisible to the local reader by construction; the GUI shows nothing false about it (ADR-031 accepted blind spot) — the absence is the honest behavior, not a defect.
- Concurrent GUI append + Dispatch append → single-event-atomic append guarantees the reader sees N or N+1 whole events, never half (Pin 3b — a v1 reader-correctness property owned by ADR-031; the NFR-2 *resolution mechanism* is ADR-032's, OUT here).
- Unknown major `schema_version` → reader refuses with the distinct "schema too new — upgrade" message (Pin 2), never a mis-parse.

## Testing Strategy

- A2/state: property suite — atomic-append-under-simulated-crash, torn-snapshot→log-replay, compaction-truncation-correctness, unknown-major-refused, last-N-retention.
- B0–B3/hooks: `--self-test` is the harness-native rubric (every error-partition cell, bootstrap, waiver, transcript-scan branch) + one real matched spawn for B1 and one real session for B2; two-layer template↔live byte-identical check for B3.
- C*/D*/GUI: `functionality-verifier` exercises each scenario in a **real browser against a real state file** (real clicks, real drag-drop, real SSE push) — never component-only; FUNCTIONALITY-OVER-COMPONENTS: a task is done only when Misha can do the thing end-to-end against the running module.
- E1: `end-user-advocate` runtime mode is the acceptance gate for the in-scope scenario set; PASS artifact under `.claude/state/acceptance/conversation-tree-ui-v1/` matching the plan commit SHA; standalone-session run is the default bar (HARNESS-GAP-34).
- Three-pane invariant: a dedicated functionality-verifier assertion that tree + actions + backlog are simultaneously rendered on one normal desktop viewport (Misha's explicit directive — treated as a first-class acceptance property, scenario s9).

## UX Design Review

The prior plan's plan-time `ux-designer` review (2026-05-15, @adee136) is **partially carried, partially superseded** by the Option-2 reframe + Misha's three-pane directive. A fresh `ux-designer` pass on THIS plan is dispatched as part of the plan-and-build gate; the disposition below is the binding starting point and the fresh pass hardens it.

**Carried (still binding — the GUI surface is unchanged by Option 2):**
- **UX-C1 (Critical) → folded into D2:** contested check-off renders a per-direction badge + inline note + two-button resolve; contested counts as NOT checked for FR-7; resolution writes an explicit audit event.
- **UX-C2 (Critical) → folded into D1:** auto-conclude is never silent — persistent on-node `↩ auto-concluded — re-open` marker, node stays in tree, one-click re-open, items stay on the lists.
- **UX-I4 (Important) → folded into C1:** loading / first-run-empty / corruption are three never-conflated states with the exact corruption-banner copy.
- **UX-I5 (Important) → folded into Edge Cases + D5:** session-unavailable node is degraded-not-dead (badge, still navigable, shows stored items). NOTE the Option-2 reframe: there is **no** "spawn a fresh bound session" affordance (the GUI never spawns) — superseded; the node simply remains a navigable tracker entry.
- **UX-I7 (Important) → folded into C4/C5/D3:** defer via action-item overflow → date/event picker, deferred items stay visibly tagged in place (NOT a collapsed group — reframed to match FR-13 stays-visible); promote = node context-menu; list-entry click focuses+reveals+surfaces-context.
- **UX-N8 (Nice-to-have) → folded into D1:** animated collapse leaving a labeled in-place stub.
- **Cross-cutting (binding):** every system-initiated transition (auto-conclude, defer-time highlight) leaves a persistent on-node signal + undo, never transient-only; every bistable/contested state names both its visible signal AND its exit affordance in the owning task body.

**Superseded by Option 2 / Misha directive (recorded so the change is traceable, not silently dropped):**
- **UX-C3 (was Critical — landing/information hierarchy):** the old "land on waiting-on-me, tree secondary" recommendation is **superseded by Misha's explicit directive: all three panes visible simultaneously on one screen, not main/secondary.** C1 builds the three-pane layout.
- **UX-I6 (was Important — costly-action spawn-confirmation specificity) and FR-19 spawn guardrail:** **GONE.** Option 2's GUI never spawns or steers a session, so the entire spawn-confirmation/guardrail surface does not exist. Recorded as deliberately removed, not an oversight.
- Old plan Q2 (contested write-back) / Q3 (auto-conclude trigger): **resolved by architecture / PRD** — see Decisions Log; not re-opened.

### ux-designer pass on the Option-2 plan (2026-05-17) — binding fold

`systems-designer` returned **PASS** (10-section SEA substantive, all 3 ADR-031 pins honored, no struck-Option-4 reintroduction; one non-blocking note: B0 is a hard prerequisite with an explicit re-plan trigger on FAIL — already framed that way in the plan). `ux-designer` returned **3 Critical + 5 Important + 2 Nice-to-have + 3 pending interface-impact decisions**. Disposition below is binding on the build. Critical #1 was flagged as a defect *class*; it is fixed once as a shared contract (class-fix per `diagnosis.md` — sweep documented in the fold commit), which also closes Important #4 and #8.

**BF-1 (Critical #1 + Important #4 + Important #8 — class-fix; binding). Option-2 Handoff-Affordance Contract.** Every surviving PRD action-verb that the passive tracker structurally cannot perform — *activate* (C4/FR-22), surface-a-cold-branch (C2/C3/FR-6), note-*becomes-a-conversation-thread* (D2/FR-9), *draft … sent* (D4/FR-27) — MUST, in its owning task, specify BOTH (a) the state event written AND (b) a **positive** user-facing handoff affordance with verbatim copy, never only the negative ("no continue button here"). The shared contract, binding on C2/C3/C4/D2/D4: on activate/surface/contest-note/draft the GUI (i) writes the appropriate appended event; (ii) shows a copy-ready context block + a **copy-to-clipboard** control; (iii) sets a persistent on-node badge from the fixed set — `▸ ready to start in Dispatch` (backlog-activated), `▸ surfaced — continue in Dispatch` (cold branch), `▸ open note — discuss in Dispatch` (contested-note), `▸ unfinished note` (draft); (iv) shows a one-line in-pane explainer "This tracker doesn't run Claude — open Dispatch and continue there; this node now tracks it." **D2 note→thread** = an appended tracked child node / open-question item under the contested item's branch, surfaced like any other open item with this same cue — explicitly **no in-GUI chat**. **D4 "draft"** is reframed: a *staged note Misha is preparing to paste into Dispatch* (a tracker scratchpad, not a message channel); "sent" → "marked used / cleared"; no "send" button anywhere; the copy-to-clipboard control is the handoff. No GUI surface presents a message-send/compose affordance.

**BF-2 (Critical #3 — binding). Four distinguishable states per data surface.** Each of the three panes specifies FOUR never-conflated states: loading (skeleton + text), first-run-empty (FR-17 per-pane explainer), **steady-state-empty** (healthy but currently nothing — success-framed, distinct copy, NOT conflated with first-run/loading/corruption), populated. Steady-state copy: actions pane empty → "Nothing waiting on you right now — items appear here when Dispatch raises a decision/question or an action needs you"; backlog pane empty → "No backlog items — capture one with [+]" + the capture affordance; tree pane all-concluded → render the concluded stubs (UX-N8), never blank. Folded into C1 as sub-item **C1e** (steady-state-empty per pane) in addition to C1b/C1c/C1d.

**BF-3 (Critical #2 — structure binding; proportions = surfaced decision DEC-A). Three-pane spatial spec.** C1a is amended: the page never scrolls; each pane scrolls **internally** when its content overflows; no pane ever collapses below a stated minimum; a stated minimum supported viewport applies; s9 must assert each pane is ≥ its minimum with its header visible (usable-size, not mere presence). The proportions + minimum viewport are **DECIDED (DEC-A, Misha 2026-05-17 = rec), now LOCKED**: tree pane left ~55–60% full-height; actions pane + backlog pane stacked right ~40–45%, each independently internally-scrollable with a pinned header; minimum viewport 1440×900. The standalone Phase-C session builds to these exact values (not re-synthesized).

**BF-4 (Important #5 — binding). Cross-surface navigation contract.** Clicking an actions/decision entry (C3b) or following a cross-tree link (D5) or a parent-notification (D1d): (i) auto-expands ALL collapsed/concluded ancestors of the target and scrolls it into view in the tree pane; (ii) if the target is in a different project/global tree than the one shown, the tree pane switches AND a transient orientation cue fires ("Switched to project B's tree to show this") and the originating entry's breadcrumb already names the tree/project. No silent context swap anywhere. Bound on C2/C3b/D1d/D5.

**BF-5 (Important #6 — binding). Shared GUI-mutation feedback contract.** Every GUI mutation (C4 capture/activate, C5 re-parent/promote/tag/archive, D1–D5 state changes) obeys one contract: (a) immediate optimistic update; (b) a subtle "saved" confirmation when the append is acknowledged; (c) on append failure or a reader-refuse (schema-too-new from a concurrent write), an explicit revert + error toast "Couldn't save that change — tree state unchanged; <reason>", tree snaps back to last-good. Crown-jewel tree state never shows an unpersisted change as if saved. Specified once in C5; referenced by C4/D1–D5.

**BF-6 (Important #7 — structure binding; channel = surfaced decision DEC-B). Notification surface.** Every "notify/alert/highlight" (D1d parent-conclude, D3 defer-time) is a **persistent in-GUI signal that survives until acted on** (consistent with the existing never-transient-only cross-cutting rule) — binding now. **DECIDED (DEC-B, Misha 2026-05-17 = rec), now LOCKED:** v1 is in-GUI-persistent-until-acted notifications ONLY; the not-focused limitation is surfaced honestly (same treatment as the cloud blind spot); a localhost OS notification is explicitly deferred to v1.5. Every notify behavior (D1d parent-conclude, D3 defer-time) states this in-GUI-persistent delivery surface in its task body.

**BF-7 (Nice-to-have #9/#10 — folded). NFR-6 + tree orientation.** (#10) Each of {concluded, deferred, draft-pending, contested} carries an explicit text/shape signal in addition to color (NFR-6 by construction, not inference); the s-scenarios assert it. (#9) C2 gains a pinned current-selection breadcrumb at the top of the tree pane and a "fit/center on selection" control (minimap optional) — useful given the tree pane is the §9 bottleneck under the three-pane width constraint.

**Acceptance hardening (binding amendments to the scenario set):** s9 success criteria amended to assert each pane is ≥ its stated minimum with header visible (usable-size), not merely present. s2/s8 amended to exercise the steady-state-empty rendering (caught-up actions pane / empty backlog) as distinct success-framed copy. s3/s8 amended to assert the positive Dispatch-handoff affordance + the copy-to-clipboard control + the node badge are present (BF-1), and that NO message-send/compose surface exists.

**Three interface-impact decisions — DECIDED by Misha 2026-05-17 (all = rec), now LOCKED inputs to Phase C/D** (recorded authoritatively in `## Decisions Log` → "Decision: DEC-A/B/C"): DEC-A three-pane proportions (tree ~55–60% L / actions+backlog stacked ~40–45% R, internally scrollable, min 1440×900); DEC-B in-GUI-persistent notifications only for v1 (OS → v1.5); DEC-C backlog→Dispatch handoff = copy-context-to-clipboard + `▸ ready to start in Dispatch` badge + explainer (per BF-1). The standalone Phase-C session builds to these exact values — NOT re-synthesized (interactive-process-fidelity: Misha's actual answers are the durable record).

### end-user-advocate plan-time review — substitute applied (HARNESS-GAP-34)

`end-user-advocate` is not dispatchable in the Dispatch environment (`Agent type not found`) — HARNESS-GAP-34 + `docs/discoveries/2026-05-15-end-user-advocate-not-dispatchable-in-dispatch-env.md`. No silent skip: the plan-time-advocate coverage checklist is self-applied and `systems-designer` + `ux-designer` independently cross-check scenario coverage as part of this plan's gate. Self-applied coverage: PRD scenarios S1–S11 map to the Acceptance Scenarios below (S6 reframed: GUI does not orchestrate; new s9 added for the three-pane invariant; s10 for one-branch-multi-question). The real `end-user-advocate` runtime pass (E1) is BLOCKED in the Dispatch env until HARNESS-GAP-34 is remediated and is planned to run from a non-Dispatch standalone session (Decision 5) — surfaced as a design-package risk, not hidden.

## Acceptance Scenarios

<!-- Seeded from PRD scenarios, reframed for the Option-2 passive tracker.
Assertions stay private to the advocate. -->

### s1-branches-persist — open branches survive a session boundary across any elapsed time
**Slug:** `s1-branches-persist`
**User flow:** 1. Drive a local Dispatch session that branches a decision-set. 2. End the session. 3. After an arbitrary elapsed gap, open the GUI. 4. Observe every branch that was open is present and click-focusable without reading scrollback.
**Success criteria (prose):** every branch open at session end is present and surface-able later; elapsed time costs nothing (PRD SM-1, FR-24).
**Artifacts to capture:** screenshot of the tree with the persisted branch; audit-log lines; no console errors.

### s2-waiting-on-me — the actions-list pane surfaces all unanswered items
**Slug:** `s2-waiting-on-me`
**User flow:** 1. Open the GUI (three panes visible). 2. Read the actions-list pane: every unanswered decision/question/open action, each with a node breadcrumb. 3. Click one → the tree pane focuses+reveals that node. 4. Mark it answered in state. 5. See it leave the list within one state refresh.
**Success criteria (prose):** answering removes the item within one state refresh; each entry links back to its node (PRD SM-3).
**Artifacts to capture:** before/after screenshots; state-refresh timing; no console errors.

### s3-surface-cold-branch-context — click an idle node, context is surfaced (NOT continued)
**Slug:** `s3-surface-cold-branch-context`
**User flow:** 1. Click an idle branch node untouched for an arbitrary time. 2. Observe its parent chain to root + diverging sub-branches + its open items surfaced (summary, expandable). 3. Confirm the GUI presents no "resume/continue session" affordance.
**Success criteria (prose):** selecting a node surfaces parent chain + sub-branches + open items; the GUI makes no claim to be where the conversation continues (FR-6 reframed, PRD SM-2/SM-9).
**Artifacts to capture:** screenshot of the surfaced context; no console errors; explicit confirmation no continue-session control exists.

### s4-auto-collapse-on-all-checked — branch concludes only when all items checked
**Slug:** `s4-auto-collapse-on-all-checked`
**User flow:** 1. Open a branch with a checklist; navigate away and back — observe it is unchanged/open. 2. Check the final item. 3. Observe auto-conclude → animated collapse to a labeled stub; parent shows exactly one notification. 4. Re-open the stub.
**Success criteria (prose):** navigate-away never concludes; all-checked is the sole trigger; exactly one parent notification; re-open restores full history (FR-7/FR-8/FR-10, UX-C2/N8).
**Artifacts to capture:** screenshots (open after navigate-away, collapsed stub, re-expanded); parent-notification count = 1.

### s5-contested-checkoff-safety-net — override either direction, never silently resolves
**Slug:** `s5-contested-checkoff-safety-net`
**User flow:** 1. State shows a Dispatch-checked item; Misha un-checks with a note → per-direction contested badge + inline note. 2. Misha checks an item; state carries a Dispatch dispute → the specific message renders. 3. Resolve via each button.
**Success criteria (prose):** both directions produce a visible non-silent contested state neither side auto-resolves; contested counts as NOT checked for FR-7; resolution is an explicit audit event (PRD SM-4, low-emphasis safety net).
**Artifacts to capture:** screenshots of both contested states; audit log shows explicit-only resolution.

### s6-conclude-no-orchestration — concluding marks concluded + notifies parent; the GUI orchestrates nothing
**Slug:** `s6-conclude-no-orchestration`
**User flow:** 1. Check all of a branch's items (or conclude it explicitly). 2. Observe it concludes, collapses to a stub, parent gets exactly one notification. 3. Confirm **no** Claude Code session is spawned, fed, or steered by the GUI.
**Success criteria (prose):** conclusion is a pure tracker state change + parent notification; the GUI never spawns/feeds/steers a session — continuation, if any, happens in Dispatch as normal (Option-2 invariant; PRD S6 reframed).
**Artifacts to capture:** screenshot of concluded state; explicit confirmation no spawn/steer occurred (no spawn tool invoked).

### s7-defer-stays-visible — defer keeps the item on the list, tagged
**Slug:** `s7-defer-stays-visible`
**User flow:** 1. Defer an action item with a scheduled time. 2. Observe it remains on the actions-list pane, visibly tagged "deferred". 3. Reach the scheduled time → exactly one highlight + notification, no other change. 4. Manually clear the tag.
**Success criteria (prose):** deferred item present throughout, tagged; at scheduled time exactly one highlight+notify and nothing else; tag clears only by explicit action; nothing destroyed/auto-resolved (FR-13 reframed).
**Artifacts to capture:** screenshots (deferred-tagged, highlighted-at-time, after manual clear); single-notification evidence.

### s8-backlog-to-root-with-context — backlog item carries context into its tree root
**Slug:** `s8-backlog-to-root-with-context`
**User flow:** 1. Capture a backlog item with priority + a context note in the backlog pane. 2. Confirm it appears only in the backlog pane (distinct from actions). 3. Activate it. 4. Observe a new tree root node exists carrying the attached context.
**Success criteria (prose):** capture→contextualize→activate yields a new tree root carrying its FR-21 context; backlog is a distinct surface from the actions list (FR-20/21/22, OQ-10, PRD SM-9).
**Artifacts to capture:** screenshots (backlog item, activated root with context); priority value rendered.

### s9-three-pane-simultaneous — tree + actions + backlog all visible on one screen
**Slug:** `s9-three-pane-simultaneous`
**User flow:** 1. Open the GUI with a seeded multi-node, multi-action, multi-backlog state on a normal desktop viewport. 2. Observe all three panes rendered simultaneously with no tab/scroll required to reach any pane. 3. Mutate state in one pane; observe the others reflect within one state refresh.
**Success criteria (prose):** the three panes are simultaneously visible and live on one screen at the stated minimum viewport, **each pane ≥ its stated minimum size with its header visible without interaction (usable-size, not mere presence — BF-3)**; the page never scrolls and each pane scrolls internally on overflow (Misha's explicit directive, treated as a first-class acceptance property).
**Artifacts to capture:** full-viewport screenshot showing all three panes; cross-pane refresh timing.

### s10-one-branch-multi-question — multiple questions in one thread is one branch
**Slug:** `s10-one-branch-multi-question`
**User flow:** 1. Drive a thread where Dispatch raises several questions discussed together. 2. Observe the tree reflects exactly **one** branch for that thread, not one-per-question. 3. Drive one question into a distinct sub-investigation. 4. Observe exactly **one** new branch forms (genuine divergence), not several.
**Success criteria (prose):** multi-question-in-one-thread ⇒ zero extra branches; a branch forms only on genuine conversational divergence (FR-2/FR-23, PRD S10).
**Artifacts to capture:** screenshots (one branch for the multi-question thread; exactly one new branch on divergence).

## Out-of-scope scenarios

- **Live mid-run injection/steering of a running session** — Option 2 is passive by construction; the GUI never commands Dispatch. Rationale: the adopted architecture's defining property.
- **Cloud-only threads (web/`--remote`/unattended Routines)** — no local transcript ⇒ invisible to the local reader; the GUI shows nothing false about them. Rationale: ADR-031 r7 accepted blind spot; mitigation (commit the gate into project `.claude/`) is enforcement-only, out of v1.
- **NFR-2 co-edit conflict-resolution mechanism** — only the safety property (single-event-atomic append, Pin 3b) is in scope; the resolution mechanism + conflict-unit are ADR-032's (PRD OQ-1). Rationale: deferred-with-rationale at the PRD layer.
- **`Bash(claude …)` / `/schedule` spawn surfaces** — accepted enforcement gap (ADR-031 r7 Pin 1), same class as the cloud blind spot.

## Decisions Log

### Decision: Carried plan-build defaults (Decisions 1/4/5) — Misha did not explicitly override
- **Tier:** 2 — **Status:** proceeded with recommendation; Misha relayed "taking my recommendations as defaults pending explicit override," flagged the absence of affirmative confirmation.
- **Chosen:** (1) tech stack = vanilla HTML/CSS/JS + Node localhost server + SSE; (4) enforcement hooks IN v1 but off the GUI's critical path (Phase B independent of Phase C given the file contract); (5) v1 "done" requires the real `end-user-advocate` runtime pass from a non-Dispatch standalone session.
- **Alternatives:** (1) Next.js/React (heavier deps, build step, harder clean-removal — rejected for a single-user localhost tracker) / Preact+Vite (still a build step) ; (4) hooks as a fast-follow (rejected — ADR-031 r7 treats them as part of the adopted design) ; (5) accept the self-applied substitute as the v1 bar (rejected as the default — the GUI is the entire user surface; substitute is weakest there).
- **Reasoning:** Node introduces no new runtime dependency; the file contract decouples hooks from the GUI; the acceptance bar must be strongest where the user-facing risk concentrates.
- **Surfaced to user:** 2026-05-17 in plain-text Dispatch response (the 5-decision surface); Misha answered Decisions 2 & 3 explicitly, relayed defaults stand for 1/4/5 with an explicit "flag if a load-bearing decision depends on these."
- **To reverse:** explicit Misha override on any of 1/4/5 → re-author the affected phase.

### Decision: Three-pane simultaneous layout (Decision 2 — Misha-directed)
- **Tier:** 2 — **Status:** proceeded per Misha's verbatim directive.
- **Chosen:** tree pane + actions-list pane + backlog-list pane all visible simultaneously on one screen; NOT a main-tree-with-side-surfaces shape. Supersedes old plan UX-C3.
- **Reasoning:** Misha: *"the tree and actions list and backlog list should all be visible on the same screen at the same time."*
- **Surfaced to user:** decision asked 2026-05-17; answered verbatim.
- **To reverse:** Misha redirect → re-author C1.

### Decision: Full v1 — no v1.5 deferral (Decision 3 — Misha-directed)
- **Tier:** 2 — **Status:** proceeded per Misha's verbatim directive.
- **Chosen:** all 27 active PRD FRs in v1; FR-20/21/22 (backlog) and FR-18/25 (multi-project + global tree) are IN, not deferred.
- **Reasoning:** Misha: *"build the full thing in v1."*
- **Surfaced to user:** decision asked 2026-05-17; answered verbatim.
- **To reverse:** Misha redirect → re-scope (would split Phases C4/D5 to a v1.5 plan).

### Decision: Old Option-4 plan SUPERSEDED, not patched
- **Tier:** 1 — **Status:** proceeded (reversible by one git mv).
- **Chosen:** `docs/plans/conversation-tree-ui.md` → Status: SUPERSEDED (auto-archives); this file is the re-authored Option-2 plan.
- **Reasoning:** ADR-031 r7 Consequences explicitly direct re-author-not-patch; the old plan's Goal/Scope/Tasks/SEA decompose the struck Option 4 and are materially divergent.
- **To reverse:** `git mv docs/plans/archive/conversation-tree-ui.md docs/plans/conversation-tree-ui.md` + flip Status back.

### Decision: Old plan Q2 (contested write-back) & Q3 (auto-conclude trigger) — resolved by architecture/PRD, not re-opened
- **Tier:** 1 — **Status:** proceeded.
- **Chosen:** Q2 collapses under Option 2 — a GUI-side contested resolution is just another appended event in the symmetric shared log; Dispatch reads it next time it reads the file (no "next-spawn reconciliation" since the GUI never spawns). Q3 is settled by PRD FR-7 — auto-conclude is all-items-checked only, explicitly never navigate-away.
- **Reasoning:** the adopted architecture (append-only symmetric log) and the signed-off PRD already determine both; re-opening would re-litigate settled scope.
- **To reverse:** an ADR-032 decision could change the event model; FR-7 is PRD-locked.

### Decision: DEC-A/B/C — three interface-impact decisions (DECIDED by Misha 2026-05-17)
- **Tier:** 2 — **Status:** DECIDED 2026-05-17 — Misha chose the recommended default for all three (verbatim: "DEC-A = rec … DEC-B = rec … DEC-C = rec"). These are now LOCKED inputs to Phase C/D; the standalone Phase-C session builds to these, NOT to a re-synthesized value.
- **DEC-A DECIDED = rec:** three-pane — tree pane left ~55–60% full-height; actions + backlog stacked right ~40–45%, each internally scrollable with a pinned header; minimum viewport 1440×900.
- **DEC-B DECIDED = rec:** in-GUI-persistent notifications only for v1 (not-focused limitation surfaced honestly, cloud-blind-spot style); localhost OS notification deferred to v1.5.
- **DEC-C DECIDED = rec:** backlog→Dispatch handoff = copy-context-to-clipboard + persistent `▸ ready to start in Dispatch` node badge + in-pane explainer (per BF-1).
- **DEC-A (three-pane proportions + min viewport):** recommended default — tree pane left ~55–60% full-height; actions + backlog stacked right ~40–45%, each internally scrollable with a pinned header; minimum viewport 1440×900. Alternatives: equal thirds (tree starved of width — trees want width); tabbed (violates Misha's simultaneity directive — rejected). The *structure* (overflow rule, min-viewport-exists, usable-size acceptance) is binding regardless; only the numbers are the decision.
- **DEC-B (notification channel):** recommended default — in-GUI-persistent-until-acted only for v1, not-focused limitation surfaced honestly (same treatment as the cloud blind spot); add localhost OS notification in v1.5. Alternative: localhost OS notification in v1 (more build, reaches Misha when GUI unfocused — the defer-time/parent-conclude case where it matters most).
- **DEC-C (backlog-activation handoff shape):** recommended default — copy-context-to-clipboard + persistent `▸ ready to start in Dispatch` node badge + in-pane explainer (BF-1). Alternative: also deep-link/raise the Claude desktop app (without spawning) — more integration surface, still passive.
- **Reasoning:** all three change user-observable behavior / the load-bearing layout Misha personally directed; per the rules they are his to decide, with recommendations marked so an explicit recommendation is more likely overridden than a silent default.
- **Surfaced to user:** 2026-05-17 plain-text Dispatch checkpoint; **answered 2026-05-17** ("DEC-A = rec / DEC-B = rec / DEC-C = rec"). BF-1/BF-3/BF-6 markers updated from "pending/surfaced" to DECIDED accordingly.
- **To reverse:** would require an explicit later Misha redirect + a plan revision; the standalone Phase-C session treats these as locked.

### Decision: DEC-D — §7c↔§8 contract gap resolution (DECIDED by Misha 2026-05-17 = option (d) snapshot-integrity attestation; supersedes the earlier (b))
- **Tier:** 2 — **Status:** DECIDED 2026-05-17 = **option (d)**. Resolves NL-FINDING-003 and dissolves NL-FINDING-004 (the (b)-attempt regression) and moots DEC-E/DEC-F.
- **Chosen — option (d), snapshot-integrity attestation (Misha confirmed verbatim, the 5-point rule binding on the B-DEC-D ADR-032 §7c/§8 r2 revision):**
  1. Every snapshot write appends a `{type:"snapshot-committed", hash:"sha256:<digest of snapshot bytes>", at:<ts>}` record to `events[]` — part of the atomic snapshot-commit operation, NOT a separate step.
  2. **Compaction rule stays UNCHANGED** (i.e. the original A2 §7c truncate-covered-prefix behavior — the (b) `gateRelevantRetention` carve-out is REMOVED). `events[]` is bounded by genuinely-new events + the latest `snapshot-committed` attestation (always the freshest record; survives compaction naturally — no carve-out).
  3. §8 gate: read snapshot → hash it (canonical JSON) → look up the most-recent `snapshot-committed` in `events[]` → compare. Match ⇒ snapshot verified-trustworthy, gate reads `snapshot.nodes` for branch-presence. Mismatch ⇒ snapshot torn ⇒ gate refuses + tree enters the existing A2 torn-snapshot-recovery mechanism.
  4. The state-library facade gets `attestSnapshot()`, called as part of any commit that updates the snapshot. Hash = **sha256 over the serialized snapshot bytes with canonical JSON key ordering** (determinism — load-bearing).
  5. ADR-032 §8 r2 states this as a **general primitive**: any future gate gets snapshot-trust for free via the same attestation. No per-gate compaction carve-outs ever. This is the architectural principle adopted.
- **Why (d) supersedes (b):** Misha raised a deeper architecture question; (d) is strictly cleaner. It dissolves NL-FINDING-004 (the (b) marker-vs-published-subset regression cannot arise — compaction is unchanged and §8 reads the *attestation-verified snapshot*, not events[]); it moots DEC-E (archive→compact→re-open — §8 reads `snapshot.nodes` which already contains the re-opened node) and DEC-F (promoted/backlog-activated already in `snapshot.nodes`, gate-resolvable for free). One primitive replaces three carve-out problems.
- **Earlier (b) (historical audit — superseded, NOT erased):** "compaction retains most-recent branch-opened per still-live node, generalized." Implemented as `91c86f8` (gateRelevantRetention + (b) §7c text + selftest P9/P10). That attempt FAILED both plan-mandated reviews with a severe §7a regression (NL-FINDING-004). The B-DEC-D-(d) rework REPLACES the (b)-specific code (removes `gateRelevantRetention`, reverts §7c to original-behavior + attestation) — it does not extend it.
- **Scope:** ADR-032 §7c/§8 r2 revision + `state/store.js` (remove gateRelevantRetention; add attestSnapshot + snapshot-committed append at snapshot write; original compaction) + `state/state.js` facade (`attestSnapshot()`) + `state/selftest.js` (replace (b) P9/P10 with (d) proofs) + `docs/findings.md` (NL-FINDING-003 → dispositioned-act; NL-FINDING-004 → dispositioned-act, (b)-approach abandoned). Part of Phase B task **B-DEC-D**, sequenced FIRST.
- **Surfaced to user:** (b) answered 2026-05-17; Misha then raised the deeper architecture question and **confirmed (d) 2026-05-17** with the verbatim 5-point rule above. DEC-E/DEC-F were surfaced under (b); (d) moots them (recorded, not synthesized — Misha's (d) choice obviates them).
- **To reverse:** the ADR-032 r2 revision + the store.js (d) change is one logical change-set; reversible by reverting it.

### Decision: Execution-mode = Option 3 (DECIDED by Misha 2026-05-17)
- **Tier:** 2 — **Status:** DECIDED 2026-05-17. Phase B runs HERE (this Dispatch env, via the proven orchestrator-mediated loop). Phases C/D/E run from a **standalone non-Dispatch session** where the canonical agents (plan-phase-builder, end-user-advocate, nested Task, SendMessage) exist. **Confirm cleanly at the Phase-B → Phase-C boundary** (write a DONE + handoff doc with the branch tip; the standalone session picks up from the plan + evidence + handoff doc).
- **Reasoning:** Phase B is decision-independent harness-infrastructure structure tolerant of the degraded loop; Phases C/D need the canonical GUI/advocate agents and are where DEC-A/B/C land; Phase E's runtime-advocate acceptance bar is unsatisfiable in Dispatch (HARNESS-GAP-34).
- **To reverse:** Misha redirect ("continue all here" / "switch now").

## Pre-Submission Audit

S1 (Entry-Point Surfacing): swept the plan for behavior-change verbs (add/emit/write/append/render/conclude/defer/archive/promote/notify); every behavior change in §1–10 is cited at a Task + a Files-to-Modify entry (Phase A↔§3/§8 state contract, Phase B↔§4/§5 enforcement, Phase C↔§1/§6 GUI panes, Phase D↔§2/§7 tracker behaviors, Phase E↔§1/§10 acceptance); 0 stranded behaviors.
S2 (Existing-Code-Claim Verification): swept existing-code claims — (a) ADR-031 r7 ACCEPTED + 3 pins folded @ 8275d31 (verified against the ADR header + Plan-safety pins section), (b) PRD at docs/prd.md with 7 sections + prd-validity-reviewer PASS @ 8b1453e (verified against the ledger + PRD), (c) `bug-persistence-gate.sh`/`teammate-spawn-validator.sh` precedents + `dag-review-waiver-gate.sh` marker path `.claude/state/dag-approved-<slug>-*.txt` (verified by reading the hook), (d) `plan-reviewer.sh` takes a file-path arg (verified `PLAN_FILE="$1"`). The `tool_name`-for-MCP claim is explicitly marked an Assumption re-verified at B0, not asserted.
S3 (Cross-Section Consistency): swept "passive/never spawns/read-mostly/symmetric" claims — the Option-2 invariant (GUI never spawns/steers) is stated identically in Goal, Scope OUT, UX superseded-items, Edge Cases, s3/s6 acceptance, and §3/§5; 0 contradictions (the old plan's spawn-orchestration is the struck-Option-4 reasoning, removed wholesale, not contradicted in place).
S4 (Numeric-Parameter Sweep): swept params [NFR-3 <100 branches, p95 <150ms; waiver <1h + ≥1 line; last-N retention; N=3 FR-2 fixture]. <100/150ms appear only by reference to PRD NFR-3 (no comparative-without-arithmetic claim authored — values are PRD-cited, not re-derived). Waiver <1h/≥1-line and N=3 each appear once, consistent. No engineered SLA asserted (SM-2 is "Claude's natural response time, expected sub-minute" per PRD — quoted, not re-computed).
S5 (Scope-vs-Analysis Check): swept Add/Implement/Build/Write verbs against Scope OUT — live-injection/steering, cloud-thread visibility, NFR-2 resolution-mechanism, `Bash(claude…)`/`/schedule` appear ONLY as explicitly-OUT or accepted-gap; 0 in-scope prescription contradicts the OUT list; FR-19 spawn guardrail explicitly removed (recorded in UX superseded), not silently carried.

## Definition of Done
- [ ] All tasks checked off (by task-verifier only; after plan-reviewer PASS + systems-designer PASS + ux-designer folded + DAG waiver)
- [ ] All property/self-test suites pass; functionality-verifier PASS on every runtime task
- [ ] `end-user-advocate` runtime PASS artifact for the in-scope scenario set (standalone-session default; HARNESS-GAP-34 risk dispositioned)
- [ ] ADR-032 authored + `docs/DECISIONS.md` indexed (A1)
- [ ] Both enforcement hooks `--self-test` green + wired two-layer (template↔live byte-identical) + arch-doc updated (B3)
- [ ] Three-pane simultaneous-render invariant verified (s9)
- [ ] SCRATCHPAD.md updated; completion report appended; Status flipped (close-plan procedure)

## Systems Engineering Analysis

### 1. Outcome (measurable user outcome, not output)
- At any later point regardless of elapsed gap, 100% of branches that were open are present and surface-able in the GUI without reading scrollback (PRD SM-1, FR-24).
- Median time from "I want to continue X" to "X's context is surfaced and I can act on it (in Dispatch)" is sub-minute and does not grow with dormancy (PRD SM-2 — bound is Claude's natural response time, not an engineered SLA).
- 100% of items needing Misha's follow-up appear in the actions-list pane within one state refresh of being raised (PRD SM-3).
- A Dispatch-installed-but-unused module fires zero module-originated interruptions (PRD SM-6); module-absent vs module-disabled hook-firing diff is empty (NFR-8).
- Plate test: Misha's plate is lighter because no open thread silently disappears, no stale decision rots unseen, and the backlog is captured instead of trapped in his head — not "a tree UI exists."

### 2. End-to-end trace with a concrete example
- T=0 Misha drives a local Dispatch session "investigate harness gap G".
- T=8min Dispatch (orchestrator, harness-bound) appends `branch-opened: G` then `decision-raised: G-d1, G-d2`, then `question-raised: G-q-deepdive`; each is a single atomic append to the well-known JSON state file; a snapshot is written; the PreToolUse `conversation-tree-state-gate.sh` had ALLOWED the work because the state file is fresh and names branch G.
- T=session-end `conversation-tree-stop-gate.sh` scans the transcript: spawns/Task/Agent each have a corresponding state write ⇒ ALLOW.
- T+1day Misha opens `http://localhost:<port>`; the GUI reads the snapshot (snapshot valid ⇒ no log replay needed), renders all three panes: tree shows G with d1/d2 + open q-deepdive; the actions pane lists d1,d2,q-deepdive each breadcrumbed to G; the backlog pane shows his other captured items.
- Misha clicks `G-q-deepdive`: the tree pane surfaces parent chain (root→G→q-deepdive) + sub-branches + open items. **No session is spawned.** He continues the actual conversation in Dispatch as normal; Dispatch's next writes append more events; the GUI reflects them on next read / SSE push.
- No step requires the GUI to read or inject into a *running* session — every cross-boundary transition is a file the GUI reads and an event Dispatch (or the GUI) appends.

### 3. Interface contracts between components
| Producer | Consumer | Contract |
|---|---|---|
| Dispatch orchestrator | JSON state file | Appends single atomic event records (Pin 3b) + periodic snapshots; schema = ADR-032; `schema_version` present; writes a state entry naming the branch before any matched spawn (B1-enforced). |
| GUI (Misha) | JSON state file | Appends single atomic event records for GUI mutations (symmetric FR-11); never hand-edits raw state; reads snapshot, falls back to log replay on torn/stale snapshot (Pin 3a). |
| JSON state file | GUI reader | snapshot + log; reader refuses unknown major `schema_version` with a distinct message (Pin 2); torn snapshot ⇒ replay log (mandatory). |
| `conversation-tree-state-gate.sh` | spawn attempts | PreToolUse on the enumerated matcher; Pin-2 error partition; bootstrap exemption; fresh-waiver release-valve. |
| `conversation-tree-stop-gate.sh` | session end | Stop; transcript-scan; spawn-without-write ⇒ BLOCK + escape-hatch marker. |
| Module | Harness core | Only the enumerated seam (two hooks + the read-only file contract); zero required core Stop/PreToolUse coupling beyond the two new opt-in hooks; module-absent == module-disabled (NFR-8). |

### 4. Environment & execution context
- Localhost-only Node server (NFR-5 — no inbound LAN port); single user; single machine; Windows (Misha's env). Static HTML/CSS/JS front-end (no build step). SSE for push-on-change.
- State file location resolved by ADR-032 (per-project under the repo + a global path — FR-18/FR-25).
- Hooks run in the local Dispatch session's harness context (`~/.claude/` fires on local Dispatch — ADR-031 r7; B0 re-verifies the `tool_name`-for-MCP sub-assumption).
- No credentials in the state file (NFR-5). No third-party network egress. Node already present in the harness toolchain (no new runtime dep).
- Module enable/disable = presence/absence of the two hook wirings + the server; disabled = byte-identical core hook behavior (NFR-8, SM-6).

### 5. Authentication & authorization map
- No auth: single local user; the Node server binds to localhost only.
- The GUI holds no credentials and invokes no spawn path (Option 2 — passive). It never authenticates anything; it reads a local file and appends events to it.
- Dispatch's own Claude Code auth is unchanged and untouched by the module (the module never spawns or steers Dispatch).
- State-file credential-pattern scan = 0 (NFR-5 acceptance). No new token/API surface introduced anywhere in the module.

### 6. Observability plan (built before the feature)
- The Dispatch lifecycle-annotation trail (FR-12) is the primary observability surface; tree change history is reconstructable from annotations alone (NFR-7).
- Every state mutation (GUI or Dispatch) is an append-only audit-log entry (NFR-7); current state across all trees + backlog is reconstructable from audit log + annotation trail (NFR-7 acceptance).
- The GUI surfaces a visible "last read from state at <ts>" indicator so staleness is observable, not silent; the corruption banner (UX-I4) surfaces parse/torn-snapshot recovery non-silently.
- Both enforcement hooks emit a stderr decision line (ALLOW/BLOCK + reason) on every fire so integration failures are diagnosable from logs alone.

### 7. Failure-mode analysis per step
| Step | Failure | Symptom | Recovery | Escalate |
|---|---|---|---|---|
| Dispatch append | crash mid-write | partial event | single-event atomic append (Pin 3b) — reader sees N or N+1 whole events | n/a (by design) |
| Snapshot write | torn snapshot | stale/partial snapshot | reader detects via validity marker, replays event log (Pin 3a) | corruption banner if log also bad |
| All versions bad | total corruption | cannot load any version | explicit "could not load from any saved version" + audit-log path (UX-I4) | finding per diagnosis loop |
| Spawn w/ stale state | gate fires | spawn BLOCKED | Pin-2 partition (closed) + fresh-waiver release-valve | recurring → finding |
| Spawn, no prior, no file | bootstrap | spawn ALLOWED | Pin 2a bootstrap exemption (a tree must be able to start) | n/a |
| Stop w/ spawn no write | stop-gate fires | session-end BLOCKED | remediation message + escape-hatch marker | recurring → finding |
| Cloud thread | no local transcript | thread invisible to GUI | accepted blind spot; GUI shows nothing false | document if cloud usage grows |
| Node bound session gone | missing session | node "session unavailable" | NFR-9 degrade; still navigable (UX-I5) | n/a |
| Defer scheduled check | check misses the time | no highlight fired | item is still visibly tagged (FR-13 stays-visible) — never lost | manual clear always works |

### 8. Idempotency & restart semantics
- Single-event-atomic append ⇒ a re-applied append is detectable/idempotent at the event-id level (ADR-032 fixes the id field); the reader is pure (no in-memory authority — GUI restart re-reads).
- Torn snapshot ⇒ deterministic log-replay reconstruction (Pin 3a); compaction is idempotent (a fresh snapshot supersedes+truncates only the prefix it provably covers — Pin 3c).
- Both hooks are stateless w.r.t. prior runs except the per-session spawn marker + the <1h waiver TTL (mirrors `bug-persistence-gate.sh`); re-run with the same inputs ⇒ same decision.
- A partially-written Dispatch event is never observed (atomic append); a partially-written snapshot is never trusted (validity marker).

### 9. Load / capacity model
- Scale is a PRD-given assumption, not a derived capacity bound: PRD NFR-3 fixes the realistic ceiling at fewer than one hundred branches total across all per-project trees + the global tree, with backlog/action lists trivially small at that scale. No arithmetic applies here because nothing is computed against a budget — the FM-013/FM-014 concern (asserting a capacity comparison without showing the math) is N/A; this is a stated input quoted from the PRD, not an asserted comparison. PRD NFR-3 also sets the p95 interaction-latency target at 150 ms and requires no pruning tier at v1 scale (NFR-3 supersedes the prior larger-node framing).
- Bottleneck: the GUI tree render — bounded by the <100-branch ceiling, hand-rolled SVG/DOM is viable at that bound (minimal-dependency principle; one focused vetted dependency surfaced as an in-flight decision only if a specific interaction proves a time-sink).
- State-file growth bounded by the compaction trigger (Pin 3c) across the FR-24 "a minute or a month" horizon; the audit log is retained separately (NFR-7).
- No network/API rate concern: localhost, no external calls, no spawn path (Option 2 passive).

### 10. Decision records & runbook
- Decision records: ADR-031 r7 (architecture, ACCEPTED); ADR-032 (state schema field layout, Task A1); the Decisions Log above (carried defaults; three-pane; full v1; supersede; Q2/Q3 resolved).
- Runbook — *GUI shows stale tree*: (1) check the "last read at <ts>" indicator, (2) check the latest snapshot validity marker / whether log-replay engaged, (3) reload the page (reader is pure — re-reads).
- Runbook — *GUI shows corruption banner*: (1) read which versions failed to parse, (2) confirm last-good rendered, (3) if all-versions-bad, follow the audit-log path in the banner; file a finding per the diagnosis loop.
- Runbook — *spawn unexpectedly blocked*: (1) read the gate's stderr decision line, (2) match it to the Pin-2 partition cell, (3) apply the named remediation (fresh state write, or a substantive <1h waiver) — diagnose before bypass per gate-respect.
- Runbook — *branch didn't auto-conclude*: (1) verify ALL checklist items checked in state, (2) check for a contested item (contested counts as NOT checked by design — D2).
- Escalation: recurring corruption-banner or gate-block events become `docs/findings.md` entries per the diagnosis "encode the fix" loop.
