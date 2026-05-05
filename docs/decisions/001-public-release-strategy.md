# Decision 001: Fresh orphan-commit for public release

**Date:** 2026-04-18
**Status:** Active
**Tier:** 3 (irreversible once public)
**Stakeholders:** Maintainer

## Context

The Neural Lace harness repo at `<personal-account>/neural-lace` (currently private) contains 27 commits with pervasive personal + business identifiers (personal name, work-org account, work-org codename, product codenames, cloud-storage paths, a test password fallback). The maintainer wants to publish Neural Lace publicly. A pre-publish security audit confirmed zero credentials leak, but substantial identity + business footprint that would be permanent and searchable once public.

## Decision

Publish via a **fresh orphan commit** to a new public repo:

1. Scrub the current working tree in place on a feature branch
2. Archive the current private `<personal-account>/neural-lace` → rename to `<personal-account>/neural-lace-archive` (stays private)
3. Create a new public `<personal-account>/neural-lace` repo from a single orphan commit of the cleaned tree
4. Force-push the same clean tree to `<work-org-codename>/neural-lace` remote (stays private, active for work mirror)

## Alternatives Considered

- **`git filter-repo` + force-push to existing remotes** — rewrites history across all 27 commits. Rejected: risk of missed string in any of 27 historical diffs; force-push on a shared private remote; history still exists in refs/reflog for some time.
- **Accept current history as-is** — flip visibility with existing commits. Rejected: permanently leaks all 30+ identifier occurrences; search indexers would pick up work-org folder structure, product codenames, etc.

## Consequences

- **Enables:** zero-leak public release; simpler verification (just grep the single new commit); archived history preserved for internal reference.
- **Costs:** loss of contributor history in the public view; outside contributors see Neural Lace as "new" rather than "migrated"; the archive repo must be kept private forever.
- **Blocks:** nothing material.

## Implementation reference

Phase 8 of `docs/plans/public-release-hardening.md`.
