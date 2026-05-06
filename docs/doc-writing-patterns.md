# Documentation Writing Patterns

**Classification:** Pattern (documented convention; not hook-enforced).

**Audience:** anyone writing or revising user-facing documentation in this repo. The 10 principles below codify what "good developer-perspective documentation" means here, with concrete examples drawn from the repo itself.

**Last verified:** 2026-05-06.

## Why this exists

The harness has accumulated documentation across eight months of Generation 4-6 evolution + the Build Doctrine integration arc. Patches accrue technical debt: each Tranche/Generation adds a callout, sections get appended rather than restructured, and the result reads as stratigraphy — layers of additions a reader has to mentally peel back. A fresh reader hitting the GitHub repo cold can't grasp the architectural shape from a doc that grew by accretion.

This file codifies the patterns to follow when writing or restructuring any user-facing documentation. The goal is not stylistic uniformity; the goal is a doc tree where each layer answers the right question for its audience and where updates compose rather than accumulate.

If a future doc-writing pass disagrees with one of these principles, the right move is to amend this file with rationale and propagate. The principles are not sacred; the discipline of updating them when reality contradicts them is.

## The 10 principles

### 1. Audience layering / progressive disclosure

Each doc serves one tier of the audience pyramid. Don't try to serve everyone in one doc.

**Tier 1: Skim-readers** (30 seconds). README. Answers: who/what/why. Architecture as shape, not detail. Strong links down.

**Tier 2: First-time installers** (5 minutes). Getting-started doc, harness-guide. Answers: how do I install this and run it once? Concrete commands, no theory.

**Tier 3: Fresh adopters** (15 minutes). Architecture-overview. Answers: how does the system work end-to-end? Walk-throughs, mental models, the team-role analogy.

**Tier 4: Maintainers / deep-divers** (read-and-reference). Catalog docs — `harness-architecture.md`, `best-practices.md`, `agent-incentive-map.md`, decision records. Answers: exhaustive specs, per-component detail, exact behavior.

Each tier links *down* to the next; never repeats *up*. README links to architecture-overview; architecture-overview links to the catalog docs. The reverse direction is rare ("the catalog doc shouldn't need to summarize the README").

**Anti-example:** an early version of `docs/harness-strategy.md` covered Layer Model + Strategic Goals + Repo Structure + Continuous Monitoring all at once. Tier-3-and-4 content mixed in one file. A fresh adopter looking for "how does this work end-to-end" had to skip past dedicated harness-repo design.

### 2. Single source of truth per concept

Each architectural concept is owned by exactly one doc. Other docs that reference it link out; they don't re-explain.

**Good:** the L0/L1/L2/L3 layer model is owned by `docs/harness-strategy.md`. README mentions it as a one-line shape with a link. `docs/architecture-overview.md` cross-walks it against other layer systems but doesn't re-define it.

**Bad pattern to avoid:** "Generation 6" has shown up in callouts in the README, in `harness-architecture.md`, in `best-practices.md`, and in `vaporware-prevention.md` as ad-hoc summaries. None of them is the source of truth; if Generation 7 ships, all four need updating in lockstep. The fix is to designate one doc as canonical (likely `harness-architecture.md`'s "Generation Evolution" section) and have the others link to it.

If you find yourself re-explaining a concept, ask: which doc *owns* this? Move the explanation there; replace the duplicate with a link.

### 3. Examples before abstractions

Concrete first. Pattern after.

**Good:** when explaining the orchestrator pattern, walk one real plan through dispatch → cherry-pick → verify with actual file paths and SHAs. Then state the pattern abstractly.

**Bad:** "The orchestrator dispatches build work to sub-agent builders running in worktree-isolated git branches, with verification serialized after parallel build completion." This is correct but the reader doesn't know why or how until they see one example.

Specifically: open every section with the example, close with the principle. The example carries the reader; the principle organizes the memory afterward.

**Anti-example:** an early draft of `docs/best-practices.md` opened the orchestrator pattern with the abstract description and lost most readers. The current version opens with a concrete dispatch.

### 4. Update-on-ship

Doc updates land in the same commit as the feature work. Not as afterthoughts. Not as "I'll catch up the docs later."

This is enforced indirectly today via `docs-freshness-gate.sh` (Rule 8 — when a new rule, hook, or agent file lands, an entry must be added to `docs/harness-architecture.md`'s catalog table in the same commit). The principle is broader than the gate's scope: any user-facing doc that mentions the changed thing should be updated *now*, not later.

**Good:** when GAP-08 spawn_task report-back shipped, the rule + hook + settings.json + vaporware-prevention.md enforcement-map row + harness-architecture.md table entry all landed in the plan's closing commits. Future sessions inherit a consistent state.

**Bad pattern:** "I'll add it to the README in a follow-up." Follow-ups slip; readers see stale architecture for weeks.

If a doc update is genuinely separable (a doc tree refresh that doesn't tie to a specific shipping feature), open a doc-only plan (like this one). But default: doc update in the same commit.

### 5. Honest staleness markers

Every major doc has a `Last verified: YYYY-MM-DD` line near the top. The line is a contract: when you read this doc and confirm it matches reality, update the date. When you read this doc and find it wrong, fix the doc and update the date.

**Good:** this file (top of page). The line gives readers signal about whether the doc is fresh and gives writers a forcing function to either verify or correct.

**Bad pattern:** `harness-architecture.md`'s "Last updated: 2026-05-04" sticky note has been wrong for weeks (the file was actually updated 2026-05-06). When the line is wrong, it teaches readers to ignore it; the protection collapses.

Companion: a periodic doc audit (e.g., `/harness-review` skill) that flags stale dates. Discipline alone is insufficient over time.

### 6. Test the docs cold

Periodically have a fresh reader (or a fresh subagent) walk through getting-started + architecture-overview as if they had no prior context. Note where they get confused; fix those points.

**Good:** a documented procedure runs every few months — give the README + getting-started + architecture-overview to a research subagent with the prompt "read these as if you've never seen this repo. Where do you get stuck? What's the first action you'd take after reading?" Surfaces gaps the writers can't see.

**When to run:** after any restructure, before any major release, periodically (quarterly is reasonable for a repo this size).

The cold-test catches what the writer's eye glides over. The writer knows the unstated context; the cold reader doesn't.

### 7. Index → detail navigation

Every doc opens with a "you are here" pointer: where does this doc fit in the doc tree, and what's the nearest neighbor for a different question?

**Good:** the top of `docs/best-practices.md` could open with: "This catalogs the best practices Neural Lace encodes — for the narrative overview see `architecture-overview.md`; for the operational rules see `~/.claude/rules/`; for the per-mechanism inventory see `harness-architecture.md`."

The pointer tells a reader: you got here via search or a link; if your question doesn't fit, here's where to go instead. Saves the reader from reading the whole doc to discover it's not what they need.

**Bad pattern:** a doc that opens with "## What this is" — a paragraph defining the doc — without telling the reader what the doc *isn't* and where the alternatives live.

### 8. Honest about scope

Each doc says explicitly what it covers AND what it doesn't, with pointers to where the rest lives.

**Good:** `docs/build-doctrine-roadmap.md` opens with a "How to use this doc" section listing what the doc IS for and what it ISN'T. Readers don't have to infer.

**Bad pattern:** a doc titled "Architecture" that's actually about hooks, leaving readers wondering where rules / agents / templates live. The title implies coverage; the content delivers a slice.

Be ruthless about scope statements. If you can't say in one sentence what's NOT in this doc, the doc is too broad.

### 9. Organize by reader's question, not writer's structure

The reader is searching for an answer to a specific question. Organize the doc by the questions readers ask, not by the structure of the underlying system.

**Reader-question-organized (good):** "How do I add a new project?" → "How do new agents fit in?" → "How do I extend a rule?"

**Writer-structure-organized (bad):** "Architecture overview" → "Adapters" → "Project-specific config" → "Adding new projects"

The bad pattern requires the reader to first understand the architecture, then find the right sub-section, then read it. The good pattern lets the reader land directly on their question.

A useful trick: imagine three real users of the doc and their first question. Make sure those three questions are H2 headings.

### 10. Visuals when load-bearing, not for decoration

Diagrams, tables, and ASCII art appear when they carry information prose can't. They don't appear because "every doc should have a diagram."

**Load-bearing visuals (good):**
- A table mapping each agent to a tech-team role (table makes the mapping scannable; prose would obscure it).
- A flow diagram showing how a feature ships through plan → build → verify → close (sequence is the load-bearing insight; prose would lose the order).
- An ASCII tree showing the directory layout (visual hierarchy mirrors the filesystem; prose would require the reader to mentally reconstruct).

**Decorative visuals (bad):**
- A box-and-arrow diagram of "the harness" with no information density beyond what the prose already says.
- A table listing the 19 agents alphabetically with one-line descriptions when the same content reads better as prose.

Test: if the visual were removed and replaced with prose, does the doc lose information? If yes, the visual is load-bearing. If no, it's decoration; cut it.

## How to apply when writing a doc

Concrete checklist for any new doc or major rewrite:

1. **Identify the audience tier.** Tier 1, 2, 3, or 4? If two tiers — split.
2. **Name the question the doc answers.** One sentence. If you can't, don't write the doc yet.
3. **Find the source of truth.** Does the concept already have a home? Link there; don't re-explain.
4. **Open with the example, close with the principle.** Concrete → abstract.
5. **Add the staleness marker.** `Last verified: YYYY-MM-DD` at the top.
6. **Add the "you are here" pointer.** Where does this fit; where do alternative questions live.
7. **State scope honestly.** What's covered AND what isn't.
8. **Organize by reader question.** H2 headings = questions readers ask.
9. **Add visuals only when load-bearing.** Test by imagining the visual removed.
10. **Cold-test before shipping.** Read the doc as if you've never seen the repo. Or have a subagent do it.

## How to apply when reviewing a doc

If you're reading an existing doc and it feels off, run this checklist:

- Does the staleness marker match reality? If not, either verify or fix.
- Does the "you are here" pointer exist? If not, the doc is hard to land on.
- Is the doc trying to serve multiple audience tiers? If so, propose a split.
- Are abstractions stated before examples? If so, propose a flip.
- Does the doc duplicate content owned by another doc? If so, propose a link replacement.
- Are visuals decorative or load-bearing? If decorative, propose cutting.

Doc-debt accumulates silently. Surfacing it at review time is cheap; surfacing it years later via a confused reader is expensive.

## When to revisit this file

This patterns doc gets revised when:

- A doc-writing convention proves wrong in practice (a principle here turns out to harm reader experience).
- A new doc tier emerges (e.g., a "for harness-tool maintainers" tier distinct from "for harness-adopters").
- A specific anti-pattern shows up enough times to warrant codification.
- The cold-test reveals systematic confusion that none of the principles cover.

Amend the file with the new principle, cross-reference any anti-example that motivated the change, and update the `Last verified` date.

## Cross-references

- `docs/best-practices.md` — the broader catalog of harness best practices (this file is the doc-writing slice of that catalog)
- `docs/agent-incentive-map.md` — adjacent shape (per-agent failure-mode analysis); same "codify the substrate so any agent can apply it" philosophy
- `docs/harness-architecture.md` — the catalog of mechanisms (Tier 4); this file is the substrate FOR writing such catalogs
- `~/.claude/rules/diagnosis.md` — "After Every Failure: Encode the Fix"; the same discipline applied to mechanism-design rather than doc-writing

## Enforcement

Pattern only — not hook-enforced. The discipline lives in the writer's head and the reviewer's eye.

If discipline proves insufficient over time (signal: cold-tests reveal repeated systematic confusion that the principles already cover), graduate one or more principles to mechanism enforcement:

- A `docs-staleness-detector.sh` SessionStart hook flagging stale `Last verified` dates.
- An extended `docs-freshness-gate.sh` requiring "you are here" pointers in new docs.
- A `/cold-test-docs` skill that runs the cold-test on demand against the doc tree.

These are speculative; build them when there's evidence the substrate alone isn't holding. Per Tranche F retirement spirit, mechanism additions need positive evidence of need.
