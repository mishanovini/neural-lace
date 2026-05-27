# Design: Auto-merge-on-green PostToolUse hook + tracking poller

**Status:** DESIGN (not yet implemented — captured 2026-05-27)
**Authors:** maintainer + Claude (dispatch session)
**Motivates:** ~198 unmerged branches across ~6 repos observed by the maintainer 2026-05-27. The "open PR → move on → forget" failure mode that `~/.claude/rules/merge-completed-work.md` documents needs mechanical backing, not just discipline.

## Problem

`~/.claude/rules/merge-completed-work.md` is Pattern-class. It binds the session that opens a PR to track it to merge. But sessions end, agents context-switch, and PRs sit. The dispatch-session-monitor scheduled task's stale-PR sweep (added 2026-05-27 to the same SKILL.md) covers the cross-session backstop, but it polls every 10 min and only sees PRs after they've already aged. The mechanism is reactive, not proactive — and it depends on a per-machine scheduled task running, which means PRs opened on machine A while monitor is only on machine B can drift indefinitely.

The proposal: capture every `gh pr create` at the moment of dispatch via a PostToolUse hook, register the PR in a tracking file, and let a companion poller drive it to terminal state (merged / closed / surfaced for review). This makes the tracking proactive (registration is automatic on PR creation, not discovered later) and machine-independent (the tracking file lives in `~/.claude/state/` which can be synced across machines per the maintainer's standard setup).

## Mechanism

### Layer A — PostToolUse hook on `gh pr create`

Hook: `~/.claude/hooks/pr-tracker-register.sh`
Event: PostToolUse, matcher `Bash`
Trigger condition: `tool_input.command` starts with `gh pr create` AND the tool's exit was successful.

**What it does:**

1. Parses the PR URL from `tool_result.stdout` (gh prints the URL on success).
2. Extracts: `repo` (owner/name), `pr_number`, `branch`, `created_at` (now, ISO 8601).
3. Reads the staged files at the time of PR creation via `gh pr view <num> --repo <repo> --json files` and classifies as `safe-class` / `product-code` / `mixed` per the file-path taxonomy in `~/.claude/rules/merge-completed-work.md`.
4. Reads (and `flock`-locks) `~/.claude/state/pr-tracking.json` and appends an entry:

```json
{
  "pr_url": "https://github.com/owner/repo/pull/N",
  "repo": "owner/repo",
  "pr_number": N,
  "branch": "feat/foo",
  "created_at": "2026-05-27T17:44:57Z",
  "classification": "safe-class | product-code | mixed",
  "registered_by_session": "<session_id>",
  "registered_at": "2026-05-27T17:44:58Z",
  "last_polled_at": null,
  "last_status": null,
  "terminal_state": null
}
```

5. Exits 0 (never blocks — registration failure is logged but doesn't fail the underlying `gh pr create` that already succeeded).

**Failure isolation:** every code path exits 0. If the JSON file is corrupt, the hook overwrites with the new entry only (preserving the previous file as `.bak`). If `gh` is not available or auth is missing, the hook logs to stderr and exits 0.

### Layer B — Companion scheduled task / poller

Scheduled task: `pr-tracking-poller` (Windows Task Scheduler, every 5 min)
Script: `~/.claude/scripts/pr-tracking-poll.sh`

**What it does on each run:**

1. Reads `~/.claude/state/pr-tracking.json`.
2. For each entry whose `terminal_state` is null:
   - Polls the PR via `gh pr view <num> --repo <repo> --json state,statusCheckRollup,mergeable,mergedAt,closedAt`
   - Updates `last_polled_at` and `last_status` in the tracking file.
   - **Decision tree per status:**
     - PR `state: MERGED` → mark `terminal_state: merged-at-<ISO>`. No further action.
     - PR `state: CLOSED` (not merged) → mark `terminal_state: closed-at-<ISO>`. SendUserMessage informing Misha of the close (in case it was unintentional).
     - PR open + `statusCheckRollup` has any `FAILURE`/`ERROR` → SendUserMessage immediately (don't wait for 30-min threshold; the hook surfaces failures on first poll).
     - PR open + `mergeable: CONFLICTING` → SendUserMessage immediately.
     - PR open + CI all green + mergeable + `classification: safe-class` + age ≥ 1 hour → `gh pr merge <num> --repo <repo> --squash --delete-branch`. On success: mark `terminal_state: auto-merged-at-<ISO>`, SendUserMessage with brief confirmation.
     - PR open + CI all green + mergeable + `classification: product-code` + age ≥ 1 hour → SendUserMessage requesting review/merge. Mark `last_surfaced_at` to avoid re-alerting more often than every 6 hours.
     - PR open + CI all green + mergeable + `classification: mixed` + age ≥ 1 hour → same as product-code (treat mixed as requiring review).
     - PR open + CI still pending + age ≥ 24 hours → SendUserMessage: stalled CI alert.
     - PR open + age ≥ 7 days regardless of state → SendUserMessage: escalation alert with "consider closing or rebasing."
3. Compacts the tracking file: entries whose `terminal_state` is set and is older than 30 days are archived to `~/.claude/state/pr-tracking-archive.jsonl` (one entry per line for grep-ability) and removed from the live tracking file.

**Concurrency:** the poller acquires the same `flock` on `pr-tracking.json` that the hook uses. Concurrent hook + poller writes serialize cleanly.

### Layer C — Read API for in-session inspection

A small read-only helper at `~/.claude/scripts/pr-tracking-list.sh` lets the orchestrator query the tracking file from within a session:

- `pr-tracking-list.sh --open` → JSON array of currently-open registered PRs.
- `pr-tracking-list.sh --my-session <session_id>` → only PRs this session opened.
- `pr-tracking-list.sh --repo <owner/name>` → only PRs in a specific repo.

The orchestrator uses this at session-end to verify every PR it opened reached `terminal_state` before reporting DONE per `~/.claude/rules/merge-completed-work.md` and `~/.claude/rules/session-end-protocol.md`.

## Lifecycle integration

- **Session opens PR** → Layer A registers it automatically.
- **Session continues working** → Layer A is silent on subsequent unrelated `gh` calls (only fires on `gh pr create`).
- **Poller fires every 5 min** → Layer B drives every tracked PR toward terminal state.
- **Session ends** → if the session opened any PR that's not yet terminal, the session's DONE marker is dishonest per `merge-completed-work.md`. A future extension could wire `continuation-enforcer.sh` to check `pr-tracking-list.sh --my-session $CLAUDE_SESSION_ID --open` and block DONE if any entries are returned (with PAUSING/BLOCKED as the honest alternative).

## What this doesn't solve

- **Repos outside the configured GitHub account.** The classification step needs `gh` auth to the right account; multi-account setups need the account-switch hook (`account-switch.sh`) to run before the tracker.
- **PRs opened by humans, Dependabot, or other tools.** The hook only fires on agent-initiated `gh pr create`. A separate periodic full-repo scan (already in the dispatch-session-monitor's step 6) catches those.
- **Forked-repo PRs.** Merging upstream PRs from forks requires the merge to happen in the upstream repo with appropriate permissions; the auto-merge path may fail. The poller logs the failure and falls back to surfacing for Misha.
- **Stop-hook integration.** Phase 1 of this design is Layers A + B + C as Mechanism + the Pattern rule as discipline. Phase 2 (wiring `continuation-enforcer.sh` to block DONE on unmerged owned PRs) is the natural follow-up that closes the loop fully but adds a new failure surface (sessions stuck unable to end because a PR's CI is genuinely slow). Defer Phase 2 until the Phase 1 tracking has been observed for ~2 weeks and the false-positive rate is understood.

## Open questions

1. Should the auto-merge step use `--squash` universally, or detect the repo's merge convention? Most user-facing app repos prefer squash; the harness repo (neural-lace) uses `--no-ff` per its convention. Detect via `gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed` on first encounter per repo, cache the answer.
2. What's the right behavior when a session reuses an open PR (push more commits to an existing PR branch)? Layer A registers on `create`, not on subsequent pushes. Probably correct — the original registration entry stays valid. But the `last_status` field might be stale; the poller refreshes it on next poll.
3. How does this interact with branch protection rules requiring review approvals? Auto-merge will fail with a clear error; the poller catches the failure and surfaces to the maintainer. No silent dropping.
4. What's the storage budget on the tracking file? At 198 historical PRs, the file is small (~50KB). Archival at 30 days keeps it bounded; not a concern.

## Why not build now

The current intervention (rule + monitor update) handles the immediate "198 unmerged branches" problem because the monitor's step 6 sweeps every 10 min across all repos. The poller adds proactive registration which is structurally better but additive — the monitor's sweep is the safety net.

Building the hook + poller now would:
- Add a PostToolUse hook to the harness (every `gh pr create` invocation pays the cost).
- Add a Windows scheduled task (per-machine config the maintainer must install).
- Introduce a new state file format (`pr-tracking.json` schema) that must be stable for future-version compatibility.

All of these are reasonable, but none are urgent given the monitor's step 6. The design is captured so a future session can implement it without re-deriving the structure.

## Implementation plan (when built)

1. **Hook script** (`hooks/pr-tracker-register.sh` in `adapters/claude-code/`, mirror to `~/.claude/hooks/`).
2. **Hook wiring** in `adapters/claude-code/settings.json.template` and live `~/.claude/settings.json`.
3. **Poller script** (`scripts/pr-tracking-poll.sh`).
4. **Read helper** (`scripts/pr-tracking-list.sh`).
5. **Scheduled task registration script** (`scripts/register-pr-tracking-poller.ps1`) — Windows Task Scheduler entry that runs the poller every 5 min.
6. **Self-test** (`pr-tracker-register.sh --self-test`) covering: safe-class PR registration, product-code PR registration, mixed PR registration, malformed `gh` output, missing tracking file (creates), corrupt tracking file (preserves backup).
7. **Architecture doc update**: `~/.claude/docs/harness-architecture.md` adds the hook, the scripts, and the state file.
8. **Cross-reference**: `~/.claude/rules/merge-completed-work.md` updated to cite this as the production Mechanism (currently cites "future").

Estimated work: 2-3 hours for Layer A + B + C + self-test + wiring. Phase 2 (Stop-hook integration) adds another 1-2 hours plus a 2-week observation window.

## Cross-references

- `~/.claude/rules/merge-completed-work.md` — the Pattern rule this design would mechanize.
- `~/.claude/rules/git.md` — the broader git/PR discipline.
- `~/.claude/rules/deploy-to-production.md` — the deploy-after-merge discipline.
- `<scheduled-tasks-dir>/dispatch-session-monitor/SKILL.md` (per-machine scheduled-task location) — the current cross-session backstop (step 6 sweep).
- `~/.claude/rules/session-end-protocol.md` — DONE/PAUSING/BLOCKED markers; Phase 2 of this design would extend `continuation-enforcer.sh` to block DONE on unmerged owned PRs.
