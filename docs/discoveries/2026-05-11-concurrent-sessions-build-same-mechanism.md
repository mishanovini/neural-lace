---
title: Concurrent sessions building same load-bearing mechanism (Check 13)
date: 2026-05-11
type: process
status: decided
auto_applied: true
originating_context: build-harness-infrastructure work-shape session resuming a crashed prior session
decision_needed: n/a — auto-applied (merge resolution + carve-out extension)
predicted_downstream:
  - adapters/claude-code/hooks/plan-reviewer.sh (both Check 4b and Check 13 carve-outs)
  - adapters/claude-code/work-shapes/build-harness-infrastructure.md (the doc the previous session started)
  - possibly docs/backlog.md for HARNESS-GAP-N tracking parallel-mechanism-emergence
---

## What was discovered

Two distinct sessions independently built integration-verification mechanisms
on parallel branches that landed within hours of each other:

1. **Branch `claude/crazy-ellis-a624f7`** (merged to master as commit `c728567`
   2026-05-11 at 02:22 PDT): added a real Check 13 to plan-reviewer.sh —
   integration-verification gate enforcing `**Prove it works:**` /
   `**Wire checks:**` / `**Integration points:**` sub-blocks on
   `Verification: full` tasks.

2. **Branch `claude/lucid-gates-bdd20e`** (this session): wrote a work-shape
   doc whose carve-out table described a hypothetical "Check 13 (integration
   verification)" matching the EXACT same contract before any code existed,
   and asked plan-reviewer.sh to make that check advisory for harness-internal
   plans. The previous (crashed) session that started this work-shape had
   written the same prescriptive description.

The merge surfaced as a textual conflict in plan-reviewer.sh self-test section
(both sides appended new scenarios at the same location, end-of-self-test).
Resolution was purely additive (keep both blocks). The semantic alignment —
my work-shape doc pre-emptively describing a check the other branch was
simultaneously building — was coincidental but striking.

## Why it matters

Two concrete failure-shapes from this discovery, plus one safety property
that worked as intended:

- **Failure A — stale numbered references in prose.** My work-shape doc
  originally said "Check 13" when only Check 12 existed in master at the
  time of writing. I "corrected" it to "Check 4b" (the closest existing
  check), then when the other branch landed Check 13, I had to revert. A
  cross-session convention of using slugs (e.g., `integration-vaporware-defense`)
  rather than numbers in PROSE references would be more robust to parallel
  emergence. Number-references should be reserved for the hook itself.
- **Failure B — duplicated mental-model work.** Both sessions independently
  derived the same contract (the three sub-blocks, the runtime-keyword
  scope). No coordination mechanism revealed the parallel work to either
  session. The build-doctrine catalog principle (Build Doctrine §2) was
  doing its job at the level of describing the contract — both sessions
  read similar substrate and converged — but there is no harness mechanism
  surfacing "another session is currently building something similar; check
  for collision before committing."
- **Safety property that worked** — the two-layer-config recovery: the
  previous crashed session had written the work-shape to `~/.claude/`
  but not synced to canonical. The next session's diff-q check caught the
  asymmetry immediately. The `harness-maintenance.md` verification step
  IS the recovery substrate; this session demonstrated it works.

## Options

A. **Coordinate parallel sessions via a shared "in-flight mechanisms"
   surface** (e.g., `.claude/state/in-flight-mechanisms.md` or a notes
   field in active plans). High coordination cost; requires every session
   to consult before starting and update on finish. Low blast-radius —
   only helps when sessions explicitly check.

B. **Prefer slug references over numbered references in doctrine prose.**
   Number-references stay in hook headers and self-test scenarios (where
   they're load-bearing for grep). Prose references in rules / work-shapes
   / ADRs use slugs like `walking-skeleton-defense` or
   `integration-verification`. Low cost, defense-in-depth against the
   stale-reference failure-shape.

C. **Accept parallel emergence as a feature, not a bug.** Build Doctrine
   §2 (engineering catalog) is supposed to converge similar work to
   similar shapes; that's a strength, not a coordination failure. The
   cost is occasional merge conflicts in additive sections, which `git
   merge` handles correctly with a 2-minute review. Do nothing.

## Recommendation

C as the dominant frame (parallel emergence converging on the same contract
is a SIGNAL the catalog is working), with B as a low-cost improvement on
prose discipline applied opportunistically going forward. A is too heavy
for the observed cost.

## Decision

C + B (auto-applied as a reversible behavioral preference, not a mechanical
change). Reversible because:

1. The C decision is just "do nothing different" — the harness already
   handles merge conflicts in additive sections via `git merge`.
2. The B preference is a prose-authoring discipline applied going forward;
   existing numbered references stay (they're not actively harmful, just
   slightly fragile under parallel emergence).

If parallel-mechanism collisions become frequent enough to warrant A, the
work-shape library can grow a `in-flight-mechanism-coordination` shape
later. Until then, the cost of coordination overhead exceeds the cost of
occasional merge conflicts.

## Implementation log

- The merge conflict was resolved purely additively (keep both Check 13
  scenarios iv1-iv7 from master AND new Check 4b harness-internal hi1-hi3
  scenarios from this branch) — commit `35ba574`.
- Check 13 extended with the same `IS_HARNESS_INTERNAL` carve-out as
  Check 4b in the same merge — commit `35ba574`.
- Work-shape doc updated to reference BOTH Check 4b AND Check 13 with
  identical carve-out semantics.
- No new HARNESS-GAP entry filed: the discovery does not warrant
  mechanization at this volume.
