# Salvage manifest — main-checkout triage 2026-06-09

This directory holds byte-exact copies of the 26 files that the
harness-hygiene pre-commit scanner flagged (downstream-project identifiers /
machine-local absolute paths) during the main-checkout salvage of 2026-06-09.
They were moved here UNMODIFIED because `docs/sessions/` non-date-prefixed
paths are the scanner's designated instance-artifact exemption — no content
was anonymized, no gate was bypassed (`--no-verify` was NOT used).

Each file's path under this directory mirrors its original repo-relative path.
The originals remain on disk at their original paths as untracked files.

## Categories

1. **Workstreams consolidation plan + evidence (closure-critical)** —
   `docs/plans/workstreams-consolidation-2026-06-08.md` +
   `docs/plans/workstreams-consolidation-2026-06-08-evidence.md`.
   6/6 verified, acceptance-passed. Also backed up at
   `workstreams-coordination/plan-backups`. The orchestrator completes plan
   closure from master using these copies.

2. **2026-06-04 stale-plan-cleanup renames (Status flips + closure notes)** —
   the five `docs/plans/archive/...` / `docs/plans/deferred/...` copies.
   Content = master's `docs/plans/<same-name>.md` plus 2-3 annotation lines
   (Status: COMPLETED/DEFERRED + closure comment). The flagged lines are
   LEGACY content already on master (verified: master's own copy of
   `doctrine-scoping-rules-authoring.md` trips the same scanner); the rename
   re-triggered a whole-file scan. To re-land the archival moves on master,
   apply the Status flips from these copies and `git mv` per plan-lifecycle.

3. **Discovery / review / handoff docs** — 3 discoveries (2026-06-02
   flat-md-skills, 2026-06-09 no-event-sourced-text-repair, 2026-06-09
   scope-gate-cwd), `docs/reviews/2026-06-09-workstreams-rebuild-residuals.md`,
   `docs/handoffs/cross-machine-context-2026-05-24.md`,
   `docs/plans/archive/cross-machine-context-handoff-2026-05-24.md`.
   These reference downstream project names; anonymize the flagged lines
   before landing any of them on master (operator call — deliberately NOT
   done unilaterally during salvage to keep the preserved copies exact).

4. **Operational instance state (not ship-docs)** — `.claude/launch.json`,
   `adapters/claude-code/config/workstreams-state-path`,
   `adapters/claude-code/hooks/conv-tree-heartbeat-hidden.vbs`, and the 10
   `neural-lace/conversation-tree-ui/state/` files (tree-state.json, its 5
   .versions snapshots, before-ws snapshot, audit log, 2 walking-skeleton
   states). Machine-local paths / workstreams node data; belongs in
   operational state, not the harness kit.

## Excluded from salvage entirely (left untracked on disk, junk)

- `neural-lace/conversation-tree-ui/state/tree-state.json.tmp.29296.1780460685822.205083`
- `neural-lace/conversation-tree-ui/state/tree-state.json.tmp.29296.1780460685881.310578`
- `neural-lace/conversation-tree-ui/state/tree-state.json.tmp.31212.1779505820475.213548`
- `.claude/scheduled_tasks.lock` (lock file; its staged deletion is committed)
