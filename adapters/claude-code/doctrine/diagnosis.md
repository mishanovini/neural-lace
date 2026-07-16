# Diagnosis before fixing — compact
> Enforcement: Pattern (this rule) — self-applied. Mechanism (the commit gate
> below) — hook-enforced. Full: doctrine/diagnosis-full.md
> Applies: any investigation, debug, or root-cause session — data/behavior/
> state defects included, not just crashes (broadened 2026-07-16, batch task
> 3; see below).

**First tool call on any production-failure investigation: pull runtime logs.**
Vercel logs, Sentry/Datadog, Supabase logs, webhook delivery logs, job-runner
logs — whatever the platform is. Inferential evidence (probing, code reading,
git bisect, dependency analysis) is permitted only AFTER logs are examined, or
after an explicit "logs are inaccessible because X" with a concrete reason.
Confidence-sounding diagnoses without log evidence are prohibited — see
doctrine/claims.md.

**This applies to ANY observed defect, not only prod crashes.** A data bug
(a duplicate row, a wrong computed value, a corrupted state) and a behavior
bug (a UI showing stale data, an event firing twice, a flag not taking
effect) are the SAME class as a 5xx crash for this rule's purpose: obtain the
OBSERVABLE evidence of the SPECIFIC incident — the actual rows, the actual
log line, the actual repro — before proposing a fix. "I found a code path
that COULD cause this" is inference; "the logs/data show this IS what
happened" is evidence. Source case (2026-07-14): three successive
investigations of a live duplicate-appointment bug each reasoned from a
plausible code path (a missing per-contact uniqueness guard) straight to a
shipped fix, without ever pulling the specific incident's rows (`created_at`
gap, `booked_via`, `service_type`, property) — the fix may not have addressed
the real cause AND introduced a multi-property regression. Full case study:
`docs/lessons/2026-07-14-root-cause-must-be-evidenced-before-fix.md`.

**If that evidence is access-blocked, that is a BLOCKER to name (the exact
datum + how to get it), not a license to fix on inference.** When you must
proceed without it, the fix's blast radius must be bounded to fail-safe
(fail-open / feature-flagged / shadow-first) precisely because the cause is
unconfirmed — say so explicitly in the fix.

**Mechanism, not just Pattern: the evidence-before-fix commit gate.** Because
"read this rule before you commit" is a Pattern that a long, frustrating
investigation reliably erodes under shipping-momentum pressure, a `fix(...)`/
`fix:` commit is gated: it must carry either (a) a `## Root cause (evidenced)`
message section with a PROVEN-tagged, citation-backed line (an ONLY-INFERRED
section is mechanically rejected), or (b) a reference to a `kind:
fix-root-cause` review record (verdict PASS, covering a staged file, tagged
PROVEN or INFERRED-with-bounded-blast-radius). See
`evidence-before-fix-gate.sh` / `doctrine/evidence-before-fix.md` for the
full mechanism, its structured-waiver escape hatch, and the `fix-trivial:`
lighter path for genuinely trivial fixes.

**Before that, grep the failure-mode catalog first.** `grep -in '<symptom
keywords>' docs/failure-modes.md`. A `Discriminator` match means you've found a
known class in minutes instead of hours — apply its `Recovery`. If you're more
than ~30 minutes into hypothesis-chasing without having run this grep, stop and
run it now.

Order: pull logs → observe the actual error signature → grep the catalog with
that precise signature → apply Recovery, or proceed to the full chain-trace
below with logs in hand.

**Process:** map the full chain (user action → frontend → API → backend →
external service → response). Trace ONE concrete example end-to-end with real
values. Check what's hiding behind the first error. List every bug across the
chain and fix them together. Typecheck passing is not validation — trace a real
value or run it and observe the outcome.

**Fix the Class, Not the Instance.** When feedback (reviewer, test, lint, user
correction) flags a defect at one location, search for every sibling instance of
the same class before calling the fix done. Document the sweep in the commit:
`Class-sweep: <pattern> — N matches, M fixed, N-M exempt (<reason>)`.

**Encode the fix.** When you find a root cause, ask: can this class be prevented
for every future session? Behavioral pattern → propose a rule. Mechanical →
propose a gate. Either way, update `docs/failure-modes.md` — extend an existing
entry or append a new one. A diagnosis that isn't catalogued will be re-paid in
full by the next session.
