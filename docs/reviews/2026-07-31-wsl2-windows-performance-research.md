# Research — WSL2 vs Native Windows for a 105-Hook, ~30-Session Claude Code Estate

**Date:** 2026-07-31
**Method:** 4 parallel web-research agents (WSL2+Claude Code field reports · WSL2 pitfalls ·
Windows alternatives · Claude Desktop/Cowork) → adversarial verification of every load-bearing
claim → synthesis. 11 agents, ~1.04M tokens, 254 tool calls, 0 errors.
**Grounding measurements (this machine, PROVEN):** Git Bash spawn 190 ms · jq 174 ms · node 532 ms ·
large hook 1096 ms to early-exit · ~10 hooks per Bash tool call ≈ **1.9 s spawn tax per tool call** ·
WSL2 marginal spawn **< 0.15 ms** (below noise floor) — a >1000× gap on the dominant cost.

## Verdict: migrate to WSL2 — but for the spawn tax, not the reasons the internet argues about

The bottleneck here is `CreateProcess`, not file I/O. Nearly every public WSL2 benchmark measures
*filesystem* throughput — a different axis than ours. **No public source has ever measured a
hook-heavy harness's spawn cost, so our own numbers are the most reliable evidence in this report.**

### Two popular claims that FAILED adversarial verification
1. **"Native Windows only achieves ~70% performance"** — REFUTED. Traced to a forum remark about
   *tool compatibility*, likely contaminated by the unrelated 70.3% SWE-bench score. Do not cite it.
2. **"Anthropic says stay native / WSL is slow"** — MISLEADING. The `/mnt/c` slowness quote is real
   but is fix **#3 of 3** in Anthropic's troubleshooting, ranked *below* their preferred fix: move
   the repo to `/home/`. On ext4 it does not apply. The setup docs frame native-vs-WSL as neutral.

### Two findings that INDICT native Windows for our specific configuration
- **[anthropics/claude-code#77078](https://github.com/anthropics/claude-code/issues/77078)** (OPEN,
  2026-07-13, `platform:windows`): hook processes left **SUSPENDED** with zero CPU, hanging turns
  30–60+ min, Escape doesn't cancel; linked to a documented **1.2–5% hook execution failure rate on
  Windows**. A 105-hook harness is the maximum-exposure configuration for this bug.
- Our 12.25 GB paged-pool / 182k-handle reboot cycle is Windows kernel object churn from process
  storms; WSL2 spawns are accounted in the Linux kernel instead. (HYPOTHESIZED — refuter: pool still
  bloats post-migration.)

## The one risk that could kill the migration — test for it explicitly
**WSL2-specific "thinking phase" latency regression** —
[#22855](https://github.com/anthropics/claude-code/issues/22855) /
[#41649](https://github.com/anthropics/claude-code/issues/41649): 1–6 minute pre-response delays on
WSL2, instant on native Linux, same account. **Closed as "not planned" by a staleness bot — never
confirmed fixed, and no post-March-2026 reproduction either way.** Instrument
**time-to-first-token** during the pilot; multi-minute pre-response delays = abort and stay native.

## Gotchas ranked for this estate
1. **Repos on `/mnt/c` waste the entire move** ([WSL#4197](https://github.com/microsoft/WSL/issues/4197),
   842 reactions, open since 2019; a July-2026 tester measured `/mnt/c` still ~12× slower than WSL1).
   Windows-side edits also never fire inotify ([#4739](https://github.com/microsoft/WSL/issues/4739)).
   **Clone to `/home`. No exceptions.**
2. **Defender still scans the VHDX from the Windows side**
   ([WSL#8995](https://github.com/microsoft/WSL/issues/8995), confirmed Feb 2026) — our existing
   exclusions do NOT cover it. Add `ext4.vhdx` + `vmmemWSL`.
3. **Docker Desktop shares the same utility VM** — one global memory/CPU budget, and it keeps distros
   alive after `wsl --shutdown`, defeating `.wslconfig` reloads and compaction.
4. **Disk is a one-way ratchet** ([WSL#4699](https://github.com/microsoft/WSL/issues/4699) — the
   repo's most-upvoted open issue, 1,414). **Do NOT set `sparseVhd=true`** — disabled in the shipping
   product for *data corruption*; `Optimize-VHD` has fresh 2026-07 corruption reports.
5. `export USERPROFILE=/mnt/c/Users/<user>` in `~/.bashrc` — free insurance against a powershell.exe
   spawn storm ([#29672](https://github.com/anthropics/claude-code/issues/29672); magnitude was
   double-counted in the original report, current status unverified).
6. Sandbox blocks all Windows binaries on WSL2; raise `fs.inotify.max_user_watches` to 524288;
   **stay on default NAT networking** — mirrored mode has two July-2026 localhost-breaking bugs.
7. WSL OAuth failure is a recurring class ([#20756](https://github.com/anthropics/claude-code/issues/20756),
   [#44136](https://github.com/anthropics/claude-code/issues/44136)) — keep native Claude Code
   installed as a fallback.

## Alternatives — what's worth our time
| Option | Verdict |
|---|---|
| **Cowork kill via OFFICIAL policy key** | **YES, now.** `HKLM\SOFTWARE\Policies\Claude` → `secureVmFeaturesEnabled=0` ([Anthropic enterprise config](https://support.claude.com/en/articles/12622667-enterprise-configuration-for-claude-desktop)). Supersedes our community JSON-config workaround. **Never disable `VirtualMachinePlatform`** — that breaks WSL2 *and* Docker. |
| **Narrow AV exclusions** | **YES, 20 min.** Measured 8.5× on a 6-parallel-Bash burst, biggest gain from `Git\mingw64\bin` + `Git\usr\bin`. Even 8.5× leaves ~22 ms/spawn vs <0.15 ms in WSL2. |
| **Dedicated Linux box** | **YES — the real destination.** ~4 GB/agent → 20–30 agents = 80–120 GB. **Our 64 GB is the true ceiling regardless of OS.** Hetzner AX ~€54/mo + tmux; inference is remote so server CPU barely matters. |
| **Dev Drive / ReFS** | **NO.** Measured −62% to +75%; one full build ran 43% *slower*. Wrong bottleneck. (Retracts an earlier recommendation in this estate.) |
| **git fsmonitor / untrackedCache** | Marginal + a known correctness bug with both enabled. Skip. |
| **`claude --cloud` / dev containers** | **NO.** Cloud has no local filesystem or MCP — incompatible with a 105-hook local harness. Dev containers on Windows run *on* WSL2 anyway. |
| **Mac** | **NO.** Apple-silicon RAM buys local *inference*, which Claude Code doesn't use. |

## What the evidence does NOT settle
- **Whether WSL2 switchers stay switched is unknown** — Reddit was inaccessible to the crawler, so
  that entire source class is missing. Treat "everyone moved to WSL" claims as unsupported.
- The latency regression's current status is genuinely unknown (bot-closed, no maintainer fix).
- Anthropic's docs pull both ways, and neither statement was written with a 105-hook harness in mind.

## Plan
1. **Today, zero migration risk:** set the Cowork **policy registry key**; add `Git\mingw64\bin` +
   `Git\usr\bin` AV exclusions; re-run the spawn benchmark to see fully-tuned native Windows.
2. **Pilot:** Ubuntu 24.04; `.wslconfig` `memory=48GB, processors=12, swap=8GB,
   autoMemoryReclaim=dropCache`; repo cloned to `/home`; `export USERPROFILE`; inotify 524288;
   Defender exclusions on `ext4.vhdx` + `vmmemWSL`; system ripgrep + `USE_BUILTIN_RIPGREP=0`.
3. **Re-run our exact benchmark inside it** + real per-Bash-tool-call harness cost. *That*
   measurement decides — not this report.
4. **A/B one workstream for a week**, instrumenting **time-to-first-token**. Multi-minute
   pre-response delays ⇒ that's #41649 ⇒ abort, stay native.
5. If it holds, migrate the fleet; keep native Claude Code installed as Windows-task + OAuth fallback.
6. **In parallel, price a dedicated Linux box** — WSL2 fixes spawn cost; it does not fix the RAM
   ceiling for 20–30 concurrent agents.
