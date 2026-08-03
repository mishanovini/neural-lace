# Plan: cockpit timeout-orphan tree-kill hotfix (2026-08-02/03 nl.sh "recursion" incident)

Status: ACTIVE
Execution Mode: direct
Mode: code
Backlog items absorbed: none — dispatched directly from the operator's 2026-08-03 incident brief (nl-issues.jsonl 2026-08-03T06:53Z)
acceptance-exempt: true
acceptance-exempt-reason: Infrastructure hotfix to the cockpit's subprocess reaper; no product-user surface changes. The demonstration is the livetest tree-kill oracle plus the operator-mandated 10-minute post-restart observation window (bash process count + syscalls/sec flat), recorded in the session report.
tier: 1
rung: 1
architecture: coding-harness
frozen: true
lifecycle-schema: v2
owner: Misha
target-completion-date: 2026-08-03
prd-ref: n/a — incident hotfix
ask-id: none — operator incident brief 2026-08-03

## Goal

Stop the 2026-08-02/03 cockpit storm at its manufacture point. Root cause
(full evidence: `docs/handoffs/2026-08-03-cockpit-nl-recursion-rootcause.md`):
`derive-cache.js` `spawnAsync`'s timeout ran bare `child.kill()`, which on
Windows terminates only the direct child — the Git-for-Windows bin-bash
LAUNCHER — orphaning the real derivation tree on every timeout. Windows
never reaps orphans; each refresh tick whose `nl status --json` exceeded
its 180s timeout manufactured one ~20-minute orphan tree (measured live:
one new chain per 5-min anti-entropy tick, 1.5M syscalls/sec sustained).
`server.js` `runAskRegistryCli`'s timeout was worse: it resolved without
killing anything. Fix: `killTree()` (taskkill /T /F on win32,
process-group kill on POSIX) — the exact fix auditor.js already carries
for this class (NL-FINDING 2026-07-14), never propagated to these two
sites.

## User-facing Outcome

n/a — harness/cockpit-internal: the maintainer is the user. The
demonstration is (a) the livetest oracle proving a production-shaped
fork-linked bash tree fully dies on timeout-kill (survivors=[]), and
(b) the operator-mandated 10-minute observation window after the
ensure-cockpit restart showing bash process count and syscalls/sec flat
(no orphan accumulation across ≥2 anti-entropy ticks).

## Scope

- IN: `killTree()` added to
  `neural-lace/workstreams-ui/server/derive-cache.js` (spawnAsync timeout
  path; exported); `neural-lace/workstreams-ui/server/server.js`
  `runAskRegistryCli` timeout now tree-kills; the root-cause handoff doc
  `docs/handoffs/2026-08-03-cockpit-nl-recursion-rootcause.md`; this plan.
- OUT: nl.sh / observability-derive.sh performance (the reason `nl status`
  exceeds 180s — known, filed elsewhere: O.9/backlog-oracle + status perf
  regression); the disarmed orphan reaper (P-13); the
  `server.selftest.js` line-893 pre-existing crash (filed to
  nl-issues.jsonl 2026-08-03); ensure-cockpit resurrection UX (its
  documented `cockpit-disabled` flag is the sanctioned off-switch and was
  used during this fix window).

## Tasks

- [ ] 1. Add `killTree()` to `derive-cache.js` and call it from
  `spawnAsync`'s timeout (replacing bare `child.kill()`); export it;
  document the MSYS exec-shim residual honestly — Verification: full
  (livetest oracle: production-shaped fork tree, survivors=[]) — Docs
  impact: root-cause handoff doc lands same commit
- [ ] 2. `server.js` `runAskRegistryCli`: kill the child tree on timeout
  (previously resolved without killing — pure leak) — Verification:
  contract (node --check + state-watch/maintenance-pane selftests green;
  exercised live by the post-restart observation window) — Docs impact:
  none beyond the shared handoff doc

## Files to Modify/Create

- `neural-lace/workstreams-ui/server/derive-cache.js` — killTree + timeout call + export
- `neural-lace/workstreams-ui/server/server.js` — runAskRegistryCli timeout tree-kill
- `docs/handoffs/2026-08-03-cockpit-nl-recursion-rootcause.md` — evidenced diagnosis (new)
- `docs/plans/cockpit-orphan-treekill-hotfix-2026-08-03.md` — this plan (new)

## Assumptions

- `taskkill /T /F` reliably walks live ParentProcessId links (verified by
  livetest on this machine); MSYS fork chains keep those links live.
- The cockpit is the only spawner matching the `bash -l <nl-bin> <sub>
  --json` shape, so no operator-interactive process is at kill risk.
- The 5-min anti-entropy floor (0808f2d9) remains the refresh cadence; the
  fix is correct at ANY cadence (it removes orphan manufacture, not ticks).

## Edge Cases

- taskkill absent/fails → killTree falls back to `child.kill('SIGKILL')`
  (the pre-fix behavior; degraded, never worse than before).
- Child already exited at timeout → taskkill exits nonzero harmlessly
  (`stdio: 'ignore'`, error handler swallows).
- POSIX estates → process-group kill with plain-kill fallback (auditor.js
  precedent, unchanged semantics there).
- In-flight external binaries (jq/grep/date) at kill moment: MSYS
  fork+exec breaks their parent link, so /T cannot reach them — they exit
  on pipe EOF/EPIPE within ms (measured; documented in the code comment).

## Acceptance Scenarios

n/a (acceptance-exempt; see reason above). The binding demonstrations are
the livetest oracle and the 10-minute observation window.

## Out-of-scope scenarios

- Making `nl status --json` fast enough to never time out (perf work,
  separately tracked).
- Arming the P-13 orphan reaper (defense-in-depth for OTHER leak sources).

## Closure Contract

- **Commands that run:** `node --check` on both touched files; livetest
  oracle (scratchpad killtree-livetest3.js) against the edited
  derive-cache.js; `state-watch.selftest.js`; `maintenance-pane.selftest.js`;
  post-restart 10-minute observation loop (bash count + `\System\System
  Calls/sec` sampled ~60s).
- **Expected outputs:** livetest `{"survivors":[],"pass":true}`; selftests
  0 failed; observation window shows no monotone growth in bash count and
  no nl.sh process older than one timeout window surviving.
- **On-disk artifact location:** the handoff doc + the session report's
  observation table.
- **Done when:** both tasks checked AND the fix is merged to master AND
  the pinned ws-ui-server checkout carries it AND the observation window
  is green.

## Testing Strategy

- Task 1: livetest oracle (production-shaped launcher→script-bash→subshell
  fork tree; assert every ParentProcessId-reachable member dies).
- Task 2: node --check + module selftests (its 180s path is impractical to
  drive synthetically in-session; the observation window exercises the
  server live).
- End-to-end: ensure-cockpit restart + 10-minute observation window
  measuring the exact metrics from the incident brief (bash process count,
  syscalls/sec).

Walking Skeleton: n/a — two call-site fixes reusing a proven in-repo
pattern; no new architectural layers.

## Decisions Log

- 2026-08-03 (decide-and-go, constitution §8 — reversible): plan file
  opened AFTER the fix was built and verified, mirroring the sanctioned
  hotfix flow (scope-enforcement-gate Scenario 12 precedent,
  `workstreams-debounce-and-sentinel-tests-hotfix-2026-07-29.md`;
  `frozen: true` at birth).
- 2026-08-03 (decide-and-go, reversible): reused auditor.js's killTree
  shape verbatim (taskkill /T /F + fallbacks) rather than inventing a
  marker-sweep or Job-Object mechanism — the in-repo precedent is
  production-proven for this class; the MSYS exec-shim residual it cannot
  reach is measured, bounded (ms-lived, pipe-bound leaves), and documented
  in the code comment.
- 2026-08-03 (decide-and-go, reversible): did NOT reorder BASH_CANDIDATES
  (usr/bin/bash first would drop the launcher layer) — minimal-diff
  principle; taskkill /T kills through the launcher anyway, and the
  launcher's env-setup semantics stay untouched.

## Definition of Done

- [ ] Both tasks checked off
- [ ] Livetest oracle green; both selftests 0 failed
- [ ] Fix merged to master; pinned ws-ui-server checkout updated to include it
- [ ] 10-minute post-restart observation window green (flat bash count + syscalls)
