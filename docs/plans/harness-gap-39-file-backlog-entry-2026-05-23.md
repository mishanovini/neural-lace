# Plan: File HARNESS-GAP-39 — cloud-orchestrator hook-detector lint
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
tier: 1
rung: 0
architecture: docs-only
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: Docs-only backlog-entry filing; no product-user surface or runtime behavior to verify. The deliverable IS the backlog bullet.

## Goal

File a HARNESS-GAP entry capturing the diagnostic signature observed in PR #24/#25's conv-tree-auto-current fix: a hook wired to an MCP-tool matcher in `~/.claude/settings.json` can ship to master and silently never fire in production because the MCP tool only runs in a cloud-orchestrator session (Dispatch / `claude --remote` / `/schedule` Routines), where local `~/.claude/` hooks are not loaded per Decision 011 / `automation-modes.md` Mode 3. Propose a lint that surfaces the audit-log signature (zero production firings over 14+ days).

## Scope

- IN: a single bullet under `## Open work — substantive deferrals` in `docs/backlog.md` filed as HARNESS-GAP-39, plus header `Last updated:` and `v45` summary touch.
- OUT: implementing the lint (separate plan if/when the gap is picked up); generalizing to non-MCP-tool hook wirings (sibling concern, out of scope here); audit-log convention extension to other hooks (out of scope here).

## Tasks

- [x] 1. File HARNESS-GAP-39 entry in `docs/backlog.md`'s `## Open work — substantive deferrals` section, including problem, evidence, proposed lint behavior, implementation sketch, out-of-scope notes, effort estimate, priority, companion links, and failure-class label. Update the v45 header. — Verification: mechanical

## Files to Modify/Create

- `docs/backlog.md` — add HARNESS-GAP-39 bullet at top of `## Open work` section + v45 header summary.
- `docs/plans/harness-gap-39-file-backlog-entry-2026-05-23.md` — this plan file (self-claiming for the scope-enforcement-gate).

## Assumptions

- The harness's `_is_self_claiming_active_plan` exemption in `scope-enforcement-gate.sh` will allow this commit (this plan file at `docs/plans/*.md` with `Status: ACTIVE` makes the commit pass scope-check; `docs/backlog.md` is governed by this plan's declared scope).
- HARNESS-GAP-39 is the next free number (max observed: GAP-38).
- The conv-tree-auto-current PR #24/#25 evidence (audit log shape) is empirically reproducible by inspecting `~/.claude/logs/conversation-tree-emit.log` — confirmed via grep showing 1463 `--on-spawn` entries, 100% with `sess-st-NN` session IDs.

## Edge Cases

- If a future scope-gate fires from another active plan claiming `docs/backlog.md` (unlikely — no current plan does), the in-flight scope update path applies. Not expected.
- If the v45 header summary collides with another concurrent session's v45 attempt: this commit's header is the source of truth; the other session reconciles.

## Testing Strategy

Mechanical:
- `git diff --cached docs/backlog.md` shows the HARNESS-GAP-39 bullet present and the v45 header line updated.
- `grep -c "HARNESS-GAP-39" docs/backlog.md` returns ≥ 2 (one in header summary, one in the bullet heading).
- `head -3 docs/backlog.md | grep -c "v45"` returns ≥ 1.

No runtime testing — docs-only change.

## Walking Skeleton

This plan IS the walking skeleton: a single backlog bullet, no implementation, no mechanism wiring. The skeleton is the audit trail for filing the gap.

## Decisions Log

(none — single-task docs-only filing)

## Definition of Done

- [x] HARNESS-GAP-39 bullet present in `docs/backlog.md` under `## Open work — substantive deferrals`
- [x] v45 header summary mentions HARNESS-GAP-39
- [x] This plan committed alongside the backlog edit
- [ ] Plan flipped to `Status: COMPLETED` in a follow-up commit (triggers auto-archive via `plan-lifecycle.sh`)
- [ ] Branch pushed; PR opened against master
