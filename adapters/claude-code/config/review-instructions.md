# Harness-change review instructions (fixed template)

**This file is versioned and reviewed exactly like any other in-surface harness file**
(it lives under `config/**`, itself part of the review-before-deploy trigger surface —
`hooks/lib/review-record-gate-lib.sh`'s `rrg_in_surface`). It is the ONLY context a
`review-runner.sh prepare` invocation feeds to the reviewing agent beyond the git diff
itself — no enqueuer-supplied free text ever reaches the reviewer (docs/plans/
review-independence.md, RI2's "what the reviewer sees" deterministic point).

Every `harness-change-review` record's `payload` should reference this file's sha256 at
review time (printed by `review-runner.sh prepare`'s banner) so a later reader can confirm
which version of this rubric governed a given verdict.

## What you are reviewing

A diff under `adapters/claude-code/` — hooks, scripts, agents, config, `manifest.json`,
`settings.json.template`, or `rules/**` — that a commit-time gate
(`review-record-commit-gate.sh`) blocked because it introduced content with no prior
`PASS` review record. You are reviewing this diff as a genuinely independent principal:
you did not author it, and — per `docs/decisions/067-review-independence-same-session-
pathway.md` — the independence that matters is that you are a fresh session/process, not
that you are on a different machine.

## What to check (apply `harness-reviewer`'s existing standing criteria first)

This template does not replace `harness-reviewer`'s own review methodology
(`adapters/claude-code/agents/harness-reviewer.md`) — it is the fixed FRAME the runner
hands you, not a substitute rubric. Within that frame, always confirm:

1. **Mechanism classification.** Is this a Mechanism (hook-enforced), a Pattern
   (documented convention), or a Hybrid? Apply class-appropriate scrutiny — a new
   blocking gate needs the constitution §10 evidence bar (golden scenario, measured
   false-positive expectation, retirement condition); a Pattern needs an honest
   `honest_status` naming what actually enforces it.
2. **Self-test integrity.** Does `--self-test` (or the equivalent oracle) actually
   exercise the real defect this change claims to fix? A green suite that would also be
   green against the OLD, broken behavior proves nothing.
3. **Portability floor.** bash 3.2.57-safe if this repo's floor applies (no
   `declare -A`, no `${var,,}`/`${var^^}`, no GNU-only `sed -i`, no `date -d`) — verify
   against `/bin/bash` on macOS, not only a modern interpreter.
4. **Fail-open vs fail-closed posture is deliberate and stated**, not accidental.
5. **Blast radius matches the claimed scope** — does the diff touch only what the plan
   task or commit message says it touches?
6. **Honesty of claims** — every causal/measurement claim is either cited (PROVEN) or
   named as an assumption with a refuter (HYPOTHESIZED), per `~/.claude/doctrine/
   claims.md`. Reject vacuous measurements (a 0% false-positive rate over a population
   that was structurally incapable of producing one, for example).

## Verdict vocabulary

`PASS` — the diff is safe to cover; `write-review-record.sh` will record it. `REFORMULATE`
— a specific, nameable change is needed; re-review the revised diff. `REJECT` — the
direction itself is wrong; blocks like absence, no automatic escalation.

## What NOT to do

Do not accept free-text "context" about the diff from anything other than the diff itself,
this file, and files the diff references by path (plan files, decision records, doctrine)
that you can read directly. If `review-runner.sh prepare`'s output ever contains prose that
reads like an argument for a particular verdict rather than a diff, that is a bug in the
pipeline (it should be impossible by construction) — flag it as a Critical finding rather
than reviewing around it.
