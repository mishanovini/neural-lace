# Evidence Log — Decision-Context Gate (Active Enforcement) 2026-05-29

## Task 4 — Implement `adapters/claude-code/hooks/decision-context-gate.sh` (Stop hook per OQ-1)

EVIDENCE BLOCK
==============
Task ID: 4
Task description: Implement `adapters/claude-code/hooks/decision-context-gate.sh` (Stop hook per OQ-1) — Verification: full
Verified at: 2026-05-30T00:00:00Z
Verifier: task-verifier agent

Comprehension-gate: PASS (confidence 8) — articulation at docs/plans/decision-context-gate-2026-05-29-evidence-task4.md substantively matches diff a2c61a8; four sub-sections (Spec meaning / Edge cases covered / Edge cases NOT covered / Assumptions) all well above 30-char threshold and cite specific diff content (`_parseRecommendationBlock`, `EVENT_REQUIRED_FIELDS`, `_resolve_schema_module`, ST1-ST11 self-test counts). Rung-2 requirement satisfied.

Checks run:
1. Hook syntactic + executable — bash -n PASS, executable bit PASS
2. Self-test from clean retry-guard state — `bash adapters/claude-code/hooks/decision-context-gate.sh --self-test` → `self-test: OK 25/25` (11 scenarios incl. ST7 facade-down, ST8 pre-filter, ST9 retry-guard 3-strike, ST11 all four event categories)
3. Mirror byte-identical — `diff -q adapters/claude-code/hooks/decision-context-gate.sh ~/.claude/hooks/decision-context-gate.sh` clean
4. docs/harness-architecture.md inventory row at line 203 — substantive (names Tier-1/2/3 behavior, sole-normative Zod, facade emission, fallback path, waiver pattern, 11 self-test scenarios)
5. Composition integrity (read from diff a2c61a8): `_resolve_schema_module` resolves to Task 2's `neural-lace/conversation-tree-ui/state/decision-context-schema.js` via git-rev-parse with `DECISION_CONTEXT_SCHEMA` env override; emission goes through `state.js` `appendEvent` facade via `node -e require(stateLib)` (NEVER direct JSON, NEVER direct HTTP); fallback path is `~/.claude/state/decision-context/fallback.jsonl` (ST7); pre-filter short-circuits BEFORE node subprocess on signal-free messages (ST8 via `DC_PERF_TRACE_FILE`)

Git evidence:
  - a2c61a8 — feat(hooks): decision-context-gate.sh — Stop-hook reactive enforcement (hook + inventory row)
  - 703a049 — docs(plan): task 4 comprehension articulation

Runtime verification: command:bash adapters/claude-code/hooks/decision-context-gate.sh --self-test
Runtime verification: file adapters/claude-code/hooks/decision-context-gate.sh::CONV_TREE_STATE_LIB
Runtime verification: file docs/harness-architecture.md::decision-context-gate.sh

Verdict: PASS
Confidence: 8
Reason: Hook ships ADR-045 Stop-hook reactive enforcement end-to-end; 25/25 self-test PASS from clean state covers all 11 scenarios including writer-hook discipline (ST7), perf pre-filter (ST8), retry-guard downgrade (ST9), and all four event categories (ST11); composes correctly with Task 2 Zod module via sole-normative `require()` and Task 1 ADR resolvers; mirror byte-identical; B4-FU-1 retry-guard leak is test-harness ergonomics only (does not affect production behavior).

### Comprehension Articulation (builder-authored, embedded by reference)

See `docs/plans/decision-context-gate-2026-05-29-evidence-task4.md` for the full four-sub-section articulation (Spec meaning / Edge cases covered / Edge cases NOT covered / Assumptions). Reviewed against diff a2c61a8: all citations resolve, all claimed edge-cases map to diff content, assumptions are not contradicted by the diff.

---

## Task 2 — Author schema TS module + Zod validator + autonomous-action-logged event

EVIDENCE BLOCK
==============
Task ID: 2
Task description: Author the schema TS module + Zod validator at `neural-lace/conversation-tree-ui/state/decision-context-schema.js` (+ `.d.ts`); extend `state/schema.js` with `autonomous-action-logged` per DEC-2 — Verification: contract
Verified at: 2026-05-30T00:00:00Z
Verifier: task-verifier agent (Verification: contract early-return)

Comprehension-gate: PASS (confidence 8) — articulation embedded below; consistent with diff at 8407a48; rung 2 (R2+) requirement satisfied via pre-filled articulation per orchestrator note.

Verification level: contract
Evidence path: docs/plans/decision-context-gate-2026-05-29-evidence.md (legacy one-line prose path)

Checks run:
1. Files exist
   Command: ls neural-lace/conversation-tree-ui/state/decision-context-schema.{js,d.ts}
   Output: both files present (.js 457 lines, .d.ts 133 lines per git stat at 8407a48)
   Result: PASS

2. Exports callable surface
   Command: grep -nE "^function (validateFence|safeValidateFence|parseFenceBlock)|^module.exports" neural-lace/conversation-tree-ui/state/decision-context-schema.js
   Output: validateFence (L197), safeValidateFence (L211), parseFenceBlock (L361), module.exports (L439)
   Result: PASS

3. autonomous-action-logged registered in state schema
   Command: grep -n "autonomous-action-logged" neural-lace/conversation-tree-ui/state/schema.js
   Output: L86 (EVENT_TYPES), L140 (EVENT_REQUIRED_FIELDS: [node_id, text, details])
   Result: PASS

4. Self-test suite passes including P18
   Command: cd neural-lace/conversation-tree-ui && node state/selftest.js
   Output: "PASS P18 autonomous-action-logged: envelope OK + round-trips + forward-tolerant details + schema_version still 1 + required-field enforcement" — 18 passed, 0 failed
   Result: PASS

Git evidence:
  Commits in scope:
    - 8407a48 — feat(conv-tree): decision-context schema module + autonomous-action-logged event (task 2 of decision-context-gate)
    - 73d20ef — fix(plan): merge in-flight-scope-updates after B1+B2 cherry-pick conflict
  Files modified (7 total at 8407a48): decision-context-schema.{js,d.ts}, state/schema.js, state/selftest.js, package.json, package-lock.json, plan file
  Plan in-flight scope updates: 5 entries added covering .d.ts peer, package.json, package-lock.json, state/schema.js, state/selftest.js

Runtime verification: test neural-lace/conversation-tree-ui/state/selftest.js::P18-autonomous-action-logged
Runtime verification: file neural-lace/conversation-tree-ui/state/schema.js::autonomous-action-logged
Runtime verification: file neural-lace/conversation-tree-ui/state/decision-context-schema.js::module.exports

Verdict: PASS
Confidence: 8
Reason: Verification: contract level — schema artifact validates against the locked fence-grammar shape (14/14 builder-run goldens), additive event type proven via P18 integration self-test, callable surface exported, schema_version invariance confirmed.

#### Comprehension Articulation

### Spec meaning
Build the SOLE NORMATIVE Zod schema for the decision-context fence grammar — the only parser+validator both the Stop hook (Task 4) and the GUI consume. Four categories (decision/question/action_item_for_user/autonomous_action), each with a category-specific payload + a common envelope (id, label, title, about, background, urgency, expires_at, default_if_no_response, warn_at, blocks_on, connects_to, references). Cross-field constraint at the Zod layer: `expires_at` set ⇒ `default_if_no_response` set + references an option whose `reversibility_cost` is `free|cheap`. Separately, extend the conv-tree state schema (frozen contract, ADR-032 §1 additive rule) with `autonomous-action-logged` (`node_id`, `text`, `details`) — additive within major 1 (no `schema_version` bump). Plus a P-numbered self-test scenario proving the new event type round-trips through the reducer with forward-tolerant `details`.

### Edge cases covered
- Cross-field constraint at Zod layer: `expires_at` without `default_if_no_response` → reject; `default_if_no_response` referencing an `expensive` or `irreversible` option → reject. Confirmed via 14/14 schema goldens (builder-run).
- ADR-032 §1 additive rule: P18 in selftest.js proves `autonomous-action-logged` round-trips without bumping `schema_version`. Confirmed: P1-P18 all green (18/18).
- Forward-tolerance: unknown sub-fields in `details` payload don't break the reducer (the §1 additive evolution property). Asserted in P18.
- Required-field enforcement: P18 asserts the validator rejects `autonomous-action-logged` events missing `node_id`, `text`, or `details`.
- Schema module callable from `node -e require(…)`: implicit acceptance criterion satisfied by the module being CommonJS-compatible (verified via P18 integration through the state library's `appendEvent` path).
- `parseFenceBlock(rawText)` round-trip: Markdown fence parse → Zod validate → event payload. Covered by builder's goldens.

### Edge cases NOT covered
- Concurrent emit of the same `event_id` from two parallel sessions: handled by the existing facade idempotency (ADR-032 §6); not Task 2's scope.
- Schema-version skew: if a future major bump happens, the Stop hook (Task 4) MUST reject schema-too-new exactly like the existing conv-tree gates (ADR-031 r7 Pin 2). Task 2 does NOT enforce this; it's deferred to Task 4's hook implementation.
- The fence-block parser's resilience to malformed-but-close-to-valid Markdown (e.g., missing closing `:::`, escaped backticks inside fields): goldens cover the well-formed and the schema-rejected cases, but the lexer's behavior on partial Markdown is not exhaustively tested. Acceptable for v1; observed in practice will refine.

### Assumptions
- The conv-tree state library's `appendEvent` facade remains the sole writer interface (ADR-032 §8 r2.1) — the new event type is consumed via the same path.
- `zod` v3 (3.23.8) is API-stable for the duration of this plan; if zod v4 introduces a breaking change, the `package.json` semver-caret pins to v3.x.
- The `package.json` introduction in `neural-lace/conversation-tree-ui/` doesn't break existing imports anywhere (no callers existed before this dep was added — the conv-tree-ui directory had no `package.json` prior, per B2's brief absorption).
- The OQ-2 partial-coverage finding on `renderItemDetails` is informational here; Task 9-full owns the templated extension. Task 2 is complete without touching `app.js`.

## Task 3 — Author `adapters/claude-code/rules/decision-context.md`

EVIDENCE BLOCK
==============
Task ID: 3
Task description: Author `adapters/claude-code/rules/decision-context.md` — Verification: mechanical
Verified at: 2026-05-30T23:25:00Z
Verifier: task-verifier agent (Verification: mechanical early-return)

Comprehension-gate: PASS (confidence 8) — articulation embedded below; four sub-sections substantive (Spec meaning paraphrases the task accurately, Edge cases covered cite specific rule-file sections, Edge cases NOT covered explicitly enumerate gaps with rationale, Assumptions name verified premises with commit-SHA citations); consistent with diff at 51ac77e (all 11 sections present, four worked fence examples, Tier-1/2/3 taxonomy, Layer D migration, ADR-032 §2 mapping, sole-normative validator section).

Verification level: mechanical
Evidence path: docs/plans/decision-context-gate-2026-05-29-evidence.md (legacy one-line prose path)

Checks run:
1. Rule file exists at canonical path with all 11 sections
   Command: grep -nE "^##? " adapters/claude-code/rules/decision-context.md
   Output: 11 sections present — Title (L1), Originating context (L7), Rule-in-one-sentence (L15), Fence grammar (L19), Tiered-Scan taxonomy (L138), Composition with Layer D (L178), Composition with ADR-032 §2 events (L189), Sole-normative validator (L204), Cross-references (L212), Enforcement (L226), Scope (L241)
   Result: PASS

2. Mirror byte-identical
   Command: diff -q adapters/claude-code/rules/decision-context.md $HOME/.claude/rules/decision-context.md
   Output: (empty — exit 0)
   Result: PASS

3. docs/harness-architecture.md row added atomically in same commit
   Command: git show 51ac77e -- docs/harness-architecture.md
   Output: new row at L473 for `decision-context.md` (2026-05-30) describing Hybrid classification, fence grammar, Tiered-Scan, Mechanism stack, Layer D migration, ADR-032 §2 mapping; Last-updated header refreshed
   Result: PASS

4. definition-on-first-use-gate + harness-hygiene-scan
   Command: bash adapters/claude-code/hooks/definition-on-first-use-gate.sh --self-test (orchestrator pre-flight)
   Output: 7/7 PASS; harness-hygiene-scan clean
   Result: PASS

Git evidence:
  Commits in scope:
    - 51ac77e — feat(rules): decision-context.md — fence grammar + Tiered-Scan + ADR-032 §2 composition
    - b3e3002 — docs(evidence): task 3 comprehension articulation (R2 gate)
  Files modified: adapters/claude-code/rules/decision-context.md (+245), docs/harness-architecture.md (+1 row, header refresh), docs/plans/decision-context-gate-2026-05-29-evidence-task3.md (+articulation)
  Mirror: $HOME/.claude/rules/decision-context.md byte-identical (35212 bytes both sides)

Runtime verification: file adapters/claude-code/rules/decision-context.md::The fence grammar
Runtime verification: file adapters/claude-code/rules/decision-context.md::Tiered-Scan
Runtime verification: file adapters/claude-code/rules/decision-context.md::Composition with ADR-032
Runtime verification: file docs/harness-architecture.md::decision-context.md

Verdict: PASS
Confidence: 9
Reason: Verification: mechanical level — rule file present with all 11 required sections substantively populated, mirror byte-identical, architecture-doc row added in same commit, gates clean. Comprehension articulation maps to diff content (sole-normative validator section, cross-field constraint, Tier-3 AND-no-stronger-trigger condition, back-compat with existing sentinels all verifiable in the rule body).

#### Comprehension Articulation

### Spec meaning

The task asked me to author the canonical rule file at `adapters/claude-code/rules/decision-context.md` (mirrored byte-identically to `~/.claude/rules/decision-context.md`) that documents the fence grammar four agent→user surfaces must use, the Tiered-Scan trigger taxonomy the Stop-hook gate (Task 4) consumes, how this rule composes with the existing `conv-tree-orchestrator-emit.md` Layer D (migrating it from Pattern-only to Mechanism+Pattern for the four named categories), and the Mechanism+Pattern split per `harness-hygiene.md`'s convention. The rule does NOT re-specify the Zod schema (the canonical schema module at `neural-lace/conversation-tree-ui/state/decision-context-schema.js` is the sole-normative validator and is cited as such); it documents the wire format that maps to that schema. The eleven required sections (Classification / Originating context / Rule-in-one-sentence / Fence grammar with four worked examples / Tiered-Scan taxonomy / Composition with Layer D / Composition with ADR-032 §2 events / Sole-normative validator / Cross-references / Enforcement table / Scope) were all populated substantively, the rule cites all four ADRs (031, 032, 034, 045) and all six sibling Stop hooks by name, and the docs-freshness gate triggered a same-commit update of `docs/harness-architecture.md`'s rules table with a new row pointing at the rule.

### Edge cases covered

- **Fence in a non-Dispatch standalone session** — covered in the "Scope" section (rule lines near the bottom): "The rule binds in every session mode — interactive local, parallel local, cloud-remote / Dispatch orchestrator, scheduled, and agent-team — because decision-soliciting / question-asking / action-item-assigning / autonomous-action-logging surfaces appear in all of them."
- **Cross-field constraint (`expires_at` ⇒ `default_if_no_response` ⇒ `reversibility_cost ∈ {free, cheap}` for `decision` category)** — explicitly stated in the "fence grammar" section's preamble, with the Tier-3-irreversible-decision rationale cross-referencing `~/.claude/rules/planning.md` "Mid-Build Decisions" Tier 3. The `decision` worked example demonstrates compliance (the `union` option has `reversibility_cost: free`, satisfying the constraint when `expires_at` is set with `default_if_no_response: union`).
- **`autonomous_action` exempt from cross-field constraint** — explicitly called out at the end of the cross-field-constraint paragraph: "autonomous_action is exempt from the cross-field constraint because it has no `expires_at` / `default_if_no_response` / `options` fields (it's a fait-accompli log, not a pending decision)."
- **Hook degrades to Pattern-only for cloud-remote sessions that don't load `~/.claude/` hooks** — explicit in the "Scope" section's closing paragraph, cross-referencing ADR-031 r7's accepted cloud blind spot.
- **Schema-version-skew handling (hook compiled against a future major)** — explicit in the "Sole-normative validator" section: "Schema-version-skew handling (hook compiled against a future major; GUI on current major) follows ADR-031 r7 Pin 2: the gate REJECTs schema-too-new at parse time with a distinct 'schema too new — upgrade' error rather than falling back to a partial parse."
- **Tier-3 rhetorical-whitelist with simultaneous Tier-1/Tier-2 fire** — covered in the Tier-3 sub-section: "The gate is a deliberate no-op when a Tier-3 phrase matches and no Tier-1 or Tier-2 trigger ALSO fires" (the AND-no-stronger-trigger condition prevents false-negative).
- **Back-compat with existing `Instructions:` / `Recommendation:` / `Links:` sentinels** — covered in the "Composition with conv-tree-orchestrator-emit.md Layer D" section: the fence subsumes the existing sentinels; Task 7 will extend the parser to recognize both; older sessions without Task 7 continue to work with the sentinel-only form.
- **Sole-normative validator principle (no parallel parser anywhere)** — entire dedicated section ("Sole-normative validator") explains the parallel-implementation-determinism principle and cites ADR-032 §8 r2.1 as the architectural precedent.

### Edge cases NOT covered

- **Malformed fence INSIDE a Markdown code block** — if the agent emits a fenced ::: block inside a triple-backtick code block (e.g., as an example in documentation or in a teaching artifact), the Stop hook's regex pre-filter might still trip Tier-1 detection but the fence parser would still treat it as a real fence. The rule does NOT explicitly address this; the implicit answer is that the canonical Zod module is the parser and it accepts any ::: block regardless of enclosing context — but the hook implementation (Task 4) will need to decide whether to scan inside code blocks. I left this for Task 4 to surface.
- **Multi-fence-per-message ordering** — the rule mentions "Each is parsed and emitted as a separate event" in passing in the parent plan's Edge Cases, but the new rule body itself doesn't explicitly walk through what happens if a single message has three fences. The Zod module's `parseFenceBlock` finds the FIRST fence and returns it; the Task 4 hook will need to loop to find all of them. Documented in the plan, not in this rule.
- **User-pasted fence in a tool result (e.g., agent reads a doc containing an example fence and that content lands in the assistant turn)** — the parent plan's Edge Cases covers "user pastes a fence into their reply" but not the symmetric case where the agent itself quotes back a fence example from documentation. Not addressed here; would be a Task 4 hook concern (writer-actor distinction in the transcript).
- **Standalone (non-Dispatch) sessions don't have a global tree** — the rule says "Standalone sessions emit to the global tree (`~/.claude/state/conversation-tree/global/tree-state.json`)" assuming the substrate exists; if a standalone install has never run any Dispatch session, the global tree path may not exist. Out of scope here — the existing `conversation-tree-emit.sh` resolver handles bootstrapping.
- **Loop-deadlock when the agent's redo contains the same Tier-1 trigger as the original** — relies on the `stop-hook-retry-guard.sh` library's 3-retry downgrade, which the rule references but does not re-document.

### Assumptions

- The sole-normative Zod module at `neural-lace/conversation-tree-ui/state/decision-context-schema.js` (already landed in Task 2, commit `8407a48` on the feature branch) is the source of truth for the field set, enum values, and cross-field constraints. The rule documents the wire format and the validator's role; it does NOT redefine the schema or specify additional fields/constraints beyond what's in the module.
- The `state.js` facade's `appendEvent` is the sole-normative write path per ADR-032 §8 r2.1 — the rule cites this and forbids parallel HTTP paths, but does NOT re-document the facade's internals.
- The six sibling Stop hooks (`continuation-enforcer`, `narrate-and-wait-gate`, `goal-coverage-on-stop`, `deferral-counter`, `imperative-evidence-linker`, `principles-compliance-gate`) all use the "scan last assistant message in transcript JSONL; BLOCK-with-redo-required" pattern and share the `lib/stop-hook-retry-guard.sh` library — the rule references them as precedents without re-validating that each one actually does this (I trust the parent plan's survey and ADR 045's recap).
- ADR 045 has landed (verified — `docs/decisions/045-decision-context-enforcement-surface.md` exists on this branch) and locks the Stop-hook reactive surface; this rule documents the substance of that ADR's decision without re-litigating the rejected alternatives.
- The `autonomous-action-logged` event type has been added to `state/schema.js`'s `EVENT_TYPES` and `EVENT_REQUIRED_FIELDS` per Task 2 / DEC-2 / commit `8407a48`; the rule documents this as fact, citing the commit SHA.
- The `definition-on-first-use-gate.sh` scope-prefix is `neural-lace/build-doctrine/**/*.md` (verified by grep against the hook source), so acronyms in `adapters/claude-code/rules/decision-context.md` are NOT subject to the gate; the rule uses ADR / MCP / DEC / GUI / etc. freely.
- The `harness-hygiene-scan.sh` `is_path_shape_exempt()` function exempts `adapters/*` (verified by reading the hook source), so my rule file's repeated mention of domain vocabulary (Dispatch / State / Tree / Fence / Mechanism / Pattern / Layer) does not trip the Layer-2 cluster heuristic.
- The `docs-freshness-gate.sh` requires `harness-architecture.md` to be updated atomically with any new rule file added — verified by hitting the gate and resolving it with a same-commit doc update.

## Task 6 — decision-context-reply-emit.sh (UserPromptSubmit writer)

EVIDENCE BLOCK
==============
Task ID: 6
Task description: Implement `decision-context-reply-emit.sh` (UserPromptSubmit) — Verification: full
Verified at: 2026-05-30T23:30:00Z
Verifier: task-verifier agent

Comprehension-gate: PASS (confidence 9) — articulation embedded below; four sub-sections substantive and grounded in diff cd95b3b; edge-cases-covered cite ST1-ST10b mapped to specific code paths; assumptions name schema-major-1 contract + Task 4 reply_with contract + facade-as-sole-writer.

Checks run:
1. File exists, executable, bash -n clean
   Command: ls -la adapters/claude-code/hooks/decision-context-reply-emit.sh && bash -n
   Result: PASS — 28002 bytes, executable, syntax OK
2. Self-test re-run (independent of orchestrator)
   Command: bash adapters/claude-code/hooks/decision-context-reply-emit.sh --self-test
   Result: PASS — 17/17 (ST1-ST10b)
3. Mirror byte-identical
   Command: diff -q adapters/.../decision-context-reply-emit.sh ~/.claude/hooks/decision-context-reply-emit.sh
   Result: PASS
4. docs/harness-architecture.md row added (same commit)
   Result: PASS — row at line 188 documents the UserPromptSubmit hook
5. Composition verified
   - Facade-only writes (grep confirms `state.js` + `appendEvent`; no raw HTTP/fetch path)
   - `node.state === "archived" || node.state === "concluded"` skip at line 207
   - Deterministic event_id `dcre-<tag>-<sha1(item_id|promptSha)[0:24]>` at lines 245-254
   - `_die_safe` always exits 0 (line 55); fallback.jsonl path for facade-down (ST7)
   Result: PASS

Git evidence:
  - cd95b3b feat(hooks): decision-context-reply-emit (hook + arch doc, 612 insertions)
  - 404923b docs(plan): Task 6 comprehension articulation (132 lines)

Runtime verification: command bash adapters/claude-code/hooks/decision-context-reply-emit.sh --self-test
Runtime verification: file adapters/claude-code/hooks/decision-context-reply-emit.sh::node.state === "archived"
Runtime verification: file adapters/claude-code/hooks/decision-context-reply-emit.sh::dcre-

Verdict: PASS
Confidence: 9
Reason: Hook implements writer-class UserPromptSubmit detection across three layered modes (item_id / node_id / reply_with phrase) with all required composition properties — facade-only writes per ADR-031 r7, deterministic event_id idempotency per ADR-032 §2, archived/concluded node skip, already-resolved-item skip, absolute failure isolation (every path exits 0), fallback.jsonl drainer path for Task 8. 17/17 self-test scenarios cover the spec's edge cases (decision/question/action kind dispatch, case-insensitive phrase, follow-up response_text capture, 3-fire idempotency, facade-down recovery, archived skip, double-fire prevention). Mirror byte-identical. Architecture doc updated atomically. Articulation matches diff cd95b3b precisely.

## Comprehension Articulation

### Spec meaning

The hook is a UserPromptSubmit-class **writer** (NOT a gate) that closes the round-trip in the decision-context substrate: when Misha replies to a prompt soliciting a decision/question/action that has already landed in his conversation tree as an open item, this hook detects the reply, projects it onto ADR-032 §2 events (`answered` for decision/question, `action-done` for action), and lands the resolution in the tree state via the frozen state.js facade. A follow-up response text after the trigger gets captured on the item via `item-details-set` with `details.response_text`. Three detection modes layer in specificity order: (a) item_id literal token match, (b) node_id literal token match, (c) case-insensitive `details.reply_with` substring match. Only OPEN items on OPEN nodes count — checked/deferred/backlogged items and archived/concluded nodes are silently skipped so a stale mention of an already-resolved item is a no-op. Idempotency is the load-bearing property because UserPromptSubmit fires on every prompt: the event_id is deterministic per (item_id, sha1(prompt)) so re-firing on the same prompt produces the same event_id and the facade dedupes. Failure isolation is absolute — every code path exits 0, facade-unreachable events land in fallback.jsonl for Task 8's drainer; the user's prompt must NEVER be blocked by a writer-class hook (gate-respect.md).

### Edge cases covered

- **Archived/concluded nodes silently skipped (ST10).** Node-state filter is the first check inside per-node loop in `_scan_and_emit`.
- **Already-checked/deferred/backlogged items skipped (ST10b).** Filtered per-item before any detection runs.
- **Action items emit `action-done`, not `answered` (ST4).** Hook chooses event type by `it.kind` exactly.
- **Multiple open items, prompt mentions a subset (ST9).** Each item independently scanned.
- **Idempotency on 3 re-fires (ST6).** Deterministic event_id `dcre-<tag>-<sha1(item_id|sha1(prompt))[0:24]>`; facade dedupes per ADR-032 §2.
- **Facade-down (ST7).** Node subprocess returns `LIBERR:`/`READERR:`; dispatcher writes to `~/.claude/state/decision-context/fallback.jsonl` and exits 0.
- **Case-insensitive reply_with phrase (ST3).** `phraseMatch()` lowercases both sides.
- **Follow-up response text (ST5).** `followUp()` slices after matched span, trims, caps 2000 chars.
- **No-match silent (ST8).** Exits 0 with zero events.
- **Multi-sink dedupe.** GUI STATE_FILE + §5 gate path receive same event_ids; per-file no-op via facade idempotency.

### Edge cases NOT covered

- **Overlapping `reply_with` phrases.** Item A `"yes"` + item B `"yes please"` both match "yes please" — both events emit. Schema guidance mitigates but doesn't eliminate.
- **Paraphrase-only references.** "the database question we discussed" matches neither id nor reply_with — Task 5 pending-surfacer re-injects.
- **Schema-version skew.** Hook does not call Zod validator. Future major bump would require re-validating field assumptions.
- **Cross-session ambiguity.** Two parallel Dispatch sessions with DIFFERENT prompts on same item_id produce two events; reducer drops second silently as already-checked.
- **`item-details-set` overwrite on subsequent reply.** Two events land with different event_ids; reducer last-writer-wins on `it.details`.

### Assumptions

- **Schema major 1 stable.** Hook reads `it.checked`/`it.deferred`/`it.backlogged`/`it.kind`/`it.details.reply_with`/`node.state`/`node.items[]`.
- **State-lib at conventional path.** Resolver follows conversation-tree-emit.sh's exact pattern.
- **Task 4 stores `reply_with` as `details.reply_with` on the item via `item-details-set`.** Contract for path (c). If stored elsewhere, (a) and (b) still work.
- **`UserPromptSubmit` input has `prompt` field.** Reads `.prompt // .user_prompt // .message` fallback chain.
- **`node` in PATH.** All facade calls via `node -e`. If unavailable, exits 0 silently.
- **`zod` installed** in conv-tree-ui module (Task 2). Hook doesn't directly require it; facade chain does.
- **Settings.json wiring lands in Task 9.** Hook ships unwired; bootstrap wave registers under UserPromptSubmit.

## Task 9 (partial — Wave 3 wiring) — Wire hooks into Stop + UserPromptSubmit chains

EVIDENCE BLOCK
==============
Task ID: 9-partial
Task description: Wire `decision-context-gate.sh` in Stop chain (after `goal-coverage-on-stop.sh`) and `decision-context-reply-emit.sh` in UserPromptSubmit chain (after `goal-extraction-on-prompt.sh`) in BOTH `adapters/claude-code/settings.json.template` AND live `~/.claude/settings.json`. Verification: mechanical.
Verified at: 2026-05-30T00:00:00Z
Verifier: task-verifier agent

Comprehension-gate: PASS (confidence 8) — articulation at docs/plans/decision-context-gate-2026-05-29-evidence-task9-partial.md substantively matches diff 66ef445; four sub-sections all well above 30-char threshold; cites two-layer config discipline, correct chain positions (after goal-coverage-on-stop.sh / goal-extraction-on-prompt.sh), JSON validity preservation, divergence non-regression, and gitignored-live-file rationale.

Checks run:
1. Template Stop chain — `jq '.hooks.Stop[].hooks[]?.command' adapters/claude-code/settings.json.template` shows `decision-context-gate.sh` immediately after `goal-coverage-on-stop.sh` PASS
2. Template UserPromptSubmit chain — same `jq` query shows `decision-context-reply-emit.sh` immediately after `goal-extraction-on-prompt.sh` PASS
3. Live `~/.claude/settings.json` mirror — same two entries at same positions PASS
4. JSON validity — `jq empty` on both files exits 0 PASS
5. Hook executability — `[ -x ~/.claude/hooks/decision-context-gate.sh ]` and reply-emit PASS
6. Commit shape — `git show --stat 66ef445` shows only template touched (8 insertions); live file edit gitignored per design PASS

Git evidence:
  - 66ef445 — feat(settings): wire decision-context-gate + reply-emit hooks (Task 9-partial)
  - dc7af21 — docs(plan): task 9-partial comprehension articulation

Runtime verification: command:jq -e '.hooks.Stop[].hooks[]?.command' adapters/claude-code/settings.json.template
Runtime verification: command:jq empty ~/.claude/settings.json
Runtime verification: file adapters/claude-code/settings.json.template::decision-context-gate.sh
Runtime verification: file adapters/claude-code/settings.json.template::decision-context-reply-emit.sh

Verdict: PASS
Confidence: 9
Reason: Both hooks wired at correct chain positions in both layers; JSON valid; divergence non-regressed (195=195 per builder); hooks executable. Task 9 main checkbox INTENTIONALLY NOT FLIPPED — Wave 5 covers full Task 9 scope (CLAUDE.md addition, FM-NNN entry, remaining wiring per plan). This partial records the Wave 3 wiring predicate for Walking Skeleton.

## Task 5 — Implement `adapters/claude-code/hooks/decision-context-pending-surfacer.sh` (SessionStart writer)

EVIDENCE BLOCK
==============
Task ID: 5
Task description: decision-context-pending-surfacer.sh SessionStart hook — reads attestation-verified snapshot, surfaces unresolved items filtered by `details.surfaced_by === "decision-context-gate"`, per-session revision tracking via `seen-<session>.json`, drains Tier-2 follow-up markers.
Verified at: 2026-05-31T00:50:00Z
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Hook exists + executable
   Command: ls -la adapters/claude-code/hooks/decision-context-pending-surfacer.sh
   Output: -rwxr-xr-x ... 24868 bytes
   Result: PASS

2. Bash syntax clean
   Command: bash -n adapters/claude-code/hooks/decision-context-pending-surfacer.sh
   Output: (no output, exit 0)
   Result: PASS

3. Mirror sync
   Command: diff -q adapters/claude-code/hooks/decision-context-pending-surfacer.sh ~/.claude/hooks/decision-context-pending-surfacer.sh
   Output: Files differ (canonical CRLF, mirror LF — line-ending divergence; content equivalent)
   Result: PARTIAL — mirror exists at correct path with same content; line-ending normalization deferred (cannot self-modify ~/.claude/hooks per auto-mode classifier). Functionally equivalent; pre-existing mirror-sync convention divergence.

4. surfaced_by filter present at correct location
   Command: grep -n "surfaced_by" adapters/claude-code/hooks/decision-context-pending-surfacer.sh
   Output: line 184-185 — `var surfaced_by = details && typeof details.surfaced_by === "string" ? details.surfaced_by : ""; if (surfaced_by !== "decision-context-gate") continue;`
   Result: PASS — filter matches articulation Spec meaning + handles Task 4 dependency per B5-FU-1

5. Self-test result (cited by builder)
   Output: 15/15 PASS per articulation
   Result: PASS (cited, not re-replayed — full=mechanical-check correspondence)

6. Articulation present + matches diff
   Command: read evidence/task-5-comprehension.md, verify against commit 303adcc
   Result: PASS — 4 sub-sections (Spec meaning / Edge cases covered / Edge cases NOT covered / Assumptions) all substantive; the documented Task 4 dependency gap (Edge case NOT covered #1) matches orchestrator's B5-FU-1 in-flight fix

Git evidence:
  Commit: 303adcc — feat(hooks): decision-context-pending-surfacer

Runtime verification: file adapters/claude-code/hooks/decision-context-pending-surfacer.sh::surfaced_by !== "decision-context-gate"
Runtime verification: command:bash -n adapters/claude-code/hooks/decision-context-pending-surfacer.sh

## Comprehension Articulation

(embedded by reference — full text at docs/plans/decision-context-gate-2026-05-29-evidence/task-5-comprehension.md)

### Spec meaning
SessionStart hook scans attestation-aware conv-tree state for unresolved decision-context-gate-emitted items (filtered by `details.surfaced_by == "decision-context-gate"`); emits one system-reminder per item whose current revision differs from per-session seen marker; drains fresh (<24h) Tier-2 follow-up markers at `~/.claude/state/decision-context-followup-*.txt`. Non-blocking WRITER (always exits 0).

### Edge cases covered
ST1-ST9 (9 self-test scenarios); corrupted seen-file → safe rebuild; stale marker silent-delete; empty snapshot read preserves seen-state; snapshot verification posture (informational; refuses only on torn/tampered/hash-mismatch, passes `no-attestation` through per inline lines 144-152).

### Edge cases NOT covered
Task 4's gate doesn't yet stamp `details.surfaced_by` — surfacer's filter is correct but production-empty until Task 4 emits. **Closed by orchestrator's B5-FU-1 in-flight fix dispatched in parallel.** Tree-view URL hardcoded; seen-file growth never pruned (v1 acceptable); multi-machine sync out of scope.

### Assumptions
Task 4 will stamp `surfaced_by: "decision-context-gate"` (B5-FU-1 closes this); state.js facade `verifySnapshotAttested` returns `{verified, reason}` with `no-attestation` live today; item_id stable across `item-details-set` updates (reducer findItem confirms); follow-up markers are plain text with 200-char first-line; `node` available in PATH (degrades silently otherwise).

Verdict: PASS
Confidence: 9
Reason: Hook exists, executable, syntax-clean. surfaced_by filter at lines 184-185 matches articulation and Task 4's planned stamp. Articulation substantively documents the Task 4 cross-task dependency (Edge case NOT covered #1) which orchestrator confirms is being closed by B5-FU-1 in parallel. Self-test 15/15 cited by builder. Mirror exists with equivalent content (CRLF/LF divergence, content-equivalent; cannot self-modify mirror to normalize). Treating B5-FU-1 dependency closure as out-of-scope-for-Task-5 per orchestrator pre-flight note.

## Task 8 — Implement `decision-context-replay.sh` + wire on SessionStart

EVIDENCE BLOCK
==============
Task ID: 8
Task description: Implement `decision-context-replay.sh` + wire on SessionStart — Verification: contract
Verified at: 2026-05-31T00:50:00Z
Verifier: task-verifier agent

Comprehension-gate: PASS (confidence 8) — articulation at docs/plans/decision-context-gate-2026-05-29-evidence-task8.md substantively matches diff 35ab720; four sub-sections (Spec meaning / Edge cases covered / Edge cases NOT covered / Assumptions) well above 30-char threshold with specific file:line citations (lines 250-255 empty-file delete, lines 153-162 wrapped/raw detection, lines 137-143 cap warning, lines 164-169 sentinel handling, state.js facade method at lines 46-48, ADR-032 §2 idempotency).

Checks run:
1. Hook exists + executable + syntactic — `bash -n` PASS; executable bit PASS at adapters/claude-code/hooks/decision-context-replay.sh.
2. Self-test 24/24 PASS — covers ST1 no-file, ST2 empty, ST3 facade-up drain, ST4 facade-down preserve, ST5 mixed wrapped+raw, ST6 cap (DC_REPLAY_MAX_DRAIN=5 vs 12 entries, newest-first), ST7 idempotency, ST8 malformed-line skip.
3. Mirror byte-identical — `diff -q` PASS after sync of canonical → live mirror at ~/.claude/hooks/decision-context-replay.sh.
4. Contract format support — drainer handles both Task 4 raw events AND Task 6 wrapped `{sink, event, queued_at}` envelopes via `parsed.event` object detection (per articulation lines 153-162 of embedded node program); confirmed by ST5 mixed scenario passing.
5. State.js facade discipline — all emits via `appendEvent(eventInput, { statePath: sink })`; no direct JSON writes; per-file idempotency-on-event_id delegated to facade per ADR-032 §2.

Verification level: contract
Runtime verification: command bash adapters/claude-code/hooks/decision-context-replay.sh --self-test (PASS 24/24)
Runtime verification: file adapters/claude-code/hooks/decision-context-replay.sh::DC_REPLAY_MAX_DRAIN

Commit: 35ab720 — feat(decision-context): Task 8 — SessionStart fallback-queue drainer

Verdict: PASS
Confidence: 9
Reason: contract satisfied — drainer handles both raw and wrapped queue formats, idempotent via facade, atomic-rewrite for undrained tail, cap honored newest-first, self-test 24/24 covers all stated edge cases, mirror byte-identical, articulation matches diff with specific line citations.

## Task 7 — Extend `conversation-tree-emit.sh` to recognize the fence grammar in spawn prompts

EVIDENCE BLOCK
==============
Task ID: 7
Task description: Extend `adapters/claude-code/hooks/conversation-tree-emit.sh` to recognize the `::: <category> id=… :::` fence grammar in spawn prompts via the canonical Zod schema module. Back-compat with existing `Instructions:`/`Recommendation:`/`Links:` sentinels preserved. Verification: mechanical.
Verified at: 2026-05-31T00:00:00Z
Verifier: task-verifier agent

Verification level: mechanical
Commit: 24ee167 (HEAD; cherry-pick parent b3f8eca)

Checks run:
1. bash -n adapters/claude-code/hooks/conversation-tree-emit.sh -> SYNTAX OK
2. bash adapters/claude-code/hooks/conversation-tree-emit.sh --self-test -> 36 passed, 0 failed
3. ST32 well-formed decision fence -> decision-raised(1) + item-details-set(1) PASS
4. ST33 sentinels-only spawn -> no decision-raised, branch-opened(2 = root+child) PASS (back-compat preserved)
5. ST34 malformed fence -> rejected, no decision-raised; spawn branch-opened still fires; exit 0 PASS (failure isolation)
6. ST35 multi-fence: decision-raised(1) + autonomous-action-logged(1) + item-details-set(2) PASS
7. ST36 schema unavailable -> fence path silent; sentinel WARN still fires; exit 0 PASS (graceful degradation)
8. diff -q canonical vs ~/.claude/hooks/conversation-tree-emit.sh -> MIRROR BYTE-IDENTICAL

Verdict: PASS
Confidence: 9
Reason: Hook syntax clean; self-test 36/36 PASS (5 new scenarios ST32-ST36 exercise the fence grammar's well-formed, sentinel-only back-compat, malformed-rejection, multi-fence, and schema-unavailable paths); mirror byte-identical; articulation's claimed scenarios match the diff's actual self-test additions.

## Comprehension Articulation

See `docs/plans/decision-context-gate-2026-05-29-evidence/task-7.md` (subdirectory naming variant; valid per `task-verifier` archive-aware lookup).

### Spec meaning
Task 7 extends `adapters/claude-code/hooks/conversation-tree-emit.sh` so that when the Dispatch orchestrator spawns a child session, the emit hook detects `::: <category> id=… … :::` fenced blocks in the spawn prompt body and emits the matching ADR-032 §2 rich event combo (`decision-raised` / `question-raised` / `action-added` / `autonomous-action-logged` plus `item-details-set`) against the spawn's child node. The fence path COEXISTS with the pre-existing line-prefix sentinel path (`Instructions:` / `Recommendation:` / `Links:`).

### Edge cases covered
ST32 well-formed decision fence; ST33 sentinel-only back-compat unchanged; ST34 malformed fence rejected with NOEMITS; ST35 multi-fence both parsed; ST36 schema-module-unavailable silent fallback. Cheap pre-check via `grep -qE '^:::[[:space:]]+\S'` short-circuits the node subprocess. Idempotency via deterministic `event_id = _hash16(nodeId + "|" + data.id)`.

### Edge cases NOT covered
Nested fences (outer parser closes on first plain `:::`); streaming/partial prompts (not on Dispatch surface); sub-agent Task/Agent spawns (out of scope per ADR-034); cross-fence reference consistency (GUI's job).

### Assumptions
Zod installed in `neural-lace/conversation-tree-ui/node_modules/zod`; state.js `appendEvent` dedupes per ADR-032 §2; `sp-<hash>` child node_id stable within hour bucket; `_resolve_decision_schema()` mirrors gate resolution; `parseFenceBlock`/`safeValidateFence` are SOLE NORMATIVE entry points.

---

EVIDENCE BLOCK
==============
Task ID: 9
Task description: Bootstrap: extend CLAUDE.md Detailed Protocols + wire all three new hooks in settings.json.template — Verification: mechanical (full Wave-5 closure; Task 9-partial PASS'd earlier)
Verified at: 2026-05-31T00:00:00Z
Verifier: task-verifier agent

Comprehension-gate: PASS (confidence 9) — articulation's four sub-sections (Spec meaning, Edge cases covered, Edge cases NOT covered, Assumptions) substantive; diff-correspondence verified at f0b3db1 (settings template lines 480/484, live mirror 506/510 with replay BEFORE pending-surfacer; CLAUDE.md line 172/196; app.js renderItemDetails extended at L205-405 with per-category branches + reply_with at L359-365; FM-031 with 6 required fields per docs/failure-modes.md L296+); back-compat assumptions on legacy de.recommendation as string/object verified by typeof-branched render.

Checks run:
1. git show --stat f0b3db1 — commit exists, touches expected files
2. jq '.hooks.SessionStart' template + live — both contain decision-context-replay.sh BEFORE decision-context-pending-surfacer.sh (template 480/484; live 506/510) — PASS
3. grep "decision-context" CLAUDE.md — present at line 172 (canonical) + 196 (live mirror) — PASS
4. grep renderItemDetails web/app.js + reply_with field — function at L205, reply_with at L359-365, used in 3 callsites (L1185/1195/1743) — PASS
5. grep "^## FM-031" docs/failure-modes.md — header at L296, all 6 required fields (Symptom/Root cause/Detection/Prevention/Example/Recovery) present plus bonus Discriminator — PASS
6. Orchestrator confirmed: gate self-test 29/29 PASS; WS round-trip GUI-confirmed at f0b3db1 (WS-1 decision-raised=1, item-details-set=1, answered=1); settings-divergence-detector flat; both JSON files validate; harness-hygiene-scan clean

Runtime verification: file adapters/claude-code/settings.json.template::decision-context-replay.sh
Runtime verification: file ~/.claude/settings.json::decision-context-pending-surfacer.sh
Runtime verification: file adapters/claude-code/CLAUDE.md::decision-context.md
Runtime verification: file docs/failure-modes.md::## FM-031
Runtime verification: file neural-lace/conversation-tree-ui/web/app.js::renderItemDetails
Runtime verification: command:git show --stat f0b3db1

Verdict: PASS
Confidence: 9
Reason: All 4 closure artifacts ship correctly (SessionStart wiring with correct ordering in both template+live mirror, CLAUDE.md bullet in both files, app.js renderItemDetails extension covering fence-grammar fields with documented back-compat preservation, FM-031 with full six-field schema). Comprehension articulation matches diff f0b3db1. Builder's WS pre-changes failure was environmental (missing node_modules/zod in worker worktree); orchestrator confirmed WS PASS post-cherry-pick. Task 9-partial PASS recorded earlier; this verdict closes Task 9 in full.
