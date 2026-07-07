---
name: coordinate-estate
description: Coordinate multiple concurrent Claude Code sessions across the estate (this machine's other checkouts/worktrees) when work is fanned out across satellites — inventory every session, classify it (active / stalled>2h / wedged-undeliverable / superseded), re-home orphaned work via nl-issue.sh, stand down superseded satellites, and run a freeze-window protocol around a shared cutover. Use when the user says "coordinate all sessions", "check on the other sessions", "freeze for the cutover", or when you are about to spawn autonomous satellite work and need to check for supersession first. Mechanizes the 2026-07-04 manual estate-coordination run (NL-FINDING-031) documented in the neural-lace SCRATCHPAD.md.
---

# coordinate-estate

You are acting as **estate coordinator**: the one session responsible for
knowing the state of every other Claude Code session on this machine, closing
out or re-homing whatever they were doing, and — when a shared cutover needs
exclusive access to master — declaring and lifting a freeze window. This
mechanizes what the operator directed by hand on 2026-07-04 ("coordinate all
sessions until everything is complete"), recorded live in
`SCRATCHPAD.md`'s `## COORDINATION ORDER` and `COORD UPDATE` sections.

**File-based channels ONLY.** `send_message` (mcp**ccd_session_mgmt**send_message)
prompts the TARGET session's user for confirmation on every single call — it is a
per-message-confirmed nudge for handing off context to a session someone is
watching, never an unattended orchestration primitive. A satellite you spawned
autonomously has no one to click "confirm" for it, so a queued send_message to
it just sits there undelivered. Coordination state lives in files two sessions
both read: the main checkout's `SCRATCHPAD.md` coordination section (durable,
polled) and `nl-issue.sh` (re-homing target). This is also why autonomous
satellites must be **orchestrator-owned Agent tool worktree dispatches**, not
independently-launched interactive sessions: an interactive session can hit an
unattended permission dialog and wedge with no channel back (the 2026-07-04
lesson — three satellites went HARD-WEDGED this way). An Agent-tool dispatch
runs to completion or reports back in the same turn; there is no dialog to wedge on.

## Step 1 — Inventory

Call `mcp__ccd_session_mgmt__list_sessions` (add `include_archived: false`
unless you're doing a full historical sweep). The real output shape (verified
live, 2026-07-06):

```json
{
  "sessionId": "local_...", "title": "...", "cwd": "C:\\...",
  "branch": "claude/...", "isArchived": false, "isRunning": true,
  "lastActivityAt": "2026-07-07T01:16:41.686Z",
  "prNumber": 67, "prState": "MERGED"
}
```

`branch`/`prNumber`/`prState` are absent when the session has no git branch or
PR. Build your working list: one row per session, excluding yourself.

## Step 2 — Classify each session

For each session, in this order:

1. **superseded** — its `branch` (or the work its `title` describes) is
   already merged to master, OR another session/commit already covers the
   same fix. Check BEFORE asking anything else:
   `git fetch origin master --quiet && git log --oneline origin/master | grep -i "<keyword from title>"`.
   Also grep sibling `origin/build/*` / `origin/claude/*` branches — the
   2026-07-04 run found a duplicate (`sleepy-wright`'s nl-issue-digest work
   was superseded by another session's `7204d19` before it even opened a PR).
   `prState: "MERGED"` is a strong direct signal.
2. **active** — `isRunning: true`, or `lastActivityAt` within the last 2
   hours. Leave it alone; note it as accounted-for.
3. **stalled>2h** — not running, `lastActivityAt` older than 2 hours, but the
   session's last state (if inspectable via
   `mcp__ccd_session_mgmt__search_session_transcripts`) does not show a
   terminal marker (no `DONE:`/`BLOCKED:` with nothing left to do) and does
   not show an unanswered permission prompt. Treat as needing a nudge or
   re-dispatch, not as dead.
4. **wedged-undeliverable** — not running, stalled, AND
   `search_session_transcripts` shows (or you have direct evidence) an
   unattended permission dialog / operator-input prompt as the last turn, with
   nothing further to click on. These sessions cannot be revived by any
   message — they are waiting on a human who isn't there. Diagnostic: the
   2026-07-04 run classified `dazzling-hodgkin`, `busy-sanderson`,
   `wizardly-goldberg` this way — all had empty/no-progress worktrees (nothing
   to lose) and a pending permission dialog as the terminal state.

`search_session_transcripts` only returns snippets around a query match — it
is confirmation evidence, not a full transcript read. Use a query built from
the session's `title` or a keyword you already suspect (e.g. an error string,
a file name) to pull the relevant snippet before classifying stalled vs wedged.

## Step 3 — Re-home orphaned work

For every `wedged-undeliverable` (and any `stalled>2h` you decide not to
revive) session that was doing real, not-yet-landed work: capture ONE line —
what it was trying to do, its session id, its branch (if any) — via:

```bash
bash ~/.claude/scripts/nl-issue.sh "orphaned from wedged session <title/branch>: <what it was doing, one line>"
```

This is the re-homing mechanism: the work is not lost, it becomes a triage-able
ledger entry (`--list --untriaged`) instead of disappearing into a wedged
session nobody will ever unwedge. Do NOT try to message the wedged session — it
cannot answer. Do NOT edit its worktree from your session (it's not yours).

## Step 4 — Stand down superseded satellites

A `superseded` session has nothing left to do; its work already landed a
different way. There is no "delivery" step here beyond noting it — the
2026-07-04 run queued a stand-down note in the coordination file (Step 5) and,
separately, wrote a `send_message` acknowledgment where the target session's
user happened to be actively present to confirm it (that is the one case
send_message earns its keep: a session someone is actively watching). Do not
rely on send_message landing for an unattended satellite — the coordination
file is the durable record either way. On a superseded session's next wake
(if it self-resumes), its own resumer/digest reading `SCRATCHPAD.md` is what
tells it to stand down — write the note so that's true.

## Step 5 — Coordination-section format (write to the MAIN CHECKOUT'S SCRATCHPAD.md)

Coordination state is declared in the **main checkout's** `SCRATCHPAD.md` (not
a worktree copy — worktrees don't share this file with each other; the main
checkout is the one path every session's digest/resumer can poll). Use this
exact section shape (mirrors the live 2026-07-04 run verbatim):

```markdown
## COORDINATION ORDER (Session <you>, operator-directed <date>)
Operator: "<the directive, quoted>". Sequencing authority granted.
1. SATELLITES (<name>/<one-line-task>, ...): finish + PR to master ASAP;
   note completion here. After FREEZE declared below: NO master pushes
   until cutover-done note appears.
2. <name>/<task>: SUPERSEDED by <sha>. verify + close, do not push.
3. <cutover-owner>: <what they do>; <coordinator> declares FREEZE here
   when satellites report (or <timeout>, whichever first); then run
   <the protocol> -> verifier flips -> both remotes -> write CUTOVER-DONE here.
4. <coordinator> (this session): standby verifier + coordinator; polls
   this file; no master pushes until cutover-done.
FREEZE STATUS: PENDING (waiting on <specific condition>)
```

Then, as sessions report in, append `COORD UPDATE (<you>, ~<time>):` lines
(never rewrite history — append-only, like the ledger) narrating
classification results and re-dispatch decisions. When ready:

```markdown
FREEZE STATUS: ACTIVE (<you>, <timestamp>) — NO master pushes by anyone but
<cutover-owner> until CUTOVER-DONE.
```

And on completion:

```markdown
CUTOVER-DONE @ <sha>
```

which is the unfreeze line — every other session's next digest read sees
`FREEZE STATUS` is no longer `ACTIVE` (or sees the `CUTOVER-DONE` line) and
resumes normal master-push behavior.

## Step 6 — Freeze-window protocol (only when a cutover needs exclusive master access)

Not every coordination pass needs a freeze — only ones where a single session
is about to do something to shared state (master branch, live `~/.claude/`
install, a schema migration) that would corrupt if another session pushed
concurrently.

1. **Declare** the freeze in the coordination section (`FREEZE STATUS: PENDING`
   naming what it's waiting on — usually "satellites land or go idle").
2. **Satellites land-or-hold**: every active/stalled satellite either merges
   its PR before the freeze flips ACTIVE, or holds its own push until
   `CUTOVER-DONE` appears. This is a convention read from the file, not an
   enforced lock — the coordinator's job is to make the file the thing every
   session actually checks (digest/resumer read it; a session's own judgment
   at session-start honors it).
3. **Flip to ACTIVE** once satellites report done-or-holding (or a timeout you
   named in step 1 elapses — do not wait indefinitely on an unresponsive
   satellite; that is itself grounds to reclassify it wedged and re-home per
   Step 3).
4. **Cutover owner proceeds** on seeing `FREEZE STATUS: ACTIVE` — this is the
   ONE session allowed to push master during the freeze.
5. **Unfreeze**: cutover owner writes `CUTOVER-DONE @ <sha>`; the coordinator
   independently verifies (re-clone or re-fetch + spot-check the claimed sha
   is really on master) before treating the freeze as lifted for planning
   purposes — never take the cutover owner's word alone for a state this
   consequential (constitution §1 — mechanically true, not self-reported).

## Step 7 — Spawn-time supersession check (do this before EVERY autonomous dispatch)

Before spawning any new autonomous satellite (Agent tool, worktree-isolated),
check that the work isn't already done or already in flight elsewhere:

```bash
git fetch origin master --quiet
git log --oneline origin/master | grep -i "<keyword>"
git branch -r | grep -E "origin/(build|claude|worker)/" # then spot-check likely matches
```

If a match turns up, do not dispatch — either the work is done (fold the
result in) or another session already owns it (note it in the coordination
section instead of duplicating effort). This is what caught the 2026-07-04
`sleepy-wright` duplicate before more work went into it.

## What this skill is NOT

- **Not a messaging system.** It never assumes a queued `send_message` will be
  seen in a useful timeframe — only that a durable file will.
  Use `send_message` only when you have direct evidence someone is actively
  watching the target session (rare, and always as a courtesy, never as the
  mechanism the coordination depends on).
- **Not a way to unwedge a wedged session.** A wedged session stays wedged
  until a human answers its dialog. This skill's job is to make sure its
  work doesn't get lost while it waits (Step 3), not to revive it.
- **Not a substitute for orchestrator-owned dispatch.** If you are about to
  fan out autonomous work, dispatch it via the Agent tool from an
  orchestrator-role session (worktree-isolated), not as independently-launched
  interactive sessions — see "File-based channels ONLY" above for why.
