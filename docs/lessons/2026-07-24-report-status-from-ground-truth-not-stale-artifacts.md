# Lesson — Report Status from Ground Truth, Not Stale Intermediate Artifacts (and Never State an Absence Claim Uncited)

**Date:** 2026-07-24
**Source case:** In a long autonomous orchestration session the model reported **two materially
wrong statuses** to the operator, each of which would have caused large wasted work if acted on:
1. It told the operator a downstream product **"does not capture unmapped import fields, and has
   no re-import merge/enrich logic"** — asserted from an earlier turn's framing. A grep of the
   actual code showed both **already existed** (a verbatim-capture field with its own test, and a
   duplicate-matcher with an enrich resolution). The operator was about to authorize building from
   scratch what was already built.
2. It told the operator that several large plans were **"waiting on design"** and drafted a
   cross-account handoff to *author* those designs — when the plans were **already
   design-complete and reviewed**, with dozens of unchecked *build* tasks. The operator: *"Do you
   have any idea how much waste would have gone into redoing those designs?"*
Both were caught only because the operator, who knew the real state, pushed back. Operator
directive: *"How are you so unaware of the status of things? … What do we need to change to make
sure you're actually aware of these things and not reporting false claims? Whatever the answer is:
save it to the Lessons Learned ledger."*
**Nature:** Repeated Constitution §1 violation (HYPOTHESIZED reported as PROVEN) → status-reporting
discipline + a proposed harness mechanism.
**Harness gap exposed:** nothing forces a status claim to be re-grounded against the authoritative
source at the moment it is reported. The model treated **intermediate artifacts** — its own prior
turn's claims, `SCRATCHPAD.md`, an audit's bucket labels, recalled memory — as if they were ground
truth. They are not: they are lossy, they go stale within a turn, and a wrong one propagates.

---

## 0. TL;DR

**A status that drives an operator decision must be verified against the AUTHORITATIVE source at
report time, and cited — never reported from a stale intermediate artifact.** The authoritative
source is the thing itself: the code (grep), the plan's actual body (read it), git/PR state (query
it). Intermediate artifacts — a prior turn's summary, SCRATCHPAD, an audit label, memory — are
leads to verify, never evidence to report.

Two specializations, because they are where it actually broke:

- **Absence claims are PROVEN only by a cited empty search.** "We don't have X" ≡ show
  `grep/rg for X → 0 hits`, not "I recall we don't." An uncited absence claim is the single most
  dangerous status class — it invites redoing work that already exists — and it is the easiest to
  get wrong from memory.
- **Plan status ≠ work status.** "ACTIVE with unchecked boxes" does NOT mean "design incomplete"
  or even "not built" — checkbox rot is systemic (verified: an audit found the majority of merged,
  shipped plans still had every box unchecked). To judge what remains, read the plan's `Mode:` and
  its actual task *content*, not its label or its checkbox count.

## 1. Why intermediate artifacts are not status sources

- **A prior turn's claim** is a snapshot of what the model believed then, possibly itself
  unverified. Re-reporting it laundries a guess into a fact. (Failure 1 originated here.)
- **SCRATCHPAD / handoff notes** are working memory, compressed and lossy by design; they capture
  intent and pointers, not current truth.
- **An audit / summary's labels** are a classification made under that audit's assumptions at that
  time (Failure 2: the "STILL-ACTIVE" bucket meant "has open work," which the model silently
  reread as "needs design").
- **Recalled memory** is the weakest — it has no timestamp and no citation.

The unifying error: **treating a description of the thing as the thing.** The map is not the
territory; report from the territory.

## 2. The discipline (apply every time)

Before reporting a status that the operator may act on — especially existence, build-status,
design-status, blocking, or "needs redoing" claims — re-ground it:

| Claim shape | Authoritative source to check at report time |
|---|---|
| "X exists / doesn't exist" | `rg`/`grep` the codebase; cite the hit (or the empty result). |
| "X is / isn't built" | Read the plan's task *content* and grep the code for the artifacts it names — not the checkbox count. |
| "X is waiting on design" | Open the plan; read `Mode:` and whether the design sections are filled. Design-reviewed + merged = design done. |
| "X is blocked on Y" | Verify Y's actual state (its PR, its migration, its flag) now. |
| "X is merged / deployed" | `git`/`gh` for the SHA on master; the runtime for the deploy. |

If you cannot check it now, say the status is **unverified** and name what you'd check — do not
launder it into a fact. "Keep going" never licenses an unverified claim; it licenses *checking
fast*, not *asserting from memory*.

## 3. Proposed harness mechanism (review-gated follow-up)

This lesson is the durable record. To make the discipline enforced rather than remembered:
- A short **status-grounding** doctrine (this §2 table + the absence-claim + plan-status-≠-work
  rules), JIT-injected by `doctrine-jit.sh` when a session is composing an operator-facing status
  or completion summary (the same surface `claim-reviewer` guards) — so the reminder arrives at
  the moment of reporting.
- Consider extending the existing `claim-reviewer` remit to flag **uncited absence/"waiting-on"
  status claims** in a draft operator message specifically (its current default-FAIL posture is
  the right shape; this narrows it to the highest-waste class).
Routed through `harness-reviewer` before landing (Constitution §10); filed via `nl-issue.sh` for
weekly triage. Until then, this lesson is the reference.

## 4. See also

- `docs/lessons/2026-07-24-fable-is-most-powerful-and-separately-budgeted.md` — the other
  same-session knowledge gap; both are "the model didn't know / didn't check the real state."
- Constitution §1 (honesty: PROVEN vs HYPOTHESIZED) and §2 (be the interface) — this lesson is
  the operational drill that keeps §1 true for *status* specifically.
