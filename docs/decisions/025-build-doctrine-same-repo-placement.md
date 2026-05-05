# Decision 025 — Build Doctrine same-repo placement

**Date:** 2026-05-05
**Status:** Active
**Stakeholders:** Maintainer (sole)
**Related plan:** `docs/plans/build-doctrine-phase-0-migration.md` (Tranche 0b)
**Related roadmap:** `docs/build-doctrine-roadmap.md`
**Related historical spec:** `~/claude-projects/Build Doctrine/outputs/build-doctrine-plan.md`

## Context

The original Build Doctrine plan (authored before this integration arc started) specified
a **three-repo architecture**:

1. `neural-lace/` — the harness (rules, hooks, agents).
2. `build-doctrine/` — the doctrine layer (universal *shape*: principles, gates,
   processes, autonomy ladder).
3. `build-doctrine-templates/` — the content layer (universal *content*: defaults
   for the universal floors).

The motivation behind the three-repo split was version-pinning: a downstream project could
pin to a specific doctrine version AND a specific templates version independently, allowing
the doctrine layer to evolve at one cadence and the content layer at another. This is the
correct long-term architecture if the system has multiple downstream projects each pinning
different versions.

Tranche 0b (Phase 0 migration) is the moment the doctrine docs land somewhere — the choice
of placement defines the topology going forward. We need to decide whether to keep the
three-repo split as originally specified, or to consolidate.

## Decision

Keep `build-doctrine/` and `build-doctrine-templates/` as **sibling top-level directories
inside the existing `neural-lace` repo**, NOT as separate repos.

The harness, the doctrine layer, and the templates layer all ship in one repo for now.
A future split via `git subtree split` is straightforward when version-pinning need emerges.

## Alternatives Considered

### Alternative A — Three separate repos (the original plan)

`neural-lace/`, `build-doctrine/`, `build-doctrine-templates/` each as its own
git repository. Downstream projects pin to specific versions of each
independently.

**Rejected because:** at current scale (one user, no projects pinning template versions),
separation adds friction without paying for itself. Every change that touches both a hook
in `neural-lace/` and a template in `build-doctrine-templates/` would require two commits
in two repos, two PRs, two reviews. Cross-repo changes that are atomic by intent become
non-atomic by mechanics. The version-pinning benefit is real but unrealized — there is
nothing currently pinning. We pay the cost without earning the benefit.

If/when there are real projects pinning different template versions, splitting via
`git subtree split` is a one-command operation that preserves history and produces a
fresh repo from any subdirectory. The reverse (merging a separate repo back in)
is harder.

### Alternative B — Templates inside the doctrine directory

Keep one new directory (`build-doctrine/`) and put templates as a subdirectory
of the doctrine (`build-doctrine/templates/`).

**Rejected because:** this conflates two distinct layers. The doctrine is the
universal *shape* (content-stable across projects); the templates are the
universal *content* (default values that downstream projects override during
specialization). The three-layer rendering convention is `doctrine + templates +
project-canon`; collapsing doctrine and templates into one directory makes the
content layer harder to update independently and harder to extract later. The
sibling-directory placement preserves the layer split that the original three-repo
plan correctly identified, without paying the multi-repo coordination cost.

### Alternative C — Status quo (defer the decision)

Leave doctrine in the Build Doctrine sibling repo (`~/claude-projects/Build Doctrine/`)
and leave templates unauthored.

**Rejected because:** every later tranche of the integration arc references the
doctrine. If the doctrine docs aren't accessible from inside the harness repo,
every reference is a broken link or a cross-repo lookup. Tranche 0b is the
foundation step that unblocks Tranches 2-7; deferring it would block the entire
arc behind a decision that does not need to wait. The decision is also cheap to
revisit later via `git subtree split` if the consolidation turns out to be wrong.

## Consequences

**Enables:**
- All harness-internal references to doctrine paths resolve cleanly (`build-doctrine/doctrine/01-principles.md` from anywhere in the repo).
- Atomic commits that touch a hook + a doctrine doc + a template land as one PR
  with one review.
- The `definition-on-first-use-gate.sh` scope-prefix can target the in-repo path.
- Tranches 2-7 of the Build Doctrine roadmap can proceed without
  cross-repo coordination overhead.

**Costs:**
- Independent version pinning is unavailable until the split happens (the maintainer
  cannot pin Project Foo to doctrine v1.2 + templates v1.5 while Project Bar pins
  doctrine v1.3 + templates v1.4 — both projects would consume the same harness
  HEAD).
- The harness repo grows by ~38000 words of doctrine content + an empty templates
  scaffold + future template content. This is content (markdown) not code, so
  build size is unaffected; clone size grows modestly.
- Future split (via `git subtree split`) becomes a small piece of one-time work
  if/when pinning matters.

**Reversal cost:** low. `git subtree split --prefix=build-doctrine-templates -b
templates-extracted` extracts the directory into its own branch with full history,
which can then be pushed to a new repo. The same operation works for
`build-doctrine/`. Net: a single command's worth of work, plus updating any in-repo
references to point at the new repos as git submodules or external clones.

## Trigger for revisiting

Revisit this decision when **any** of the following becomes true:

1. Two or more downstream projects begin pinning different template versions.
2. The templates directory grows to a size where the harness repo's clone time
   becomes operationally painful (rough threshold: > 100 MB of templates or >
   10000 files).
3. A maintainer other than the current sole maintainer needs read-but-not-write
   access to templates while having full access to the harness, or vice versa.

Until any of those is true, the same-repo placement is correct.
