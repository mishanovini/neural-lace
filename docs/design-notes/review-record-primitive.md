# Design: the review-record primitive

Batch task 1 of `docs/plans/harness-governance-batch-2026-07-15.md`. Feeds tasks 2
(review-before-deploy gate), 3 (evidence-before-fix commit gate), and 4 (pt's
`artifact-evidence-bar` integration). MUST pass `architecture-reviewer` (design-shape
review) before any builder is dispatched against tasks 2-4 — this doc is that review's
input, not a build spec to execute directly.

**Status: SOUND-WITH-AMENDMENTS (architecture-reviewer verdict, 2026-07-16).** The six
binding amendments are folded into the relevant sections below (marked `[amended A-F]`)
and summarized in full in "Architecture-review amendments (2026-07-16, folded)" near
the end of this doc. This doc is now a build spec for task 2 (task 3/4 still need their
own consumer-side build).

## Problem

Three follow-ups from the model-enforcement postmortem share one root gap: **§10
("no artifact ships without evidence") is a Pattern, not a Mechanism.** Nothing
deterministically stops (a) a harness change reaching every machine without a
`harness-reviewer` PASS, (b) a `fix(...)` commit landing on an inferred-not-observed
root cause, or (c) a gate/agent/design/review landing without its own evidence bar
(pt's `artifact-evidence-bar`). All three need the same thing: **a structured record,
keyed to a change, that a downstream gate can check for a PASS verdict before letting
the next step (deploy / commit / land) proceed.** This doc designs that record once.

## Prior art in this repo (what I reuse, what I reject)

**`write-evidence.sh` / `close-plan.sh`'s `.evidence.json`** (e.g.
`docs/plans/concurrent-ownership-gate-2026-07-12-evidence/1.evidence.json`):
`{schema_version, task_id, verdict, commit_sha, files_modified[], mechanical_checks{},
timestamp, verifier, plan_path}`. **Reused:** one-file-per-record under a sibling
directory (never a shared ledger), `schema_version`, a `jq`-able `verdict` enum,
`files_modified` as a list. **Rejected as-is:** `commit_sha` as the sole identity key
(see Identity model) — this record needs per-file content digests, since "does file C,
changed after the review, still have coverage" is a per-file question a commit SHA
cannot answer.

**`manifest.json`'s evidence-bar fields** (the `model-pin` entry,
`adapters/claude-code/manifest.json:44-69`): `added_after`, `golden_scenario`,
`fp_expectation`, `retirement_condition`, `waiver_path`/`honesty_rationale`. **Reused:**
these are exactly pt's `artifact-evidence-bar` fields for the `Gate` artifact type — the
`artifact-evidence` record kind below carries them verbatim, not a parallel vocabulary.

**`check_new_gate_evidence_bar`** (`harness-doctor.sh:2059-2115`): asserts the four
evidence fields on manifest entries with `added_after >= "2026-07"`, but **`continue`s
past any entry with NO `added_after` at all** (line 2081) — the exact evasion-by-omission
batch task 5 fixes. **Lesson applied here:** an "if present, must be complete" check is
gameable by omission; the deploy gate (task 2) must require a record to *exist* for
every trigger-surface file, not merely validate one *if* present.

**`artifact-evidence-bar.md` / `-full.md`** (pt/master, read via
`git show c2aacad:adapters/claude-code/doctrine/artifact-evidence-bar.md`, not yet
reconciled to this checkout): generalizes §10 to Gate / Agent / Design / Review, each
with its own required evidence fields, enforced per that doc by `plan-reviewer.sh` +
`harness-reviewer` — but its own manifest entry admits **"the two enforcing gates ...
are NOT WIRED"**. This record is the wiring.

**Reviewer agents cannot write files.** `harness-reviewer.md` and
`plan-evidence-reviewer.md` both declare `tools: Read, Grep, Glob, Bash` (verified, no
Write/Edit). A design where the reviewer "writes its own record" isn't buildable
against current agent charters — see Writer section.

## The record

**One schema, `kind`-discriminated** (not three). Rationale: all three consumers ask
the *same* trust question — "does a PASS cover this exact content, and can I believe a
real reviewer produced it" — which is the shared identity + staleness + anti-fabrication
logic. Splitting into three schemas would triple that logic for zero difference in the
part that actually matters; only the per-kind `payload` differs.

```json
{
  "schema_version": 1,
  "kind": "harness-change-review",
  "record_id": "hcr-20260715-a3f9c1",
  "created_at": "2026-07-15T18:42:03Z",
  "verdict": "PASS",
  "reviewer": "harness-reviewer",
  "reviewer_model": "fable",
  "plan_ref": "docs/plans/harness-governance-batch-2026-07-15.md#task-2",
  "change_ref": { "commit_sha": "0085781", "branch": "master" },
  "covered_files": [
    { "path": "adapters/claude-code/hooks/model-pin-gate.sh",
      "blob_sha": "9f2a1c4de9b1c0..." },
    { "path": "adapters/claude-code/manifest.json",
      "blob_sha": "7be0dd28f31a..." }
  ],
  "dispatch_evidence": {
    "transcript_ref": "session 29f2930a, harness-reviewer invocation, final message",
    "verdict_quote": "PASS — golden scenario covers silent-inherit; fp_expectation names the display-name-resolution edge case; retirement_condition present.",
    "findings_summary": "0 Critical, 1 Minor (fixed same commit)."
  },
  "written_by": "orchestrator-session-29f2930a via write-review-record.sh",
  "payload": {
    "golden_scenario_confirmed": true,
    "fp_expectation_reviewed": true
  }
}
```

Per-kind `payload` (shared envelope above stays fixed):
- **`harness-change-review`** (consumer: task 2): `{golden_scenario_confirmed,
  fp_expectation_reviewed, findings[]}`.
- **`fix-root-cause`** (consumer: task 3): `{root_cause: {tag: "PROVEN"|"INFERRED",
  evidence, refuter_if_inferred}, blast_radius_bounded: bool}`.
- **`artifact-evidence`** (consumer: task 4 / pt's bar): `{artifact_type:
  "gate"|"agent"|"design"|"review", golden_case_or_scenario, fp_expectation,
  retirement_condition, architecture_review_ref}` — the manifest fields, carried
  1:1 so task 4 is a translation, not a redesign.

`verdict` ∈ `PASS | REFORMULATE | REJECT` (mirrors `harness-reviewer`'s existing
output contract — no new vocabulary for builders to learn).

## Identity + staleness model

**Identity key = the set of `{path, blob_sha}` pairs in `covered_files`** — the git
blob SHA of each reviewed file's content, not the commit SHA, not a whole-subtree hash,
not the plan-task id alone.

- **Why not commit SHA:** a rebase, amend, or fixup-on-top changes the commit SHA
  without changing content (spurious staleness → re-review churn), while a fixup commit
  that changes content *keeps referencing the same reviewed ancestor* if the gate
  checks ancestry rather than the tip — either way, "which SHA does the gate check"
  is structurally ambiguous. A review of commit X provably says nothing about X+1.
- **Why not one tree-hash of the whole `adapters/claude-code/` subtree:** conflates
  every file into one hash, so an unrelated one-line doc typo anywhere invalidates
  *every* file's coverage simultaneously (false generalized staleness), and cannot
  express partial coverage — the exact "review of A,B doesn't cover unreviewed C" case
  this design must support.
- **Why not plan-task-id alone:** necessary as a human-facing label (`plan_ref`,
  kept in the envelope for traceability) but not sufficient as the trust boundary — a
  task id doesn't change when a builder pushes a silent fixup after the review ran; the
  label would still read "reviewed" while content drifted underneath it.
- **Staleness falls out of content-addressing for free.** The moment any covered file's
  live blob SHA no longer matches a record's `covered_files` entry, that record simply
  no longer applies to that file — there is no separate "invalidate this record" step,
  no stale-flag to set, no cleanup job. This is the load-bearing property: it is
  impossible to forget to invalidate a record, because "does it match right now" is
  computed fresh every time, not cached as a boolean.
- **Records are append-only.** A superseding review writes a *new* record with a new
  `record_id`; old records are never edited or deleted. This is both an audit trail and
  an anti-fabrication property (see Writer section) — a PASS can't be silently
  retargeted to cover different content after the fact.
- **`REJECT`/`REFORMULATE` block identically to absence** — only an exact-content-match
  `PASS` unblocks. A rejected record sitting in history is informational (why did the
  first attempt fail), not itself enforced beyond "still no PASS, still blocked."

## Trigger surface + fp expectation `[amended A]`

**Surface = path-match, NOT manifest-derived** (reversed from the pre-review draft's
"derive the surface from the manifest's own `hooks[]` union" — see Amendment A for why).
A file is in-surface **iff its repo-relative path matches**
`adapters/claude-code/{hooks/**/*.sh, scripts/**/*.sh, agents/*.md, config/**,
manifest.json, settings.json.template, rules/**}`. This closes the exact hole the
pre-review draft had: `hooks/lib/merge-scan-lib.sh`, `hooks/lib/progress-log-lib.sh`,
and `scripts/dispatch-provenance.sh` — three of the five files reverted by merge
`937e8cb` — appear in **no** `manifest.json` entry's `hooks[]` array, so a manifest-
derived surface would have silently excluded them from review-before-deploy coverage
even though they are exactly the kind of executable harness content the gate exists to
protect. `hooks/**/*.sh` and `scripts/**/*.sh` (recursive, includes `lib/`) close that
hole directly — a file's blast radius comes from being an executable/behavioral surface
under `adapters/claude-code/`, not from whether some manifest author remembered to list
it in a `hooks[]` array.

**The manifest is now a CROSS-CHECK, not the source of the surface:** every filename
named in any `manifest.json` entry's `hooks[]` array MUST resolve to a path that is
itself in-surface per the glob above — if a manifest entry names a hook file the glob
wouldn't match, that is a manifest/surface inconsistency and the doctor REDs (see the
new `check_review_surface_cross_check` doctor check, task 2 build). This is the
inverse relationship of the pre-review draft: before, the manifest was upstream of the
surface (and could silently narrow it by omission); now the path-glob is upstream and
the manifest is checked against it, so an omission is a doctor RED instead of a silent
gap.

**Explicitly excluded:** `doctrine/**`, `templates/**`, `skills/**`, `commands/**`,
`examples/**`, `patterns/**`, `business-patterns*`, `data/**`, `work-shapes/**`,
`pipeline-*/**` — these are documentation/content surfaces whose failure mode is "a
maintainer reads something wrong," not "every machine's enforcement silently changes."

**Open Question 1 resolved (per Amendment A):** `scripts/*.sh` invoked *by* hooks or by
orchestrator-run procedures (`write-evidence.sh`, `close-plan.sh`, `plan-lifecycle.sh`)
are now IN-SURFACE by construction — `scripts/**/*.sh` is part of the glob, not a
residual carved out. There is no longer a class of hook-equivalent-blast-radius script
sitting outside the surface.

**fp_expectation: low-moderate.** A pure-prose doctrine/rules-content edit is scoped
out entirely. The one deliberate over-inclusion: an `agents/*.md` wording-only edit
still requires a PASS, because an agent's prompt *is* its enforcement logic and there
is no cheap way to distinguish cosmetic from behavioral prose edits — trading rare
friction on cosmetic-only edits for never missing a behavioral one dressed as cosmetic.

## Writer + anti-fabrication residual `[amended C]`

**Neither `harness-reviewer` nor `architecture-reviewer` can write the record** — both
are `tools: Read, Grep, Glob, Bash`, no Write/Edit (verified against
`adapters/claude-code/agents/harness-reviewer.md`). A new
`write-review-record.sh` (mirrors `write-evidence.sh`'s shape: `capture --kind <k>
--reviewer <agent> --verdict <v> --plan-ref <ref> --file <path>...`) is invoked by the
**orchestrating session**, not the reviewer, after the reviewer returns its verdict.
The script computes each file's live `blob_sha` via `git hash-object` (or
`git ls-tree`), and requires a non-empty `dispatch_evidence.verdict_quote`.

**Downgrade (per Amendment C — do not oversell this record):** the record's
`dispatch_evidence.verdict_quote` is **NOT independently verifiable at deploy time**.
Zero `SubagentStop`/`TaskCompleted` capture hooks exist anywhere in this harness that
would let a downstream check retrieve the reviewer's actual transcript and confirm the
quote is real (verified: grepped `settings.json.template` and every hook under
`hooks/` for a capture wired to either event — none feeds this record). The pre-review
draft's "verbatim substring + `plan-evidence-reviewer` spot-check" mitigation is
**honestly insufficient as an anti-fabrication control** — a spot-check that runs
*after* the fact, on the same LLM-authored record, with no independent transcript to
check the quote against, cannot rule out fabrication; it can only make fabrication
slightly more effortful.

**What this record IS, restated:** an audit trail + honesty anchor (it makes the claim
"a review happened and said PASS" a citable, timestamped, content-addressed artifact
instead of an unrecorded verbal claim) — **NOT a deploy-path anti-fabrication
control.** The deploy gate (task 2) checks record **EXISTENCE and content-match only**;
it structurally cannot check whether the quoted verdict is genuine. This is a real,
named gap, not a solved one.

**Follow-up (out of scope for this batch, named not silently dropped):** a real anchor
requires a capture hook on `SubagentStop` (or `TaskCompleted` for Task-tool dispatches)
that writes the reviewer's actual final message to a location `write-review-record.sh`
can read back and diff against the claimed `verdict_quote` — turning "the orchestrator
says the reviewer said X" into "the transcript captured at dispatch time says X." Log
this in `docs/backlog.md` as a follow-up (`REVIEW-RECORD-ANTI-FABRICATION-ANCHOR-01`)
when task 2 lands.

## Verdict lifecycle

`PASS` → consumed by the relevant consumer gate as "this exact content is cleared."
`REFORMULATE` → reviewer wants a specific change; blocks like absence; the orchestrator
re-dispatches on the revised diff, producing a new record. `REJECT` → reviewer rejects
the direction; blocks like absence; no automatic escalation is built into this design
(see Open Question 3). Re-review is simply "run the same dispatch-then-write flow
again" — there is no separate "invalidate the old record" step because content-
addressing already makes the old record inapplicable to changed content.

## Consumer contracts

**1. Review-before-deploy gate (task 2).** `[amended D, E, F]` At `install.sh` /
`session-start-auto-install.sh` sync time, for every file in the trigger surface whose
live `blob_sha` differs from what's already installed at the target: (a) check the
grandfather marker first (Amendment E — pre-cutover content is covered with no record
lookup); (b) else do an **index lookup** (Amendment D — `docs/reviews/records/
index.json`, a content-keyed `{path, blob_sha} -> record_id` map, rebuildable from the
records directory but never rebuilt on the hot path) for a `kind: harness-change-review`
row with `verdict: PASS` matching that exact `{path, blob_sha}`. **The records directory
itself (`docs/reviews/records/*.json`) is audit-only and is never scanned by the deploy
gate** — only the index is read at deploy time, and every subprocess the gate runs
(git, jq) carries a timeout, so an unbounded/growing records directory never slows or
hangs a deploy.

**Posture differs by carrier (Amendment F — do not describe both the same way):**
- **`install.sh` (operator present) = loud HARD BLOCK.** Any uncovered changed file
  aborts the *entire* install run before any file is touched, with a teaching message
  naming every uncovered file + its blob_sha and the exact remedy (get a PASS review,
  or wait for the fresh dispatch). The operator is present to act on it immediately.
- **`session-start-auto-install.sh` (fail-open by platform contract, always exits 0)
  = SKIP + loud WARN.** An uncovered file is left un-synced (stale-not-blocked,
  stated explicitly, never silently) while every other file still syncs normally; a
  loud warning names the file. This composes with the hook's existing fail-open
  posture rather than fighting it — making this ONE hook the sole hard-blocking
  exception on an otherwise-always-exits-0 script would be a bigger behavioral change
  than this batch's blast-radius budget allows, and would reintroduce the exact
  "a background SessionStart hook can wedge every session" risk the fail-open contract
  exists to prevent. **Rollout-lag consequence, stated honestly:** a machine relying
  solely on auto-install can run a stale (but never unreviewed-and-silently-applied)
  copy of a covered file for at least one more session after a change lands unreviewed
  — `install.sh` remains the authoritative, immediate enforcement point.

**Bootstrap/grandfather (Amendment E):** enforcement applies only to a file whose
**blob content first appears on master at/after the cutover** (mirrors the manifest's
own `added_after >= "2026-07"` convention, applied per-blob instead of per-manifest-
entry). A `docs/reviews/records/grandfather-manifest.json` snapshot, taken once at the
cutover commit, lists every in-surface file's `{path, blob_sha}` as of that commit —
anything matching it is covered with no review record needed. This is what makes a
fresh machine (nothing installed yet) or a long-stale machine (everything pre-cutover)
never get bricked by this gate: only *new* content earns the requirement.

**2. Evidence-before-fix commit gate (task 3).** On a commit whose message matches
`^fix(...)`, require a `kind: fix-root-cause` record whose `covered_files` matches the
commit's changed files and whose `payload.root_cause.tag == "PROVEN"` (an `INFERRED`
tag blocks unless `payload.blast_radius_bounded == true`, per the lesson's stated
residual that evidence is sometimes genuinely unreachable).

**3. artifact-evidence-bar (task 4).** `plan-reviewer.sh`'s architecture-review-before-
build check and an agent golden-case check both become: "does a `kind:
artifact-evidence` record with `verdict: PASS` exist whose `covered_files` matches this
design doc / this agent file's current content." Direct reuse of pt's already-named
required fields, carried in `payload`.

## Location + format `[amended D]`

`docs/reviews/records/<yyyy-mm-dd>-<kind>-<short-id>.json`, **committed** (not
gitignored, not `.claude/state/`) — forced by the deploy gate's own mechanism:
`session-start-auto-install.sh` reads canonical content via `git show
origin/master:<path>` on every machine, so anything not committed and merged to master
is invisible to the check on every machine but the one that wrote it.

**The index (Amendment D, cost model) is ALSO committed, at `docs/reviews/records/
index.json`** — this is the one file the deploy gate actually reads on its hot path (a
single `jq`/`node` lookup against one small JSON file), never the records directory.
Committing the index (rather than treating it as a `.claude/state/` cache) is required
by the exact same reasoning as the records themselves: `session-start-auto-install.sh`
resolves canonical content via `git show <ref>:<path>`, so an uncommitted index would
be invisible on every machine but the one that built it. The index is fully
**rebuildable** from the records directory (`write-review-record.sh --rebuild-index`
recomputes it from scratch) — it is a derived read-optimization, never a second source
of truth, and a doctor check (`check_review_index_consistency`, task 2 build) REDs if
the committed index and a from-scratch rebuild disagree.

**One file per record, never a shared ledger** — a single JSONL ledger would reproduce
the exact merge-conflict class the batch plan's own R1 task names as the recurring pain
point (`manifest.json` + `backlog.md` are "the only" files that conflict during the pt
reconcile); N parallel worktree builders writing records concurrently would multiply
that conflict onto a new file. One-file-per-record (already `close-plan.sh`'s
convention) is merge-conflict-free by construction.

## Rejected alternatives (summary)

| Alternative | Rejected because |
|---|---|
| Commit-SHA identity | Rebase/amend/fixup churn; ambiguous which SHA a gate checks |
| Whole-subtree tree-hash | One hash for everything; can't express partial coverage; unrelated edits cause false staleness everywhere |
| Plan-task-id as sole key | Doesn't change when content silently drifts after review |
| `.claude/state/` location | Invisible to the estate-wide deploy gate, which reads only committed+merged content |
| Single JSONL ledger | Reproduces the manifest.json/backlog.md merge-conflict class across every parallel builder |
| MD prose as canonical format | A bash gate parsing prose reliably is the fragility class `write-evidence.sh` replaced JSON for |
| Reviewer agent writes its own record | Not buildable — `harness-reviewer`/`plan-evidence-reviewer` have no Write/Edit tool |
| Three separate schemas (one per consumer) | Triplicates identical identity/staleness/anti-fabrication logic for no behavioral gain |

## Open questions for the architecture reviewer — ANSWERED (2026-07-16)

1. **Trigger-surface scope: ANSWERED = A.** Path-glob surface
   (`adapters/claude-code/{hooks/**/*.sh, scripts/**/*.sh, agents/*.md, config/**,
   manifest.json, settings.json.template, rules/**}`), manifest is a cross-check not
   the source. See "Trigger surface + fp expectation" above.
2. **Anti-fabrication bar: ANSWERED = insufficient, downgraded.** Quoted-verbatim +
   spot-check does NOT meet the bar "gates every harness deploy on every machine"
   implies. Downgraded per Amendment C: the record is an audit + honesty anchor, NOT a
   deploy-path anti-fabrication control, until a real capture-hook anchor is built
   (named follow-up, out of scope here).
3. **REJECT escalation: ANSWERED = ledger-log only, no operator gate.** No operator
   sign-off requirement on a single REJECT. `write-review-record.sh` logs a ledger
   entry (via the existing signal-ledger convention) when the **same file set** earns
   **2+ consecutive** `REJECT`/`REFORMULATE` records — informational surfacing, not a
   block; "blocks until a materially different diff earns PASS" remains sufficient as
   the actual gate.
4. **Revert-silently-revalidates: ANSWERED = accept, no TTL.** A file reverted to a
   previously-PASS'd `blob_sha` is covered again by the old record with no new review
   — accepted as correct, not a gap: if the content is byte-identical to something a
   human reviewer already looked at and passed, re-reviewing it teaches nothing. No
   TTL (rejected: a clock-based expiry adds timer-drift complexity for zero additional
   safety — content that hasn't changed cannot have grown a NEW defect from the mere
   passage of time).
5. **Retention: ANSWERED = unbounded is fine, records are audit-only.** Per Amendment
   D, the records directory is never on the deploy gate's hot path (the index is), so
   unbounded growth costs disk, not deploy latency. It is the audit trail the
   append-only anti-fabrication property depends on — pruning it would destroy that
   property. No pruning/archival policy for this batch.

## Architecture-review amendments (2026-07-16, folded)

**Verdict: SOUND-WITH-AMENDMENTS.** Six binding amendments, folded into the sections
above (marked `[amended <letter>]`) rather than kept as a separate patch layer, so the
doc stays internally coherent for anyone building tasks 2-4 from it going forward.

| # | Amendment | Section amended |
|---|---|---|
| A | Trigger surface = path-glob match (`adapters/claude-code/{hooks/**/*.sh, scripts/**/*.sh, agents/*.md, config/**, manifest.json, settings.json.template, rules/**}`); manifest is a cross-check, not the source. Rationale: 3 of the 5 files reverted by merge `937e8cb` (`hooks/lib/merge-scan-lib.sh`, `hooks/lib/progress-log-lib.sh`, `scripts/dispatch-provenance.sh`) are in NO manifest `hooks[]` array — a manifest-derived surface is silently holed. | Trigger surface + fp expectation |
| B | New "What this gate does NOT catch" section (below): content-presence only — blind to (i) absence of expected forward content (silent drop, the `937e8cb` class) and (ii) reverts to a previously-PASS'd blob. Merge-integrity is the merge-time dropped-side sweep (a separate mechanism, runbook step 6). No TTL (rejected — see OQ4). | New section below + OQ4/OQ5 |
| C | Anti-fabrication downgrade: the deploy gate checks record EXISTENCE only, cannot verify the reviewer quote (zero `SubagentStop`/`TaskCompleted` capture hooks exist). The record is an audit + honesty anchor, NOT deploy-path anti-fabrication. A real anchor is a named follow-up, out of scope. | Writer + anti-fabrication residual |
| D | Cost: the deploy gate reads a content-keyed INDEX file (`docs/reviews/records/index.json`, committed, rebuildable from records) on its hot path; the records dir is audit-only and never scanned by the gate; every gate subprocess gets a timeout. Records unbounded is fine for audit-only. | Consumer contracts (task 2) + Location + format |
| E | Bootstrap/cutover grandfather: enforcement applies only to blobs first appearing on master at/after the cutover (mirrors the manifest's `added_after >= "2026-07"` pattern, applied per-blob). A fresh or long-stale machine is never bricked. | Consumer contracts (task 2) |
| F | Posture per carrier: `session-start-auto-install.sh` is fail-open by platform contract (exits 0 always) — SKIPS the unreviewed file + warns loudly (stale-not-blocked, stated explicitly); `install.sh` (operator-present) is the loud HARD-BLOCK path; rollout lag of ≥1 session on the auto-install path is stated, not hidden. | Consumer contracts (task 2) |

## What this gate does NOT catch `[amendment B]`

Stated explicitly so nobody mistakes this record for more than it is: this is a
**content-presence** check — "does a PASS record's `covered_files` include this exact
`{path, blob_sha}`" — and nothing more. Named blind spots:

- **Absence of expected forward content (the `937e8cb` class).** A merge or rebase
  that silently DROPS a file the source branch carried is not something a per-file
  content-presence check can see, because there is no "expected file" model here — the
  gate only ever asks "is THIS file, which IS present, covered," never "should a file
  be present that isn't." Merge-integrity (did every file the merge's source side
  carried survive into the result) is a **different mechanism**: the merge-time
  dropped-side sweep at runbook step 6 of
  `docs/runbooks/master-reconcile-and-estate-cleanup.md`. This record does not
  substitute for it and does not claim to.
- **Reverts to a previously-PASS'd blob.** By design (see OQ4) — accepted, not a gap.
- **No TTL / staleness clock.** Rejected per OQ4 — timer-drift complexity for zero
  additional safety over content-addressing.
- **The grandfather manifest and the records directory are themselves TRUST
  ANCHORS, not self-verifying data** (harness-review REFORMULATE fixup, finding 3,
  2026-07-16). Before this fixup, nothing checked whether `grandfather-manifest.json`
  actually reflected reality — a hand-edit (add an entry for content that was NEVER
  reviewed) or a silent re-bootstrap (quietly moving the cutover forward to
  grandfather something that should have required a real review) would have been
  invisible. This is now DETECTABLE two ways: (1) the doctor's
  `review-grandfather-integrity` check re-derives the grandfather manifest at its own
  recorded `cutover_ref` (a resolved commit SHA, never the literal string `HEAD` — see
  Bootstrap section) via `bootstrap-grandfather --ref <cutover_ref>` and REDs on any
  divergence from the committed file, and separately REDs if the records directory is
  absent while the gate's own lib is present (a bootstrapped-then-emptied checkout is
  a defect, distinct from the legitimate pre-cutover fail-open case where the lib
  itself doesn't exist yet); (2) `grandfather-manifest.json`'s own git history is a
  second, independent audit trail — every edit to it is a normal commit, reviewable
  the same way any other harness change is. Neither mechanism PREVENTS a bad edit at
  write time (there is no commit-time gate on this specific file yet); both make a bad
  edit detectable after the fact, which is the same class of residual as the
  anti-fabrication gap above — raising the cost of dishonesty, not eliminating it.
