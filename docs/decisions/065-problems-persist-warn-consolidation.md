# 065 — Problems-persist mechanism: WARN-only, consolidated into the existing Stop dispatcher (no new hook, no new blocking unit)

**Date:** 2026-07-29
**Status:** DECIDED
**Tier:** 2 (reversible — a function can be removed from an existing file in one commit; no history rewrite, no data surgery)
**Backlog anchor:** `SURFACED-PROBLEMS-CAN-BE-DROPPED-01` (`~/.claude/state/nl-issues.jsonl`); design doc `docs/reviews/2026-07-29-operator-five-questions.md` Q2 (as of this build, only reachable via `git show 1a2ba8a:docs/reviews/2026-07-29-operator-five-questions.md` — see Measurement note below)

## Problem (cold-read context)

The operator (2026-07-29, verbatim): *"Can we enforce a system where anytime you tell me
about a problem that should probably be fixed, you never just allow it to not be addressed?
... I need these concerns to persist until we actually address them."* Constitution §5
already says bugs/gaps/findings get written to their durable home in the same response that
surfaced them — but filing is entirely discretionary; nothing mechanically checks it. The
build task specified three parts: (1) a doctrine amendment establishing inline ledger IDs in
chat, (2) a Stop-time gate that catches problem-shaped prose with no inline ID, (3) a
UserPromptSubmit splice that auto-files when the OPERATOR names a problem. This decision
covers part (2)'s WARN-vs-block and new-file-vs-consolidate choice, which the dispatch
explicitly left to the builder with an instruction to write the reasoning here.

**Measurement note (honest, per constitution §1):** the dispatch prompt cited "doctor says
blocking session-event units are 16/14 OVER budget." Measured live in this worktree
(`node adapters/claude-code/scripts/blocking-budget-check.js`): **14/14, GREEN** — exactly at
cap, zero headroom. This worktree's branch is not a descendant of `wip/harness-hardening-
2026-07-29` (`git merge-base --is-ancestor 1a2ba8a HEAD` fails), so the 16/14 reading was
likely taken on a lineage with additional in-flight blocking gates not present here, or
before an intervening consolidation landed. Either number leads to the same operative fact:
**there is no room for a new blocking unit**, so this decision does not turn on which figure
is current.

## Options considered

| Option | What happens | Cost / risk |
|---|---|---|
| A. New file `hooks/problems-persist-gate.sh`, wired as its own Stop entry, `blocking:false` | A new settings.json.template Stop entry (5→6, exactly at the `budget-chains` cap of 6) plus a new manifest entry | Zero blocking-budget impact (the counting rule in `blocking-budget-check.js` filters `blocking:true` only) BUT consumes the LAST remaining Stop chain-length slot for a WARN-only check, leaving zero room for any future Stop-time need (blocking or not); duplicates machinery (transcript extraction, ledger emission) that already exists in the dispatcher |
| B. New file, but NOT wired into settings.json (called only from a test harness) | Passes review as "a file exists" | This is exactly the vaporware pattern the harness's own doctrine forbids — a mechanism with no live trigger is worse than no mechanism, because it looks done |
| C. Splice into `session-honesty-gate.sh` as a new demoted-warn (its own established pattern: `warn_deferral_phrases`, `warn_narrate_and_wait`, etc.) | Zero new settings.json entries, zero new manifest entries, reuses the existing `ledger_emit` plumbing | `session-honesty-gate.sh`'s own manifest entry states it plainly: **"no longer a direct Stop-chain entry"** — it is invoked BY `stop-verdict-dispatcher.sh` in `--report` mode. Splicing here would still work (the dispatcher calls it), but the check would live one indirection layer away from where its two closest siblings (functional-link, cold-reader-lint) already sit |
| D. **Splice into `stop-verdict-dispatcher.sh` as a third WARN-only side-channel check, following the FUNCTIONAL-LINK / COLD-READER-LINT precedent already in that exact file** | Zero new settings.json entries, zero new manifest entries, zero Stop chain-length impact, matches the file's own documented pattern verbatim ("WARN-ONLY, never contributes to the block/gap verdict... never participates in cycle-counting/DONE-refusal... pure signal-ledger + stderr side-channel") | The file is 2465 lines and already dense; one more ~80-line function follows its existing shape closely enough that this is additive, not structurally risky |

## Decision

**Option D.** `stop-verdict-dispatcher.sh` is the file that is *actually* the live Stop-chain
entry point (confirmed: `settings.json.template`'s `Stop` array wires it directly; the three
"member gates" — work-integrity, session-honesty, bug-persistence — are invoked internally
via `--report` mode, not as separate settings.json entries). It already carries the exact
established idiom for "add a teaching-only check without spending any budget": two prior
WARN-only side-channel checks (FUNCTIONAL-LINK, COLD-READER-LINT) live in this same file,
called from `_svd_main` alongside the member-gate aggregation, each emitting a
`ledger_emit "warn"` event plus a stderr notice, NEVER touching the block/gap verdict, the
cycle count, or the DONE-refusal path. The new "problems-persist" check is implemented as a
third function of the identical shape (`_svd_problems_persist_check`), called at the same
call site, manifest entry `stop-verdict-dispatcher` (already `blocking:true`/`budget_class:
stop` for its OWN aggregated verdict — this WARN addition changes nothing about that
classification, since it never contributes to the verdict).

This deviates from the dispatch prompt's literal file name (`hooks/problems-persist-gate.sh`)
by design: Chesterton's Fence pointed at the ALREADY-EXISTING mechanism for exactly this
class of addition, and using it is lower-risk (no new wiring surface to get wrong, no new
budget-check edge case) than inventing a second one. The `problems-persist` name survives as
the ledger `check` identifier (`gate: stop-verdict-dispatcher, check: problems-persist`) so it
is greppable under its own name in the signal ledger.

**WARN, never BLOCK,** because the vocabulary match (defect/bug/broken/silently/data loss/root
cause) cannot distinguish "a concern raised and left hanging" from "a bug already fixed in
this same commit, described in the past tense" — that distinction is exactly the kind of
discretion this mechanism exists to remove, so building a clever carve-out here would
reproduce the same failure shape as Q1/Q5 in the operator's five-questions review (a
documented practice quietly relying on judgment). A WARN that fires on ordinary engineering
prose is an acceptable, honestly-disclosed cost; a BLOCK that does the same is a gate the
operator has to fight on every completion message — the harness's own §10 rule ("no evidence,
no gate") requires a golden scenario, an FP estimate, and a retirement condition before ANY
blocking gate lands, and the FP estimate here (ordinary "fixed a bug in X" commit-message-
shaped prose WILL fire) does not clear that bar for BLOCK. See the check's own header comment
in `stop-verdict-dispatcher.sh` for the full golden-scenario / FP-estimate / retirement text
required by §10.

## Why this is mine to decide (and what would reverse it)

Reversible: the entire addition is ~80 lines inside one already-existing, already-self-tested
file, removable in one commit with no schema migration, no waiver files, no history rewrite.
Reversal trigger: if weekly signal-ledger triage shows the warn/session ratio for `gate:
stop-verdict-dispatcher, check: problems-persist` is high with a low true-catch rate (per the
retirement condition written into the check's own header), narrow the vocabulary or demote
further rather than silently deleting it — per constitution §10, removal requires the same
named justification creation did.

## Consequences

- No change to `settings.json.template`, no new manifest entry (only `honest_status` text
  updated on the existing `stop-verdict-dispatcher` entry), no change to the `budget-chains` or
  `budget-blocking-gates` doctor numbers.
- The check inherits every sandboxing/fail-open guarantee `stop-verdict-dispatcher.sh` already
  has (HARNESS_SELFTEST routing, subshell isolation not needed since it never blocks, never
  writes stdout).
- Part 3 (auto-file on operator naming) is a SEPARATE UserPromptSubmit-time mechanism (in
  `workstreams-read.sh`, following that file's own existing ASK-CAPTURE splice precedent) —
  not covered by this decision, which is scoped to part 2's WARN-vs-block/file-placement
  choice only.
