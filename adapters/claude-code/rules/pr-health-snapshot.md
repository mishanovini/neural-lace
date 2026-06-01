# PR-Health Snapshot at Session Close (Stub — enforcement is in the hook)

**Rule:** before a session calls its work complete, it MUST surface a **PR Health Snapshot** — a markdown section headed `## PR Health Snapshot` covering every one of Misha's active repos — in its final user-facing message. This is a HARD REQUIREMENT (block-mode default), not a soft memory rule.

**Classification:** Mechanism. This file is intentionally short. The detection logic, the repo-coverage check, the mode resolution, the warn-vs-block semantics, and the self-test all live in `pr-health-snapshot-gate.sh`. If a constraint described here isn't backed by the hook, it's theater.

## Why this rule exists

Cross-repo PR rot — a CI-red master, an open PR with failing checks, a green-mergeable PR left sitting > 1h — was structurally invisible to the orchestrator. The `dispatch-session-monitor` scheduled task *detects* it every 10 min but *delivers* via `SendUserMessage` into ephemeral sessions Misha never reads, not the active Dispatch chat. A memory rule ("remember to check PRs") is exactly the kind of discipline that drifts under context pressure. The fix is to make PR-health a **pull the agent must emit at session close**, where the operator actually sees it, and to enforce that emission mechanically. The originating failure (a CI-red neural-lace master that went unnoticed for a day) is catalogued as HARNESS-GAP-42.

## What the snapshot must contain

A `## PR Health Snapshot` section in the final message, with one row per active repo, classifying each repo's open PRs into:

- **CI failure** — open PR whose `statusCheckRollup` contains a FAILURE/ERROR.
- **Merge conflict** — open PR whose `mergeable` is `CONFLICTING`.
- **Stale green-mergeable** — open PR that is green + mergeable and last updated ≥ 1h ago (a merge that should have happened).

Data source per repo:
`gh pr list --repo <owner>/<repo> --state open --json number,title,statusCheckRollup,mergeable,headRefName,updatedAt`

## Enforcement map (hook-backed)

| Constraint | Hook that enforces it | File |
|---|---|---|
| Final message must contain `## PR Health Snapshot` covering all active repos, or session wrap is blocked | `pr-health-snapshot-gate.sh` Stop hook (block-mode default) | `~/.claude/hooks/pr-health-snapshot-gate.sh` |
| Snapshot present but missing ≥ 1 repo → allowed with a stderr warning naming the missing repos ("malformed → fail-with-warning") | same hook | same |
| Repo list read from `~/.claude/config/active-repos.txt`; hardcoded fallback when absent | same hook | same (example: `adapters/claude-code/examples/active-repos.example.txt`) |
| Mode resolution: `PR_HEALTH_GATE_MODE` env > `~/.claude/local/pr-health-gate-mode` file > `block` | same hook | same |
| Escape hatch: `PR_HEALTH_GATE_DISABLE=1` (harness-dev sessions editing the gate/repo-list) | same hook | same |
| 3-retry downgrade-to-warn loop-break | shared `lib/stop-hook-retry-guard.sh` | `~/.claude/hooks/lib/stop-hook-retry-guard.sh` |

## Live-wiring note (HARNESS-GAP-14 class)

The canonical wiring is in `adapters/claude-code/settings.json.template` (Stop chain). Live `~/.claude/settings.json` is per-machine and is updated by the operator's `install.sh` run — the same template-vs-live split F7's `doc-gate.sh` has. Until install runs, the gate's script is present in `~/.claude/hooks/` but is not yet invoked from the live Stop chain.

## Cross-references

- `~/.claude/hooks/pr-health-snapshot-gate.sh` — the gate; format spec + self-test live in the hook header.
- `~/.claude/rules/merge-completed-work.md` — the standing "don't leave a green PR sitting" discipline this gate operationalizes at session close.
- `~/.claude/rules/session-end-protocol.md` — sibling session-close Stop-gate (DONE/PAUSING/BLOCKED marker); both fire at wrap.
- `~/.claude/rules/vaporware-prevention.md` — enforcement-map row pointing at this rule.
- `docs/backlog.md` HARNESS-GAP-42 — the originating cross-repo-rot failure.

## Scope

Applies in any session whose Claude Code installation has `pr-health-snapshot-gate.sh` wired in `settings.json`. The gate fires on every Stop; defensive no-ops (no transcript, no `jq`, disable env) keep it inert where it can't apply. Repo coverage is per-machine via the config file, so the same hook serves any operator's repo set.
