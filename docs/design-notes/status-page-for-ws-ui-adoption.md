# Reference: "Overnight Run Status" page → candidate patterns for the Workstreams UI

**Purpose:** a durable, one-click reference the operator can paste into a Workstreams-UI
session to discuss adopting aspects of a status-page design that worked well.
**Filed:** 2026-07-15. **Backlog row:** `WS-UI-STATUS-PAGE-ADOPTION-01`.

## The artifact

- **Live URL:** https://claude.ai/code/artifact/47636abb-dd82-4d2c-b294-326908ed3d77
- **What it is:** a static claude.ai Artifact (hand-authored HTML, published to a URL) that a
  prior overnight run (2026-07-12→13) produced as a point-in-time status report. It is NOT a
  view of the Workstreams UI and NOT tracked in the repo — it is a one-off communication
  artifact. (The Workstreams UI, by contrast, is the live `workstreams-ui-server` that renders
  live workstream *state* dynamically.)
- **Why it's here:** the operator likes the design and wants to consider folding aspects of it
  into the live Workstreams UI. This doc is the bridge between the two.

## What's good about it (candidate patterns to adopt)

1. **A single, unmissable "status verdict" banner up top** — a full-width green
   "● NOTHING AWAITING YOU" block that answers the only question the operator opens the page
   for ("do I need to do anything?") before any detail. The ws-UI equivalent: a top-of-page
   Blocking/When-you-can verdict (ties directly to the constitution §2 two-bucket sign-off and
   `NEEDS-YOU.md`), green only when both buckets are empty.
2. **Scannable stat tiles** — a grid of big-number + one-line-label cards (2 lessons, 118
   branches reclaimed, 8 plans closed, 12 skills, ~10 bugs). High information scent, zero
   reading. ws-UI could surface live counts (active plans, open NEEDS-YOU items, stale
   worktrees, untriaged nl-issues) the same way.
3. **`LIVE` badges on mechanisms** — each shipped capability card carries a state chip
   (LIVE / self-test N/N / harness-reviewed / plan-closed). This is exactly the
   claimed-vs-actual honesty the harness-doctor computes; ws-UI could render doctor state as
   per-mechanism chips.
4. **Terminal/monospace header treatment + calm dark palette** — reads as "systems status,"
   not "marketing." Matches the operator's stated communication-hygiene preference (signal
   over decoration).
5. **Clear three-tier hierarchy** — verdict banner → metrics → detail cards. The reader
   descends only as far as they need. Maps onto ws-UI's plan/session drill-down.

## The ask for the ws-UI session

Consider which of the five patterns above belong in the live Workstreams UI, and whether the
"status verdict banner + live stat tiles" pairing should become the ws-UI landing view. The
key difference to respect: the artifact is *frozen and hand-authored*; ws-UI must derive the
same surface from *live state* (plans, NEEDS-YOU, doctor, worktrees) with no hand-authoring.

Related decisions/surfaces: `docs/decisions/055-workstreams-status-surface.md`,
`docs/decisions/056-workstreams-deploy-detection-and-builder-dispatch-bucketing.md`.
