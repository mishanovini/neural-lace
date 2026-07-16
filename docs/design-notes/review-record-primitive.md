# Design: the review-record primitive

Batch task 1 of `docs/plans/harness-governance-batch-2026-07-15.md`. Feeds tasks 2
(review-before-deploy gate), 3 (evidence-before-fix commit gate), and 4 (pt's
`artifact-evidence-bar` integration). MUST pass `architecture-reviewer` (design-shape
review) before any builder is dispatched against tasks 2-4 — this doc is that review's
input, not a build spec to execute directly.

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

## Trigger surface + fp expectation

**Recommended surface, derived from the manifest itself rather than a hand-maintained
glob list:** every file named in any `manifest.json` entry's `hooks[]` array, **plus**
`agents/*.md`, `config/**`, `manifest.json` itself, `settings.json.template`, and
`rules/**`. Tying the surface to the manifest's own `hooks[]` union means a new gate
that registers itself is automatically in-surface without a second place to remember to
update it.

**Explicitly excluded:** `doctrine/**`, `templates/**`, `skills/**`, `commands/**`,
`examples/**`, `patterns/**`, `business-patterns*`, `data/**`, `work-shapes/**`,
`pipeline-*/**` — these are documentation/content surfaces whose failure mode is "a
maintainer reads something wrong," not "every machine's enforcement silently changes."

**Named residual, not silently dropped:** `scripts/*.sh` invoked *by* hooks or by
orchestrator-run procedures (`write-evidence.sh`, `close-plan.sh`,
`plan-lifecycle.sh`) have hook-equivalent blast radius but are **not** in a
`manifest.json` `hooks[]` array today, so this surface excludes them — flagged as
Open Question 1, not resolved unilaterally (a scope call with real fp cost).

**fp_expectation: low-moderate.** A pure-prose doctrine/rules-content edit is scoped
out entirely. The one deliberate over-inclusion: an `agents/*.md` wording-only edit
still requires a PASS, because an agent's prompt *is* its enforcement logic and there
is no cheap way to distinguish cosmetic from behavioral prose edits — trading rare
friction on cosmetic-only edits for never missing a behavioral one dressed as cosmetic.

## Writer + anti-fabrication residual

**Neither `harness-reviewer` nor `architecture-reviewer` can write the record** — both
are `tools: Read, Grep, Glob, Bash`, no Write/Edit (verified against
`adapters/claude-code/agents/harness-reviewer.md`). A new
`write-review-record.sh` (mirrors `write-evidence.sh`'s shape: `capture --kind <k>
--reviewer <agent> --verdict <v> --plan-ref <ref> --file <path>...`) is invoked by the
**orchestrating session**, not the reviewer, after the reviewer returns its verdict.
The script computes each file's live `blob_sha` via `git hash-object` (or
`git ls-tree`), and requires a non-empty `dispatch_evidence.verdict_quote`.

**Honest residual (not solved, named):** the orchestrator is an LLM and can fabricate
`dispatch_evidence.verdict_quote` — paste a plausible PASS no reviewer actually said.
Same trust gap `plan-evidence-reviewer` already exists to police for ordinary evidence
blocks; not a new hole, and this design does not claim to close it. Two mitigations,
both raising cost rather than eliminating the gap: (1) `verdict_quote` must be a
**verbatim substring of the reviewer agent's actual returned message**, not a
paraphrase; (2) `plan-evidence-reviewer` is extended to spot-check review records the
same way it spot-checks evidence blocks: re-derive `covered_files` blob SHAs against
the live repo, and grep the session transcript for the quoted string where available.
Not full prevention — a fabrication that also fakes a transcript reference survives.

## Verdict lifecycle

`PASS` → consumed by the relevant consumer gate as "this exact content is cleared."
`REFORMULATE` → reviewer wants a specific change; blocks like absence; the orchestrator
re-dispatches on the revised diff, producing a new record. `REJECT` → reviewer rejects
the direction; blocks like absence; no automatic escalation is built into this design
(see Open Question 3). Re-review is simply "run the same dispatch-then-write flow
again" — there is no separate "invalidate the old record" step because content-
addressing already makes the old record inapplicable to changed content.

## Consumer contracts

**1. Review-before-deploy gate (task 2).** At `install.sh` / `session-start-
auto-install.sh` sync time, for every file in the trigger surface whose live
`blob_sha` differs from what's already installed at the target, scan
`docs/reviews/records/*.json` for a `kind: harness-change-review` record with
`verdict: PASS` whose `covered_files` includes that exact `{path, blob_sha}`. Missing
→ block that file's sync (not the whole deploy, where separable) and name the specific
uncovered file + its blob_sha.

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

## Location + format

`docs/reviews/records/<yyyy-mm-dd>-<kind>-<short-id>.json`, **committed** (not
gitignored, not `.claude/state/`) — forced by the deploy gate's own mechanism:
`session-start-auto-install.sh` reads canonical content via `git show
origin/master:<path>` on every machine, so anything not committed and merged to master
is invisible to the check on every machine but the one that wrote it. A derived local
index/cache under `.claude/state/` is fine as a rebuildable convenience, never the
source of truth.

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

## Open questions for the architecture reviewer

1. **Trigger-surface scope:** should `scripts/*.sh` invoked by hooks/orchestrator
   procedures (`write-evidence.sh`, `close-plan.sh`, `plan-lifecycle.sh`) be added to
   the trigger surface despite not appearing in any `manifest.json` `hooks[]` array?
   They have hook-equivalent blast radius.
2. **Anti-fabrication bar:** is quoted-verbatim-substring + `plan-evidence-reviewer`
   spot-check sufficient given the residual is explicitly unsolved, or does "gates every
   harness deploy on every machine" warrant a stronger control (e.g. requiring a
   retrievable session/transcript reference the spot-check can independently fetch,
   not just grep)?
3. **REJECT escalation:** should repeated REJECTs on the same file set (e.g. 2
   consecutive) require operator sign-off, or is "blocks until a materially different
   diff earns PASS" sufficient?
4. **Revert-silently-revalidates:** content-addressing means a file reverted to a
   previously-PASS'd blob_sha is silently covered again by the old record, with no new
   review. Acceptable, or should records also carry a TTL independent of content match?
5. **Retention:** `docs/reviews/records/` accumulates one file per review forever — is
   unbounded accumulation acceptable given it is the audit trail the append-only
   anti-fabrication property depends on, or does this need a pruning/archival policy?
