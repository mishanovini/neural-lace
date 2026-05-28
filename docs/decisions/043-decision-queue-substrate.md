# 036 — Decision Queue substrate (throughput-bottleneck-reducer)

- **Date:** 2026-05-24
- **Status:** Active
- **Stakeholders:** Misha (sole operator + decision-maker); Dispatch (cloud-side orchestrator that drives most asks at him); the daily harness evaluator script; the Conversation Tree UI (downstream consumer that renders the queue).
- **Plan:** `docs/plans/decision-queue.md`

## Context

Misha is the throughput bottleneck on the whole multi-project system. Dispatch surfaces decisions at him constantly. Today they arrive as unsorted, weakly-structured prose in chat — sometimes a recommendation, sometimes raw options, sometimes "what should I do?". He has to:

1. Re-load enough context to understand the question
2. Compare it against the other 5–15 pending asks he carries in his head
3. Decide priority on his own
4. Reply

That stack of work is what makes him the bottleneck. The harness already has several adjacent substrates — backlog (`docs/backlog.md`), discoveries (`docs/discoveries/`), findings ledger (`docs/findings.md`), session-end-protocol markers — but none of them is shaped like *"a decision the human owes, with enough context to resolve it"*. Each substrate exists for a different consumer and a different lifecycle:

- Backlog = work the team intends to do (not a decision-to-make queue)
- Discoveries = mid-process realizations needing a Yes/No (single-realization-shaped, not multi-option)
- Findings = class-aware observations (audit trail, not asks)
- session-end markers = PAUSING/BLOCKED on a specific session (per-session, not durable across sessions)

The gap is a **persistent prioritized decision queue** with rich per-item context (recommendation + counterargument + deferral cost + downstream impact + mode flag + dependencies + source link) that any agent can write to and that Misha resolves at his own cadence through a UI he already has open (the Conversation Tree).

This ADR locks the substrate decisions.

## Decision

A new harness substrate: **Decision Queue.**

1. **Storage location.** Per-machine, at `~/.claude/state/decision-queue/queue.json` (computed view) + `queue.audit.jsonl` (append-only audit log). NOT committed to any repo. Mirrors how the Conversation Tree state is stored (`~/.claude/state/conversation-tree/...`).

2. **File format.** Single JSON file containing an array of items, with a top-level `schema_version`. Each item validates against `adapters/claude-code/schemas/decision-queue.schema.json` (JSON Schema 2020-12). Operations are atomic-write (tmpfile + rename). The audit log is JSONL, append-only, never read by the queue itself — for debugging and replay only.

3. **Item field set.** Per Misha's spec (verbatim, six paragraphs in the user message inviting this work):
   - Identity: `id` (UUID), `created_at`, `updated_at`, `closed_at`
   - Routing: `project`, `source_session_id`, `source_doc_links[]`
   - Content: `question`, `recommendation`, `counterargument`, `consequence_of_deferring`
   - Structure: `mode` (enum `QUICK`/`PICK`/`DEEP`), `options[]` (for `PICK`), `downstream_impact[]`, `dependencies[]`, `dependents[]` (computed)
   - Lifecycle: `state` (enum `open`/`answered`/`superseded`/`moot`), `answer`, `answer_by` (enum `user`/`dispatch`/`auto-default`)
   - Salience: `priority_score` (computed), `highlighted` (bool), `highlight_reason`, `highlight_level` (enum `subtle`/`strong`/`urgent`), `highlight_history[]`

4. **Priority score formula (v1).** Documented as a plain formula so any reviewer can adjust:
   ```
   score = (age_days * 0.1)                                # decision-staleness pressure
         + (dependent_count * 2)                          # unblocking impact
         + (highlight_weight[highlight_level] or 0)       # urgent=10, strong=5, subtle=2, null=0
         + (10 if state == 'open' and now - updated > 14d else 0)  # aging tax at 14d
   ```
   Computed on `list` and on each `add`/`update`; cached in the item's `priority_score` field for cheap sorting.

5. **Mechanism vs Pattern split.**
   - **Mechanism (storage + schema):** `decision-queue.sh add/list/get/close/update/highlight/unhighlight/--self-test` script + `decision-queue.schema.json` schema validation. These are deterministic and self-tested.
   - **Pattern (when to add, when to highlight, when to mark moot):** documented in `docs/dispatch-decision-queue-tools.md`. Self-applied by Dispatch and human operators. No hook polices "should this have been a decision?" — that would be the wrong shape.

6. **Conv Tree integration is a separate session's work.** The Conv Tree Decisions panel lives in `conversation-tree-ui/` on a different branch with an in-flight UX redesign. This ADR ships the substrate; `docs/conv-tree-decisions-panel-spec.md` is the handoff so the next session can build the panel against a stable contract.

7. **Auto-emit to Conv Tree is deferred.** ADR-031/034 enumerate the spawn tools that auto-emit to the tree. Adding `decision-queue.sh` operations to the auto-emit set is a follow-up that requires extending `conversation-tree-emit.sh`. Until then, Dispatch can manually note in chat ("added DQ-<id>: <question>") if the operator wants tree visibility before the panel ships.

## Alternatives Considered

- **A. Reuse `docs/backlog.md` for decisions.** Rejected: backlog is "work we'll do," not "decisions the human owes." Mixing the two erodes both: the backlog gets noisy with one-line questions; decisions get lost in a list of build tasks. They are different lifecycles.

- **B. Reuse `docs/findings.md` (the findings ledger).** Rejected: findings are *observations* with class-aware feedback (six-field schema for `Severity`/`Scope`/`Source`/`Location`/`Status`). Decisions are *asks* with options + a recommendation; the shape diverges enough that overloading findings would weaken both schemas.

- **C. Reuse `docs/discoveries/`.** Closer fit (discoveries already auto-apply reversible decisions and pause-and-surface irreversible ones). Rejected because the discovery surface is *per-discovery-as-a-file* (one markdown file per realization). The decision queue needs *multi-item ordered, filterable, query-able* — a list shape, not a directory-of-files shape. Discoveries also model a different lifecycle (decided→implemented vs answered→closed).

- **D. Build it as a database (sqlite) instead of JSON.** Rejected for v1: adds a dependency, complicates atomic writes from shell, makes the audit log story harder. JSON file scales fine until ~10k items; if we ever hit that we can migrate.

- **E. Build it inside the Conversation Tree state file.** Rejected: the conv-tree state is gated by ADR-031/034 attestation + Dispatch-spawn-only scope. Decision queue items are not spawn events — they have their own lifecycle. Co-locating would muddy both substrates and force every decision-queue operation through the conv-tree attestation gate (overkill).

- **F. Use a third-party tool (Linear, GitHub Issues, etc.).** Rejected per Misha's "Conv Tree integration" requirement — the queue has to be readable inside the Conv Tree, which is local. Round-tripping through an external service adds latency and a credential surface.

## Consequences

**Enables:**
- Dispatch can write to a single canonical surface every time it needs Misha to decide something. The "where do I put this?" question dissolves.
- The Conv Tree Decisions panel (Task B, follow-up session) reads from a stable, documented source. The panel can ship without changing the substrate.
- The daily harness evaluator surfaces recommendations directly into the queue (Task E in the plan). Misha no longer has to scrape the daily packet.
- Future agents — `claim-reviewer`, `end-user-advocate`, `prd-validity-reviewer` — can route their structured asks into the queue without inventing per-agent surfaces.
- Highlight ability gives Dispatch a way to draw attention to the most-blocking items (e.g., "this blocks 8 other items," "aging past 14 days"). Misha sees them first.

**Costs:**
- Yet another piece of per-machine state to manage. Mitigated: the live file is gitignored (lives at `~/.claude/state/decision-queue/`); the substrate ships as schema + script in the harness kit; the rule for "when to add a decision" lives in `docs/dispatch-decision-queue-tools.md` (Pattern-level).
- Per-machine state means cross-machine sync is manual (same as Conv Tree state today). Acceptable per the "single operator" assumption.
- The priority-score formula (v1) is a guess. Mitigated: it's a documented formula in this ADR; any reviewer can adjust by editing the script's `compute_priority_score()` function. ADR amendment if/when the formula needs to change shape (not just constants).
- Decisions can stack up unread if Dispatch over-uses the substrate. Mitigated: aging-tax in the priority score surfaces stale items; daily evaluator can highlight aging items; ultimately Misha's pruning is the backstop.

**Blocks:**
- Nothing on master is blocked by this ADR — additive substrate.

## Refutation criteria

- If after 30 days of use Misha reports the substrate is making things WORSE (more friction, not less; queue stays empty because Dispatch finds it easier to ask in chat; or queue grows unbounded because Dispatch over-uses it), the substrate is wrong-shaped. Refutation: weekly check via the daily evaluator on queue size + close-rate + Misha-reported friction.
- If the per-machine constraint hurts (e.g., Misha wants to triage the queue from a phone away from the desktop), refutation: the queue should be moved to a synced backing store (Supabase / GitHub gist / shared dropbox file). Documented as a follow-up ADR if/when needed.

## Implementation log

(populated as tasks land in `docs/plans/decision-queue.md`)
