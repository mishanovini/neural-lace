# Plan: PR-Health Snapshot Stop-Hook Gate
Status: ACTIVE
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
