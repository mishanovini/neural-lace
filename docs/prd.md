# PRD: Conversation Tree Management UI

<!--
Working name only. Per ~/.claude/CLAUDE.md "Naming & Identity", the product
is NOT named until Misha names it; "Conversation Tree Management UI" is a
descriptive placeholder, not a brand.

Optional Neural Lace harness module. Canonical PRD at docs/prd.md
(Decision A RESOLVED to option (a), 2026-05-15). Phase-0 initially leaned
toward docs/prd-conversation-tree.md (honest naming over gaming the path).
That reversed when the prd-validity-gate became mechanically live at
plan-write time: the gate resolves any non-carve-out `prd-ref:` to
docs/prd.md, the harness-development carve-out would be a FALSE claim for a
user-facing product, and `gate-respect` forbids both gaming the carve-out
and `--no-verify` bypass. Conforming to the single-PRD-per-project
convention is the gate's own named remediation AND makes the mechanism
genuinely fire — which is the explicit point of this exercise. This module
is the first genuine user-facing product surface inside the harness repo;
that one-product-PRD framing is accepted. Substance review via the
`prd-validity-reviewer` agent (passed at 8b1453e). Resolution recorded in
ADR-031 (OQ-9 / Consequences).

Produced via the Build Doctrine guided-PRD-intake protocol
(build-doctrine/doctrine/05-implementation-process.md, Stages A–F). Stage
provenance is annotated inline so the process is visible, not a black box.
-->

## Problem

<!-- Stage A — Problem framing. -->

**Root problem (Misha's framing, Stage A — verbatim basis).** Conversations between Misha and Dispatch are **inherently multi-threaded and branch off in multiple directions, yet are managed as if they are a single thread.** The current workflow does not make it easy to keep track of what was previously being discussed, what still needs to be discussed further, what decisions still need to be made, and what questions have not been answered. A specific, concrete friction compounds this: **Claude (Dispatch) often asks several questions at a time, but Misha's response to any one of them requires conversation — not a bulk answer — so a multi-question turn is unmanageable in a single linear thread.** The decision to go deep on one question necessarily defers the others, and there is no surface that holds the deferred ones as live, trackable branches.

In Misha's words: *"conversations are multi-threaded and branch off in multiple directions, yet are managed as if they're a single thread … Claude often asks me several questions at a time and my response requires conversation. It's not easy to manage a conversation like this around multiple questions simultaneously."*

**Second root dimension (Misha's framing, Stage B — verbatim basis): the unmanaged, capacity-limited mental backlog.** The problem is not only managing conversations *already in flight* — it is also the **set of things Misha wants to work on with Claude Code but has not yet started**. Today that backlog lives only in his head, and it is capacity-limited: it is challenging to put enough thought into each prospective item to start parallel sessions simultaneously, so items queue mentally instead of being captured, contextualized, and parallelized. The solution should also be a to-do/backlog surface where Misha enters and tracks these items, adds context to them, and moves them into sessions — with each item's goals and progress represented in the same tree structure as it advances. Enabling **more parallelization** is an explicit primary goal, not a side effect.

In Misha's words: *"I keep a task list in my head of all the things I want to be working on with Claude Code because it's challenging to put enough thought into each one to start parallel sessions simultaneously. I imagine this solution as also being a to-do list where I can enter and track the items I need to work on with Claude Code. This solution should help me manage those items and move them into sessions, and manage the conversations and decisions of each of them in this tree structure as they go. This tree structure seems to be the most logical way to represent the goals and progress being made toward each."*

So the problem is structural, not cosmetic, on **two dimensions**: (1) the medium (a single linear chat) cannot represent the actual shape of in-flight work (a branching tree of open threads and pending Q&A); and (2) there is no durable surface for the not-yet-started backlog, so prospective work stays trapped in a capacity-limited mental list instead of being captured and parallelized. Everything below is a **consequence** of that two-part root mismatch.

**Consequences of single-thread management of a multi-threaded reality.** The branching work-tree today exists in only two volatile places — Misha's head and the agent's ephemeral context — neither of which survives a session boundary. That produces:

- **Lost threads.** When a session closes, open branches that weren't explicitly resumed evaporate. Misha has no durable surface that says "these branches are still open and waiting on you."
- **Stale decisions.** A decision Misha was asked to make several sessions ago is still pending, but nothing surfaces it; it silently rots until the work it gated is irrelevant.
- **Half-built efforts pile up.** A branch gets most of the way done, the session ends, and the remainder is invisible until someone re-derives it by reading scrollback — the exact failure mode the harness's SCRATCHPAD/plan/backlog discipline fights at the code level, with no equivalent at the *conversation-tree* level.
- **No "waiting on me" surface.** Misha cannot answer "what decisions are blocked on my input?" or "what questions are still unanswered?" without manually reconstructing the tree from memory and chat history. The information exists but is not *surfaced* and not *linked back to the structure that produced it*.
- **Multi-question turns are unmanageable.** A single Dispatch turn raising several questions forces Misha to either answer shallowly in bulk (which his answers don't support — they require conversation) or answer one well and silently drop the rest. Today there is no place for the dropped ones to live as tracked, resumable branches.
- **The prospective backlog is trapped in his head and capacity-limited.** Items Misha wants to work on with Claude Code queue mentally because contextualizing each well enough to start a session is effortful; the result is fewer parallel sessions than he could run, and prospective work that is never captured at all.

Misha explicitly does not do manual git/code work — the system and Dispatch drive execution. So the problem is not "give Misha tools to manage code"; it is "give Misha a durable, visible, navigable model of (a) the *conversation tree* of in-flight work — its open threads, pending decisions, and unanswered questions — and (b) the *backlog* of not-yet-started items he wants to work on with Claude Code, with context attachable and items movable into sessions — both represented in the same tree structure, with the things he is the bottleneck on surfaced and linked back to where they came from, in service of more parallelization."

**Invisible-knowledge surfaces (N-R-B prompt — user-confirmed at Stage A).** The following three were proposed by the AI and **explicitly confirmed by Misha** as accurate (not AI-inferred-and-unconfirmed):

1. **Node granularity is a tacit heuristic, not a rule.** "A node is roughly the same criteria I'd use to spawn a separate code session" — a coherent piece of work, not a per-message unit. *(Refined at Stage B: the branching trigger is a conversation going off in a new direction — see FR-2. The earlier "goes deep on a subset / doesn't answer all" phrasing here was Misha-corrected; the "cost of a separate code session" heuristic stands.)* The model must encode this branching trigger, not invent its own granularity.
2. **Implicit Dispatch check-offs are currently untrusted, and that distrust is the feature.** The friction isn't "Dispatch doesn't track completion"; it's "when Dispatch silently considers something done, Misha has no way to see it or contest it." The agree/disagree-both-directions requirement exists *because* implicit completion is invisible and unilateral today.
3. **The stale-and-forgotten friction is real but the wanted remedy is far narrower than a naive design would build.** The actual need is minimal: alert a parent branch *only* when one of its children concludes, plus let Misha defer his own action items with an optional condition. An aggressive nag/alert engine is a known anti-pattern Misha pre-empted.

## Scenarios

<!-- Stage B — Scenarios and stories. Primary + edge + explicit not-scenarios. -->

### Scenario 1 — A request branches and the branches persist (primary)

Misha asks Dispatch to investigate a harness gap. Dispatch works, then surfaces three decisions. Misha answers two and the conversation goes deep on the third. The tree now shows: a parent node (the original request), an open child branch for the deep-dive, and the two answered decisions auto-checked on the parent. **Whether Misha continues immediately or walks away and comes back a day later, nothing changes from his perspective** — the open deep-dive branch is right there, exactly as it was, with no scrollback to read and no sense that "a session ended." Elapsed time is invisible; everything persists (NFR-11).

### Scenario 2 — "What's waiting on me?" (primary)

Misha opens the decision-list side surface. It shows every unanswered decision across the entire tree, each linked back to the node that raised it. He clicks one; the GUI focuses the conversation at that node with that branch's context reloaded. He answers. The decision auto-checks and disappears from the list.

### Scenario 3 — Click a node to resume a dormant branch (primary)

A branch has not been touched in a while (the elapsed time is irrelevant — a minute or a month is the same to Misha). He clicks its node. The branch's context reloads (the parent question, the decisions raised, the work done). He types a follow-up at that node. The previously-focused leaf auto-concludes (with the ability to re-open it). The clicked branch is now the active conversation context. There is no "resuming a session" moment — the branch was simply always there, persisted.

### Scenario 4 — A branch auto-collapses when complete (primary)

A branch has a checklist of 3 decisions and 2 actions. As Dispatch completes actions and Misha answers decisions, items auto-check. When the last item checks, the branch visually collapses (still expandable). Its parent receives a single alert: "child branch *Y* concluded — resume?"

### Scenario 5 — Agree/disagree on a check-off, both directions (primary)

(a) Dispatch implicitly marks "wire the hook" done. Misha disagrees: he un-checks it and annotates "not done — the live mirror wasn't synced." The item reopens with his note attached, **and that annotation can itself become a conversation thread** (Stage B, Misha-confirmed) — i.e., un-checking with a note can open a discussion branch about *why* it isn't done, not just leave a static label. (b) Misha explicitly marks "Phase 2 complete." Dispatch disagrees and surfaces "you marked Phase 2 complete but the acceptance scenario for FR-7 was never exercised." The conflict is visible, not silently resolved either way.

### Scenario 6 — Conclude a branch, kick off a session (primary)

A branch's decisions are answered. Misha concludes it. Concluding **does not necessarily start a new Dispatch session** (Stage B, Misha-confirmed): the gathered context can EITHER (i) prompt a brand-new session, OR (ii) be fed to an *already-running* session to let it continue. Moreover, a session may be allowed to **start work with only a subset of its questions answered** while the still-open questions continue to be discussed in the GUI as live branches — partial-answer parallelization. A question raised by a running session appears as a new child node under the branch that spawned it. The explicit primary goal of this scenario is **more parallelization** — enabling concurrent progress, not serializing it behind full answer-sets.

### Scenario 7 — Defer my own action item with a condition (edge)

Misha has an action item "decide on hosting provider." He can't decide yet — it depends on a quote arriving. He defers it with the condition "after 2026-05-20." It disappears from the active action list and reappears (or is re-surfaced) when the condition resolves.

### Scenario 8 — Dispatch writes the state while Misha is editing it (edge)

Dispatch is mid-work writing branch annotations to the JSON state file. Simultaneously, Misha drags a node to re-parent it in the GUI. Both writes target the same state file. The system must not corrupt the tree or silently drop either change.

### Scenario 9 — Backlog item → start a session (primary; Stage B, Misha-confirmed)

Misha adds an item to the **backlog** — a thing he wants to work on with Claude Code that has not been started — optionally with a short note. It sits in the backlog list (a surface distinct from the action-items list, per OQ-10 resolved). Later he selects it and starts a Dispatch conversation about it; the item becomes a **root node** of a new tree. Nothing about this differs whether he activates it minutes or weeks after capturing it (NFR-11).

### Scenario 10 — Partial-answer parallelization (primary; Stage B, Misha-confirmed + refined)

A running conversation has several open questions. Misha does not have to answer them one-branch-at-a-time: **multiple questions can be discussed within the same conversation thread** — that is still one branch, not many. He gives enough answers for the work to make progress, and the session **runs in parallel with those partial answers** while the remaining questions stay under open discussion in the same thread. A **new branch forms only if the conversation actually goes off in a new direction** (e.g., one question opens a sub-investigation that warrants its own thread) — not merely because a question is still open. The point is more concurrent progress, not a branch per question.

### Scenario 11 — Add context to a backlog item before activating (primary; Stage B, Misha-confirmed)

Before turning a backlog item into a conversation, Misha selects it and attaches context — research notes, files, prior decisions. When he later activates it, that context is carried into the conversation that the item's root node opens. (Misha noted he has not fully thought through the context-attachment mechanics; this scenario fixes the user-observable intent, not the mechanism — mechanics are an Open Question for later stages.)

### Explicitly NOT scenarios

- **Misha hand-edits the JSON.** The JSON is an internal representation. Every manipulation Misha does is through the GUI (drag-drop, check-off, promote-to-branch). He never opens the file.
- **Multiple humans collaborating on one tree.** Single-user. No presence, no shared cursors, no per-user permissions.
- **The GUI as a code editor / git client.** Misha does not do manual git/code work; the GUI never shows a diff editor or a commit UI.
- **A *generic* project-management tool.** *(Reconciled at Stage B.)* The system IS a backlog/to-do surface for Claude-Code work items (Scenarios 9/11) — but it is not a Jira/Linear/Asana: no sprints, story points, assignees, arbitrary ticket types, or due-date workflows. It models exactly one thing — Claude-Code work items and the conversation tree they grow into.

## Functional requirements

<!-- Stage C — Functional requirements. Each FR is falsifiable. Bracketed
items marked (GAP) are requirements the scenarios imply that Misha did NOT
state — surfaced per the intake protocol's "AI surfaces what users miss." -->

- **FR-1. Tree model.** The system maintains a strict tree (each node has exactly one parent). The root is a top-level Misha request. Acceptance: any node has a single resolvable parent path to the root; no node has two parents.
- **FR-2. Node granularity — branching is about CONVERSATIONS, not questions/decisions (Stage B, Misha-corrected).** A branch forms when **a conversation goes off in a new direction** — not per-question, not per-decision, not per-message. Multiple questions or decisions discussed *within one conversation thread* are **one branch, not many**. In Misha's words: *"we don't necessarily need a separate branch for every question. we often discuss multiple questions at the same time. the branching concept is branching of conversations, not specifically questions or decisions or anything specific like that."* Heuristic for "is this a new branch?": roughly the cost/coherence of a separate code session — not per-question granularity. Acceptance: discussing several questions in one thread produces ZERO additional branches; a branch is created only when the conversation demonstrably diverges into a distinct line of work (e.g., one point opens a sub-investigation warranting its own thread). This supersedes the earlier Stage-A "goes deep on a subset / doesn't answer all" trigger; the "cost of a separate code session" heuristic from invisible-knowledge surface #1 is retained, the per-decision-subset trigger is not.
- **FR-3. Manual cross-links.** Beyond the strict parent tree, Misha can create non-hierarchical cross-links between nodes via tags. Acceptance: a tag applied to two nodes renders a visible non-tree association without changing either node's parent.
- **FR-4. Decision-list side surface.** A view listing every unanswered decision across the whole tree, each linked back to its originating node. Acceptance: answering a decision (anywhere) removes it from this list within one state refresh; clicking an entry focuses the conversation at its node.
- **FR-5. Action-list side surface.** A view listing every open action item across the whole tree, each linked back to its node. Acceptance: completing an action removes it from this list within one state refresh.
- **FR-6. Click-to-focus.** Clicking any node makes that node's branch the active conversation context and reloads that branch's context (format per OQ-3). Acceptance: after a click, a follow-up the user types is threaded under the clicked node, not under the previously-active node.
- **FR-7. Auto-conclude on navigate-away.** When Misha navigates focus away from the current leaf, that leaf auto-concludes, with an explicit affordance to re-open it. Acceptance: navigating away marks the leaf concluded; a re-open control restores it to active without data loss.
- **FR-8. Branch checklist + auto-collapse.** Each branch carries a checklist of its decisions and actions. Items auto-check when answered/done. When all items are checked, the branch collapses visually but remains expandable. Acceptance: checking the final item collapses the branch; expanding it shows full history.
- **FR-9. Bidirectional check-off override.** (a) An implicit Dispatch check-off can be un-checked or contested by Misha with an attached note. (b) An explicit Misha check-off can be contested by Dispatch, which surfaces a specific "X marked complete but Y may not be covered" message. Acceptance: both override paths produce a visible contested state that neither side silently resolves.
- **FR-10. Return-to-parent.** A concluded child branch surfaces a single alert on its parent ("child *Y* concluded — resume?"). Misha can also navigate to any parent manually via the tree. Acceptance: child conclusion produces exactly one parent alert (not a stream); manual tree navigation to a parent always works regardless of alerts.
- **FR-11. JSON state as source of truth, bidirectional.** Dispatch writes a structured JSON state file as it works. The GUI reads it and lets Misha modify it (drag-drop re-parent, check-off, promote-node-to-branch). Misha never edits JSON directly. Acceptance: a GUI edit is reflected in the JSON; a Dispatch JSON write is reflected in the GUI; the JSON is never shown to or hand-edited by Misha.
- **FR-12. Dispatch state-author annotations.** Dispatch emits explicit lifecycle markers as it works: "opening child node: X", "concluding branch: Y, returning to Z". These are the model's authorship trail. Acceptance: every node creation and branch conclusion the system performs has a corresponding Dispatch annotation; a session's annotations reconstruct the tree changes it made.
- **FR-13. Defer-my-action with condition.** Misha can defer one of his own action items with an optional condition (date/time/event). Deferred items leave the active action list and return when the condition resolves. Acceptance: a deferred item is absent from the active list while deferred and present again after the condition resolves (resolution mechanism per OQ-5).
- **FR-14. Conclude-branch-spawns-session.** Concluding a branch can kick off a Dispatch session whose prompt is the branch's gathered decisions. A question from a running session appears as a new child node under the branch that spawned it. Acceptance: branch conclusion with the spawn option produces a session whose prompt contains the gathered decisions; a session question creates exactly one child node under the correct parent.
- **FR-15. (GAP) Session ↔ branch binding.** Every branch is bound to one or more harness sessions; clicking a node loads that branch's conversation context. Acceptance: a branch with zero bound sessions is a valid (not-yet-started) state; a branch with bound sessions resolves each to a loadable context.
- **FR-16. (GAP) Optional-module enable/disable.** The module is installable and removable without affecting harness behavior. Disabling it leaves no required hook, no broken reference, and no orphaned state read. Acceptance: with the module disabled, a normal harness session runs identically to a harness without the module ever installed.
- **FR-17. (GAP) Empty / first-run state.** On first run with no tree yet, the GUI shows a coherent empty state explaining what populates the tree, not a blank screen. Acceptance: a fresh install with no state file renders an informative empty state, not an error.
- **FR-18. (GAP) Tree scope.** The system defines whether a tree is per-project (one tree per repo) or global across all Dispatch work. (Surfaced as OQ-6; the FR is that the answer is explicit and the model enforces it, not that a particular answer is chosen here.)
- **FR-19. (GAP) Spawn guardrail.** Because FR-14 can auto-create Dispatch sessions, the system requires an explicit Misha confirmation before a branch-conclusion spawns a session, unless Misha has pre-authorized auto-spawn for that branch. Acceptance: no session is spawned by branch conclusion without either a per-spawn confirmation or a recorded pre-authorization.

## Non-functional requirements

<!-- Stage D — every category gets a stated requirement, an explicit N/A
with rationale, or a deferred-with-rationale open question. -->

- **NFR-1. State durability.** The JSON state file is the crown-jewel artifact. Every write is atomic (write-temp-then-rename) and the prior version is recoverable. Target: zero observed tree-corruption events; last-N versions retained for rollback. A corrupt or unparseable state file degrades to "show last good version + surface the corruption", never to data loss or a blank tree.
- **NFR-2. Co-edit safety.** Concurrent Dispatch-write + Misha-GUI-edit to the same state must not corrupt the tree or silently drop a change (the FR-11/Scenario-8 case). Target: last-write-wins per *field* with optimistic concurrency; a clobbered field surfaces a visible "Dispatch also changed this" notice rather than silently overwriting. (Mechanism is OQ-1; the NFR is the safety property, not the mechanism.)
- **NFR-3. Tree-render performance.** The tree remains interactive (pan/zoom/expand/collapse, click-to-focus) at the scale a year of Dispatch work produces. Target: p95 interaction latency < 150 ms at ≥ 500 nodes; the design must state a node-count ceiling and a pruning/archival story (see OQ-7).
- **NFR-4. State read/write latency.** A Dispatch annotation write and the GUI reflecting it: target < 1 s end-to-end for the snapshot model, or < 250 ms for the real-time model (the choice is OQ-2; the NFR is that whichever is chosen has a stated, testable bound).
- **NFR-5. Security / locality.** The module is single-user and local. The GUI binds to localhost only; no remote network surface is exposed. The JSON state contains no credentials, tokens, or secrets — only conversation-tree structure and references. Acceptance: a port scan from another host on the LAN finds no listening GUI port; a scan of the state file matches zero credential patterns.
- **NFR-6. Accessibility.** Single-user personal tool, but the tree and lists must be keyboard-navigable (tab/arrow to traverse nodes, enter to focus, escape to collapse) and not rely on color alone to convey state (concluded/contested/deferred each have a non-color signal). Full WCAG-AA conformance is **explicitly N/A** (rationale: single known user, no external/public surface) — keyboard + non-color-signal is the scoped subset that matters.
- **NFR-7. Observability.** The Dispatch annotation trail (FR-12) *is* the primary observability surface — the tree's change history is reconstructable from annotations alone. Additionally, every state mutation (GUI or Dispatch) appends to an append-only audit log. Acceptance: given only the audit log + annotation trail, the current tree state is reconstructable.
- **NFR-8. Harness coupling ceiling.** The module touches the harness only through a documented, minimal integration surface (session-binding, context-load, session-spawn, question-injection). It introduces no required hook into the core Stop/PreToolUse chains. Acceptance: the integration points are enumerable on one page; removing the module removes exactly those points and nothing else.
- **NFR-9. Reliability of session integration.** If a harness session the tree references no longer exists (cleaned up, crashed, archived), the node degrades to "session unavailable — context may be partial" rather than erroring. Acceptance: a node bound to a missing session still renders and still allows manual navigation.
- **NFR-10. Internationalization.** Explicitly **N/A** — single English-speaking user, no localization requirement. Stated to close the category, per intake protocol (no silent skips).
- **NFR-11. Continuity (HARD CONSTRAINT, Stage B, Misha-stated).** User-perceived state is **identical regardless of elapsed time between interactions**. There is no user-visible concept of "the next time you sit down to work," no session-start moment, no "resume" affordance, no scrollback to re-read — responding immediately vs. walking away and returning tomorrow changes nothing the user sees. In Misha's words: *"there should not be any concept of 'the next time you sit down to work'. there's nothing about this that should be different whether I respond immediately or if I walk away and come back tomorrow. everything should persist."* Implementation MAY use session boundaries underneath, but they MUST be invisible at the UX layer — including **no user-visible session-startup latency and no per-interaction session authorization** when continuing an existing branch. **This is a binding UX constraint on the architecture choice (ADR-031):** Option 4's "fresh bound session per click" is an acceptable *implementation* only if the spawn is invisible to Misha (seamless continuation, no perceptible startup gap, no approve-this-session prompt for continuing an existing conversation). If Option 4 cannot satisfy NFR-11, the architecture choice is reopened. Acceptance: a click that continues an existing branch presents no session-lifecycle UI and no latency Misha would attribute to "starting something"; the only spawn-confirmation permitted is the FR-19 guardrail for *concluding-into-a-new* spawn, never for *continuing* an existing branch.

## Success metrics

<!-- Stage E — every metric passes the plate test (outcome, not output).
"Is Misha's plate lighter when this finishes?" -->

- **SM-1. Zero lost threads across any elapsed time gap.** At *any* later point — seconds or weeks after the work paused, with no user-visible "session" notion (NFR-11) — 100% of branches that were open are still present and click-to-focus-able without reading scrollback. Measured via: after an arbitrary elapsed gap (including across the technical session boundaries the implementation uses internally), every branch the audit log recorded as open is present in the tree and focusable. Plate test: Misha's plate is lighter because no open work silently disappears and elapsed time costs him nothing. (Outcome, not "we built a tree view.")
- **SM-2. Time-to-resume a dormant branch.** Resuming a branch untouched for an arbitrary period takes ≤ 3 GUI interactions (find it → click → it's focused with context) and zero scrollback reading — and the interaction count does not change with how long it was dormant. Measured via: instrumented interaction count + a self-report that no chat history was manually re-read, sampled across short and long dormancy. Baseline today: unbounded (often a full scrollback re-read). Plate test: lighter — the re-derivation cost is eliminated and does not grow with elapsed time.
- **SM-3. Decision latency visibility.** 100% of decisions Dispatch raises appear in the decision-list surface within one state refresh of being raised, and carry a visible age. Measured via: audit-log timestamp of decision-raised vs. decision-appearing-in-list. Plate test: lighter — Misha sees the stale-decision pile instead of discovering it by accident three sessions late.
- **SM-4. Contested-state never silently resolves.** Of all bidirectional-override events (FR-9), 100% produce a visible contested state until Misha explicitly resolves it; 0% are silently auto-resolved by either side. Measured via: audit log — every override event has a corresponding explicit-resolution event, never an implicit one. Plate test: lighter — Misha stops re-discovering "Dispatch thought this was done and it wasn't."
- **SM-5. Module is genuinely optional.** With the module disabled, a standard harness regression session is byte-for-byte identical in hook behavior to a harness that never had the module. Measured via: hook-firing diff between module-absent and module-disabled runs = empty. Plate test: lighter for *future Misha* — the module can be turned off without becoming a maintenance liability. (Counterbalancing metric: guards against the module's value coming at the cost of harness coupling.)
- **SM-6. (Counterbalancing) No new always-on friction.** Number of new mandatory prompts/confirmations the module injects into a normal Dispatch session that does not use the tree = 0. Measured via: a Dispatch session run with the module installed-but-unused fires zero module-originated interruptions. Plate test: ensures SM-1..SM-4's value doesn't arrive as a tax on every session.

## Out-of-scope

<!-- Stage E continued — things a reasonable reader might assume are
included but explicitly are not, each with rationale. -->

- **Multi-user / collaboration** — single known user; presence, shared cursors, and per-user permissions are 10x the model complexity for zero current value.
- **Real-time collaborative editing** — only one human and one Dispatch write the tree; the co-edit case is narrow (NFR-2), not a general CRDT/OT problem.
- **Mobile-native client** — Misha drives Dispatch from desktop; a mobile tree client is not in the friction path. Revisit only if Dispatch usage moves to mobile primarily.
- **JSON hand-editing surface / schema docs for the user** — the JSON is internal; exposing it as an editable surface contradicts FR-11. The schema is an engineering artifact, not a user-facing one.
- **Replacing the full Claude desktop app feature set** — whether the GUI subsumes the chat interface at all is the architecture decision (ADR-031); even in the most ambitious option, parity with every desktop-app convenience feature is explicitly not a goal of the first release.
- **Generic project-management tooling** — *(reconciled at Stage B — see note).* The system **IS** a to-do/backlog for items Misha wants to work on with Claude Code (Stage B scope expansion: capture, contextualize, move into sessions, track per-item goals/progress in the tree). What remains out of scope is *generic* PM: sprints, story points/estimates, arbitrary ticket types, assignees, due-date workflows, and any field not in service of "a thing to work on with Claude Code and its conversation tree." It is not a Jira/Linear/Asana; it is a Claude-Code-work backlog whose items become conversation-tree roots.
- **Aggressive nag/alert engine** — per invisible-knowledge surface #3, alerting is intentionally minimal (parent-on-child-conclude + Misha's own deferrals). A notification/reminder system beyond that is explicitly excluded.
- **Automatic conflict *resolution* of contested check-offs** — the system surfaces contested state; it does not decide who is right. Auto-resolution would destroy the exact signal SM-4 protects.

## Open questions

<!-- Stage F — decisions that must be made before the product finalizes.
Each has a current lean + a decision process. The architecture choice is
the largest and is deferred to ADR-031 by design (Tier-5 → ADR is the
deliverable, per the work-sizing rubric). -->

- **OQ-1. Co-edit conflict resolution mechanism.** Optimistic concurrency, last-write-wins per field (Misha's stated lean). Open sub-question: what is the conflict *unit* — per JSON field, per node, per subtree? Leaning per-field with a visible "Dispatch also touched this" notice. Decide in: ADR-031 or a sibling ADR if it proves independently load-bearing.
- **OQ-2. Real-time updates vs. end-of-turn snapshots.** Real-time = the GUI reflects Dispatch writes mid-turn; snapshot = the GUI updates at turn boundaries. Real-time is more responsive but multiplies the co-edit surface (OQ-1) and the latency budget (NFR-4). Leaning **snapshot for v1** (smaller co-edit surface, simpler NFR), real-time as a later enhancement. Decide in: ADR-031.
- **OQ-3. Branch-context-reload format.** When Misha clicks a node, what loads? Options: full message range / a summary / just the parent question / **all of the above as expandable layers**. Leaning the layered option (summary by default, expandable to full). Decide in: the plan's UX section + ux-designer review.
- **OQ-4. Action-item typing.** Generic actions, or typed (decision / manual-action / awaiting-deploy / awaiting-third-party / …)? Typed enables better side-surface filtering and the OQ-5 deferral conditions; generic is simpler. Leaning a **small fixed enum** (decision, manual-action, awaiting-external, deferred). Decide in: ADR-031 (it shapes the JSON schema, which is a contract → Tier-4-ish, ADR-worthy).
- **OQ-5. "Deferred until [condition]" resolution mechanism.** Polling a condition, a harness hook firing on the event, or manual unhide. Leaning: date/time conditions resolve by a lightweight scheduled check; event conditions resolve via the harness's existing surfacing hooks; manual unhide always available as the floor. Decide in: ADR-031 or sibling ADR.
- **OQ-6. (GAP) Tree scope: per-project or global?** Is there one tree per repo, or one global tree spanning all Dispatch work across projects? This materially shapes the state-file location, the session-binding model, and FR-18. No stated lean — genuinely open and surfaced as a gap Misha did not address. Decide in: ADR-031 (it is an architecture-level decision, not a UI detail).
- **OQ-7. (GAP) Concluded-branch lifecycle / tree growth.** Over months a tree could reach thousands of nodes. Does a concluded branch ever archive/prune, or does the tree grow unbounded (collapse-only)? Affects NFR-3's node ceiling. Leaning: collapse-by-default, with an archival tier for branches concluded > N days, recoverable. Decide in: the plan's data-model section + systems-designer review.
- **OQ-8. (GAP) Architecture choice — the load-bearing one.** Custom GUI as full chat replacement (Agent SDK) vs. parallel observer alongside the desktop app vs. hybrid control-surface. Deliberately **not answered in this PRD** — per the work-sizing rubric this is a Tier-5 architecture decision whose deliverable is ADR-031 with full options analysis, prior-art research (Claude Agent SDK capabilities, desktop-app bridge investigation), and a recommendation Misha decides on. Decide in: **ADR-031** (Phase 3).
- **OQ-9. PRD location — RESOLVED 2026-05-15.** This PRD is at the canonical `docs/prd.md`. Resolution forced by the prd-validity-gate becoming mechanically live + `gate-respect` (carve-out would be false; bypass forbidden); conforming to the single-PRD convention is the gate's named remediation and makes the mechanism genuinely fire. Full rationale in ADR-031 Consequences. Reversible (one `git mv`) but not recommended to reverse. **Closed** — no longer pending Misha feedback (Misha may still override; default is conform).
- **OQ-10. Two-list information architecture — RESOLVED 2026-05-15 (Misha decided at Stage B).** The GUI keeps **two separate surfaces**: (a) a **backlog** list of items Misha wants to work on but has not started, and (b) an **action-items** list of follow-ups required on in-flight work. Both link back to tree nodes. Misha's words: *"I agree, let's keep the backlog separate from the action items."* **Closed.** (This was a Stage-F-class question raised at Stage B and resolved immediately by the user; recorded here for traceability. Downstream: FR set will need a backlog-list FR distinct from the existing FR-5 action-list — to be surfaced at Stage C.)
