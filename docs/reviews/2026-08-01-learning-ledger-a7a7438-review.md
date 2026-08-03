# Harness review: a7a7438 (learning-ledger machine-noise discriminator) — REFORMULATE

Reviewer: harness-reviewer (opus), dispatched 2026-08-01 by the takeover session per the
brief's "UNREVIEWED" flag. Commit `a7a7438` (parent `17c0d4ca`) touches
adapters/claude-code/hooks/workstreams-read.sh (+206) and
adapters/claude-code/scripts/nl-issue.sh (+199/−4). NOT on master. Transport itself is
mechanically clean (dry-run cherry-pick onto master dc05aa2: zero conflicts; master has
not touched either file since the parent) — but REFORMULATE before landing.

## Verdict: REFORMULATE — 2 Critical, 5 Major, 3 Minor

Suite tallies REPLICATED on this machine from the commit's own blobs:
workstreams-read.sh 71/0 (their 70/1's failure R20 passes here — environment-specific);
nl-issue.sh 41/0. The origin.kind marker independently replicated (this machine, 1470
transcripts: task-notification=556, human=329, coordinator=105, peer=7 — same four kinds,
same rank order). The mechanism's layering order, allowlist-over-content-shape decision,
and negative controls (PC10/S17/PC2/PC7) are genuinely good. The wrapper predicate's
false-positive rate measured 0 against 341 real wrapper-opened turns.

### Critical 1 — absolute claim exceeds mechanism coverage (PROVEN)
The store-guard comment (nl-issue.sh:348-357) and commit body claim machine text "can no
longer land as operator-verbatim from ANY caller" / "may never enter the ledger". The
guard's only test is the 13-element wrapper allowlist. The reviewer drove the commit's own
nl-issue.sh 3x with NLI_SOURCE=operator-verbatim and real machine PROSE (a review-brief
sentence): 3 permanent dedup-exempt rows landed — the exact one-row-per-echo amplification
the commit claims eliminated. Fix: rewrite both claims to the true scope (wrapper-OPENING
text only; plain machine prose is not detectable at the store boundary).

### Critical 2 — unnamed residual on the DOMINANT unmarked stratum (PROVEN)
Driving the commit's hook end-to-end: a real "Stop hook feedback:" turn and a real
subagent dispatch-brief both FILED as operator-verbatim. Census on this machine: 103/360
(29%) of recent string-content user turns carry NO origin.kind, and that population is
machine-dominated (Stop-hook feedback x33, session-wrap stdout x18, dispatcher verdicts
x12, dispatch briefs x9, compaction continuations x6) — none open with a wrapper element,
so all three layers miss and the original defect reproduces unchanged. Never named as a
residual. Fix: RESIDUAL paragraph in the block comment + nl-issue row.

### Majors (all PROVEN, all local edits)
- M1 backup-failure swallowed: retag verb's `cp ... || true` then `mv` — a failed backup
  still rewrites the machine-wide ledger and the success message names a backup that may
  not exist. Fix: backup is a hard precondition (abort on failure, verify -s).
- M2 unknown-arg-defaults-to-destructive: `--dryrun` (typo) silently IGNORED and the
  destructive path ran (proven live). Fix: reject unrecognized args (return 2).
- M3 hot-path ordering regression: the discriminator (tail|jq transcript scan, measured
  ~4.5x cost, ~7 extra spawns/prompt) sits ABOVE the cheap vocabulary grep on the
  synchronous UserPromptSubmit path. Fix: cheap predicate first (behavior identical).
- M4 layer-2 prefix collision: content-prefix + `tail -n 1` join can return a PRIOR
  machine entry's origin.kind for an operator's un-flushed paste (fixture-proven) —
  dropping a genuine operator correction, the direction the commit itself calls "the
  worse error". Fix: require full-prompt match or treat multiplicity as UNRESOLVED;
  add PC13 (must go red against current code).
- M5 zero manifest/doctrine coupling: manifest.json:1524, harness-architecture.md:321/385,
  doctrine/INDEX.md:88, findings-ledger.md:39, skills/nl-issue/SKILL.md all still assert
  pre-fix behavior; the new `system-injected` enum value and the destructive verb appear
  nowhere. Fix: same-commit doc delta.
- (M-adjacent) coverage figure omitted: origin.kind presence rate (~34% of prompt-shaped
  entries overall, ~71% last-2-days here) never stated — layer 3 decides roughly a
  quarter to a third of live turns. State it beside the distribution.

### Minors
- `local-command-caveat` missing from both allowlists (observed turn-opening element;
  no live FN today) + no drift query committed.
- Retagged `system-injected` rows invisible in --list and still counted by the digest's
  untriaged escalation (relabel-without-consumer-update).
- Retag whole-file rewrite has no lock vs concurrent hook appends (pre-existing class,
  widened window).

### Dropped as false positives (triage was real)
Leading-newline asymmetry (test artifact); sed corrupting text fields (json-escape
prevents); set -e abort (not set); array-content defeat of layer 2 (fails toward
capturing = stated safe direction; noted as context).

## Disposition
Lane author (Mac mini) is out of quota; the takeover session owns the reformulation.
Plan: worktree builder applies the two claim rewrites + five Major fixes + doc coupling
per this review, re-runs both suites, then transport (clean pick expected — master not
moving on these files). Full reviewer transcript: session d3059d78, agent task
a6e064b18ec4f5ca1.
