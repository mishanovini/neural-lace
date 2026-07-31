# Plan — Model-Awareness Knowledge (Fable is top-tier + separately budgeted)

Status: ACTIVE
Mode: docs
Owner: interactive session (2026-07-24)
Backlog items absorbed: none
acceptance-exempt: yes (harness-internal knowledge doc + a review-gated doctrine follow-up; demonstrated by the lesson file existing on master and, for the follow-up, by `doctrine-jit.sh --self-test` once that step is built)

## Why
No loaded harness surface carried two model-identity facts, and sessions have repeatedly
gotten both wrong (operator: "made apparent to me multiple times that Claude does not know
that Fable is the most powerful model"):
1. Fable/Mythos is the TOP capability tier, above Opus (Fable > Opus > Sonnet > Haiku).
2. Fable has its OWN weekly budget, independent of the "all models" weekly (observed live
   2026-07-24: Weekly·Fable 95% while Weekly·all-models 55%).
A grep for `fable`/`mythos`/`most powerful`/`model tier` across the harness returned nothing.
This plan lands the durable lesson now and tracks the review-gated wiring that would make the
facts known by default rather than rediscovered.

## Files to Modify/Create
- `docs/plans/model-awareness-knowledge-2026-07-24.md` — this plan
- `docs/lessons/2026-07-24-fable-is-most-powerful-and-separately-budgeted.md` — created; the durable fact record

## Tasks
- [x] Author the lesson (both facts + budget mechanics + sub-agent-fixed-at-dispatch +
  misleading-limit-error + operational rules). — done, this commit.
- [ ] FOLLOW-UP (review-gated, separate PR): draft a short model-facts doctrine (capability
  order + three-limit budget model + fixed-at-dispatch/exhaustion-kills) and wire
  `doctrine-jit.sh` to inject it on model-selection / budget / sub-agent-dispatch surfaces;
  route through `harness-reviewer` before it lands (constitution §10 — new loaded content is
  review-gated). File via `nl-issue.sh` for weekly triage.

## Notes
The lesson is the reference until the doctrine wiring lands. The follow-up is deliberately a
separate, reviewed change — this plan does not itself modify any always-loaded or JIT surface.
## In-flight scope updates
- 2026-07-29: adapters/claude-code/scripts/model-availability.sh — the ACTUAL fable->opus fallback (operator directive: "Fable is supposed to always fail back to Opus"). Stateless canonical-derived reconcile; the pin is the only executing decision point (decision 063 + the 2026-07-24 lesson prove no runtime fallback exists).
- 2026-07-29: adapters/claude-code/hooks/model-pin-gate.sh — exhausted-tier reroute backstop: blocks a dispatch still pinned to a tier marked unavailable, naming the override.
- 2026-07-29: adapters/claude-code/hooks/session-start-digest.sh — SessionStart reconcile splice so the borrow ends by itself when the budget resets (operator: "Opus is a fallback, not the primary option").
- 2026-07-29: adapters/claude-code/doctrine/model-selection.md — corrected: the previous text claimed "runtime applies the fallback", which no code implements.
- 2026-07-29: adapters/claude-code/doctrine/model-selection-full.md — same correction, with the three verified facts and the real procedure.
