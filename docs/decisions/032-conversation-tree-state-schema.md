# ADR 032 — Conversation Tree State Schema: JSON Field Layout Contract

**Date:** 2026-05-17
**Status:** Active
**Stakeholders:** Misha (product authority — the tree model must match how he actually works: branches are conversations, not questions); ADR-031 r7 (the accepted Option-2 architecture this contract serves); the Dispatch orchestrator (the sole writer of this state); the localhost GUI (the sole non-mutating reader); `conversation-tree-state-gate.sh` / `conversation-tree-stop-gate.sh` (Phase-B enforcement that consumes this layout's key-presence shape); every later phase (A2/B/C/D) which builds against this frozen layout.

## Revision history

- **2026-05-17 — r1 (DEC-D, §7c/§8 cross-clause gap closure).** Resolves NL-FINDING-003 (`docs/findings.md`): the original §7c compaction emptied `events[]` once a fresh snapshot provably covered all events, while §8 specifies the Phase-B branch-presence gate against `events[]` — a silent DoS against the orchestrator on long-lived (FR-24 "a month"-horizon) trees once compaction fired. Misha decided (2026-05-17) **option (b), generalized**: §7c is revised so compaction preserves the most-recent gate-relevant event for every still-live entity in `events[]` (the *general* "compaction may not drop any event that is still live and gate-relevant" principle; branch-opened-per-still-live-node is v1's only instance). §8 is left structurally unchanged — it still reads `events[]` and only `events[]`, preserving its torn-snapshot-immune design — and now carries an explicit `§7c↔§8 interaction — CLOSED, not worked around` clause documenting that the gap is closed at the producing clause. **Rejected alternatives:** (a) §8 also consults `snapshot.nodes` — re-introduces the snapshot-trust §8 deliberately avoids (a torn write would weaken the gate); (c) §8 falls back to the never-truncated audit log — a second-file dependency + gate complexity for the §8 hot path. **Schema-version impact:** none — this is an *additive/behavioral* change *within* major `1` (it constrains the writer's compaction behavior to retain a subset it previously dropped; no required field of any existing event is changed or removed, no snapshot/marker contract field changes, the §8 consumer query is byte-identical). Per the ADR's own §180 rule, only a *major* contract change (changing/removing a required field of an existing event, or the snapshot/marker contract) warrants a `schema_version` bump; DEC-D is not that. The skeleton's `schema_version: 1` is unchanged. Revised clauses: §7c (compaction retention obligation), §8 (added the CLOSED interaction clause). Implemented by plan task B-DEC-D (`neural-lace/conversation-tree-ui/state/store.js` compaction + `state/selftest.js` proof).

## Context

ADR-031 r7 ACCEPTED Option 2: a passive localhost GUI reads a **file-mediated state contract** that the harness-bound local Dispatch orchestrator writes as it works. ADR-031 deliberately deferred exactly one thing to this ADR — the **state-file field layout** — and pinned everything else as a binding input:

- The **three Option-2-viability properties** (torn-snapshot recovery, single-event-atomic append, compaction trigger) are **fixed by ADR-031 r7 Pin 3**. This ADR restates them as fixed constraints and designs the field layout that *expresses* them; it does **not** re-decide them.
- The **versioned-reader-refuses-unknown-major** behavior is fixed by ADR-031 r7 Pin 2 (error partition). This ADR fixes the `schema_version` field's shape and semantics so the reader can implement that partition.
- The **branch-name-as-required-key** enforcement bar is fixed by ADR-031 r7 Pin 1. This ADR's load-bearing obligation is to make that bar reduce to a single `jq` key-presence check (see "Decision §8 — Enforcement-shaped layout (LOAD-BEARING for Phase B)").

The Phase-0 Walking Skeleton (`neural-lace/conversation-tree-ui/state/state.js`, committed at `68d598e`) already established the forward-shaped spine: a single JSON file with `schema_version` (int), an append-only `events` array, and a derived `snapshot` reduced from `events`, published via write-temp-then-`renameSync` (atomic single-fs publish). **This ADR formalizes and extends that exact shape — it does not contradict it.** The skeleton's `branch-opened` event, `{id, parent_id, title, timestamp}` node fields, and `{nodes:[...]}` snapshot are the seed of the contract below.

What this ADR must fix, per the plan's Task A1:

1. `schema_version` semantics (major-version, unknown-major ⇒ distinct refuse — Pin 2).
2. The finalized event-type enum + each event's required fields incl. a stable idempotency id.
3. Node shape; the strict-tree invariant (FR-1); the FR-2 conversational-divergence cardinality rule, encoded so "several items in one thread ⇒ 0 extra branches; genuine divergence ⇒ exactly 1 new branch" is representable (with the N=3 fixture).
4. The typed item set {decision, question, action} (OQ-4); defer-as-tag is a STATE not a type (FR-13).
5. Well-known path resolution: per-project trees (FR-18) + the global tree (FR-25) + cross-tree FR-3 links **without multi-parenting**.
6. NFR-2 conflict-unit + the conflict-resolution-mechanism boundary (PRD OQ-1 — the *mechanism* is this ADR's to decide).
7. Pin 3 restated as fixed (torn-snapshot recovery / single-event-atomic append / compaction trigger).
8. The enforcement-shaped layout that lets `conversation-tree-state-gate.sh` verify branch-presence with a key-presence check, no semantic interpretation.

## Decision

The state file is a single JSON document at a well-known per-tree path (§5). Its top-level shape, frozen by this ADR:

```json
{
  "schema_version": 1,
  "tree_id": "global" | "<project-slug>",
  "events": [ /* append-only; the source of truth (Pin 3) */ ],
  "snapshot": { /* derived cache; never trusted without its coverage marker (Pin 3a) */ }
}
```

`events` is the source of truth. `snapshot` is a derived cache reducible from `events` and is never authoritative without a valid coverage marker (§7). This is the ADR-031 r7 forward-compat refinement #2 ("append-only event log + periodic snapshot; the log is truth, the snapshot is a derived cache") made concrete and is exactly the skeleton's existing shape, now extended.

### §1. `schema_version` — integer, major-version semantics (Pin 2, fixed input)

`schema_version` is a single integer (not semver string). It is the **major** version. v1 = `1` (matches the skeleton's `SCHEMA_VERSION = 1`).

- A reader whose known major == the file's major reads normally.
- A reader whose known major < the file's major **refuses** with the distinct message `schema too new — upgrade the GUI/gate` and reads **nothing** from the file (never a partial / best-effort mis-parse). This is the Pin-2 "unknown-schema-major → closed with the distinct message" cell — fixed by ADR-031 r7, restated here so A2d and B1b can implement it against a concrete field.
- Minor/additive evolution within a major (new optional event fields, new event types appended to the enum) does **not** bump the major; readers ignore unknown event types in the reducer (forward-tolerant) but never ignore an unknown **major**. Adding a new event type is additive; changing/removing a required field of an existing event, or changing the snapshot/marker contract, is a major bump.

### §2. Event-type enum (finalized) + per-event required fields

`events` is an array of event records. **Every event** carries these envelope fields (required, all events):

| Field | Type | Meaning |
|---|---|---|
| `event_id` | string (ULID/uuid; ASCII; stable, globally unique within the file) | Idempotency key. A reader/writer that sees a duplicate `event_id` treats the second as a no-op. This is what makes single-event-atomic append (§7b) safe under a retried write. |
| `type` | string (one of the enum below) | The event class. |
| `ts` | string (ISO-8601 UTC) | When the event was authored (matches the skeleton's `timestamp`; renamed `ts` for brevity, the skeleton reducer is updated in A2 — additive, no major bump since Phase 0 is pre-freeze). |
| `actor` | `"dispatch"` \| `"gui"` | Which writer authored it (FR-11 symmetric interface; needed by NFR-7 audit and the §6 conflict-unit). |

**The finalized event-type enum (v1 — closed set; new types are additive, see §1):**

| `type` | Required fields (in addition to the envelope) | Semantics / FR mapping |
|---|---|---|
| `branch-opened` | `node_id`, `parent_id` (string or `null` for a root), `title` | Creates a tree node. `parent_id: null` ⇒ a root node (FR-22 backlog-activation roots, FR-1 root). The skeleton's existing event, envelope-extended. |
| `decision-raised` | `node_id`, `item_id`, `text` | Adds a `decision`-typed item to `node_id`'s checklist (FR-8, OQ-4). |
| `question-raised` | `node_id`, `item_id`, `text` | Adds a `question`-typed item (OQ-4; questions feed FR-4/FR-5 surfaces). |
| `action-added` | `node_id`, `item_id`, `text` | Adds an `action`-typed item (OQ-4). |
| `answered` | `node_id`, `item_id` | Marks a `decision` or `question` item answered ⇒ checked (FR-4/FR-8). |
| `action-done` | `node_id`, `item_id` | Marks an `action` item done ⇒ checked (FR-5/FR-8). |
| `concluded` | `node_id` | Branch auto/explicitly concluded — written **only** when all checklist items are checked (FR-7); the reducer rejects a `concluded` whose node still has an unchecked item (FR-7 invariant enforced in the reducer, not the writer). |
| `re-opened` | `node_id` | Reverses `concluded` with no data loss (FR-7). |
| `archived` | `node_id` | Branch leaves the active view, stays in the archive surface (FR-28). Never closes a Claude session. |
| `deferred` | `node_id`, `item_id`, `scheduled_for` (ISO-8601 or `null`) | Sets the `deferred` **state tag** on an item (FR-13 / OQ-5). NOT a type — see §4. |
| `defer-cleared` | `node_id`, `item_id` | Misha manually clears the deferred tag (FR-13 — only explicit user action clears it). |
| `draft-saved` | `node_id`, `draft_text` | Per-branch draft persistence (FR-27). Best-effort durability (NFR-1), not crown-jewel. |
| `draft-cleared` | `node_id` | Draft sent/used/cleared ⇒ remove the draft-pending indicator (FR-27, reframed per plan BF-1: "marked used / cleared", no send channel). |
| `cross-linked` | `from_node`, `to_node`, `tag` | Non-hierarchical FR-3 cross-link, **including cross-tree** (`to_node` may be a `tree_id::node_id` qualified ref — §5). Does NOT change either node's parent. |
| `re-parented` | `node_id`, `new_parent_id` | GUI drag-drop / Claude re-parent (FR-11). The reducer rejects a re-parent that would create a cycle or a second parent (FR-1 strict-tree invariant). |
| `promoted` | `node_id`, `item_id`, `new_node_id` | Opt-in per-item split: an item is promoted to its own branch (FR-3/C5; the *only* way a single item becomes a branch — see §3). |
| `backlog-added` | `item_id`, `tree_id`, `priority` (`"high"`\|`"medium"`\|`"low"`), `text` | Adds a not-yet-started backlog item (FR-20, OQ-11 3-value categorical). |
| `backlog-activated` | `item_id`, `new_node_id` | Backlog item → new tree root (FR-22). Emits the equivalent of a `branch-opened` for `new_node_id` with `parent_id: null`. |
| `context-attached` | `target` (`node_id` or backlog `item_id`), `context_ref` | FR-21 context attach (notes/files/prior decisions) carried into activation. |
| `reordered` | `scope` (`"backlog"`\|`"actions"`), `ordered_ids` (array) | FR-29 manual drag-reorder + sort persistence. |
| `annotated` | `node_id`, `text` | FR-12 lifecycle annotation / authorship-observability marker. |

The reducer (`deriveSnapshot`, A2) folds `events` left-to-right into `snapshot`. Unknown `type` values within the same major are skipped by the reducer (forward-tolerant additive evolution, §1) — they are never an error and never a major bump.

### §3. Node shape + strict-tree invariant (FR-1) + FR-2 cardinality (with the N=3 fixture)

A snapshot node:

```json
{
  "node_id": "string",
  "parent_id": "string | null",
  "title": "string",
  "tree_id": "global | <project-slug>",
  "state": "open | concluded | archived",
  "items": [ { "item_id", "kind": "decision|question|action",
               "text", "checked": bool, "deferred": bool,
               "scheduled_for": "ISO-8601 | null" } ],
  "draft": "string | null",
  "cross_links": [ { "to": "<tree_id>::<node_id> | <node_id>", "tag": "string" } ],
  "bound_sessions": [ "string" ]
}
```

**Strict-tree invariant (FR-1):** every node has exactly one `parent_id` (or `null` for a root). The A2 reducer **rejects** any `re-parented` / `branch-opened` that would give a node two parents or introduce a cycle (resolvable single path to root is an invariant the reducer asserts, not a writer convention). Non-hierarchical relationships are `cross_links` (FR-3) only — never multi-parenting.

**FR-2 conversational-divergence cardinality — encoded so it is representable, not enforced by the schema's shape alone:** branching is per-*conversation*, not per-question. The schema makes this representable because **items live ON a node (`node.items[]`), not as nodes**. Therefore:

- *N items discussed in one thread ⇒ 0 extra branches.* They are N `decision-raised`/`question-raised`/`action-added` events all carrying the **same `node_id`** — they append to one node's `items[]`; **zero** `branch-opened` events are emitted.
- *Genuine divergence ⇒ exactly 1 new branch.* When a conversation demonstrably forks into a distinct line of work, exactly one `branch-opened` (child of the diverging node) is emitted.
- *Per-item split is opt-in only* via `promoted` (the single mechanism by which one item becomes its own branch — FR-3/C5).

**N=3 fixture (encoded in the contract for A2's property suite + B's `--self-test`):** A thread on node `n1` where Dispatch raises 3 items: emit `branch-opened(n1)`, then `decision-raised(n1,i1)`, `question-raised(n1,i2)`, `action-added(n1,i3)`. **Assertion:** post-reduction the tree has exactly **1** node (`n1`) with `items.length == 3` and **0** additional `branch-opened` events ⇒ **0 extra branches**. Contrast fixture: if `i2` opens a sub-investigation, exactly **one** `branch-opened(child-of-n1)` is emitted ⇒ **exactly 1 new branch**. This fixture is the falsifiable encoding of FR-2's acceptance criterion and is a required A2/B `--self-test` case.

### §4. Typed item set {decision, question, action} (OQ-4); defer is a STATE not a type (FR-13)

`node.items[].kind` is exactly one of `decision`, `question`, `action` (OQ-4 closed set). **`deferred` is NOT a kind** — it is the boolean `node.items[].deferred` state tag plus `scheduled_for` (FR-13 / OQ-5). A deferred item keeps its original `kind` and **stays on its list** (the FR-13 "stays visible, never removed" property is structural: the item is not deleted, only `deferred:true` is set). At `scheduled_for` the system highlights+notifies and does nothing else; only a `defer-cleared` event (explicit user action) flips `deferred` back to `false`. The schema cannot represent "defer auto-resolves" because there is no event that clears `deferred` other than the explicit `defer-cleared` — the FR-13 guarantee is enforced by the absence of any auto-clear event in the enum.

### §5. Well-known path resolution: per-project trees (FR-18) + global tree (FR-25) + cross-tree FR-3 without multi-parenting

**One state file per tree** (the skeleton's single-file shape, generalized). Resolution:

- **Per-project tree (FR-18):** `<project-root>/.claude/state/conversation-tree/tree-state.json`. `tree_id` = the project slug. Project A's file never contains project B's nodes (NFR-5 project isolation is structural — separate files).
- **Global tree (FR-25):** `~/.claude/state/conversation-tree/global/tree-state.json`. `tree_id = "global"`. Holds cross-cutting work; it is an **addition**, not a merge of per-project trees.

The Phase-0 skeleton's `STATE_DIR = __dirname` single-file path is the pre-freeze placeholder; A2 implements the resolver above (additive — Phase 0 is pre-freeze, no major bump).

**Cross-tree FR-3 links WITHOUT multi-parenting:** a `cross_links[].to` value may be a **qualified reference** `"<tree_id>::<node_id>"` (e.g., `"projectB::n-7"` or `"global::n-3"`). A cross-link is a non-hierarchical association rendered visibly; it does **not** appear in any node's `parent_id` and the reducer never treats a cross-link as a parent edge. This is the FR-3 "cross-links between a per-project tree and the global tree" requirement satisfied with zero multi-parenting: the strict tree (§3) is intra-file via `parent_id`; cross-tree relationships are `cross_links` qualified refs, resolved by the GUI at render time across files, never by reparenting.

### §6. NFR-2 conflict-unit + conflict-resolution-mechanism boundary (PRD OQ-1 — this ADR decides the mechanism)

PRD OQ-1 explicitly delegated the conflict **mechanism + conflict-unit** to this ADR. **Decision:**

- **Conflict-unit = a single event record.** Because the log is append-only and §7b makes one event the atomic append unit, two writers (Dispatch + GUI, the only two — FR-11 symmetric) never co-mutate the *same* unit. Each writer appends whole events; the merge of two concurrent writers' work is the **union of their event records, ordered by append arrival, deduplicated by `event_id`**. There is no field-level merge and no per-field-mergeable-node requirement (ADR-031 r7 explicitly recorded that the obsolete r2 "per-field-mergeable" pin was Option-4-specific and is NOT carried forward; this ADR confirms the conflict-unit is the event record, not the node field).
- **Conflict-resolution mechanism = last-writer-append-wins at the event grain, with reducer-level invariant rejection.** Concurrency correctness is the §7b single-event-atomic append (reader sees N or N+1 whole events, never half). Semantic conflicts (e.g., GUI re-parents `n5` while Dispatch concludes `n5`) are resolved by **event order + reducer invariants**: both events are retained in the log (nothing is silently dropped — the NFR-2 safety property); the reducer applies them in append order and rejects only those that violate a hard invariant (cycle, two-parent, conclude-with-unchecked), surfacing the rejection in the C1 corruption/anomaly UX rather than discarding data. The mechanism is intentionally minimal because the realistic concurrency is two cooperating writers at <100-branch scale (NFR-3), not an adversarial multi-writer CRDT problem (PRD out-of-scope explicitly excludes the general CRDT/OT case).

### §7. Pin 3 restated as fixed input (NOT re-decided here)

ADR-031 r7 Pin 3 fixed three Option-2-viability properties. This ADR restates them and fixes the **field layout** that expresses them; the *properties themselves are not re-decided*:

- **§7a — Torn-snapshot recovery (Pin 3a, mandatory):** `snapshot` carries a coverage marker `snapshot.covers_through_event_id` (the `event_id` of the last event the snapshot provably reduced) and `snapshot.valid` (written `true` only after the snapshot is fully serialized). A reader that finds `snapshot.valid != true`, OR `covers_through_event_id` not equal to the last `events[]` element's `event_id`, OR the snapshot absent, **MUST** discard the snapshot and reconstruct state by replaying `events` from the start. The snapshot is never trusted without this marker. This is the field layout for the ADR-031-fixed property — the property is an input, the marker fields are this ADR's expression of it.
- **§7b — Single-event-atomic append (Pin 3b):** the atomic unit is one event record. A write publishes via write-temp-then-`renameSync` (the skeleton's existing primitive at `state.js:79`) so a concurrent reader of the well-known path always sees a file with N or N+1 **whole** events, never a half event. `event_id` (§2) makes a retried append idempotent.
- **§7c — Compaction trigger (Pin 3c), revised per DEC-D 2026-05-17:** a fresh snapshot supersedes and truncates the log prefix it provably covers, **with one general retention obligation**: compaction **MUST preserve, in `events[]`, the most-recent event of every event-class that a gate consumes from `events[]` for every entity that is still live**. The general principle: *compaction may not drop any event that is still live and gate-relevant.* Concretely: when `events.length` exceeds a compaction threshold, the writer computes a full snapshot, sets `snapshot.covers_through_event_id` to the last covered event's id and `snapshot.valid:true`, then truncates the covered prefix — **except** that, for each entity (node) still live in the post-reduction snapshot, the single most-recent gate-relevant event for that entity is *retained* in the published `events[]` even if it falls inside the covered prefix. The v1 instance of this general rule is **`branch-opened` per still-live node** (the only event-class §8 consumes from `events[]` today): after compaction, the post-compaction `events[]` contains exactly the most-recent `branch-opened` for every node that is live (exists in `snapshot.nodes` and is not `archived`) at compaction time — bounded by the live-node count (NFR-3 <100-branch), not the full history. "Still live" is defined against the reducer's own liveness notion: a node is live iff it survives reduction into `snapshot.nodes` and its `state` is not `archived` (a `concluded` node stays live — `re-opened` reverses it with no data loss, so it remains gate-relevant; only `archived` is the terminal "no longer active" state). `snapshot.covers_through_event_id` continues to mark the last covered event's id, so §7a's reader-replay contract is unchanged: a reader still discards an untrustworthy snapshot and replays whatever `events[]` holds — now a small live-set rather than possibly-empty. The audit log (NFR-7, separate append-only file — never truncated) retains the full history regardless. The general retention obligation is *future-proof*: when a later phase adds a new gate that consumes a new event-class from `events[]`, that event-class automatically inherits the "preserve most-recent per still-live entity" rule with no further §7c amendment — the rule is stated over *any* gate-relevant-still-live event, with branch-opened-per-live-node being merely v1's only instance. Truncation of everything *outside* the live retention set is still sound precisely because §7a guarantees a reader replays from the snapshot's covered point forward and the live retention set is exactly the subset a gate could still need.

### §8. Enforcement-shaped layout (LOAD-BEARING for Phase B — explicitly called out)

Per ADR-031 r7 Pin 1, the schema **must make the most semantically-meaningful enforcement property reduce to a cheap key-presence/shape check** — that is the documented ceiling of the mechanical layer. This ADR discharges that obligation as follows:

- **The branch-presence check is a single `jq` key-presence query, no semantic interpretation.** `conversation-tree-state-gate.sh` (B1a) receives the spawned branch's identifying string **independently** from the spawn `tool_input` (it does not derive it from the state file — that is what makes the bar non-gameable per ADR-031 r7). The gate's check is: *does an `events[]` element exist with `type == "branch-opened"` AND `title == <the title from tool_input>` (or `node_id == <id from tool_input>`)?* This is expressible as one `jq -e` filter:

  ```
  jq -e --arg b "$BRANCH" '.events[] | select(.type=="branch-opened" and (.title==$b or .node_id==$b))' tree-state.json >/dev/null
  ```

  Exit 0 ⇒ "an entry naming this branch exists" ⇒ ALLOW; exit non-zero ⇒ BLOCK (subject to the Pin-2 error partition for parse-fail/missing/stale/unknown-major). The gate performs **no** semantic interpretation of the tree — it only asserts a keyed record exists. `branch-opened` carrying `title` AND `node_id` as required, top-level (not nested under derived `snapshot`, which a torn write may invalidate — the check runs against the append-only `events`, the source of truth, so a torn snapshot never weakens the gate), is the specific layout choice that makes this true.
- **§7c↔§8 interaction — CLOSED, not worked around (DEC-D 2026-05-17).** The `events[]`-only check above remains correct on long-lived trees *because* §7c's revised compaction now preserves the most-recent `branch-opened` for every still-live node in `events[]` (the general "preserve any gate-relevant-still-live event" rule, of which branch-opened-per-live-node is v1's instance). Before the DEC-D revision there was a cross-clause gap (NL-FINDING-003): §7c compaction emptied `events[]` once a snapshot covered all events, while §8 reads `events[]`, so post-compaction every legitimate Phase-B spawn for a still-live branch would have been silently BLOCKed — a DoS against the orchestrator on exactly the FR-24 "a month"-horizon trees the feature targets. The resolution is the §7c revision (compaction retains the live-set), **not** a §8 change: §8 still reads `events[]` and **only** `events[]` — it does NOT consult `snapshot.nodes` (rejected DEC-D option (a): re-introduces the snapshot-trust §8 deliberately avoids — a torn write must never weaken the gate) and does NOT fall back to the audit log (rejected DEC-D option (c): a second-file dependency + gate complexity for the §8 hot path). The torn-snapshot-immune `events[]`-only property of §8 is therefore *fully preserved*; the gap is closed at the producing clause (§7c retains what §8 needs), so the two clauses are now mutually consistent by construction rather than via a downstream patch. Bound: post-compaction `events[]` is sized by the live-node count (NFR-3 <100), so the §8 `jq` scan stays cheap.
- **Pin-2 error partition is a shape check on `schema_version` + JSON-parse + mtime** — all top-level, all `jq`/stat-checkable without interpreting tree semantics. Unknown major ⇒ the gate emits the distinct `schema too new — upgrade` message and fails closed (§1).
- **`conversation-tree-stop-gate.sh` (B2)** correspondingly checks state-file **mtime** freshness vs. transcript-observed spawns — also a pure shape/timestamp check, no semantic interpretation.

This is the ceiling, stated honestly (ADR-031 r7): the gate verifies *an entry naming this branch was written*, not that the tree is *semantically true*. Raising the bar from "wrote anything" to "wrote a record naming this exact branch the spawn independently declared" is the strongest mechanical proxy; semantic correctness is the rule-class `conversation-tree-state.md` (B3) layer with Misha's interrupt authority as backstop.

## Alternatives considered

- **Semver string `schema_version` (e.g., `"1.2.0"`) instead of a bare major integer.** Rejected: the only behavior the reader needs is "is this major newer than I understand?" (Pin 2). A bare integer makes the unknown-major refuse a single `>` comparison; minor/patch carry no reader-behavior difference at this scale. Adds parsing surface for zero benefit. The skeleton already uses an int — keeping it avoids a gratuitous major bump.
- **Snapshot as the source of truth, event log as an audit-only sidecar.** Rejected: directly contradicts ADR-031 r7 refinement #2 + Pin 3a (the log is truth, the snapshot is a derived cache, torn-snapshot recovery is mandatory). A torn snapshot with no replayable truth is the exact data-loss failure Pin 3a forbids.
- **Per-field-mergeable nodes (the obsolete r2 Option-4 pin).** Rejected explicitly: ADR-031 r7 recorded this pin as Option-4-specific (it existed because Option 4 had two independent live writers reconciling at spawn) and NOT carried forward to Option 2. Under Option 2 the orchestrator owns writes and the GUI appends events; the conflict-unit is the event record (§6), not the node field. Reintroducing field-mergeability would be solving a problem the accepted architecture does not have.
- **Multi-parent nodes to model cross-project relationships.** Rejected: violates FR-1 (strict tree, single parent). FR-3 cross-links with qualified `<tree_id>::<node_id>` refs (§5) express every cross-cutting/cross-tree relationship FR-25 needs without any node ever having two parents — the reducer can then assert the single-parent invariant unconditionally.
- **A separate item-node per question/decision (per-item branching).** Rejected: directly contradicts FR-2 (Misha-corrected: branching is per-conversation, not per-question). Items-on-node (§3) is the layout that makes "N items in one thread ⇒ 0 extra branches" structurally true; per-item nodes would make it structurally false.
- **Gate derives the branch name from the state file itself.** Rejected: ADR-031 r7 Pin 1 specifically requires the spawn `tool_input` to supply the branch independently — deriving it from the file the writer controls would let a writer satisfy the gate by writing *anything* and naming it after whatever it wrote, collapsing the bar back to "wrote anything." §8 keeps the independent-input property.

## Consequences

- **Enables (frozen contract for all later phases):** A2 implements the state library against §1–§7 (atomic append, snapshot+coverage-marker, compaction, unknown-major refuse, the N=3 fixture as a property test). B1/B2 implement the gates against §8's single-`jq`-key-presence shape. C/D build the GUI reader against the `snapshot` shape + the §7a coverage-marker fallback. The schema is now the single contract every consumer builds to — the "our contract is the stable layer, decoupled from the undocumented transcript format" guarantee (ADR-031 r7 refinement #1/#4) made concrete.
- **Skeleton evolution (additive, no major bump):** Phase 0 is pre-freeze; A2 extends the skeleton's `branch-opened`/node/snapshot to the §2/§3/§7 shapes (envelope fields, coverage marker, path resolver). These are additive within major 1 — the skeleton's `schema_version: 1` is unchanged; no consumer of the frozen contract exists yet to break.
- **Costs / accepted ceilings (honest):** (a) The §8 mechanical layer verifies branch-record-presence, not semantic tree correctness — the documented ADR-031 ceiling; semantic truth is the B3 rule-class layer + Misha's interrupt authority. (b) The §6 conflict mechanism is minimal (event-grain last-writer-append-wins + reducer invariant rejection), correct for two cooperating writers at <100-branch scale (NFR-3) but explicitly NOT a general CRDT — PRD out-of-scope excludes the general case, so this is an accepted scope boundary, not a gap. (c) Cross-tree links resolve across files at GUI render time (§5); a referenced foreign `tree_id::node_id` that no longer exists degrades per NFR-9 (rendered, flagged "unavailable", never a crash) rather than being a hard referential-integrity constraint — accepted because cross-file FK enforcement is disproportionate at this scale.
- **Blocks / sequencing:** A2 is unblocked by this freeze (it could not start until the field layout was fixed — plan Assumption: "A2 cannot proceed until A1 freezes the field layout"). B0/B1/B2 consume §8. The plan's `## In-flight scope updates` will record any layout amendment discovered during A2 build per the spec-freeze/scope-enforcement protocol; a *major* change (changing/removing a required field of an existing event, or the snapshot/marker contract) requires a `schema_version` bump and a follow-up ADR revision, not a silent in-flight edit.
- **One-state-file-per-tree (§5)** means project isolation (NFR-5) is structural (separate files), not a runtime filter — a desirable property: no code path can leak project B into project A's tree because the file simply does not contain it.

## Cross-references

- ADR-031 r7 (`docs/decisions/031-conversation-tree-ui-architecture.md`) — the accepted Option-2 architecture; **Pin 1** (enumerated matcher + branch-name-as-required-key), **Pin 2** (error partition / unknown-major refuse), **Pin 3** (torn-snapshot recovery / single-event-atomic append / compaction) are the binding inputs this ADR expresses as a field layout, not re-decided.
- PRD `docs/prd.md` — FR-1 (strict tree), FR-2 (conversational-divergence cardinality), FR-3 (cross-links incl. cross-tree), FR-8 (branch checklist), FR-11 (persistent shared state, symmetric writers), FR-13/OQ-5 (defer as a tag/state), FR-18/FR-25 (per-project + global trees), FR-22 (backlog→root), FR-24 (persistence across arbitrary elapsed time), FR-27 (drafts), FR-28 (archival, never closes a session), FR-29 (sort/reorder), OQ-1/NFR-2 (co-edit conflict-unit, delegated here), OQ-4 (typed item set), OQ-11 (3-value priority).
- `docs/plans/conversation-tree-ui-v1.md` — Task A1 (this ADR), A2 (implements §1–§7), B0/B1/B2 (consume §8), `## Edge Cases` (FR-2 N=3 fixture, torn-snapshot, unknown-major).
- `neural-lace/conversation-tree-ui/state/state.js` @ `68d598e` — the Phase-0 forward-shaped skeleton this ADR formalizes and extends (schema_version int, append-only events, derived snapshot, atomic renameSync publish at `state.js:79`).
- `build-doctrine/doctrine/03-work-sizing.md` — Tier-4 contract work; the deliverable is this committed schema contract document.
