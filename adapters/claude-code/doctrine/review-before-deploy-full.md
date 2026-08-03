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

**Enforced set == admitted-and-deployed set.** Both carriers walk the
carrier-chain trees RECURSIVELY (a `find`, not a flat top-level glob) — a flat
`scripts/*.sh` glob previously missed `scripts/lib/*.sh` (e.g.
`imperative-classifier.sh`) entirely, and would silently miss any future
`scripts/host-setup/*.sh` too, even though `sync_directory`/`git ls-tree -r`
deploy those files just the same as top-level ones. `rules/**` is walked
recursively for the same reason (no nested `rules/*.md` exists today, but the
surface glob is recursive and a flat glob would silently miss one added
later). `settings.json.template` is gated at BOTH its real call sites — the
`--replace-settings` mode (which always applies it) and the normal flow's
missing-`settings.json` copy — not just the one a narrower fix might touch.

> **SUPERSEDED IN PART, 2026-07-30 (Amendment H).** This section used to say
> the carriers walk `hooks/**/*.sh` and `scripts/**/*.sh` — an
> EXTENSION-SCOPED surface that Amendment H retired. The recursion rationale
> above still holds and is why the surface is recursive; the extension
> allowlist does not. The four carrier-chain trees (`hooks/`, `scripts/`,
> `git-hooks/`, `schemas/`) are now matched **WHOLESALE**, with an exact-path
> exemption list, because an extension allowlist is itself a hand-written list
> that drifts silently: `hooks/lib/evil.mjs`, `hooks/evil.rb`,
> `schemas/x.yaml` were each PROBED and confirmed NOT-COVERED under the old
> arms. `git-hooks/` additionally cannot be extension-filtered at all — its
> load-bearing members (`pre-push`, `pre-commit`, `post-commit`,
> `pre-merge-commit`) are extensionless. Canonical statement:
> `doctrine/review-before-deploy.md` "Amendment H surface shape"; implementation:
> `hooks/lib/review-record-gate-lib.sh` `rrg_in_surface`.
>
> **Why this correction is filed here and not silently rewritten:** the
> compact and the full drifted apart in OPPOSITE directions twice in two
> rounds — first a retraction landed in the full and missed the JIT-delivered
> compact, then this fix landed in the compact and missed the full. The pair
> is now swept mechanically; see "Compact/full drift sweep" below.

## Compact/full drift sweep (harness-reviewer MAJOR 3, 2026-07-30)

Every `<name>-full.md` and its `<name>.md` compact must agree on the PATH
GLOBS they quote — that is the specific thing that has now drifted twice.
Run this before landing any doctrine edit that touches a surface definition:

```sh
for f in adapters/claude-code/doctrine/*-full.md; do
  b="${f%-full.md}.md"; [ -f "$b" ] || continue
  d=$(diff <(grep -oE '[a-z-]+/\*\*?/?\*?\.[a-z]+' "$f" | sort -u) \
           <(grep -oE '[a-z-]+/\*\*?/?\*?\.[a-z]+' "$b" | sort -u))
  [ -n "$d" ] && { echo "=== $f vs $b ==="; echo "$d"; }
done
```

`grep -oE`, not `rg`: on this machine `rg` is a SHELL FUNCTION supplied by the
Claude Code shell snapshot, so it resolves inside an agent's tool shell and
vanishes in a plain `bash script.sh` subprocess — a documented command that
silently does not run is the same theatre class this doctrine exists to
prevent. Verified: `command -v rg` reports a function, and the loop above
using `rg` failed with `rg: command not found` on every file.

A non-empty diff is not automatically a defect (a full may legitimately
discuss a glob the compact omits), but it IS the list a doctrine edit must
walk before claiming the pair is consistent. Current state of that walk
(2026-07-30, re-executed at this commit): see the sweep result recorded in
`docs/plans/review-gate-identity-anchor-2026-07-30.md`.

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

## Amendment H (2026-07-30, deterministic-process.md) — full detail

The commit-time carrier's block was UNSATISFIABLE from the layer it fired at — 78 override
events (docs/backlog.md REVIEW-GATE-UNSATISFIABLE-FROM-BUILDER-01), every 2026-07-30 one
citing the same builder-has-no-dispatch-tool deadlock: a builder subagent typically has no
Task/Agent-dispatch tool and cannot itself satisfy the remedy. `review-record-push-gate.sh`
moves the authoritative check to `git push` (the funnel every commit reaches the remote
through, AND the layer where the actor — the orchestrator — can actually satisfy the remedy).
`review-record-commit-gate.sh` (PreToolUse, commit time) becomes ADVISORY ONLY as of this
amendment — it warns but never blocks. Its own override is NOT `REVIEW_RECORD_GATE_OVERRIDE`
(removed from the commit gate entirely) but an operator-authorized, sha-scoped, 900s-TTL marker
written by `scripts/authorize-review-record-push-override.sh` (Rule 2: an override the acting
agent authors unilaterally is not an override). Manifest proof obligation (Rule to self): every
`blocking:true` entry declares `chokepoint` + `bypass_paths`, mechanized by doctor
`check_deterministic_process_proof`.

**Amendment H surface shape.** The four CARRIER-CHAIN trees (`hooks/`, `scripts/`,
`git-hooks/`, `schemas/`) are matched WHOLESALE — not by extension — minus an exact-path
exemption list of three non-code members. Extension allowlists were retired because they are
hand-written lists that drift silently: a new `.mjs`/`.rb`/`.yaml` fell OUT of surface with no
edit and no reviewer. Exemptions are exact paths, never patterns, so a new sibling defaults IN.
Re-derive the exemption list with `git ls-files 'adapters/claude-code/hooks/*'
'adapters/claude-code/scripts/*' | grep -vE '\.(sh|js|ts|py|ps1)$'`.

**Subject-set enumeration (Amendment H, extended round 4).** `review-record-push-gate.sh`
enumerates the pushed range on THREE arms — `--diff-filter=ACMRT`, a separate
`--diff-filter=D --no-renames` pass, and a `--raw` pass for FILE MODE. "The enforcing file no
longer enforces at its path" is ONE outcome with FIVE verbs: edit `M`, `git rm` `D`, `git mv`
`R100 <old> <new>` (ACMR emits only the DESTINATION, D emits nothing), typechange `T` (excluded
by BOTH), and **mode-only `chmod` `M` with an unchanged blob — enumerated, but it PASSED
coverage, because the authorized key is `{path, blob_sha}` and the blob never moved.**
`review-record-commit-gate.sh` and `lib/review-queue-auto-enqueue-lib.sh` carry ACMRT + the `D`
pass too (round 4): advisory-only is a reason for a softer CONSEQUENCE, never for a smaller
SUBJECT SET.

Three rules, each earned by a proven bypass:

1. **Enumerate by the codes through which the subject can change *or leave* the surface.**
   Every self-test carries a `git mv`, a typechange, and a mode-only case beside its `git rm`
   case.
2. **A control that authorizes content BY HASH must state what metadata the hash does NOT
   cover** — mode, symlink-ness, path encoding, filename case — and either cover it or
   enumerate it as a named bypass. See `manifest.json`
   `review-record-push-gate.bypass_paths[16]` for this control's exhaustive statement.
3. **Git path OUTPUT is a rendering, not the path.** Every harness consumer of `git diff
   --name-only` / `ls-files` that feeds a path PREDICATE must use `-c core.quotePath=false`
   **and** `-z`, consumed with `while IFS= read -r -d ''`. Measured: `core.quotePath=false`
   alone still quotes a backslash; a space is never quoted, which is why the obvious probe
   misses this. A C-quoted `hooks/pré-push-gate.sh` was classified out-of-surface and landed
   on a real remote at rc=0.

**Degraded scans re-derive EVERY arm or fail closed (round 4).** When the pushed range cannot
be diffed (an unfetched remote tip — reachable on a plain push and on `--force`), the change
arm degrades UPWARD to `EMPTY_TREE..local_sha`, a strict superset. The removal and mode arms
cannot: both are differential and re-derive from the remote-tracking refs (an anchor the push
does not write), unioned across every ref that resolves. If none resolves, the push is
REFUSED. A fallback that recomputes a SUBSET of the subject set is a bypass that fires exactly
when the gate is least sure of itself — the previous revision recomputed only the change arm
and silently dropped the whole deletion arm, and `EMPTY_TREE..local` structurally cannot emit
a `D`.

**A remedy must be SATISFIABLE, not merely runnable.** For a mode-only change the review
pathway can never clear the block (the record would attest to the blob it already attests to),
so that block routes to the operator override and says why. Scenario 22 pins that the emitted
remedy PARSES; Scenario 17g pins that it can actually be FOLLOWED.

**Coverage (Amendments D+E).** Covered iff `{path, blob_sha}` is in `grandfather-
manifest.json` (pre-cutover, exempt) OR in `index.json` with `kind: harness-change-review`,
`verdict: PASS`. Records dir is audit-only, never scanned on the hot path (doctor
`review-index-consistency`). Amendment G re-bootstraps at a new cutover in the commit right
after it lands (cutover_ref = the Amendment-G commit's SHA); `review-grandfather-integrity`
REDs for that one commit BY DESIGN, not a regression.

**Retirement.** Hard-block half retires when `install.sh` retires for a reconciling sync path,
or an anti-fabrication anchor + native review-gate make it redundant.

## Doctor checks that back this gate (names restored 2026-08-03)

The 2026-08-03 trim that brought `review-before-deploy.md` under the 3000-byte cap
(`evals/golden/rules-index-coverage.sh` invariant 4) correctly moved detail here, but two
doctor CHECK NAMES fell out of the doctrine corpus entirely: the concepts survived, the
greppable names did not. Restored below, because this doctrine cites doctor checks by name
everywhere else and an un-named check is an unfindable one.

- **`review-surface-cross-check`** (`check_review_surface_cross_check`,
  `hooks/harness-doctor.sh`) — the manifest CROSS-CHECK the compact refers to: every
  `hooks[]` entry in `manifest.json` must resolve in-surface, else RED.
- **`review-reviewer-independence`** (`check_review_reviewer_independence`, same file; spec
  `docs/plans/review-independence.md`) — closes WHO reviews: `scripts/review-queue.sh
  enqueue` is the authoring session's ONLY legal move, and the check REDs on matching
  git-commit authorship between author and reviewer. The rule itself also lives in
  `doctrine/verification-dispatch.md`; only the check name was missing here.

With `review-index-consistency` and `review-grandfather-integrity` (above), these are the
four doctor checks that keep this gate honest.
