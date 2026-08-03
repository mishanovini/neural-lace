# Deterministic process — compact

> Enforcement: **HYBRID — the proof obligation is now a Mechanism; the
> BACKFILL is not.**
>
> WHAT EXISTS (verify, do not trust this line): `manifest.schema.json` defines
> both `chokepoint` and `bypass_paths` as optional typed fields; and
> `harness-doctor.sh`'s `check_deterministic_process_proof` REDs on any
> `"blocking": true` entry that is missing EITHER field, unless it is on a
> dated, closed grandfather exempt-list or carries `added_after < "2026-07"`.
> Re-derive rather than believe:
> `grep -c check_deterministic_process_proof adapters/claude-code/hooks/harness-doctor.sh`
> and `jq '.properties.entries.items.properties | has("chokepoint")' adapters/claude-code/schemas/manifest.schema.json`.
>
> WHAT DOES NOT EXIST: the backfill. Of the 40 `blocking: true` units, only 2
> are outside the grandfather list, and the rest still declare neither field —
> they are exempted by a DATED list that is meant to shrink to empty, not by
> having discharged the obligation. Count it, do not quote this sentence:
> `jq -r '.entries[]|select(.blocking==true)|select((((.chokepoint//"")|length)==0) or (((.bypass_paths//[])|length)==0))|.id' adapters/claude-code/manifest.json | wc -l`.
> Nor does a server-side check exist: every gate here is LOCAL, so `--no-verify`
> and a web-UI merge remain open on all of them.
>
> HISTORY, kept because it is this file's own best evidence. The FIRST version
> of this header claimed the mechanism existed when it did not; the SECOND
> (the "NONE YET" correction) stayed on the page after the mechanism actually
> landed, so the file spent a day understating itself while asserting
> `manifest.schema.json` "would REJECT both keys" — false the moment the
> schema was extended in the same commit that added the check. A doc that
> lies in EITHER direction about its own enforcement is the defect this file
> names; the inverse error is not the safe one, because a stale "not built"
> is exactly how a real control goes unused. Tracked as
> `DETERMINISM-PROOF-OBLIGATION-UNBUILT-01` (docs/backlog.md), which closes
> when the grandfather list reaches empty.
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
