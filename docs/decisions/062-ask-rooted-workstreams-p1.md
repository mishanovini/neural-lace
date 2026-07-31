# ADR 062 — Ask-rooted Workstreams P1: log-first mechanism-emitted progress + ask registry

- **Date:** 2026-07-12
- **Status:** Accepted — build in progress (`docs/plans/ask-rooted-workstreams-p1.md`, Tasks 1-9 + 11 landed on master; this record lands with Task 10, the plan<->ask linkage convention + registry backfill).
- **Stakeholders:** Misha (sole operator + user of the workstreams surface).
- **Supersedes / relates to:** revises the wave-O six-question cockpit's sole-truth derivation architecture (ADR 060, `docs/decisions/060-wave-o-observability-architecture.md`) — the wave-O derivation layer is demoted from sole-truth to a background auditor that badges drift; ADR 045 (Workstreams work-first reframe) is unaffected and its schema stays live for the Harness Health tab. Normative source: `docs/reviews/2026-07-10-ask-rooted-workstreams-design-sketch.md`.

## 1. Problem

The 2026-07-10 operator verdict on the wave-O six-question cockpit: "not helpful at all, super noisy... completely different from what I had originally asked for." Two failure classes compounded:

1. **Conversation-scroll archaeology.** Returning to a session days later costs a context-reestablishment tax — verbose transcripts, unclear relevance, no at-a-glance "what did I even ask for, how far along is it, what's waiting on me." This is NL-FINDING-024's failure class.
2. **Derivation as sole truth is fragile.** The prior cockpit derived ALL state from a reconciler walking plan files, heartbeats, and NEEDS-YOU.md at read time — any parser drift or format change silently produced wrong or noisy output with no independent record of what actually happened, when.

## 2. Decision

Rebuild around the operator's actual unit of thought — the **ask** — on a data layer designed to not rot the way the derivation-only layer did:

1. **Log-first, mechanism-emitted architecture.** A versioned JSONL progress-log event is emitted by a MECHANISM at each of six points in the ask/plan lifecycle (verifier flip, dispatch, NEEDS-YOU append, master merge, plan amendment, plan completion) — never by model memory. The log is the primary record; a background auditor (relaxed cadence, off the request path) compares the log against ground truth and BACKFILLS or BADGES divergence per an explicit per-class table (Task 12) — it never fabricates state and never overwrites the log's append-only history.
2. **The ask registry as the one new primitive** (`ask-registry.sh`, `~/.claude/state/ask-registry.jsonl` + a best-effort in-repo mirror): an append-only, fold-by-natural-key record of what the operator actually asked, auto-captured at the first prompt of a session (zero ceremony — Decision D3 below), summarized heuristically with an optional cheap-model upgrade, never Fable-tier.
3. **Plan<->ask linkage convention (this task, Task 10).** Every plan header records `ask-id:`; plan creation back-links the registry in the other direction (`start-plan.sh --ask-id <id>` calls `ask-registry.sh link-plan`, appending a `plan_linked` record). `plan-reviewer.sh` Check 16 WARNS — never blocks — when an ACTIVE `lifecycle-schema: v2` plan lacks a populated value, since not every historical or hand-authored plan has (or needs) a linked ask.
4. **Wave-O demotion, not deletion.** The six wave-O panes move to a Harness Health tab; their reconciler (`server/reconciler.js`) stays as-is as a SIBLING to the new auditor, not a replacement — no shared mutable state, no functionality lost.

## 3. Alternatives considered

- **Keep deriving everything at read time, just fix the noisy copy/filtering.** Rejected: treats the symptom. The 2026-07-04 and 2026-07-10 verdicts are the SAME failure class recurring — a derivation-only layer with no independent event record cannot self-diagnose drift; it can only be re-tuned until the next silent break.
- **Event-sourced writer + GUI-write gate** (the attic'd `workstreams-state-gate.sh` / `POST /api/event` design). Rejected: sketch §5 — that architecture required every mutation to flow through a gate the UI called directly, which re-introduces a write-path the UI can corrupt; the mechanism-emission model instead has ONLY already-wired hooks/scripts emit, so the UI is a read+narrow-write surface, never the event author of record.
- **A single dedup hash formula per event** (uniform natural key). Rejected (round-1 review finding) — would silently suppress legitimate recurrences (e.g., a re-dispatch of a failed task needs a NEW `task_started`, not a deduped no-op); Task 2's per-event-type natural-key table fixes this per type.
- **Ask-id required (blocking) rather than WARN.** Rejected for this task: forcing every ACTIVE v2 plan to carry a linked ask at commit time would hard-block the (currently: all) pre-existing plans created before this convention existed, and not every plan is meaningfully "asked for" via a captured session prompt (hand-authored infra plans, migration-only plans). A WARN nudges toward the convention without punishing the estate that predates it — mirrors the grandfather-gate precedent already established for Checks 14/15 (ADR 036-d).

## 4. Consequences

- **Enables:** the ask-tree landing page (Tasks 11-13) can group work by the operator's actual asks instead of by session or by six disconnected panes; a plan's progress bar and drill-down resolve unambiguously to the ask that requested it; the mechanical ask-done derivation (Task 12) can fire once every linked plan reaches a terminal state, closing the ask lifecycle without operator ceremony.
- **Costs:** every mechanism-emission splice is one more surface a future refactor must keep wired (mitigated by the manifest `honest_status` entries + harness-reviewer's mandatory pass over every splice diff, Task 7). The registry and progress-log are machine-local (`~/.claude/state/`) with a best-effort in-repo mirror for durability across worktrees — cross-machine sync is explicitly P3 (out of scope here).
- **Backward-compat:** plans without `ask-id:` (the entire pre-Task-10 estate) are grandfathered — Check 16 WARNs but never blocks, and the auditor's orphan lane holds events whose ask-id cannot yet be resolved rather than dropping them.

## 5. Refutation Criterion

This architecture's premise — "log-first mechanism-emission survives where derivation-only failed" — would be REFUTED if, after the full plan ships, the landing page's state again silently diverges from ground truth with no drift badge surfacing it (the exact failure mode this design targets). The Task 12 divergence-class table + its `--self-test` fixtures (each class produces exactly its specified backfill-or-badge action) are the standing, re-run-every-cadence check for this; a future NEEDS-YOU or plan-format change that breaks a parser is expected to produce a visible count-mismatch badge, per the Testing Strategy's reconciliation fixture, not silent wrongness.
