# Deterministic process — compact

> Enforcement: **NONE YET — this file is currently PATTERN, not Mechanism.**
> CORRECTION 2026-07-30 (caught by a builder within hours of this file landing,
> and it is the exact defect this file names): the first version of this header
> claimed "`manifest.json` carries `chokepoint` + `bypass_paths` on every
> `"blocking": true` unit; `harness-doctor.sh` REDs on one declaring neither."
> All three halves were false. MEASURED: 39 blocking units, **0** carry
> `chokepoint`; the doctor check `determinism-chokepoint-declared` does not
> exist (0 occurrences); and `manifest.schema.json` is `additionalProperties:
> false`, so it would REJECT both keys today. Writing an unbuilt enforcement
> claim into the file whose thesis is that unbuilt enforcement claims are the
> cardinal defect is the sharpest available proof of the thesis. Tracked as
> `DETERMINISM-PROOF-OBLIGATION-UNBUILT-01` (docs/backlog.md); the header
> becomes an Enforcement line again only when the schema, the check and a
> backfill actually exist.
> Applies: every required step — reviews, verifications, gates, emits.
> Operator directive 2026-07-30: "We should never need to review whether the
> reviewers fired. Make them a deterministic part of the process."
> Full: `deterministic-process-full.md`.

## The standard

**A required step is DETERMINISTIC iff no path reaches the outcome without it.**

That is a reachability property — checkable by enumeration, not by trust: name
the outcome, enumerate the paths to it, show the step is on every one. If you
can name one path that reaches the outcome without the step, the step is
advisory no matter what the inventory calls it, and it will eventually not fire.

**Never ask "did the reviewer run?"** The question is itself the defect: it
means the process permits a run in which it did not. Asking after the fact is
auditing, and auditing is what you do when enforcement is absent.

## The three rules

**1. Enforce at the NARROWEST CHOKEPOINT EVERY PATH TRAVERSES.** Early checks
at convenient layers are fine as extras; the authoritative gate belongs at the
funnel. Picking convenience over the funnel is how a Mechanism becomes a
Pattern. (Golden case: review coverage gated at `git commit` — four bypass
paths, four agents through it in a day — while `pre-push`, the funnel to the
remote, checked nothing.)

**2. An override the actor authors UNILATERALLY is not an override.** A waiver
costing one typed sentence is a suggestion. A real one needs an authorization
artifact the acting party cannot produce for itself — copy `/grant-local-edit`
(operator-authorized, session-scoped marker consumed by the gate). Length
checks, placeholder denylists and audit logs are forensics, not authorization.

**3. A step nothing INVOKES is not part of the process.** Every required step
names the event that fires it, and that event must occur regardless of anyone
remembering. "The model calls it when appropriate", "run it weekly", "the
operator triggers it" are non-triggers. (Golden cases: the limit-resume
watchdog's marker — consumed by a script, written by nobody; `/calibrate` —
zero entries ever.)

## The proof obligation

**STATUS: SPECIFIED, NOT BUILT** (see the corrected Enforcement note above —
0 of 39 blocking units carry these fields; the schema rejects them; no doctor
check exists). This is the obligation the standard *requires*, written down so
the gap is visible and closable, NOT a description of what runs today.

Every `"blocking": true` manifest unit declares:
- `chokepoint` — the firing event, in verifiable form (`pre-push`, `Stop`, …).
- `bypass_paths` — every known route to the outcome that skips it, each CLOSED
  (with how) or NAMED-AND-ACCEPTED (with why). An empty list claims none exist
  and is a lie unless someone enumerated them.

Prefer MECHANICAL enumeration to careful reading — producer/consumer scanning
(`scripts/config-control-producer-scan.sh`: finds a consumed lever with zero
producers, rule 3's failure mode as a grep) and call-graph reachability. A
reading is done by a mind that may hold the assumption that produced the gap.

A gate at the wrong layer, a waiver anyone can write, and a step nobody invokes
all look like enforcement in the inventory and deliver none at runtime. That is
§10 theatre; this file is its positive statement: **do not ask whether the
process ran — build it so it could not have been skipped.**
