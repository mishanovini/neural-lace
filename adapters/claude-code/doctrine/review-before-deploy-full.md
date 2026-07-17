# Review-before-deploy — full

This is the detail companion to `review-before-deploy.md` (the compact,
capped at 2800 bytes by `evals/golden/rules-index-coverage.sh`). It holds
the elaboration, rationale, and incident narratives trimmed out of the
compact — the compact's imperative rules stand alone; this file is why
they exist and how the edge cases were found.

## The gap this closes — incident narrative

Nothing deterministically required a harness change (hook/gate/agent/rule)
to carry a `harness-reviewer` PASS before it reached a live `~/.claude/`.
This failed twice in the model-enforcement workstream: a buggy gate
live-synced with zero review, and a fix was `install.sh`-deployed before
its re-review returned. Golden scenario for this doctrine: those two
proven misses.

## Trigger surface — recursive-walk rationale (harness-review REFORMULATE fixup, 2026-07-16)

**Enforced set == admitted-and-deployed set.** Both carriers walk
`hooks/**/*.sh` and `scripts/**/*.sh` RECURSIVELY (a `find`, not a flat
top-level glob) — a flat `scripts/*.sh` glob previously missed
`scripts/lib/*.sh` (e.g. `imperative-classifier.sh`) entirely, and would
silently miss any future `scripts/host-setup/*.sh` too, even though
`sync_directory`/`git ls-tree -r` deploy those files just the same as
top-level ones. `rules/**` is walked recursively for the same reason (no
nested `rules/*.md` exists today, but the surface glob is recursive and a
flat glob would silently miss one added later). `settings.json.template`
is gated at BOTH its real call sites — the `--replace-settings` mode
(which always applies it) and the normal flow's missing-`settings.json`
copy — not just the one a narrower fix might touch.

## Named residual — verification detail

**Named, deliberate residual:** `config/**` is part of the trigger surface
(Amendment A) but is **never deployed by either carrier** — neither
`install.sh` nor `session-start-auto-install.sh` syncs
`adapters/claude-code/config/` anywhere (verified: `config/model-policy.json`
reaches no live mirror today). The gate therefore has nothing to check for
it; this is not a hole in the gate, it is a pre-existing gap in deployment
coverage, tracked separately from this batch.

## Posture differs by carrier — rollout-lag consequence (Amendment F)

`install.sh` (operator present) is a loud HARD BLOCK — the whole install
aborts before touching any file, naming every uncovered file + its
blob_sha + the remedy. `session-start-auto-install.sh` (fail-open by
platform contract, always exits 0) SKIPS the uncovered file + warns loudly
(stale-not-blocked, stated explicitly) while every other file still syncs
— this composes with the hook's existing fail-open posture instead of
making it the one hard-blocking exception. Rollout-lag consequence: a
machine relying solely on auto-install can run a stale copy of a covered
file for at least one more session after an unreviewed change lands —
`install.sh` remains the authoritative immediate enforcement point.

## Grandfather manifest + records dir — trust-anchor mechanism detail (harness-review REFORMULATE fixup, finding 3)

`grandfather-manifest.json` records a `cutover_ref` that is a RESOLVED
commit SHA (never the literal string "HEAD"). Two detection mechanisms
guard against a hand-edit or a silent re-bootstrap: (1) doctor check
`review-grandfather-integrity` re-derives the manifest at its own recorded
`cutover_ref` via `write-review-record.sh bootstrap-grandfather --ref
<cutover_ref>` and REDs on divergence from the committed file, and
separately REDs when the records directory is absent while the gate's lib
is present (bootstrapped-then-emptied is a defect, distinct from the
legitimate pre-cutover fail-open case); (2) the file's own git history is
an independent audit trail. Neither prevents a bad edit at write time —
both make it detectable after.

## What this gate does not catch — the 937e8cb class (Amendment B)

The gate is content-presence only — blind to (i) absence of expected
forward content (a silent merge/rebase drop, the `937e8cb` class) and (ii)
reverts to a previously-PASS'd blob (accepted by design, no TTL).
Merge-integrity is a SEPARATE mechanism (the merge-time dropped-side sweep,
`docs/runbooks/master-reconcile-and-estate-cleanup.md` step 6) — this
record does not substitute for it.
