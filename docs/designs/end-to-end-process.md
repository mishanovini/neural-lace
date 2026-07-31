# The end-to-end process — intent to merged, with handoffs

Status: DRAFT for operator review (2026-07-30). Written in response to the operator's
direct question: "Are you able to articulate what the full process is supposed to be
with handoffs between each of the agents?"

Governing standard: `adapters/claude-code/doctrine/deterministic-process.md`.
A step is real only if (1) something fires it on an event that happens regardless,
(2) compliance is *reachable from the layer it fires at*, and (3) its output is a
durable artifact that is the next step's required input.

**Chat is never a handoff.** Every arrow below carries a file, not a message.

---

## The stages

| # | Stage | Actor | Fires on | Input (artifact) | Output (artifact) |
|---|---|---|---|---|---|
| 0 | Intent capture | orchestrator ↔ operator | operator states a want | operator's words | **Intended-Functionality statement** |
| 1 | Design | orchestrator / planner | IF statement exists | IF statement | plan file w/ required fields |
| 2 | Design review | design reviewer | plan reaches ACTIVE | plan | verdict + amended plan |
| 3 | Build | builder (worktree) | design review PASS | plan task | commits in worktree |
| 4 | Failure-mode analysis | failure-mode agent | build claims complete | diff + IF statement | requirements ledger |
| 5 | Functionality verification | functionality-verifier | requirements ledger exists | IF statement | PASS/FAIL + runtime evidence |
| 6 | Code review | harness/code reviewer | verification PASS | diff | review record (blob-addressed) |
| 7 | Integration | orchestrator | reviews PASS | worktree commits | commits on integration branch |
| 8 | **Funnel gate** | pre-push | `git push` | pushed commits | allow / refuse |
| 9 | Merge + deploy | estate-merge | funnel PASS | branch | master SHA + live restart |

---

## Stage 0 — Intent capture (the stage that does not exist yet)

**The defect it fixes:** "the watchdog script exists and runs" is a component
description, not a functionality. Every downstream reviewer that validates against a
component-level statement will pass component-level work. Garbage in, garbage out —
the failure recurses one level up.

**The Intended-Functionality (IF) statement** — required fields:

- **Outcome, in the operator's terms.** What becomes true for them. Names an
  observable surface and a state change. *"After a usage limit resets, work continues
  without me touching anything."*
- **Observation.** How anyone tells it happened, without reading code.
  *"The session resumes and the transcript shows post-reset activity."*
- **Deterministic pass/fail.** The rule that decides, with no judgment call.
  *"Resumption occurred within N minutes of reset, with zero human actions in between."*
- **Explicitly NOT included.** What this does not promise.
- **Human dependencies, declared up front.** Every human action the outcome requires,
  each marked INTENDED or DEFECT. *(The watchdog's answer was "operator must arm the
  marker" — marked DEFECT, it fails immediately at stage 0.)*

**The anti-restatement rule.** An IF statement that names only artifacts ("the script
exists", "the gate is wired", "the field renders") is REJECTED. The test: could this
sentence be true while the operator's situation is unchanged? If yes, it is a
component description. This is the hard part and it is why stage 0 has a human in it.

**Escalation:** if the orchestrator cannot write a statement passing the
anti-restatement test, it must *ask the operator* rather than invent one. Ambiguity is
surfaced, never resolved by assumption.

---

## Handoff contracts (what makes a stage refusable)

Each stage REFUSES its input if the contract is unmet — that is what makes the
process deterministic rather than advisory.

- **0 → 1** Design cannot begin without an IF statement. A plan with no IF statement is
  not ACTIVE.
- **1 → 2** The plan must carry: the IF statement; the component/wiring map; **the
  chokepoint that fires the functionality**; human dependencies; accumulated state.
- **2 → 3** Build cannot begin on a design with an unwired link, an unintended human
  dependency, or an untriggered step (deterministic-process rules 1–3).
- **3 → 4** The build declares which IF statement it satisfies.
- **4 → 5** Every requirement is tagged MECHANICALLY GUARANTEED / EXTERNAL STATE /
  HUMAN / UNVERIFIED. Anything below the first tier, on functionality declared
  automatic, FAILS back to the builder with instructions.
- **5 → 6** Verification evidence must be a runtime observation of the user path — a
  suite count is not admissible for a user-observable claim.
- **6 → 7** Review record is blob-addressed, so it cannot silently cover different bytes
  than the commit contains.
- **7 → 8** Integration performs no gating (see below) — it only moves commits.
- **8 → 9** Coverage is checked at the funnel, authoritative.

---

## The cherry-pick problem, and the resolution

**The laundering path (real, measured 2026-07-30):** builder commits in a worktree →
the commit-time review gate fires → but builder subagents have **no dispatch tool**, so
the reviewer the gate demands is *unreachable from that layer* → the only exits are
"never commit" or override → 78 override events logged, every one of today's naming
that exact reason → orchestrator cherry-picks (explicitly exempt, to avoid stranding a
mid-rebase) → `git push` never checks coverage at all. Unreviewed code reaches master
with no step having malfunctioned.

**The resolution — separate "don't strand" from "don't publish":**

1. **Commit-time stays ADVISORY.** It informs; it cannot deadlock an actor who is
   structurally unable to comply. Hardening it would make the deadlock worse.
2. **The cherry-pick exemption is KEPT and is correct.** Nobody is ever stranded
   mid-rebase; you can always complete the operation.
3. **`pre-push` becomes AUTHORITATIVE.** Every commit crossing to the remote must carry
   coverage, regardless of how it arrived on the branch. Being stranded mid-rebase and
   being unable to publish unreviewed work are different states, and only the second
   should be enforced.
4. **The actor at the funnel is the orchestrator, which CAN dispatch reviewers** — so
   the remedy is reachable from the layer that enforces it. That is the property the
   commit-time gate lacked, and it is the real argument for the move.
5. **Overrides at the funnel require an operator-authorized artifact** (the
   `/grant-local-edit` shape), not a self-written sentence.

**Remaining bypass path, declared not hidden:** `git push --no-verify`. Closing it
requires server-side enforcement this estate does not have. NAMED-AND-ACCEPTED.

---

## Honest status of each stage (2026-07-30)

| Stage | Exists? | Fires deterministically? |
|---|---|---|
| 0 Intent capture | **NO** — being designed | no |
| 1 Design | partial (plan template) | plan-time gates fire; IF field absent |
| 2 Design review | `architecture-reviewer` exists | **NO** — trigger is data-shaped designs only |
| 3 Build | yes | yes |
| 4 Failure-mode analysis | **NO** — being built | no |
| 5 Functionality verification | `functionality-verifier` exists | **NO** — only `Verification: full` plan tasks; and its harness carve-out accepts a `--self-test` as proof, which a source-regex suite satisfies |
| 6 Code review | yes | **deadlocked** (see above) |
| 7 Integration | yes | n/a — gating removed by design |
| 8 Funnel gate | **NO** — being built | no |
| 9 Merge + deploy | yes (`estate-merge.sh`) | yes |

Five of ten stages do not deterministically fire today. That is the honest picture,
and it is the work-list.
