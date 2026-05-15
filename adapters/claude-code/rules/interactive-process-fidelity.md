# Interactive-Process Fidelity — Carry-Forward Context Is Briefing, Not a Substitute for the User's Authority Touchpoints

**Classification:** Pattern (self-applied discipline). No hook detects "you synthesized the user's answer from upstream context instead of asking." The mechanical gates that exist around interactive protocols (notably `prd-validity-gate.sh` + the `prd-validity-reviewer` agent) verify the *shape and substance* of the produced artifact — they do NOT verify that the human-authorization convergence signals the protocol defines were actually collected from the human. This rule is what holds the line where Mechanism structurally cannot, because the thing being protected (the user's actual answer) is not present in any artifact the gate can read.

**Originating incident:** a downstream product's UI design pass (2026-05-15). The session was handed carry-forward context from an upstream Dispatch design conversation and then ran the harness's 6-stage guided PRD intake protocol *autonomously*, treating the briefing as proxy input for Stages A–F. It self-closed an open question (OQ-9, PRD file location) by assigning its own disposition rather than surfacing the resolve/defer/halt choice to the user. The mechanical `prd-validity-reviewer` returned PASS — correctly, because the artifact's substance-shape was fine — and that PASS did NOT catch the defect, because human-authorization convergence is a separate signal the agent does not review. The miss was caught only when the user noticed the protocol had run without any interactivity. The resulting PRD was flagged as "parked and provisional" pending an interactive re-do. Hours of work produced an artifact that had to be invalidated, not because its content was wrong, but because the convergence signal the protocol requires was never collected.

## The rule in one sentence

**When a process is defined to be interactive — its stages exist to collect the user's answers, dispositions, and approvals — the AI MUST surface each stage's actual question to the user and wait for the user's reply, even when carry-forward context from an upstream conversation appears to already contain the answer; synthesizing the user's response from prior context skips the convergence signal the protocol requires and invalidates the artifact.**

## The structure/authority asymmetry

The load-bearing distinction. Not all autonomous progress through an interactive protocol is illegitimate — only the part that stands in for the human.

- **Structure IS legitimately autonomous.** Instantiating the template scaffolding, choosing the artifact's file location per convention, formatting sections, ordering stages, running the mechanical gates, drafting *proposed* content for the user to react to, carrying forward upstream context as a *briefing the user can confirm or correct*. The AI should do all of this without pausing — pausing on structure is narrate-and-wait (prohibited under a keep-going directive per `~/.claude/rules/testing.md`).
- **Authority is NOT autonomous.** The user's answer to a stage's question. The disposition of an open question (resolve / defer / halt). An approval to proceed past a convergence checkpoint. A choice between options with interface impact. These are convergence signals the protocol defines *because the human is the only valid source for them*. Carry-forward context can inform a *proposed* answer; it cannot *be* the answer. The user reacting to a proposal ("yes, that's right" / "no, change X") IS the convergence signal; the AI inferring "the upstream conversation implies they'd say yes" is NOT.

Restated: it is correct to walk into the interactive stage with a drafted, context-informed proposal. It is incorrect to walk *out* of the stage having answered it yourself. The proposal accelerates the user's decision; it does not replace it.

## The canonical un-synthesizable touchpoint

Stage A of the guided PRD intake protocol mandates the N-R-B invisible-knowledge prompt — the prompt that elicits the knowledge living *only in the user's head*: the unstated constraint, the political context, the thing they know but have not written anywhere, the reason the obvious approach is wrong. This is the archetype of a touchpoint that **cannot be synthesized by definition**: if the knowledge were derivable from any upstream artifact or transcript, the prompt would not exist. Carry-forward context, by construction, contains only what was already said — it cannot contain the invisible knowledge the prompt is designed to surface. Any stage that has the *shape* of "ask the user something only they can answer" inherits this property. Treating carry-forward context as a substitute for the N-R-B prompt is the purest form of the failure this rule names: the AI fabricates a convergence signal for a question whose entire purpose is to extract what no prior context holds.

## The three-step protocol

### Step 1 — Recognize you are inside an interactive process

Before proceeding through any multi-stage protocol, ask: **were these stages defined to collect the user's input, or to organize the AI's work?** If a stage's purpose is to elicit an answer, a disposition, or an approval from the human, the process is interactive at that stage and this rule binds. Signals that a process is interactive:

- The protocol names stages by what they *ask the user* (intake, elicitation, disposition, approval, sign-off, convergence).
- A stage produces an open-question list whose entries require resolve/defer/halt decisions.
- The protocol's own documentation says the artifact is invalid without the user's convergence signal.
- The harness already classifies the surface as needing user surfacing (e.g., `planning.md` "Plan-Time Decisions With Interface Impact", `discovery-protocol.md` irreversible-decision pause, the guided PRD intake protocol's Stages A–F).

If the process is purely organizational (the stages structure the AI's build work and have no human-answer slot), this rule does not bind — drive to completion per the keep-going directive.

### Step 2 — Surface the stage's actual question; wait

For each interactive stage:

1. **Draft the proposal first.** Use carry-forward context to compose the best proposed answer you can. This is legitimate and valuable — it makes the user's decision fast.
2. **Surface the actual question, plainly, with the proposal attached.** State what the stage asks, present the proposal, name the alternatives and tradeoffs, mark your recommendation. Make explicit that this is a touchpoint, not a notification: "this stage needs your answer before I proceed."
3. **Wait for the user's reply.** Do not proceed past the stage on the strength of the proposal alone. The user's reply — even a one-word "yes" — is the convergence signal. Its absence means the stage did not converge.
4. **Surfacing medium is Dispatch-conditional** (per `~/.claude/CLAUDE.md` Autonomy section detection priority): under Dispatch, plain-text prose only — NO `AskUserQuestion`; standalone clients may use the MC widget; unknown → default to plain text.

Open-question dispositions (resolve / defer / halt) are authority, never structure. The AI proposes a disposition; the user chooses it. Self-closing an open question — assigning your own disposition because upstream context "implies" it — is the exact defect of the originating incident.

### Step 3 — If you cannot wait, halt and say so; do not synthesize

A keep-going / autonomous directive authorizes you to not narrate-and-wait on *structure*. It does NOT convert *authority* touchpoints into AI-fillable slots. If an interactive stage's question is genuinely blocking and the user is not available to answer it:

- The correct action is to **halt the protocol at that stage** and surface the blocker concretely ("Stage C needs your disposition on OQ-9; I cannot synthesize this — the protocol's convergence signal requires your answer"), then proceed only with structure that does not depend on the unanswered authority.
- The incorrect action is to **synthesize the answer from carry-forward context and proceed**, producing an artifact that looks complete but carries no convergence signal. That artifact is provisional-at-best and invalidated-at-worst, regardless of how good its content is.

Halting one interactive stage does not mean stopping all work — continue any structural work that does not depend on the unanswered authority, and batch the authority questions for the user. But the protocol's artifact is not "done" until its convergence signals are real.

## What this rule is NOT

- **Not a ban on carry-forward context.** Carry-forward briefing is essential — it is how a session starts informed instead of cold. The rule governs what the briefing may be *used for*: informing a proposal (yes) vs. standing in for the user's answer (no).
- **Not narrate-and-wait re-introduced.** The keep-going directive and `narrate-and-wait-gate.sh` prohibit pausing on structure ("shall I proceed with phase 2?"). This rule prohibits the opposite failure — racing through *authority* touchpoints. They are complementary, not contradictory: be maximally autonomous on structure, strictly non-autonomous on authority. The boundary between them is the asymmetry section above.
- **Not satisfied by a passing mechanical gate.** `prd-validity-reviewer` PASS certifies the artifact's substance-shape (seven sections present, scenarios concrete, metrics measurable). It is silent on whether the user actually answered Stages A–F. A protocol artifact can pass every mechanical gate and still be invalid for lack of a convergence signal. Gate PASS is necessary, not sufficient, for an interactive-protocol artifact.
- **Not an exemption for "the answer is obvious from context."** "The upstream conversation clearly implies they'd want X" is the precise rationalization this rule exists to stop. If the answer is obvious, surfacing it as a proposal costs the user one word ("yes") and produces a real convergence signal; synthesizing it saves one word and produces an invalid artifact. The trade is never worth it.

## Worked example — the originating incident

**What happened.** Session handed carry-forward context from an upstream Dispatch design conversation about a downstream product's UI feature. Task: produce a PRD via the 6-stage guided intake protocol. The session ran Stages A–F autonomously, reading the carry-forward briefing as the user's input for each stage. At the open-question stage it encountered OQ-9 (where the PRD file should live) and *self-closed* it — assigned a disposition rather than surfacing resolve/defer/halt to the user. `prd-validity-reviewer` returned PASS on the finished artifact. Commit landed on a feature branch.

**Why the gate didn't catch it.** `prd-validity-reviewer` reviews substance-shape: are the seven sections present and substantive, are scenarios concrete, are metrics measurable. All true — the artifact's *content* was fine. The defect was not in the content; it was in the *provenance*: every Stage A–F "answer" was AI-synthesized from briefing, and OQ-9 was AI-dispositioned. The gate has no view onto "was a human the source of these convergence signals." That is structurally outside what a substance-shape reviewer can certify.

**What should have happened.** Stage A: draft the invisible-knowledge prompt's expected content from the briefing as a *proposal*, then surface it — "based on the upstream conversation I believe the unstated constraint is X; is that right, and what am I missing that wasn't said upstream?" — and wait. The "what am I missing" half is the un-synthesizable core; the briefing by construction cannot contain it. Stages B–F: same shape — propose from context, surface, wait. OQ-9: present resolve/defer/halt with a recommendation; let the user choose. The artifact would have taken slightly longer and been *valid* instead of provisional.

**The class lesson.** Carry-forward context degrades silently into a proxy for the user under autonomy pressure. The pressure to "keep going" is real and usually correct — but it applies to structure, not authority. The cost of one surfaced proposal-plus-wait is small (often a one-word reply); the cost of an invalidated multi-hour artifact is large, and the invalidation is invisible until the user notices the protocol never asked them anything.

## Cross-references

- `~/.claude/rules/gate-respect.md` — sibling rule. Gate-respect is "diagnose before bypassing a *blocking* gate"; this rule is "don't synthesize the user's answer in an *interactive* protocol." Composes: a session can satisfy every gate (gate-respect) and still produce an invalid interactive-protocol artifact (this rule) if it fabricated the convergence signals.
- `~/.claude/rules/planning.md` "Plan-Time Decisions With Interface Impact — Surface To User" — the same surface-then-wait discipline applied to plan-time either/or choices. This rule generalizes it to every interactive-protocol stage.
- `~/.claude/rules/discovery-protocol.md` — the reversible-auto-apply vs. irreversible-pause split is the same asymmetry: reversible/structural decisions auto-apply; irreversible/authority decisions pause and wait. An interactive-protocol authority touchpoint is always pause-and-wait.
- `~/.claude/rules/testing.md` "Keep Going When Keep-Going Is Authorized" + `narrate-and-wait-gate.sh` — the *opposite* failure (pausing on structure). Read together with this rule, they define the full policy: autonomous on structure, non-autonomous on authority.
- `~/.claude/rules/prd-validity.md` + `~/.claude/agents/prd-validity-reviewer.md` — the gate explicitly referenced above as substance-shape-only. PASS there does not certify convergence.
- `~/.claude/CLAUDE.md` Autonomy section — the Dispatch-conditional surfacing-medium detection priority this rule's Step 2.4 defers to.
- `docs/failure-modes.md` — class FM-N "AI-synthesized convergence signal in an interactive protocol" if/when this becomes a catalogued failure pattern.
- `docs/backlog.md` HARNESS-GAP for the `prd-validity-reviewer` provenance-detection extension (filed alongside this rule).

## Enforcement

| Layer | What it enforces | File |
|---|---|---|
| Rule (this doc) | Surface-then-wait on authority touchpoints; structure/authority asymmetry; halt-don't-synthesize | `adapters/claude-code/rules/interactive-process-fidelity.md` |
| Sibling gate (Mechanism, partial) | `prd-validity-reviewer` certifies substance-shape only — explicitly NOT convergence provenance | `~/.claude/agents/prd-validity-reviewer.md` |
| Proposed gap (Mechanism, not yet built) | `prd-validity-reviewer` extension to flag artifacts whose only authoring provenance is the AI with no user-authorization marker | `docs/backlog.md` HARNESS-GAP entry |
| User authority | The user retains interrupt authority when they notice an interactive protocol ran without surfacing its questions | (Pattern) |

The rule is documentation-enforced. The mechanical gate that exists around the canonical interactive protocol (PRD intake) is structurally blind to the convergence-provenance signal this rule protects — which is why the rule is Pattern-class and why the proposed gap-detection extension is filed but explicitly scoped as a separate, not-yet-built mechanism.

## Scope

This rule applies in every project whose Claude Code installation has this rule file present at `~/.claude/rules/interactive-process-fidelity.md`. It is loaded contextually by the harness; no opt-in or hook wiring is required. The rule binds whenever a session executes any multi-stage process whose stages exist to collect the user's answers, dispositions, or approvals — the guided PRD intake protocol (Stages A–F), plan-time interface-impact decisions, discovery-protocol irreversible dispositions, and any future interactive protocol the harness adds. It does not bind purely organizational stage structures whose only purpose is to sequence the AI's own build work.
