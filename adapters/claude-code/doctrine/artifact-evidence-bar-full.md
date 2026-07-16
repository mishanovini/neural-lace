# The evidence bar — full

Companion to `doctrine/artifact-evidence-bar.md` (the compact). Operator directive, 2026-07-14:
*"I want everything we build, everything we design, and every agent and builder within that process to
always be world-class, never simply decent. I want to enforce best-in-class principles across everything."*

## Why this exists — the proven miss

Every reviewer in this harness tested **correctness-against-spec**: comprehension-reviewer (does the
model match the diff), harness-reviewer (does the gate have teeth), end-user-advocate (does it run), a
7-lens implementation panel (7 real bugs found). **Not one attacked the SHAPE of the design.** So a
read-time re-derivation shipped completely unquestioned — and when the operator challenged it, the author
*defended it* with an objection that only applied to a strawman of the alternative.

The `architecture-reviewer` was then built to close that hole. On its **first run** it killed the
replacement design too, using a measurement nobody had taken: the "expensive" read-time parse being
eliminated cost **3.5 ms** for every active plan; **one spawn** of its replacement cost **~87 ms**. Five
other adversarial reviewers had already reviewed that same plan and missed it, because none of them
measured.

**The lesson is not "review more."** It is: *an artifact is only as good as the specific failure it was
built to defeat.* Name the failure. Defeat it **structurally**. Then **prove** it.

## How to write each of the seven properties

1. **Named failure modes.** Do not write "reviews code carefully." Write the taxonomy: *anchoring ·
   speculation-instead-of-measurement · amnesia (the system already learned this) · second-system
   enthusiasm · rubber-stamping · bikeshedding · taste-as-defect.* Each must be traceable to something
   that actually went wrong here. A failure mode with no incident behind it is speculation.
2. **A structural protocol.** For each failure mode, a STEP that makes it impossible — not a warning.
   Anchoring is defeated by *"Phase 0: derive your own answer from the code BEFORE reading the
   proposal"*, because a reviewer who has already absorbed the author's frame cannot un-absorb it.
   Speculation is defeated by *"no number, no finding."* Rubber-stamping is defeated by *"you may not
   return SOUND without first writing the steelman of the opposing design."* Ordered phases; mandatory;
   auditable in the output.
3. **Named canon.** The agent must cite the discipline's real frameworks (for architecture: Parnas,
   Brooks, Chesterton, Klein's pre-mortem, Hyrum, connascence, CQRS/materialized-view discipline,
   CAP/PACELC, two-way-door reversibility). Canon converts opinion into authority and gives the agent a
   toolkit instead of a vibe.
4. **System hazard priors.** A generic world-class expert is not world-class *here*. Bake in what this
   codebase already knows: hooks are blind to git operations · process spawns cost ~87ms on Windows
   Git-Bash · ~59 worktrees and multiple machines make any global read-modify-write a routine lost-update
   · unmerged worktree state must never render as done · absence must never render as zero.
5. **An output contract.** Severity = blast-radius × likelihood × irreversibility (not vibes).
   Confidence = PROVEN (cite file:line/number) or HYPOTHESIZED (name the refuter). **The ONE thing** —
   most reviews produce twenty findings of which two matter; say which two. And **what would change my
   verdict** — an unfalsifiable review is not a review, it is an opinion with formatting.
6. **An anti-rubber-stamp mechanism.** The agent's most likely failure is agreeing with the author
   because the author's framing is all it saw. Give it a step it CANNOT skip that forces it to argue the
   other side, and make the verdict conditional on having done so.
7. **A GOLDEN CASE.** A real, historical defect from this project that the agent catches and a naive/
   generic agent misses. State the case, state what the naive reviewer concludes, state what this agent
   must conclude, and state the verdict it must reach. **If a candidate agent does not catch its own
   golden case, it is not that agent.** This is the same bar constitution §10 sets for gates — an
   artifact with no evidence is a claim, not a control.

## Applying the bar beyond agents
- **Plans** — already gated (plan-reviewer). Add: a qualifying plan cannot dispatch a builder without an
  architecture-review verdict. Design → plan → REVIEW → build.
- **Builders** — already gated (the rung-based comprehension articulation: the builder must prove it
  understood the spec, not merely that the tests pass).
- **Reviews** — a review that finds nothing must state what it looked for and what would have changed its
  verdict. Otherwise "LGTM" is indistinguishable from "I did not look."
- **Docs** — a doc that claims a mechanism must have the mechanism. §10 already says this; the doctor is
  the arbiter. **Theater is the cardinal defect: wire it or delete the claim.**

## The retirement condition for this doctrine
If a future artifact class emerges that cannot be evidenced (no golden case is constructible), that is a
signal the artifact is not a control at all — not a signal to relax the bar.
