# PR-Health Snapshot — compact
> Enforcement: pr-health-snapshot-gate.sh (Stop, block-mode default — RELOCATING per D.4). Full: none (compact only)
> Applies: every session close, before declaring work complete.

- Before a session calls its work complete, its final message MUST contain a `## PR Health Snapshot` section covering every one of the operator's active repos (read from `~/.claude/config/active-repos.txt`, hardcoded fallback when absent).
- Per repo, classify open PRs into: CI failure (a `statusCheckRollup` FAILURE/ERROR), merge conflict (`mergeable: CONFLICTING`), or stale green-mergeable (green + mergeable, last updated ≥1h ago — a merge that should have happened).
- Data source: `gh pr list --repo <owner>/<repo> --state open --json number,title,statusCheckRollup,mergeable,headRefName,updatedAt`.
- Snapshot missing → BLOCK. Snapshot present but missing ≥1 repo → allow + stderr warning naming the gaps ("malformed → fail-with-warning").
- Escape hatch: `PR_HEALTH_GATE_DISABLE=1` for harness-dev sessions editing the gate/repo-list.
- **D.4 relocates this**: the Stop-hook gate moves to a **digest** feed — periodic PR-health summary delivered outside the per-session block, since cross-repo rot is better caught by a standing digest than a per-turn gate the operator reads once and forgets.
