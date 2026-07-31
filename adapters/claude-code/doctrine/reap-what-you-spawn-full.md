# Reap what you spawn — full

Companion to `doctrine/reap-what-you-spawn.md`. Operator question, 2026-07-14, after the auditor
process-leak took the machine down: *"Is there a lesson worth encoding? Something about always closing
out anything that gets initiated?"* Yes. This is that lesson.

## The principle in one line
**The initiator owns the full lifecycle of what it initiates — creation AND termination — across every
exit path, especially the abnormal ones.** Abandonment is not termination. A timeout, an early return,
an error, a process restart, a thrown exception — each is an exit path, and each must actively tear down
whatever this code (or agent) brought into existence.

## Why this is subtle and keeps recurring
The happy path always reaps: work finishes, the child exits, the promise resolves, the `finally` runs.
Leaks live exclusively on the **abnormal** paths, which are the ones nobody exercises and nobody tests.
So the discipline is: *for every `spawn` / launch / open / acquire / create, ask what happens to it on
timeout, on error, and on shutdown* — and make all three terminate it.

The trap is that abandonment **looks like** success to the caller. `auditor.js`'s timeout resolved the
promise with `rc:124`; the auditor's single-flight guard then saw a finished cycle and started the next
one — while the previous cycle's entire bash tree kept running. The guard was correct; the lie it was
fed was the bug. **A control structure that reports completion without ensuring termination will defeat
every downstream safeguard.**

## The auditor incident (the golden case, in full)
- `runCli()` spawned `bash -lc "merge-scan-lib.sh scan-repo …"` on a 120s auditor cadence.
- The repo grew ~180 commits in a session; a `-m` change to `diff-tree` (a correctness fix) made the
  scan heavier; the scan began exceeding the 60s CLI timeout **every** cycle.
- The timeout `resolve()`d and walked away. Nothing killed the child. **Each cycle leaked a whole tree.**
- Compounding: because the scan never *completed*, its "last-scanned" marker never advanced, so every
  cycle re-scanned the same enormous range and re-forked `progress-log.sh` per commit.
- Result over hours: 781 live `bash.exe`; a bare `date` took 4.6s; three reboots; three misdiagnoses
  (I blamed "too many concurrent agents" and adopted a *memory-rung* "≤2 agents" rule — which is the
  weakest possible control and did nothing, because agents were never the cause).
- Fix: `killTree(child)` before `resolve()`, using `taskkill /T /F` (Windows) because `child.kill()`
  reaps only the top `-lc` shell and leaves the grandchildren — the exact processes that pile up.

## The generalization (this is one failure with many faces)
Everything this session leaked is the SAME shape — initiate-without-guaranteed-reap:
1. **Processes** — the auditor bug above.
2. **Background agents** — repeatedly left running on a Claude restart; "stopped/no-completion" agents
   that had to be reconciled by hand. The reap here is: on restart, enumerate and reconcile every
   in-flight agent before assuming anything landed.
3. **Git commands** — timed-out `git push`/`fetch` left orphaned processes holding refs locks, which
   wedged git itself. The reap: a timed-out git op must be killed, not abandoned.
4. **Locks** — `progress-log-lib.sh`'s mutex "proceeds unlocked" after ~150ms. That is abandonment
   dressed as tolerance; for a read-modify-write it is a lost update. A lock you cannot guarantee to
   release is a lock you should not take.
5. **Servers / worktrees / temp files** — a deployed server not stopped on redeploy; worktrees whose
   untracked artifacts vanished on prune. Same class.

## Making it a Mechanism (per the artifact-evidence-bar: Pattern → Mechanism)
A doctrine that is only read is memory-rung. Stronger forms, in order:
- **code-reviewer lens:** flag any `spawn`/`exec` paired with a `setTimeout`/deadline whose handler does
  not kill the child; flag any `spawn` on Windows relying on `child.kill()` without tree-kill; flag any
  `acquire`/`open`/`create` without a matching release on the error path.
- **architecture-reviewer lens:** this is already covered by its *failure-mode-first* method ("crash
  mid-write", "the abandon path") and its *operability* method — but add the explicit reap check to its
  hazard priors so every design that spawns is asked "who reaps this, on every exit?".
- **golden test:** a repo-grep gate that fails CI on the literal `setTimeout(...resolve...` -adjacent-to-
  `spawn` shape without a kill in the handler is possible but noisy; prefer the review lens first and
  measure its false-positive rate before hardening (§10).

## The one-question test
For anything you start, answer: **"When this times out or errors, what actively kills it?"** If the
answer is "the promise resolves" / "we return" / "the next tick" — it leaks. The initiator reaps.
