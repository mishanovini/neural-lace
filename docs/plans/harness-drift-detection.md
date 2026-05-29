# Plan: Harness-internal cross-repo drift detection (replaces mirror Action)

Status: ACTIVE
Execution Mode: orchestrator
Mode: code
frozen: true
tier: 1
rung: 0
architecture: harness-infrastructure
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: harness-internal mechanism; verification is the self-tests passing on each component (`sync.sh --self-test`, `check-cross-repo-drift.sh --self-test`, `cross-repo-drift-warn.sh` exit 0 on no-config and rc=0/silent on unverifiable).
Backlog items absorbed: none

## Goal

Replace the reverted cross-repo mirror Action (ADR-044, PR #33) with three small
harness-internal drift-detection components. The mirror Action's cross-account
PAT operational burden was disproportionate to the actual use case (every NL
push happens through Claude Code with the harness loaded), so a local check
covers the steady-state need. Drift coverage shifts from "push automation" to
"detection at every push + periodic backstop + session-start surface."

## Scope
- IN:
  - Extend `adapters/claude-code/sync.sh` with post-push master-SHA verification.
  - New `adapters/claude-code/scripts/check-cross-repo-drift.sh` periodic poller
    (scheduled-task-friendly; honors a per-machine pairs config + optional ntfy).
  - New `adapters/claude-code/hooks/cross-repo-drift-warn.sh` SessionStart hook
    that surfaces drift at session start (warn-only, never blocks).
  - Wire the new SessionStart hook into `settings.json.template`.
  - Ship `adapters/claude-code/examples/cross-repo-drift-pairs.example.txt`
    as the format reference (real values stay in `~/.claude/local/` per
    harness-hygiene).
- OUT:
  - Deleting `sync.sh` (it's kept and extended).
  - Reverting the Reverted ADR-044 (separate PR #33 already did the workflow
    removal).
  - Wiring the scheduled-task entry on this machine (per-machine operator
    action; this PR ships the script the operator wires).
  - Revoking MIRROR_PAT secrets (operator action — Misha via GitHub UI).
  - Reconverging PT ↔ personal SHA (separate Phase 3 step).

## Tasks
- [ ] 1. Ship the 3 drift-detection components + example config + SessionStart wiring — Verification: mechanical (each component's `--self-test` passes; jq validates `settings.json.template`; the new SessionStart hook exits 0 on no-config silent no-op).

## Files to Modify/Create
- `adapters/claude-code/sync.sh` — extend with post-push verification
- `adapters/claude-code/scripts/check-cross-repo-drift.sh` — NEW
- `adapters/claude-code/hooks/cross-repo-drift-warn.sh` — NEW
- `adapters/claude-code/examples/cross-repo-drift-pairs.example.txt` — NEW
- `adapters/claude-code/settings.json.template` — wire the new SessionStart hook

## Testing Strategy
- Mechanical: `bash sync.sh --self-test` (7 scenarios), `bash check-cross-repo-drift.sh --self-test` (7 scenarios), `bash cross-repo-drift-warn.sh` (silent no-op without config, exit 0). All three pass locally.
- Runtime: on first real push through `sync.sh` on master, the post-push verify step will print a TREE-HASH list and either confirm content convergence or flag drift.

## Amendments

### 2026-05-29 — tree-hash (content) comparison, not commit-SHA comparison

Under the divergent-history-identical-content posture adopted 2026-05-29 (one
repo canonical; the other receives the same content via cherry-pick + non-force
direct push), the two repos are EXPECTED to have different commit SHAs forever
— each cherry-pick produces a distinct commit object on the receiving side.
The original drift scripts compared `.commit.sha` (the commit SHA the branch
tip points at), which would false-positive on every invocation under this
posture.

Fix landed: all three components now compare `.commit.commit.tree.sha` (the
TREE hash the master tip points at). Tree-hash equivalence is the correct
content-equivalence check; identical content with different history is the
target state and reports OK. Sibling self-test scenarios added:
- `check-cross-repo-drift.sh` ST6 (same-tree-different-commit → rc 0) +
  ST7 (different-tree → rc 1), using a mock `gh` on PATH.
- `sync.sh` T7 (mock-gh tree-hash equivalence → rc 0 with "tree hashes match"
  in output).

Operator-facing prose throughout (log lines, warning banners, ntfy bodies,
docstrings) updated from "SHA" / "commit SHA" → "tree hash" / "content hash"
so the surface matches the semantics.

## Walking Skeleton

n/a — three independent additive components.

## Acceptance Scenarios

n/a — acceptance-exempt (harness-internal; downstream operator wires the
scheduled task on their machine; SessionStart surface is opt-in via the
per-machine config file).
