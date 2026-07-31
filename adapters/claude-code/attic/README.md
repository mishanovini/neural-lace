# attic/ — retired hooks, kept one release

<!-- last-verified: 2026-07-05 (doctor-checked) -->

## Why this directory exists

When the NL Overhaul Program (ADR 058) retires a hook — because it was
consolidated into a stronger replacement, demoted from a blocking gate to a
non-blocking ledger warning, or superseded outright — the hook's file moves
here rather than being deleted outright. A 3-line exit-0 shim is left at the
hook's OLD live path (see the `wave-d-retired-shims` manifest entry) so a
session that snapshotted its hook configuration at session start — before an
`install.sh` refresh moved the file — does not error mid-session when its
Stop/PreToolUse chain still names the old path. Deleting the file outright the
moment a wave lands would break that already-running session; the shim +
attic pair keeps retirement safe for anyone mid-session at cutover time (ADR
058 D5 pin c: "Retired hooks move to `adapters/claude-code/attic/**` AND leave
a 3-line exit-0 shim at their old live path for one release").

## Retention rule: ONE release, then hard-delete

A file lands here at the wave that retires it and is hard-deleted at the
START of the NEXT wave/release — not sooner (live-session safety would break)
and not indefinitely (attic is not a second home for dead code; it is a
one-cycle safety buffer). Concretely:

- Wave D retired the Stop-chain hooks currently sitting here (narrate-and-wait,
  deferral-counter, transcript-lie-detector, imperative-evidence-linker,
  goal-coverage/goal-extraction, decision-context-gate, principles-compliance,
  pr-health-snapshot, customer-facing-review, completion-criteria,
  register-progress-gate, pre-stop-verifier, product-acceptance,
  worktree-teardown, continuation-enforcer, tool-call-budget,
  dag-review-waiver, check-harness-sync, settings-divergence-detector,
  cross-repo-drift-warn, decision-context-replay) per ADR 058 D5 — see the
  manifest's `wave-d-retired-shims` entry for the exact list and its
  `honest_status` field for the current shim state.
- These are due for hard-delete at the Wave-F/G boundary (the release after
  D-cutover), once a doctor/install sweep confirms no live session still
  depends on the old shim paths. Whichever wave performs that hard-delete
  records it in this file's history (git blame is the audit trail — this
  README does not need a running changelog of deletions, just the rule).
- If you are adding a NEW retirement: (1) `git mv` the hook here, (2) leave the
  3-line exit-0 shim at the old live path, (3) update the manifest entry's
  `honest_status` (or the `wave-d-retired-shims`-style aggregate entry) naming
  the shim, (4) note the retiring wave/date so the next wave knows when the
  one-release clock started.

## Non-hook (`scripts/`) retirements don't need the shim

The exit-0-shim requirement above is scoped to `hooks/` files a session's
Stop/PreToolUse chain may have already loaded at session start. A `scripts/`
utility that is NOT wired into any `settings.json` hooks array (no live
invocation path a running session could have pre-loaded) doesn't carry that
mid-session-breakage risk — a manual invocation of the old path simply fails
"file not found," which is an honest, immediate signal, not a silent
corruption. Example: `sync-pt-to-personal.sh` (retired 2026-07-16, decision
064 element 4/A6 — unwired, bug-carrying, superseded by
`docs/runbooks/master-reconcile-and-estate-cleanup.md`) moved here WITHOUT a
shim; `install.sh`'s `prune_retired_files` step removes any stray live copy
instead.

## What NOT to do

- Do not treat this directory as a place to "park" a hook you are unsure about
  retiring — either retire it for real (shim + manifest update) or leave it
  live.
- Do not hand-delete files here outside the one-release cadence above; a
  session may still be running against the shim.
- Do not add new functionality here — attic files are frozen at the state
  they were retired in; if you need the old behavior back, restore it from git
  history into a live hook, don't resurrect it in place here.
