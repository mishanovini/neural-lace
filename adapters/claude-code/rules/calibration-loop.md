# Calibration Loop — Manual Bootstrap of the Knowledge Integrator Role

**Classification:** Hybrid. The discipline (when to invoke `/calibrate`,
which observation classes apply, what becomes a prompt update vs. work-shape
extension vs. defers to telemetry) is Pattern — self-applied by the
operator and the orchestrator at session boundaries. The capture surface
is Mechanism: `/calibrate` skill writes structured entries to
`.claude/state/calibration/<agent-name>.md` deterministically, and the
roll-up Check in `/harness-review` reads those entries mechanically and
surfaces patterns. The decision of whether a roll-up signal warrants a
prompt update OR a new mechanical gate is Pattern — it requires human
judgment, and is the explicit Knowledge Integrator role's authority per
Build Doctrine.

## Why this rule exists

Build Doctrine Principle 9 ("Documents are living; updates propagate on
trigger") and Role 9 (Knowledge Integrator) describe a self-improving
harness: every observed agent failure produces a candidate doctrine update;
patterns trigger propagation; no anonymous changes. ADR 026 ("harness
catches up to doctrine") frames Tranche 1.5 as the harness's catch-up
arc against the now-codified doctrine.

Telemetry — the mechanical substrate that would auto-detect agent
shortcuts, hallucinations, and pass-by-default reviewer behaviors — is
HARNESS-GAP-11, gated on 2026-08. Until telemetry lands, the calibration
loop must run on **discipline-plus-skill**: the operator notices a
failure, captures a structured entry via `/calibrate`, and `/harness-review`
periodically rolls up the entries to surface patterns.

This rule documents the discipline. The skill (`adapters/claude-code/skills/calibrate.md`)
is the capture surface; this rule is when and how to use it.

## When to invoke /calibrate

Three triggers, in priority order:

### 1. Reviewer agent returned PASS where it should have returned FAIL

This is the highest-leverage calibration signal. Reviewer agents
(`task-verifier`, `code-reviewer`, `claim-reviewer`,
`plan-evidence-reviewer`, `end-user-advocate`, `harness-reviewer`,
`comprehension-reviewer`) gate work shipping; their false-PASS is the
exact failure shape that compounds (vaporware ships because the verifier
trusted the builder).

When you observe a reviewer's PASS verdict that didn't catch a real gap:

```
/calibrate <reviewer-name> pass-by-default "<one or two sentences naming what the reviewer missed and how the gap was caught downstream>"
```

The downstream catch matters: a reviewer that returned PASS where the
next session's pre-stop hook caught the gap is a different signal than
a reviewer that returned PASS where the user caught the gap in
production.

### 2. Builder agent took a shortcut to mark work complete

Builder agents (`plan-phase-builder`, `task-verifier` flipping its own
checkbox, etc.) have an LLM-induced bias toward "find the easiest exit
that lets me say DONE." When you observe a builder narrowing scope,
skipping a runtime check, or claiming coverage without exercising the
path:

```
/calibrate <builder-name> shortcut "<observation>"
```

### 3. Agent output drifted from its documented contract

Format-drift is the third class. An agent that returned the right verdict
but in the wrong shape (missing required field, wrong section heading,
off-by-one severity) is feeding garbage into downstream mechanical
checks. Calibrate this even when the verdict was correct — the format
contract is what makes the mechanical chain compose.

```
/calibrate <agent-name> format-drift "<what was wrong with the output shape>"
```

## Observation classes

The five canonical classes (kebab-case, fixed vocabulary):

- **`shortcut`** — agent took the easiest exit. Use this when the agent
  could have done the right thing but chose a narrower path. Common
  variants: narrowed test scope; skipped a runtime exercise; claimed
  coverage without citation; deferred work to a follow-up that shouldn't
  have been deferred.
- **`hallucination`** — agent claimed something that does not exist
  (file, function, capability, behavior). Common variants: cited a
  file:line that doesn't resolve; described a "fix" that wasn't in the
  diff; named an agent or hook that doesn't exist.
- **`pass-by-default`** — reviewer agent returned PASS without
  substantively reviewing. Common variants: PASS in suspiciously low
  duration relative to scope; PASS without naming any specific finding;
  PASS where a sibling-instance check would have caught a regression.
- **`format-drift`** — agent output did not conform to its documented
  contract. Common variants: missing required section heading; wrong
  field order; severity miscategorization; evidence-block schema
  violation.
- **`scope-drift`** — agent went outside its declared scope. Common
  variants: builder touching files outside the plan's
  `## Files to Modify/Create`; reviewer making decisions outside its
  role's authority; agent self-extending its remit.

If none of the five fit, propose a new class with the
`new-class:<label>` prefix in the details. The roll-up reviewer
(`/harness-review` Check 12) will surface new-class proposals so the
canonical list can be extended via doctrine update.

Do not coerce a misfit observation into one of the five — false
classification is itself a failure mode and contaminates the roll-up
signal.

## What becomes a prompt update

Patterns from the roll-up that warrant **prompt extensions** for the
named agent:

- **Recurring `shortcut` of the same shape** (e.g., task-verifier
  consistently skipping runtime evidence on docs-only tasks) → extend
  the agent's Counter-Incentive Discipline section with a specific
  sentence naming the shortcut and the corrected behavior.
- **Recurring `hallucination` against the same surface** (e.g., agent
  cites file:line that doesn't resolve) → extend the agent's prompt
  with a citation-verification sub-step ("before claiming a file:line
  exists, run `rg <pattern> <file>` and confirm the line is in
  output").
- **Recurring `format-drift`** in the same field → extend the agent's
  Output Format Requirements section with a worked example that
  includes the field as required.

These updates land via the standard rule-and-agent maintenance flow:
edit the agent file, sync to `~/.claude/agents/`, commit per
`harness-maintenance.md`. Reference the calibration entries as the
trigger so the audit trail is intact.

## What becomes a work-shape library extension

Patterns that warrant **new entries in the work-shape library** (Tranche C
of the architecture-simplification arc):

- **Recurring shortcut on a specific work shape** (e.g., builder
  consistently skips coverage on "wire X into all forms" sweep tasks) →
  the work-shape library should declare the canonical shape with
  per-target decomposition mandatory.
- **Recurring scope-drift on a class of plan** (e.g., orchestrator
  consistently dispatches builders without a `Verification:` field) →
  the work-shape library should ship a default that prevents the drift
  by structure.

Work-shape extensions are landed via Tranche C's plan; this rule defers
to that plan for the canonical-shape format.

## What defers to telemetry

Patterns that need **machine-detectable signals** before mechanization:

- **Reviewer time-budget anomalies** (e.g., reviewer that returns PASS
  in suspiciously low wall-clock time across many invocations) — needs
  per-invocation timing, which today only telemetry can capture
  reliably.
- **Cross-session shortcut detection** (e.g., agent that consistently
  marks complete in session N but the work fails in session N+1) —
  needs cross-session correlation, which is HARNESS-GAP-11 territory.
- **Reviewer-disagreement signals** (e.g., two reviewers returning
  different verdicts on the same artifact) — needs structured verdict
  storage, also gated on telemetry.

Patterns that defer get noted in the calibration entry's suggested
mitigation as `defer-telemetry: <observation>` so the roll-up can
forward them to HARNESS-GAP-11's eventual scope.

## What is NOT calibration

Three explicit exclusions to keep the substrate from contaminating with
unrelated noise:

1. **Codebase bugs go to backlog or findings.** A bug in the project
   under build (not in the agent's behavior) goes to `docs/backlog.md`
   or `docs/findings.md` per the findings-ledger rule. Calibration is
   about agents, not products.
2. **One-off user corrections that don't generalize.** "User corrected
   me once" is not a calibration entry. Wait for a second instance, or
   for a pattern that suggests the same correction would apply to other
   sessions, before calibrating.
3. **Speculative concerns.** "Agent X might do Y under condition Z" is
   not a calibration entry. Calibrate on observed behavior only. The
   skill enforces this by requiring details with concrete observation,
   not hypothesis.

## The roll-up consumer

`/harness-review` Check 12 reads `.claude/state/calibration/*.md` and
emits a section per agent:

```
## 12. Calibration roll-up

### task-verifier
Total entries: 7
Top observation classes: pass-by-default (4), shortcut (2), format-drift (1)
Most-recent: pass-by-default — "verifier returned PASS without checking the runtime command actually ran" (2026-05-04)

### code-reviewer
Total entries: 3
Top observation classes: pass-by-default (2), hallucination (1)
Most-recent: hallucination — "reviewer cited a file:line that did not resolve" (2026-05-03)
```

Reviewers reading the roll-up apply the discipline above:
recurring-pattern → prompt update OR work-shape extension OR defer to
telemetry.

## Promotion to durable substrate

Per Decision G.1 (queued-tranche-1.5.md), calibration entries are
gitignored operational state for v1. Promotion to durable artifacts
(committed `docs/calibration/<agent-name>.md` OR `docs/findings.md`
entries with `Source: calibration`) is reversible and gated on:

- Volume of cross-machine value (does another teammate's calibration
  stream contribute signal mine doesn't?).
- Maturity of the canonical-class vocabulary (is the five-class list
  stable enough to share across operators?).
- Knowledge Integrator role's explicit decision that the calibration
  loop has graduated from bootstrap to durable artifact.

Until then, calibration is per-machine. Operators with multiple
machines accumulate separate streams; this is acceptable for the
bootstrap.

## Cross-references

- `adapters/claude-code/skills/calibrate.md` — the manual-entry skill.
- `adapters/claude-code/skills/harness-review.md` Check 12 — the
  roll-up consumer (added in this tranche).
- `docs/decisions/queued-tranche-1.5.md` G.1, G.2 — the decisions
  backing storage location and manual-vs-mechanized cadence.
- `docs/decisions/026-harness-catches-up-to-doctrine.md` — the framing
  this loop operationalizes.
- `build-doctrine/doctrine/01-principles.md` Principle 9 — Documents
  are living; updates propagate on trigger.
- `build-doctrine/doctrine/02-roles.md` Role 9 (Knowledge Integrator) —
  the doctrinal role this manual loop bootstraps.
- `~/.claude/rules/diagnosis.md` "After Every Failure: Encode the Fix"
  — the broader discipline this rule operationalizes for agent
  behavior specifically (vs. project-bug behavior).
- `~/.claude/rules/findings-ledger.md` — the durable-artifact substrate
  calibration may eventually promote to (Decision G.1 option C).
- HARNESS-GAP-11 (`docs/backlog.md`) — the telemetry mechanization
  gated on 2026-08; this rule is the bootstrap until then.

## Enforcement

| Layer | What it enforces | File |
|---|---|---|
| Skill | Mechanically captures structured calibration entries to per-agent files | `adapters/claude-code/skills/calibrate.md` |
| Rule (this doc) | When to invoke, observation classes, what becomes prompt update vs. work-shape vs. telemetry-defer | `adapters/claude-code/rules/calibration-loop.md` |
| /harness-review Check 12 | Roll-up of calibration entries; surfaces patterns per agent | `adapters/claude-code/skills/harness-review.md` |
| State substrate | `.claude/state/calibration/<agent-name>.md` (gitignored, per-machine) | `.claude/state/` (already in .gitignore) |

The first two are documentation. The skill is the capture mechanism;
the harness-review extension is the consumption mechanism. Together
they bootstrap the Knowledge Integrator loop without telemetry.

## Scope

This rule applies in any project whose Claude Code installation has the
`calibrate` skill and the `harness-review` skill with Check 12 wired in.
Project-level: any project with operator-level calibration discipline
honors the rule; projects without `.claude/state/calibration/` see
`/harness-review` Check 12 surface "no calibration entries" and the
roll-up is silent. Adoption is implicit — the skill creates the
directory on first invocation. No flag flip required.
