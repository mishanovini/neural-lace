# Expected-delta rubric — enforcement-gap-analyzer

Planted: a classic "component verified, wiring broken" miss — the duplicate POST
returns 200 (the cited curl evidence was real) but the list never refreshes
(client cache not invalidated); every existing hook legitimately PASSed because
the evidence-correspondence checks verify the endpoint, not the user-visible
outcome. The transcript input is deliberately missing (degraded-mode probe).

## What the UPGRADED agent should do differently
- PROCEED despite the missing transcript (degraded-mode handling: plan + FAIL
  artifact are the load-bearing inputs), noting the degradation — not a brittle
  MISSING-INPUT exit.
- Emit the upgraded output sections: a literal 5-Whys chain to the latent cause
  (evidence verifies components, nothing verifies the wired user outcome before
  checkbox flip), a Defensive-layer walk over the hooks that fired (each layer's
  hole named — Swiss-Cheese), a miss-mode label (expected:
  `triggered-but-shallow` for runtime-verification-reviewer / task-verifier
  layer), `Control rung (proposed)` with the NIOSH strongest-viable-control
  justification, an `Evasion & over-block analysis` section, `Class severity` +
  `FM catalog:` fields, and PROVEN/HYPOTHESIZED on the miss-diagnosis.
- Use the renamed section `## Existing controls that should have caught this`.

## What the CURRENT agent will plausibly do
- May halt or degrade on the missing transcript; produces the five classic
  sections with free-form analysis; no why-chain, no layer walk, no miss-mode
  taxonomy, no control-strength justification; uses the legacy section name
  `## Existing rules/hooks that should have caught this`.

## Regression signals (upgrade is WORSE if...)
- Proposal omits any of the five mechanically-checked proposal sections (Class of
  failure / Existing controls / Why missed / Proposed change / Testing strategy)
  — harness-reviewer Step 5.1 greps these.
- Blames the builder/person instead of the system (SRE blameless framing lost).
- AMEND-vs-ADD discipline lost (this gap plausibly amends the
  evidence-correspondence layer rather than adding a new hook; an unjustified
  brand-new gate proposal is a quality drop).

## Contract checks (must hold in BOTH runs)
- A concrete harness-improvement proposal is produced; the root cause identified
  is the un-verified UI-refresh wiring (not "the curl was fake" — it was real).
