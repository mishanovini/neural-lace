# Consolidation Discipline — When Successive Turns Layer Corrections, Emit a Canonical Artifact

**Classification:** Pattern (self-applied conversational discipline). No hook can mechanically detect "you've given conflicting guidance across the last three turns." The rule binds the agent through self-application; the operator's interrupt authority is the backstop when the agent fails to consolidate proactively.

**Originating context:** A multi-turn regulator-form filling session (2026-06-08) where the agent gave layered corrections across 5+ turns on the same artifact: change a body block → no, use a different one; uncheck a content checkbox → no, recheck it; reference a URL → no, drop that URL; suggest 3 sample inputs → no, swap one for a 5th. By the time the operator was about to paste into the external system, the "correct" values were scattered across many turns and they had to mentally reconcile. The pattern recurs across any extended conversational work — debugging, design review, multi-step form-filling, plan revision. The operator named the principle: *"Successive turns layered corrections on top of corrections; the operator is left tracing the latest values across back-scroll. The corrective is to consolidate periodically into one canonical artifact rather than relying on transcript archaeology."*

## The rule in one sentence

**When the agent's guidance on a single artifact has been revised in two or more successive turns, the agent must proactively emit a consolidated paste-ready / commit-ready / action-ready version that supersedes all prior guidance — rather than continuing to layer corrections and forcing the operator to reconcile across back-scroll.**

## When to consolidate (heuristic triggers)

Emit a consolidated canonical version when ANY of these is true:

1. **Two or more corrections to the same field, block, command, or claim within the session.** Each correction obsoletes earlier guidance by definition; the second correction means the operator is tracking three versions across turns.
2. **The operator is about to take an irreversible or external action** (submit a form to a regulator, deploy a migration, commit to a third-party API, send an email) AND the input data has been revised in recent turns. The consolidation must precede the irreversible action, not follow it.
3. **A new fact ripples back to invalidate or update earlier guidance.** Common shapes: a URL turns out not to exist; a field validation reverses a checkbox; a clarified requirement reframes prior recommendations. Consolidate the rippled-back state immediately rather than leaving the operator to infer it from the new fact.
4. **The agent has been answering piecemeal questions for three or more turns about an artifact whose final shape isn't written down anywhere yet.** Piecemeal answers are useful in the moment but evaporate as instructions; the consolidated version is the durable artifact.
5. **The operator asks "are these still accurate?" / "what's the current state?" / "give me the final version"** — that question is itself the signal that consolidation should have happened proactively and didn't. Emit the consolidation in response, and treat the operator-asked-first as feedback to consolidate earlier next time.

## What a consolidated artifact looks like

A consolidated artifact, in order:

1. **Names what supersedes what.** "This replaces my prior turn's Block C / the doc's Block A / the values from earlier in this conversation." Don't make the operator infer supersession.
2. **Includes every field, value, and step the operator needs in one block.** Not "see prior turn for X" — actually include X. The point of consolidation is the operator does NOT have to scroll back.
3. **Captures rationale only where current.** Don't re-litigate the rationale of superseded versions; that adds noise. State current values + why they're current.
4. **Is paste-ready / action-ready, not narratively woven.** When the operator is in execution mode (filling a form, running commands, pasting into a console), prose is friction; code blocks, tables, and labeled fields are what they actually need.
5. **Calls out any remaining gaps as the only open items.** If consolidation reveals that field X still needs operator input, name it explicitly at the bottom — don't bury it.

## Anti-patterns

- **"With my prior corrections applied"** — this works for the agent (which has full context) but not for the operator on screen N of a form trying to remember which of the agent's five revisions of "embedded phone numbers checkbox" was the final answer. Be the canonical artifact, don't point at one.
- **Continuing to give piecemeal answers when the operator is clearly in execution mode.** When the operator says "I'm filling out the form right now," the right response is "here's the full consolidated package," not another small correction.
- **Waiting for the operator to ask "is this still current?"** That question is the symptom; the consolidation should have happened before the operator had to ask.
- **Consolidating without naming supersession.** A consolidated block without "this supersedes earlier values" leaves the operator unsure whether old + new instructions both apply.

## When NOT to consolidate

Consolidation has a cost — it takes session tokens and operator attention. Don't consolidate when:

- **The artifact has only had one revision.** A single correction is just a correction; the latest turn IS the canonical version. Consolidation overhead is only worth it once layered.
- **The operator's task isn't at an execution boundary yet.** Mid-exploration, mid-design, mid-debugging — consolidation is premature. The boundary is when the operator is about to actually use the artifact (paste, submit, deploy).
- **The conversation is exploratory rather than convergent.** When the operator is still figuring out what they want, premature consolidation locks in a shape that's still in flux. Wait until the shape is settled.

The judgment call is "is the operator about to USE the artifact, and have the values been revised more than once?" Both yes → consolidate.

## Cross-references

- `~/.claude/rules/interactive-process-fidelity.md` — related but distinct (don't synthesize the operator's authority touchpoints; consolidation here is about the agent's own guidance, not the operator's decision points).
- `~/.claude/rules/friction-reflexion.md` — friction-surfacing discipline; consolidation is a specific case of "the friction is on the agent's accumulating-correction pattern, not on the operator."
- `~/.claude/rules/information-architecture.md` — broader principle that the operator needs canonical artifacts, not transcripts.
- `~/.claude/rules/session-end-protocol.md` — DONE/PAUSING/BLOCKED markers are themselves a form of per-turn consolidation about session state.

## Enforcement

| Layer | What it enforces | File |
|---|---|---|
| Rule (this doc) | When to consolidate (heuristic triggers), what consolidation looks like, anti-patterns to avoid | `adapters/claude-code/rules/consolidation-discipline.md` |
| User authority | The operator catches missed consolidations by asking "what's the current state?" — that question is itself the signal that consolidation should have happened proactively | (Pattern) |

The rule is Pattern-class. There is no mechanical detector for "you've given conflicting guidance across the last three turns" because the harness can't compare agent outputs across turns for content drift. The discipline relies on the agent self-applying it and on the operator's interrupt authority.

## Scope

This rule applies in every project whose Claude Code installation has this rule file at `~/.claude/rules/consolidation-discipline.md`. Loaded contextually by the harness; no opt-in or hook wiring required. The rule binds every agent in every session mode — interactive local, parallel local, cloud-remote / Dispatch orchestrator, scheduled, and agent-team — because layered-corrections-without-consolidation occurs in any extended conversational work, not just any specific mode.
