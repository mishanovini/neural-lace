# Expected-delta rubric — documentation-auditor (NEEDS-MISHA tier: net-new agent)

NOTE: there is no current agent file — the A/B baseline is the nearest existing
capability (the single-doc reviewer skill, which grades one doc's writing at a
time). The comparison is "what does a CORPUS auditor catch that per-doc grading
structurally cannot."

Planted corpus-level defects: (a) type-mixing — getting-started.md is a tutorial
that dumps reference/internals (batch sizes, token-bucket rates, API headers) on
a non-technical office-manager audience; (b) a redundant pair — campaigns.md and
sending-messages.md document the SAME task under different vocabulary; (c)
terminology drift — campaign/blast, recipients/client list/customers across
docs; (d) leaked internal codename — "Project Hummingbird" in contact-import.md;
(e) no index/navigation, contact-import reachable only via a Labs flag mention
(orphan/findability); (f) one deliberately GOOD doc (troubleshooting-texts.md)
as the false-positive control.

## What the NEW agent should do (no baseline to differ from)
- Inventory + Diataxis type classification per doc; flag (a) as type-mixing with
  a split recommendation (tutorial vs reference; the reference content likely
  CULLED for this audience, not moved).
- Catch (b) as a merge candidate and (c) with a terminology map naming the
  canonical term per concept (audience.md says "customers", "texts").
- Flag (d) against the audience's "allergic to internal codenames".
- IA findings: missing index/entry point; orphaned import doc.
- Proposed doc map as the centerpiece deliverable (merges/splits/culls/adds,
  each tagged by Diataxis type); six-field class-aware findings;
  PROVEN/HYPOTHESIZED discipline on any accuracy claims (it cannot verify app
  behavior — accuracy findings must be HYPOTHESIZED with refutation criteria).
- troubleshooting-texts.md is praised or left mostly alone (FP control).

## Comparison-run note for the orchestrator
For the "current" arm, run the per-doc review capability over the same 5 files
and observe what it CANNOT see: the redundancy, terminology drift, orphaning,
and missing index are invisible to per-doc grading. That delta is the case for
(or against) adding the agent to the roster.

## Regression-equivalent signals (do not adopt if...)
- It asserts accuracy facts about the product without flagging them unverifiable.
- Micro-typo/style bikeshedding dominates over the planted structural findings.
- It invents a persona or ignores audience.md.
- The proposed doc map is a flat complaint list rather than a target structure.

## Decision note for Misha
This fixture informs the inventory decision (new roster agent + Write/browser
tool grant + doc coupling vs folding corpus-audit duties into existing skills).
