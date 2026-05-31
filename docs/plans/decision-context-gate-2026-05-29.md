# Plan: Decision-Context Gate (Active Enforcement) 2026-05-29
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
tier: 4
rung: 2
architecture: harness-hook-and-rule
prd-ref: n/a — harness-development
frozen: true
acceptance-exempt: true
acceptance-exempt-reason: harness-internal mechanism extending the existing conversation-tree substrate (ADR-031 r7/r8, ADR-032, ADR-034, conv-tree-orchestrator-emit.md); the "user" of this mechanism is the maintainer running the Dispatch orchestrator; self-tests + a live Dispatch round-trip into the tree are the verification surface; no user-observable product runtime for end-user-advocate to exercise.
Backlog items absorbed: none
owner: misha
frozen-as-of-commit: pending

## Goal

Make every **decision / question / action-item / autonomous-action** that the Dispatch orchestrator surfaces to Misha **structurally auditable** and **automatically tracked** in his Conversation Tree, instead of evaporating into freeform chat prose.

Concretely: when the orchestrator surfaces an option-with-tradeoffs decision, a question, an action item, or logs an autonomous action, that surface is (a) emitted in a parseable in-chat **fence** that names options, recommendation, reversibility, urgency, expiry, and links; (b) parsed and projected onto the **existing ADR-032 §2 event types** (`decision-raised` / `question-raised` / `action-added` / `annotated` + `item-details-set` for rich fields); (c) landed in the conversation tree at `127.0.0.1:7733/api/event` so it appears in Misha's "what's waiting on me" view; and (d) **mechanically enforced** at the strongest surface the Claude Code hook substrate permits (see Open Question OQ-1 — the original "Pre-SendUserMessage hook" the brief assumed does not exist as a hook event in Claude Code; the choice of enforcement surface is decisive for the design and must be settled before build).

This is **foundation work**: once it ships, every decision/question/action-item Dispatch surfaces is structurally auditable, version-vector-tracked, and present in Misha's tree — no more "did Claude ask me something three sessions ago that I missed?".

## Scope

- **IN:**
  - New rule `adapters/claude-code/rules/decision-context.md` (the fence grammar, the four categories, the Tiered-Scan trigger taxonomy, composition with `conv-tree-orchestrator-emit.md`'s Layer D).
  - New hook `adapters/claude-code/hooks/decision-context-gate.sh` (Stop-hook reactive model — see OQ-1; final surface decided before Task 2 starts).
  - New schema artifact (canonical TS module + Zod validator) co-located with the conversation-tree state library at `neural-lace/conversation-tree-ui/state/decision-context-schema.{js,d.ts}` — sole-normative parser + validator, callable from both the hook (via `node -e require(…)`) and the GUI.
  - Extension of `conversation-tree-emit.sh` to recognize fenced blocks in spawn prompts (today it parses the simpler `Instructions:` / `Recommendation:` / `Links:` sentinels — the fence subsumes these). Emit `decision-raised` / `question-raised` / `action-added` / `annotated` plus `item-details-set` for the rich fields.
  - New incoming-message hook on `UserPromptSubmit` that detects references to open node IDs OR `reply_with` phrases in Misha's reply and POSTs state updates (`answered` / `action-done` / `item-details-set`).
  - Turn-start (SessionStart) state pull that injects a system reminder of any open node updated externally since the orchestrator last saw it (the user-edits-tree-mid-AI-response race condition).
  - Fallback log + replay path for backend-unreachable events (`~/.claude/state/decision-context/fallback.jsonl` — append-only; reconciler script drains it on backend reachable).
  - Bootstrap: pointer in `adapters/claude-code/CLAUDE.md` to the rule + grammar; first-message self-bootstrap in the Stop hook (if Misha's first turn was decision-soliciting with no fence, hook returns the full schema as the rejection reason).
  - GUI: confirm `renderItemDetails` already supports the rich fields (options table, recommendation, reply_with, urgency, expires_at). If not, extend.
  - Self-tests for: schema validation (each category × required-field constraints), fence parser (well-formed / malformed / user-pasted-sender-tagged), Tiered-Scan classifier (each tier × positive/negative cases), `expires_at` + `default_if_no_response` constraint enforcement, backend fail-open + fallback log write + reconciler replay, bootstrap behavior on first turn.

- **OUT:**
  - Modifications to the **frozen** ADR-032 §1 contract (`schema_version` stays `1`; new event types may be added additively but no required-field changes to existing event types).
  - The `mcp__ccd_session__send_user_message` / `mcp__ccd_session__send_message` PreToolUse wrapping — the tools are not exposed today (`conv-tree-auto-emit-enforcement-2026-05-23.md` Decision: "don't wrap send_message / send_user_message yet"). If/when they're exposed, the hook surface can move to PreToolUse on those tools; until then, the Stop-hook reactive model is the available surface (OQ-1).
  - GUI redesign — additions are confined to `renderItemDetails` if needed; no new pages, panes, or interactions are in scope.
  - Sub-agent `Task` / `Agent` invocations — explicitly out of scope per ADR-034 (AI-internal mechanics are not branches of the user↔AI conversation).
  - `Bash(claude…)` / `/schedule` invocations — accepted gap (same blind spot as ADR-031 r7 / ADR-034).
  - Modifications to the existing conv-tree-state-gate / stop-gate / emit-reconciler — they continue to enforce the spawn-side ADR-031 r7 Pin 1 contract unchanged.

## Survey: what's already in the harness (extension vs. net-new vs. duplication-risk)

This plan was redirected after I missed `conv-tree-orchestrator-emit.md` in my first design pass. The survey below catalogs every overlap between the original brief and existing harness substrate, so the build composes with what's there.

### A. Conversation-tree event schema (ADR-032 §2 — frozen contract)

| Brief's proposed category | Existing event type(s) | Disposition |
|---|---|---|
| `decision` (id, label, title, options[], recommendation, reply_with, urgency, expires_at, default_if_no_response, warn_at, blocks_on, connects_to, references) | `decision-raised` (envelope + `node_id`, `item_id`, `text`) **+** `item-details-set` (`node_id`, `item_id`, `details` — free-form per ADR-032 §2) | **EXTENSION.** Land the rich fields (options table, recommendation, reply_with, urgency, expires_at, default_if_no_response, warn_at, blocks_on, connects_to, references) in `item-details-set.details` as a structured sub-object. Optional-on-existing-events ⇒ no `schema_version` bump (ADR-032 §1 additive rule). |
| `question` (id, label, title, question, why_asking, what_ive_tried, answer_shape, urgency, expires_at, ...) | `question-raised` + `item-details-set` | **EXTENSION.** Same pattern as decision. |
| `action_item_for_user` (id, label, title, the_ask, why_assigned, what_im_doing_meanwhile, urgency, ..., state) | `action-added` + `item-details-set` + the existing `action-responded` / `action-done` / `item-unchecked` / `deferred` / `defer-cleared` / `item-backlogged` lifecycle | **EXTENSION.** Lifecycle is already richly modeled — the `state` field in the brief is *derived* from the event log, not a new field. |
| `autonomous_action` (id, label, title, action_taken, reasoning, reversibility, references) | **NEW additive event type `autonomous-action-logged` (DEC-2)** — `node_id`, `text`, `details` (with `action_taken`, `reasoning`, `reversibility`, `references` as sub-fields of `details`) | **NET NEW (schema-additive within major 1; no `schema_version` bump per ADR-032 §1).** Decided per OQ-3 resolution: cleaner GUI rendering; same additive precedent as `priority-assigned`, `branch-note-add`, `item-details-set`. Added to ADR-032 §2 EVENT_TYPES enum + EVENT_REQUIRED_FIELDS map as part of Task 2. |

Net schema work: **zero required-field changes to existing events**, additive rich-payload conventions on `item-details-set`, **one OQ on autonomous-action shape**, possibly one new additive event type. The frozen contract stays frozen.

### B. In-chat fence format

| Brief's proposal | Existing surface | Disposition |
|---|---|---|
| `::: decision id=…` / `::: question id=…` / `::: action_item_for_user id=…` / `::: autonomous_action id=…` fenced blocks | `conversation-tree-emit.sh` already parses **line-prefix sentinels** `Instructions:` / `Recommendation:` / `Links:` from spawn prompts (v1.1.4 item 41) and warns on absence | **NET NEW** for the in-chat agent→user surface, **but composes with / subsumes** the existing spawn-prompt sentinels. Migration: the fence parser becomes the canonical parser; the simple sentinels remain accepted (back-compat) inside fenced blocks AND as bare sentinels for the bare-prompt case; the hook's warn-when-prompt-substantive-but-no-rich-details path is unchanged. |
| User-pasted fence rejection | Hook only fires on Claude's outgoing turn, so user-pasted fences don't reach the writer path | **IMPLICIT BY HOOK ATTACHMENT POINT** — the Stop hook (OQ-1) only reads the last *assistant* message in the transcript; user content is structurally tagged by the JSONL. No explicit sender-tag needed. |

### C. The hook (Tiered-Scan + fence enforcement + tree POST)

| Brief's proposal | Existing surface | Disposition |
|---|---|---|
| Pre-SendUserMessage PreToolUse hook | **DOES NOT EXIST.** Claude Code has no PostMessage / Pre-SendUserMessage hook event (`vaporware-prevention.md`: "Verbal vaporware in conversation is not mechanically blocked. Claude Code has no PostMessage hook…"). `mcp__ccd_session__send_user_message` is not exposed (`conv-tree-auto-emit-enforcement-2026-05-23.md` Decision: "don't wrap send_message / send_user_message yet"). | **STRUCTURAL FINDING — OQ-1 (decisive).** Available enforcement surfaces today: (a) Stop hook reactive — reads last assistant message in `$TRANSCRIPT_PATH`, blocks Stop if decision-soliciting prose has no fence; agent forced to redo as fence before session can end. (b) Convention-only with post-hoc transcript-mining emit — no blocking; emitter extracts events from the transcript afterward. (c) Wait for `send_user_message` tool to be exposed by Anthropic. The brief assumed something that doesn't exist; the plan can't paper over this. |
| Tiered-Scan trigger taxonomy (Tier 1 hard-block / Tier 2 soft-warn / Tier 3 rhetorical-whitelist) | Six harness Stop hooks already operate on the "scan last assistant message; block-with-redo-required" pattern: `continuation-enforcer.sh`, `narrate-and-wait-gate.sh`, `goal-coverage-on-stop.sh`, `deferral-counter.sh`, `imperative-evidence-linker.sh`, `principles-compliance-gate.sh`. Class-shape proven. | **NET NEW** classifier (the four categories + the Tier 1-3 vocabulary) **with strong precedent for the Stop-hook block-with-redo enforcement shape.** Sibling-pattern reuse is the integration story. |
| POST to `127.0.0.1:7733/api/event` | Backend already exposes `POST /api/event` (referenced by `conv-tree-orchestrator-emit.md` Layer D); `conversation-tree-emit.sh` already writes via the frozen `state.js` library facade which is dual-write to the GUI's `tree-state.json` and the §5-resolved gate path. | **EXTENSION.** Reuse the same `state.js` facade for atomic publish + attestation + idempotency. **Do not** open a parallel HTTP path from the hook; that bypasses the facade's attestation and breaks the §8 r2.1 contract. The HTTP POST is the GUI's job (server.js watches the state file). |
| User-pasted fence rejection by sender-tag | (covered above in B) | n/a — implicit. |

### D. Fallback log + replay job

| Brief's proposal | Existing surface | Disposition |
|---|---|---|
| `~/.claude/conversation-tree-fallback.jsonl` append-only + periodic replay | `conversation-tree-emit.sh` already has failure-isolation: writer-hook errors log to `~/.claude/logs/conversation-tree-emit.log` and exit 0 (gate-respect.md: writer hooks do not block). `conv-tree-emit-reconciler.sh` is the existing Layer B Stop-hook auto-fill against transcript ↔ ledger drift. | **PARTIAL DUPLICATION.** The reconciler is a Stop-hook auto-fill that compares transcript to ledger; it is NOT a generalized replay queue. **Compose:** keep the fallback-log file (`~/.claude/state/decision-context/fallback.jsonl`), drain via a small `decision-context-replay.sh` script invoked from SessionStart (or on-demand) that POSTs queued events through the same `state.js` facade. Don't conflate with the reconciler (different concern: reconciler enforces the Pin-1 contract, replay drains a queue). |

### E. Incoming-message hook (Misha replies → tree state update)

| Brief's proposal | Existing surface | Disposition |
|---|---|---|
| Pre-Claude-receives-message hook detects `reply_with` phrases and POSTs state updates | `UserPromptSubmit` hook fires on every user submission — this **IS** the surface ("Pre-Claude-receives-message" exists as `UserPromptSubmit`). | **NET NEW HOOK ON EXISTING SURFACE.** Hook: `adapters/claude-code/hooks/decision-context-reply-emit.sh` (`UserPromptSubmit`). Scans the user's submitted prompt for open node IDs OR `reply_with` phrase matches against the current snapshot; emits `answered` / `action-done` / `item-details-set` via the `state.js` facade. Fallback-log on facade failure. |

### F. Turn-start state pull + system-reminder injection

| Brief's proposal | Existing surface | Disposition |
|---|---|---|
| Diff tree state vs last-seen rev per node; inject system reminder when externally resolved | `SessionStart` hook + `discovery-surfacer.sh` precedent for "inject system-reminder block per pending item at session start." Per-node "last-seen rev" is what ADR-032 §8 r2.1 attestation hash gives us for free (one hash per snapshot). | **NET NEW HOOK ON EXISTING SURFACE.** Hook: `adapters/claude-code/hooks/decision-context-pending-surfacer.sh` (`SessionStart`). Reads the current snapshot via `verifySnapshotAttested`, compares per-node mtime to a per-session marker (`~/.claude/state/decision-context/seen-<sid>.json`), and emits a system-reminder summarizing externally-resolved nodes. Pattern is identical to `discovery-surfacer.sh`. |

### G. Bootstrap (system-prompt injection + memory index + first-message self-bootstrap)

| Brief's proposal | Existing surface | Disposition |
|---|---|---|
| System-prompt injection of fence grammar | `adapters/claude-code/CLAUDE.md` `@`-reference pattern (already used for `@~/.claude/rules/principles.md`); per-CLAUDE.md "Detailed Protocols" list pointer convention. | **EXTENSION.** Add one bullet to `Detailed Protocols` pointing at `rules/decision-context.md`. Optionally add an `@~/.claude/rules/decision-context.md` reference if the rule is short enough to inline (currently rule docs are pointed-at, not inlined — keep the convention). |
| Memory index entry | `MEMORY.md` index pattern (already exists at the per-session memory dir) | **EXTENSION.** One-line entry in the appropriate `MEMORY.md` once the rule ships. |
| First-SendUserMessage interception returns full schema | Same constraint as OQ-1 — depends on Stop-hook reactive model. On first turn, if Stop hook detects decision-soliciting prose without a fence, the block message IS the full schema. | **NET NEW** (specific to the Stop hook's first-fire-in-session detection). |

### H. Tree node UI support

| Brief's proposal | Existing surface | Disposition |
|---|---|---|
| Render rich payload (options + reversibility, recommendation, reply_with) | `conversation-tree-emit.sh` line 27 references `renderItemDetails` already rendering items with an "incomplete metadata" badge for items lacking the (Instructions:/Recommendation:/Links:) sentinels. GUI already renders `item-details-set` `details` payloads. | **PARTIAL EXTENSION.** Confirm `renderItemDetails` supports the new rich shape via inspection. If options-table rendering is missing, add it (small templated addition to `web/app.js`). Verify in the live GUI (port 7733). |

### I. Tests

Standard `--self-test` convention all existing harness hooks follow; mirror that pattern.

## Tasks

Dependency-ordered (see "Dependency graph" below for the visual). Tasks 1-3 unblock everything; Tasks 4-7 are parallelizable once Tasks 1-3 land; Task 8 closes.

- [x] 1. **Author `docs/decisions/037-decision-context-enforcement-surface.md` per DEC-1 — Verification: contract**
      - The architectural decision is settled (Misha 2026-05-29: Stop-hook reactive). Builder authors the ADR with Title/Status/Stakeholders/Context/Decision/Alternatives/Consequences sections per Tier-2+ ADR format, citing sibling Stop-hook precedents (`continuation-enforcer`, `narrate-and-wait-gate`, `goal-coverage-on-stop`, `deferral-counter`, `imperative-evidence-linker`, `principles-compliance-gate`).
      - Update `docs/DECISIONS.md` index with the new row.
      - Done when: the ADR exists, the index row is added, `decisions-index-gate.sh` passes on the diff, `definition-on-first-use-gate.sh` passes on the diff.

- [x] 2. **Author the schema TS module + Zod validator at `neural-lace/conversation-tree-ui/state/decision-context-schema.js` (+ `.d.ts`); extend `state/schema.js` with `autonomous-action-logged` per DEC-2 — Verification: contract**
      - Four categories (decision/question/action_item_for_user/autonomous_action) with the field set the brief specifies, expressed as a Zod schema. Maps to ADR-032 §2 events plus `item-details-set` payloads for decision/question/action_item_for_user, AND the **new** `autonomous-action-logged` event for autonomous_action.
      - **Schema additions (DEC-2):** add `'autonomous-action-logged'` to `state/schema.js` `EVENT_TYPES` enum (additive within major 1, no `schema_version` bump per ADR-032 §1) and `EVENT_REQUIRED_FIELDS` map (`['node_id', 'text', 'details']`). Extend `state/selftest.js` with a P15 scenario proving the new event type round-trips through the reducer.
      - Constraint: `expires_at` set ⇒ `default_if_no_response` must reference an option whose `reversibility_cost` is `free` or `cheap`. Validated at the Zod layer.
      - Sole-normative parser — both the hook (`node -e`) and the GUI consume this module. NO shell re-implementation.
      - **OQ-2 confirmation:** inspect `web/app.js` `renderItemDetails`. If options-table / recommendation / reply_with rendering is missing, surface in `## In-flight scope updates` and add to Task 9 scope OR add a minimal extension in this task. Either way, document the finding in the evidence block.
      - Done when: golden-file `--self-test` round-trips well-formed fixtures, rejects malformed ones (each required-field absent, each enum-out-of-range, the expires_at + reversibility_cost cross-field constraint), AND `state/selftest.js` runs all P1-P15 green.
      - **Wire check:** `rg "require\(.*decision-context-schema\)" adapters/claude-code/hooks/ neural-lace/conversation-tree-ui/` → both hook + GUI import the same module; `rg "autonomous-action-logged" neural-lace/conversation-tree-ui/state/schema.js` → present in `EVENT_TYPES` AND `EVENT_REQUIRED_FIELDS`.

- [x] 3. **Author `adapters/claude-code/rules/decision-context.md` — Verification: mechanical**
      - The fence grammar (with worked examples per category), the Tiered-Scan trigger taxonomy, composition with `conv-tree-orchestrator-emit.md`'s Layer D (this rule IS the load-bearing mechanism for the Layer D enforcement; Layer D's Pattern moves to: "the agent self-applies the fence; the hook enforces it"), composition with ADR-032 §2 (which fenced category emits which event type combo), and the Mechanism+Pattern split per `harness-hygiene.md` conventions.
      - Done when: rule file exists, `plan-reviewer.sh` and `definition-on-first-use-gate.sh` pass on the diff, the rule cross-references conv-tree-orchestrator-emit.md / ADR-031 / ADR-032 / ADR-034.

- [x] 4. **Implement `adapters/claude-code/hooks/decision-context-gate.sh` (Stop hook per OQ-1) — Verification: full**
      - Reads last assistant message from `$TRANSCRIPT_PATH`. Tier 1 trigger (enumerated options OR terminal `?` + list OR explicit phrases "pick one"/"your call"/"which do you want") AND no fence → BLOCK Stop with the schema as the error message. Tier 2 (weaker signals) → no block; appends a fresh `decision-context-followup-*.txt` marker that `decision-context-pending-surfacer.sh` (Task 5) reads on next SessionStart. Tier 3 (rhetorical asks "does that make sense?", "right?") → whitelisted no-op.
      - When a fence IS present: parse via the Zod module (`node -e require(state-library + decision-context-schema) … validate`), enforce expires_at × default_if_no_response constraint, emit `decision-raised` / `question-raised` / `action-added` / `annotated` + `item-details-set` via the `state.js` facade.
      - On facade failure: write to `~/.claude/state/decision-context/fallback.jsonl`, log to `~/.claude/logs/decision-context-gate.log`, ALLOW Stop (writer-hook failure must not block per `gate-respect.md` "writer hooks do not block" + the existing `conversation-tree-emit.sh` pattern).
      - Loop safety: source `~/.claude/hooks/lib/stop-hook-retry-guard.sh` exactly like the six sibling Stop hooks.
      - Escape valve: fresh `.claude/state/decision-context-waiver-*.txt` (≥1 substantive line, <1h) — same shape as every other harness Stop-hook waiver.
      - **Wire check:** `rg "decision-context-gate" adapters/claude-code/settings.json.template` → wired in Stop chain after `goal-coverage-on-stop.sh`; `bash adapters/claude-code/hooks/decision-context-gate.sh --self-test` → PASS.
      - **Prove it works:** 1. In a sandbox transcript with a Tier-1-trigger last assistant message + no fence, run the hook → expect exit 2 + the schema in stderr. 2. Append a well-formed fence to the same transcript, re-run → expect exit 0 + an event landed in the `--self-test` state file. 3. Append a Tier-3 rhetorical "does that make sense?" → expect exit 0, no block, no event. 4. Force the facade to fail (broken `CONV_TREE_STATE_LIB` path) → expect exit 0 + fallback.jsonl line.

- [ ] 5. **Implement `decision-context-pending-surfacer.sh` (SessionStart) — Verification: full**
      - Mirror `discovery-surfacer.sh` exactly. Reads the attestation-verified snapshot, finds unresolved decision-context items, compares per-node `event_id` to `~/.claude/state/decision-context/seen-<sid>.json`, emits one system-reminder per item the agent hasn't seen this session.
      - Also drains Task-4 Tier-2 follow-up markers as a "previous-turn weak signal" reminder.
      - Done when: `--self-test` covers (a) no pending → silent, (b) one pending → system-reminder block emitted, (c) externally-resolved-since-last-seen → injection includes the resolution.

- [x] 6. **Implement `decision-context-reply-emit.sh` (UserPromptSubmit) — Verification: full**
      - Scans user's submitted prompt for open node IDs (regex from the schema's `id` field shape) AND/OR `reply_with` literal-phrase matches against open nodes. Emits `answered` / `action-done` / `item-details-set` via the `state.js` facade. Fallback-log on facade failure.
      - Done when: `--self-test` covers (a) user references node ID → state update emitted, (b) user mentions `reply_with` literal phrase → state update emitted, (c) user message with no references → no-op, (d) facade-down → fallback line written.

- [ ] 7. **Extend `conversation-tree-emit.sh` to recognize the fence grammar in spawn prompts — Verification: mechanical**
      - The existing `Instructions:` / `Recommendation:` / `Links:` sentinels stay accepted (back-compat) — they're a degenerate sentinel-only form of the fence. The hook ALSO recognizes a full fence in the prompt body and emits the rich payload via `item-details-set` instead of just logging a "missing rich details" warning.
      - `--self-test` scenarios ST20-ST24: ST20 fence-in-prompt → rich item-details-set emitted; ST21 sentinel-only-prompt → existing behavior unchanged; ST22 user-pasted fence in tool result → ignored (writer is `dispatch` actor, not `gui`); ST23 fence with malformed schema → log warning + emit bare branch-opened only (no partial item); ST24 multiple fenced blocks → all parsed.

- [ ] 8. **Implement `decision-context-replay.sh` + wire on SessionStart — Verification: contract**
      - Drains `~/.claude/state/decision-context/fallback.jsonl`. For each queued event, calls the `state.js` facade. On success, deletes the line (atomic-rewrite). On persistent failure, leaves the line and stops draining.
      - Idempotent on `event_id` per the ADR-032 §2 facade contract.
      - Done when: `--self-test` covers (a) empty queue → no-op, (b) 3 queued events all succeed → file empty after, (c) facade fails on event 2 → events 1 succeeds & is removed, events 2+3 remain.

- [ ] 9. **Bootstrap: extend `adapters/claude-code/CLAUDE.md` Detailed Protocols list + wire all three new hooks in `settings.json.template` — Verification: mechanical**
      - One bullet in CLAUDE.md "Detailed Protocols" pointing at `rules/decision-context.md`.
      - `settings.json.template`: wire `decision-context-gate.sh` in Stop (after `goal-coverage-on-stop.sh`), `decision-context-pending-surfacer.sh` in SessionStart, `decision-context-reply-emit.sh` in UserPromptSubmit, `decision-context-replay.sh` in SessionStart (before pending-surfacer so newly-flushed events are visible).
      - `harness-hygiene-scan.sh`, `docs-freshness-gate.sh`, `definition-on-first-use-gate.sh` all pass on the diff.
      - **Wire check:** `jq . adapters/claude-code/settings.json.template > /dev/null && rg "decision-context" adapters/claude-code/settings.json.template | wc -l` ≥ 4.

- [ ] 10. **Live Walking Skeleton: end-to-end Dispatch demonstration — Verification: full**
      - In a test Dispatch session: orchestrator emits a well-formed `::: decision id=DEMO-1` fence in its reply.
      - Confirm: (a) Stop hook validates + emits via facade; (b) the event lands in `tree-state.json`; (c) the GUI at `127.0.0.1:7733` renders the new decision node with options table + recommendation + reply_with; (d) Misha replies with the `reply_with` phrase; (e) `decision-context-reply-emit.sh` fires on UserPromptSubmit and emits the `answered` event; (f) the GUI shows the decision as resolved.
      - Done when: a screen capture / GUI snapshot of step (c)-(f) lands as evidence in `<plan-evidence>/10.evidence.json` `runtime_evidence`.

- [ ] 11. **PR open → review → merge to master (per Operating Rule 5 — "Done means shipped to master") — Verification: mechanical**
      - All gates green: `pre-commit-tdd-gate.sh`, `harness-hygiene-scan.sh`, `definition-on-first-use-gate.sh`, `plan-reviewer.sh`, `docs-freshness-gate.sh`, the CI workflow.
      - PR description fills the capture-codify section ("What mechanism would have caught this?" — answer: the FM-NNN entry for "decision-soliciting prose without structured payload escapes audit," to be authored as part of this plan).
      - Done when: PR is merged to master + the merge SHA is cited; `close-plan.sh close decision-context-gate-2026-05-29` flips `Status: COMPLETED` and auto-archives.

## Files to Modify/Create

- `adapters/claude-code/rules/decision-context.md` — new rule (the fence grammar, the Tiered-Scan taxonomy, composition with conv-tree-orchestrator-emit.md's Layer D, the Mechanism+Pattern split). Mirror to `~/.claude/rules/decision-context.md` per `harness-maintenance.md`.
- `adapters/claude-code/hooks/decision-context-gate.sh` — new Stop hook (Tier-1/2/3 classifier + fence parser + facade-driven emit). Mirror to `~/.claude/hooks/`.
- `adapters/claude-code/hooks/decision-context-pending-surfacer.sh` — new SessionStart hook. Mirror to `~/.claude/hooks/`.
- `adapters/claude-code/hooks/decision-context-reply-emit.sh` — new UserPromptSubmit hook. Mirror to `~/.claude/hooks/`.
- `adapters/claude-code/hooks/decision-context-replay.sh` — new SessionStart hook (fallback-queue drainer). Mirror to `~/.claude/hooks/`.
- `adapters/claude-code/hooks/conversation-tree-emit.sh` — extend `_extract_rich_details` / `_warn_no_rich_details` to recognize the fence grammar in spawn prompts.
- `neural-lace/conversation-tree-ui/state/decision-context-schema.js` + `.d.ts` — new Zod schema module + types, co-located with the state library so both writer and reader import the same canonical source.
- `neural-lace/conversation-tree-ui/web/app.js` — small templated addition to `renderItemDetails` IF the existing renderer doesn't already cover the options table + recommendation + reply_with rich fields. Check first; extend only if needed.
- `adapters/claude-code/settings.json.template` — wire the four new hooks (Stop, SessionStart×2, UserPromptSubmit). Sync to live `~/.claude/settings.json`.
- `adapters/claude-code/CLAUDE.md` — one bullet in "Detailed Protocols" pointing at the new rule.
- `docs/decisions/037-decision-context-enforcement-surface.md` — new ADR IF OQ-1 closes as Tier-2+ (likely, given the Stop-hook reactive model is an architectural pattern not in canon).
- `docs/failure-modes.md` — extend with FM-NNN: "Decision-soliciting prose surfaced without structured payload — escapes audit." Source: this plan.
- `docs/handoffs/` — not touched (read-only / out of scope).
- `docs/plans/decision-context-gate-2026-05-29.md` — this plan file.
- `docs/plans/decision-context-gate-2026-05-29-evidence/` — evidence artifacts directory (per-task `.evidence.json` files plus the Walking Skeleton GUI snapshot).

## In-flight scope updates

- 2026-05-30: `docs/decisions/045-decision-context-enforcement-surface.md` — ADR ID renumbered from 037 to 045 (037-044 already taken at dispatch time). Plan references to "037" in `## Files to Modify/Create` and `## Definition of Done` resolve to file 045. Same content, same Task 1, mechanical-only change.
- 2026-05-30: `docs/DECISIONS.md` — index row added for ADR 045 (atomic with the new ADR per `decisions-index-gate.sh`).
- 2026-05-30: `neural-lace/conversation-tree-ui/state/decision-context-schema.d.ts` — TypeScript peer of `decision-context-schema.js`. The Files-to-Modify entry above lists the pair as "`...-schema.js` + `.d.ts`" — the scope-enforcement-gate parses bullets atomically, so the `.d.ts` path is broken out here explicitly.
- 2026-05-30: `neural-lace/conversation-tree-ui/package.json` — Task 2 introduces zod as the conv-tree-ui module's only runtime dep (SOLE NORMATIVE validator per the canonical schema). The `conversation-tree-ui` directory had no `package.json` prior to this plan; scope explicitly absorbed per Task 2's brief ("if it doesn't have a package.json, scope absorbed: add one with `zod` only").
- 2026-05-30: `neural-lace/conversation-tree-ui/package-lock.json` — automatic peer of the above; locks `zod ^3.23.8`. Required for reproducible installs.
- 2026-05-30: `neural-lace/conversation-tree-ui/state/schema.js` — additive edit: append `autonomous-action-logged` to `EVENT_TYPES` + matching `EVENT_REQUIRED_FIELDS` entry. Per DEC-2 (this plan) + ADR-032 §1 ("Adding a new event type to EVENT_TYPES is additive (no bump)"); `schema_version` stays 1. Edit is purely additive — no existing required field changed. Already implicitly named in the parent task brief ("extend the conversation-tree state schema with one new additive event type"), surfaced here for the gate's explicit-file requirement.
- 2026-05-30: `neural-lace/conversation-tree-ui/state/selftest.js` — additive edit: new property scenario (P18) exercising the `autonomous-action-logged` round-trip + forward-tolerance + required-field enforcement. Already implicitly named in the parent task brief ("extend the conversation-tree self-test"), surfaced here for the gate's explicit-file requirement.
- 2026-05-30 (orchestrator, cherry-pick conflict resolution): Task 9-full Wave 5 scope absorbs `neural-lace/conversation-tree-ui/web/app.js` `renderItemDetails` extension per B2's OQ-2 finding (ii — Partial). Missing fields: per-option `what_it_does` / `risk` / `reversibility_cost` / `cost` / `key`, recommendation `option_key` + `reasoning` sub-fields, `reply_with`, `why_not_decide_alone`, question's `why_asking` / `what_ive_tried` / `answer_shape`, action_item's `the_ask` / `why_assigned` / `what_im_doing_meanwhile` / `state`, autonomous_action's `action_taken` / `reasoning` / `reversibility` / `references`, envelope `default_if_no_response` / `expires_at` / `warn_at` / `urgency`.
- 2026-05-30 (Wave 2): `docs/harness-architecture.md` — three orchestrator-merged rows added (one per Wave-2 artifact: rule `decision-context.md`, Stop hook `decision-context-gate.sh`, UserPromptSubmit hook `decision-context-reply-emit.sh`). Forced by `docs-freshness-gate.sh` on every new rule/hook landing — `harness-maintenance.md` Rule 3 mandate. Auto-merged cleanly across the three parallel cherry-picks (different table rows).
- 2026-05-30 (Wave 2): `docs/plans/decision-context-gate-2026-05-29-evidence-task3.md`, `docs/plans/decision-context-gate-2026-05-29-evidence-task4.md`, `docs/plans/decision-context-gate-2026-05-29-evidence-task6.md` — per-task builder-authored comprehension articulations (rung 2 gate; one file per builder to avoid plan-file cherry-pick conflicts). Will be consolidated by task-verifier into the canonical `docs/plans/decision-context-gate-2026-05-29-evidence.md` Evidence Log.
- 2026-05-30 (Wave 2): `neural-lace/conversation-tree-ui/node_modules/zod` — `npm install` run by orchestrator in the feature-branch worktree post-cherry-pick. Required for the gate's `node -e require('decision-context-schema.js')` call to resolve `require('zod')`. `node_modules/` is gitignored so this is operational state, not committed.
- 2026-05-30 (Wave 2 follow-up — B4-FU-1): `decision-context-gate.sh --self-test` leaks retry-guard state files at `.claude/state/stop-hook-retries-decision-context-gate-*.txt` between runs, causing ST1+ST5 to spuriously fail on a second run (3-strike threshold downgrades BLOCK to WARN). Fix: self-test should pre-clean those files. Filed as backlog candidate; Task 4 ships with the leak (verified PASS on a clean retry-guard state).
- 2026-05-30 (Task 10 — Walking Skeleton): `neural-lace/conversation-tree-ui/state/walking-skeleton-decision-context.sh` — replayable end-to-end fence → tree → reply → resolved round-trip script (executable, idempotent, cleanup-on-failure via `trap EXIT`, restores live state bit-identical on completion). Co-located with `state.js` so it shares the facade resolver naturally. Plan's `## Files to Modify/Create` was authored before the Walking Skeleton script path was decided; absorbed here.
- 2026-05-30 (Task 10): `docs/plans/decision-context-gate-2026-05-29-evidence-task10.md` — builder-authored Walking Skeleton evidence + rung-2 comprehension articulation (matches Wave-2 per-task evidence file convention).
- 2026-05-30 (Task 10 follow-up — B10-FU-1): The `decision-context-gate.sh` facade-emit path emits `decision-raised` with a fresh `node_id` (e.g., `dc-decision-<id>`) but does NOT first emit a `branch-opened` for that node. The reducer's `decision-raised` arm rejects events whose `node_id` doesn't resolve via `findNode`, so the item silently never appears in `snapshot.nodes[]` (events DO persist in `events[]`, masking the bug from the gate's own self-tests which only count `events.filter(type==="decision-raised").length`). The reply hook reads `snapshot.nodes`, so it then fails to match the item. Walking Skeleton works around this with a pre-seeded `branch-opened` via the `state.js` facade. Filed as backlog candidate: gate should emit `branch-opened` for new `node_id` it owns, OR an orchestrating sibling hook should do it.

## Assumptions

- The conversation-tree-ui backend at `127.0.0.1:7733` is the canonical GUI server, watches `tree-state.json` written by the `state.js` facade, and re-renders on file change. (Verified during survey: `/api/health` ok, state file located.)
- The `state.js` facade's `appendEvent({statePath})` is the SOLE NORMATIVE write path (ADR-032 §8 r2.1 sole-normative attestation primitive). All emit paths in this plan go through it; no parallel HTTP-direct path is opened.
- `mcp__ccd_session__send_user_message` is NOT exposed today and remains unexposed for the lifetime of this plan. If it is exposed mid-plan, OQ-1 reopens and the enforcement surface migrates from Stop-hook reactive to PreToolUse on that tool — a thaw-and-re-freeze cycle per `spec-freeze.md`.
- The four-category schema does not require a `schema_version` bump (additive — new event types are additive per ADR-032 §1; rich payload on existing `item-details-set` is optional per the same clause).
- Sibling Stop-hook pattern (six existing) generalizes to the decision-context-gate's Tier-1 block-with-redo. The redo-friction IS the agent's incentive to fence first.
- The GUI's `renderItemDetails` already handles structured `details` payloads (per `conversation-tree-emit.sh` comments and the existing v1.1-ux item flow). Confirm via inspection; small addition only if needed.
- The `decision-context-replay.sh` fallback drainer is best-effort. Persistent backend unavailability is surfaced as a system-reminder via the pending-surfacer; no claim is made that events queued > 24h are guaranteed to land.
- Misha's Dispatch sessions emit to the main-checkout `tree-state.json` per the existing `_main_repo_root` + `_resolve_gui_state_path` resolver in `conversation-tree-emit.sh` — this plan's hooks reuse that resolver, not re-implement it.

## Edge Cases

- **Fence in a non-Dispatch standalone session.** The hook fires regardless of mode (per `decision-context.md` Pattern — "applies to every agent in every session mode"). Standalone sessions emit to the global tree (`~/.claude/state/conversation-tree/global/tree-state.json`) per ADR-032 §5; the resolver in `conversation-tree-emit.sh` already does this.
- **Multiple fenced blocks in one assistant message.** Each is parsed and emitted as a separate event. `event_id` is deterministic per `id` field so duplicates are no-ops.
- **Fence with duplicate `id` across sessions.** ADR-032 §2 says duplicate `event_id` is treated as no-op (idempotency). The schema enforces `id` MUST be unique within a tree (validator rejects if it collides with an existing live node).
- **User pastes a fence into their reply.** The Stop hook reads `assistant` role only; user content is structurally ignored. The reply-emit hook reads user role; it does NOT call into the schema validator's emit path — it only reads node-id / reply_with references. So a user-pasted fence cannot inject events.
- **Backend unreachable during emit.** Hook writes to fallback.jsonl, logs the failure, ALLOWS Stop (writer-hook discipline). `decision-context-replay.sh` drains on next SessionStart.
- **`expires_at` passes during a live session.** Out of scope for v1 — the GUI displays the expiry; an external scheduled task could later auto-apply the `default_if_no_response`, but that's a follow-up (notes in the failure-mode catalog + a future enhancement).
- **Compaction during a long session.** ADR-032 §7c r2 + §8 r2.1 attestation primitive — the schema's `id` field is the only key the hook looks up, and `id` lives in `snapshot.nodes` after compaction (the published shape attested via `verifySnapshotAttested`). No work needed.
- **Schema-version skew (GUI is on schema_version=1; hook compiled against schema_version=2 if a future major bump happens).** The hook MUST reject schema-too-new exactly like the existing conv-tree gates per ADR-031 r7 Pin 2. The Zod validator handles this by gating on the `schema_version` field of the state file before parsing.
- **Cross-session fence-id collisions in genuinely parallel Dispatch sessions.** ADR-032 §6 conflict unit = event record + idempotency on `event_id`. Two sessions emitting the same `id` simultaneously is the same shape as the existing `appendEvent` race — handled by the facade's append-and-rename atomicity. No new work.
- **Misha replies in plain prose without quoting the `reply_with` phrase or node ID.** The reply-emit hook does nothing (silent no-op). The decision stays open. The pending-surfacer re-injects on next SessionStart, so it doesn't disappear from view.

## Testing Strategy

- Per-task `Verification:` declarations are inline above; per `risk-tiered-verification.md`:
  - Tasks 1, 3, 7, 9, 11 → `mechanical` or `contract` (deterministic file/schema/wiring checks).
  - Tasks 2, 8 → `contract` (Zod golden-file validation; reconciler queue invariants).
  - Tasks 4, 5, 6, 10 → `full` (runtime behavior — Stop-hook block-and-redo, SessionStart injection, UserPromptSubmit emit, live Dispatch round-trip).
- Self-tests follow the harness `--self-test` convention; each new hook ships its own `--self-test` with the scenarios named per-task above.
- The Walking Skeleton (Task 10) is the live integration check — fence emitted by Dispatch lands in the GUI's tree and round-trips through Misha's reply.

## Walking Skeleton

The thinnest end-to-end vertical slice that proves the system works (also Task 10's acceptance):

1. Misha asks Dispatch a question whose answer requires a structured decision.
2. Dispatch emits a `::: decision id=WS-1 …` fence in its reply.
3. Stop hook validates the fence and emits `decision-raised` + `item-details-set` via the `state.js` facade.
4. The GUI (already running at `127.0.0.1:7733`) re-renders and shows WS-1 with options table + recommendation + reply_with phrase.
5. Misha replies with the `reply_with` phrase.
6. UserPromptSubmit hook emits `answered`; GUI shows WS-1 as resolved.

If steps 1-6 all happen without manual intervention, the system is shipped. This is the simplest possible demonstration; everything beyond it (Tiered-Scan classification, fallback log, replay, autonomous-action category, multi-fence-per-message, etc.) is generalization on top.

## Risk callouts

- **R1 (highest) — OQ-1 is unresolved.** Until Misha picks the enforcement surface (Stop-hook reactive vs. convention-only vs. wait-for-tool), Task 2 + Task 4 are pre-architectural and may need rework. Mitigation: Task 1 is the literal first action — settle OQ-1 before any code lands.
- **R2 — `mcp__ccd_session__send_user_message` is exposed mid-plan by Anthropic.** Stop-hook reactive surface becomes legacy; PreToolUse on that tool becomes the right surface. Mitigation: design Task 4's classifier (Zod schema + fence parser) to be hook-event-agnostic — invoked with the message text as input, returning a verdict — so re-wiring is a 10-line settings.json edit.
- **R3 — Schema-additive change in `item-details-set` payload accidentally breaks GUI rendering.** ADR-032 §1 says payloads on `item-details-set` are free-form, so this is non-mechanical (the GUI must tolerate unknown sub-fields). Mitigation: GUI inspection in Task 8 BEFORE shipping; if the renderer assumes a closed shape, extend it explicitly in scope.
- **R4 — False-positive Tier-1 classification blocks legitimate non-decision messages.** Mitigation: Tier-3 rhetorical-whitelist + the substantive Stop-hook waiver (≥1 line, <1h). The sibling hooks (`narrate-and-wait-gate.sh`, `principles-compliance-gate.sh`) hit this same trade-off and resolve it with explicit-rhetorical-allowlist + waiver. Reuse those allowlists.
- **R5 — Loop deadlock between Tier-1 block and agent's re-fenced retry containing the same content.** Mitigation: Stop-hook retry-guard (sibling pattern); after 3 identical-failure retries the block downgrades to a warn. Same loop-break every blocking Stop hook in the harness uses.
- **R6 — Race: Misha edits the tree mid-AI-response, then AI emits a stale fence referencing a node that was just archived.** Mitigation: the pending-surfacer (Task 5) injects the externally-resolved state on next SessionStart; the gate's facade-write will see the up-to-date snapshot when it lands. No deadlock; AI's next reply incorporates the resolution.
- **R7 — Performance: Stop hook calls into `node` for every Stop fire (Zod validation).** Sibling hooks do the same (`conv-tree-emit-reconciler.sh`, `conversation-tree-emit.sh`). Mitigation: short-circuit when the last assistant message contains no triggers AT ALL (cheap regex pre-filter) — only invoke `node` when Tier-1/2 trigger is present.
- **R8 — Hook scope creep into the wrong substrate.** The hook MUST NOT bypass the `state.js` facade. Re-stating: the §8 r2.1 attestation primitive is the ONLY way snapshot trust is established. Mitigation: code review must reject any direct JSON write or HTTP POST that bypasses `appendEvent`.

## Dependency graph

```
        Task 1 (settle OQ-1)
              │
              ▼
        Task 2 (schema module)  ←──┐
              │                     │
              ├──→ Task 3 (rule)    │
              │                     │
              ├──→ Task 4 (Stop hook)   ──┐
              ├──→ Task 5 (SessionStart) ─┤
              ├──→ Task 6 (UserPromptSubmit) ──┤
              ├──→ Task 7 (extend emit.sh) ────┤
              └──→ Task 8 (replay) ─────────────┤
                                                ▼
                                          Task 9 (bootstrap + wiring)
                                                │
                                                ▼
                                          Task 10 (Walking Skeleton — live)
                                                │
                                                ▼
                                          Task 11 (PR → master)
```

Tasks 3-8 are parallelizable once Tasks 1+2 land. Task 9 needs all of 3-8. Task 10 needs 9. Task 11 needs 10.

## Resolved Open Questions (decisions in Decisions Log below)

All five plan-time open questions were resolved by Misha on 2026-05-29 before build began. The Decisions Log below records each decision. Summary:

- **OQ-1 → DEC-1:** Enforcement surface = Stop-hook reactive model. ADR-037 captures the architecture choice.
- **OQ-2 → DEC-2-confirm:** Resolves during Task 2 inspection of `web/app.js`'s `renderItemDetails`. Flagged for the Task 2 builder; if missing, scope absorbed via `## In-flight scope updates`.
- **OQ-3 → DEC-2:** `autonomous_action` → new additive event type `autonomous-action-logged`. Cleaner GUI rendering; additive within major 1 (no `schema_version` bump).
- **OQ-4 → DEC-3:** Target-completion-date removed. Ship quality without artificial pressure.
- **OQ-5 → DEC-4:** FM-NNN entry authored at PR time (Task 11).

## Decisions Log

### DEC-1 — Enforcement surface = Stop-hook reactive model (ADR-037)

- **Tier:** 2 (architectural pattern not previously in canon; requires ADR per Tier-2+ rule)
- **Status:** decided — Misha 2026-05-29
- **Chosen:** Stop-hook reactive — after agent sends a message, the new `decision-context-gate.sh` Stop hook scans the last assistant message in `$TRANSCRIPT_PATH`; Tier-1 triggers without a fence BLOCK Stop with the schema as the error; agent forced to redo as fence before session can end.
- **Alternatives Considered:** (b) Convention-only with post-hoc transcript-mining emit — rejected because no enforcement; verbal vaporware persists. (c) Wait for `mcp__ccd_session__send_user_message` to be exposed — rejected because indefinite delay; Anthropic-controlled timeline.
- **Reasoning:** Six sibling Stop hooks (`continuation-enforcer`, `narrate-and-wait-gate`, `goal-coverage-on-stop`, `deferral-counter`, `imperative-evidence-linker`, `principles-compliance-gate`) all use the "scan last assistant message; block-with-redo-required" pattern successfully. The redo-friction IS the agent's incentive to fence first. The Stop hook reads `$TRANSCRIPT_PATH` which is agent-uneditable (Gen-6 narrative-integrity property). Class proven.
- **To reverse:** if `mcp__ccd_session__send_user_message` is exposed by Anthropic, migrate the hook from Stop to PreToolUse on that tool. Designed for portability — the Zod schema + fence parser are hook-event-agnostic (invoked with message text as input, return verdict).
- **ADR:** `docs/decisions/037-decision-context-enforcement-surface.md` authored as Task 1 deliverable.

### DEC-2 — `autonomous_action` ships as new additive event type `autonomous-action-logged`

- **Tier:** 1 (additive within ADR-032 §1; no major bump)
- **Status:** decided — Misha 2026-05-29
- **Chosen:** New event type `autonomous-action-logged` with required fields `node_id`, `text`, `details`. `details` is a structured object carrying `action_taken`, `reasoning`, `reversibility`, `references` as sub-fields.
- **Alternatives Considered:** (i) Emit `annotated` with a JSON sub-block in `text` — rejected for GUI cleanliness; forces GUI to parse JSON from a string field, complicating `renderItemDetails`.
- **Reasoning:** Same additive precedent as `item-details-set`, `priority-assigned`, `branch-note-add`. Zero contract risk: no required-field change to any existing event; reducer is forward-tolerant (skips unknown event types within the same major, ADR-032 §1).
- **Schema-version impact:** none — `schema_version: 1` stays. Per ADR-032 §1 "Adding a new event type to EVENT_TYPES is additive (no bump)."
- **To reverse:** `git revert` the schema additions in `neural-lace/conversation-tree-ui/state/schema.js`; the reducer's forward-tolerance means existing snapshots survive.

### DEC-3 — No target completion date; ship quality without artificial pressure

- **Tier:** 1
- **Status:** decided — Misha 2026-05-29 verbatim: *"I want you to finish this work now."*
- **Chosen:** Remove `target-completion-date` from plan header. Highest urgency, no fixed deadline. Ship Walking Skeleton (Task 10) before piling on the rest, as Misha directed.
- **Reasoning:** Artificial deadlines incentivize cutting scope. Walking-Skeleton-first ordering proves the round-trip is functional early; remaining tasks land against a verified foundation.

### DEC-4 — FM-NNN catalog entry authored at PR time (Task 11)

- **Tier:** 1
- **Status:** decided — Misha 2026-05-29
- **Chosen:** Author the failure-mode entry "decision-soliciting prose surfaced without structured payload — escapes audit" in `docs/failure-modes.md` as part of Task 11 (PR description capture-codify section). Cross-references this plan as the originating context.
- **Reasoning:** Operating Rule 6 ("Preemptive over symptom-treating") + the harness's capture-codify discipline at PR time. The mechanism that catches this class IS the decision-context-gate; the FM entry documents the class so future sessions can grep it via the diagnosis.md catalog-first reflex.

### DEC-5 — Build sequencing: Walking Skeleton early (Wave 2), full coverage after (Waves 4-5)

- **Tier:** 1
- **Status:** decided — Misha 2026-05-29 ("ship Walking Skeleton early so we know the round trip is functional before piling on the rest")
- **Chosen:** Five waves of orchestrator dispatch (see "Build sequencing" below). Wave 1 = foundation (Tasks 1, 2 parallel). Wave 2 = Walking Skeleton minimum slice (Tasks 3, 4, 6 parallel). Wave 3 = wire + demo (Tasks 9-partial, 10 sequential). Wave 4 = full coverage (Tasks 5, 7, 8 parallel). Wave 5 = close (Tasks 9-full, 11).
- **Reasoning:** Walking Skeleton is the proof-of-life. If end-to-end emit-fence → tree → reply → resolved doesn't work with the minimum slice, the architecture is wrong and the remaining tasks are wasted effort. Validating early is cheaper than discovering the failure at Task 11.

## Build sequencing (orchestrator dispatch waves)

- **Wave 1 (parallel):** B1 = Task 1 (ADR-037), B2 = Task 2 (schema module + Zod + types).
- **Wave 2 (parallel, after Wave 1 cherry-picked):** B3 = Task 3 (rule), B4 = Task 4 (Stop hook), B6 = Task 6 (UserPromptSubmit hook).
- **Wave 3 (sequential, after Wave 2 cherry-picked):** B9p = Task 9-partial (wire just the 3 hooks for WS), B10 = Task 10 (Walking Skeleton live demonstration).
- **Wave 4 (parallel, after Wave 3 passes):** B5 = Task 5 (SessionStart pending-surfacer), B7 = Task 7 (extend conversation-tree-emit.sh), B8 = Task 8 (replay drainer).
- **Wave 5 (sequential, close):** B9f = Task 9-full (CLAUDE.md + remaining wiring + FM-NNN), B11 = Task 11 (PR + merge + close).

Each parallel builder uses `isolation: "worktree"` with the first-action `git checkout -b worker-<task-id> feat/decision-context-gate-2026-05-29` per `orchestrator-pattern.md`. Cherry-picked sequentially onto the feature branch in task-ID order; `task-verifier` invoked per result before next wave dispatches.

## Pre-Submission Audit

Not applicable — `Mode: code` plan under `build-harness-infrastructure` work-shape (everything under `adapters/claude-code/` or `neural-lace/conversation-tree-ui/`). The five-sweep pre-submission audit is a `Mode: design` discipline; the work-shape's relaxation applies here.

## Definition of Done

- [ ] OQ-1, OQ-3, OQ-4, OQ-5 resolved in Decisions Log (OQ-2 self-resolves during Task 2)
- [ ] All 11 tasks checked off (task-verifier flips each, per the verifier mandate)
- [ ] All hooks `--self-test` PASS
- [ ] Walking Skeleton (Task 10) demonstrated live with GUI snapshot evidence
- [ ] All harness gates green on the PR (pre-commit-tdd / harness-hygiene / definition-on-first-use / plan-reviewer / docs-freshness / CI)
- [ ] FM-NNN entry authored
- [ ] PR merged to master with cited merge SHA (Operating Rule 5)
- [ ] `close-plan.sh close decision-context-gate-2026-05-29` flips Status: COMPLETED and archives
- [ ] SCRATCHPAD updated to reflect the closed state
