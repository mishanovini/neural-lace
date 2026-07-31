# Operator's five questions — 2026-07-29, answered with evidence

Durable record. The operator's standing complaint is that chat is too noisy to rely on
("It's very common for me to not read everything you tell me... But I need these concerns to
persist until we actually address them"). This file is the persistence. Every row below has an
owner and a next action; NONE may be closed by a chat message alone.

---

## Q1. The verification-dispatch enforcement gap — are you doing anything about it?

**Honest answer: no, not until today.** `doctrine/verification-dispatch.md` states its own
enforcement as *"NONE at the memory rung — this is a Pattern... a commit-time carrier is the
named gap."* The plan that closes it, `docs/plans/verification-dispatch-directive.md` (V1-V6),
is **0 of 6 tasks done — every task still `not-started`**. I wrote the doctrine and left the
mechanism unbuilt, which is precisely the theatre constitution §10 calls the cardinal defect.

**UPDATE (same day, task-verifier):** the 0/6 was itself stale — V1–V5 had been BUILT and
MERGED TO MASTER on 2026-07-28 (84f5a3c, fe78ed3) and simply never verified or flipped.
task-verifier re-derived each with live probes (V3 proven by before/after differential
against fe78ed3~1) and flipped all five at conf 8–9 (landed cd1aa93). V6 is deferred by the
plan's own text. The REMAINING gap is unchanged: the commit-time carrier
(review-record-commit-gate.sh, fixed today at 9828ea1) goes live only via the
sweep → records → template-merge chain, which waits on the operator's SWEEP/DESKTOP/HYBRID
call.

The intended carrier is `hooks/review-record-commit-gate.sh`. It has been **rejected four times**
by harness-reviewer. Q1 and Q5 are therefore the same blockage.

**Next action:** V1-V6 must be dispatched, and the commit-time carrier landed. Until then the
dispatch rule is memory-only and WILL be skipped again — f6562b2 is the proof it already was.

---

## Q2. Can we enforce that a surfaced problem never just gets dropped?

**The gap is real and it is structural.** `nl-issue.sh` exists and writes to a machine-wide
ledger with weekly triage; `docs/backlog.md` exists. But **nothing forces a problem I state in
chat to become a row**. Filing is entirely my discretion, so the ledger reflects what I
remembered to file, not what I found. That is the same failure shape as Q1: a documented
practice with no mechanism.

**Design adopted (build item, not a promise):**
1. Every problem I state to the operator carries its ledger ID **inline** (`[NL-###]`), so a
   missing ID is visible to the operator at read time rather than discoverable only by audit.
2. A Stop-gate reconciles problem-shaped statements in the turn against rows filed that turn,
   and blocks session end on any unfiled one — the teaching-gate pattern already used by the
   needs-you cold-reader lint.
3. Anything the operator names as a problem is auto-filed on their behalf, not on mine.

**Constitution §5 already says this** ("Bugs, gaps, findings... written to their durable home in
the same response that surfaced them"). It has no enforcement. Adding one is the fix.

---

## Q3. Multi-machine cockpit — when is it real?

**Built, not running here.** `server/peer-view.js` and `server/export-state.js` exist and
`cockpit-roadmap-redesign` task 7 (event-triggered publish + person grouping) is checked
complete. But on this Mac, measured today:
- `GET /api/peers` → **route does not exist** in the server's route table.
- `~/.claude/state/coord-sync/cycles.log` → **absent**; the sync has never run here.

So the peer machinery has no data on this machine and no surfaced route. The cross-machine view
is not blocked on design — it is blocked on coord-sync never having been wired on this Mac, the
same "this machine was a second-class citizen" class as the Windows-only cockpit launcher fixed
today.

**Next action:** wire and verify coord-sync on this machine, then confirm the peer surface
renders the other machine. Until a peer actually appears, the answer to "when" is
**not scheduled** — do not let this file imply otherwise.

---

## Q4. Why is the harness deleting important work?

**Root cause, proven twice.** On this Mac `~/.claude/hooks`, `~/.claude/scripts` etc. are
**symlinks back into `adapters/claude-code/`**. Both deploy carriers therefore run with
source inode == target inode and write over their own source:

| Carrier | Damage | Status |
|---|---|---|
| `install.sh` | Deleted `hooks/lib/` — 19 files, ~12,400 lines. **Twice.** | **FIXED** — `4e29dc6`, guard at the sync primitive, 12/0 verified on bash 3.2.57 |
| `session-start-auto-install.sh` | 2026-07-29 09:41:43 — overwrote **27 committed files** with older `origin/master` content, reverting all of M2+M3+M4 and blanking `model-pin-gate.sh` | Guard port **in flight** |

Proof for the second: the log records `updated hooks/runtime-verification-executor.sh (backed
up prior copy…)`, and that file's post-run bytes were byte-identical to
`git show origin/master:<path>` while HEAD held the newer copy. Recovered via `stash@{0}`
(`auto-install-overwrite-2026-07-29`) — **that stash is evidence, do not drop it.**

**The deeper answer the operator deserves:** the symlink topology was never a supported install
shape. I set this machine up that way, and neither carrier was written to survive it. The
operator's "first-class harness-dev machine" directive is what makes it supported — so the
carriers must change, not the machine.

**Same mechanism, second symptom:** these rewrites bump plan-file mtimes, and
`roadmap-routes.js:1001` uses mtime as the `completed_at` fallback, so the cockpit's 7-day
completed-aging clock restarts on every sync. Filed as
`ROADMAP-COMPLETED-AGING-MTIME-RESET-01`.

---

## Q5. Why can't you get past the gate?

**Because nobody ran the reviews. Not the gate's fault — mine.** Measured on the working branch:

- in-surface files changed vs master: **141**
- with a PASS `harness-change-review` record at their **current blob_sha**: **31**
- **uncovered: 110**

The gate matches `{path, blob_sha}`, so a record against an older blob does not count. I spent
this session dispatching builders and **zero reviewers for the work that landed**. That is the
identical failure to Q1: the review is standard process with no mechanism, so it got skipped —
by me, in the same session where I was building the mechanism to stop it.

**Next action:** a review sweep across the 110 uncovered files, grouped by surface, each writing
its own record, followed by an independent audit that the records match HEAD blobs. Launched
today; first attempt died instantly on a script argument-type bug (zero tokens spent) and needs
re-launch.

---

## Ledger

| # | Concern | Owner | State |
|---|---|---|---|
| Q1 | verification-dispatch has no enforcement | plan `verification-dispatch-directive` V1-V6 | **V1-V5 verified+flipped (cd1aa93); carrier live-wiring waits on the sweep call** |
| Q2 | surfaced problems can be silently dropped | problems-persist mechanism | **BUILT+LANDED** ecbc6dd — inline IDs + Stop-WARN (83/0) + operator auto-file (32/0); plan closed |
| Q3 | multi-machine cockpit has no data on this Mac | coord-sync LaunchAgent | **WIRED** a8ce622 — 60s cadence live (cycles.log ticking); 2 operator commands remain: coord-repo-url.txt here + install-coord-sync-task.ps1 on Windows |
| Q4 | harness deletes work (2 carriers) | both carriers guarded | **2 of 2 FIXED** — 4e29dc6 + b8dd674, proven end-to-end (54 updated -> 0 updated, 326 self-sync-skipped) + kill-switch ~/.claude/local/no-auto-install |
| Q5 | in-surface files unreviewed (now 123+ at HEAD) | review sweep | **PARKED on operator word** — safety classifier requires explicit authorization of self-review; Inbox NY-1785357818-7d3f (SWEEP/DESKTOP/HYBRID) |
