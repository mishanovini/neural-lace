# Deterministic process — compact

> Enforcement: HYBRID — the proof obligation is a Mechanism (`harness-doctor.sh`'s
> `check_deterministic_process_proof`); the BACKFILL across existing blocking units is not.
> Full: `deterministic-process-full.md` (verification commands, self-referential history,
> re-derive the status, do not trust a summary of it). Applies: every required step —
> reviews, verifications, gates, emits. Operator directive 2026-07-30: "We should never need
> to review whether the reviewers fired. Make them a deterministic part of the process."

## The standard

**A required step is DETERMINISTIC iff no path reaches the outcome without it.** A
reachability property — checkable by enumeration, not trust: name the outcome, enumerate
the paths, show the step is on every one. Name one path that skips the step and it is
advisory no matter what the inventory calls it — it will eventually not fire.

**Never ask "did the reviewer run?"** The question is itself the defect: it means the
process permits a run in which it did not. Asking after the fact is auditing, and auditing
is what you do when enforcement is absent.

## The three rules

**1. Enforce at the NARROWEST CHOKEPOINT EVERY PATH TRAVERSES.** Early checks at convenient
layers are fine as extras; the authoritative gate belongs at the funnel. Picking convenience
over the funnel is how a Mechanism becomes a Pattern. (Golden case: review coverage gated at
`git commit` — four bypass paths in a day — while `pre-push`, the funnel to the remote,
checked nothing.)

**2. An override the actor authors UNILATERALLY is not an override.** A waiver costing one
typed sentence is a suggestion. A real one needs an authorization artifact the acting party
cannot produce for itself — copy `/grant-local-edit`. Length checks and audit logs are
forensics, not authorization.

**3. A step nothing INVOKES is not part of the process.** Every required step names the event
that fires it, occurring regardless of anyone remembering. "The model calls it when
appropriate" is a non-trigger. (Golden cases: the limit-resume watchdog's marker — consumed
by a script, written by nobody; `/calibrate` — zero entries ever.)

## The proof obligation

**STATUS: SPECIFIED, NOT BUILT for the backfill** (most existing `blocking: true` units still
carry neither field, exempted by a shrinking grandfather list — full doctrine has the exact
count + re-derivation commands). Every blocking unit declares:
- `chokepoint` — the firing event, in verifiable form (`pre-push`, `Stop`, …).
- `bypass_paths` — every known route that skips it, CLOSED or NAMED-AND-ACCEPTED. An empty
  list claims none exist and is a lie unless someone enumerated them.

Prefer MECHANICAL enumeration to careful reading — a reading is done by a mind that may hold
the assumption that produced the gap. This file's positive statement: **do not ask whether the
process ran — build it so it could not have been skipped.**
