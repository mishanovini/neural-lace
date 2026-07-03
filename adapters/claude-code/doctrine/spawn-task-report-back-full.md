# Spawn-Task Report-Back — Convention-Based Callback Channel for `mcp__ccd_session__spawn_task`

**Classification:** Hybrid. The convention parts (orchestrator generates a monotonic kebab-case task-id, embeds a `Report-back: task-id=<X>` sentinel in the spawn prompt, spawned session writes a result JSON before its Stop hook fires, orchestrator writes a `.acked` marker after acting) are Pattern — self-applied by the orchestrator and the spawned session reading its own prompt. The surfacing of unread results at session start is Mechanism: `hooks/spawned-task-result-surfacer.sh` is a SessionStart hook that scans `.claude/state/spawned-task-results/*.json`, filters out files with sibling `.acked` markers, and emits a system-reminder block for each unread result. The acknowledgment-via-marker discipline is Pattern; the surfacing of unacknowledged results is Mechanism. No result is ever silently lost.

## Why this rule exists

`mcp__ccd_session__spawn_task` is a third-party MCP tool with a stable `{title, prompt, tldr}` interface. It is fire-and-forget by design — once dispatched, the orchestrator has no built-in callback. The spawned session executes its prompt and stops; whatever it produced (commits, branches, PRs, partial work) lives only in git state and the spawned session's transcript. The orchestrator that dispatched the task has no mechanical way to observe completion or pick up the thread on the next turn.

Today the workaround is user mediation: the orchestrator dispatches, the user watches the side session, the user reports back when it's done. This breaks orchestrator-coordinated punchlist work — for sweeps with N independent fixes that need parallel dispatch + sequential cherry-pick, the orchestrator cannot poll for completion without the user as a relay.

The harness layer adds the callback as a **convention** rather than a tool modification (the MCP tool is third-party and not modifiable). The convention is small enough that a spawned session reading the harness rule file can implement it correctly: write a JSON result file at a known path before the Stop hook fires. The orchestrator's next session start surfaces every unread result — the orchestrator reads the surfaced summary, cherry-picks/verifies/replans, then writes a `.acked` sibling marker so the result doesn't re-surface. The mechanism is the surfacer hook; the discipline is the orchestrator's `.acked` write.

## The convention

Three actors, three responsibilities:

1. **Orchestrator (dispatcher).** Generates a monotonic task-id, embeds the sentinel in the spawn prompt, dispatches via `mcp__ccd_session__spawn_task`, and on a future session start reads the surfaced result and writes the `.acked` marker after acting.
2. **Spawned session.** Reads its own prompt, recognizes the `Report-back: task-id=<X>` sentinel, performs the requested work, and writes the JSON result file to `.claude/state/spawned-task-results/<task-id>.json` BEFORE its Stop hook fires.
3. **Surfacer hook.** On every session start, scans the working directory's `.claude/state/spawned-task-results/` for `*.json` files lacking a sibling `*.json.acked` marker. Emits a system-reminder block for each unread result. Silent when nothing is unread or when the directory does not exist.

### Task-id format

Task-ids are monotonic, kebab-case, ASCII-only, and timestamped to prevent collision:

```
<YYYY-MM-DDTHH-MM-SS>-<short-slug>
```

Example: `2026-05-05T14-22-31-fix-login-redirect`. The timestamp prefix makes file ordering deterministic; the short slug (≤ 40 chars, kebab-case) is descriptive enough that a surfaced result names something the orchestrator recognizes. Same task-id used twice is discouraged (second write overwrites the first); the convention does not enforce uniqueness mechanically because that would require parsing JSON state at hook-fire time.

### The sentinel format

The orchestrator's spawn prompt MUST contain a literal line of the form:

```
Report-back: task-id=<task-id>
```

The line should appear once in the prompt, ideally near the top so the spawned session sees it during initial prompt comprehension. The exact string `Report-back: task-id=` (case-sensitive, with the `=` and no spaces around it) is the recognition pattern; spawned sessions are instructed by this rule (and by their inherited harness) to look for it.

## JSON schema

The spawned session writes its result to `.claude/state/spawned-task-results/<task-id>.json`. The schema is fixed:

```json
{
  "task_id": "string",
  "started_at": "ISO 8601",
  "ended_at": "ISO 8601",
  "branch": "string",
  "pr_url": "string | null",
  "exit_status": "ok | failed | partial",
  "summary": "string",
  "commits": ["array of commit SHAs"],
  "artifacts": ["array of file paths"]
}
```

Field semantics:

- **`task_id`** — must match the sentinel value verbatim. Surfacer keys results by task-id; mismatch breaks the loop.
- **`started_at`** / **`ended_at`** — ISO 8601 timestamps. Used for retrospective audit; not enforced beyond format.
- **`branch`** — name of the branch the spawned session created (or operated on). Empty string if the session did no git work.
- **`pr_url`** — URL of any opened PR, or `null` if no PR was opened. Surfaced verbatim so the orchestrator can navigate.
- **`exit_status`** — one of `ok` (work completed as requested), `failed` (work could not complete; reason in `summary`), `partial` (some work shipped, some blocked; details in `summary`).
- **`summary`** — one-to-three sentence prose summary of what shipped, what's blocked, and what the orchestrator should do next. The surfacer displays this verbatim.
- **`commits`** — array of full commit SHAs (40-char) on `branch`, oldest first. Empty if no commits made.
- **`artifacts`** — array of relative file paths the spawned session produced or materially modified. Used for audit and for orchestrator follow-up work that needs to know what's on disk.

The result file MUST be written before the spawned session's Stop hook fires. If the spawned session crashes before writing, no result file appears — the orchestrator finds out via absence of expected git artifacts (the same fallback as today's fire-and-forget mode).

## Lifecycle

1. **Dispatch.** Orchestrator generates task-id, builds the spawn prompt with the sentinel embedded, calls `mcp__ccd_session__spawn_task`. The spawn returns immediately; the orchestrator continues with other work.
2. **Execution.** Spawned session executes the prompt. Before its Stop hook fires, it writes the JSON result file at `.claude/state/spawned-task-results/<task-id>.json`. The session ends.
3. **Surface.** On the orchestrator's next session start, `spawned-task-result-surfacer.sh` runs as part of the SessionStart hook chain. It scans `.claude/state/spawned-task-results/*.json` for files lacking a sibling `<task-id>.json.acked` marker. For each unread result, it emits a system-reminder block naming task-id, exit_status, branch, pr_url, summary, commits, and artifacts.
4. **Act.** Orchestrator reads the surfaced summary and decides next steps: cherry-pick the commits onto its feature branch, verify via `task-verifier`, plan follow-up work, or accept partial completion and surface to the user.
5. **Acknowledge.** After acting on the result, the orchestrator writes a sibling marker:

   ```
   touch .claude/state/spawned-task-results/<task-id>.json.acked
   ```

   The marker may be empty or contain a one-line note describing what action was taken. The surfacer filters acked results out of subsequent surface passes.

6. **Re-surface (failure mode).** If the orchestrator forgets step 5, the result re-surfaces every session. The repeated mention is itself a signal that the orchestrator hasn't completed the loop on a prior task.

## Worked example

### Step 1 — Orchestrator's spawn-prompt

The orchestrator dispatches a fix for a login redirect bug:

```
Title: Fix login redirect after OAuth callback
TLDR: Spawned session fixes the post-OAuth redirect bug where users land on /login instead of their original destination. Returns a single commit on a worker branch.

Prompt:
Report-back: task-id=2026-05-05T14-22-31-fix-login-redirect

You are a spawned builder session. Read this prompt fully before doing any work.

Task: in `src/app/auth/callback/route.ts`, the redirect after OAuth callback drops the
`returnTo` query parameter. Find the bug, fix it, write a regression test, and commit
on branch `worker-2026-05-05T14-22-31-fix-login-redirect` from the current master.

Before your Stop hook fires, write your result to:
  .claude/state/spawned-task-results/2026-05-05T14-22-31-fix-login-redirect.json

Schema and conventions in `~/.claude/rules/spawn-task-report-back.md`. Field semantics:
exit_status=ok|failed|partial; commits is an ARRAY of full SHAs; pr_url is null if
you did not open a PR; summary is 1-3 sentences naming what shipped and what (if
anything) is blocked.

Do NOT push the branch. The orchestrator will cherry-pick locally.
```

### Step 2 — Spawned session writes result

After completing the fix, the spawned session writes:

```json
{
  "task_id": "2026-05-05T14-22-31-fix-login-redirect",
  "started_at": "2026-05-05T14:22:31Z",
  "ended_at": "2026-05-05T14:38:14Z",
  "branch": "worker-2026-05-05T14-22-31-fix-login-redirect",
  "pr_url": null,
  "exit_status": "ok",
  "summary": "Fixed the returnTo drop in src/app/auth/callback/route.ts:42 — the redirect now preserves the query parameter through the OAuth round-trip. Added a regression test in src/app/auth/callback/route.test.ts. Branch ready for cherry-pick; no PR opened per orchestrator instruction.",
  "commits": [
    "a1b2c3d4e5f6789012345678901234567890abcd"
  ],
  "artifacts": [
    "src/app/auth/callback/route.ts",
    "src/app/auth/callback/route.test.ts"
  ]
}
```

### Step 3 — Orchestrator's next session-start surfaces the result

The surfacer hook fires on session start. It finds the unacked result and emits:

```
[spawned-task-result] task-id: 2026-05-05T14-22-31-fix-login-redirect
  exit_status: ok
  branch: worker-2026-05-05T14-22-31-fix-login-redirect
  commits: a1b2c3d4e5f6789012345678901234567890abcd
  summary: Fixed the returnTo drop in src/app/auth/callback/route.ts:42 — the redirect
    now preserves the query parameter through the OAuth round-trip. Added a regression
    test in src/app/auth/callback/route.test.ts. Branch ready for cherry-pick; no PR
    opened per orchestrator instruction.
  artifacts: src/app/auth/callback/route.ts, src/app/auth/callback/route.test.ts
  Ack with: touch .claude/state/spawned-task-results/2026-05-05T14-22-31-fix-login-redirect.json.acked
```

### Step 4 — Orchestrator acts and acks

```bash
git cherry-pick a1b2c3d4e5f6789012345678901234567890abcd
# task-verifier invocation, evidence block, etc.
touch .claude/state/spawned-task-results/2026-05-05T14-22-31-fix-login-redirect.json.acked
```

The next session start does NOT re-surface this result.

## Edge cases

- **Spawned session crashes before writing the result.** No result file appears. Surfacer is silent. The orchestrator finds out via the absence of expected git artifacts (the spawned branch was created or wasn't). Acceptable — same fallback as today's fire-and-forget mode; the convention adds value without removing the existing recovery path.
- **Spawned session writes malformed JSON.** Surfacer detects non-parsing JSON and emits a warning to stderr but doesn't block session start. The orchestrator can manually fix the file (or delete and re-dispatch) and the next session start re-evaluates.
- **Multiple results stack up unread.** Surfacer surfaces ALL unread results in date-then-name order, not just one. Orchestrator processes them in any order it chooses; each is acked independently.
- **Same task-id used twice.** Convention requires monotonic timestamp-prefixed task-ids. Second write overwrites the first; the prior result is lost. Discouraged but not blocked at hook level (would require parsing JSON state at hook-fire time, which conflicts with the silent-when-nothing-to-do invariant).
- **Orchestrator forgets to write the `.acked` marker.** Result re-surfaces every session. Annoying but recoverable. The repeated mention is itself a signal that the orchestrator hasn't completed the loop on a prior task — this is the safety property the explicit-ack design buys.
- **Surfacer runs in a project that hasn't adopted the convention.** `.claude/state/spawned-task-results/` doesn't exist; surfacer exits 0 silently (mirrors `discovery-surfacer.sh`'s "directory doesn't exist" path). Adoption is implicit — projects that have not created the directory pay no overhead.
- **Result file written but the orchestrator's session is terminated before next surface.** No data lost — the result file persists across session boundaries and surfaces on the next session start.
- **Orchestrator runs in a different worktree than the one that received the result.** The state directory is per-working-directory. If the orchestrator is in a separate worktree, the unread result is invisible. Mitigation: dispatch from the same working directory the orchestrator will return to, or the orchestrator manually checks sibling worktrees' state directories.

## Cross-references

- `~/.claude/rules/discovery-protocol.md` — sibling SessionStart-surfacer pattern. The discovery surfacer (decisions awaiting orchestrator action) and the spawned-task surfacer (data awaiting orchestrator action) share the same shape: silent-when-empty, working-directory-scoped scan of a state subdir, system-reminder block per unread item.
- `~/.claude/rules/orchestrator-pattern.md` — the orchestrator-pattern this rule extends. `mcp__ccd_session__spawn_task` complements the in-process `Task` tool with worktree isolation; the report-back convention closes the callback gap that distinguishes them.
- `~/.claude/rules/vaporware-prevention.md` — enforcement-map this rule extends with one new row: "Spawn_task results surfaced at session start" → `spawned-task-result-surfacer.sh` SessionStart hook + `spawn-task-report-back.md` rule.
- `~/.claude/hooks/spawned-task-result-surfacer.sh` — the surfacing mechanism (Phase 1d / GAP-08 Task 2).
- `~/.claude/hooks/discovery-surfacer.sh` — the pattern this surfacer mirrors.

## Enforcement

| Layer | What it enforces | File |
|---|---|---|
| Rule (this doc) | The convention shape: task-id format, sentinel format, JSON schema, ack mechanism | `adapters/claude-code/rules/spawn-task-report-back.md` |
| Hook (Mechanism) | Unread results surface at every session start; results with `.acked` siblings are filtered | `adapters/claude-code/hooks/spawned-task-result-surfacer.sh` |
| Convention (Pattern) | Orchestrator generates monotonic task-id, embeds sentinel, writes ack marker after acting | self-applied by orchestrator |
| Convention (Pattern) | Spawned session reads its own prompt, recognizes sentinel, writes result JSON before Stop fires | self-applied by spawned session |

The mechanical part (surfacing) is what makes the convention reliable: even if the orchestrator forgets to check for results, the next session start surfaces them. The convention parts (task-id generation, sentinel, schema, ack write) rely on the orchestrator and spawned session reading this rule. There is no hook that validates the spawn prompt contains the sentinel, and no hook that validates the spawned session writes a result — those failures degrade gracefully (surfacer is silent if no result was written), and the convention is correct under the assumption that downstream orchestrators and spawned sessions follow harness rules.

## Scope

This rule applies in any project whose Claude Code installation has the `spawned-task-result-surfacer.sh` SessionStart hook wired in `settings.json`. Project-level: any project with a `.claude/state/spawned-task-results/` directory honors the convention; projects without the directory see the surfacer exit silently. Adoption is implicit — the harness ships the substrate (rule + hook + wiring); downstream projects opt in by creating the directory on first dispatch (the spawned session does `mkdir -p` before writing). No flag or config field needs to flip.
