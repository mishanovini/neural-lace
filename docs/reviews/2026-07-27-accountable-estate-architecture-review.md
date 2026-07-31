# Architecture Review — Accountable Estate program (2026-07-27)

**Reviewer:** architecture-reviewer (worktree-isolated, read-only)
**Scope:** docs/lessons/2026-07-27-outcome-blind-closure-and-estate-entropy.md ·
docs/designs/accountable-estate-2026-07-27.md · docs/designs/estate-performance-governor-2026-07-27.md
**Verdict: SOUND-WITH-AMENDMENTS** — direction confirmed (the reviewer's independent Phase-0
derivation converged on nearly the same spine before reading the proposals), with two P0-blocking
amendments and a mandatory resequencing of P1.

**THE ONE THING:** the admission ticket must be DERIVED, never DECLARED — enforced by a sourced lib
in EVERY dispatcher (gate + session-resumer + any runner), with lineage checked from mechanical
facts (heartbeat exists ∧ ask-registry attach-session record ∧ work-item auto-created by the
dispatch emission). A self-registered record checked by a client-side PreToolUse gate recreates both
documented failure classes of this estate at once: decision-064 (client gate ≠ every writer —
session-resumer.sh spawns `claude -p --resume` from a scheduled task with zero hooks) and
pattern-degradation (self-declared fields become ritual).

## Findings (ranked)

- **F1 [CRITICAL, PROVEN by measurement]** P0's proposed caps (4/min, burst 6, cap 5) are
  contradicted by measured LEGITIMATE load: the protected downstream-product orchestrator sustains 15–21
  dispatches/min; 5 of the last 10 days ran 1,200–1,400 dispatches/day (storms are CHRONIC, not a
  one-off). As written, the governor throttles the operator's most-valued work on night one and gets
  disabled in frustration. → P0 ships **observe-first** (would-block ledger only; repo precedent:
  9f22cd8), enforce flips only after ≥7 days of calibration.
- **F2 [CRITICAL, PROVEN]** PreToolUse gate does not cover all dispatchers (resumer, cloud/scheduled
  — Decision-011 sessions have no hooks). → Admission = ONE lib (sessionstart-singleflight idiom:
  mkdir-atomic, fail-open) sourced by every dispatch path; the gate is a convenience surface, never
  the guarantee.
- **F3 [CRITICAL, PROVEN]** The janitor cannot be the RESOURCE backstop (hourly staleness ≈ ~900
  dispatches at peak; a janitor on a starving machine runs late or never — today it could not have
  saved today; and "extends health-tick" violates health-tick's written PASSIVE contract). → Split:
  admission lib = resource authority (ms); NEW active janitor task = accountability authority
  (flag→stop unattributable work, SLA advance, prune) with its own reviewed contract.
- **F4 [MAJOR]** Derived lineage over self-declared registration (see THE ONE THING).
- **F5 [MAJOR]** Consolidation target ≤3, not ≤2: one obligation store + one dumb telemetry log
  (signal-ledger stays a flight recorder — it solved this incident's forensics BECAUSE it is dumb)
  + plans-as-spec. backlog/NEEDS-YOU/operator-todo/nl-issues become views or absorbed verbs.
- **F6 [MAJOR]** Migration sequencing: views-first → new-writes-via-verb (constitution wording
  updated atomically) → freeze+backfill → retire; one store at a time; divergence detector during
  each overlap window. NEEDS-YOU.md is constitution-anchored — regenerating it as a view while
  un-migrated writers still hand-write it clobbers live operator asks.
- **F7 [MAJOR]** Backpressure vs LLM retry-without-backoff (PROVEN precedent: UNRESOLVED__ spam):
  deny messages must prescribe the concrete alternative + retry-after; breaker counts denials;
  denial-rate gets its own alarm.
- **F8 [MAJOR]** Slot lifecycle: background builders never emit done (workstreams-emit contract) —
  slot liveness must derive from heartbeats (hb_classify), TTL only as final fallback.
- **F9 [MINOR]** Token bucket as read-modify-write file loses updates → stamp-file-per-dispatch,
  count files younger than window.
- **F10 [MINOR — substrate recommendation]** Per-machine append-only JSONL, hostname-scoped files
  (one writer per file), O_APPEND, reduced by the janitor into snapshot.json with an explicit
  generated_at staleness stamp; snapshot-only committed to the coordination repo for cross-machine
  visibility. NOT SQLite on the write path (spawn cost, git-merge hell, MSYS locking); SQLite fine
  later as a read-side index.
- **F11 [MINOR — LOE]** v1 = per-PLAN classing (3–5 classes, plan-level P50/P90 bands + the
  concentration flag) mined from plan evidence + git history. Per-task token attribution from
  interleaved transcripts is noise-dominated; go finer only after v1 proves out.

## Pre-mortem (the operator's exact fear, and its structural prevention)
Failure path: P0 enforced uncalibrated → throttles protected work → env-var disable → off forever;
migration stalls at 9 stores; janitor demoted to flag-only into the saturated surface; brief never
built. **Prevention, binding on the program's plan:** (a) each phase closes with an outcome metric +
re-check date, auto-reopen on recurrence; (b) subtraction in every phase's Definition of Done — a
named store or hook RETIRED, doctor-verified, before the phase closes; (c) program WIP-limit: one
phase in flight; (d) observe-first before every enforcement flip.

## Revised build order (slices, first slice corrected)
1. **Slice 1 — read-only estate inventory (THE first slice):** new janitor task reduces
   already-existing truth (heartbeats, process table, `git worktree list`, signal-ledger tail,
   ask-registry) into snapshot.json + a rendered daily brief. Zero write-path changes, zero
   migration. Delivers the P1 outcome metric ("what is running and who asked, <30 s") immediately.
2. Slice 2 — SLA/deadline/default-action verbs on ask-registry + the ≤5-asks panel in the brief.
3. Slice 3 — admission lib (slots+rate+HALT), OBSERVE mode, called from gate + resumer.
4. Slice 4 — enforce flip after ≥7-day calibration separates storm from legitimate load.
5. Slice 5+ — surface consolidation, one store at a time per F6.

## Verdict-change conditions
→ NEEDS-RESHAPING if a coverage audit finds a substantial dispatch path emitting nothing into the
ledger, or if the build proceeds gate-enforced/store-first as originally written.
→ SOUND once 7 days of observe-mode data confirm calibrated caps produce ~zero false positives and
slice 1 demonstrably answers "what is running and who asked" from one surface.
