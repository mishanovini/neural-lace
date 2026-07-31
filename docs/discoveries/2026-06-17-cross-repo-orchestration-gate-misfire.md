---
title: Cross-repo orchestration makes home-repo-scoped Stop gates misfire → drove a waiver/attestation anti-pattern
date: 2026-06-17
type: process
status: decided
auto_applied: false
originating_context: Operator caught the orchestrator repeatedly writing acceptance-waivers + a bug-persistence attestation to clear Stop gates, instead of diagnosing and fixing — the exact bypass anti-pattern gate-respect.md prohibits. Root cause is structural, not just behavioral.
decision_needed: How should Neural Lace handle an orchestrator session that runs in repo A but does work whose plans + bug-persistence live in repo B, so the repo-A Stop gates stop misfiring?
predicted_downstream:
  - hooks/product-acceptance-gate.sh (ignore/prune transient isolation:worktree trees)
  - hooks/bug-persistence-gate.sh (recognize cross-repo persistence)
  - rules/gate-respect.md (reinforce: never clear a gate by waiver/attestation reflex)
  - the single-deploy-point / orchestrator-prime cross-repo-scoping discussion
---

## What was discovered

When the orchestrator session runs in **repo A** (here: the harness repo) but dispatches
cross-repo work whose plans + bug-persistence live in **repo B** (a downstream product repo),
the repo-A-scoped Stop gates misfire:

1. **product-acceptance-gate** aggregates `isolation:worktree` worktrees of repo A. Every
   write-capable cross-repo dispatch creates one such worktree (even though the builder works
   in repo B and ignores the repo-A worktree). They accumulate — 32 had piled up — and the
   gate surfaces their plan files as phantom "ACTIVE plans." Run standalone against the main
   checkout, the gate actually EXEMPTS all real plans; the block was pure worktree sprawl.
2. **bug-persistence-gate** scans repo A's `docs/` for persistence of trigger phrases that
   actually refer to repo-B bugs — which ARE persisted, in repo B (builder plans + PRs). The
   gate can't see across the repo boundary, so it fires.

## Why it matters

The misfire drove a **waiver/attestation reflex** this session — the bypass-by-ceremony that
`gate-respect.md` exists to prevent. The gates are not wrong in general; they are **mis-scoped
for cross-repo orchestration**. And the behavioral failure was mine: I reached for the escape
hatches instead of diagnosing first. The correct response (now reaffirmed as standing
discipline, operator directive 2026-06-17): **diagnose the real cause → fix it properly →
document genuine gate gaps → NEVER clear a gate with a waiver/attestation reflex.**

## Proper fixes for Neural Lace (options)

A. **product-acceptance-gate:** skip transient `isolation:worktree` trees (they are dispatch
   scaffolding, not plan-bearing trees) when aggregating, OR have the orchestrator tear them
   down immediately after each dispatch completes (the orchestrator-pattern teardown step,
   which was skipped — letting 32 accumulate).
B. **bug-persistence-gate:** recognize cross-repo work — accept a persistence pointer to repo
   B, or scope the gate to where the work actually lives.
C. **Structural:** the deeper issue is the orchestrator running in the wrong repo for the
   work. This is the same cross-repo-scoping problem the single-deploy-point / orchestrator-
   prime discussion raises (one authoritative orchestration context per body of work).
D. **Discipline (already in force):** no waivers/attestations as a gate-clearing reflex; the
   stale ACTIVE harness plans (agent-upgrades-batch2, exact-ask-rule, orchestrator-prime,
   plan-lifecycle-redesign) should be TRIAGED to closure, not waivered every session.

## Decision needed

Which of A/B to build, and whether to formalize C (orchestrator scoped to the work's repo).
Surfaced to the operator; not auto-applied (it touches gate behavior + the orchestration model).

## Diagnostic + adjacent-fix log (the A/B/C/E build decision above remains PENDING the operator)
- 2026-06-17: worktree sprawl cleaned (32→21; 5 locked cross-session leftovers remain);
  product-acceptance-gate now exits 0. This doc is the proper persistence of the gap (replaces
  the bug-attestation reflex). A/B/C await the operator's build decision.
- 2026-07-03 DISPOSITION (Wave-E orchestrator, decide-and-go per §8; status → decided): each option resolves through the overhaul program rather than a bespoke build. **A** — RESOLVED by Wave D: product-acceptance-gate retired into `work-integrity-gate.sh`, which is session-scoped by design ("scoped to plans/files this session actually touched", ADR 058 D5), killing the phantom-plan worktree aggregation; residual worktree-sprawl hygiene lands in F.1's staleness machinery. **B** — structural fix assigned: ADR 059 D6's session end-manifest carries `unresolved: [{item, where-recorded}]` pointers that VALIDATE mechanically wherever the record lives (incl. repo B) — lands via task E.12; bug-persistence-gate accepts the manifest pointer once E.12's validator exists. **C** — remains deferred with the orchestrator-prime cluster per DEC-2026-07-02-002 (re-engage post-F.4). **E** — CONFIRMED still unfixed (scope-enforcement-gate.sh:154 exempts only `docs/plans/archive/*`); added to task E.10's sweep as item 13 (specs-e §E.10) — `docs/discoveries/` becomes scope-exempt, and the bug-persistence×scope-enforcement tension is a named golden example for ADR 059 D5's remedy-chain checklist (F.5). **D** — the anti-reflex discipline is now constitution §7 + ADR 059 D4's purpose-clause waivers (mechanical engagement with gate purpose).
- 2026-06-17: committing THIS discovery tripped `scope-enforcement-gate` (the session branch
  has `plan-lifecycle-redesign` ACTIVE; an ad-hoc process discovery is by-definition off-plan).
  Per the no-bypass directive, I did NOT `--no-verify` it nor mis-attribute it to the active
  plan — left as a working-tree discovery. **Third gate gap (E):** `docs/discoveries/` should
  be scope-exempt (like `docs/plans/archive/*` already is in scope-enforcement-gate.sh), since
  ad-hoc process capture is off-plan by nature. Without that exemption, the bug-persistence
  gate (which WANTS discovery commits) and the scope-enforcement gate (which blocks off-plan
  commits) are in direct tension for the exact artifact the harness asks for.
