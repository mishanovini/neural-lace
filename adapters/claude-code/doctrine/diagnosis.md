# Diagnosis before fixing — compact

> Enforcement: Pattern (this rule) — self-applied. Mechanism (the commit gate
> below) — hook-enforced, currently WARN-MODE (teaches, never blocks; see
> below and doctrine/evidence-before-fix.md's PROMOTION CONDITION). Full:
> doctrine/diagnosis-full.md
> Applies: any investigation, debug, or root-cause session — data/behavior/
> state defects included, not just crashes (broadened 2026-07-16, batch task
> 3; see below). NOTE (scope mismatch, named not hidden): the RULE below is
> scoped to observed defects; the gate's TRIGGER (any fix(/fix: commit) is
> broader than that by construction — see doctrine/evidence-before-fix.md for
> why, and why that gap is exactly what warn-mode is calibrating.

**First tool call on any production-failure investigation: pull runtime
logs** (Vercel, Sentry/Datadog, Supabase, webhook, job-runner — whatever the
platform). Inferential evidence (probing, code reading, bisect) is permitted
only AFTER logs are examined, or after an explicit "logs are inaccessible
because X" with a concrete reason. Confidence-sounding diagnoses without log
evidence are prohibited — see doctrine/claims.md.

**Applies to ANY observed defect, not only prod crashes** — a data or
behavior bug needs the SAME observable evidence of the specific incident
before a fix. If evidence is access-blocked, name it as a BLOCKER and bound
the fix to fail-safe (fail-open / feature-flagged / shadow-first). Case
study: `docs/lessons/2026-07-14-root-cause-must-be-evidenced-before-fix.md`.

**Mechanism (warn-mode, not yet blocking): the evidence-before-fix commit
gate.** A `fix(...)`/`fix:` commit needs an evidenced `## Root cause
(evidenced)` section or a passing `kind: fix-root-cause` review record —
missing both gets a teaching banner, not a block. Full criteria + waiver
hatch: `doctrine/evidence-before-fix.md`.

**Grep the failure-mode catalog first:** `grep -in '<symptom keywords>'
docs/failure-modes.md`. A `Discriminator` match = known class — apply its
`Recovery`. >~30 min into hypothesis-chasing without running this grep →
stop and run it now.

**Process:** map the full chain (user → frontend → API → backend → external
service → response), trace ONE concrete example end-to-end, check what's
hiding behind the first error, and fix every bug in the chain together.
Typecheck passing is not validation.

**Fix the Class, Not the Instance.** When feedback flags one defect, search
for every sibling instance before calling it done. Document: `Class-sweep:
<pattern> — N matches, M fixed, N-M exempt (<reason>)`.

**Encode the fix.** Behavioral pattern → a rule. Mechanical → a gate. Update
`docs/failure-modes.md` either way — an uncatalogued diagnosis gets re-paid
in full next session.
