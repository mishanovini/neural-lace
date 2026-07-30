# Fragment: review-independence — the merge-time integration contract for estate-merge.sh

`docs/plans/review-independence.md` RI3. The accountable-estate program's merge lock
(`estate-merge.sh`, live-in-progress per this session's dispatch constraints — this
fragment does NOT edit that file, the same discipline the roadmap fragments in this
directory already establish for concurrent same-phase builders) is the natural place
to enforce review-independence's guarantee AT MERGE TIME, not just at commit time.
This is a read-only handoff: the estate-merge builder applies the check described
below to their own script when they land it; review-independence does not.

## Why this belongs at merge time, not only commit time

`review-record-commit-gate.sh` (V6, `docs/plans/verification-dispatch-directive.md`)
blocks a LOCAL `git commit` of uncovered in-surface content. It has no visibility
into what happens after that commit is pushed and merged into a protected target
(`master`, or whatever branch `estate-merge.sh` treats as the integration target) —
a commit that was allowed through via `REVIEW_RECORD_GATE_OVERRIDE` (the gate's own
documented self-waiver escape hatch), or one made outside a harnessed session
entirely (another machine, CI, a GitHub-web-UI merge), reaches the commit-time gate's
blind spot exactly the way `doctrine/review-before-deploy.md`'s own "What this gate
does NOT catch" section already names for the deploy-time carriers. Merge time is the
last deterministic checkpoint before content becomes part of the protected target's
history.

## The contract

**Merge into a protected target requires BOTH of the following, computed over every
file the merge would introduce or change that matches `rrg_in_surface`
(`adapters/claude-code/hooks/lib/review-record-gate-lib.sh`):**

1. **All in-surface records present.** For every `{path, blob_sha}` the merge would
   land, a `kind: harness-change-review`, `verdict: PASS` row must exist in
   `docs/reviews/records/index.json` (or the content must be covered by
   `grandfather-manifest.json` — Amendment E, pre-cutover content). This is the
   SAME predicate `rrg_is_covered` already computes for the commit-time gate;
   `estate-merge.sh` can call it directly
   (`source hooks/lib/review-record-gate-lib.sh; rrg_is_covered "$repo_root" "$ref"
   "$path" "$blob_sha"`) rather than reimplementing it.

2. **Author ≠ reviewer, for CONSTITUTION-TIER paths specifically.** For any in-surface
   file under `rules/**`, `manifest.json`, or `settings.json.template` (the
   highest-leverage behavior surfaces — the ones a bad merge could use to weaken
   its OWN enforcement), the covering PASS record's introducing commit must have a
   DIFFERENT git author than the commit that introduced the reviewed content. This
   is the exact predicate `harness-doctor.sh`'s `check_review_reviewer_independence`
   already computes (RI3, this plan) — reusable directly:

   ```
   reviewed_author=$(git -C "$repo_root" log -1 --format=%ae "$reviewed_commit_sha")
   record_author=$(git -C "$repo_root" log --diff-filter=A --format=%ae -- "$record_relpath" | tail -n 1)
   [[ "$reviewed_author" == "$record_author" ]] && REFUSE
   ```

   For in-surface files OUTSIDE the constitution tier (an ordinary `hooks/*.sh` or
   `scripts/*.sh` edit), requirement 1 alone (a PASS record exists at all) is
   sufficient at merge time — the commit-time gate plus this program's own review
   pipeline is the enforcement point for those; the merge-time author≠reviewer check
   is reserved for the highest-blast-radius paths specifically, mirroring
   `check_review_reviewer_independence`'s own WARN-vs-RED asymmetry (see plan RI3:
   the doctor REDs unconditionally on self-approval for ANY `harness-change-review`
   PASS record — this fragment's requirement 2 narrows that to constitution-tier
   paths ONLY at merge time, since a merge lock's false-positive cost is higher than
   a doctor RED's advisory one).

## What this fragment does NOT ask estate-merge.sh to build

- No new review-record schema, no new doctor check, no new queue mechanism — RI1-RI3
  of `docs/plans/review-independence.md` already ship all of that. This fragment is
  purely "call the existing predicates at your own merge checkpoint."
- No opinion on WHERE in `estate-merge.sh`'s own verify → merge → worktree-remove
  sequence (per `close-worktree.sh`'s header comment, which already names
  `estate-merge.sh`'s "merge lock + single deterministic merge script" as
  not-yet-built at the time that file was written) this check should be spliced —
  that is the estate-merge builder's own architectural call, informed by their
  script's actual structure, which this session has not read.

## Verification (for whoever applies this fragment)

- A fixture merge that introduces an uncovered `rules/*.md` change → refused, naming
  the specific uncovered `{path, blob_sha}`.
- A fixture merge that introduces a `rules/*.md` change covered by a PASS record
  whose introducing commit shares the SAME git author as the reviewed commit →
  refused, naming the self-approval.
- A fixture merge that introduces a `rules/*.md` change covered by a PASS record
  with a genuinely different author → allowed.
- A fixture merge that introduces an ordinary `hooks/*.sh` change covered by ANY
  PASS record (same or different author) → allowed (requirement 2 does not apply
  outside the constitution tier).
