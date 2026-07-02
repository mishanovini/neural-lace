# NL Overhaul Program — Baseline Snapshot (2026-07-02)

**Purpose:** the pre-program measurement for the F.4 retro (ADR 058 D7 refutation
criteria) against `docs/plans/nl-overhaul-program-2026-07.md`. Captured by task
B.10 before any of Waves C–F land. Every number below has an exact reproduction
command so a future session can re-measure the same six metrics against the
post-program state without re-deriving the methodology.

Machine: this snapshot was taken on the machine whose main checkout is
`C:/Users/misha/dev/Pocket Technician/neural-lace` and whose live mirror is
`$HOME/.claude` (`C:/Users/misha/.claude`). Numbers are machine-local (per-user
state under `.claude/state/` and `~/.claude/`); the F.4 retro should re-measure on
the same machine for a valid before/after comparison.

## 1. Retry-guard downgrade entries (`unresolved-stop-hooks.log`)

**Value: 321 lines**

Source: main checkout's `.claude/state/unresolved-stop-hooks.log` (project-local
state directory, not the home-dir mirror — this file did not exist under
`$HOME/.claude/state/` at snapshot time).

```bash
wc -l < "C:/Users/misha/dev/Pocket Technician/neural-lace/.claude/state/unresolved-stop-hooks.log"
```

This is the append-only log `lib/stop-hook-retry-guard.sh` writes every time a
blocking Stop hook is downgraded to warn after 3 identical-failure retries with no
new commits (per `~/.claude/rules/git-discipline.md` Rule 3 and the retry-guard
library itself). Each line is one downgrade event; 321 accumulated downgrade
events is itself a data point for RC2 (enforcement theater) — a high downgrade
count means gates are frequently failing to hold across retries.

## 2. Acceptance waiver files count

**Value: 12 files**

Source: `.claude/state/*.txt` files matching `acceptance-waiver-*` in the main
checkout's project-local state directory (per the waiver mechanism documented in
`~/.claude/rules/acceptance-scenarios.md`).

```bash
find "C:/Users/misha/dev/Pocket Technician/neural-lace/.claude/state" \
  -maxdepth 1 -iname "acceptance-waiver-*.txt" | wc -l
```

12 waiver files span 7 distinct plan slugs (`agent-upgrades-batch2-ab-staging`,
`conv-tree-project-root-topology`, `cross-machine-workstreams-coordination-2026-06-04`,
`file-lifecycle-redesign`, `orchestrator-prime` ×2, `plan-lifecycle-redesign` ×3,
`workstreams-ui-status-surface-redesign-2026-06-11` ×3). A high per-plan waiver
count for `orchestrator-prime` and `plan-lifecycle-redesign` in particular is a
signal the effectiveness audit's RC2 finding names directly — repeated waivers on
the same plan rather than a fixed underlying gap.

## 3. External-monitor alert count + acked count

**Value: 33 total alerts, 0 acked**

Source: `~/.claude/state/external-monitor-alerts/*.json` (home-dir mirror; per
`external-monitor-alert-surfacer.sh`'s documented convention, an alert is "acked"
when a sibling `<name>.json.acked` file exists).

```bash
find "$HOME/.claude/state/external-monitor-alerts" -maxdepth 1 -name "*.json" ! -name "*.acked" | wc -l   # total: 33
find "$HOME/.claude/state/external-monitor-alerts" -maxdepth 1 -name "*.json.acked" | wc -l                # acked: 0
```

All 33 captured alerts are `principles-gate-r3-*` — Rule 3 ("distinguish needs-user-input
from should-figure-it-out") warn-mode detections from `principles-compliance-gate.sh`,
spanning 2026-05-29 through 2026-07-01 (the day before this snapshot). **0 of 33
have ever been acknowledged.** This is the audit's RC4 "open-circuit signal loop"
finding made concrete: a full 5-week signal stream with a 0% consumption rate.

## 4. Live rules-dir byte size

**Value: 883,882 bytes (≈ 863 KiB) across 61 files**

Source: every `*.md` file directly under `~/.claude/rules/` (the always-loaded
doctrine corpus per Claude Code's auto-load behavior, per this plan's `## Assumptions`).

```bash
cat "$HOME/.claude/rules"/*.md | wc -c   # 883882
ls "$HOME/.claude/rules"/*.md | wc -l    # 61 files
```

This is the RC1 (context saturation) headline number. The program's stated target
(Wave C, task C.5 Done-when) is `cat ~/.claude/rules/*.md | wc -c` ≤ 30,000 bytes
post-diet — i.e. a ≥96.6% reduction from this baseline.

## 5. Live Stop-chain entry count

**Value: 20 hook entries (1 matcher group)**

Source: `$HOME/.claude/settings.json`, the `hooks.Stop` array.

```bash
node -e '
const fs = require("fs");
const j = JSON.parse(fs.readFileSync(process.env.HOME + "/.claude/settings.json", "utf8"));
const stop = (j.hooks && j.hooks.Stop) || [];
let count = 0;
for (const m of stop) count += (m.hooks || []).length;
console.log("Stop matcher-groups:", stop.length, "total hook entries:", count);
'
# Stop matcher-groups: 1  total hook entries: 20
```

The program's target (Wave D, task D.5 Done-when) is Stop entries ≤ 6. 20 → ≤6 is
the RC5 (unmaintained gate sprawl) headline number for the Stop chain specifically.

For context (not part of this baseline's required six metrics, but useful
cross-reference for the same D.5/D.6 targets): live `PreToolUse` currently has 35
matcher groups / 35 hook entries (target ≤ 12 blocking gates per D.5); live
`SessionStart` currently has 3 matcher groups / 21 hook entries (target ≤ 8 per E.1).

```bash
node -e '
const fs = require("fs");
const j = JSON.parse(fs.readFileSync(process.env.HOME + "/.claude/settings.json", "utf8"));
for (const key of ["PreToolUse", "SessionStart"]) {
  const arr = (j.hooks && j.hooks[key]) || [];
  let count = 0;
  for (const m of arr) count += (m.hooks || []).length;
  console.log(key, "matcher-groups:", arr.length, "total hook entries:", count);
}
'
```

## 6. Live blocking-gate count

**Value (backfilled 2026-07-02 post-B.6): doctor --quick GREEN 6/6, exit 0. Live Stop-chain entries: 20 pre-B.6 → 22 post-B.6** (the count deliberately went UP in Wave B — truth reconciliation wired the six dormant claimed-Mechanisms before Wave D consolidates to ≤6). Per-gate `blocking:` classification (the ≤12 budget metric) is defined by the C.1 manifest; re-record it there. Original pending note preserved below for provenance.

~~Value: pending — `harness-doctor.sh` (task B.1) has not yet landed on this branch~~

Per the B.10 spec ("live blocking-gate count (doctor output once B.6 lands — else
note pending)"): at snapshot time neither `harness-doctor.sh` nor its wiring
reconciliation (B.6) exist yet on the integrated program branch (`claude/modest-satoshi-150d97`
HEAD `e2f9814`, which is B.5's commit — B.1 and B.6 checkboxes are unchecked in the
plan file). This metric is intentionally deferred; re-run the command below once
B.6 has landed and re-record the value in this file (or supersede it in the F.4
retro if this file is not re-opened).

```bash
# once B.1/B.6 have landed:
bash "$HOME/.claude/hooks/harness-doctor.sh" --quick
# doctor's own output enumerates the live blocking-gate count directly.
```

Verified absent at snapshot time:

```bash
ls "$HOME/.claude/hooks/harness-doctor.sh"                                    # No such file or directory
ls "C:/Users/misha/dev/Pocket Technician/neural-lace/adapters/claude-code/hooks/harness-doctor.sh"  # No such file or directory
```

## Snapshot provenance

- Branch: `worker-B.10`, cut from `claude/modest-satoshi-150d97` at commit
  `e2f9814` ("overhaul(B.5): doc truth sweep — 8 items correcting false/stale
  rule-file claims").
- Captured: 2026-07-02, task B.10 of `docs/plans/nl-overhaul-program-2026-07.md`.
- All six numbers above are read-only observations of pre-existing machine state
  (`.claude/state/`, `~/.claude/rules/`, `~/.claude/settings.json`); no files were
  modified to produce this snapshot other than this document itself.
