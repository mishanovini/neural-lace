# Mechanical Evidence Substrate — Structured Artifacts Replace Prose Narration

**Classification:** Hybrid. The substrate (canonical schema + helper script + plan-edit-validator extension) is Mechanism — `adapters/claude-code/schemas/evidence.schema.json` locks the format, `adapters/claude-code/scripts/write-evidence.sh` captures outcomes deterministically, and `adapters/claude-code/hooks/plan-edit-validator.sh` recognizes both the new `<task-id>.evidence.json` artifacts and the legacy prose `<plan>-evidence.md` blocks. The discipline of preferring mechanical evidence for `Verification: mechanical` (or purely structural) tasks and escalating to prose for genuinely-novel work is Pattern — the agent self-applies it.

**Ships with:** Tranche B of `docs/plans/architecture-simplification.md` (parent: ADR 026 simplification arc). Cross-references Build Doctrine Principle 7 ("Visibility lives in artifacts, not narration") at `build-doctrine/doctrine/01-principles.md`.

## Why this rule exists

Until 2026-05-05 every task-verification artifact in the harness was a prose evidence block — paragraphs of free-form text the LLM had to read and judge. The format imposed two costs that compounded across long plans:

- **Closure cost.** Validating "is this evidence sufficient?" required parsing prose. The plan-evidence-reviewer agent and the closure-validator hook both spent context budget reading paragraphs to extract claims a structured field could have surfaced in one jq query.
- **Narration drift.** Prose evidence drifted from "what the mechanical check actually showed" to "what the builder claims the check showed." The artifact was the agent's report, not the system's recording. Build Doctrine Principle 7 calls this out specifically: system state should be readable without asking the system what happened.

The mechanical-evidence substrate replaces the default. Each task's evidence is a JSON file (locked schema, six required fields) capturing each mechanical check's outcome with a passed/failed boolean plus optional command + detail string. A bash check determines whether evidence is sufficient — no LLM reading required. Prose evidence becomes the escalation path: novel-judgment tasks where mechanical checks cannot fully express the verification rationale add a `prose_supplement` field, but the mechanical fields are still required.

## When to use mechanical evidence (default)

Use the mechanical-evidence substrate (helper script + JSON artifact) when ANY of these are true:

- The plan task's `Verification:` field is `mechanical` (per Tranche D's risk-tiered verification — the default for structural / non-runtime / non-novel work).
- The work is purely structural: file edits, hook updates, schema authoring, prompt updates, sync-to-mirror operations, doc additions where success = "file exists with the expected sections."
- The task has runtime evidence expressible in the canonical replayable formats (test, playwright, curl, sql, file) — capture them in the `runtime_evidence` array of the JSON artifact.
- The task is one of N parallel sweep sub-tasks where consistency across artifacts matters (a JSON ledger surfaces inconsistencies; a folder of prose blocks does not).

## When to use prose evidence (escalation)

Use the legacy prose evidence block (`<plan>-evidence.md`) — OR populate the `prose_supplement` field on a JSON artifact — when ANY of these are true:

- The task involves genuinely novel judgment that mechanical checks cannot fully express (e.g., "did the rewrite of this rule capture the user's intent?").
- The task's verification depends on adversarial review whose outcome is qualitative (the agent reviewed the diff and its summary IS the evidence).
- The task discovered something during build that materially changes downstream work and the discovery itself is the load-bearing record.

When in doubt, default to mechanical. The substrate accepts a `prose_supplement` field for escalation; the legacy prose-only path remains valid (the plan-edit-validator hook accepts both formats) but the mechanical artifact is the new convention for everything that fits.

## How the helper script integrates with task-verifier

The `task-verifier` agent (`adapters/claude-code/agents/task-verifier.md`) decides the verdict; the helper script captures the mechanical-check inputs the agent reasons over.

A typical invocation:

```bash
bash adapters/claude-code/scripts/write-evidence.sh capture \
  --task 3.2 \
  --plan docs/plans/architecture-simplification-tranche-b-mechanical-evidence.md \
  --check exists:adapters/claude-code/schemas/evidence.schema.json \
  --check schema-valid:adapters/claude-code/schemas/evidence.schema.json \
  --check files-in-commit
```

This:

1. Runs each `--check` in sequence, capturing `passed`, `detail`, `command`, and `exit_code`.
2. Auto-discovers `files_modified` from `git diff-tree HEAD` (or `git ls-tree HEAD` for the initial commit).
3. Writes a fully-validated JSON artifact to `<plan-dir>/<plan-slug>-evidence/<task-id>.evidence.json` (sibling-directory layout — keeps the active plan file unchanged when many task evidences accumulate).
4. Exits `0` on PASS, `1` on FAIL, `1` on INCOMPLETE, `2` on usage error.

Supported `--check` specs (full list in script header):

| Spec | What it runs | When passes |
|---|---|---|
| `typecheck` | `npm run typecheck` (falls back to `npx tsc --noEmit`) | exit code 0 |
| `lint` | `npm run lint` | exit code 0 |
| `test:<name>` | `npm test -- <name>` | exit code 0 |
| `files-in-commit` | `git diff-tree HEAD` (or `git ls-tree HEAD` initial-commit fallback) | non-empty file list |
| `schema-valid:<path>` | `jq empty <path>` | the file is valid JSON |
| `exists:<path>` | bash `[ -e <path> ]` | path exists |
| `command:<cmd>` | arbitrary command via `eval` | exit code 0 |

The agent picks the checks that correspond to the task's claims. For a hook-update task, `exists:<hook>.sh` + `command:<hook>.sh --self-test` is typical. For a runtime task, `runtime_evidence` entries are added separately (the helper does not auto-run these — the agent records them after replaying the verification).

## Schema enforcement

The schema is at `adapters/claude-code/schemas/evidence.schema.json` (JSON Schema draft 2020-12, self-validating against the meta-schema). Required fields: `task_id`, `verdict` (`PASS|FAIL|INCOMPLETE`), `commit_sha`, `files_modified`, `mechanical_checks`, `timestamp`. Optional: `runtime_evidence`, `prose_supplement`, `verifier`, `plan_path`, `schema_version` (defaults to 1).

Every artifact the helper script writes is well-formed against the schema by construction (the script uses `jq -n` with typed inputs to compose the output). Manual artifacts written by other tooling SHOULD validate via `jq` or `ajv`; the harness does not currently enforce schema-validity at session-end (an opportunity for Tranche D / E follow-up work).

## Backward compatibility with prose evidence

`adapters/claude-code/hooks/plan-edit-validator.sh` accepts BOTH:

- The legacy prose evidence block (`<plan>-evidence.md` with `EVIDENCE BLOCK`, `Task ID:`, and `Runtime verification:` lines per the existing `task-verifier` prose convention).
- The new structured artifact (`<plan-dir>/<plan-slug>-evidence/<task-id>.evidence.json`).

For the new format, the validator's freshness check (file mtime within 120s of the plan edit attempt) applies to the JSON artifact's mtime; the substance check parses the JSON and verifies `task_id` matches the task being checked.

Existing closed plans with prose evidence remain valid — no migration is required. New plans default to the structured format; the `task-verifier` agent's prompt (extended in Tranche B Task 5) prefers `write-evidence.sh capture` over prose authorship when the task's verification level is mechanical.

## Cross-references

- **Schema:** `adapters/claude-code/schemas/evidence.schema.json` — canonical structured-evidence shape.
- **Helper script:** `adapters/claude-code/scripts/write-evidence.sh` — captures mechanical-check outcomes deterministically; `--self-test` covers 9 scenarios.
- **Hook extension:** `adapters/claude-code/hooks/plan-edit-validator.sh` — recognizes both prose and structured evidence; `--self-test` extended with mechanical-evidence regression coverage.
- **Agent extension:** `adapters/claude-code/agents/task-verifier.md` — section "Helper-script preference" added in Tranche B Task 5.
- **Build Doctrine source:** `build-doctrine/doctrine/01-principles.md` Principle 7 — "Visibility lives in artifacts, not narration."
- **Parent plan:** `docs/plans/architecture-simplification-tranche-b-mechanical-evidence.md` (this Tranche B).
- **Sibling tranches consuming the substrate:**
  - Tranche D — risk-tiered verification (per-task `Verification: mechanical|review|runtime` field).
  - Tranche E — deterministic close-plan procedure (consumes structured evidence to validate plan closure).

## Enforcement summary

| Layer | What it enforces | File |
|---|---|---|
| Schema | Locked shape of structured evidence (six required fields + optional escalation fields) | `adapters/claude-code/schemas/evidence.schema.json` |
| Helper script | Deterministic capture of mechanical-check outcomes; PASS/FAIL/INCOMPLETE verdict by aggregation | `adapters/claude-code/scripts/write-evidence.sh` |
| Rule (this doc) | When to use mechanical vs prose; helper-script invocation; schema enforcement; backward compatibility | `adapters/claude-code/rules/mechanical-evidence.md` |
| Hook | Recognizes both prose and structured artifacts at plan-edit time | `adapters/claude-code/hooks/plan-edit-validator.sh` |
| Agent | Prefers helper script for mechanical / structural tasks | `adapters/claude-code/agents/task-verifier.md` |
| Enforcement-map row | Inventory entry pointing at the substrate | `adapters/claude-code/rules/vaporware-prevention.md` |

The schema + helper + hook are mechanical (cannot be subverted by editing the rule body). The agent extension is Pattern (the agent self-applies the preference). Together they implement Build Doctrine Principle 7 at the harness level.

## Scope

This rule applies in any project whose Claude Code installation has the mechanical-evidence substrate installed (schema + helper script + plan-edit-validator extension). The mirror at `~/.claude/` is synced from `adapters/claude-code/` via `install.sh`. Downstream projects automatically receive the substrate; no per-project opt-in is required. Plans written before Tranche B continue to validate via the prose evidence path — the new substrate is purely additive.
