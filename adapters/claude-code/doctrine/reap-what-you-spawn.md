# Reap what you spawn — lifecycle ownership on every exit path

> Enforcement: Pattern (self-applied) + a code-reviewer / architecture-reviewer lens.
> Full: doctrine/reap-what-you-spawn-full.md
> Applies: any code or agent that spawns a process, launches a background agent/workflow,
> starts a server, acquires a lock, or creates a temp file/worktree.

**The law:** whatever you initiate, you OWN until it terminates — on EVERY exit path, especially the
abnormal ones (timeout, error, early return, abandonment). A control-flow path that stops *waiting for*
a thing without *terminating* it is an orphan factory. Extends constitution §8 ("a launched task is a
tracked obligation until its result is consumed") from consumption to **termination**.

**The cardinal anti-pattern — timeout-without-kill:**
```
setTimeout(() => resolve({rc:124}), ms);   // WRONG: resolves and walks away; the child runs forever
```
The timeout must KILL the child, THEN resolve. Resolving alone orphans it — and worse, the caller now
BELIEVES the work finished, so a single-flight guard won't save you: it starts the next one.

**Golden case (2026-07-14, PROVEN):** `auditor.js runCli()` did exactly this — every 120s cycle whose
bash `merge-scan` exceeded the 60s timeout leaked a whole process tree. Measured on the operator's
machine: **781 live bash.exe** (435 merge-scan + 194 progress-log), accumulating ~1 tree/cadence for
hours, **3 forced reboots**. Fix: `killTree()` before resolve. A candidate reviewer that reads this
`setTimeout` and does not flag the missing kill has missed the defect.

**Platform reality (Windows):** `child.kill()` reaps ONLY the direct child (the `bash -lc` shell), NOT
its grandchildren (the inner bash / git / emitters — the ones that actually pile up). Kill the TREE:
`taskkill /T /F /PID` (Windows) or a process-group kill `process.kill(-pid)` (Unix). Verified to 3
levels: a bare kill leaves 2 alive; tree-kill → 0.

**Generalizes to every initiated resource:**
| Initiated | The reap obligation |
|---|---|
| child process | kill the TREE on timeout/error/shutdown — not just the top shell |
| background agent / workflow | reconcile + reap on restart; abandoned agents are this bug in a different medium |
| server / port | stop it on shutdown; don't leave `:PORT` bound to a zombie |
| lock | release on every path; "proceed-unlocked-after-Nms" ABANDONS, it does not reap |
| temp file / worktree | clean up in `finally`, even on error |

**The test for any spawn:** trace all three exits — success, error, timeout/abandon — and confirm each
one TERMINATES what it started. If any path merely stops waiting, it leaks. **The initiator reaps. No
orphans.** Full detail, the generalization, and the review-lens spec: reap-what-you-spawn-full.md
