# Plan: Harness Principles Doc + Warn-Mode Compliance Gate
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan; the "user" is the maintainer and the gate's `--self-test` PASS + a real warn-mode log entry are the acceptance artifacts. No product UI surface exists.
tier: 1
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development
owner: Misha
target-completion-date: 2026-05-27

## Goal

Consolidate the operating guidance that was scattered across `rules/*.md`, ADRs,
`docs/conventions/`, CLAUDE.md, and the agent's feedback memories into ONE canonical
decision-level reference (`rules/principles.md`) a fresh-machine Claude can use to make
decisions without Misha — and ship the closest *real* mechanical companion to the
"pre-send gate" Misha asked for. The literal pre-send gate is impossible (Claude Code has
no pre-send/PostMessage hook); the honest substitute is a Stop hook that scans the final
assistant message for operating-rule anti-patterns, warn-mode first. This closes tracker
item A27 (principles-doc authoring).

## Scope

- IN: `rules/principles.md` (Operating Rules 0-7 + decision principles + design philosophy
  + enforcement map); `hooks/principles-compliance-gate.sh` (warn-mode Stop hook, 10-scenario
  self-test); Stop-chain wiring (template + live settings); architecture-doc update; memory
  cross-links.
- OUT: flipping the gate to block-mode (deferred until false-positive rate is calibrated);
  wiring `continuation-enforcer.sh` (separate A25 item, found unwired during this work);
  fixing the stale `core.hooksPath` worktree pointer (harness-friction #3, separate item);
  any change to the 6 pending discoveries surfaced at session start.

## Tasks

- [ ] 1. Ship principles.md + principles-compliance-gate.sh, wire into the Stop chain (template + live), update the architecture doc, and update the three memory cross-links — Verification: mechanical

## Files to Modify/Create

- `docs/plans/harness-principles-doc-and-gate.md` — this plan (self-claim for the scope gate).
- `adapters/claude-code/rules/principles.md` — NEW: the canonical principles doc.
- `adapters/claude-code/hooks/principles-compliance-gate.sh` — NEW: warn-mode Stop hook + self-test.
- `adapters/claude-code/settings.json.template` — wire the hook into the Stop chain.
- `docs/harness-architecture.md` — add hook-table row, rules-table row, Stop-chain list entry; bump Last-updated.

## Assumptions

- Claude Code exposes no pre-send/PostMessage hook event (verified: settings matchers show only
  PreToolUse/PostToolUse/Stop/SessionStart/UserPromptSubmit/Task* — no outbound-message surface),
  so the Stop-hook final-message scan is the closest real mechanical surface.
- The live `~/.claude/` mirror is a per-machine copy synced from the repo (Windows install.sh
  copies, not symlinks); both must be updated and kept byte-identical.
- "Misha" in prose is not denylisted (only `mishanovini`/`MishaPT`/user-path patterns are).

## Edge Cases

- No transcript / no `jq` → hook is a no-op (exit 0), like its sibling Stop hooks.
- Final message contains internal newlines → extracted via base64 round-trip so the full last
  message is scanned, not just its last line.
- Rule 3 (multi-option question) is too heuristic to block reliably → warn-only even in block-mode.
- Completion claims that DO cite a SHA or "master" → exempt from the Rule 5 detector (a real "done").
- Harness-dev session editing the patterns themselves → `PRINCIPLES_GATE_DISABLE=1` escape hatch.

## Testing Strategy

- `principles-compliance-gate.sh --self-test` → 10/10 scenarios pass (clean, R4×2, R5 detect + 2 exempt,
  R7 detect + exempt, R3 detect + plain).
- Full live path: feed a synthetic transcript via stdin → confirm last-message extraction, detection
  (R4/R5/R7), exit 0 in warn-mode, and a real entry appended to `~/.claude/state/principles-gate-warnings.log`.
- `jq -e` on live + template settings.json confirms the hook is wired in the Stop chain.
- `diff -q` confirms repo ↔ live-mirror byte-identical for both new files.

## Walking Skeleton

The thinnest end-to-end slice: a transcript with a violating final message → the wired Stop hook
extracts it → detects the anti-pattern → writes a warn-log line → exits 0 (warn-mode). This slice was
exercised live during the build and produced real log entries.

## Decisions Log

### Decision: pre-send gate reframed to a Stop-hook final-message scan
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** Stop hook scanning the final assistant message in the transcript, warn-mode default.
- **Alternatives:** literal PreToolUse on a `SendUserMessage` tool (no such tool/hook exists — impossible); wait for Misha (rejected — explicit "ship today, no deferral" + Rule 1).
- **Reasoning:** Claude Code has no pre-send/PostMessage hook; the final-message scan is the closest real surface and matches the Gen-6 narrative-integrity hook family. Named honestly in the doc per Rule 0/7.
- **To reverse:** delete the hook + unwire from settings; revert the doc rows.

## Definition of Done

- [ ] Task 1 verified
- [ ] principles.md present in repo + live mirror (grep-able on master)
- [ ] gate self-test 10/10 + a real warn-mode log entry produced
- [ ] memory cross-links updated
- [ ] PR merged to master

## Systems Engineering Analysis

n/a — `Mode: code`, tier 1 harness-infrastructure work-shape (`build-harness-infrastructure`); the
self-test + mechanical-evidence checks replace the 10-section design analysis.
