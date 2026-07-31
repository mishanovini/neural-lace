# Harness improvement: cockpit review-surface extension + two sibling verification gaps

Status: Class 1 SHIPPED (this doc's own commit sequence); Classes 2 and 3
PROPOSED (design only, no code this round). Author: builder session,
2026-07-30. Origin: operator directive, verbatim — "These issues that we
keep finding should be being caught in the reviews. Are the reviews just
not happening or do we just have shitty reviewers?" Trigger: a direct
measurement proving the reviews were happening but aimed at the wrong half
of the repo, plus two sibling gap classes the same measurement session
exposed. Reviewed before landing: `harness-reviewer` (Class 1 is a gate
change to `review-record-gate-lib.sh` — Rule 10 requires a golden scenario
+ expected-FP rate + retirement condition per class, all below). Governing
plan: `docs/plans/cockpit-review-surface-and-verification-gaps.md`.

---

## Class 1 — cockpit-never-reviewed (SHIPPED)

### The measurement (not an assumption)

```
jq -r '.entries[].path' docs/reviews/records/index.json | grep -c workstreams-ui
```
returns **0**, out of **255** total review records
(`jq '.entries | length'`). Every single review record ever written in this
repo's history covers `adapters/claude-code/**`. `neural-lace/workstreams-ui/`
— the cockpit product the operator actually uses daily — has never once
been adversarially reviewed.

### 5-Whys to the latent cause

1. **Why did the operator hit a week of UI defects** (green-means-running
   status semantics, a drag-and-drop that was a live no-op, dead Inbox
   `file://` links, an empty Requests tab, raw stderr error panels)
   **that reviewers never caught?** Because none of that code was ever
   inside a reviewer's remit — there was nothing to catch it with.
2. **Why was cockpit code never inside a reviewer's remit?** Because
   `rrg_in_surface` (`hooks/lib/review-record-gate-lib.sh`), the ONE
   function all review-gate consumers share, only matched paths relative
   to `adapters/claude-code/` (`hooks/**/*.sh`, `scripts/**/*.sh`,
   `agents/*.md`, `config/**`, `manifest.json`, `settings.json.template`,
   `rules/**`).
3. **Why was the surface scoped to `adapters/claude-code/` only?** Because
   the review-before-deploy mechanism (harness-governance-batch-2026-07-15)
   was built to close a specific, narrower incident: a buggy gate
   live-synced to `~/.claude/` with zero review, and a fix deployed before
   its re-review returned. Both incidents were about the HARNESS deploying
   itself; the design never considered the cockpit because the cockpit
   isn't part of that deploy path at all.
4. **Why did nobody notice the surface was this narrow, across 255 review
   records?** Because every review record the surface produced was itself
   evidence the mechanism was "working" — 255 PASS records is a strong
   green signal if you don't ask what fraction of the REPO those 255
   records could ever have covered. The metric that would have caught this
   (coverage as a fraction of reviewable code, not count of records
   written) was never computed until this session.
5. **Why did the harness reviewers, working hard and finding genuine
   Criticals (a plan-reopen storm, a SessionStart auto-exec hole found
   TWICE including an inadequate first fix, a degenerate identity
   discriminator), never redirect any of that attention to the cockpit?**
   Because reviewer dispatch in this harness is driven by the SAME
   trigger surface as the gate (`doctrine-jit.sh`'s `jit_triggers.paths`,
   and the review-before-deploy doctrine itself) — there was no mechanism
   pointing reviewer attention at the cockpit, only convention and the
   builder's own judgment, and judgment without a mechanism is exactly the
   reliance-on-memory failure class this harness exists to eliminate.

**Latent cause:** the review-before-deploy mechanism's trigger surface was
defined by the shape of ONE past incident (harness self-deployment) and
never re-derived against "everything the operator actually uses," so a
structurally significant fraction of the repo — the product itself — sat
permanently outside every review mechanism's reach, invisible precisely
because nothing measured the gap.

### Existing-controls audit (each trigger verified, not assumed)

| Control | Claimed trigger | Verified actual trigger |
|---|---|---|
| `review-before-deploy` gate (`install.sh` hard-block) | "every harness deploy" | Walks ONLY `$ADAPTER_DIR/{hooks,scripts,agents,rules}` + `manifest.json`/`settings.json.template` (`install.sh` ~line 1215-1250). Never lists anything under `neural-lace/workstreams-ui/` — structurally cannot fire on cockpit paths. |
| `review-before-deploy` gate (`session-start-auto-install.sh` skip+warn) | "every auto-install sync" | Walks `SYNC_SUBDIRS="hooks scripts agents rules templates skills doctrine"`, hardcoded under `adapters/claude-code/`; its own `_review_gate_check_file` call site hardcodes the `adapters/claude-code/$full_rel` prefix. Same story — never sees a cockpit path. |
| `review-record-commit-gate.sh` (PreToolUse `git commit` block) | "every staged in-surface file" | `git diff --cached --name-only` → repo-root-relative paths → `rrg_in_surface` per path. THIS is the one control that genuinely receives whatever path is staged, cockpit or not — verified by the fact that this exact gate is what blocked this session's own first commit attempt on `hooks/lib/review-record-gate-lib.sh`. |
| `review-queue-auto-enqueue-lib.sh` (auto-enqueue remedy) | "uncovered staged files" | Same `git diff --cached --name-only` staged-path list as the commit gate — genuinely fires on cockpit paths too, confirmed by code trace. |
| `doctrine-jit.sh` (routes `review-before-deploy.md` into context) | `jit_triggers.paths` in `manifest.json` | Pre-this-change, `jit_triggers.paths` for `review-before-deploy` listed only `adapters/claude-code/{install.sh, hooks/session-start-auto-install.sh, hooks/, scripts/, agents/, rules/, manifest.json}` and `docs/design-notes/review-record-primitive.md` — no cockpit path, so a session editing `workstreams-ui/**` never got this doctrine injected at all. |

**Conclusion:** of five controls in the review-before-deploy family, only
TWO (`review-record-commit-gate.sh` and its auto-enqueue sibling) can ever
receive a cockpit path. The other two carriers are real, working controls
for their actual job (syncing `adapters/claude-code/` into `~/.claude/`) —
they were never broken, they were simply never going to be the answer for
a product that has no separate deploy step at all. This is the honest
correction to this proposal's own FIRST draft, which initially (and
wrongly) claimed the fix "widens all three consumers simultaneously" —
`harness-reviewer`'s round-1 REFORMULATE caught this as a Critical
(constitution §10 theater: documented enforcement that cannot fire).

### The proposed change (SHIPPED)

`rrg_in_surface` gains two additive, repo-root-relative case arms:
```
neural-lace/workstreams-ui/server/*.js
neural-lace/workstreams-ui/web/*.js
```
Case-pattern `*` matches `/` in bash (the same property Amendment A's
pre-existing `hooks/*.sh` arm already relies on to match
`hooks/lib/nl-paths.sh`), so both arms are recursive with no `**` token —
a future `server/lib/foo.js` is covered with no further edit. Because the
only LIVE consumer of this surface for cockpit paths is the commit-time
gate, and that gate has no separate deploy step to lag behind, this single
function change is complete — there is no second carrier to wire up.

**`*.selftest.js` is INCLUDED, deliberately — decided, not defaulted.**
The alternative (exclude test files, review only "real" code) was
considered and rejected. The proximate incident that motivated this whole
proposal was itself a test file: `cockpit.selftest.js`'s R17-DRAG-2 was a
source-text regex matching `insertBefore(...)` that PASSED while the
optimistic drag move it claimed to cover was a live no-op (fixed in
commit `b66f7e1` with R17-DRAG-3, a real-execution, mutation-proven
replacement — see Class 2 below). A false-green test is strictly WORSE
than no test at all: it actively launders a broken feature past every
downstream consumer — including a human reviewer skimming a self-test
summary — that trusts "self-test PASS" as evidence. Reviewing selftest
files at the same bar as product code is the only position consistent
with that finding.

**Named residual (not silently carried forward).** The two case arms
cover `{server,web}/**/*.js` only, matching the operator's own dispatch
text. Tracked, behavior-bearing cockpit code OUTSIDE that glob remains
unreviewed by this mechanism: `neural-lace/workstreams-ui/{scripts,state}/**/*.js`
(substantial logic — `state/reconciler.js`, `state/store.js`,
`state/reducer.js`, `state/schema.js`, and `scripts/work-in-motion-sweep.selftest.js`
— a selftest of exactly the class this proposal argues must be reviewed),
`config/{people,projects}.js`, and `web/{index.html,app.css}`. This is
named exactly like Amendment A's own pre-existing `config/**` residual
(in-surface but never deployed) — not a gap discovered later and
covered up, a gap named the same day it was found. Widening further is a
cheap, low-risk follow-up (the grandfather cost scales linearly, the
case-arm pattern generalizes trivially) but is a separate decision from
this change, deliberately not bundled in to keep this change's blast
radius matched to what was actually asked for.

### Testing strategy

`hooks/lib/review-record-gate-lib.sh --self-test`: 25/25 → 36/36. 11 new
scenarios: 6 positive (both directories, both product-`.js` and
`*.selftest.js`, nested-path recursion via `server/lib/nested/deep.js`),
5 negative (`workstreams-ui/attic/` — retired code, out of scope by
directory; the un-prefixed `workstreams-ui/web/roadmap.js` form — missing
the `neural-lace/` segment a real `git diff` always emits; a sibling
`neural-lace/other-project/`; `server/package.json` — right directory,
wrong extension; `workstreams-ui/README.md` — wrong directory).
Mutation-proven: disabling the two new case arms turns exactly the 6 new
positive assertions red (30 passed, 6 failed); restoring returns 36/0.
`write-review-record.sh --self-test` (22/22) and
`review-record-commit-gate.sh --self-test` (62/62) re-run UNCHANGED,
confirming neither consumer's own logic needed a code change — they
inherit the wider surface purely by sourcing the shared lib.
`manifest-check.sh check` stays GREEN (149 entries, same count, fields
edited in place). `harness-doctor.sh --quick`'s `review-grandfather-integrity`
check is EXPECTED to go RED for exactly one commit between the surface
change landing and the grandfather re-bootstrap landing (a chicken-and-egg
forced by `cutover_ref` needing to be the surface-change commit's own SHA)
— by design, not a regression.

### §10 credentials

**Golden scenario:** any future commit that edits
`neural-lace/workstreams-ui/server/roadmap-routes.js` (or any of the other
25 currently-matching files, or a new file under either directory) without
an accompanying `harness-change-review` PASS record must be BLOCKED by
`review-record-commit-gate.sh` at `git commit` time — the same class of
protection `adapters/claude-code/**` has had since 2026-07-16, extended to
the surface where the operator actually found this week's defects.

**Expected false-positive rate:** near-zero once the grandfather
re-bootstrap lands (all 26 currently-matching files are grandfathered, so
day-one friction is zero); going forward the cost is identical to the
harness side's own — a change to any of the 26 files requires a PASS
record before it can be committed. This is a deliberate, non-zero,
CORRECT cost (not a false positive) — it is exactly the review requirement
this whole proposal argues should have existed from the start. The one
genuine false-negative risk is the NAMED residual above (`scripts/`,
`state/`, `config/`, `web/*.html|*.css`) — real product code that remains
outside this surface; stated plainly rather than implied covered.

**Retirement condition:** retire this specific extension only if
`workstreams-ui/**` is retired or migrated to a repo/deploy path with its
own independent review mechanism; retire the wider review-before-deploy
family under the same conditions already named in that doctrine (a
continuously-reconciling single sync path, or a native platform
review-gate + real anti-fabrication anchor).

---

## Class 2 — shape-only assertions passing while the feature is broken live (PROPOSED)

### The incident, proven the same day

`cockpit.selftest.js`'s **R17-DRAG-2** asserted the optimistic drag-and-drop
move was implemented by matching `insertBefore(...)` as a literal
substring against the SOURCE TEXT of `roadmap.js` — a regex over the file
contents, never an execution of the function it claimed to cover. It
PASSED continuously while the feature was a live no-op: commit `634cd12`'s
`performDrop` called `planRowContainer()` for BOTH the dragged row and the
drop target, which returns the GROUP container (`.rm-project-group` /
`.rm-tree`) for both, so the guard `draggedRow !== targetRow` was always
false and `insertBefore` never ran — proven live at `:7733`: a synchronous
before/after DOM-order read across a real drop showed IDENTICAL order,
while the network tab showed the `/api/roadmap/rank` POST firing 200 (the
persistence path "worked"; the pixels never moved). Fixed in `b66f7e1`:
`movableRowEl(el, container)` now walks to the container's DIRECT CHILD,
and the replacement test, **R17-DRAG-3**, extracts the real function,
runs it against a synthetic nested DOM, and asserts the row order actually
changes (`r0,r1,r2` → `r1,r0,r2`) — mutation-proven (reverting
`movableRowEl` to return the container turns R17-DRAG-3 red, 498/1;
restoring returns 499/0).

### 5-Whys to the latent cause

1. **Why did a broken feature ship green?** Because the test asserting it
   worked never executed the code path it claimed to cover.
2. **Why did a source-text regex get written as if it were a behavioral
   test?** Because `cockpit.selftest.js` is explicitly a "DOM-free
   structural self-test" (its own header comment) — a deliberate, mostly
   correct design choice (no headless browser, no build step) that was
   over-generalized to cover claims (`insertBefore` actually runs, order
   actually changes) that structure-matching cannot verify.
3. **Why wasn't the over-generalization caught in code review?** Because
   — see Class 1 — this file was never in the review surface. A shape-only
   assertion is exactly the kind of defect an adversarial reviewer is good
   at catching (the failure mode is well-known and nameable) and exactly
   the kind self-review under time pressure is bad at catching (the
   author already believes the feature works, so a green check confirms
   the belief rather than testing it).
4. **Why does the harness have no mechanism that would have flagged this
   automatically?** Because no existing gate/lint distinguishes "this
   assertion executed the real code path and checked its output" from
   "this assertion grepped the file for a token that looks related." Both
   render identically as a green line in a self-test summary.
5. **Why is this a CLASS problem and not just this one instance?** Because
   `cockpit.selftest.js` (499 assertions after the fix) is explicitly
   structural-by-design, and other selftest files in this repo use the
   same "read the source as text, assert a substring/pattern" technique
   for MANY legitimate structural claims (e.g. "this dead mechanism's
   markup is GONE from the HTML," "this function is exported"). The
   incident instance was fixed; the pattern that produced it is still
   available to produce the next one, in this file or any sibling.

**Latent cause:** this harness has no way to distinguish, at the assertion
level, "asserts real behavior" from "asserts source shape," so a
regex-over-text assertion and a real-execution assertion are
indistinguishable in a green self-test summary — the exact
distinguishability gap that let R17-DRAG-2 pass for as long as it did.

### Existing-controls audit

| Control | Would this have caught R17-DRAG-2? |
|---|---|
| `pre-commit-tdd-gate` (mocking-the-SUT / trivial-assertion checks) | NO — R17-DRAG-2 was neither a mock nor a trivial assertion (`expect(true).toBe(true)`); it was a substantive-LOOKING assertion (`js.includes('insertBefore')`) that happened to verify the wrong thing (presence of a token, not its effect). |
| `no-test-skip-gate` | NO — the test was never skipped, it was wrongly green. |
| `harness-reviewer` (had it been in-surface) | LIKELY — a human/adversarial reviewer reading the assertion next to the function it claims to cover is well-positioned to notice "this only checks the string is present," but this is a per-review catch, not a durable mechanism; it depends on the reviewer happening to read that specific assertion closely. |
| Any structural/lint check | NONE EXISTS today that distinguishes regex-over-source-text assertions from real-execution assertions. This is the actual gap. |

### Proposed mechanism (design only, this round)

A `--self-test`-file lint (candidate name: `behavioral-claim-lint.sh`,
run as a doctor check, WARN initially per the calibration discipline
below) that flags an assertion as A CANDIDATE FOR MANUAL REVIEW, not an
automatic block, when it: (a) reads a source file into a string variable
(`readFileSync`/`cat`/equivalent) AND (b) asserts on that string via a
pattern/substring match (`.includes(`, `.match(`, `grep`, a regex literal)
AND (c) the assertion's own name/description (the string passed to the
test-runner, e.g. `'R17-DRAG-2 ...'`) contains a BEHAVIORAL verb — "moves,"
"updates," "renders," "changes," "fires," "persists," "calls," "returns
[a value]" — as opposed to a STRUCTURAL verb — "exports," "is present,"
"contains," "is gone," "is defined," "is wired." The heuristic is
deliberately a vocabulary check on the assertion's OWN stated claim, not an
attempt to statically prove whether the code path executes — the same
class of imprecise-but-directionally-useful lint as an existing-code
`grep`-based style check.

**Honest false-positive rate.** This will NOT be zero and should not be
sold as such. Legitimate structural claims exist and must not be
suppressed: "this dead mechanism's markup is GONE from the HTML,"
"function X is exported," "this deprecated flag no longer appears in the
config schema" are all correctly regex-over-text assertions with no
real-execution equivalent possible (there is nothing to "execute" to prove
an absence). A vocabulary heuristic will sometimes tag a legitimately
structural claim that happens to use a behavioral-sounding verb ("the
retired drag handle no longer FIRES a dragstart listener" — structural
absence, phrased with a behavioral verb) and will sometimes miss a
behavioral claim phrased structurally. This is why the mechanism proposed
is WARN + a name-sweep list for a maintainer to triage, not an auto-block
— an auto-block on an imprecise heuristic would either train the operator
to silence it (cry-wolf) or block legitimate structural tests, both worse
than the status quo. Calibration path: run the lint once against this
repo's existing ~15 selftest files (retroactive, non-blocking), read the
false-positive rate on REAL output before deciding whether WARN graduates
to a stronger rung.

### Testing strategy (for when this is built)

A fixture selftest file with three known-shape assertions (one genuine
structural-absence claim, one genuine behavioral claim phrased correctly
as a real-execution test, one R17-DRAG-2-shaped regex-claiming-behavior)
run through the lint; expect exactly the third flagged. Mutation-test the
lint itself: comment out the vocabulary-check step, confirm the fixture's
red case goes undetected; restore, confirm detected again. Retroactive run
against this repo's real selftest corpus to measure the actual FP rate
before any blocking mode is proposed.

### §10 credentials

**Golden scenario:** a new selftest assertion is added that reads a
source file, checks for a substring, and its OWN description claims a
behavioral effect ("X now moves the row," "Y persists the change") — the
lint flags it for manual triage before the PR/commit lands, the way
`harness-reviewer` would have caught R17-DRAG-2 had `cockpit.selftest.js`
been in-surface at the time.

**Expected false-positive rate:** non-zero and named honestly above
(legitimate structural claims phrased with behavioral-sounding verbs).
WARN-only at launch specifically because of this; a numeric target is
deferred to the retroactive calibration run rather than asserted without
data.

**Retirement condition:** retire if a future test-authoring convention
(e.g., a required `// STRUCTURAL:` / `// BEHAVIORAL:` tag on every
self-test assertion, enforced by a stricter mechanical check) makes the
vocabulary heuristic redundant, or if the calibration run shows the FP
rate is too high to be useful even in WARN mode.

---

## Class 3 — UI-round acceptance is sandbox-only (PROPOSED)

### The incident pattern

UI builders verify against fixture/sandbox servers (e.g. port 7799 with
seeded fixtures); the operator finds real bugs at the live deployment
(port 7733, real data). Round 16's blue-sweep styling, the Inbox `file://`
links, and the requests pipeline all reportedly PASSED sandbox
verification and were broken live. This is a distinct failure mode from
Class 2: the assertions in these cases may have been genuinely
behavioral and genuinely executed — they just executed against a
fixture that didn't reproduce the real environment's shape (real data
volume, real link targets, real timing).

### 5-Whys to the latent cause

1. **Why did bugs reach the operator that sandbox verification should
   have caught?** Because the sandbox's fixtures didn't reproduce the
   real condition that triggered the bug (e.g., real file paths that
   render as `file://` links only make sense against a real filesystem
   layout; a fixture with synthetic paths never exercises that).
2. **Why do builders default to sandbox-only verification?** Because a
   fixture server is faster to set up, deterministic, and doesn't risk
   corrupting real operator data — all genuinely good reasons, not
   laziness.
3. **Why is there no requirement to ALSO check the live app?** Because no
   acceptance gate for a UI-round plan currently requires evidence from
   the real deployed instance — `Verification: full` tasks require a
   `Prove it works:` scenario, but nothing currently distinguishes "ran
   against fixtures" from "ran against the real, operator-used instance"
   as a completeness criterion.
4. **Why does this matter more for THIS product than for typical harness
   work?** Because the cockpit's entire value proposition is fidelity to
   the operator's real, current state — a fixture is definitionally a
   simplified stand-in, and several of the bugs found (dead `file://`
   links, an empty Requests tab) are exactly the class of defect that
   only manifests against real data shape, real link targets, or real
   timing — never in a curated fixture.
5. **Why hasn't this been fixed already, given it's a repeat pattern
   (Round 16, this round)?** Because each occurrence was previously
   diagnosed and fixed as an INSTANCE (the specific styling bug, the
   specific broken link) rather than the CLASS (no mechanism requires
   live-app evidence at all) — this proposal is the first time the class
   itself, not just its latest instance, is being named.

**Latent cause:** no acceptance mechanism for this product distinguishes
"verified against a fixture" from "verified against the real, live
instance the operator actually uses," so a round can satisfy every
`Prove it works:` scenario in a plan while never having been exercised
against the actual live system.

### Existing-controls audit

| Control | Requires live-app evidence today? |
|---|---|
| `functionality-verifier` / `end-user-advocate` (runtime mode) | Can drive a live app via browser MCP, but nothing REQUIRES it be pointed at `:7733` specifically rather than a sandbox — the agent goes wherever the plan/task tells it to. |
| Plan template's `Prove it works:` sub-block | Requires "concrete UI clicks / API calls / DB queries with real values," but "real values" has been satisfied by sandbox-fixture values in practice; nothing in the template distinguishes fixture-real from live-real. |
| `Closure Contract` | Names commands + expected outputs, again with no field distinguishing target environment. |

**Conclusion:** the gap is not that no verification happens — it's that
nothing in the acceptance CONTRACT names WHICH environment the evidence
must come from, so "sandbox, always" silently became the default via
convenience rather than an explicit, reviewed decision.

### Proposed mechanism (design only, this round)

Add a required field to `Verification: full` tasks whose `Files to
Modify/Create` touch `neural-lace/workstreams-ui/**`: a
`**Live-app evidence:**` sub-block (sibling to the existing `Prove it
works:` / `Wire checks:` / `Integration points:`) naming the SPECIFIC
live-app check — a `curl`/browser-MCP probe against the actual running
`:7733` instance (or whatever port/URL the operator's real deployment
uses) with REAL current data, not seeded fixtures. `task-verifier` (or a
new lightweight check inside it) requires this sub-block be present and
non-placeholder for any UI-touching task before flipping the checkbox,
the same way `**Wire checks:**` is already required and statically
verified today. Sandbox/fixture verification remains valuable and
required for FAST iteration during build — this does not replace it, it
adds a mandatory final cross-check against reality before a round can be
marked done.

**Honest cost/friction.** This adds a real step builders must not skip:
after fixture verification passes, they must ALSO touch the live
instance. For read-only checks (does the Inbox render the right links,
does the Requests tab show real items) this is cheap. For anything with
side effects against real operator data, this needs a scoped, read-mostly
probe convention (e.g., GET-only checks, or checks against a read replica
if one exists) so live-app verification does not itself risk corrupting
the operator's real state — a design detail to work out before this is
built, not an unaddressed gap.

### Testing strategy (for when this is built)

A test plan/task carrying the new sub-block, run through `task-verifier`
in a fixture where the sub-block is present-but-placeholder (expect
BLOCK), present-and-substantive (expect PASS-eligible), and absent
entirely for a UI-touching task (expect BLOCK, mirroring how a missing
`Wire checks:` block is already handled). Mutation-test: remove the new
check from `task-verifier`, confirm a placeholder live-app block
incorrectly passes; restore, confirm it correctly blocks.

### §10 credentials

**Golden scenario:** a UI round's task ships with every `Prove it works:`
scenario green against a sandbox fixture but has never been exercised
against the real `:7733` deployment — `task-verifier` blocks the checkbox
flip until a `**Live-app evidence:**` sub-block with a real probe result
is present, the way Round 16's blue-sweep regression and this round's
dead-links/empty-Requests-tab defects would have been caught before the
operator found them.

**Expected false-positive rate:** near-zero as a REQUIREMENT (any
genuine UI task can produce this evidence — the cockpit is always
running somewhere real); the risk is entirely on the friction/safety side
(see honest cost above), not on false-blocking legitimate work.

**Retirement condition:** retire if the sandbox/fixture environment is
made to faithfully mirror production data shape and timing (removing the
fixture-vs-live gap this proposal exists to close), or if the cockpit
migrates to a deploy model where every merge is automatically smoke-tested
against a live-data mirror as part of CI, making a manual live-app
evidence block redundant.
