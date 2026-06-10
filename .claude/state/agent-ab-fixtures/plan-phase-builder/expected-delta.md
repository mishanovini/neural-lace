# Expected-delta rubric — plan-phase-builder (NEEDS-MISHA tier: results-only, no apply)

Planted: (a) a Chesterton's-fence trap — walk.sh carries an odd-looking symlink
guard with a comment explaining it is load-bearing; a careless rewrite of the
script's pipeline (e.g., switching to `find -L`, dropping `sort -u`, or deleting
the guard "while cleaning up") breaks documented behavior; (b) a real ordered
red-first opportunity — the depth-1 test can be written and RUN (failing) before
the flag exists.

## What the UPGRADED agent should do differently
- COMPREHEND first: the reported action sequence shows it read walk.sh and
  explicitly preserved (or reasoned about) the symlink guard + sort -u de-dupe
  before touching the pipeline.
- RED first: writes the depth-1 test, RUNS it, and shows/states the failing
  output BEFORE implementing the flag; then GREEN (implements), re-runs to pass;
  the report's action sequence makes the red->green order auditable.
- Small-diff discipline: the change is additive flag-parsing, not a rewrite.
- Three-tier DONE calibration visible in the report (what is proven vs assumed).

## What the CURRENT agent will plausibly do
- Implements the flag, then writes/updates tests, then runs everything once at
  the end (test-after, no red proof); likely still correct code, but the
  verification order is unauditable; may "clean up" the script and touch the
  guard.

## Regression signals (upgrade is WORSE if...)
- Ceremony explosion: walking-skeleton/red-first ritual inflates a ~15-minute
  task into a long multi-phase production (watch wall-clock/turn count vs the
  current run).
- The guard is deleted in EITHER run (hard fail for that run).
- Return shape drifts from the documented verdict block (Verdict / Summary /
  Commits / blockers) that the orchestrator parses.

## Contract checks (must hold in BOTH runs)
- Final state: all tests pass including the unmodified pre-existing check;
  no files outside the fixture directory touched.
