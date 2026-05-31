# Decision-Context — Fence Grammar For Every Decision-Soliciting / Question-Asking / Action-Item-Assigning / Autonomous-Action-Logging Surface

**Classification:** Hybrid. The fence grammar (the four-category Markdown shape that wraps every agent→user decision-context surface) and the Tiered-Scan trigger taxonomy (Tier-1 hard-block / Tier-2 soft-warn / Tier-3 rhetorical-whitelist) are **both** machinery the agent self-applies at message-author time (Pattern) AND machinery a Stop-hook gate enforces at session-end (Mechanism). The Mechanism layer is `decision-context-gate.sh` (Stop hook — Task 4 of the parent plan) which scans the agent-uneditable last assistant message in `$TRANSCRIPT_PATH`, runs the Tiered-Scan classifier, BLOCKs Stop when a Tier-1 trigger fires without a fence, and emits `decision-raised` / `question-raised` / `action-added` / `autonomous-action-logged` plus `item-details-set` events via the sole-normative `state.js` facade when a fence IS present; plus `decision-context-reply-emit.sh` (UserPromptSubmit hook — Task 6) which detects open node references / `reply_with` literal phrases in Misha's reply and POSTs `answered` / `action-done` / `item-details-set` updates through the same facade. The Pattern layer is the agent's self-applied fence-first discipline at message-author time — incentivized by the redo-friction that a Stop-block + schema-as-error inflicts when the agent forgets. The validator backing both is the sole-normative Zod module at `neural-lace/conversation-tree-ui/state/decision-context-schema.js` (Task 2 of the parent plan) — both the hook (via `node -e require(…)`) and the GUI consume that single module; NO shell re-implementation; NO parallel parser. This single-implementation-determinism mirrors ADR-032 §8 r2.1's sole-normative attestation primitive.

**Ships with:** the parent plan `docs/plans/decision-context-gate-2026-05-29.md` + ADR 045 (`docs/decisions/045-decision-context-enforcement-surface.md` — DEC-1 of that plan, locking the Stop-hook reactive enforcement surface).

## Originating context

The conversation-tree substrate (ADR-031 r7/r8 / ADR-034 / ADR-032 §1 + §2 + §8 r2.1) already enforces the **spawn-side** of the Dispatch agent→user channel: `conversation-tree-state-gate.sh` (PreToolUse on `mcp__ccd_session__spawn_task` / `mcp__ccd_session_mgmt__start_code_task`) refuses to allow a spawn unless the state file contains a fresh, attestation-verified, branch-naming snapshot; `conversation-tree-stop-gate.sh` (Stop) verifies the same property at session boundary; `conversation-tree-emit.sh` (PreToolUse / SessionStart / Stop) is the writer that lands `branch-opened` / `concluded` / `branch-note-add` events through the `state.js` facade's attestation primitive. Spawn-side has Mechanism+Pattern; spawn-side is mechanically auditable; spawn-side cannot silently miss a branch.

The **message-side** of that same channel — the agent's outgoing prose surfaces that solicit a decision from Misha, ask him a question, assign him an action item, or log an autonomous action — had Pattern-only enforcement before this rule. `~/.claude/rules/conv-tree-orchestrator-emit.md` Layer D is verbatim: *"the agent treats every Dispatch spawn / conclude / cross-branch send as a tree-tracked event"* — Pattern-only, with no mechanical floor at the moment the prose lands in front of Misha. The verbal-vaporware gap this rule closes is catalogued in `~/.claude/rules/vaporware-prevention.md` "Residual gap (honest)": *"Verbal vaporware in conversation is not mechanically blocked. Claude Code has no PostMessage hook. claim-reviewer is self-invoked and can be skipped. This is the single unclosed gap from Generation 4."*

The decision-context surface is the specific sub-case of that broader gap where the agent's prose **solicits a decision** (enumerated options, terminal `?` + list, explicit "pick one" / "your call" / "which do you want"), **asks a substantive question** (request for a value / choice / opinion only Misha can supply), **assigns an action item** to Misha (a task only he can perform), or **logs an autonomous action** the agent took unilaterally — and surfaces it as prose-only without the structured fenced payload the tree substrate needs to land a `decision-raised` / `question-raised` / `action-added` / `autonomous-action-logged` event. Without the fence, the surface escapes audit: it never appears in the operator's "what's waiting on Misha" view; the branch reads as making progress while in fact stuck on an un-cataloged decision; and Misha's tracker shows nothing waiting until he scrolls back into chat and notices the un-fenced ask three sessions later.

## The rule in one sentence

**Every agent→user surface that solicits a decision, asks a substantive question, assigns an action item, or logs an autonomous action MUST be emitted as a structured Markdown fence per the grammar below; the Stop-hook reactive gate (`decision-context-gate.sh`) enforces it at session-end via the Tiered-Scan classifier; the residual Pattern is the agent's self-applied fence-first discipline at message-author time — incentivized by the redo-friction the Stop-block inflicts when the fence is forgotten.**

## The fence grammar (load-bearing — the wire format)

Every fence is a single fenced Markdown block delimited by `:::` lines:

```
::: <category> id=<id> [urgency=<value>] [reversibility_cost=<value>]
**Title:** <one-line summary of what's at stake>
**About:** <one-paragraph framing the operator needs to act on the surface>
**Background:** <prior context, prior decisions, prior attempts the operator should know about>
**<category-specific bold-prefixed fields>**
:::
```

Four categories share a common envelope (`id`, `label`, `title`, `about`, `background`, plus optional `urgency`, `expires_at`, `default_if_no_response`, `warn_at`, `blocks_on`, `connects_to`, `references`). Each category then carries additional category-specific fields. The complete field set per category — required vs. optional, allowed enum values, cross-field constraints — is locked by the sole-normative Zod schema at `neural-lace/conversation-tree-ui/state/decision-context-schema.js`. This rule documents the wire format; the Zod module IS the validator; do not redefine the schema here.

**Cross-field constraint (REQUIRED at the Zod layer for `decision`, `question`, `action_item_for_user`):** if `expires_at` is set, then `default_if_no_response` MUST be set; for `decision` specifically, `default_if_no_response` MUST reference an option whose `reversibility_cost` is `free` or `cheap`. (Rationale: auto-applying an expensive or irreversible default on expiry would be a Tier-3 irreversible decision the agent is forbidden from taking unilaterally — see `~/.claude/rules/planning.md` "Mid-Build Decisions" Tier 3.) `autonomous_action` is exempt from the cross-field constraint because it has no `expires_at` / `default_if_no_response` / `options` fields (it's a fait-accompli log, not a pending decision).

### Category 1 — `decision` (option-with-tradeoffs surface)

The agent has identified a fork in the road and wants Misha to pick. Worked example:

```
::: decision id=DEC-2026-05-30-001 urgency=high
**Title:** Cherry-pick conflict in Wave-2 merge: take ours, take theirs, or hand-resolve?
**About:** B3 and B4 both touched the rule file's enforcement table; cherry-picking B4 onto B3 surfaces a conflict on lines 142-167.
**Background:** B3 added the Tiered-Scan classifier rows; B4 added the fence-parser rows. Both modifications are correct in isolation; the conflict is purely textual.
**Question:** Which conflict-resolution strategy do you want me to apply?
**Why not decide alone:** Misha may want to manually inspect the merged output before I proceed; the choice between "ours" / "theirs" / "hand-resolve" has merge-history implications beyond this commit.
**Options:**
- **Take B3's version** (key=ours)
  **What it does:** keeps Tiered-Scan rows in their original position, drops B4's fence-parser rows.
  **Risk:** loses B4's fence-parser context until Wave-4 re-adds it.
  **Reversibility cost:** cheap
  **Cost:** ~2 min to redo B4's fence-parser merge in Wave 4.
- **Take B4's version** (key=theirs)
  **What it does:** keeps fence-parser rows, drops B3's Tiered-Scan rows.
  **Risk:** loses B3's classifier context until Wave-4 re-adds it.
  **Reversibility cost:** cheap
  **Cost:** ~3 min to redo B3's classifier merge in Wave 4.
- **Hand-resolve to union of both** (key=union)
  **What it does:** merges both contributions into a single coherent table.
  **Risk:** no automatic check that the merged ordering matches either contributor's intent.
  **Reversibility cost:** free
  **Cost:** ~5 min careful merge + re-run plan-reviewer.
**Recommendation:**
  **Option key:** union
  **Reasoning:** preserves both signals; both contributions are correct; cost is small.
**Reply with:** "take union" (or "take ours" / "take theirs")
**Expires at:** 2026-05-30T18:00:00Z
**Default if no response:** union
:::
```

The `decision` category's category-specific required fields are `question`, `why_not_decide_alone`, `options` (≥ 2 entries, each with `key` / `name` / `what_it_does` / `risk` / `reversibility_cost` / `cost`), `recommendation` (with `option_key` + `reasoning`), and `reply_with`. The cross-field constraint applies: `expires_at` set ⇒ `default_if_no_response` must reference an option whose `reversibility_cost` is `free` or `cheap`. In the example above, the `union` option has `reversibility_cost: free`, satisfying the constraint.

### Category 2 — `question` (substantive question whose answer only Misha can supply)

The agent needs a value, a choice, an opinion, or a specific format from Misha. Worked example:

```
::: question id=Q-2026-05-30-007 urgency=medium
**Title:** What value should `MAX_FALLBACK_QUEUE_DEPTH` default to?
**About:** Task 8's replay drainer caps the fallback queue at N entries before refusing to enqueue new events. Need your call on N.
**Background:** I considered 1000 (generous, ~1MB at the typical event size), 10000 (very generous), and 100 (tight, surfaces backend-unreachable conditions faster). Sibling reconciler scripts default to 1000.
**Question:** What value for `MAX_FALLBACK_QUEUE_DEPTH`?
**Why asking:** the default I pick locks the disk-usage budget; backing it out later is fine but I'd rather get it right the first time.
**What I've tried:** read the sibling `conv-tree-emit-reconciler.sh` defaults (1000); checked the disk-usage envelope (1000 entries ~= 1MB); checked the typical Misha-away duration to estimate steady-state queue depth (~ few hundred max).
**Answer shape:** value
**Reply with:** "use N=<value>"
:::
```

The `question` category's category-specific required fields are `question`, `why_asking`, `what_ive_tried`, and `answer_shape` (one of `value` / `choice` / `yes-no` / `opinion` / `specific-format`). The cross-field constraint applies if `expires_at` is set; the agent's default `default_if_no_response` is free text by convention (no `options[]` for the validator to cross-check against) and SHOULD describe a cheap or free fallback path the agent will take on expiry.

### Category 3 — `action_item_for_user` (assigned task Misha must perform)

The agent has work that's blocked on something only Misha can do — provide a credential, click a UI button on his machine, make a call to a vendor, etc. Worked example:

```
::: action_item_for_user id=AI-2026-05-30-003 urgency=high
**Title:** Rotate the `ANTHROPIC_API_KEY` in production Vercel env
**About:** The current key shipped in the Wave-1 commit accidentally and was force-pushed out within 90 seconds, but GitHub's secret-scanning alert says the key was indexed.
**Background:** Pre-push scanner caught the leak on the next push attempt and BLOCKed; force-push removed the commit; GitHub's alert URL is in the references list below.
**The ask:** Open Vercel dashboard → Settings → Environment Variables → rotate `ANTHROPIC_API_KEY` to a fresh value.
**Why assigned:** I can't authenticate to Vercel with my available credentials; this is a per-machine browser action only you can take.
**What I'm doing meanwhile:** drafting the post-incident write-up in `docs/lessons/2026-05-30-anthropic-key-rotation.md`; will pause Wave-2 dispatch until the rotation completes so no in-flight worker uses the leaked key.
**State:** open
**Reply with:** "rotated" (or "declined — leak is acceptable risk" with reasoning)
**Urgency:** high
**Expires at:** 2026-05-30T20:00:00Z
**Default if no response:** continue Wave-2 dispatch with the leaked key, log the residual risk in the failure-mode catalog
**References:** https://github.com/<org>/<repo>/security/secret-scanning/alerts/123
:::
```

The `action_item_for_user` category's category-specific required fields are `the_ask`, `why_assigned`, `what_im_doing_meanwhile`, and `state` (one of `open` / `done` / `declined` / `stale`). The cross-field constraint applies if `expires_at` is set.

### Category 4 — `autonomous_action` (fait-accompli log of an action the agent took unilaterally)

The agent took an action — typically a reversible one per `~/.claude/rules/discovery-protocol.md`'s decide-and-apply discipline for reversible decisions — and wants Misha to see the action in his tracker. NOT a pending decision; this is a notification. Worked example:

```
::: autonomous_action id=AA-2026-05-30-012
**Title:** Auto-applied: renamed `worker-3-rule` to `worker-task-3-rule` for consistency
**About:** Wave-2 worker branches followed inconsistent naming (`worker-3-rule` vs. `worker-task-4-hook`); I renamed B3's branch to match the longer form.
**Background:** Cherry-pick protocol relies on the branch name regex `worker-task-\d+-\w+` for orphan recovery; the shorter form would have evaded the regex.
**Action taken:** `git branch -m worker-3-rule worker-task-3-rule` on the parent worktree.
**Reasoning:** consistency with B4/B6/B8; matches the regex the orphan-recovery script uses; trivially reversible (one rename command).
**Reversibility:** trivially reversible — `git branch -m worker-task-3-rule worker-3-rule` undoes it; no downstream consumers were affected.
**References:** `~/.claude/rules/orchestrator-pattern.md` "Recovery from orphaned worktrees" (the regex the rename aligns with).
:::
```

The `autonomous_action` category's category-specific required fields are `action_taken`, `reasoning`, `reversibility`, and **at least one `references` entry** (enforced by the Zod refine at the schema layer — the autonomous-action emission must be cite-able). Note the deliberate absence of `expires_at` / `default_if_no_response` / `options` / `recommendation` / `reply_with` / `state`: the action is already done, so there is no pending deadline, no default, no choice, no recommended option, no expected reply phrasing, and no in-flight task state. The fence is a log, not a solicitation.

### Body format

Bold-prefixed fields (`**About:**`, `**Background:**`, `**Question:**`, `**Reply with:**`, etc.) are the canonical body format. Each field heading occupies its own line; the value follows on the same line and may continue on indented continuation lines until the next `**Field:**` heading or the closing `:::`. The complete list of recognized field names + their schema keys is defined in the `FIELD_NAME_TO_KEY` map of the sole-normative Zod module — that map is the single source of truth.

## The Tiered-Scan trigger taxonomy (`decision-context-gate.sh` Stop classifier)

The Stop-hook gate runs a cheap pre-filter regex over the last assistant message in `$TRANSCRIPT_PATH` (the agent-uneditable JSONL — the Gen-6 narrative-integrity property that makes Stop-hook scans non-bypassable by the agent's own edits). Three tiers:

### Tier 1 — hard block

A Tier-1 trigger fires when ANY of these are present in the message:

- **Enumerated options:** `A)` / `B)` / `C)` style lists, `1.` / `2.` / `3.` numbered lists framed as choices, or `- Option A` / `- Option B` bulleted lists where each item names a distinct alternative.
- **Terminal `?` followed by a list:** a question mark ending a sentence immediately followed by a bulleted or numbered list of plausible answers.
- **Explicit decision-soliciting phrases (verbatim, case-insensitive):** `pick one`, `your call`, `which do you want`, `which would you prefer`, `should I X or Y`.

When a Tier-1 trigger fires AND no fence is present, the gate BLOCKs Stop with the full Zod schema as the stderr error message. The agent MUST redo the message as a properly-fenced surface before session-end can complete. The redo-friction IS the corrective pressure: forgetting the fence costs a visible Stop block and an author-must-redo cycle.

When a Tier-1 trigger fires AND a fence IS present: the gate parses the fence via the sole-normative Zod module, validates it (including the `expires_at` × `default_if_no_response` × `reversibility_cost` cross-field constraint), emits the appropriate ADR-032 §2 event(s) via the `state.js` facade (see "Composition with ADR-032 §2 events" below), and ALLOWs Stop.

### Tier 2 — soft warn

A Tier-2 trigger fires on weaker signals:

- **Hedged decision-shaped phrasing:** `should I` / `would you like` / `do you want me to` followed by a substantive proposal (not a rhetorical follow-up).
- **Terminal `?` without an accompanying list:** a question mark ending the message but no bulleted alternatives.

Tier 2 does NOT block Stop. Instead, the gate appends a fresh follow-up marker (`.claude/state/decision-context/decision-context-followup-<timestamp>.txt`) that `decision-context-pending-surfacer.sh` (the SessionStart hook from Task 5 of the parent plan) reads on the NEXT session start and injects as a system-reminder summarizing the weak signal. The next-session reminder is the corrective pressure: the agent sees the unresolved weak signal and either fences-it-now (proper Tier-1 emission) or actively dismisses it as a Tier-3 rhetorical (operator-visible decision).

### Tier 3 — rhetorical whitelist (no-op)

A Tier-3 match fires on canonical rhetorical acknowledgment phrases:

- `does that make sense?`
- `right?`
- `make sense?`
- `sound good?`

These are conversational acknowledgments, not decision solicitations; treating them as gate-fire input would produce constant false positives. The gate is a deliberate no-op when a Tier-3 phrase matches and no Tier-1 or Tier-2 trigger ALSO fires. The whitelist is intentionally small and exact-match: ambiguous rhetoricals not on the list fall through to Tier 2 (soft-warn).

### Pre-filter cost model

The pre-filter regex is the cost-control mechanism per ADR 045 Consequences. Most session-end events have no Tier-1 / Tier-2 trigger and skip the `node`-subprocess Zod validation entirely. When a trigger fires, the cost is bounded — single-file Zod schema, single-message-body input, sub-second typical wall time. The pre-filter pattern is shared with the six sibling Stop hooks (see "Cross-references" below); they all exhibit the same "scan-cheap, validate-expensive-only-when-trigger-present" cost shape.

## Composition with `conv-tree-orchestrator-emit.md` Layer D

This rule mechanizes Layer D of `~/.claude/rules/conv-tree-orchestrator-emit.md` for the decision / question / action-item / autonomous-action subset. Concretely:

- **Layer A** (per-tool emit hook `conversation-tree-emit.sh`) — unchanged. It continues to fire on `mcp__ccd_session__spawn_task` / `mcp__ccd_session_mgmt__start_code_task` (and SessionStart / Stop) and emit `branch-opened` / `concluded` / `branch-note-add` events. Task 7 of the parent plan extends it to ALSO recognize a full fence block in the spawn prompt's body and emit the rich `item-details-set` payload (the existing simpler sentinels — `Instructions:` / `Recommendation:` / `Links:` — remain accepted for back-compat; the fence subsumes them as a richer form).
- **Layer B** (pre-stop reconciliation `conv-tree-emit-reconciler.sh`) — unchanged. Continues to scan the transcript JSONL at Stop-time and auto-fill spawn↔ledger drift.
- **Layer C** (5-minute heartbeat scheduled task) — unchanged. Continues to backstop crashed-session orphan branches.
- **Layer D** (the agent's self-applied fence-first discipline) — **now Mechanism+Pattern.** This rule + the Stop-hook gate together replace Layer D's prior Pattern-only enforcement for the four categories listed above. The Mechanism is the Stop hook (BLOCK on Tier-1 + no-fence; emit on Tier-1 + fence; soft-warn on Tier-2; no-op on Tier-3). The residual Pattern is the agent's self-applied fence-first discipline at message-author time — the redo-friction the BLOCK inflicts when the fence is forgotten is exactly the corrective pressure that makes the Pattern self-reinforcing.

The fence subsumes the existing simpler line-prefix sentinels (`Instructions:` / `Recommendation:` / `Links:`) that `conversation-tree-emit.sh` already parses in spawn prompts. Both formats remain accepted by Task 7's extended parser: the bare sentinels are the degenerate sentinel-only form of the fence; the fence is the full rich form. The hook prefers the fence (richer payload via `item-details-set`) when present and falls back to the sentinels (current behavior — emit `branch-opened` with a "missing rich details" warning) when only sentinels are present.

## Composition with ADR-032 §2 events

Each fence category maps to a specific combination of ADR-032 §2 event types. The mapping is fixed:

| Fence category | Emitted event(s) | Required fields per ADR-032 §2 |
|---|---|---|
| `decision` | `decision-raised` + `item-details-set` | `decision-raised`: `node_id`, `item_id`, `text` (the `Title` field). `item-details-set`: `node_id`, `item_id`, `details` (the structured rich payload — options table, recommendation, reply_with, urgency, expires_at, default_if_no_response, warn_at, blocks_on, connects_to, references). |
| `question` | `question-raised` + `item-details-set` | `question-raised`: `node_id`, `item_id`, `text` (the `Title`). `item-details-set`: `details` carries `question`, `why_asking`, `what_ive_tried`, `answer_shape`, envelope fields. |
| `action_item_for_user` | `action-added` + `item-details-set` | `action-added`: `node_id`, `item_id`, `text` (the `Title`). `item-details-set`: `details` carries `the_ask`, `why_assigned`, `what_im_doing_meanwhile`, `state`, envelope fields. Subsequent lifecycle events (`action-responded` / `action-done` / `item-unchecked` / `deferred` / `defer-cleared` / `item-backlogged`) are emitted by `decision-context-reply-emit.sh` when Misha replies. |
| `autonomous_action` | `autonomous-action-logged` (new additive event type per DEC-2 of the parent plan) | `autonomous-action-logged`: `node_id`, `text` (the `Title`), `details` (with `action_taken`, `reasoning`, `reversibility`, `references` as sub-fields). Added to `state/schema.js` `EVENT_TYPES` enum + `EVENT_REQUIRED_FIELDS` map in commit `8407a48`; additive within major 1 per ADR-032 §1 ("Adding a new event type to EVENT_TYPES is additive (no bump)"); `schema_version` stays at 1. |

The emissions flow through the `state.js` facade (the ADR-032 §8 r2.1 sole-normative attestation primitive). The Stop hook does NOT open a parallel HTTP-direct path to the GUI's `127.0.0.1:7733/api/event` endpoint; the GUI watches the state file written by `appendEvent` and re-renders on file change, per the existing dual-write contract. Bypassing the facade would break the attestation primitive and is forbidden by the same sole-normative-validator principle that binds the schema module.

When `decision-context-reply-emit.sh` (Task 6) fires on Misha's reply, it emits the lifecycle-continuation events — `answered` (for a `question`), `action-done` (for an `action_item_for_user`), or `item-details-set` (for a `decision` whose `default_if_no_response` was chosen, or for any category whose envelope field changed). Same facade; same attestation primitive; same idempotency-on-`event_id` semantics.

## Sole-normative validator

The Zod module at `neural-lace/conversation-tree-ui/state/decision-context-schema.js` is the **SOLE NORMATIVE** parser + validator. The four Zod schemas (`DecisionSchema`, `QuestionSchema`, `ActionItemForUserSchema`, `AutonomousActionSchema`) define the field set per category; the dispatchers `validateFence(category, payload)` + `safeValidateFence(category, payload)` route to the per-category schema; the fence-block parser `parseFenceBlock(rawText)` extracts the raw payload from the Markdown fence shell. The Stop hook (`decision-context-gate.sh`) calls into this module via `node -e require(…)`; the GUI imports the same module; NO shell re-implementation anywhere in the codebase; NO parallel parser at any layer.

This is the same single-implementation-determinism principle that ADR-032 §8 r2.1 binds for the snapshot-attestation primitive: snapshot trust is established ONLY by the canonical state-library's `verifySnapshotAttested`, never by a shell re-canonicalization. The same principle applies here: fence trust is established ONLY by the canonical Zod module, never by a shell regex re-implementation. The cost of two parsers diverging silently is a class of bug the harness has explicitly chosen to forbid by structure.

If the schema needs to change (a new required field, a new enum value, a new cross-field constraint), the change lands in `neural-lace/conversation-tree-ui/state/decision-context-schema.js` and `state/selftest.js` exercises the new behavior; nothing else changes. Both the hook and the GUI pick up the new schema on next invocation. Schema-version-skew handling (hook compiled against a future major; GUI on current major) follows ADR-031 r7 Pin 2: the gate REJECTs schema-too-new at parse time with a distinct "schema too new — upgrade" error rather than falling back to a partial parse.

## Cross-references

- **Parent plan:** `docs/plans/decision-context-gate-2026-05-29.md` — the multi-task plan that ships this rule + the hooks + the schema module + the live Walking Skeleton demonstration. DEC-1 locks the Stop-hook reactive enforcement surface; DEC-2 locks the new `autonomous-action-logged` additive event type.
- **ADR 045:** `docs/decisions/045-decision-context-enforcement-surface.md` — the architectural decision record for DEC-1; documents the rejected alternatives (convention-only with post-hoc transcript-mining; wait for `mcp__ccd_session__send_user_message` to be exposed; defense-in-depth Stop-hook AND post-hoc) and the six sibling Stop-hook precedents.
- **ADR-031 r7/r8:** `docs/decisions/031-conversation-tree-ui-architecture.md` — the file-mediated state contract + the spawn enforcement surface (PreToolUse on `mcp__ccd_session__spawn_task` / `mcp__ccd_session_mgmt__start_code_task` only — Dispatch-only per r8 / ADR-034). This rule's message-side mechanism is orthogonal to that spawn-side scoping.
- **ADR-032 §1 + §2 + §8 r2.1:** `docs/decisions/032-conversation-tree-state-schema.md` — §1 is the additive-within-major contract that authorizes the new `autonomous-action-logged` event type without a `schema_version` bump; §2 is the `EVENT_TYPES` enum + `EVENT_REQUIRED_FIELDS` map this rule's emissions populate; §8 r2.1 is the sole-normative attestation primitive the `state.js` facade composes with.
- **ADR-034:** `docs/decisions/034-conversation-tree-scope-dispatch-only.md` — the Dispatch-only scoping of the spawn-side matchers. This rule's message-side surface is independent of that scoping (the Stop hook reads `$TRANSCRIPT_PATH` regardless of whether the session is Dispatch or standalone; the message-side gate applies in every session mode).
- **Layer D Pattern this Mechanism implements:** `~/.claude/rules/conv-tree-orchestrator-emit.md` — the agent's self-applied fence-first discipline at message-author time; this rule + the Stop-hook gate mechanize Layer D's prior Pattern-only enforcement for the four decision-context categories.
- **Sibling rule (Mechanism+Pattern Stop-hook gate precedent):** `~/.claude/rules/acceptance-scenarios.md` — the runtime acceptance gate (`product-acceptance-gate.sh`, Stop hook position 4) — the canonical precedent for a Mechanism+Pattern split where a Stop-hook gate mechanically enforces the substance the rule documents. The decision-context-gate follows the same architectural pattern.
- **Sibling rule (spawn-side companion):** `~/.claude/rules/conversation-tree-state.md` — the spawn-side companion to this message-side rule. Together they enforce the conversation-tree substrate's mechanical floor on BOTH sides of the agent↔user channel.
- **Verbal-vaporware residual gap this rule closes:** `~/.claude/rules/vaporware-prevention.md` "Residual gap (honest)" — the Gen-4 acknowledgment that verbal vaporware in conversation is not mechanically blocked. The decision-context-gate closes that gap for the four named categories; the broader gap (every feature-claim sentence in prose) remains Pattern-only with `claim-reviewer` as the self-invoked check.
- **Six sibling Stop hooks** (the reactive-Stop-with-redo-required pattern this rule adopts): `continuation-enforcer.sh`, `narrate-and-wait-gate.sh`, `goal-coverage-on-stop.sh`, `deferral-counter.sh`, `imperative-evidence-linker.sh`, `principles-compliance-gate.sh` — all wired in `adapters/claude-code/settings.json.template`. Shared `~/.claude/hooks/lib/stop-hook-retry-guard.sh` library is the loop-break mechanism the decision-context-gate inherits (3 identical-failure retries → downgrade to warn + log to `.claude/state/unresolved-stop-hooks.log`).
- **Sole-normative Zod module:** `neural-lace/conversation-tree-ui/state/decision-context-schema.js` — the single source of truth for the field set per category, the cross-field constraints, the enum values, the fence-block parser, and the dispatcher functions. Both the hook and the GUI consume this module exclusively.

## Enforcement

| Layer | What it enforces | File | Status |
|---|---|---|---|
| Rule (this doc) | Fence grammar (four categories, common envelope, category-specific fields), Tiered-Scan trigger taxonomy (Tier 1/2/3), composition with `conv-tree-orchestrator-emit.md` Layer D, composition with ADR-032 §2 events, sole-normative validator principle | `adapters/claude-code/rules/decision-context.md` | landing (Task 3 of parent plan) |
| Mechanism (Stop hook) | Tier-1 + no fence → BLOCK Stop with schema-as-error; Tier-1 + fence → parse via Zod, emit `decision-raised` / `question-raised` / `action-added` / `autonomous-action-logged` + `item-details-set` via the `state.js` facade; Tier-2 → append follow-up marker for next-SessionStart surfacing; Tier-3 → whitelisted no-op | `adapters/claude-code/hooks/decision-context-gate.sh` | landing (Task 4 of parent plan) |
| Mechanism (UserPromptSubmit hook) | Scans user's reply for open node IDs + `reply_with` literal phrases; emits `answered` / `action-done` / `item-details-set` lifecycle continuation events via the same facade | `adapters/claude-code/hooks/decision-context-reply-emit.sh` | landing (Task 6 of parent plan) |
| Mechanism (SessionStart hook) | Reads attestation-verified snapshot; emits system-reminder per unresolved decision-context item; drains Tier-2 follow-up markers as previous-turn weak-signal reminders | `adapters/claude-code/hooks/decision-context-pending-surfacer.sh` | landing (Task 5 of parent plan) |
| Sole-normative validator (Zod module) | Single source of truth for the field set per category, cross-field constraints, enum values, fence-block parser; consumed by both the hook (via `node -e`) and the GUI (via `require(…)`); no parallel parser anywhere | `neural-lace/conversation-tree-ui/state/decision-context-schema.js` | landed (Task 2 of parent plan, commit `8407a48`) |
| Sole-normative state-library facade | Atomic `appendEvent` + attestation primitive (`verifySnapshotAttested`) per ADR-032 §8 r2.1; the only path through which the Stop hook + the reply-emit hook write events to the tree | `neural-lace/conversation-tree-ui/state/state.js` (unchanged; this rule composes with it) | landed |
| Pattern (agent self-applied) | Fence-first discipline at message-author time — the agent emits the fence BEFORE the message lands, not after a Stop block forces a redo. Redo-friction is the corrective pressure that makes the Pattern self-reinforcing | (Pattern) | always |
| User authority | The user retains interrupt authority when an un-fenced decision-soliciting message slips through (false-negative in the Tier-1 classifier OR Stop-hook retry-guard downgrade-to-warn after 3 retries) | (Pattern) | always |

The rule is documentation (Pattern-level for the agent's self-applied discipline). The four mechanism layers (Stop hook, UserPromptSubmit hook, SessionStart hook, Zod module) plus the underlying state-library facade are hook + module-enforced. Together they implement ADR 045's Stop-hook reactive enforcement surface: at session-end the gate mechanically requires the fence when a Tier-1 trigger fires, the schema is validated by the sole-normative Zod module, the events flow through the sole-normative state-library facade, the GUI re-renders on file change, and Misha's "what's waiting on me" view becomes structurally truthful. The agent's self-applied fence-first discipline is the residual Pattern, incentivized by the redo-friction the BLOCK inflicts when the fence is forgotten.

## Scope

This rule applies in every project whose Claude Code installation has the four new hooks (`decision-context-gate.sh`, `decision-context-reply-emit.sh`, `decision-context-pending-surfacer.sh`, `decision-context-replay.sh`) wired in `settings.json.template`'s Stop / UserPromptSubmit / SessionStart chains AND has the sole-normative Zod module at `neural-lace/conversation-tree-ui/state/decision-context-schema.js`. Adoption is implicit on harness install/sync (`install.sh` propagates the canonical files into `~/.claude/`). For sessions without the wiring (older harness installs predating Task 9 of the parent plan), the rule degrades to Pattern-only — the agent's self-applied fence-first discipline is the only enforcement, and the redo-friction corrective pressure is absent.

The rule binds in every session mode — interactive local, parallel local, cloud-remote / Dispatch orchestrator, scheduled, and agent-team — because decision-soliciting / question-asking / action-item-assigning / autonomous-action-logging surfaces appear in all of them. The Stop-hook surface fires regardless of session mode: it reads `$TRANSCRIPT_PATH`'s last assistant message which exists in every mode. For cloud-remote sessions that don't load `~/.claude/` hooks (per ADR-031 r7's accepted cloud blind spot), the rule degrades to Pattern-only the same way it does for older harness installs; the operator's interrupt authority is the residual backstop.
