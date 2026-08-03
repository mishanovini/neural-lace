# 069 — Should `doctrine/**` enter the review-record surface?

**Date:** 2026-07-30
**Status:** OPEN — awaiting operator decision. No surface change has been landed.
**Tier:** 1 (reversible — the surface is one `case` arm in
`adapters/claude-code/hooks/lib/review-record-gate-lib.sh`; reverting is one line.
Listed here because the operator explicitly reserved this call, not because it is
hard to undo.)

**Every number below was executed on BOTH `/bin/bash 3.2.57` and
`/opt/homebrew/bin/bash 5.3.15`, sequentially, and agreed. Nothing is carried forward
from a draft.** Figures were first taken at `3caaeff` (the branch tip when the
measurement ran) and then **re-executed against the tree this commit lands** (a commit
cannot cite its own SHA, so that tree is identified below by its observable property:
1764 tracked files). Two figures were invalidated by this commit's own 4 files and are
stated post-commit: tracked-file count (1762 → **1764**) and repo-wide 90-day commit count
(1459 → **1460**, 113.5 → **113.6**/wk). Every doctrine figure — 89 files, 69/15/9/54
commits, the pair and co-change counts — is **unchanged**, because this commit touches
no file under `adapters/claude-code/`. The re-execution is the point: a count true one
commit ago is the recurring defect on this branch, including one's own commit.

---

## What this is about (cold-read context)

This repo has a **review-record gate**. Certain files are "in-surface": before a
change to one of them can be pushed to `master`, a `harness-reviewer` agent must have
returned a **PASS** record for that exact file content (keyed by `path` + git
`blob_sha`, stored in `docs/reviews/records/index.json`). The blocking chokepoint is
**pre-push to `master`/`main`** (`review-record-push-gate`, `blocking=true`); the
commit-time gate was demoted to advisory on 2026-07-30.

Today the surface is **hooks, scripts, agents, config, manifest, rules, and the
cockpit product JS**. `adapters/claude-code/doctrine/` — the harness's rule prose,
**89 tracked files** — is **not** in it. Doctrine is the largest un-gated arm, and the
question is whether to add it.

**Doctrine is not inert documentation.** It is the text agents are given as binding
instruction — injected automatically by `doctrine-jit.sh` for some files, and read on
demand (named in `CLAUDE.md` and in individual agent definitions) for others. A false
claim in a doctrine file is a false instruction delivered to every agent that reads it.

### Correction to the premise this task was dispatched with

The dispatch said the surface "was extended today from 283 to 311 files (`git-hooks/*`,
`schemas/*.json`, `install.sh`, `sync.sh`)". **That is not true at the branch tip.**
Executing the real `rrg_in_surface` over all **1764** tracked files at this commit yields
**283 in-surface files**, identical on both interpreters (283 of 1762 at `3caaeff` —
the surface count is unmoved by this commit; only the tracked total grew). Those four arms are absent
from the function. The archived plan
[`docs/plans/archive/deterministic-process-gate-2026-07-30.md`](../plans/archive/deterministic-process-gate-2026-07-30.md)
lists widening the surface to `git-hooks/*` under its OUT-of-scope section, verbatim:
"noted, not fixed in this pass." So the extension was **proposed and deferred, not
landed**, and 311 is not a number that describes anything at HEAD. The only surface
change that did land today was Amendment G (cockpit product code, `39a3dc3`).

This matters for the decision: the baseline is 283, and the marginal cost figures below
are measured against that baseline.

---

## 1. Cost — measured over the real git history

Window: **90 days** (`--since=2026-05-01` through `3caaeff`), `--no-merges`, 12.857 weeks.
Repo-wide activity in that window: **1460 commits** (113.6/wk), counted inclusive of
this commit.

| Measure | Commits (90d) | Per week |
|---|---:|---:|
| Commits touching `doctrine/**` at all | **69** | 5.36 |
| …touching **ONLY** `doctrine/**` (no other path whatsoever) | **9** | 0.70 |
| …touching doctrine **and no already-in-surface file** | **15** | **1.16** |
| …that already require a record today (contain an in-surface file) | **54** | 4.20 |

**The honest cost is two different things, and they should not be added together:**

- **New review round-trips: +1.16 commits/week.** These 15 commits require **zero**
  review today and would require a `harness-reviewer` PASS before pushing to master.
  This is the real added friction — a new blocking dependency where none exists.
- **Widened existing reviews: 4.20 commits/week.** These 54 already produce a record.
  Adding doctrine does **not** add a round-trip; it widens the diff the reviewer reads.

**Why 15 and not 9.** The dispatch asked for "commits touching ONLY doctrine" as the
pure added friction. That undercounts. Records are keyed per **file**, so a commit
touching doctrine plus `docs/backlog.md` (not in-surface) still gets no record today and
would newly need one. 9 is the ONLY-doctrine count; **15** is the count that actually
gains a blocking dependency. Use 15.

Supporting figure: **188 distinct `(path, blob_sha)` doctrine pairs** changed in the
window across **89 distinct paths** — the volume of file-content that would need
coverage, most of it riding inside reviews that already happen.

---

## 2. The compact/`-full` pairs — the friction discount is smaller than assumed

The premise was that pairs mean "one review covers two files." Measured:

- **34** `-full.md` files; **32** have a compact sibling (**32 pairs = 64 files**);
  **2** orphan `-full` with no compact; **23** unpaired singletons. (32×2 + 2 + 23 = 89.)

But **pairs do not reliably co-change**. Of **83** commits in the window touching either
member of a pair:

| | Commits | Share |
|---|---:|---:|
| Both members changed together | 48 | **57%** |
| Compact changed **alone** | 27 | 33% |
| `-full` changed **alone** | 8 | 10% |

**43% of pair-touching commits change one member alone.** So the "one review covers two
files" discount applies to a bare majority of cases, not to the file count as a whole.

More importantly, **this divergence is itself the harm mechanism**, not just a costing
detail — see incident 1 below, which is precisely a `-full`-only correction leaving the
compact carrying the retracted claim.

---

## 3. Harm — what is actually being prevented

Doctrine is effectively unreviewed today: of **293** entries in
`docs/reviews/records/index.json`, exactly **3** cover a doctrine path
(`intended-functionality.md`, `review-before-deploy.md`, `review-before-deploy-full.md`),
and those were voluntary — doctrine is not in the surface, so nothing required them.

### Incident 1 — PROVEN. `orchestrator-pattern.md` shipped a retracted false claim

The compact carried *"a header QUOTED further down … is inert rather than emitting a
false green."* That claim was **false and known to be false**: a quoted header inside the
first 5 joined lines does fire a false green.

- `1394fe8` (17:47:58) corrected **`orchestrator-pattern-full.md` only**.
- `b24f4ff` (18:39:48) corrected **the compact** — **~52 minutes later**.

For that window the corrected `-full` sat beside a compact still carrying the retraction,
which is the 43%-divergence statistic above expressed as a live defect.

**One correction to the dispatch's framing, which matters for option C.** The dispatch
called this "the JIT-delivered compact." It is **not** JIT-delivered. Manifest entry
`orchestrator-pattern` has `jit_triggers.paths: []`, and `doctrine-jit.sh:229` skips any
entry with empty paths outright. **Behaviourally verified, not grepped:** executing the
real hook against the real manifest across **all 81 distinct trigger patterns**,
`orchestrator-pattern` was injected **0 times** — on both interpreters, with a passing
control (`docs/plans/` does inject, proving the probe harness was live). The commit
message of `b24f4ff` asserts `doctrine-jit.sh` "resolves THAT, so agents were being served
the false version"; the resolution half of that is wrong.

The **harm is still real** — `orchestrator-pattern.md` is named as required reading by
`CLAUDE.md` and by four agent definitions (`plan-phase-builder`, `harness-reviewer`,
`systems-designer`, `end-user-advocate`), so agents do read it. The delivery path is
agent-prompt reference, not JIT injection.

### Incident 2 — PROVEN. `deterministic-process.md` shipped a false *enforcement* claim

`e91cdfa` introduced the file with the header: *"`manifest.json` carries `chokepoint` +
`bypass_paths` on every `blocking: true` unit; `harness-doctor.sh` REDs on one declaring
neither."* **All three halves were false** — 39 blocking units, **0** carrying
`chokepoint`; the named doctor check has 0 occurrences; and `manifest.schema.json` is
`additionalProperties: false`, so it would have *rejected* both keys. `b815b00` retracted
it hours later, after a **builder** — not a gate — caught it.

**Both `e91cdfa` and `b815b00` touch only doctrine + `docs/backlog.md`, so both are in the
15-commit zero-review set.** A doctrine review record is exactly the control that was
missing. This is the strongest single datum in this document: the file whose entire thesis
is *"unbuilt enforcement claims are the cardinal defect"* shipped an unbuilt enforcement
claim, with no review, because doctrine is out of surface.

### Incident 3 — content deleted from a delivered compact, unreviewed (partly hypothesized)

**PROVEN:** `6fc33cf` ("trim … under the 3000B compact cap") shrank
`orchestrator-pattern.md` from 3451 → 2730 bytes (+10/−11 lines) and **did not touch
`orchestrator-pattern-full.md`** — verified by `--numstat`, which lists only the compact.
Roughly 700 bytes left the delivered file without being relocated to its companion.
`2c74fe8` ("fix-trivial: 5 doctrine compacts back under the cap") rewrote **five**
delivered compacts in one commit — `diagnosis.md` −112 lines, `evidence-before-fix.md`
−180 lines, plus `gh-merge-canonical.md`, `model-selection.md`, `review-before-deploy.md`.

**HYPOTHESIZED:** that some of the removed prose was load-bearing instruction rather than
redundancy. **Refuted by** reading the deleted hunks and finding each either preserved in
the `-full` sibling or genuinely redundant. I did not do that reading, so I am not
claiming harm here — only that the highest-volume rewrites of agent-facing instruction in
the window were labelled "fix-trivial"/"trim" and landed with zero review.

**This kills the obvious cost-saving exemption.** 7 of the 15 zero-review commits are
cap-trims or `INDEX.md` regeneration and look mechanical enough to exempt. They are in
fact the commits that **rewrite the delivered compacts most aggressively**. An exemption
for "mechanical" doctrine commits would exempt exactly the wrong ones.

---

## 4. Options

Cost = **new review round-trips per week** (commits that today need no review at all).
"Catches 1 / 2" = whether the option's file set contains the incident files above.

| Option | Files gated | New round-trips/wk | Catches inc. 1 | Catches inc. 2 |
|---|---:|---:|:--:|:--:|
| **A — status quo**, doctrine stays out | 0 | **0** | ✗ | ✗ |
| **B — all `doctrine/**`** | 89 | **1.16** | ✓ | ✓ |
| **C — JIT-injectable compacts only** | 23 | **0.70** | **✗** | **✗** |
| **C+ — those 23 + their `-full`** | 38 | 0.70 | ✗ | ✗ |
| **D — JIT + `CLAUDE.md`-named compacts** | 29 | 0.85 | ✓ | ✗ |
| **E — compacts carrying an `Enforcement:` header** | 54 | 1.01 | ✓ | ✓ |

### Option C — the cheaper control the dispatch asked me to consider — does not work

The dispatch proposed gating only the JIT-delivered compacts, "since those are the ones
agents actually read." **Measured: 23 files** (manifest entries with a non-empty
`jit_triggers.paths` and a non-null `doctrine_file`), costing 0.70 round-trips/week.

**But it misses BOTH proven incidents.** `orchestrator-pattern` has empty
`jit_triggers.paths` (behaviourally confirmed: 0 injections across 81 patterns), and
`deterministic-process.md` has **no manifest entry at all**. The premise that JIT
delivery ≈ "what agents actually read" is false: agents also read doctrine named in
`CLAUDE.md` and in their own agent definitions, and that path carried both incidents.

Saving 0.46 round-trips/week — **one review every ~2.2 weeks** — while catching zero of
two known incidents is not a cheaper control; it is a control that does not address the
harm. **Recommend against C and C+.**

### Option E — the plausible runner-up

Gating the 54 compacts that carry an `Enforcement:` header line targets the claim-bearing
surface where both incidents live, and covers both. But it costs 1.01/wk versus B's
1.16/wk — **0.15/wk apart, about one extra review every 7 weeks** — and it makes the
surface **content-dependent**: a file silently enters or leaves the gate when someone
edits a header line. Every other arm of this surface is a stable path glob. A moving,
content-derived surface is harder to verify and is itself a drift risk. The 13% saving
does not buy that complexity.

---

## Recommendation

**Option B — add `doctrine/**` to the review-record surface.**

Reason: it is the only option that covers both proven incidents, it costs **+1.16 new
review round-trips per week** (against 113.6 commits/wk of repo activity — about 1% of
commits gaining a blocking dependency), and it is **one `case` arm** consistent with how
every other arm of this surface is defined. Options C/C+ are measurably cheaper but catch
neither incident. Option E covers both but saves only ~1 review every 7 weeks in exchange
for a content-dependent surface.

Second recommendation, independent of the above: **do not exempt "mechanical" doctrine
commits** (cap trims, `INDEX.md` regeneration), even though they are 7 of the 15. Section 3
shows they are the commits that rewrite delivered agent instruction most heavily.

**Honest residual:** I have not measured the *cost of a review round-trip* (wall-clock or
token). 1.16/week is a count, not a duration. If a `harness-reviewer` pass on a doctrine
diff is slow, B's cost is higher than this document can show, and E's 13% saving becomes
proportionally more attractive. Nothing here measures reviewer quality either — a PASS
record is evidence a review happened, not that it was good.

---

## What would change this recommendation

- If a review round-trip turns out to be expensive in wall-clock terms, C's cheapness
  starts to matter and the framing shifts to "which 23 files are worth the cost."
- If `jit_triggers.paths` were backfilled so the genuinely high-traffic compacts
  (including `orchestrator-pattern`) are actually JIT-injected, option C would become
  coherent — today it is not, because the field is empty on the files that matter.
- If a third incident lands in a doctrine file with no `Enforcement:` header, E weakens
  further and B becomes the only defensible option.

## How this was measured

Scripts executed at `3caaeff` on both interpreters; all agreed. Surface counts execute the
real `rrg_in_surface` from
[`adapters/claude-code/hooks/lib/review-record-gate-lib.sh`](../../adapters/claude-code/hooks/lib/review-record-gate-lib.sh)
rather than reimplementing the globs. The JIT finding executes the real
[`adapters/claude-code/hooks/doctrine-jit.sh`](../../adapters/claude-code/hooks/doctrine-jit.sh)
against the real `manifest.json` with a control assertion that fails loudly if the probe
harness is dead — the first version of that probe reported a false "0 hits" because the
payload omitted `tool_name`, and the control is what caught it.

**No surface change was landed by this work.** This document is the deliverable.
