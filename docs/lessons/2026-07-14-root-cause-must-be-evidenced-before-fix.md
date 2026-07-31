# Lesson — A Bug Fix Must Cite OBSERVED Root-Cause Evidence, Not an Inferred Mechanism

**Date:** 2026-07-14
**Source case:** A duplicate appointment ("two Linda Ha $189 cards in one window") on a live
customer. The operator asked **repeatedly** to "dig deep and find the root cause before suggesting
solutions." Instead, three successive investigations each reasoned *from the code* to a **plausible
mechanism** (missing per-contact uniqueness → a double-submit / retry / cross-turn AI re-book could
insert a second row) and **shipped a fix (#972) on that inference** — without ever obtaining the
**observable evidence of the specific incident** (the two rows' `created_at` gap, `booked_via`,
`service_type`, property). When the evidence required prod DB access (Supabase 401), the session
**substituted inference for evidence** rather than pursue the reachable evidence (Vercel booking
logs *did* work) or stop and declare the evidence unreachable. Consequence: the fix (a) may not
address the real cause and (b) introduced a **regression** — its `(contact_id, capacity_slot_id)`
dedup grain would collapse a legitimate second booking for a customer with two properties, a case
the operator had to catch.
**Nature:** Failure post-mortem → harness-mechanism proposal.
**Harness gap exposed:** the DIAGNOSTIC-FIRST protocol (`~/.claude/rules/diagnosis.md`, "pull
runtime logs FIRST") EXISTS but (1) is framed for prod-runtime *crashes*, so its applicability to a
*data/behavior* bug was non-obvious, and (2) is a **Pattern, not a Mechanism** — nothing *gates* a
fix from shipping on an unverified cause. A rule you must *remember* loses to shipping momentum.

---

## 0. TL;DR

"I found a code path that *could* cause this" is **inference**. "The logs/data show this *is* what
happened" is **evidence**. A fix may only ship on the latter. Today's failure was treating a
mechanism-that-could-explain-it as a root-cause-that-did-explain-it, and shipping. The fix must
enforce the distinction: **a bug-fix PR carries an evidenced root-cause artifact (the observed
data/log/repro of the SPECIFIC incident), tagged PROVEN vs INFERRED, and a gate/reviewer rejects a
fix whose cause is inferred-not-observed OR whose evidence was declared unreachable without the
fix's blast-radius being bounded accordingly.**

## 1. The failure, precisely

- **Expected (per the rule):** on a reported defect, obtain the observable evidence of what actually
  happened *before* proposing a fix.
- **Actual:** grep → "here is a code path with no uniqueness guard" → propose+ship a guard. The
  actual incident's provenance was never observed.
- **Trigger:** an access wall (Supabase 401) on the one evidence source, met with inference instead
  of (a) the reachable alternative (Vercel logs) or (b) an honest "evidence unreachable" stop.
- **Amplifier:** a strong "never idle / keep moving" posture that rewards shipping a fix over the
  slower work of evidencing the cause.
- **Cost:** wrong-or-unconfirmed root cause + a live regression (multi-property collapse) the
  operator caught, not the harness.

## 2. Classification

**Vaporware-adjacent / inference-dressed-as-diagnosis.** The harness let a *hypothesis* be shipped
with the confidence of a *finding*. Same family as claiming done without runtime verification —
here, claiming *cause* without observation.

## 3. Why the soundness asymmetry makes this severe

A fix on an unverified cause fails in BOTH directions at once:
- **False-negative on the cause:** the real generator keeps generating (the bug persists, now
  "fixed" and closed).
- **False-positive collateral:** the speculative fix changes behavior somewhere it shouldn't (the
  multi-property regression). Evidencing the cause first would have surfaced the property/service
  dimension *before* a grain was chosen.

## 4. Proposed mechanism (deployable)

1. **Broaden `diagnosis.md` beyond prod crashes.** Add an explicit clause: *"For ANY observed defect
   — data, behavior, state, or crash — obtain the OBSERVABLE evidence of the SPECIFIC incident (the
   actual rows/logs/events/repro), not merely a code path that could produce it, BEFORE proposing a
   fix. If that evidence is access-blocked, that is a BLOCKER to surface (name the exact datum + how
   to get it), not a license to fix on inference. A fix shipped on an unverified cause must have its
   blast radius bounded to fail-safe (fail-open / shadow-first) precisely because the cause is
   unconfirmed."*
2. **A gate / reviewer remit (the Mechanism).** A PR that presents itself as a bug fix (title/body
   `fix(...)`, or touches a path a linked incident names) must contain a **`## Root cause (evidenced)`**
   section that cites the OBSERVED artifact and tags each causal claim **PROVEN** (observed) or
   **INFERRED** (reasoned). The `code-reviewer` agent's remit is extended (or a lightweight gate
   added) to FAIL/flag a bug-fix PR whose root cause is entirely INFERRED, or whose evidence is
   "unreachable" while the fix's grain is *not* fail-safe. This turns the Pattern into a check that
   fires at the moment of shipping, where the momentum pressure is highest.
3. **Name the anti-pattern in the failure-mode catalog** (`docs/failure-modes/`): *"mechanism-
   sufficient fix"* — shipping a fix because a plausible cause exists in the code, without confirming
   that cause fired for the actual incident. Symptom: a `fix(...)` PR whose evidence is a grep result,
   not a log/data observation.

## 5. Honest residual risk

- **Evidence is sometimes genuinely unreachable** (creds, retention). The mechanism does NOT demand
  omniscience — it demands honesty: name the missing datum, and if you must proceed, make the fix
  fail-SAFE and say so. It only fails a PR that ships an *unbounded* fix on an *unverified* cause.
- **Over-gating trivial fixes.** Scope: the gate applies to `fix(...)`-class PRs / incident-linked
  changes, not refactors or features. A one-line typo fix needs no incident forensics.
- **The reviewer can't always judge PROVEN vs INFERRED** — but requiring the author to *tag* each
  claim, and citing the artifact, is itself most of the value (it forces the author to look).

## 6. Companion work
- Filed via `nl-issue.sh` (2026-07-14) as the quick capture; this is the durable write-up.
- Sibling of [`2026-07-14-background-agent-heartbeat-watchdog.md`](2026-07-14-background-agent-heartbeat-watchdog.md)
  and [`2026-07-13-false-nothing-needed-from-you.md`](2026-07-13-false-nothing-needed-from-you.md) —
  all three are "the harness trusted a claim/absence/inference where it should have required an
  observation."
