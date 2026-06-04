# Plan: Inline PR-body validator gate (HARNESS-GAP-43 / FM-030)

Status: COMPLETED
<!-- Closed 2026-06-04 by stale-ACTIVE-plan cleanup. Verified on master HEAD: pr-template-inline-gate.sh wired in settings.json.template Stop chain, FM-030 in failure-modes.md, harness-architecture.md inventory row, HARNESS-GAP-43 absorbed. Shipped eda6f2b, reconverged PR #35 (94cb114). Dispatch never ran task-verifier. -->
Mode: code
Execution Mode: solo
Backlog items absorbed: harness-gap-43-pr-template-inline-body
acceptance-exempt: true
acceptance-exempt-reason: harness-internal mechanism; 11-scenario `--self-test` is the acceptance artifact, plus 3/3 sibling vaporware-volume-gate regression + 15/15 canonical validator regression PASS
prd-ref: n/a — harness-development
tier: 1
rung: 1
architecture: build-harness-infrastructure
frozen: true

## Goal

Close the inline-body PR-template validation gap. The existing
`pre-push-pr-template.sh` git hook validates `.pr-description.md` files
and commit messages but never the inline `--body` argument that AI
sessions naturally use via `gh pr create --body "$(cat <<'EOF' ... EOF)"`.
The server-side `PR Template Check` workflow is currently the first place
the body gets validated, generating ~19 failure emails/week and a
constant 2-push amend cycle.

Ship a sibling PreToolUse `Bash` hook (`pr-template-inline-gate.sh`) that
intercepts `gh pr create` / `gh pr edit`, parses the inline body from
`--body`, `--body=`, `--body-file`, and heredoc forms, and pipes it
through the same canonical validator library used by CI + pre-push hook.

## Scope

- IN: new sibling hook `pr-template-inline-gate.sh`; live-mirror sync;
  `settings.json.template` + `~/.claude/settings.json` wiring;
  `FM-030` catalog entry; `HARNESS-GAP-43` backlog entry; harness-architecture
  inventory row; this plan file; `.pr-description.md` for the PR.
- OUT: changes to canonical validator (`.github/scripts/validate-pr-template.sh`)
  — gate is a pure consumer of the existing library, same regex, same stderr.
- OUT: changes to the CI workflow (`.github/workflows/pr-template-check.yml`).
- OUT: changes to `pre-push-pr-template.sh` (sibling git-hook side covers
  `.pr-description.md` + commit-message paths; orthogonal to inline body).
- OUT: changes to `vaporware-volume-gate.sh` (sibling, not extension —
  decision documented in commit message; would push it past 500 lines).

## Tasks

- [x] 1. Author `adapters/claude-code/hooks/pr-template-inline-gate.sh`
  with body-extraction (parameter-expansion-based for multi-line) +
  validator sourcing + 11-scenario `--self-test` flag.
  Verification: mechanical (self-test 11/11 PASS).
- [x] 2. Sync to live mirror at `~/.claude/hooks/pr-template-inline-gate.sh`
  via `cp` + `chmod +x`; verify byte-identical via `diff -q`.
- [x] 3. Wire the hook in `adapters/claude-code/settings.json.template`
  immediately after `vaporware-volume-gate.sh`. Mirror the wiring to
  `~/.claude/settings.json`. Verify both files are valid JSON via
  `jq empty`.
- [x] 4. Add `FM-030` entry to `docs/failure-modes.md` per six-field
  schema (Symptom / Root cause / Detection / Prevention / Example /
  Discriminator / Recovery).
- [x] 5. Add `HARNESS-GAP-43` entry to `docs/backlog.md` (numbering note
  explaining label-vs-number disambiguation against existing GAP-40).
  Refresh `Last updated:` line.
- [x] 6. Add inventory row to `docs/harness-architecture.md` immediately
  after the existing `vaporware-volume-gate.sh` row.
- [x] 7. Self-validate: bad-body invocation BLOCKs (exit 1, structured
  remediation); valid-body invocation ALLOWs (exit 0, silent).
  Document outputs in commit message body.

## Files to Modify/Create

- `adapters/claude-code/hooks/pr-template-inline-gate.sh` — new hook (528 lines).
- `~/.claude/hooks/pr-template-inline-gate.sh` — live mirror (byte-identical).
- `adapters/claude-code/settings.json.template` — wire the new hook.
- `~/.claude/settings.json` — wire in live mirror.
- `docs/failure-modes.md` — add FM-030.
- `docs/backlog.md` — add HARNESS-GAP-43; refresh Last updated.
- `docs/harness-architecture.md` — add inventory row.
- `docs/plans/pr-template-inline-gate-2026-05-24.md` — this plan file (self-claim).
- `.pr-description.md` — PR body for `gh pr create --body-file`.

## In-flight scope updates

- 2026-05-24: `adapters/claude-code/hooks/harness-hygiene-scan.sh` — added `.pr-description.md` to `is_path_shape_exempt()` allowlist; the file is a per-PR transient consumed by `gh pr create --body-file`, naturally repeats PR-shape domain vocabulary (Template / Inline / Check), and the Layer-2 cluster heuristic was false-firing on legitimate prose. Same logic as the other root-level prose-file exemptions (README, CONTRIBUTING, etc.).
- 2026-05-24: `~/.claude/hooks/harness-hygiene-scan.sh` — byte-identical mirror sync (per harness-maintenance.md two-layer-config rule).

## Testing Strategy

- Mechanical: `bash adapters/claude-code/hooks/pr-template-inline-gate.sh --self-test`
  must show `all 11 self-tests passed`.
- Regression: `bash adapters/claude-code/hooks/vaporware-volume-gate.sh --self-test`
  must still show `all 3 self-tests passed`.
- Regression: `bash .github/scripts/validate-pr-template.sh --self-test`
  must still show `Self-test passed (15 cases)`.
- Self-validation: synthetic bad-body invocation must BLOCK (exit 1);
  synthetic valid-body invocation must ALLOW (exit 0, silent output).
- End-to-end: this PR's own first push must pass the server-side
  `PR Template Check` workflow (the new gate validates this PR's
  `.pr-description.md` via Path 1 — the `--body-file` form).
