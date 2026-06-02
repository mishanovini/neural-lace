# Plan: PR-Health Snapshot Stop-Hook Gate
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
tier: 1
rung: 0
architecture: One Stop-hook presence-gate (`pr-health-snapshot-gate.sh`) + stub rule + `settings.json.template` wiring + enforcement-map/architecture-doc rows. build-harness-infrastructure work-shape — self-test is the acceptance artifact; no product runtime.
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: harness-internal Stop-hook gate; its gh-free --self-test (6/6 PASS) is the acceptance artifact — there is no product user to advocate for.
Backlog items absorbed: none

## Goal

Make the PR-health snapshot a HARD REQUIREMENT at session close (Misha's directive 2026-06-01: "I strongly prefer this to be automatic ... a hard requirement in order for a session to call any of their work completed"). A new Stop-hook gate blocks session wrap unless the final assistant message contains a `## PR Health Snapshot` section covering every active repo. Closes the cross-repo-PR-rot invisibility HARNESS-GAP-42 surfaced (dispatch-session-monitor detects rot but delivers via SendUserMessage to ephemeral sessions the operator never reads).

## Scope
- IN: a new Stop-hook gate; its stub rule; example repo-list config; `settings.json.template` Stop-chain wiring; enforcement-map row; architecture-doc changelog + Stop-table row + Rules-table row; live-mirror sync of hook + rule.
- OUT: live `~/.claude/settings.json` wiring (operator's `install.sh` step — HARNESS-GAP-14 template-vs-live split); building the producer-side `pr-health-snapshot.sh` engine / re-pointing the dispatch-session-monitor (that is the separate option-C producer recommendation, not this gate); resolving the 24 stale ACTIVE plans (HARNESS-GAP-29/30/31).

## Tasks

- [ ] 1. Build `pr-health-snapshot-gate.sh` + gh-free `--self-test`, wire it into the template Stop chain, ship the stub rule + example config + enforcement-map row + architecture-doc rows, mirror hook+rule to `~/.claude/` byte-identical. — Verification: mechanical

## Files to Modify/Create
- `docs/plans/pr-health-snapshot-gate-2026-06-01.md` — this plan.
- `adapters/claude-code/hooks/pr-health-snapshot-gate.sh` — the Stop-hook gate (new).
- `adapters/claude-code/rules/pr-health-snapshot.md` — stub rule (new).
- `adapters/claude-code/examples/active-repos.example.txt` — example repo-list config (new).
- `adapters/claude-code/settings.json.template` — wire the gate into the Stop chain.
- `adapters/claude-code/rules/vaporware-prevention.md` — enforcement-map row.
- `docs/harness-architecture.md` — changelog + Stop-table row + Rules-table row.

## In-flight scope updates
- 2026-06-01: `adapters/claude-code/rules/INDEX.md` — the `rules-index-coverage.sh` golden test requires every rule file to have an INDEX row; the new `pr-health-snapshot.md` rule needs its one-line entry. Surfaced by CI on PR #48.

## Assumptions
- Claude Code has no pre-send/PostMessage hook; the Stop event is the closest real surface for "before a session calls its work complete" (same constraint principles-compliance-gate accepted).
- The gate is a presence-check on the transcript; the agent runs `gh` and emits the snapshot. The gate does not call `gh` itself — keeping it fast and CI-safe.
- The shipped kit's hardcoded fallback is empty (harness-hygiene: no business/org/product identifiers in the kit); the operator's real repo list lives only in the per-machine `~/.claude/config/active-repos.txt`. Empty resolved list → gate no-ops.

## Edge Cases
- No transcript / no `jq` / empty transcript → defensive no-op (exit 0).
- Snapshot present but missing ≥1 repo → allow + stderr warning (don't hard-block on partial coverage).
- Repo name that is a prefix of another (e.g. `web` vs `web-admin`) → boundary-matched, case-sensitive coverage check.
- Self-test must not depend on `gh` auth or a fixture directory → fixtures generated inline (HARNESS-GAP-42 lesson).
- Infinite Stop-loop → shared `lib/stop-hook-retry-guard.sh` 3-retry downgrade-to-warn.

## Testing Strategy
- `bash adapters/claude-code/hooks/pr-health-snapshot-gate.sh --self-test` → 6/6 PASS (present-all-allows, missing-blocks, incomplete-warns, missing-warn-mode-allows, disable-allows, no-transcript-noop).
- Production stdin path exercised directly: complete snapshot → exit 0; missing → exit 2 + JSON `{"decision":"block"}`.
- `jq -e . settings.json.template` → valid JSON after wiring.
- `diff -q` hook + rule against `~/.claude/` mirror → byte-identical.
- CI: the `Hooks self-test` workflow discovers the new hook (it contains `--self-test`) and runs it gh-free → green; no `KNOWN_FAILING_HOOKS` entry needed.

## Walking Skeleton
The thinnest end-to-end slice: a Stop hook that reads `$TRANSCRIPT_PATH`, checks the last assistant message for `## PR Health Snapshot` + repo coverage, and blocks (block-mode) / warns (incomplete) / allows. Verified by the 6-scenario self-test + the two-way production stdin invocation before any wiring.

## Decisions Log

### Decision: block-mode default (not warn-default)
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** ship in block-mode by default; provide `PR_HEALTH_GATE_MODE` env + `~/.claude/local/pr-health-gate-mode` file escape to warn.
- **Alternatives:** warn-default with a soak window (the F7 doc-gate pattern).
- **Reasoning:** Misha explicitly asked for a HARD REQUIREMENT ("a session [cannot] call its work completed" without it). Warn-default would contradict the directive. The retry-guard + disable env prevent lockout.

### Decision: presence-gate (agent emits) vs gate-runs-gh
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** the gate verifies the agent emitted a snapshot in the transcript; the agent runs `gh`.
- **Alternatives:** the gate itself runs `gh pr list` per repo and produces the snapshot.
- **Reasoning:** matches the task spec ("checks whether the session has emitted ... If not, block ... and require the session to produce one"), keeps the gate fast + CI-safe (no gh dependency), and mirrors every sibling Stop gate (presence-check on the agent-uneditable transcript).

### Decision: dedicated stub rule vs editing conv-tree-orchestrator-emit.md
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** new dedicated stub rule `pr-health-snapshot.md`.
- **Alternatives:** bolt a section onto `conv-tree-orchestrator-emit.md` (the directive's "or sibling").
- **Reasoning:** the gate is not conv-tree-related; a dedicated short stub (the `observed-errors-first.md` / `local-edit-authorization.md` convention) is the cleaner sibling and keeps enforcement-in-the-hook.

## Definition of Done
- [ ] Gate built; `--self-test` 6/6 PASS; production stdin path verified both ways.
- [ ] Wired in `settings.json.template`; JSON valid.
- [ ] Stub rule + example config + enforcement-map row + architecture-doc rows shipped.
- [ ] Hook + rule mirrored to `~/.claude/` byte-identical.
- [ ] PR opened, CI green, squash-merged to master, post-merge master CI verified green.

## Completion Report

_Generated by close-plan.sh on 2026-06-01T19:38:24Z._

### 1. Implementation Summary

Plan: `docs/plans/pr-health-snapshot-gate-2026-06-01.md` (slug: `pr-health-snapshot-gate-2026-06-01`).

Files touched (per plan's `## Files to Modify/Create`):

- `adapters/claude-code/examples/active-repos.example.txt`
- `adapters/claude-code/hooks/pr-health-snapshot-gate.sh`
- `adapters/claude-code/rules/pr-health-snapshot.md`
- `adapters/claude-code/rules/vaporware-prevention.md`
- `adapters/claude-code/settings.json.template`
- `docs/harness-architecture.md`
- `docs/plans/pr-health-snapshot-gate-2026-06-01.md`

Commits referencing these files:

```
0090d4b feat(hook): bug-persistence-gate.sh — mechanical enforcement of testing.md rule
03e4883 feat(harness): credentials inventory mechanism for cross-session auth visibility
07691d5 feat(conv-tree): Claude-side event emitter — Dispatch conversations auto-populate the GUI
0909869 feat(work-shapes): Tranche C — work-shape library + rule + integrations
099d4e2 feat(phase-1d-c-2): Task 9 — wire prd-validity-gate + spec-freeze-gate into settings.json (template + live)
0b14705 fix(scope-gate): Windows drive-letter git-dir recognized as absolute (+ HARNESS-GAP-27 docs superseded) (#27)
0be6526 feat(hook): A1 — independent goal extraction (UserPromptSubmit + Stop)
0d6bc43 feat(scope-gate): full-skip scope check during rebase/merge conflict resolution (#26)
0e2c3a6 fix(harness-architecture): restore 8 regressed Phase 1d-C-2/1d-C-3 doc rows + Task 1-3 evidence
0f34109 feat(phase-1d-c-3): Tasks 1+2+6 — Decision 019 + findings-template + findings-ledger rule + docs/findings.md bootstrap
120593c feat(harness): plan-closure-validator gate + /close-plan skill (HARNESS-GAP-16, Phase 1d-H)
15496c3 feat(rules+hook): branch-hygiene + stale-local-branch surfacer (#49)
167a188 feat(harness): class-aware reviewer feedback contract (Mods 1+3)
17db609 docs(1d-E-1): Decision 021 + backlog cleanup + inventory (Phase 1d-E-1 Task 4)
18d3911 feat(incentive-map): proactive shift — catalog agent incentives + counter-incentive prompts
1900089 feat(harness): static-trace.sh — auto-detect chain tracer for modified files
1a878a5 feat(harness): comprehension-gate rule (Phase 1d-C-4 Task 2)
1e6310c feat(hook): A7 — imperative-evidence linker
2371e97 feat(scripts): harness-hygiene-sanitize helper (GAP-13 Task 4 / Layer 4)
25465b6 feat(phase-1d-c-3): Tasks 5+7 — wire findings-ledger-schema-gate + FM-022 + vaporware-prevention enforcement-map
2590947 feat(hook): pre-push-divergence-check — block stale-fetch pushes to master (#47)
2a49b11 feat(harness): resolve 3 pending discoveries — sweep hook, divergence detector, worktree-Q workaround
2dc69a5 feat(drift-detection): 3-component harness-internal cross-repo drift detection (#34)
331e048 feat(hooks): session-start cheatsheet + credential-asking guard (hygiene-2 PR 2/3) (#54)
343d5c6 docs(vaporware-prevention): add enforcement-map row for spawn_task report-back (GAP-08 Task 4)
35ee3df feat(harness): mechanical evidence substrate (Tranche B)
393ba6f feat(harness): Phase B template + rule pattern for end-user-advocate acceptance loop
3afa037 feat(phase-1d-c-3): Tasks 3+4 — findings-ledger-schema-gate.sh hook + bug-persistence-gate.sh extension
3ce9b05 feat(doc-gate): F7 dev-doc gate (warn-mode default) for src/**/*.ts(x) commits (#46)
3e3568f feat(harness): build-harness-infrastructure work-shape — lighter process carve-out for harness work
```

Backlog items absorbed: see plan header `Backlog items absorbed:` field;
the orchestrator can amend this section post-procedure with shipped/deferred
status per item.

### 2. Design Decisions & Plan Deviations

See the plan's `## Decisions Log` section for the inline record. Tier 2+
decisions should each have a `docs/decisions/NNN-*.md` record landed in
their implementing commit per `~/.claude/rules/planning.md`.

### 3. Known Issues & Gotchas

(orchestrator may amend post-procedure)

### 4. Manual Steps Required

(orchestrator may amend post-procedure — env vars, deploys, third-party setup)

### 5. Testing Performed & Recommended

See the plan's `## Testing Strategy` and `## Evidence Log` sections.
This procedure verifies that every task has its declared verification level
satisfied before allowing closure.

### 6. Cost Estimates

(orchestrator may amend; harness-development plans typically have no recurring cost — n/a)
