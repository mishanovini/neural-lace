# Plan — Verification dispatch is standard process (harness governance)

Status: ACTIVE
Mode: code
Owner: interactive session (2026-07-28, operator-directed)
Backlog items absorbed: none
acceptance-exempt: yes (harness-internal; maintainer is the user, demonstrated by the JIT
injection firing on a real `hooks/` edit and by `manifest-check.sh` staying green)

## Why

Commit `f6562b2` (accountable-estate T3) reached master with no `harness-reviewer` and no
`task-verifier`. The session told the operator that verification "belongs to the desktop
machine." Operator response: *"Who the hell gave you a standing instruction not to dispatch
agents unless I request it? That's supposed to be the standard process."*

A filesystem search proved the instruction is NOT the operator's: absent from
`settings.json`, `settings.local.json`, `~/.claude.json`, `~/.claude/local/`,
`~/.claude/CLAUDE.md`, the repo `.claude/`, `settings.json.template`, and `rules/`. It is a
Claude Code **application-layer** default ("do not call the Agent tool unless the user
requested it") that ships in some builds' system prompts.

`harness-reviewer` reviewed the first draft of this fix and returned REFORMULATE, naming a
root cause the draft did not touch: `manifest.json` `entries[93]` JIT-routes the
`review-before-deploy` doctrine **only** to `install.sh` and `session-start-auto-install.sh`
— never to `hooks/**`, where harness changes are actually authored. So the doctrine that
says "a harness change needs a harness-reviewer PASS" was never injected while
`hooks/lib/admission-lib.sh` was being written. The always-loaded paragraph the draft added
would not have prevented anything.

## Scope / Tasks

- [ ] V1 — Replace the 11-line always-loaded directive in `CLAUDE.md` with a <=4-line pointer
      bullet (Pattern-class verbs, no "does NOT apply / is overridden" mechanism claim).
      Verification: mechanical (line count; `claude-md-hygiene-gate.sh` check 2c no longer
      classifies it as extractable rule-body).
- [ ] V2 — Create `doctrine/verification-dispatch.md` carrying the body: the rule, the
      trigger table, an explicit NOT-triggers exemption set, model-routing guidance (pass an
      explicit `model`; retry on opus on a spend-limit error), the say-so-explicitly clause,
      and the GOLDEN CASE. Verification: full (JIT injection observed firing).
- [ ] V3 — Fix `manifest.json` `entries[93]` (`review-before-deploy`) `jit_triggers.paths` to
      route to the surfaces the gate GOVERNS (`hooks/`, `scripts/`, `agents/`, `rules/`,
      `manifest.json`), not only the two files that implement its carriers.
      Verification: full (edit a `hooks/` file, observe the doctrine inject).
- [ ] V4 — Add the `verification-dispatch` manifest entry, honestly labelled PATTERN with the
      missing commit-time mechanism named. Verification: mechanical (`manifest-check.sh`).
- [ ] V5 — File the two review-surface gaps `harness-reviewer` surfaced as nl-issues:
      `rrg_in_surface` returns OUT for `CLAUDE.md` and `doctrine/*.md` (the highest-leverage
      behavior files are outside the review surface), and the Fable-exhaustion event.
      Verification: mechanical (rows in the ledger).
- [ ] V6 — DEFERRED, NOT IN THIS PLAN: the commit-time carrier gate (a PreToolUse hook
      sourcing `rrg_in_surface`/`rrg_is_covered` to block a `git commit` of an uncovered
      in-surface file). `harness-reviewer` named this "the single most important thing to
      fix" and the enforcement API plus `write-review-record.sh` already exist unwired. It is
      a new blocking gate, so it needs its own §10 evidence bar (golden scenario, measured
      false-positive expectation, retirement condition) and a warn-mode calibration period.
      Tracked here so the debt is visible; it does not ship in this plan.

## Files to Modify/Create
- `adapters/claude-code/CLAUDE.md` — V1
- `adapters/claude-code/doctrine/verification-dispatch.md` — V2
- `adapters/claude-code/manifest.json` — V3, V4
- `docs/plans/verification-dispatch-directive.md` — this plan

## Assumptions
- A project `CLAUDE.md` instruction genuinely outranks an application-layer default. The
  system prompt states project instructions override default behavior, so the pointer is
  load-bearing — but as a Pattern it is enforced by the model reading it, which is the rung
  that already failed once. This is why V6 exists and why the manifest entry says PATTERN.
- Routing the doctrine to `hooks/**` fires at the moment of the decision (JIT is path-matched
  on edit), which is the correct trigger point. Verified live during this build.

## Edge Cases
- Over-firing: an unscoped "always verify" reading would burn tokens on doc typos and
  conversational turns. Addressed by the explicit NOT-triggers list in V2.
- The verifier model chain is `fable -> opus` and Fable was budget-exhausted during this
  session — both dispatches died until forced to opus. A mandate to dispatch agents that
  reliably fail reproduces the failure it prevents, so V2 carries the retry guidance.
- `entries[93]`'s existing three paths must be preserved, not replaced, or the deploy
  carriers lose their own injection.

## Testing Strategy
`manifest-check.sh` green for the new and amended entries. JIT injection demonstrated live:
editing a file under `adapters/claude-code/hooks/` must inject `verification-dispatch` (and,
after V3, `review-before-deploy`) — observed during this build, which is the functional
oracle per constitution §4. `claude-md-hygiene-gate.sh` must not classify the CLAUDE.md
bullet as extractable rule-body.

## In-flight scope updates
- 2026-07-28: docs/plans/verification-dispatch-directive.md — this plan
- 2026-07-28: adapters/claude-code/rules/constitution.md — V7: §3 cold-reader bar extended to cover ASKS as well as decisions, and the §2 ask bullet reduced to the genuine delta (harness-reviewer REFORMULATE: two-thirds of the first draft restated §3)
- 2026-07-28: adapters/claude-code/scripts/needs-you.sh — V8: `_ny_lint_ask_text`, the WARN-ONLY carrier for `--section question` (harness-reviewer: that section was completely unlinted while the decision twin has been linted since 53d3bee)
