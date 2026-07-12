# Plan: SECRET-SCAN-CI-BACKSTOP-01 — CI backstop for `--no-verify` secret bypass (design-skip)
Status: COMPLETED
Execution Mode: direct
Mode: design-skip
Backlog items absorbed: SECRET-SCAN-CI-BACKSTOP-01
acceptance-exempt: true
acceptance-exempt-reason: Harness-dev CI-config change with no product user; the deliverable is a new CI workflow whose own oracle (seeded-fixture branch -> RED, clean branch -> GREEN) is the acceptance artifact, validated locally against the extracted scan logic since Actions cannot run live from this environment.
tier: 1
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Why design-skip

The new file is `.github/workflows/secret-backstop.yml`, which trips the
systems-design-gate path pattern. The change is genuinely low-risk and
non-novel: it invokes two ALREADY-SHIPPED, already-battle-tested scripts
(`adapters/claude-code/hooks/pre-push-scan.sh`,
`adapters/claude-code/hooks/harness-hygiene-scan.sh`) against a diff range,
using the EXACT same diff-range-synthesis pattern already proven in
`.github/workflows/server-side-enforcement.yml`'s `credential-scan` and
`harness-hygiene` jobs (added independently, pre-F.3). No new pattern list,
no new external dependency beyond what those jobs already use (`git`,
`grep`, `bash` — all pre-installed on `ubuntu-latest`), no new job
dependency graph, no infra/secrets/credentials touched. It reverts in one
commit (delete the file). This is the "CI-config change with no systems-
design surface" case the design-skip hatch exists for — same class as
`nl-finding-030-crlf-validator-skip.md`.

## Change

- New `.github/workflows/secret-backstop.yml`: a standalone, independently
  named CI check (own required-status-check surface) that re-invokes
  `pre-push-scan.sh` (credential regexes) and `harness-hygiene-scan.sh`
  (denylist + heuristics) against the push/PR diff range. Provenance
  comment block explains why this deliberately duplicates
  `server-side-enforcement.yml`'s existing coverage of the same two
  scripts (defense-in-depth: two independent workflow files calling the
  same underlying scanners, so removing/misconfiguring one doesn't remove
  all CI-side secret coverage) rather than forking the pattern list.
- New `adapters/claude-code/tests/secret-backstop-fixture-check.sh`: local
  validation harness proving the oracle (seeded fixture secret -> scanner
  exit 1; clean diff -> scanner exit 0) since GitHub Actions cannot be run
  live from this environment. Runs the same two scripts the workflow
  invokes, against a real temp git repo with a synthesized push-diff range
  — same invocation shape as the workflow's own steps.
- `docs/backlog.md`: SECRET-SCAN-CI-BACKSTOP-01 entry marked
  dispositioned-in-progress with the branch ref.

## Goal

Give the operator's F.3 disposition ("ACCEPT-DOCUMENTED" for the
`git push --no-verify` bypass on `secret-hygiene-prepush`, conditioned on a
genuine CI backstop existing) a concrete, independently-named CI artifact,
so a bypassed local scan cannot ship a secret to the remote unnoticed.

## Scope
- IN: the new workflow file, the local fixture-check test script proving
  the RED/GREEN oracle, YAML-validity check, backlog disposition update.
- OUT: removing or refactoring `server-side-enforcement.yml`'s existing
  `credential-scan`/`harness-hygiene` jobs (they stay — this is additive
  defense-in-depth, not a replacement); changing the pattern lists
  themselves; resolving the still-open "should --no-verify be disallowed
  entirely for secrets" question (that was the F.3 disposition already
  made — ACCEPT-DOCUMENTED — not reopened here); wiring branch-protection
  required-status-checks in GitHub's settings (operator-side GitHub admin
  action, outside repo-content scope).

## Tasks
- 1. Write `.github/workflows/secret-backstop.yml` invoking
  `pre-push-scan.sh` + `harness-hygiene-scan.sh` on the diff range. — DONE.
- 2. Write `adapters/claude-code/tests/secret-backstop-fixture-check.sh`
  proving the oracle locally (planted fake AWS key -> RED; clean diff ->
  GREEN). — DONE.
- 3. Validate the new workflow YAML with `js-yaml` (via `npx`). — DONE.
- 4. Mark the backlog entry dispositioned-in-progress with the branch ref. — DONE
  (docs/backlog.md SECRET-SCAN-CI-BACKSTOP-01 entry; updated to merged state at close).

## Files to Modify/Create
- `.github/workflows/secret-backstop.yml` — new CI workflow.
- `adapters/claude-code/tests/secret-backstop-fixture-check.sh` — new local
  oracle-validation script.
- `docs/backlog.md` — SECRET-SCAN-CI-BACKSTOP-01 entry disposition update.
- `docs/plans/secret-scan-ci-backstop-skip.md` — this design-skip record.

## Assumptions
- `ubuntu-latest` runners ship `bash`, `git`, `grep` (all already relied on
  by `server-side-enforcement.yml`'s identical invocation pattern).
- The oracle ("seeded fixture secret in a test branch -> CI RED; normal
  branch -> GREEN") is satisfied by the LOCAL fixture-check script running
  the exact same scanner invocations the workflow performs, since this
  environment cannot dispatch a live GitHub Actions run. The workflow YAML
  structure is additionally validated for well-formedness via `js-yaml`.

## Edge Cases
- A push/PR whose diff touches zero files: `harness-hygiene-scan.sh` step
  short-circuits with "no added/modified files in diff range — nothing to
  scan" and exits 0 (mirrors `server-side-enforcement.yml`'s existing
  behavior).
- A branch-deletion push (`local_sha == 0000...0`): `pre-push-scan.sh`
  itself already handles this (skips the loop iteration), unchanged here.
- First commit in a new repo / orphan branch: `pre-push-scan.sh` already
  falls back to the empty-tree SHA as the diff base (pre-existing logic,
  not touched by this change).

## Testing Strategy
- `bash adapters/claude-code/tests/secret-backstop-fixture-check.sh` — two
  scenarios: (1) a temp repo with a planted flagless-shape fake AWS key
  (`AKIAIOSFODNN7EXAMPLE`, AWS's own public documentation placeholder —
  matches `pre-push-scan.sh`'s `AKIA[0-9A-Z]{16}` regex structurally but is
  not a live credential) committed on a branch — asserts `pre-push-scan.sh`
  exits 1 and names the file; (2) the same repo with a clean commit —
  asserts exit 0. Both scenarios also exercise
  `harness-hygiene-scan.sh --full-tree` against the same temp repo for the
  denylist layer.
- `node -e "require('js-yaml').load(...)"` (via `npx --yes js-yaml`) against
  `secret-backstop.yml` to confirm it parses as valid YAML with the
  expected job/step shape (no GitHub Actions run available in this
  environment, so this is the structural-validity substitute).

## Walking Skeleton
Walking Skeleton: n/a — harness-internal CI-config change with no UI→API→DB
layers; the fixture-check script's RED/GREEN oracle is the end-to-end proof
that the workflow's own logic (extracted to run identically outside Actions)
behaves correctly.

## Decisions Log

**DEC-1 (reversible — decide-and-go): keep this as a SEPARATE workflow file
rather than adding jobs to `server-side-enforcement.yml`.** The backlog
entry explicitly asks for "its own workflow file secret-backstop.yml" even
though `server-side-enforcement.yml` already runs the same two scripts on
the same trigger shape. Options: (a) add nothing new, just re-label the
existing jobs as satisfying the item; (b) create the separate file as
asked. **Chose (b).** A dedicated, independently-named required-status-check
is a genuine defense-in-depth improvement over folding into an
already-multi-purpose workflow (single point of YAML-syntax-error failure
currently takes down 5 unrelated jobs at once); it also makes the F.3
disposition's compensating control legible as its own named CI artifact
the operator can point to. Revert is deleting one file. Documented the
overlap explicitly in the new file's header comment so a future reader
does not mistake it for accidental duplication/fork of the pattern list.

**DEC-2 (reversible — decide-and-go): use AWS's own public documentation
placeholder key (`AKIAIOSFODNN7EXAMPLE`) as the planted fixture secret
rather than a randomly-generated flagless-shape string.** It is guaranteed
never to be a live credential (it is AWS's canonical SDK-documentation
example, reused deliberately across the industry for this exact purpose),
while still matching the `AKIA[0-9A-Z]{16}` shape the scanner's regex
requires — satisfying the environment's "real flagless shape" fixture
convention without inventing a novel string that could theoretically
collide with something real.

## Definition of Done
- `secret-backstop.yml` created, YAML-valid (js-yaml parse succeeds).
- Local fixture-check script proves: planted-secret branch -> underlying
  scanner exit 1 (RED); clean branch -> exit 0 (GREEN).
- Backlog entry marked dispositioned-in-progress with this branch's ref.
- Branch pushed (per environment discipline — no master push/PR/checkbox
  flips from this session).

## Completion Report (2026-07-12, closure session)

All deliverables merged to master in `f25132a` (verified master-ancestor of
HEAD `4f861df` at close): `.github/workflows/secret-backstop.yml`,
`adapters/claude-code/tests/secret-backstop-fixture-check.sh`, backlog
disposition, manifest entries. Definition of Done re-verified at close:

- Fixture-check oracle re-run at master state:
  `secret-backstop-fixture-check: 3 passed, 0 failed` — planted AWS-key
  fixture → `pre-push-scan.sh` exit 1 naming the file (RED); clean diff →
  exit 0 (GREEN); denylist fixture → `harness-hygiene-scan.sh` exit 1 (RED).
- Workflow YAML present and previously js-yaml-validated (Task 3).
- Backlog entry SECRET-SCAN-CI-BACKSTOP-01 updated at close from
  dispositioned-in-progress to merged (`f25132a`).
- Remaining operator-side item (unchanged, out of repo-content scope):
  wire `secret-backstop` into GitHub branch-protection
  required-status-checks (repo-admin action).

Closure path: manual equivalent of close-plan.sh — the script exits 2
("no tasks found") on design-skip prose task records; report first,
Status flip last, archive, pathspec-limited commit. Backlog reconciliation
(absorbed item SECRET-SCAN-CI-BACKSTOP-01) satisfied by the merged-state
disposition note.
