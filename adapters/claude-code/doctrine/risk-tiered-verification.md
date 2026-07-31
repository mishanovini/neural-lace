# Risk-Tiered Verification — compact
> Enforcement: plan-reviewer.sh Check 12 (field validity), plan-edit-validator.sh (evidence routing), task-verifier (dispatch routing). Full: doctrine/risk-tiered-verification-full.md
> Applies: every plan task — verify proportionate to risk.

- Declare the level at the END of the task's checkbox line: `Verification: mechanical | contract | full`. Legal values are exactly those three, lowercase; unknown values fail plan review. When the token appears more than once on a line, the LAST occurrence wins.
- Tasks WITHOUT a declaration default to `full` — backward-compatible; existing plans need no migration.
- `mechanical`: correctness is attestable by deterministic bash checks (file edits, hook updates, schema authoring, doc/config work). Evidence = a structured `.evidence.json` via write-evidence.sh OR a one-line evidence block citing a commit SHA. No agent dispatch — task-verifier returns PASS citing the artifact.
- `contract`: correctness = match against a locked truth-target — a JSON Schema validation exiting 0 or a golden-file diff producing zero output. Requires an explicit oracle; if the task has no schema, golden fixture, or reference output, use `full` instead. No agent dispatch.
- `full`: the default. UI pages, API routes, webhooks, migrations, scheduled jobs, novel judgment, anything user-facing. Requires a fresh evidence block with matching Task ID plus a replayable `Runtime verification:` line; task-verifier runs its full rubric.
- Escalate mid-build when a mechanical-marked task turns out to carry a runtime surface: record an in-flight scope update + Decisions Log entry; the new level applies immediately.
- Mechanical does not mean skip verification — it means verification IS mechanical; include runtime_evidence entries when the change has hidden runtime effect (e.g. hook wiring).
- Never demote a runtime task to `mechanical` to dodge the evidence requirement — surface BLOCKED instead.
