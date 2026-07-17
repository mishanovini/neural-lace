# The evidence bar — no artifact ships without proof it beats naive

> Enforcement: plan-reviewer.sh Check 17 (blocking, verified) + agent-design-gate.sh +
> agent-commit-gate.sh (both observe-first; flip criteria in manifest, review 2026-07-17).
> Full: doctrine/artifact-evidence-bar-full.md
> Applies: every gate, agent, design, and review this harness produces.

**The law (constitution §10, generalized):** *No artifact ships without evidence it catches what a
naive version would miss.* "Decent" is a failure state. If you cannot name what your artifact catches
that a generic one does not, you have not built anything.

| Artifact | Evidence required before it lands |
|---|---|
| **Gate** | named golden scenario · expected false-positive rate · retirement condition |
| **Agent** | a **GOLDEN CASE** — a real, historical defect it catches that a generic agent misses |
| **Design** | an **architecture review** (`architecture-reviewer`) BEFORE any build dispatch |
| **Review** | what it looked for, and **what would have changed its verdict** |

## The seven properties of a world-class agent (all seven, or it does not land)
1. **Named failure modes** — how this job fails, each traced to a REAL past failure here.
2. **A structural protocol that defeats each** — an ordered phase, not an exhortation. *"Don't anchor"
   is worthless; "Phase 0: derive your own answer from the code BEFORE reading the proposal" is a
   mechanism.* Exhortation = memory-rung. Protocol = pattern-rung. A gate = mechanism-rung.
3. **Named canon** — the discipline's actual frameworks, cited and applied by name. An agent that
   cannot name its methods is guessing.
4. **System hazard priors** — it arrives already knowing THIS codebase's landmines. A generic expert
   is not world-class here; a specific one is.
5. **An output contract** — calibrated severity (blast-radius × likelihood × irreversibility), PROVEN
   vs HYPOTHESIZED (with the refuter), the ONE thing that matters most, and **what would change its
   verdict** (an unfalsifiable review is not a review).
6. **An anti-rubber-stamp mechanism** — a step it MUST execute that makes agreeing-by-default
   impossible (e.g. a mandatory steelman of the opposing position).
7. **A GOLDEN CASE.** **No golden case, no agent** — the same bar §10 sets for gates, for the same
   reason: an artifact with no evidence is a claim, not a control.

## Nothing gets built before it is designed, planned, and reviewed
Enforced, not remembered: **design → plan → REVIEW → build.** A plan that introduces or changes a data
architecture, a source-of-truth boundary, a read/write path, a cache/derived store, a cross-component
data flow, or a consistency/staleness contract MUST carry an `architecture-reviewer` verdict before any
builder is dispatched. **The gate blocks the dispatch, not the conscience.**

Why this exists, the proven miss, and how to write each of the seven: artifact-evidence-bar-full.md
