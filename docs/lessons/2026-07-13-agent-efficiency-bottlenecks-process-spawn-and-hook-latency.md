# Lesson — Agent Efficiency Bottlenecks on Windows: the Process-Spawn Tax, Hook Latency, and Context Overhead

**Date:** 2026-07-13
**Source case:** A diagnostic session that began with the operator noticing *Antimalware Service
Executable* (Windows Defender / MsMpEng) burning ~50% CPU around Claude's work, and widened into
the general question: **"How do we identify the bottleneck in different circumstances and relieve
it? Is there latency/friction in spinning up the processes a session initiates, or in the tools it
uses, and can we improve the tools or the framework around them?"**
**Nature:** This is a *measurement + framework* lesson, not a failure post-mortem. Everything below
with a number was measured on this machine (Windows 11, Git Bash / MSYS2) during the session; the
raw commands are reproducible and cited inline. Claims are tagged **MEASURED** (timed here) or
**HYPOTHESIZED** (reasoned, with the refuter named).
**Harness gaps exposed:** (1) no single-flight lock on SessionStart scripts → Defender fork-storm;
(2) hooks are large monolithic bash scripts that pay a per-invocation parse+spawn tax on Windows,
including retired `exit 0` shims that still fire; (3) agents reach for disk-wide `find` instead of
`git rev-parse`. Filed: `SESSIONSTART-SINGLEFLIGHT-01` (backlog) + 3 nl-issues; this lesson is the
consolidated write-up the operator asked for.

---

## 0. TL;DR — where the cycles actually go

On **Windows specifically**, the agent's #1 hidden cost is **process creation**. Windows has no
`fork()`; every subprocess is a full `CreateProcess` routed through the MSYS2/Git-Bash emulation
layer, and Windows Defender real-time protection scans each process-create and file-open. Measured
here:

| Operation | Cost (MEASURED) | Why it matters |
|---|---:|---|
| `bash -c 'true'` (bare spawn) | **190 ms** | The floor. Every hook, every piped `jq`/`git` pays this. Linux equivalent ≈ 1–2 ms. |
| `jq` one-shot (`echo … \| jq`) | **174 ms** | Most hooks extract `tool_input` via `jq`. |
| `git rev-parse --show-toplevel` | **225 ms** | The *correct* cheap way to find repo root — still 225 ms here because it's a spawn. |
| `node -e 'process.exit(0)'` | **532 ms** | Every subagent, MCP server, and `node`-based tool pays this at startup. |
| A representative hook body `(jq \| grep)` | **260 ms** | A *small* hook's real per-call cost. |
| `no-test-skip-gate.sh` early-exit (129 lines) | **547 ms** | A small hook, *passing* — not even acting. |
| `scope-enforcement-gate.sh` early-exit (2076 lines) | **1,096 ms** | A large hook takes **over a second to decide to do nothing**. |

**The compounding effect:** a single **Bash** tool call fires **10 PreToolUse hooks** (see §3). Each
is its own bash process. Whether Claude Code runs them in parallel or sequentially, the aggregate is
**seconds of CPU and ~10–30 process-creates per tool call** — every one of which Defender scans. That
is the MsMpEng CPU the operator saw, and it is also invisible latency on every command the agent runs.

The **second** hidden cost is **context/Model-I/O overhead** (§5): ~12K tokens (~6% of a 200K window)
of harness doctrine is injected on *every* API call before any real work, and cumulative tool results
fill the rest across a long session until compaction.

---

## 1. The diagnostic framework: four resource pools, and how to tell which is saturated

The operator's insight — *"the bottleneck changes depending on what sort of effort is being used"* —
is exactly right. An agent session draws on four distinct resource pools. Two are visible in Task
Manager; two are invisible and usually dominant.

| Pool | Visible? | Saturated by | Symptom | How to identify |
|---|---|---|---|---|
| **Local compute** | Yes (Task Mgr CPU) | Process spawns (hooks, subshells), disk-wide `find`, Defender scanning | High CPU on `MsMpEng`, `bash.exe` ×N, `node.exe` ×N | Task Manager process list; count `bash.exe` instances |
| **Local memory** | Partly | Many concurrent Claude/node processes; large file reads held in RAM | RAM pressure, swapping | Task Mgr; `~5.3 GB` for 18 Claude + 14 node procs (MEASURED this session) |
| **Model I/O** | **No** | Always-loaded doctrine, cumulative tool results, reasoning tokens | Slow turns, early compaction, "lost the thread" | Transcript byte analysis (§5); context-watermark hook |
| **Remote / network** | **No** | API rate limits (429/529), CI queues, MCP server round-trips | Stalls with low local CPU; 529s; agent fan-out throttling | API error logs; `feedback_stagger_api_init` memory |

**The identification protocol** (what to run when the agent "feels slow"):

1. **Open Task Manager first.** If `MsMpEng` + `bash.exe`×N + `node.exe`×N dominate → **local
   compute**, and the cause is the process-spawn storm (§2–§4). This is the Windows-default failure.
2. **If local CPU is low but turns are slow** → **Model I/O** (context too full → each turn re-reads
   a huge window) or **remote** (waiting on API/CI). Check the transcript size and the API error tail.
3. **If RAM is the ceiling** (many parallel worktree agents) → **local memory**; reduce fan-out width.
4. **Map the work-mode to the expected bottleneck** (below) and confirm, rather than guessing.

### Work-mode → expected #1 bottleneck (confirmed against measurements)

| Work mode | #1 bottleneck | #2 | Relief lever |
|---|---|---|---|
| Single interactive edit/command | Hook latency + spawn tax (§3–4) | Model reasoning time | Coalesce hooks; retire dead hooks; Defender exclusions |
| Search-heavy exploration | Local compute (find/grep spawns) + context fill from results | Defender scan | Use `Grep`/`Glob` tools (ripgrep, one process) not shell `find`; use subagents to keep results out of main context |
| Orchestrator fan-out (parallel builders) | Remote API rate limits (529) | Local RAM + spawn ×workers | Stagger init in waves (`feedback_stagger_api_init`); cap width ≤5 |
| Long autonomous session | Model I/O — context window fill | Compaction data loss | Trim/summarize old tool results; lean on SCRATCHPAD as durable state |
| Build + test | Test execution time | Pre-commit hook chain (harness-sync + tests) | Unavoidable-but-real; keep the gate chain lean |

---

## 2. Finding 1 — the Windows process-spawn tax (root cause of the Defender CPU)

**MEASURED:** `bash -c 'true'` = **190 ms/spawn**; `node` startup = **532 ms**; `jq` = **174 ms**.

On Linux, `fork()` + copy-on-write makes a subprocess nearly free (~1 ms). Windows has no `fork()`;
Git Bash emulates POSIX process semantics through the MSYS2 runtime, so every `bash`, `jq`, `git`,
`grep`, `sed` is a full `CreateProcess` + DLL load + emulation-layer setup. **Windows Defender
real-time protection intercepts every one of those process-creates and file-opens to scan them** —
which is *why* MsMpEng, not `bash.exe`, showed as the top CPU consumer. Defender is doing real work;
it is just doing it because the harness generates a fork storm.

**The fork storm, quantified (MEASURED, prior session):** concurrent SessionStart hooks (doctor +
digest + auto-install, with **no single-flight lock**) drove the live `bash.exe` process count from
**34 → 81** in seconds, with MsMpEng at ~125% of a core scanning them all.

**Why the harness shape makes this worse:** the harness is *process-oriented*. Rules are enforced by
standalone bash scripts that shell out to `jq`/`git`/`grep`. Each is defensible individually; in
aggregate, on Windows, they are a spawn multiplier.

---

## 3. Finding 2 — hook latency compounds the tax (the load-bearing finding)

The hook wiring (MEASURED from live `~/.claude/settings.json`):

| Event | Hook commands | Fires on |
|---|---:|---|
| **PreToolUse** | 16 total | every tool call (matcher-filtered) |
| → per **Bash** call | **10 hooks** | every shell command |
| → per **Edit/Write** call | **6 PreToolUse + 2 PostToolUse = 8** | every file mutation |
| Stop | 5 | session end |
| SessionStart | 5 (+1 on compact) | session start |
| UserPromptSubmit | 1 | every user message |
| Notification | 1 | notifications |

**The critical measurement — hooks pay a parse+spawn tax even when they pass:**

| Hook | Lines | Early-exit cost on a *non-matching* command (MEASURED) |
|---|---:|---:|
| `no-test-skip-gate.sh` | 129 | **547 ms** |
| `scope-enforcement-gate.sh` | 2,076 | **1,096 ms** |

The large hook takes **over a second to decide it has nothing to do**, because bash must lex and parse
all 2,076 lines before it reaches the early-exit branch, *and* it runs `jq` + command-splitting logic
before concluding the command isn't a `git commit`. **Script size is a per-invocation runtime cost on
Windows, not merely a maintainability concern.**

**Aggregate per Bash call:** 10 hook processes, several in the 500–1,100 ms range, several in the
250–360 ms range. If Claude Code runs them **sequentially**, that is ~4–6 s of pure hook latency per
shell command (HYPOTHESIZED — refuter: if CC parallelizes hooks, wall-clock is bounded below by the
slowest, ~1.1 s, but the *CPU* and the *process-create count Defender scans* are unchanged). Either
way: **every trivial `ls` the agent runs triggers ~10 process spawns and ≥1 s of overhead.**

**Worst-of-both example — dead weight that still costs:** `tool-call-budget.sh` is a **retired `exit 0`
shim** (3 lines: *"Retired to attic/ … Exit-0 shim for sessions started pre-cutover"*). It is still
wired into PreToolUse and **still spawns a bash process (~190 ms) on every Bash/Edit/Write to do
nothing.** A retired hook is not free on Windows.

---

## 4. Finding 3 — agent tool-choice behavior (the self-inflicted spike)

**MEASURED / OBSERVED (prior session):** a live `find / -maxdepth 6 -iname neural-lace -type d`
(PID 19396) consuming **~65% of a core** — a full-disk scan issued by an agent to locate the repo
root. Every harness script that needs the repo root uses the cheap `git rev-parse --show-toplevel`
(confirmed by reading `session-wrap.sh:62`, `dispatch-ci-watcher.sh:69`, `harness-evaluator.sh:65`,
and others — none do a disk-wide `find`). So the `find /` is **agent ad-hoc behavior**, not the
harness. On Windows a disk-walk is pathological: every directory `stat` is a syscall through the
emulation layer, and Defender scans each opened path.

**The lesson for agent behavior:** reach for the **dedicated tool** (`Grep`/`Glob`, which run a single
ripgrep process) or `git rev-parse` — never shell `find /`. This is now also a candidate for a
PreToolUse warn-hook that catches `find /` / `find ~` disk-wide scans and suggests the alternative.

---

## 5. Finding 4 — Model I/O / context overhead (the invisible, often-#1 pool)

**MEASURED** always-loaded context (injected into *every* API call, before any user content):

| Component | Bytes | ~Tokens |
|---|---:|---:|
| `~/.claude/CLAUDE.md` | 4,230 | 1,058 |
| `~/.claude/rules/constitution.md` | 10,385 | 2,596 |
| Project memory (8 files) | 14,940 | 3,735 |
| `SCRATCHPAD.md` | 2,490 | 623 |
| Claude Code system prompt (est.) | ~15,000 | ~3,750 |
| **Total always-loaded** | **~47,000** | **~11,800 (~6% of a 200K window)** |

**Doctrine JIT (well-designed, low cost):** `doctrine-jit.sh` injects a doctrine compact **once per
session per matching surface** (PostToolUse on Edit/Write), capped at 6,000 bytes/injection. There are
**45 compact doctrine files (~3 KB each)**; a typical build session pulls in ~4 of them (~12 KB). This
is the *right* pattern — pay for a rule only when you touch its surface — and needs no change.

**The real context killer is cumulative tool results.** Context is additive: every file read and every
command output stays in the window until compaction. A session with 50 Bash calls averaging ~2 KB of
output holds ~100 KB (~25K tokens) of *historical* tool output. The largest transcript on this machine
is **140 MB / 32,813 turns** — that is what unbounded accumulation looks like at the limit, and
compaction (where sessions lose coherence) is the direct consequence.

**Budget summary for a mid-size session:** ~200K window − ~12K always-loaded − ~3K JIT − ~2K hook
injections − ~5K tool-result framing ≈ **~178K (~89%) available for actual work** early on, degrading
turn-over-turn as tool results accumulate.

---

## 6. Tool friction — which tools, what friction, what to prefer

| Situation | Friction | Better choice |
|---|---|---|
| Finding files by name/pattern | Shell `find` = one process per traversal + full-disk risk on Windows | **`Glob`** tool (single ripgrep pass) |
| Searching file contents | Shell `grep -r` = spawn + no permission integration | **`Grep`** tool (ripgrep; integrates with permission UI) |
| Locating repo root | `find / -iname repo` = ~65% of a core (§4) | `git rev-parse --show-toplevel` (225 ms) |
| Reading a known file region | `cat`/`head`/`tail` = spawn each | **`Read`** tool with `offset`/`limit` (no spawn) |
| Any multi-step shell pipeline | Each stage is a Windows spawn (~190 ms × stages) | Collapse to one `jq`/`awk` program, or a single tool call |
| Large search fan-out | Results land in *main* context and fill the window | Dispatch a **subagent** (`Explore`/`explorer`) — it pays the token cost in its own window and returns only the conclusion |
| Repo-root/branch checks the harness already did | Re-running them ad hoc | Read the **SessionStart digest** already injected (git-freshness, worktree, account map) |

**General rule the agent should internalize:** on this machine, *prefer the in-process dedicated tool
(`Read`/`Grep`/`Glob`) over shelling out*, because each shell-out is a ~190 ms Windows spawn that
Defender scans. Reserve `Bash` for things only a shell can do (git, builds, running programs).

---

## 7. Recommendations, ranked by leverage

**Tier 1 — highest leverage, lowest risk (do these first):**

1. **Windows Defender exclusions for the harness working set** (`SESSIONSTART-SINGLEFLIGHT-01`, part 2).
   Exclude `~/.claude/`, the Git Bash install dir, and the active repo/worktree roots from real-time
   scanning. This directly removes the MsMpEng scan-per-spawn cost — the single biggest visible CPU
   sink. *Operator action required* (admin / Windows Security UI); verify current exclusion list first.
   **HYPOTHESIZED impact:** eliminates most of the ~50% MsMpEng CPU. Refuter: if exclusions are already
   set and MsMpEng is still high, the cause is elsewhere (re-measure).

2. **Single-flight lock on SessionStart scripts** (`SESSIONSTART-SINGLEFLIGHT-01`, part 1). A lockfile so
   doctor/digest/auto-install don't run concurrently across simultaneously-starting sessions. Kills the
   34→81 `bash.exe` spike at its source.

3. **Retire the dead `exit 0` shims from the live hook wiring.** `tool-call-budget.sh` (and any sibling
   attic shims) still spawn a process per tool call to do nothing. Removing them from `settings.json`
   is pure win: −1 spawn per Bash/Edit/Write, zero behavior change.

**Tier 2 — structural, higher effort, needs harness-reviewer + `--self-test`:**

4. **Coalesce the 10 per-Bash PreToolUse hooks into one dispatcher.** A single `pretooluse-dispatch.sh`
   that reads `tool_input` **once**, then runs the individual checks as **shell functions in-process**
   (no re-spawn, no re-parse, one `jq`). Turns ~10 process-creates + ~10 script-parses into **1**.
   **HYPOTHESIZED impact:** ~5–8× fewer spawns per Bash call and elimination of the large-script parse
   tax. Refuter: if CC's hook model requires separate processes for independent block semantics, the
   dispatcher must preserve per-check exit codes — verify the block-message contract survives.

5. **Shrink or lazy-load the giant hooks.** `scope-enforcement-gate.sh` (2,076 lines) and
   `plan-deletion-protection.sh` (1,018 lines) should **cheaply pre-filter first** (a 2-line grep: "is
   this even a `git commit`/deletion? if not, `exit 0`") *before* sourcing the heavy parsing logic, so
   the common pass-path never parses the 2,000-line body. Cuts the ~1.1 s early-exit to ~0.2 s.

6. **A `find /` warn-hook** (or agent-doctrine reinforcement) that catches disk-wide `find ~` / `find /`
   and suggests `Glob` / `git rev-parse`. Addresses Finding 3 at the mechanism level.

**Tier 3 — Model I/O hygiene (long-session quality):**

7. **Context-aware tool-result trimming.** A watermark/summarizer that collapses old, superseded tool
   outputs so a long session's window doesn't fill with stale `ls`/`grep` dumps. Extends effective
   session length and delays coherence-losing compaction.

8. **Keep leaning on the JIT + SCRATCHPAD design** — it's already the right shape. Don't move doctrine
   back into always-loaded; don't let SCRATCHPAD exceed its 30-line cap.

---

## 8. What was persisted / filed (in-session, per constitution §5)

- **This lesson** (`docs/lessons/2026-07-13-agent-efficiency-bottlenecks-process-spawn-and-hook-latency.md`).
- **`SESSIONSTART-SINGLEFLIGHT-01`** — backlog row (`docs/backlog.md`): single-flight lock + Defender-
  exclusion doctrine.
- **3 nl-issues** (machine-wide ledger): (a) SessionStart fork-storm; (b) disk-wide-`find` agent
  behavior; (c) `session-wrap.sh` Signal-3 false-fire (temporal over-attribution + `tranche` keyword
  over-match) — the loop pathology observed earlier this session.
- **New candidates surfaced by this write-up** (not yet filed as their own rows — flagged here for the
  review session to triage): retire dead `exit 0` hook shims (rec 3); PreToolUse dispatcher coalescing
  (rec 4); cheap pre-filter for giant hooks (rec 5); `find /` warn-hook (rec 6).

### 8b. Disposition (2026-07-13 review session — `docs/plans/lessons-learned-fixes-2026-07-13.md`)

An assess+adversarially-verify audit (26 agents, 0 disagreements) classified every rec, then a
fix plan landed the actionable ones:
- **rec 5 (giant-hook pre-filter) — IMPLEMENTED.** `scope-enforcement-gate.sh` + `plan-deletion-protection.sh`
  now short-circuit the common non-matching path before any jq/sed spawn (measured ~612→205 ms on
  scope-enforcement); self-tests unchanged (34/33, 18/18).
- **rec 6 (`find /` warn-hook) — IMPLEMENTED.** New `find-scan-warn.sh` (non-blocking, 11/11 self-test).
- **rec 2 (single-flight lock) — PARTIALLY IMPLEMENTED.** `lib/sessionstart-singleflight.sh` ttl-debounce
  now gates `session-start-auto-install.sh` (the fork-storm's biggest source); digest left ungated
  (per-session operator output). `SESSIONSTART-SINGLEFLIGHT-01` annotated with what remains.
- **rec 1 (Defender exclusions) — OPERATOR-ONLY, artifact already shipped** (`setup-defender-exclusions.ps1`).
- **rec 3 (retire dead shim) — DEFERRED** → backlog `HOOK-SHIM-RETIRE-01` (removal needs a live settings
  reconcile that would race concurrent sessions).
- **rec 4 (PreToolUse dispatcher) — DEFERRED** → backlog `PRETOOLUSE-DISPATCHER-01` (high blast radius;
  needs its own plan + harness-reviewer).
- **rec 7 (tool-result trimming) — OBSOLETE** (unbuildable as a hook; the warning half already ships as
  `context-watermark.sh`).

## 9. Reproducing the measurements

All timings are `date +%s%N` deltas around loops, run in the repo root under Git Bash on the host
machine, 2026-07-13:

```bash
# Spawn tax
for i in $(seq 1 50); do bash -c 'true'; done          # → ~190 ms/spawn
for i in $(seq 1 20); do echo '{"a":1}' | jq -r '.a'; done   # → ~174 ms
for i in $(seq 1 10); do git rev-parse --show-toplevel; done # → ~225 ms
node -e 'process.exit(0)'                               # → ~532 ms

# Hook early-exit tax (non-commit command)
export CLAUDE_TOOL_INPUT='{"tool_input":{"command":"ls -la"},"tool_name":"Bash"}'
for i in $(seq 1 10); do echo "$CLAUDE_TOOL_INPUT" | bash adapters/claude-code/hooks/scope-enforcement-gate.sh; done  # → ~1096 ms
for i in $(seq 1 10); do echo "$CLAUDE_TOOL_INPUT" | bash adapters/claude-code/hooks/no-test-skip-gate.sh; done       # → ~547 ms
```

Context/wiring figures come from `~/.claude/settings.json` (hook counts), byte sizes of the doctrine
files, and transcript JSONL analysis under
`~/.claude/projects/C--Users-misha-claude-projects-neural-lace/`.
