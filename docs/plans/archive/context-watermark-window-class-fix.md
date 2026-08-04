# Plan — context-watermark: retire the stale-window-table CLASS

Status: COMPLETED
Mode: code
Owner: builder session (2026-07-29, orchestrator-directed)
Backlog items absorbed: CONTEXT-WATERMARK-WINDOW-TABLE-STALENESS-01
acceptance-exempt: yes (harness-internal; the maintainer is the user, demonstrated by
`context-watermark.sh --self-test` plus a live run against a real transcript, per
constitution §4)

## Why

`docs/plans/context-watermark-opus5-window.md` shipped the INSTANCE fix (adding
`claude-opus-5` to the table) and deliberately deferred the class. This plan is the class.

The defect has now fired twice with identical shape: a model missing from
`_model_window`'s hardcoded allowlist falls through to a hardcoded 200,000 denominator,
and the hook prints a confident percentage against it — "~95% of 200000" on a
`claude-opus-4-8` session (2026-07-20), "~74% of 200000" then "~90% of 200000" on a
`claude-opus-5` session whose client readout said 163.2k / 1.0M = 16% (2026-07-28). The
first fix added an "ASSUMED" label, which made the wrongness honest but not rare: the
table goes stale by construction on every model launch, silently, and the only detector
was "an operator eventually notices the percentage is absurd". A third occurrence was
expected on the next launch.

## Decision — which of the three candidate fixes, and why

The backlog row named three. All three were evaluated against the real runtime before
choosing; the evaluation is recorded in the hook's own header under `THE CLASS FIX` so it
travels with the code.

| Option | Verdict |
| --- | --- |
| (b) read the real window at runtime | RULED OUT — not obtainable by this hook. Proven, not assumed: the client's PostToolUse payload schema carries no model and no window; `message.usage` in the transcript carries a numerator only (0 hits for any window-shaped key across all 67 real transcripts on this machine); no env var exposes it (`CLAUDE_CODE_MAX_CONTEXT_TOKENS` is an operator-set INPUT the client honors only under `DISABLE_COMPACT` or for non-`claude-` ids); `~/.claude.json`'s `autoCompactWindowsCache` is a `claude-sonnet-4-6`-only experiment knob and is null here. The one channel that does expose `context_window.context_window_size` is the StatusLine command input — an operator-owned UI surface this harness does not configure, so wiring it would be claiming a mechanism never observed to fire (constitution §10). |
| (c) doctor check that REDs on a missing model | Viable but strictly weaker — the wrong percentage is still emitted, and it is only caught whenever someone next runs the doctor. Shortens detection latency; does not remove the harm. |
| **(a) invert the default** | **CHOSEN.** No denominator for an unknown model means no percentage can be printed at all, so the harm becomes structurally impossible rather than less likely. |

Suppression alone would have destroyed the only existing detector (the absurd
percentage), so the detector is rebuilt IN BAND rather than deferred to the doctor: on an
unknown model the hook emits one non-numeric maintenance notice per session that names
the model, names the file and function to edit, gives both candidate readings as an
explicit either/or, and names the `CONTEXT_WATERMARK_WINDOW` escape hatch. That reaches
the agent who can fix it, in the session where it matters — louder than option (c), and
without ever asserting a number the hook cannot defend.

## Scope / Tasks

- [ ] C1 — `_resolve_window` returns `0 unknown` for an unrecognized/absent model; the
      hardcoded 200,000 fallback denominator is deleted outright. Verification: full.
- [ ] C2 — `_compute_watermark` grows an UNKNOWN branch that emits the maintenance notice
      and returns: no percentage, no 70/85 markers, no proactive snapshot. One-shot per
      session via a `--window-unknown` marker. Verification: full.
- [ ] C3 — Notice floor at 70% of the smallest known window (140,000 tokens); the marker
      is written ONLY when the notice fires, so a session that starts small still gets it
      later. Verification: full.
- [ ] C4 — Scenarios T20/T20b/T21/T22/T23/T23b for the new mechanism; T12 rewritten (it
      previously PINNED the invented denominator); T1/T2/T4/T6/T7 fixtures moved to a
      real table-listed model so they still test the watermark rather than the new path.
      Verification: full.
- [ ] C5 — Fix the suite's own bare-`bash "$0"` re-invocations (T9, T11) to `"$BASH"`, and
      add T24 as a source-level guard. Before this, a suite launched with /bin/bash 3.2.57
      silently ran those two scenarios under /opt/homebrew/bin/bash 5.3.15 and still
      reported a clean count for 3.2. Verification: full.
- [ ] C6 — Update `docs/backlog.md` CONTEXT-WATERMARK-WINDOW-TABLE-STALENESS-01 with the
      chosen option, the (b) evidence, and the residual risk. Verification: mechanical.

## Files to Modify/Create
- `adapters/claude-code/hooks/context-watermark.sh` — C1-C5
- `docs/backlog.md` — C6
- `docs/plans/context-watermark-window-class-fix.md` — this plan

## Assumptions
- The smallest and largest windows in `_model_window` are 200,000 and 1,000,000. These are
  mirrored into `MIN_KNOWN_WINDOW` / `MAX_KNOWN_WINDOW` with a comment requiring they be
  kept in sync if the table ever gains a smaller or larger bucket. If they drift, the only
  consequence is a slightly wrong RANGE in the notice — never a wrong point estimate,
  because the notice never states one.
- Going quiet on an unknown model is an acceptable cost. The PreCompact backstop
  (`pre-compact-continuity.sh`) still fires on compaction, and this hook's own message has
  always said context pressure is never a stop reason. The proven cost of a false alarm
  (an autonomous program paused, 28 of 34 remaining items abandoned, 2026-07-20) is far
  larger than the cost of a missed early nag.

## Edge Cases
- `CONTEXT_WATERMARK_WINDOW` must still outrank BOTH a detected window (T15) and an
  unknown one (T23) — otherwise suppression would be a dead end with no escape hatch.
- The bytes-fallback measurement path never has a model, so it now always routes to the
  UNKNOWN notice. That is correct twice over: its numerator is itself 6x-uncertain, so a
  percentage from it was never defensible either. T8's assertion is unchanged.
- A below-floor call must not write the dedup marker, or the notice would be silently
  suppressed for the rest of the session — the same silent-by-default failure this change
  exists to end. Covered by T22 and mutation-verified (M4).
- An unrecognized `win_source` (a future third source) returns without emitting rather
  than falling through to a percentage.

## Testing Strategy
`context-watermark.sh --self-test` on BOTH `/bin/bash` 3.2.57 and
`/opt/homebrew/bin/bash` 5.3.15: 21/0 before, 28/0 after, on each.

Every claimed control is mutation-verified (delete it, suite goes RED, restore, GREEN):
M1b full revert to pre-change semantics, M2 floor removed, M3 dedup removed, M4 marker
moved above the floor, M5 unknown path claims watermarks, M6 bare-`bash` reintroduced,
M7b override branch disabled, M8 one candidate reading dropped.

The oracle of record is not a hand-written fixture: the live path is exercised against
this machine's real 8 MB session transcript (926,925 tokens, model `claude-opus-5`), and
against that SAME real file with one controlled substitution of the model id to an
unlisted `claude-opus-6` — which is precisely what the next model launch looks like on
disk. Pre-fix code on that artifact emits "~463% of 200000 … AT THE 85% MARK"; post-fix
code emits the UNKNOWN notice.

## Completion Report (drain disposition — gated-pipeline-master-2026-08 Task 21, REQ-C2, 2026-08-03)

Found landed-but-unflipped during the REQ-C2 estate drain: `adapters/claude-code/hooks/context-watermark.sh`
on master carries `MIN_KNOWN_WINDOW`, the "0 unknown" return path, and self-test scenarios T20-T24
matching this plan's C1-C6 controls exactly (independently confirmed by reading the live file at
HEAD this pass). No further build work needed — bookkeeping close only. Status flipped
ACTIVE -> COMPLETED.

## In-flight scope updates
- 2026-07-29: `docs/plans/context-watermark-window-class-fix.md` — this plan
