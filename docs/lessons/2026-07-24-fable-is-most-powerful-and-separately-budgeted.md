# Lesson — Fable Is the Most Powerful Model, and It Has Its Own Separate Weekly Budget

**Date:** 2026-07-24
**Source case:** During a long autonomous multi-agent orchestration session, the operator twice
had to correct the model's spending posture ("be mindful of what you are using Fable for",
then "we're running low on Fable budget"). When the model reasoned about whether switching
work to Opus would help, it hedged that the weekly cap *might* be shared across models — it
did not know Fable is separately budgeted. The operator then sent a screenshot of the usage
panel proving two distinct bars: **"Weekly · Fable" at 95%** while **"Weekly · all models"
sat at 55%** (5-hour limit 75%). The operator's words: *"Fable does have its own weekly
budget, independent of the regular weekly budget. I am realizing that this is not something
that Claude tends to be aware of by default. I would like to add this knowledge to the
harness, along with the knowledge that Fable is the most powerful model. It has been made
apparent to me multiple times that Claude does not know that Fable is the most powerful
model."*
**Nature:** Missing model-identity + budget-mechanics knowledge → durable fact record, with
operational implications for model selection and pacing.
**Harness gap exposed:** no loaded surface (constitution, doctrine, principles, rules) carries
either fact. A grep of the whole harness for `fable` / `mythos` / `most powerful` /
`model tier` returned nothing. So every session rediscovers (or fails to discover) the model
hierarchy and the budget separation from scratch — and has repeatedly gotten both wrong.

---

## 0. TL;DR

Two facts every session should hold by default, and neither was written down anywhere:

1. **Fable is the single most powerful Claude model** — Mythos-class, a tier **above Opus**.
   The capability order is **Fable / Mythos > Opus > Sonnet > Haiku**. Fable 5 and Mythos 5
   are the *same underlying model* (Mythos is the without-extra-safety-measures variant for
   approved orgs). Do **not** treat Fable as a peer or a lesser of Opus, and do not reach for
   Opus as "the top tier" — Fable is the top tier.

2. **Fable has its own independent weekly budget**, tracked separately from the "all models"
   weekly limit. There are (at least) three concurrent limits: a **5-hour rolling** limit, a
   **Weekly · all models** limit, and a **Weekly · Fable** limit. Fable usage draws down its
   own Fable-weekly pool, which can be **near-exhausted while the all-models weekly is
   comfortable** (observed live: Fable-weekly 95% vs all-models-weekly 55%). "Low on Fable" is
   therefore **not** "low overall," and vice-versa — the pools move independently.

The operational upshot: **route work to the model that fits the task AND the pool that has
headroom.** Because Fable is both the most capable *and* the scarcest-per-its-own-pool,
reserve it for the work that actually needs the top tier and pay for cheaper work out of the
roomier pools.

---

## 1. The facts, precisely

### 1a. Capability hierarchy

- **Fable 5 / Mythos 5** — Mythos-class, sits **above Opus**; the most intelligent generally
  available Claude model. Fable and Mythos share one underlying model (Fable carries additional
  dual-use safety measures; Mythos is available without them to approved organizations only).
  Model IDs: Fable = `claude-fable-5`.
- **Opus 4.8** (`claude-opus-4-8`) — below Fable, above Sonnet. Very strong, and the right
  default for heavy orchestration/judgment when Fable must be conserved.
- **Sonnet 5** (`claude-sonnet-5`) — the workhorse for build/mechanical/reconcile work.
- **Haiku 4.5** (`claude-haiku-4-5-20251001`) — cheapest/fastest; scoped lookups, cheap
  read-only passes.

The recurring failure this corrects: sessions defaulting to "Opus is the strongest, downgrade
to Fable/Sonnet for cheap work" — which mis-ranks Fable. Correct framing: **Fable is the
strongest; step DOWN to Opus/Sonnet/Haiku to conserve Fable**, not the reverse.

### 1b. Budget mechanics

- Usage is metered by **multiple simultaneous limits**, and a request can be gated by whichever
  binds first: **5-hour rolling**, **Weekly · all models**, **Weekly · Fable**.
- **Fable draws its own weekly pool.** That pool is smaller/tighter in practice than the
  all-models weekly and can hit ~100% while the all-models weekly is only half-spent.
- **Evidence (operator usage panel, 2026-07-24):** `Weekly · Fable 95%` · `Weekly · all
  models 55%` · `5-hour limit 75%` — three separate bars, Fable's own bar the binding one.
- **A different account has a different, independent Fable pool.** Handing Fable-heavy work
  (design authoring, adversarial review of money/safety-critical paths) to a second account's
  session is a legitimate way to access more Fable capacity when one account's Fable-weekly is
  spent — coordinated via files per the estate-coordination doctrine, not by one session
  reaching into another's budget (a session's sub-agents always draw on *that session's*
  account).

### 1c. Sub-agent model is fixed at dispatch — exhaustion kills, never downgrades

- A sub-agent's model is set at **dispatch time** (the `model:` parameter, or inheritance) and
  **cannot change mid-run**. There is no live model-swap; an agent does not "switch to Opus"
  when Fable runs out.
- On budget exhaustion the running agent's next request **hits the limit error and the agent
  terminates** — it does not fall back to a cheaper model. Uncommitted work-in-progress is
  **lost**. (See the misleading-limit-error note below.)
- Therefore: any Fable-assigned agent must **commit + push WIP frequently** so a mid-run death
  is recoverable from the branch, and the orchestrator should prefer to check Fable headroom
  *before* dispatching Fable-heavy work.

### 1d. The limit error text is misleading

- The limit-death error can read like a "monthly spend limit" — that text is **false**; the
  real limits are the rolling 5-hour and the weekly pools (all-models + Fable). Treat a limit
  death as a **rolling-window** event: salvage WIP, resume after the relevant window resets
  (the panel shows the reset time), and never escalate it to the operator as a billing problem.

---

## 2. Operational rules that follow

1. **Rank correctly.** Fable > Opus > Sonnet > Haiku. Never describe moving *to* Fable as a
   downgrade, and never call Opus the top tier.
2. **Reserve Fable for what needs the top tier:** hardest design/planning, adversarial review
   of money-path / safety-critical / live-customer changes, deepest judgment calls. Mechanical
   build/reconcile/verification work goes to Sonnet (or done inline); scoped read-only lookups
   to Haiku.
3. **Pace against the Fable pool separately.** When Fable-weekly is high, shift the main loop
   to Opus and dispatch new design/review sub-agents on Opus explicitly — this genuinely
   extends runway *because the pools are independent*. It is a real lever, not a cargo-cult one.
4. **Protect in-flight Fable work.** Fable-assigned agents commit+push WIP; prefer a headroom
   check before a Fable-heavy dispatch.
5. **Use cross-account Fable deliberately.** A second account's separate Fable pool is a valid
   capacity source for design/review lanes; coordinate via files (briefs on master, the
   estate-coordination protocol), never by assuming one session can spend another's budget.

---

## 3. Recommended harness wiring (follow-up, review-gated)

This file is the durable record. For the two facts to be *known by default* rather than
rediscovered, they should reach a session-loaded surface. Because the always-loaded budget is
capped (constitution §10 — a new rule enters only by replacing) and harness changes go through
`harness-reviewer`, the proposed path is:

- A short **model-facts reference** in doctrine (capability order + the three-limit budget
  model + "fixed at dispatch, exhaustion kills") that `doctrine-jit.sh` injects whenever a
  session touches a model-selection / budget / sub-agent-dispatch surface — the same JIT
  pattern already used for estate-coordination and deploy-sync.
- Filed to the machine-wide ledger via `nl-issue.sh` so it enters weekly triage for promotion.

Until that wiring lands and is reviewed, this lesson is the reference; sessions that reason
about model selection or budget should be pointed here.

---

## 4. See also

- `docs/lessons/2026-07-14-background-agent-heartbeat-watchdog.md` — background-agent liveness
  (the WIP-loss-on-death risk in §1c compounds when a Fable agent dies unnoticed).
- A downstream project's own memories on sub-agent model bias (route mechanical work to
  cheaper models) and on misleading limit-error text — the project-local precedents this
  lesson generalizes into harness knowledge.
