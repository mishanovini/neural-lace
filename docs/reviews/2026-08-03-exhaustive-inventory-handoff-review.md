# Review: the EXHAUSTIVE issue inventory handoff (2026-08-03)

**Reviewed:** `docs/handoffs/2026-08-03-EXHAUSTIVE-issue-inventory.md` together with its three
companions (`2026-08-03-MASTER-HANDOFF-process-integrity.md` · `docs/reviews/2026-08-03-stage0-stage1-harness-review.md`
· `docs/reviews/2026-08-03-harness-execution-redesign-REAL-architecture-review.md`) and
`docs/designs/end-to-end-process.md`.
**Reviewer:** Fable (main session 4a470c8c, 2026-08-02/03) — pre-design assessment, per the
handoff's own stated purpose ("the complete, un-summarized input for a fresh session to produce
an updated DESIGN and PLAN").

## Verdict: FIT FOR PURPOSE as design input — with five items the design must resolve, one
formatting defect, and one item the inventory itself asks to be re-derived (P-42).

### What the handoff does right (and the design must preserve)

- Genuinely exhaustive and honestly labeled: 46 problems, 23 operator directives, 36 solution
  items with SHIPPED/NOT-BUILT status, 12 open review findings, 9 operator questions — every one
  tagged [OP]/[AI] and PROVEN/HYPOTHESIZED. The PROVEN tags spot-check clean against the two
  full review files.
- Self-correcting: P-42 records that the architecture review's headline justification (a
  Law-1/push conflict) is WRONG, operator-identified, and flags the meta-failure (agent relayed
  a plausible reviewer claim unverified — same class as P-30). An inventory that indicts its own
  reviews is doing its job.
- D-15 (THE GATED PIPELINE) is properly expanded to a binding spine with a real acceptance bar:
  *"demonstrated by an attempted skip being mechanically blocked, not by documentation saying it
  should be."* This is the correct, testable formulation.
- Clear hard stops carried from the master handoff: no `NL-Maintenance` registration until F1/F2
  fixed; no WSL; no new hardware; the current calm is a truce, not a fix.

### Items the design MUST resolve (found by cross-reading the four documents)

1. **D-15.2 vs the master handoff §5 pull in opposite directions.** D-15.2 demands a dedicated,
   world-class-at-ONE-job reviewer per transition; master handoff §5 recommends extending the two
   existing reviewers and adding only `design-author`. S-19a acknowledges the tension ("extend
   where an agent already owns the transition, create only where none does") but no document
   resolves it. The design must decide per-transition, with rationale, and reconcile with D-07.
2. **D-07 (anti-bloat: modify/replace/delete, never add) vs the gated pipeline's additive
   nature.** A pipeline of reviewers + chaining artifacts is net-new inventory. The design must
   name what each new mechanism DISPLACES (Check-17 single-link semantics, derived review
   records, ad-hoc review dispatch prose, NEEDS-YOU duplication of standing directives) or it
   violates the operator's own scorecard rule the moment it ships.
3. **P-42's re-derivation was never actually written.** The inventory says the directives
   register "may still be right but its justification must be re-derived." The re-derivation
   exists implicitly (P-32 append-invisibility, P-33 seven stores with no identity/supersession,
   P-28/P-38 mechanism-never-armed recurrences are all carriage failures independent of the
   Law-1 story) but no document states it. The design must carry the register's justification
   on those grounds, explicitly not on the refuted Law-1-conflict premise.
4. **Q-09 is posed as an operator question but is decidable from principles** (constitution §3:
   decide what you can defend). The review-set-per-change-class table should be a design
   decision with a trail, not an open ask that rots in the queue (P-35 is the inventory's own
   evidence of what happens to asks).
5. **The reviews' own sequencing findings must bind the plan shape:** drain + 71-red doctor
   triage BEFORE Stage 2 (arch F2); F1/F2/F6 before any activation (harness review); manifest
   integration commit immediately (F9). A design that re-sequences these has to defend it.

### Defects in the handoff document itself

- **Formatting defect, Part 7:** Q-07's text is truncated mid-sentence at line 438
  ("allowlist + two-strike") and its tail ("guard proposed.)") is orphaned at line 449, AFTER
  Q-08/Q-09 — the operator-questions section is corrupted exactly where an operator would read
  it. Noted here rather than silently edited (the handoff is a session record).
- Part 6 compresses F1–F12 to one line each; acceptable as an index since the full review file
  carries them, but a cold reader of the inventory alone would under-weight F2 (arbiter
  corruption) badly.

### Binding constraints extracted for the design (the short list)

Hard stops: F1/F2 before any activation · no WSL · no new hardware · drain before Stage 2.
Spine: D-15 (all four clauses + acceptance bar). Standing: D-07 anti-bloat scorecard ·
D-13/D-14 Fable-authored exhaustive designs and same-rigor plans · D-03 gates never block
silently · D-12 nothing discarded for age · D-17/D-18/D-19 autonomy, parallelization, 24/7.
Open Criticals to fix first: F1, F2, F6 (+ F9 integration commit). P-42: register justified on
P-32/P-33 grounds only.
