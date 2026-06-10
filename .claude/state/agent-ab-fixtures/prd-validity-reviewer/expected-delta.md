# Expected-delta rubric — prd-validity-reviewer

Planted: (a) solution-disguised-as-problem ("The problem is that we lack an
AI-powered scheduling dashboard"); (b) two could-be-any-product scenarios ("manage
my data to be more productive", "configure settings") next to one weak-but-real
dispatcher scenario; (c) adjectival metrics ("Users love it", "Engagement
increases significantly") next to ONE fully-parseable metric (double-booking
6/month -> 1/month within 90 days); (d) NFR1 adjectival ("fast and responsive")
next to a parseable NFR2 (p95 < 2s @ 50 techs); (e) a legitimately small but
substantive Out-of-scope + Open-questions pair (minimum-viable-floor probe).

## What the UPGRADED agent should do differently
- Run the JTBD rewrite detector on the Problem section: name it
  solution-disguised-as-problem and demand a When-I/But/Help-me/So-I restatement
  (dependency-ordered: graded FIRST, with downstream sections inheriting the
  weakness).
- Parse EVERY metric as quantity + baseline + target + time-window; pass the
  double-booking metric, fail the two adjectival ones with the named parse
  failure; same treatment for NFR1 vs NFR2.
- Fast-fail the two generic scenarios as could-be-any-product while crediting the
  dispatcher scenario as salvageable.
- Tag per-section confidence; any LOW-confidence FAIL marked advisory
  (non-blocking) rather than blocking.
- NOT fail the PRD for brevity alone (minimum-viable-PRD floor — substance
  density, not length).

## What the CURRENT agent will plausibly do
- Flags vague metrics and generic scenarios in prose, but without the
  metric-parse discipline (may let "fast and responsive" slide), without
  dependency ordering, without blocking-vs-advisory separation; may or may not
  catch the solution-as-problem framing.

## Regression signals (upgrade is WORSE if...)
- Verdict vocabulary outside PASS / FAIL / REFORMULATE / INCOMPLETE.
- The genuinely-good metric (double-booking) or NFR2 flagged as failures.
- Over-failing on length (the floor exists to prevent exactly this).

## Contract checks (must hold in BOTH runs)
- Verdict present; the two adjectival success metrics are flagged in some form;
  class-aware findings shape preserved.
