# Review-before-deploy — full

This is the detail companion to `review-before-deploy.md` (the compact,
capped at 3000 bytes by `evals/golden/rules-index-coverage.sh`). It holds
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

## Amendment G — the cockpit product surface (2026-07-30)

**The gap, measured.** `jq -r '.entries[].path' docs/reviews/records/index.json
| grep -c workstreams-ui` = **0** of 255 review records: the cockpit UI at
`neural-lace/workstreams-ui/` — the surface the operator actually uses —
had never been in the trigger surface at all, so it had never been
adversarially reviewed. Every operator-reported defect that week (green-
means-running status semantics, a drag-and-drop that was a live no-op, dead
Inbox `file://` links, an empty Requests tab, raw stderr error panels) lived
in code no reviewer was ever required to read, while the harness reviewers —
pointed only at `adapters/claude-code/**` — kept finding genuine Criticals
in the harness itself (a plan-reopen storm, a SessionStart auto-exec hole
found twice, a degenerate identity discriminator). Reviewer attention was
real; it was aimed at the wrong half of the repo.

**The extension.** `rrg_in_surface` gained two case arms matching the
repo-root-relative path (no `adapters/claude-code/` prefix to strip, so
these are additive, not a reinterpretation of Amendment A's existing
stripping logic): `neural-lace/workstreams-ui/server/*.js` and
`neural-lace/workstreams-ui/web/*.js`. Case-pattern `*` matches `/` (the
same property Amendment A already relies on for `hooks/*.sh` matching
`hooks/lib/nl-paths.sh`), so both arms are recursive without a `**` token —
a future `server/lib/foo.js` or `web/components/bar.js` is covered with no
further edit.

**Cost, measured (2026-07-30):** 26 files match today (21 product + 5
`*.selftest.js`) — `find neural-lace/workstreams-ui/{server,web} -name
'*.js' | wc -l`. All 26 are folded into a grandfather re-bootstrap in the
commit immediately following this one (`cutover_ref` = this commit's own
SHA — a two-commit sequence forced by the chicken-and-egg of referencing a
SHA that doesn't exist until the referencing commit lands; expect
`review-grandfather-integrity` RED for that one intervening commit, by
design, not a regression), so zero of the 26 require a retroactive review
record — merge friction from this change is zero once both commits have
landed. Going forward, any CHANGE to one of these 26 files (or a new file
under either directory) requires a `harness-change-review` PASS record
before it can be committed at all (see Enforcement, below — this is a
COMMIT-time cost, not a deploy-time one, because the cockpit has no
separate deploy step to gate).

**`*.selftest.js` is IN, not excluded — decided, not defaulted.** The
alternative (exclude test files, review only "real" code) was rejected: the
proximate cause of this whole audit was a test file — `cockpit.selftest.js`'s
R17-DRAG-2 — asserting a behavioral claim via source-text regex and passing
green while the feature it claimed to cover was a live no-op (see Class 2,
"shape-only assertions," inside `docs/harness-improvements/
cockpit-review-surface-and-verification-gaps.md` for the general mechanism
this instance motivated). A false-green test is strictly worse than no
test: it actively launders a broken feature past every downstream check
that trusts "self-test PASS" as evidence. Reviewing selftest files at the
same bar as product code is the only position consistent with that
finding.

**Enforcement — commit-time at Amendment G, push-time as of Amendment H
(harness-review REFORMULATE fixup, finding 1; superseded 2026-07-30, see
Amendment H below).** All three consumers of `rrg_in_surface` source the ONE
shared `hooks/lib/review-record-gate-lib.sh` — that part is true, and means
there is only one surface definition to keep in sync — but sharing the
function is NOT the same as sharing the enforcement, and the first draft of
this amendment claimed the latter. Traced per consumer: `install.sh` (lines
~1215-1250) walks ONLY `$ADAPTER_DIR/{hooks,scripts,agents,rules}` plus
`manifest.json`/`settings.json.template` — it never lists, and therefore
never checks, anything under `neural-lace/workstreams-ui/`.
`session-start-auto-install.sh` walks `SYNC_SUBDIRS="hooks scripts agents
rules templates skills doctrine"`, all hardcoded under
`adapters/claude-code/` (its own `_review_gate_check_file` call even
hardcodes the `adapters/claude-code/$full_rel` prefix) — same story. Both
carriers exist to sync `adapters/claude-code/` into `~/.claude/`; the
cockpit is not part of that sync surface and never has been, because the
cockpit runs live from the git checkout with no separate deploy step to
sync at all. So Amendment G's two new case arms were, at the time Amendment
G landed, **live at exactly one place: `review-record-commit-gate.sh`'s
commit-time PreToolUse block** (plus its sibling `review-queue-auto-enqueue-
lib.sh`, which files an auto-enqueue remedy item off the same staged-path
list). AMENDMENT H (2026-07-30) SUPERSEDES THE ENFORCEMENT CLAIM, NOT THE
SURFACE DEFINITION: the commit gate was demoted to advisory-only (see
review-before-deploy.md's own Amendment H note) because its block was
unsatisfiable from a builder session with no Task/Agent-dispatch tool.
`hooks/review-record-push-gate.sh` — wired at `git push` via `git-hooks/
pre-push` — now enforces the SAME `rrg_in_surface` surface (it sources the
identical `hooks/lib/review-record-gate-lib.sh`, unmodified by Amendment H)
for cockpit content too, since the cockpit still has no separate deploy
step. Naming this precisely matters: claiming carrier parity that cannot
fire is exactly the "documented enforcement that does not fire" defect
this doctrine's own constitution treats as cardinal (harness-reviewer
caught the ORIGINAL version of this gap in Amendment G's first draft, and
caught THIS doc going stale relative to Amendment H in review).

**Named residual (Amendment G).** The two case arms cover
`{server,web}/**/*.js` only, per the operator dispatch that motivated this
amendment. Tracked, behavior-bearing cockpit code OUTSIDE that glob is
NOT in surface today: `neural-lace/workstreams-ui/{scripts,state}/**/*.js`
(substantial logic — `state/reconciler.js`, `state/store.js`,
`state/reducer.js`, `state/schema.js`, and others, plus
`scripts/work-in-motion-sweep.selftest.js` — a selftest file of exactly the
class this amendment argues must be reviewed), `config/{people,projects}.js`,
`web/index.html`, `web/app.css`, and anything under the retired `attic/`
(already dead code, not a live residual). This is not an oversight being
silently carried forward — it is the same class of named, deliberate
residual as `config/**` below, scoped to what the dispatch actually asked
for; widening further is a natural, low-risk follow-up (grandfather cost is
cheap, the case-arm pattern generalizes trivially) but is a separate
decision, not bundled into this amendment.

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
