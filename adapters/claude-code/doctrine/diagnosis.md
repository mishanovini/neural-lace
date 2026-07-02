# Diagnosis before fixing — compact
> Enforcement: Pattern — self-applied. Full: doctrine/diagnosis-full.md
> Applies: any investigation, debug, or root-cause session

**First tool call on any production-failure investigation: pull runtime logs.**
Vercel logs, Sentry/Datadog, Supabase logs, webhook delivery logs, job-runner
logs — whatever the platform is. Inferential evidence (probing, code reading,
git bisect, dependency analysis) is permitted only AFTER logs are examined, or
after an explicit "logs are inaccessible because X" with a concrete reason.
Confidence-sounding diagnoses without log evidence are prohibited — see
doctrine/claims.md.

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
