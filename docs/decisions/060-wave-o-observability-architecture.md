# 060 — Wave O observability architecture (derivation-first, tree trust-path retirement)

Date: 2026-07-06 · Status: decided (decide-and-go, constitution §8) · Owner: O-program orchestrator
Context: `docs/plans/nl-observability-program-2026-08.md` (ACTIVE, operator early-activation
2026-07-06) · Spec: `docs/plans/nl-observability-program-2026-08-specs-o.md` §O.0.5 ·
Normative design: `docs/reviews/2026-07-04-observability-design-sketch.md`.

## Decisions (all reversible = decide-and-go; batched here for §8 review)

1. **D-O1 — `nl` CLI is a new dispatcher** (`scripts/nl.sh`) over a new read-only
   derivation lib (`hooks/lib/observability-derive.sh`). No existing `nl` dispatcher;
   `hooks/lib/` is the shared-lib precedent (signal-ledger.sh). The lib is the
   canonical-oracle host mandated by CANONICAL-COUNTERS-01: one query, one named
   definition, reused by digest/KPI/cockpit/doctor.
2. **D-O2 — Heartbeat = per-session JSON file** written from EXISTING hook chains
   (SessionStart is at cap 8/8, Stop at 4/6 — zero new settings entries). Staleness
   computed on read, never written (law 1: derive-don't-maintain; staleness IS the
   crash signal).
3. **D-O3 — Turn-traces from the two Stop aggregators only** (stop-verdict-dispatcher,
   workstreams-stop-writer time their own members). Per-hook PreToolUse spans rejected:
   their verdict events already land in the ledger, and full instrumentation would be
   a budget + cooperative-discipline cost with no named consumer beyond `nl why`.
   Revisit at O.7 if the `nl why` drill shows diagnosis gaps.
4. **D-O4 (headline) — §O.4 retires the Workstreams event-sourced trust path,
   INCLUDING both blocking gates** (`workstreams-state-gate.sh`, `workstreams-stop-gate.sh`)
   and the tree item-extraction writers (`workstreams-turn-emit.sh`,
   `workstreams-extract-pending.sh` → attic/). Rationale: the rebuilt cockpit reads
   derived truth only, so the tree loses its last trusted consumer — law 2 (every
   signal has a named consumer or it doesn't ship) then REQUIRES retirement, and it
   closes NL-FINDING-024 (spawn writer→gate PreToolUse race, the waiver-tax
   generator) at the root rather than patching the disk-sync window. Blocking-gate
   budget 10→8. Item extraction is superseded by needs-you.sh (its own header says
   so). KEPT: workstreams-emit spawn/stop paths as ledger emitters, correlation
   ledger (resumer consumer), heartbeat tick (O.6 health surface). Undo = one revert
   restores template+manifest entries and un-attics the hooks.
5. **D-O5 — ntfy topic is a capability token**: lives only in
   `~/.claude/local/ntfy-topic` (public-mirror discipline — never repo/docs/chat);
   push script silently no-ops when absent, so the program never blocks on the
   operator reply (ask front-loaded via NEEDS-YOU).
6. **D-O6 — Contract-first parallelism**: O.9 builds against the frozen C4 lib API
   contract (specs-o §O.0.3) in parallel with O.3; orchestrator reconciles at merge.
   Worst case is a serial O.9 re-run.

## Refuters (HYPOTHESIZED risks, per constitution §1)

- D-O4: if a consumer of tree-state.json exists outside the mapped set (dynamic
  read not found by grep), retirement breaks it — the O.4 consumer-map check +
  divergence reconciler run BEFORE the retirement fragments are applied.
- D-O3: if the `nl why` 024-fixture drill cannot reconstruct a real block chain to
  the sketch's ~2-min bar, per-hook spans get reconsidered (O.7 gate).
